import 'package:flutter/foundation.dart';

import '../platform_interface/barikoi_trace_platform.dart';

/// Android-only calls, reached through `BarikoiTrace.android`.
///
/// Every method here exists to work around something specific to Android —
/// the `POST_NOTIFICATIONS` runtime permission, Doze/App Standby battery
/// optimization, and OEM autostart managers. None of them has an iOS
/// counterpart.
///
/// On any non-Android platform each call **no-ops and returns a benign value**
/// (`false`, or nothing) rather than throwing, so cross-platform code can call
/// them unconditionally:
///
/// ```dart
/// await BarikoiTrace.android.requestNotificationPermission();
/// await BarikoiTrace.android.requestDisableBatteryOptimization(
///   onlyIfNeeded: true,
/// );
/// ```
class BarikoiTraceAndroid {
  const BarikoiTraceAndroid._();

  /// The singleton reached through `BarikoiTrace.android`.
  static const BarikoiTraceAndroid instance = BarikoiTraceAndroid._();

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// Requests the `POST_NOTIFICATIONS` runtime permission, required on API 33+
  /// for the foreground-service notification the SDK posts while tracking.
  ///
  /// Returns whether the permission is granted once the prompt resolves — and
  /// `true` on API levels below 33, where it is granted at install time.
  /// Returns `false` on non-Android platforms.
  Future<bool> requestNotificationPermission() {
    if (!_isAndroid) return Future<bool>.value(false);
    return BarikoiTracePlatform.instance.androidRequestNotificationPermission();
  }

  /// Opens the system dialog asking the user to exempt this app from battery
  /// optimization, which Doze would otherwise use to throttle background
  /// location work.
  ///
  /// With [onlyIfNeeded] set, the dialog is skipped when the app is already
  /// exempt — worth passing so a resumed app does not re-prompt on every
  /// launch. Does nothing on non-Android platforms.
  Future<void> requestDisableBatteryOptimization({
    bool onlyIfNeeded = false,
  }) {
    if (!_isAndroid) return Future<void>.value();
    return BarikoiTracePlatform.instance
        .androidRequestDisableBatteryOptimization(onlyIfNeeded: onlyIfNeeded);
  }

  /// Whether the app is currently exempt from battery optimization.
  ///
  /// Renamed, not inverted. The native `isBatteryOptimizationEnabled()` is a
  /// misnomer — it returns `PowerManager.isIgnoringBatteryOptimizations()`,
  /// i.e. `true` already means "exempt, healthy". This name says what the
  /// value actually is. Returns `false` on non-Android platforms.
  Future<bool> isIgnoringBatteryOptimizations() {
    if (!_isAndroid) return Future<bool>.value(false);
    return BarikoiTracePlatform.instance
        .androidIsIgnoringBatteryOptimizations();
  }

  /// Opens the OEM autostart / protected-apps screen on the vendors that ship
  /// one (Xiaomi, Oppo, Vivo, Huawei and friends), where the user must
  /// whitelist the app or the OEM will kill its background service.
  ///
  /// A no-op on stock Android — there is no such screen to open — and on
  /// non-Android platforms.
  Future<void> openAutostartSettings() {
    if (!_isAndroid) return Future<void>.value();
    return BarikoiTracePlatform.instance.androidOpenAutostartSettings();
  }
}
