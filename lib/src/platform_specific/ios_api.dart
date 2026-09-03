import 'package:flutter/foundation.dart';

import '../platform_interface/barikoi_trace_platform.dart';

/// iOS-only calls, reached through `BarikoiTrace.ios`.
///
/// On any non-iOS platform each call no-ops rather than throwing, so
/// cross-platform code can call them unconditionally.
class BarikoiTraceIos {
  const BarikoiTraceIos._();

  /// The singleton reached through `BarikoiTrace.ios`.
  static const BarikoiTraceIos instance = BarikoiTraceIos._();

  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  /// Controls whether the SDK posts a local notification when location
  /// services are switched off while tracking.
  ///
  /// This is the iOS port of Android's unconditional "Need to turn on location
  /// service" notification. It is **on by default**, and the first post asks
  /// the user for notification authorization — pass `false` before
  /// `startTracking` to suppress both the notification and that prompt.
  ///
  /// Does nothing on non-iOS platforms.
  Future<void> setLocationDisabledNotificationEnabled(bool enabled) {
    if (!_isIos) return Future<void>.value();
    return BarikoiTracePlatform.instance
        .iosSetLocationDisabledNotificationEnabled(enabled);
  }
}
