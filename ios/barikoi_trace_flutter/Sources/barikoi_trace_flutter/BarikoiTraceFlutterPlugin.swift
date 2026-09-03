import CoreLocation
import Flutter
import Foundation
import UIKit

import BarikoiTrace

/// Delivers a `FlutterResult` exactly once, on the platform thread.
///
/// The async SDK calls (`setOrCreateUser`, `updateCurrentLocation`,
/// `getSettingsFromRemote`) and the permission requests all answer from
/// somewhere other than the call that started them, and the contract is
/// explicit that a result must be delivered once and on the main thread. A
/// `FlutterResult` is a plain non-`Sendable` closure, so it is boxed rather
/// than captured directly.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: FlutterResult?

    init(_ result: @escaping FlutterResult) {
        self.result = result
    }

    func succeed(_ value: Any?) {
        deliver(value)
    }

    func fail(_ error: Error) {
        deliver(Codecs.flutterError(from: error))
    }

    private func deliver(_ value: Any?) {
        lock.lock()
        let pending = result
        result = nil
        lock.unlock()

        guard let pending = pending else { return }
        if Thread.isMainThread {
            pending(value)
        } else {
            DispatchQueue.main.async { pending(value) }
        }
    }
}

/// The iOS half of `barikoi_trace_flutter`.
///
/// Conforms to `FlutterPlugin` only. `FlutterPlugin` already inherits the
/// `UIApplicationDelegate` hooks through `FlutterApplicationLifeCycleDelegate`
/// — spelling `UIApplicationDelegate` out a second time would drag in UIKit's
/// own `application(_:didFinishLaunchingWithOptions:)`, whose `launchOptions`
/// is typed `[UIApplication.LaunchOptionsKey: Any]?` where Flutter's is a
/// non-optional `[AnyHashable: Any]`, leaving two conflicting Swift signatures
/// for one Objective-C selector.
public final class BarikoiTraceFlutterPlugin: NSObject, FlutterPlugin {

    private static let methodChannelName = "barikoi_trace_flutter/methods"
    private static let locationChannelName = "barikoi_trace_flutter/location_updates"
    private static let logChannelName = "barikoi_trace_flutter/logs"

    private let logStreamHandler = LogStreamHandler()
    private let locationStreamHandler = LocationStreamHandler()
    private let permissionObserver = PermissionObserver()

    /// Kept alive for the life of the plugin. `setStreamHandler` installs a
    /// message handler that retains the stream handler, but holding the
    /// channels too keeps the ownership obvious and lets them be torn down
    /// together if this ever grows a `detachFromEngine` path.
    private var locationEventChannel: FlutterEventChannel?
    private var logEventChannel: FlutterEventChannel?

    /// Set by a successful `initialize`. Everything else answers
    /// `NOT_INITIALIZED` until then, per the contract — including on this
    /// platform, where the SDK itself was already initialized at launch.
    private var isInitialized = false

    // MARK: - Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let instance = BarikoiTraceFlutterPlugin()

        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: messenger
        )
        // Retains `instance`. That matters for the two registrations below:
        // `FlutterPluginAppLifeCycleDelegate` holds its application delegates
        // *weakly*, and `TraceManager.logListener` is a `weak var` too, so
        // this is the reference that keeps the whole object graph alive.
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let locationChannel = FlutterEventChannel(
            name: locationChannelName,
            binaryMessenger: messenger
        )
        locationChannel.setStreamHandler(instance.locationStreamHandler)
        instance.locationEventChannel = locationChannel

        let logChannel = FlutterEventChannel(
            name: logChannelName,
            binaryMessenger: messenger
        )
        logChannel.setStreamHandler(instance.logStreamHandler)
        instance.logEventChannel = logChannel

        BarikoiTrace.setLogListener(instance.logStreamHandler)
        registrar.addApplicationDelegate(instance)
    }

    // MARK: - UIApplicationDelegate (via FlutterApplicationLifeCycleDelegate)

    /// The SDK's real initialization point — see `LaunchBootstrap`.
    ///
    /// Reached only when the host app registers its plugins from inside
    /// `application(_:didFinishLaunchingWithOptions:)` *before* calling
    /// `super.application(...)`, which is what the standard Flutter AppDelegate
    /// template does.
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any] = [:]
    ) -> Bool {
        LaunchBootstrap.run(launchOptions: launchOptions, log: logStreamHandler)
        // Never veto launch: a `false` here would abort the whole chain of
        // application delegates, including the host app's own.
        return true
    }

    // MARK: - Method channel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = Codecs.wireMap(call.arguments)

        // Answered regardless of initialization state.
        switch call.method {
        case "initialize":
            handleInitialize(args, result)
            return

        // The Android-only surface. The Dart layer checks `defaultTargetPlatform`
        // and never invokes these here, so reaching them means a host app went
        // around the plugin's own API. A benign default is friendlier than an
        // error for calls that are, by construction, no-ops on this platform.
        case "android.requestNotificationPermission":
            result(false)
            return
        case "android.isIgnoringBatteryOptimizations":
            result(false)
            return
        case "android.requestDisableBatteryOptimization",
             "android.openAutostartSettings":
            result(nil)
            return

        default:
            break
        }

        guard isInitialized else {
            result(FlutterError(
                code: TraceErrorCodes.notInitialized,
                message: "BarikoiTrace has not been initialized. Call initialize(TraceConfig) "
                    + "before '\(call.method)'.",
                details: nil
            ))
            return
        }

        switch call.method {

        // MARK: Configuration

        case "setBaseUrl":
            guard let url = Codecs.string(args["url"]) else {
                result(missingArgument("url", call.method))
                return
            }
            BarikoiTrace.setBaseURL(url)
            result(nil)

        case "setMqttUrl":
            guard let url = Codecs.string(args["url"]) else {
                result(missingArgument("url", call.method))
                return
            }
            BarikoiTrace.setMqttURL(url)
            result(nil)

        case "setMqttClientIdPrefix":
            guard let prefix = Codecs.string(args["prefix"]) else {
                result(missingArgument("prefix", call.method))
                return
            }
            BarikoiTrace.setMqttClientIdPrefix(prefix)
            // Held in memory by the SDK only, so the plugin persists it for
            // the next launch's `TraceConfig`.
            PluginPreferences.mqttClientIdPrefix = prefix
            result(nil)

        case "resetUrls":
            BarikoiTrace.resetURLs()
            result(nil)

        // MARK: User

        case "setOrCreateUser":
            let name = Codecs.string(args["name"])
            let email = Codecs.string(args["email"])
            let phone = Codecs.string(args["phone"]) ?? ""
            let box = ResultBox(result)
            Task {
                do {
                    let user = try await BarikoiTrace.setOrCreateUser(
                        name: name,
                        email: email,
                        phone: phone
                    )
                    box.succeed(Codecs.encodeUser(user))
                } catch {
                    box.fail(error)
                }
            }

        case "getUser":
            if let user = BarikoiTrace.getUser() {
                result(Codecs.encodeUser(user))
            } else {
                result(nil)
            }

        case "getUserId":
            // Spelled out rather than `result(BarikoiTrace.getUserId())` so
            // there is no chance of a `String?` being boxed into a non-nil
            // `Any` on its way through the codec.
            if let userId = BarikoiTrace.getUserId() {
                result(userId)
            } else {
                result(nil)
            }

        // MARK: Permissions & settings

        case "isLocationPermissionsGranted":
            result(BarikoiTrace.isLocationPermissionsGranted())

        case "isLocationSettingsOn":
            result(BarikoiTrace.isLocationSettingsOn())

        case "hasBackgroundPermission":
            result(BarikoiTrace.hasBackgroundPermission())

        case "requestLocationPermissions":
            let box = ResultBox(result)
            permissionObserver.requestWhenInUse { granted in box.succeed(granted) }

        case "requestBackgroundLocationPermission":
            let box = ResultBox(result)
            permissionObserver.requestAlways { granted in box.succeed(granted) }

        case "openLocationSettings":
            // iOS exposes no deep link to the system Location Services toggle,
            // so the app's own settings page — which carries its Location row
            // — is the destination. Same call as `openAppSettings`, kept as a
            // separate case because the contract keeps them separate.
            result(BarikoiTrace.openAppSettings())

        case "openAppSettings":
            result(BarikoiTrace.openAppSettings())

        case "isBackgroundTrackingDegraded":
            result(BarikoiTrace.isBackgroundTrackingDegraded)

        // MARK: Tracking

        case "setTraceMode":
            BarikoiTrace.setTraceMode(Codecs.decodeMode(args["mode"]))
            result(nil)

        case "startTracking":
            // Pre-checked here because `TraceManager.startTracking` returns
            // after a bare log line when there is no user or no permission —
            // a Dart `await startTracking(...)` would otherwise succeed and no
            // fix would ever arrive. The Android plugin does the same, so the
            // two platforms fail identically.
            guard let userId = BarikoiTrace.getUserId(), !userId.isEmpty else {
                result(FlutterError(
                    code: TraceErrorCodes.noUser,
                    message: "No user. Call setOrCreateUser() before startTracking().",
                    details: nil
                ))
                return
            }
            guard BarikoiTrace.isLocationPermissionsGranted() else {
                result(FlutterError(
                    code: TraceErrorCodes.permission,
                    message: "Location permission not granted.",
                    details: nil
                ))
                return
            }
            guard BarikoiTrace.isLocationSettingsOn() else {
                result(FlutterError(
                    code: TraceErrorCodes.permission,
                    message: "Location Services are off device-wide.",
                    details: nil
                ))
                return
            }
            BarikoiTrace.startTracking(
                Codecs.decodeMode(args["mode"]),
                withTrip: Codecs.bool(args["withTrip"], false)
            )
            result(nil)

        case "stopTracking":
            BarikoiTrace.stopTracking()
            result(nil)

        case "refreshTracking":
            BarikoiTrace.refreshTracking()
            result(nil)

        case "isLocationTracking":
            result(BarikoiTrace.isLocationTracking())

        case "setOfflineTracking":
            BarikoiTrace.setOfflineTracking(Codecs.bool(args["enabled"], false))
            result(nil)

        case "setLoggingEnabled":
            BarikoiTrace.setLoggingEnabled(Codecs.bool(args["enabled"], false))
            result(nil)

        case "setBroadcastingEnabled":
            BarikoiTrace.setBroadcastingEnabled(Codecs.bool(args["enabled"], false))
            result(nil)

        // MARK: Trips

        case "isOnTrip":
            result(BarikoiTrace.isOnTrip())

        case "getTripId":
            if let tripId = BarikoiTrace.getTripId() {
                result(tripId)
            } else {
                result(nil)
            }

        // MARK: Location

        case "updateCurrentLocation":
            let box = ResultBox(result)
            Task {
                do {
                    let location = try await BarikoiTrace.updateCurrentLocation()
                    box.succeed(Codecs.encodeLocation(location))
                } catch {
                    // `TraceLocationEngine` already throws PERMISSION when
                    // authorization is missing and LOCATION when no fix could
                    // be obtained, so both codes pass straight through.
                    box.fail(error)
                }
            }

        case "uploadOfflineData":
            // Fire-and-forget by construction: the SDK's implementation
            // schedules a `Task` and returns.
            BarikoiTrace.uploadOfflineData()
            result(nil)

        case "getSettingsFromRemote":
            let box = ResultBox(result)
            Task {
                do {
                    let mode = try await BarikoiTrace.getSettingsFromRemote()
                    box.succeed(Codecs.encodeMode(mode))
                } catch {
                    box.fail(error)
                }
            }

        // MARK: iOS-only

        case "ios.setLocationDisabledNotificationEnabled":
            BarikoiTrace.setLocationDisabledNotificationEnabled(
                Codecs.bool(args["enabled"], true)
            )
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - initialize

    /// Applies everything a `TraceConfig` can still change after launch, and
    /// persists the rest for the next one.
    ///
    /// Deliberately does **not** call `BarikoiTrace.initialize` — see
    /// `LaunchBootstrap` for why that would re-register a `BGTaskScheduler`
    /// identifier and terminate the app.
    private func handleInitialize(_ args: [String: Any], _ result: @escaping FlutterResult) {
        let apiKey = Codecs.string(args["apiKey"]) ?? ""
        let mqttUsername = Codecs.string(args["mqttUsername"]) ?? ""
        let mqttPassword = Codecs.string(args["mqttPassword"]) ?? ""
        let baseUrl = Codecs.string(args["baseUrl"])
        let mqttUrl = Codecs.string(args["mqttUrl"])
        let clientIdPrefix = Codecs.string(args["mqttClientIdPrefix"])

        // 1. Warnings first, so they precede anything the setters below log.
        //    Built from the same `TraceConfig.warnings` the SDK computes, on a
        //    config that mirrors what the host app asked for — a null endpoint
        //    leaves the SDK's own default in place, which is what the warning
        //    text should describe.
        var config = TraceConfig(
            apiKey: apiKey,
            mqttUsername: mqttUsername,
            mqttPassword: mqttPassword
        )
        if let baseUrl = baseUrl { config.baseURL = baseUrl }
        if let mqttUrl = mqttUrl { config.mqttURL = mqttUrl }
        if let clientIdPrefix = clientIdPrefix { config.mqttClientIdPrefix = clientIdPrefix }

        for warning in config.warnings {
            logStreamHandler.emit(level: "WARN", tag: "TraceConfig", message: warning)
        }

        if !LaunchBootstrap.didFireLaunchHook {
            logStreamHandler.emit(
                level: "WARN",
                tag: "BarikoiTraceFlutterPlugin",
                message: "The plugin's application(_:didFinishLaunchingWithOptions:) hook never ran, "
                    + "so BarikoiTrace was not initialized at launch: no BGTaskScheduler task is "
                    + "registered, background offline-queue flushing is disabled, and a "
                    + "significant-location-change relaunch will not resume tracking. Register "
                    + "plugins from inside application(_:didFinishLaunchingWithOptions:) and before "
                    + "calling super — i.e. 'GeneratedPluginRegistrant.register(with: self)' must "
                    + "precede 'super.application(application, didFinishLaunchingWithOptions: "
                    + "launchOptions)' in AppDelegate.swift."
            )
        }

        // 2. Apply what can be applied post-launch. Only non-null endpoints —
        //    a null means "leave the native default in place", and calling the
        //    setter with an empty string would wipe it.
        TraceManager.shared.setMqttCredentials(
            username: mqttUsername,
            password: mqttPassword
        )
        if let mqttUrl = mqttUrl {
            BarikoiTrace.setMqttURL(mqttUrl)
        }
        if let clientIdPrefix = clientIdPrefix {
            BarikoiTrace.setMqttClientIdPrefix(clientIdPrefix)
            PluginPreferences.mqttClientIdPrefix = clientIdPrefix
        }
        if let baseUrl = baseUrl {
            // Last of the three: `TraceManager.setBaseURL` clears the stored
            // user and trace mode and stops tracking when the value actually
            // changes, so it is the most disruptive of them. It is a no-op
            // when the URL matches what `LaunchBootstrap` already applied,
            // which is the normal case.
            BarikoiTrace.setBaseURL(baseUrl)
        }

        // 3. The API key. `TraceApiClient` reads it once, at
        //    `TraceManager.shared` construction, and the only public way to
        //    refresh it is `TraceManager.initialize(apiKey:)` — which is
        //    exactly the call that must not run twice. So it is persisted for
        //    the next launch, and the mismatch is reported rather than
        //    silently ignored.
        let store = TraceDataStore()
        let persistedKey = store.getApiKey()
        if persistedKey != apiKey {
            store.setApiKey(apiKey)
            logStreamHandler.emit(
                level: "WARN",
                tag: "BarikoiTraceFlutterPlugin",
                message: "The apiKey passed to initialize() differs from the one this process "
                    + "launched with. It has been persisted and takes effect on the next app "
                    + "launch; this session keeps using the previous key. (iOS registers its "
                    + "background tasks during launch, so the SDK cannot be re-initialized "
                    + "mid-process.)"
            )
        }

        isInitialized = true
        result(nil)
    }

    // MARK: - Helpers

    private func missingArgument(_ key: String, _ method: String) -> FlutterError {
        FlutterError(
            code: TraceErrorCodes.internalError,
            message: "'\(method)' was called without a '\(key)' argument.",
            details: nil
        )
    }
}
