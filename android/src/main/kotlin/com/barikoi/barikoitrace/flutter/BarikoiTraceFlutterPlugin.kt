package com.barikoi.barikoitrace.flutter

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import com.barikoi.barikoitrace.BarikoiTrace
import com.barikoi.barikoitrace.LocTraceManager
import com.barikoi.barikoitrace.TraceConfig
import com.barikoi.barikoitrace.TraceMode
import com.barikoi.barikoitrace.model.TraceError
import com.barikoi.barikoitrace.model.TraceException
import com.barikoi.barikoitrace.model.TraceUser
import com.barikoi.barikoitrace.util.SystemSettingsManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.yield
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Android implementation of the `barikoi_trace_flutter` platform interface.
 *
 * Bridges one method channel and two event channels onto the
 * `com.github.barikoi:barikoitrace` SDK, exactly as specified in
 * `docs/WIRE_CONTRACT.md`. Read that document before changing anything here:
 * method-name strings, argument keys, result shapes and error codes are all
 * part of the contract the Dart layer is already written against.
 *
 * Shape of the implementation:
 *
 *  - Every handler runs on [scope], a `Dispatchers.Main.immediate` scope, so
 *    `MethodChannel.Result` is always answered on the platform thread (§6.3).
 *  - Blocking and `suspend` SDK calls are moved to `Dispatchers.IO` by [io].
 *    The SDK's facade is `suspend` but does not pick a dispatcher of its own,
 *    and several of its "getters" read an encrypted DataStore — running those
 *    inline on the main thread is how you get an ANR under a slow disk.
 *  - Exactly one `try` wraps every handler, in [onMethodCall], and it is the
 *    only place a native throwable becomes a channel error.
 */
class BarikoiTraceFlutterPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private var methodChannel: MethodChannel? = null
    private var locationEventChannel: EventChannel? = null
    private var logEventChannel: EventChannel? = null

    private var applicationContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var activity: Activity? = null

    private var scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var locationStreamHandler: LocationStreamHandler? = null
    private var logStreamHandler: LogStreamHandler? = null

    private val pendingPermissions = PendingPermissionRequests()

    /**
     * Serializes `initialize` against itself and against the first
     * `setOrCreateUser`. See [handleInitialize].
     */
    private val initializeMutex = Mutex()

    /** `SystemClock.elapsedRealtime()` of the last `initialize`, or 0. */
    @Volatile
    private var initializedAtMs: Long = 0L

    // ------------------------------------------------------------------
    // FlutterPlugin
    // ------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

        val logs = LogStreamHandler()
        val locations = LocationStreamHandler(scope)
        logStreamHandler = logs
        locationStreamHandler = locations

        methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL_METHODS).apply {
            setMethodCallHandler(this@BarikoiTraceFlutterPlugin)
        }
        locationEventChannel = EventChannel(binding.binaryMessenger, CHANNEL_LOCATION_UPDATES).apply {
            setStreamHandler(locations)
        }
        logEventChannel = EventChannel(binding.binaryMessenger, CHANNEL_LOGS).apply {
            setStreamHandler(logs)
        }

        // Installed before any initialize() can run, so the config warnings the
        // SDK logs from inside initialize() land in the log handler's replay
        // buffer instead of being dropped (WIRE_CONTRACT §3.1, §7.2).
        BarikoiTrace.setLogListener(logs)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        BarikoiTrace.setLogListener(null)

        methodChannel?.setMethodCallHandler(null)
        locationEventChannel?.setStreamHandler(null)
        logEventChannel?.setStreamHandler(null)
        methodChannel = null
        locationEventChannel = null
        logEventChannel = null

        locationStreamHandler?.dispose()
        logStreamHandler?.dispose()
        locationStreamHandler = null
        logStreamHandler = null

        // Anything still waiting on a permission prompt gets the current state
        // rather than being abandoned.
        resolveAllPendingWithCurrentState()

        scope.cancel()
        applicationContext = null
    }

    // ------------------------------------------------------------------
    // ActivityAware
    // ------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachActivity(binding)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        // Pending requests are deliberately kept across a configuration change:
        // the system permission dialog survives the recreation and delivers its
        // result to the new Activity, which this listener is re-registered on.
        attachActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity(resolvePending = false)
    }

    override fun onDetachedFromActivity() {
        // A real detach — no callback is coming. Answer every waiter with the
        // state as it stands so no Dart future is left hanging (§6.3).
        detachActivity(resolvePending = true)
    }

    private fun attachActivity(binding: ActivityPluginBinding) {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = binding
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    private fun detachActivity(resolvePending: Boolean) {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        if (resolvePending) resolveAllPendingWithCurrentState()
    }

    // ------------------------------------------------------------------
    // Permission results
    // ------------------------------------------------------------------

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (!isOwnRequestCode(requestCode)) return false

        val waiters = pendingPermissions.takeAll(requestCode)
        if (waiters.isEmpty()) return false

        // The live permission state, not grantResults: it is what the contract
        // actually promises ("whether the permission is now granted"), and it is
        // correct even when the dialog was dismissed without a decision or the
        // user flipped the permission in Settings while the app was backgrounded.
        val granted = currentStateFor(requestCode)
        for (waiter in waiters) waiter.resolve(granted)
        return true
    }

    private fun resolveAllPendingWithCurrentState() {
        for (waiter in pendingPermissions.takeEverything()) {
            waiter.resolve(currentStateFor(waiter.requestCode))
        }
    }

    private fun currentStateFor(requestCode: Int): Boolean {
        val context = applicationContext ?: return false
        return when (requestCode) {
            REQUEST_CODE_LOCATION -> SystemSettingsManager.checkPermissions(context)
            REQUEST_CODE_BACKGROUND_LOCATION ->
                SystemSettingsManager.checkBackgroundLocationPermission(context)
            REQUEST_CODE_NOTIFICATION -> isNotificationPermissionGranted(context)
            else -> false
        }
    }

    private fun isOwnRequestCode(requestCode: Int): Boolean =
        requestCode == REQUEST_CODE_LOCATION ||
            requestCode == REQUEST_CODE_BACKGROUND_LOCATION ||
            requestCode == REQUEST_CODE_NOTIFICATION

    // ------------------------------------------------------------------
    // MethodCallHandler
    // ------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val once = ResultOnce(result)

        if (call.method !in SUPPORTED_METHODS) {
            // Includes `ios.setLocationDisabledNotificationEnabled`, which the
            // Dart layer already short-circuits on Android (§3).
            once.notImplemented()
            return
        }

        scope.launch {
            try {
                dispatch(call, once)
            } catch (e: PluginException) {
                once.error(e.code, e.message ?: "", null)
            } catch (e: TraceException) {
                // The SDK's own stable codes, passed through verbatim (§6.1).
                once.error(e.error.code, e.error.message, null)
            } catch (e: CancellationException) {
                // MUST be caught before IllegalStateException:
                // kotlinx.coroutines.CancellationException is a typealias for
                // java.util.concurrent.CancellationException, which extends
                // IllegalStateException — so the NOT_INITIALIZED branch below
                // would otherwise swallow every cancellation and answer the
                // channel with a wrong, and very confusing, error code.
                //
                // The scope was cancelled: the engine is detaching and the
                // channel is already gone. Rethrow so structured concurrency
                // stays intact; there is nobody left to answer.
                throw e
            } catch (e: IllegalStateException) {
                // What BarikoiTrace.getInstance() throws before initialize().
                once.error(
                    CODE_NOT_INITIALIZED,
                    e.message ?: "BarikoiTrace is not initialized. Call initialize() first.",
                    null
                )
            } catch (e: Throwable) {
                once.error(CODE_INTERNAL, e.toString(), null)
            }
        }
    }

    private suspend fun dispatch(call: MethodCall, result: ResultOnce) {
        if (call.method != METHOD_INITIALIZE) assertInitialized()

        when (call.method) {

            // --- Initialization & configuration (§3.1) ---

            METHOD_INITIALIZE -> {
                handleInitialize(Codecs.asWireMap(call.arguments))
                result.success(null)
            }

            "setBaseUrl" -> {
                BarikoiTrace.setBaseUrl(requireStringArg(call, "url"))
                result.success(null)
            }

            "setMqttUrl" -> {
                BarikoiTrace.setMqttUrl(requireStringArg(call, "url"))
                result.success(null)
            }

            "setMqttClientIdPrefix" -> {
                BarikoiTrace.setMqttClientIdPrefix(requireStringArg(call, "prefix"))
                result.success(null)
            }

            "resetUrls" -> {
                BarikoiTrace.resetUrls()
                result.success(null)
            }

            // --- User (§3.2) ---

            "setOrCreateUser" -> {
                val user = setOrCreateUser(
                    name = call.argument<String>("name"),
                    email = call.argument<String>("email"),
                    phone = requireStringArg(call, "phone")
                )
                result.success(Codecs.encodeUser(user))
            }

            "getUser" -> {
                val user: TraceUser? = io { BarikoiTrace.getUser() }
                result.success(user?.let { Codecs.encodeUser(it) })
            }

            "getUserId" -> {
                result.success(io { BarikoiTrace.getUserId() })
            }

            // --- Permissions & settings (§3.3) ---

            "isLocationPermissionsGranted" -> {
                result.success(BarikoiTrace.isLocationPermissionsGranted())
            }

            "isLocationSettingsOn" -> {
                result.success(BarikoiTrace.isLocationSettingsOn())
            }

            "hasBackgroundPermission" -> {
                result.success(
                    SystemSettingsManager.checkBackgroundLocationPermission(requireContext())
                )
            }

            "requestLocationPermissions" -> {
                result.success(requestForegroundLocationPermission())
            }

            "requestBackgroundLocationPermission" -> {
                result.success(requestBackgroundLocationPermission())
            }

            "openLocationSettings" -> {
                result.success(openLocationSettings())
            }

            "openAppSettings" -> {
                result.success(openAppSettings())
            }

            "isBackgroundTrackingDegraded" -> {
                result.success(isBackgroundTrackingDegraded())
            }

            // --- Tracking (§3.4) ---

            "setTraceMode" -> {
                BarikoiTrace.setTraceMode(Codecs.decodeMode(call.argument<Any>("mode")))
                result.success(null)
            }

            "startTracking" -> {
                startTracking(
                    mode = Codecs.decodeMode(call.argument<Any>("mode")),
                    withTrip = Codecs.asBool(call.argument<Any>("withTrip"), false)
                )
                result.success(null)
            }

            "stopTracking" -> {
                BarikoiTrace.stopTracking()
                result.success(null)
            }

            "refreshTracking" -> {
                // Not on the Kotlin facade — only LocTraceManager has it. It
                // bounces the foreground service so the current TraceMode is
                // re-applied to a running session. Off the main thread: it
                // reads the tracking flag and the stored mode synchronously.
                val manager = LocTraceManager.getInstance(requireContext())
                io { manager.refreshTracking() }
                result.success(null)
            }

            "isLocationTracking" -> {
                result.success(io { BarikoiTrace.isLocationTracking() })
            }

            "setOfflineTracking" -> {
                BarikoiTrace.setOfflineTracking(requireBoolArg(call, "enabled"))
                result.success(null)
            }

            "setLoggingEnabled" -> {
                BarikoiTrace.setLoggingEnabled(requireBoolArg(call, "enabled"))
                result.success(null)
            }

            "setBroadcastingEnabled" -> {
                BarikoiTrace.setBroadcastingEnabled(requireBoolArg(call, "enabled"))
                result.success(null)
            }

            // --- Trips (§3.5) ---

            "isOnTrip" -> {
                result.success(io { BarikoiTrace.isOnTrip() })
            }

            "getTripId" -> {
                result.success(io { BarikoiTrace.getTripId() })
            }

            // --- Location (§3.6) ---

            "updateCurrentLocation" -> {
                result.success(Codecs.encodeLocation(updateCurrentLocation()))
            }

            "uploadOfflineData" -> {
                // Fire and forget: the SDK only bounces the service, which makes
                // the MQTT client reconnect and flush the offline queue. It does
                // not wait for the flush, so this returns as soon as the restart
                // is scheduled (§3.6).
                io { BarikoiTrace.uploadOfflineData() }
                result.success(null)
            }

            "getSettingsFromRemote" -> {
                val mode: TraceMode = io { BarikoiTrace.getSettingsFromRemote() }
                result.success(Codecs.encodeMode(mode))
            }

            // --- Android-only (§3.7) ---

            "android.requestNotificationPermission" -> {
                result.success(requestNotificationPermission())
            }

            "android.requestDisableBatteryOptimization" -> {
                requestDisableBatteryOptimization(
                    onlyIfNeeded = Codecs.asBool(call.argument<Any>("onlyIfNeeded"), false)
                )
                result.success(null)
            }

            "android.isIgnoringBatteryOptimizations" -> {
                // Positive polarity, and no inversion: despite its name, the
                // SDK's isBatteryOptimizationEnabled() forwards to
                // LocTraceManager.checkIgnoringBatteryOptimization(), which is
                // SystemSettingsManager.isIgnoringBatteryOptimization() —
                // PowerManager.isIgnoringBatteryOptimizations(packageName).
                // It already returns "true means exempt", the Dart meaning.
                result.success(BarikoiTrace.isBatteryOptimizationEnabled())
            }

            "android.openAutostartSettings" -> {
                BarikoiTrace.openAutostartSettings(requireActivity())
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------------
    // Initialization
    // ------------------------------------------------------------------

    /**
     * Configures the SDK, and then waits long enough for the configuration to
     * actually be in place.
     *
     * `LocTraceManager.initialize` logs the config warnings synchronously (which
     * is what puts them on the log channel), then hands everything else —
     * writing the API key and the broker credentials into the encrypted store —
     * to `scope.launch` on `Dispatchers.IO` and returns immediately. A Dart
     * caller that does the natural thing:
     *
     * ```dart
     * await BarikoiTrace.initialize(config);
     * await BarikoiTrace.setOrCreateUser(phone: '01…');
     * ```
     *
     * would otherwise race that write, and `setOrCreateUser` starts with
     * `if (dataStore.getApiKey().isNullOrBlank()) throw NO_KEY`. So: yield to
     * let the launched coroutine start, then give the disk write a short
     * settling window. [setOrCreateUser] retries once on NO_KEY as a backstop
     * for a device slow enough that this was not enough.
     *
     * The mutex makes repeated `initialize` calls (which must be idempotent,
     * §3.1) serial rather than interleaved, and [setOrCreateUser] takes it too
     * so it can never start while an initialize is still in flight.
     */
    private suspend fun handleInitialize(args: Map<String, Any?>) {
        val context = requireContext()

        initializeMutex.withLock {
            // Build on the SDK's own defaults, then override only the endpoints
            // that arrived non-null. A null on the wire means "keep the native
            // default" (§4.1) — and the endpoints must go through TraceConfig
            // rather than the setters, because setBaseUrl()/resetUrls() clear
            // the cached user and stop tracking when the value changes.
            val defaults = TraceConfig(
                apiKey = Codecs.asStringOrNull(args["apiKey"]) ?: "",
                mqttUsername = Codecs.asStringOrNull(args["mqttUsername"]) ?: "",
                mqttPassword = Codecs.asStringOrNull(args["mqttPassword"]) ?: ""
            )
            val config = defaults.copy(
                baseUrl = Codecs.asStringOrNull(args["baseUrl"]) ?: defaults.baseUrl,
                mqttUrl = Codecs.asStringOrNull(args["mqttUrl"]) ?: defaults.mqttUrl,
                mqttClientIdPrefix = Codecs.asStringOrNull(args["mqttClientIdPrefix"])
                    ?: defaults.mqttClientIdPrefix
            )

            // Logs config.warnings through BarikoiTrace.notifyLog on the way in,
            // which is how they reach the `logs` event channel.
            BarikoiTrace.initialize(context, config)
            initializedAtMs = SystemClock.elapsedRealtime()

            yield()
            delay(INITIALIZE_SETTLE_MS)
        }
    }

    /** True while we are still inside the window where a NO_KEY is suspect. */
    private fun isWithinInitializeWindow(): Boolean {
        val at = initializedAtMs
        return at != 0L && SystemClock.elapsedRealtime() - at <= INITIALIZE_RETRY_WINDOW_MS
    }

    /**
     * Cheapest facade call that still routes through `BarikoiTrace.getInstance()`
     * — two `checkSelfPermission` calls, no I/O — so it raises the same
     * `IllegalStateException` every other facade call raises before
     * `initialize()`, which [onMethodCall] turns into `NOT_INITIALIZED` (§6.2).
     *
     * Used to give that behaviour to the handful of methods that do not touch
     * the facade at all (`hasBackgroundPermission`, `refreshTracking`, the
     * settings shortcuts), so the rule "every method other than `initialize`
     * fails with NOT_INITIALIZED until it has succeeded once" holds uniformly.
     */
    private fun assertInitialized() {
        BarikoiTrace.isLocationPermissionsGranted()
    }

    // ------------------------------------------------------------------
    // User
    // ------------------------------------------------------------------

    private suspend fun setOrCreateUser(name: String?, email: String?, phone: String): TraceUser {
        // Ordering barrier only: if an initialize is in flight, wait it out.
        initializeMutex.withLock { }

        return try {
            io { BarikoiTrace.setOrCreateUser(name, email, phone) }
        } catch (e: TraceException) {
            if (e.error.code == CODE_NO_KEY && isWithinInitializeWindow()) {
                // The API-key write from initialize() had not landed yet. One
                // retry, bounded — never a loop, because a genuinely empty key
                // must still surface as NO_KEY.
                delay(NO_KEY_RETRY_DELAY_MS)
                io { BarikoiTrace.setOrCreateUser(name, email, phone) }
            } else {
                throw e
            }
        }
    }

    // ------------------------------------------------------------------
    // Tracking
    // ------------------------------------------------------------------

    /**
     * `LocTraceManager.startTracking` returns silently — one `Log.w` and
     * nothing else — when there is no user, when location permission is
     * missing, or when location services are off. From Dart that is
     * indistinguishable from success: the future completes, no fixes ever
     * arrive. Pre-check and raise the SDK's own error codes instead.
     */
    private suspend fun startTracking(mode: TraceMode, withTrip: Boolean) {
        val userId = io { BarikoiTrace.getUserId() }
        if (userId.isNullOrBlank()) throw TraceException(TraceError.noUserError())

        if (!BarikoiTrace.isLocationPermissionsGranted()) {
            throw TraceException(TraceError.locationPermissionError())
        }
        if (!BarikoiTrace.isLocationSettingsOn()) {
            throw TraceException(
                TraceError(
                    CODE_PERMISSION,
                    "Location services are turned off. Call openLocationSettings() first."
                )
            )
        }

        // The SDK re-reads the user id and enqueues the DataStore writes itself;
        // keep it off the main thread all the same, since both of those touch
        // the encrypted store synchronously on the calling thread.
        io { BarikoiTrace.startTracking(mode, withTrip) }
    }

    // ------------------------------------------------------------------
    // Location
    // ------------------------------------------------------------------

    /**
     * `LocationEngine.getCurrentLocation` does not speak `TraceException`: it
     * resumes with a `SecurityException` when permission is missing and with a
     * bare `Exception("Could not determine location")` when the fused provider
     * hands back null. Map both onto the contract's codes (§3.6) so `INTERNAL`
     * never shows up for an ordinary "no fix" (§6.2).
     */
    private suspend fun updateCurrentLocation(): Location {
        if (!BarikoiTrace.isLocationPermissionsGranted()) {
            throw TraceException(TraceError.locationPermissionError())
        }
        return try {
            io { BarikoiTrace.updateCurrentLocation() }
        } catch (e: TraceException) {
            throw e
        } catch (e: SecurityException) {
            throw TraceException(TraceError.locationPermissionError())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            throw TraceException(
                TraceError(CODE_LOCATION, e.message ?: TraceError.locationNotFoundError().message)
            )
        }
    }

    // ------------------------------------------------------------------
    // Permissions & settings
    // ------------------------------------------------------------------

    private suspend fun requestForegroundLocationPermission(): Boolean {
        val context = requireContext()
        if (SystemSettingsManager.checkPermissions(context)) return true
        return awaitPermission(REQUEST_CODE_LOCATION) { host ->
            BarikoiTrace.requestLocationPermissions(host)
        }
    }

    private suspend fun requestBackgroundLocationPermission(): Boolean {
        val context = requireContext()

        // Below Q there is no such permission; the SDK's checker reports true
        // and its requester is a no-op, so prompting would hang forever.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        if (SystemSettingsManager.checkBackgroundLocationPermission(context)) return true

        // Android refuses to even show the background prompt without foreground
        // permission — the callback would come straight back denied.
        if (!SystemSettingsManager.checkPermissions(context)) return false

        // An Activity is still required, so a missing one is NO_ACTIVITY rather
        // than a quiet false.
        requireActivity()

        return awaitPermission(REQUEST_CODE_BACKGROUND_LOCATION) { host ->
            BarikoiTrace.requestBackgroundLocationPermission(host)
        }
    }

    private suspend fun requestNotificationPermission(): Boolean {
        val context = requireContext()
        // POST_NOTIFICATIONS does not exist below API 33; the SDK's requester is
        // a no-op there and notifications are granted by default.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        if (isNotificationPermissionGranted(context)) return true

        requireActivity()

        return awaitPermission(REQUEST_CODE_NOTIFICATION) { host ->
            BarikoiTrace.requestNotificationPermission(host)
        }
    }

    /**
     * Issues a system permission prompt and suspends until it settles.
     *
     * Three ways out, and the result is delivered exactly once whichever fires:
     * the system callback, a timeout (which answers with the state as it
     * stands), or an Activity detach ([resolveAllPendingWithCurrentState]).
     * The timeout matters because a user who has chosen "Don't ask again" gets
     * no dialog and, on some OEM builds, no callback either.
     */
    private suspend fun awaitPermission(
        requestCode: Int,
        request: (Activity) -> Unit
    ): Boolean {
        val host = requireActivity()

        val settled: Boolean? = withTimeoutOrNull(PERMISSION_TIMEOUT_MS) {
            suspendCancellableCoroutine<Boolean> { continuation ->
                val entry = pendingPermissions.add(requestCode) { granted ->
                    if (continuation.isActive) continuation.resume(granted)
                }
                continuation.invokeOnCancellation { pendingPermissions.remove(entry) }
                try {
                    request(host)
                } catch (t: Throwable) {
                    pendingPermissions.remove(entry)
                    if (continuation.isActive) continuation.resumeWithException(t)
                }
            }
        }

        return settled ?: currentStateFor(requestCode)
    }

    private fun isNotificationPermissionGranted(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

    private fun openLocationSettings(): Boolean {
        val host = requireActivity()
        return try {
            // Settings.ACTION_LOCATION_SOURCE_SETTINGS, via the SDK.
            BarikoiTrace.requestLocationServices(host)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun openAppSettings(): Boolean {
        val host = requireActivity()
        return try {
            val intent = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", host.packageName, null)
            )
            host.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun requestDisableBatteryOptimization(onlyIfNeeded: Boolean) {
        val host = requireActivity()
        if (onlyIfNeeded && BarikoiTrace.isBatteryOptimizationEnabled()) {
            // Already exempt — showing the system dialog would just confuse.
            return
        }
        BarikoiTrace.requestDisableBatteryOptimization(host)
    }

    /**
     * Android has no `isBackgroundTrackingDegraded` of its own (iOS does), so
     * the plugin computes the same idea: background tracking is unreliable when
     * the app cannot get a fix in the background, when Doze may kill the
     * service, or when there is no location provider at all (§3.3).
     */
    private fun isBackgroundTrackingDegraded(): Boolean {
        val context = requireContext()
        val backgroundLocationGranted =
            SystemSettingsManager.checkBackgroundLocationPermission(context)
        val isIgnoringBatteryOptimizations = BarikoiTrace.isBatteryOptimizationEnabled()
        val isLocationSettingsOn = BarikoiTrace.isLocationSettingsOn()

        return !backgroundLocationGranted ||
            !isIgnoringBatteryOptimizations ||
            !isLocationSettingsOn
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /**
     * Runs an SDK call on `Dispatchers.IO`. The facade's `suspend` functions do
     * no dispatching of their own, and its plain getters read an encrypted
     * DataStore, so neither belongs on the main thread. The caller resumes back
     * on the main thread because the enclosing scope is `Main.immediate`.
     */
    private suspend fun <T> io(block: suspend () -> T): T =
        withContext(Dispatchers.IO) { block() }

    private fun requireContext(): Context =
        applicationContext ?: throw PluginException(
            CODE_INTERNAL,
            "BarikoiTraceFlutterPlugin is not attached to a FlutterEngine."
        )

    private fun requireActivity(): Activity =
        activity ?: throw PluginException(
            CODE_NO_ACTIVITY,
            "This call needs a foreground Activity, and the plugin is not attached to one."
        )

    private fun requireStringArg(call: MethodCall, key: String): String =
        call.argument<String>(key) ?: throw PluginException(
            CODE_INTERNAL,
            "Missing required '$key' argument for ${call.method}."
        )

    private fun requireBoolArg(call: MethodCall, key: String): Boolean =
        call.argument<Boolean>(key) ?: throw PluginException(
            CODE_INTERNAL,
            "Missing required '$key' argument for ${call.method}."
        )

    /** A bridge-level failure that already knows its channel error code (§6.2). */
    private class PluginException(val code: String, message: String) : Exception(message)

    /**
     * Guarantees a `MethodChannel.Result` is answered at most once (§6.3) — a
     * permission timeout firing next to a late system callback is exactly the
     * shape of bug this exists to make impossible.
     */
    private class ResultOnce(private val delegate: MethodChannel.Result) : MethodChannel.Result {
        private var answered = false

        override fun success(result: Any?) {
            if (answered) return
            answered = true
            delegate.success(result)
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            if (answered) return
            answered = true
            delegate.error(errorCode, errorMessage, errorDetails)
        }

        override fun notImplemented() {
            if (answered) return
            answered = true
            delegate.notImplemented()
        }
    }

    internal companion object {
        const val CHANNEL_METHODS = "barikoi_trace_flutter/methods"
        const val CHANNEL_LOCATION_UPDATES = "barikoi_trace_flutter/location_updates"
        const val CHANNEL_LOGS = "barikoi_trace_flutter/logs"

        const val METHOD_INITIALIZE = "initialize"

        // Plugin-only error codes (§6.2).
        const val CODE_NOT_INITIALIZED = "NOT_INITIALIZED"
        const val CODE_NO_ACTIVITY = "NO_ACTIVITY"
        const val CODE_INTERNAL = "INTERNAL"

        // Native codes referenced by name (§6.1). Values match TraceError's
        // factories; kept as constants so they can be compared without
        // allocating a TraceError per call.
        const val CODE_NO_KEY = "NO_KEY"
        const val CODE_PERMISSION = "PERMISSION"
        const val CODE_LOCATION = "LOCATION"

        /**
         * The request codes the SDK itself passes to
         * `ActivityCompat.requestPermissions`, from
         * `util/SystemSettingsManager.kt`. They have to match exactly, because
         * the plugin asks the SDK to issue the prompt and then reads the result
         * out of the Activity callback.
         */
        const val REQUEST_CODE_LOCATION = 10221
        const val REQUEST_CODE_BACKGROUND_LOCATION = 10222
        const val REQUEST_CODE_NOTIFICATION = 10226

        /** How long a prompt may stay unanswered before we answer with the current state. */
        const val PERMISSION_TIMEOUT_MS = 120_000L

        /** Settling window for initialize()'s asynchronous credential write. */
        const val INITIALIZE_SETTLE_MS = 120L

        /** A NO_KEY inside this window of an initialize() is treated as the race. */
        const val INITIALIZE_RETRY_WINDOW_MS = 500L

        /** Pause before the single NO_KEY retry. */
        const val NO_KEY_RETRY_DELAY_MS = 250L

        /**
         * The 33 methods this platform answers, out of the contract's 34.
         * `ios.setLocationDisabledNotificationEnabled` is deliberately absent:
         * anything not on this list gets `notImplemented()` (§3).
         */
        val SUPPORTED_METHODS: Set<String> = hashSetOf(
            "initialize",
            "setBaseUrl",
            "setMqttUrl",
            "setMqttClientIdPrefix",
            "resetUrls",
            "setOrCreateUser",
            "getUser",
            "getUserId",
            "isLocationPermissionsGranted",
            "isLocationSettingsOn",
            "hasBackgroundPermission",
            "requestLocationPermissions",
            "requestBackgroundLocationPermission",
            "openLocationSettings",
            "openAppSettings",
            "isBackgroundTrackingDegraded",
            "setTraceMode",
            "startTracking",
            "stopTracking",
            "refreshTracking",
            "isLocationTracking",
            "setOfflineTracking",
            "setLoggingEnabled",
            "setBroadcastingEnabled",
            "isOnTrip",
            "getTripId",
            "updateCurrentLocation",
            "uploadOfflineData",
            "getSettingsFromRemote",
            "android.requestNotificationPermission",
            "android.requestDisableBatteryOptimization",
            "android.isIgnoringBatteryOptimizations",
            "android.openAutostartSettings"
        )
    }
}
