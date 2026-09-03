import 'models/trace_config.dart';
import 'models/trace_location.dart';
import 'models/trace_log_entry.dart';
import 'models/trace_mode.dart';
import 'models/trace_user.dart';
import 'platform_interface/barikoi_trace_platform.dart';
import 'platform_specific/android_api.dart';
import 'platform_specific/ios_api.dart';

/// The Barikoi Trace SDK, as one static facade.
///
/// Method names and shapes mirror `BarikoiTrace.kt` and `BarikoiTrace.swift`
/// so that call sites read the same on all three platforms. Everything is
/// asynchronous here even where the native call is synchronous, because every
/// call crosses a platform channel.
///
/// Failures arrive as `TraceException` with the native error code passed
/// through verbatim.
///
/// ```dart
/// await BarikoiTrace.initialize(const TraceConfig(
///   apiKey: '…',
///   mqttUsername: '…',
///   mqttPassword: '…',
/// ));
///
/// if (!await BarikoiTrace.isLocationPermissionsGranted()) {
///   await BarikoiTrace.requestLocationPermissions();
/// }
///
/// await BarikoiTrace.setOrCreateUser(phone: '01700000000');
/// await BarikoiTrace.startTracking(TraceMode.active);
///
/// BarikoiTrace.locationUpdates.listen((fix) => print(fix.latitude));
/// ```
abstract final class BarikoiTrace {
  /// The native SDK version this plugin release is built and tested against,
  /// on both Android and iOS.
  static const String nativeSdkVersion = '0.4.0';

  static BarikoiTracePlatform get _platform => BarikoiTracePlatform.instance;

  // --- Init & configuration ---

  /// Configures and starts the SDK. Call once, before anything else.
  ///
  /// Endpoints are applied before the native manager starts, which matters:
  /// initialization resumes tracking when the previous process was tracking,
  /// and a resumed session builds its MQTT client immediately — setting the
  /// broker URL afterwards would be too late for that first client.
  static Future<void> initialize(TraceConfig config) =>
      _platform.initialize(config);

  /// Overrides the REST base URL after [initialize].
  ///
  /// Prefer `TraceConfig.baseUrl`, which cannot land after the first network
  /// call the way this can.
  static Future<void> setBaseUrl(String url) => _platform.setBaseUrl(url);

  /// Overrides the MQTT broker URL after [initialize].
  ///
  /// Prefer `TraceConfig.mqttUrl` — a session resumed by [initialize] builds
  /// its client before this call can land.
  static Future<void> setMqttUrl(String url) => _platform.setMqttUrl(url);

  /// Overrides the MQTT client-id prefix (`AndroidClient-` / `iOSClient-` by
  /// default). Only needed when the broker ACL authorizes by client-id
  /// pattern. Call before [startTracking].
  static Future<void> setMqttClientIdPrefix(String prefix) =>
      _platform.setMqttClientIdPrefix(prefix);

  /// Restores both endpoints to the native SDK defaults, discarding any
  /// persisted override.
  static Future<void> resetUrls() => _platform.resetUrls();

  // --- User ---

  /// Looks up the user by [phone], creating them if they do not exist, and
  /// makes them the tracked user.
  ///
  /// Required before tracking: every upload and the MQTT topic are keyed on
  /// the returned user id.
  static Future<TraceUser> setOrCreateUser({
    String? name,
    String? email,
    required String phone,
  }) =>
      _platform.setOrCreateUser(name: name, email: email, phone: phone);

  /// The currently tracked user, or null if [setOrCreateUser] has not
  /// succeeded yet on this device.
  static Future<TraceUser?> getUser() => _platform.getUser();

  /// Just the tracked user's id, or null. Cheaper than [getUser] when that is
  /// all you need.
  static Future<String?> getUserId() => _platform.getUserId();

  // --- Permissions & settings ---

  /// Whether foreground location permission is granted.
  static Future<bool> isLocationPermissionsGranted() =>
      _platform.isLocationPermissionsGranted();

  /// Whether device location services are switched on.
  static Future<bool> isLocationSettingsOn() => _platform.isLocationSettingsOn();

  /// Whether background location is granted —
  /// `ACCESS_BACKGROUND_LOCATION` on Android, `Always` authorization on iOS.
  static Future<bool> hasBackgroundPermission() =>
      _platform.hasBackgroundPermission();

  /// Prompts for foreground ("when in use") location permission.
  ///
  /// Resolves to whether the permission is granted after the prompt settles.
  static Future<bool> requestLocationPermissions() =>
      _platform.requestLocationPermissions();

  /// Prompts for background ("always") location permission.
  ///
  /// Both platforms only grant this once foreground permission is already
  /// held, so call [requestLocationPermissions] first. Resolves to whether the
  /// permission is granted afterwards.
  static Future<bool> requestBackgroundLocationPermission() =>
      _platform.requestBackgroundLocationPermission();

  /// Sends the user to the location-services screen.
  ///
  /// Android opens the system location settings directly. iOS exposes no deep
  /// link to that toggle, so it opens this app's Settings page — which carries
  /// its Location row — instead. Resolves to whether a screen was opened.
  static Future<bool> openLocationSettings() => _platform.openLocationSettings();

  /// Opens this app's system settings page, where the user can change a
  /// permission they previously denied. Resolves to whether it opened.
  static Future<bool> openAppSettings() => _platform.openAppSettings();

  /// Whether something is currently limiting how reliably background tracking
  /// can run.
  ///
  /// On iOS that means Low Power Mode, a downgraded or denied `Always`
  /// authorization, or Background App Refresh being off. On Android it means
  /// battery optimization is not exempted, background location is missing, or
  /// location services are off. Use it to show a "tracking may be unreliable"
  /// banner rather than to gate [startTracking].
  static Future<bool> isBackgroundTrackingDegraded() =>
      _platform.isBackgroundTrackingDegraded();

  // --- Tracking ---

  /// Stores [mode] as the active configuration.
  ///
  /// Applied immediately when tracking is already running; otherwise it takes
  /// effect at the next [startTracking].
  static Future<void> setTraceMode(TraceMode mode) =>
      _platform.setTraceMode(mode);

  /// Starts tracking with [mode].
  ///
  /// Pass `withTrip: true` to open a trip alongside the session, which groups
  /// the fixes server-side and makes [getTripId] non-null.
  static Future<void> startTracking(
    TraceMode mode, {
    bool withTrip = false,
  }) =>
      _platform.startTracking(mode, withTrip: withTrip);

  /// Stops tracking and, if one is open, ends the trip.
  static Future<void> stopTracking() => _platform.stopTracking();

  /// Re-applies the stored [TraceMode] to a running session.
  ///
  /// [setTraceMode] already does this while tracking; this is for callers that
  /// changed the mode through some other path, such as
  /// [getSettingsFromRemote].
  static Future<void> refreshTracking() => _platform.refreshTracking();

  /// Whether a tracking session is currently running.
  static Future<bool> isLocationTracking() => _platform.isLocationTracking();

  /// Enables or disables persisting fixes while offline for later upload.
  static Future<void> setOfflineTracking(bool enabled) =>
      _platform.setOfflineTracking(enabled);

  /// Enables or disables the SDK's verbose internal logging. Gates what the
  /// [logs] stream carries.
  static Future<void> setLoggingEnabled(bool enabled) =>
      _platform.setLoggingEnabled(enabled);

  /// Enables or disables local broadcasting of fixes. Gates the
  /// [locationUpdates] stream — it stays silent while this is off.
  static Future<void> setBroadcastingEnabled(bool enabled) =>
      _platform.setBroadcastingEnabled(enabled);

  // --- Trips ---

  /// Whether a trip is currently open.
  static Future<bool> isOnTrip() => _platform.isOnTrip();

  /// The open trip's id, or null when not on a trip.
  static Future<String?> getTripId() => _platform.getTripId();

  // --- Location ---

  /// Requests a single fresh fix, independently of any tracking session.
  ///
  /// Throws `TraceException` with code `PERMISSION` when location permission
  /// is missing, or `LOCATION` when no fix could be obtained.
  static Future<TraceLocation> updateCurrentLocation() =>
      _platform.updateCurrentLocation();

  /// Flushes any fixes buffered while offline. Fire-and-forget: it returns as
  /// soon as the upload has been scheduled.
  static Future<void> uploadOfflineData() => _platform.uploadOfflineData();

  /// Fetches the company's tracking settings from the Barikoi backend as a
  /// [TraceMode].
  ///
  /// It is not applied automatically — pass the result to [setTraceMode] (or
  /// [startTracking]) if you want it to take effect.
  static Future<TraceMode> getSettingsFromRemote() =>
      _platform.getSettingsFromRemote();

  // --- Streams ---

  /// Live location fixes from the running tracking session.
  ///
  /// Broadcast, so it takes any number of listeners, and silent until
  /// `setBroadcastingEnabled(true)`.
  static Stream<TraceLocation> get locationUpdates => _platform.locationUpdates;

  /// The native SDK's internal debug log.
  ///
  /// Broadcast, and gated by [setLoggingEnabled]. This is the stream a debug
  /// console screen should render; it is not a substitute for handling
  /// `TraceException`.
  static Stream<TraceLogEntry> get logs => _platform.logs;

  // --- Platform-specific escape hatches ---

  /// Android-only calls. No-ops on other platforms — see
  /// [BarikoiTraceAndroid].
  static BarikoiTraceAndroid get android => BarikoiTraceAndroid.instance;

  /// iOS-only calls. No-ops on other platforms — see [BarikoiTraceIos].
  static BarikoiTraceIos get ios => BarikoiTraceIos.instance;
}
