import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/trace_config.dart';
import '../models/trace_exception.dart';
import '../models/trace_location.dart';
import '../models/trace_log_entry.dart';
import '../models/trace_mode.dart';
import '../models/trace_user.dart';
import '../platform_interface/barikoi_trace_platform.dart';
import 'codecs.dart';

/// The default [BarikoiTracePlatform], talking to the Android and iOS SDKs
/// over one method channel and two event channels.
///
/// Every native failure arrives as a [PlatformException] and leaves this class
/// as a [TraceException] whose `code` is the platform's code **verbatim** —
/// there is no mapping table, so a code the natives add later reaches host
/// apps without a plugin release.
class MethodChannelBarikoiTrace extends BarikoiTracePlatform {
  /// The channel every request/response call goes over.
  @visibleForTesting
  final MethodChannel methodChannel =
      const MethodChannel('barikoi_trace_flutter/methods');

  /// Live location fixes, gated by `setBroadcastingEnabled(true)`.
  @visibleForTesting
  final EventChannel locationEventChannel =
      const EventChannel('barikoi_trace_flutter/location_updates');

  /// The native SDK's internal debug log.
  @visibleForTesting
  final EventChannel logEventChannel =
      const EventChannel('barikoi_trace_flutter/logs');

  Stream<TraceLocation>? _locationUpdates;
  Stream<TraceLogEntry>? _logs;

  /// The one place a [PlatformException] becomes a [TraceException].
  ///
  /// [T] is constrained to `Object` so that `void` can never be substituted —
  /// callers that do not care about the result ask for `Object` and discard
  /// it, which keeps a single implementation for value-returning and
  /// void-returning calls.
  Future<T?> _invoke<T extends Object>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await methodChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw TraceException(code: e.code, message: e.message ?? '');
    }
  }

  /// Maps event-channel errors the same way [_invoke] maps call errors, and
  /// decodes each event with [decode]. Preserves the broadcast nature of the
  /// underlying stream.
  static StreamTransformer<Object?, T> _events<T>(T Function(Object?) decode) {
    return StreamTransformer<Object?, T>.fromHandlers(
      handleData: (Object? data, EventSink<T> sink) => sink.add(decode(data)),
      handleError: (Object error, StackTrace stackTrace, EventSink<T> sink) {
        if (error is PlatformException) {
          sink.addError(
            TraceException(code: error.code, message: error.message ?? ''),
            stackTrace,
          );
        } else {
          sink.addError(error, stackTrace);
        }
      },
    );
  }

  // --- Init & configuration ---

  @override
  Future<void> initialize(TraceConfig config) =>
      _invoke<Object>('initialize', Codecs.encodeConfig(config));

  @override
  Future<void> setBaseUrl(String url) =>
      _invoke<Object>('setBaseUrl', <String, Object?>{'url': url});

  @override
  Future<void> setMqttUrl(String url) =>
      _invoke<Object>('setMqttUrl', <String, Object?>{'url': url});

  @override
  Future<void> setMqttClientIdPrefix(String prefix) => _invoke<Object>(
        'setMqttClientIdPrefix',
        <String, Object?>{'prefix': prefix},
      );

  @override
  Future<void> resetUrls() => _invoke<Object>('resetUrls');

  // --- User ---

  @override
  Future<TraceUser> setOrCreateUser({
    String? name,
    String? email,
    required String phone,
  }) async {
    final Map<Object?, Object?>? result =
        await _invoke<Map<Object?, Object?>>('setOrCreateUser', <String, Object?>{
      'name': name,
      'email': email,
      'phone': phone,
    });
    if (result == null) {
      throw const TraceException(
        code: TraceErrorCode.noData,
        message: 'setOrCreateUser returned no user.',
      );
    }
    return Codecs.decodeUser(result);
  }

  @override
  Future<TraceUser?> getUser() async {
    final Map<Object?, Object?>? result =
        await _invoke<Map<Object?, Object?>>('getUser');
    return Codecs.decodeUserOrNull(result);
  }

  @override
  Future<String?> getUserId() => _invoke<String>('getUserId');

  // --- Permissions & settings ---

  @override
  Future<bool> isLocationPermissionsGranted() async =>
      await _invoke<bool>('isLocationPermissionsGranted') ?? false;

  @override
  Future<bool> isLocationSettingsOn() async =>
      await _invoke<bool>('isLocationSettingsOn') ?? false;

  @override
  Future<bool> hasBackgroundPermission() async =>
      await _invoke<bool>('hasBackgroundPermission') ?? false;

  @override
  Future<bool> requestLocationPermissions() async =>
      await _invoke<bool>('requestLocationPermissions') ?? false;

  @override
  Future<bool> requestBackgroundLocationPermission() async =>
      await _invoke<bool>('requestBackgroundLocationPermission') ?? false;

  @override
  Future<bool> openLocationSettings() async =>
      await _invoke<bool>('openLocationSettings') ?? false;

  @override
  Future<bool> openAppSettings() async =>
      await _invoke<bool>('openAppSettings') ?? false;

  @override
  Future<bool> isBackgroundTrackingDegraded() async =>
      await _invoke<bool>('isBackgroundTrackingDegraded') ?? false;

  // --- Tracking ---

  @override
  Future<void> setTraceMode(TraceMode mode) => _invoke<Object>(
        'setTraceMode',
        <String, Object?>{'mode': Codecs.encodeMode(mode)},
      );

  @override
  Future<void> startTracking(TraceMode mode, {bool withTrip = false}) =>
      _invoke<Object>('startTracking', <String, Object?>{
        'mode': Codecs.encodeMode(mode),
        'withTrip': withTrip,
      });

  @override
  Future<void> stopTracking() => _invoke<Object>('stopTracking');

  @override
  Future<void> refreshTracking() => _invoke<Object>('refreshTracking');

  @override
  Future<bool> isLocationTracking() async =>
      await _invoke<bool>('isLocationTracking') ?? false;

  @override
  Future<void> setOfflineTracking(bool enabled) => _invoke<Object>(
        'setOfflineTracking',
        <String, Object?>{'enabled': enabled},
      );

  @override
  Future<void> setLoggingEnabled(bool enabled) => _invoke<Object>(
        'setLoggingEnabled',
        <String, Object?>{'enabled': enabled},
      );

  @override
  Future<void> setBroadcastingEnabled(bool enabled) => _invoke<Object>(
        'setBroadcastingEnabled',
        <String, Object?>{'enabled': enabled},
      );

  // --- Trips ---

  @override
  Future<bool> isOnTrip() async => await _invoke<bool>('isOnTrip') ?? false;

  @override
  Future<String?> getTripId() => _invoke<String>('getTripId');

  // --- Location ---

  @override
  Future<TraceLocation> updateCurrentLocation() async {
    final Map<Object?, Object?>? result =
        await _invoke<Map<Object?, Object?>>('updateCurrentLocation');
    if (result == null) {
      throw const TraceException(
        code: TraceErrorCode.location,
        message: 'updateCurrentLocation returned no fix.',
      );
    }
    return Codecs.decodeLocation(result);
  }

  @override
  Future<void> uploadOfflineData() => _invoke<Object>('uploadOfflineData');

  @override
  Future<TraceMode> getSettingsFromRemote() async {
    final Map<Object?, Object?>? result =
        await _invoke<Map<Object?, Object?>>('getSettingsFromRemote');
    if (result == null) {
      throw const TraceException(
        code: TraceErrorCode.noData,
        message: 'getSettingsFromRemote returned no settings.',
      );
    }
    return Codecs.decodeMode(result);
  }

  // --- Streams ---

  @override
  Stream<TraceLocation> get locationUpdates => _locationUpdates ??=
      locationEventChannel
          .receiveBroadcastStream()
          .transform(_events<TraceLocation>(Codecs.decodeLocation));

  @override
  Stream<TraceLogEntry> get logs => _logs ??= logEventChannel
      .receiveBroadcastStream()
      .transform(_events<TraceLogEntry>(Codecs.decodeLogEntry));

  // --- Android-only ---

  @override
  Future<bool> androidRequestNotificationPermission() async =>
      await _invoke<bool>('android.requestNotificationPermission') ?? false;

  @override
  Future<void> androidRequestDisableBatteryOptimization({
    bool onlyIfNeeded = false,
  }) =>
      _invoke<Object>(
        'android.requestDisableBatteryOptimization',
        <String, Object?>{'onlyIfNeeded': onlyIfNeeded},
      );

  @override
  Future<bool> androidIsIgnoringBatteryOptimizations() async =>
      await _invoke<bool>('android.isIgnoringBatteryOptimizations') ?? false;

  @override
  Future<void> androidOpenAutostartSettings() =>
      _invoke<Object>('android.openAutostartSettings');

  // --- iOS-only ---

  @override
  Future<void> iosSetLocationDisabledNotificationEnabled(bool enabled) =>
      _invoke<Object>(
        'ios.setLocationDisabledNotificationEnabled',
        <String, Object?>{'enabled': enabled},
      );
}
