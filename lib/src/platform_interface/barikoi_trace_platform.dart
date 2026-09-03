import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../method_channel/method_channel_barikoi_trace.dart';
import '../models/trace_config.dart';
import '../models/trace_location.dart';
import '../models/trace_log_entry.dart';
import '../models/trace_mode.dart';
import '../models/trace_user.dart';

/// The interface every platform implementation of `barikoi_trace_flutter`
/// implements.
///
/// Host apps never touch this — call the static `BarikoiTrace` facade instead.
/// It exists so tests can swap in a fake, and so a federated implementation
/// (say, a desktop no-op) can register itself without this package changing.
///
/// Platform implementations must `extend` this class rather than `implement`
/// it: the [PlatformInterface] token check enforces that, so adding a method
/// here is a non-breaking change for implementors.
abstract class BarikoiTracePlatform extends PlatformInterface {
  /// Constructs a platform implementation.
  BarikoiTracePlatform() : super(token: _token);

  static final Object _token = Object();

  static BarikoiTracePlatform _instance = MethodChannelBarikoiTrace();

  /// The active implementation. Defaults to [MethodChannelBarikoiTrace].
  static BarikoiTracePlatform get instance => _instance;

  /// Replaces the active implementation.
  ///
  /// Platform-specific packages set this in their `registerWith`; tests set it
  /// to a fake. The value must extend [BarikoiTracePlatform].
  static set instance(BarikoiTracePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // --- Init & configuration ---

  /// See `BarikoiTrace.initialize`.
  Future<void> initialize(TraceConfig config) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// See `BarikoiTrace.setBaseUrl`.
  Future<void> setBaseUrl(String url) {
    throw UnimplementedError('setBaseUrl() has not been implemented.');
  }

  /// See `BarikoiTrace.setMqttUrl`.
  Future<void> setMqttUrl(String url) {
    throw UnimplementedError('setMqttUrl() has not been implemented.');
  }

  /// See `BarikoiTrace.setMqttClientIdPrefix`.
  Future<void> setMqttClientIdPrefix(String prefix) {
    throw UnimplementedError(
      'setMqttClientIdPrefix() has not been implemented.',
    );
  }

  /// See `BarikoiTrace.resetUrls`.
  Future<void> resetUrls() {
    throw UnimplementedError('resetUrls() has not been implemented.');
  }

  // --- User ---

  /// See `BarikoiTrace.setOrCreateUser`.
  Future<TraceUser> setOrCreateUser({
    String? name,
    String? email,
    required String phone,
  }) {
    throw UnimplementedError('setOrCreateUser() has not been implemented.');
  }

  /// See `BarikoiTrace.getUser`.
  Future<TraceUser?> getUser() {
    throw UnimplementedError('getUser() has not been implemented.');
  }

  /// See `BarikoiTrace.getUserId`.
  Future<String?> getUserId() {
    throw UnimplementedError('getUserId() has not been implemented.');
  }

  // --- Permissions & settings ---

  /// See `BarikoiTrace.isLocationPermissionsGranted`.
  Future<bool> isLocationPermissionsGranted() {
    throw UnimplementedError(
      'isLocationPermissionsGranted() has not been implemented.',
    );
  }

  /// See `BarikoiTrace.isLocationSettingsOn`.
  Future<bool> isLocationSettingsOn() {
    throw UnimplementedError('isLocationSettingsOn() has not been implemented.');
  }

  /// See `BarikoiTrace.hasBackgroundPermission`.
  Future<bool> hasBackgroundPermission() {
    throw UnimplementedError(
      'hasBackgroundPermission() has not been implemented.',
    );
  }

  /// See `BarikoiTrace.requestLocationPermissions`.
  Future<bool> requestLocationPermissions() {
    throw UnimplementedError(
      'requestLocationPermissions() has not been implemented.',
    );
  }

  /// See `BarikoiTrace.requestBackgroundLocationPermission`.
  Future<bool> requestBackgroundLocationPermission() {
    throw UnimplementedError(
      'requestBackgroundLocationPermission() has not been implemented.',
    );
  }

  /// See `BarikoiTrace.openLocationSettings`.
  Future<bool> openLocationSettings() {
    throw UnimplementedError(
      'openLocationSettings() has not been implemented.',
    );
  }

  /// See `BarikoiTrace.openAppSettings`.
  Future<bool> openAppSettings() {
    throw UnimplementedError('openAppSettings() has not been implemented.');
  }

  /// See `BarikoiTrace.isBackgroundTrackingDegraded`.
  Future<bool> isBackgroundTrackingDegraded() {
    throw UnimplementedError(
      'isBackgroundTrackingDegraded() has not been implemented.',
    );
  }

  // --- Tracking ---

  /// See `BarikoiTrace.setTraceMode`.
  Future<void> setTraceMode(TraceMode mode) {
    throw UnimplementedError('setTraceMode() has not been implemented.');
  }

  /// See `BarikoiTrace.startTracking`.
  Future<void> startTracking(TraceMode mode, {bool withTrip = false}) {
    throw UnimplementedError('startTracking() has not been implemented.');
  }

  /// See `BarikoiTrace.stopTracking`.
  Future<void> stopTracking() {
    throw UnimplementedError('stopTracking() has not been implemented.');
  }

  /// See `BarikoiTrace.refreshTracking`.
  Future<void> refreshTracking() {
    throw UnimplementedError('refreshTracking() has not been implemented.');
  }

  /// See `BarikoiTrace.isLocationTracking`.
  Future<bool> isLocationTracking() {
    throw UnimplementedError('isLocationTracking() has not been implemented.');
  }

  /// See `BarikoiTrace.setOfflineTracking`.
  Future<void> setOfflineTracking(bool enabled) {
    throw UnimplementedError('setOfflineTracking() has not been implemented.');
  }

  /// See `BarikoiTrace.setLoggingEnabled`.
  Future<void> setLoggingEnabled(bool enabled) {
    throw UnimplementedError('setLoggingEnabled() has not been implemented.');
  }

  /// See `BarikoiTrace.setBroadcastingEnabled`.
  Future<void> setBroadcastingEnabled(bool enabled) {
    throw UnimplementedError(
      'setBroadcastingEnabled() has not been implemented.',
    );
  }

  // --- Trips ---

  /// See `BarikoiTrace.isOnTrip`.
  Future<bool> isOnTrip() {
    throw UnimplementedError('isOnTrip() has not been implemented.');
  }

  /// See `BarikoiTrace.getTripId`.
  Future<String?> getTripId() {
    throw UnimplementedError('getTripId() has not been implemented.');
  }

  // --- Location ---

  /// See `BarikoiTrace.updateCurrentLocation`.
  Future<TraceLocation> updateCurrentLocation() {
    throw UnimplementedError(
      'updateCurrentLocation() has not been implemented.',
    );
  }

  /// See `BarikoiTrace.uploadOfflineData`.
  Future<void> uploadOfflineData() {
    throw UnimplementedError('uploadOfflineData() has not been implemented.');
  }

  /// See `BarikoiTrace.getSettingsFromRemote`.
  Future<TraceMode> getSettingsFromRemote() {
    throw UnimplementedError(
      'getSettingsFromRemote() has not been implemented.',
    );
  }

  // --- Streams ---

  /// See `BarikoiTrace.locationUpdates`.
  Stream<TraceLocation> get locationUpdates {
    throw UnimplementedError('locationUpdates has not been implemented.');
  }

  /// See `BarikoiTrace.logs`.
  Stream<TraceLogEntry> get logs {
    throw UnimplementedError('logs has not been implemented.');
  }

  // --- Android-only ---

  /// See `BarikoiTrace.android.requestNotificationPermission`.
  Future<bool> androidRequestNotificationPermission() {
    throw UnimplementedError(
      'androidRequestNotificationPermission() has not been implemented.',
    );
  }

  /// See `BarikoiTrace.android.requestDisableBatteryOptimization`.
  Future<void> androidRequestDisableBatteryOptimization({
    bool onlyIfNeeded = false,
  }) {
    throw UnimplementedError(
      'androidRequestDisableBatteryOptimization() has not been implemented.',
    );
  }

  /// See `BarikoiTrace.android.isIgnoringBatteryOptimizations`.
  Future<bool> androidIsIgnoringBatteryOptimizations() {
    throw UnimplementedError(
      'androidIsIgnoringBatteryOptimizations() has not been implemented.',
    );
  }

  /// See `BarikoiTrace.android.openAutostartSettings`.
  Future<void> androidOpenAutostartSettings() {
    throw UnimplementedError(
      'androidOpenAutostartSettings() has not been implemented.',
    );
  }

  // --- iOS-only ---

  /// See `BarikoiTrace.ios.setLocationDisabledNotificationEnabled`.
  Future<void> iosSetLocationDisabledNotificationEnabled(bool enabled) {
    throw UnimplementedError(
      'iosSetLocationDisabledNotificationEnabled() has not been implemented.',
    );
  }
}
