import 'package:barikoi_trace_flutter/barikoi_trace_flutter.dart';
import 'package:barikoi_trace_flutter/src/method_channel/codecs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _methods = MethodChannel('barikoi_trace_flutter/methods');
const EventChannel _locationEvents =
    EventChannel('barikoi_trace_flutter/location_updates');
const EventChannel _logEvents = EventChannel('barikoi_trace_flutter/logs');

const Map<String, Object?> _userMap = <String, Object?>{
  'userId': 'u-1',
  'name': 'Jane',
  'email': 'jane@example.com',
  'phone': '01700000000',
  'companyId': 'c-1',
  'group': 'riders',
  'lastLat': 23.8103,
  'lastLon': 90.4125,
  'updatedAt': 1700000000000,
};

const Map<String, Object?> _locationMap = <String, Object?>{
  'latitude': 23.8103,
  'longitude': 90.4125,
  'altitude': 4.0,
  'accuracy': 9.5,
  'verticalAccuracy': 3.0,
  'speed': 1.5,
  'bearing': 90.0,
  'timestampMs': 1700000000000,
  'isMock': false,
  'provider': 'fused',
};

/// Every method whose contract is `-> bool`.
const List<String> _boolMethods = <String>[
  'isLocationPermissionsGranted',
  'isLocationSettingsOn',
  'hasBackgroundPermission',
  'requestLocationPermissions',
  'requestBackgroundLocationPermission',
  'openLocationSettings',
  'openAppSettings',
  'isBackgroundTrackingDegraded',
  'isLocationTracking',
  'isOnTrip',
  'android.requestNotificationPermission',
  'android.isIgnoringBatteryOptimizations',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MethodChannelBarikoiTrace platform;
  late List<MethodCall> log;
  late Object? Function(MethodCall call) respond;

  Object? defaultResponse(MethodCall call) {
    if (_boolMethods.contains(call.method)) return true;
    switch (call.method) {
      case 'setOrCreateUser':
      case 'getUser':
        return _userMap;
      case 'getUserId':
        return 'u-1';
      case 'getTripId':
        return 'trip-1';
      case 'updateCurrentLocation':
        return _locationMap;
      case 'getSettingsFromRemote':
        return TraceMode.reactive.toMap();
      default:
        return null;
    }
  }

  setUp(() {
    platform = MethodChannelBarikoiTrace();
    log = <MethodCall>[];
    respond = defaultResponse;
    messenger.setMockMethodCallHandler(_methods, (MethodCall call) async {
      log.add(call);
      return respond(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockStreamHandler(_locationEvents, null);
    messenger.setMockStreamHandler(_logEvents, null);
  });

  MethodCall single() {
    expect(log, hasLength(1), reason: 'expected exactly one platform call');
    return log.single;
  }

  Map<String, Object?> args() => Codecs.asWireMap(single().arguments);

  group('channel names', () {
    test('the plugin uses the three documented channels', () {
      expect(platform.methodChannel.name, 'barikoi_trace_flutter/methods');
      expect(
        platform.locationEventChannel.name,
        'barikoi_trace_flutter/location_updates',
      );
      expect(platform.logEventChannel.name, 'barikoi_trace_flutter/logs');
    });
  });

  group('init & configuration', () {
    test('initialize sends the flattened config', () async {
      await platform.initialize(const TraceConfig(
        apiKey: 'k',
        mqttUsername: 'u',
        mqttPassword: 'p',
        baseUrl: 'https://api.example.com/',
        mqttUrl: 'ssl://broker.example.com:8883',
        mqttClientIdPrefix: 'fleet-',
      ));

      expect(single().method, 'initialize');
      expect(args(), <String, Object?>{
        'apiKey': 'k',
        'mqttUsername': 'u',
        'mqttPassword': 'p',
        'baseUrl': 'https://api.example.com/',
        'mqttUrl': 'ssl://broker.example.com:8883',
        'mqttClientIdPrefix': 'fleet-',
      });
    });

    test('initialize sends null endpoints when they are unset', () async {
      await platform.initialize(const TraceConfig(
        apiKey: 'k',
        mqttUsername: 'u',
        mqttPassword: 'p',
      ));

      final Map<String, Object?> sent = args();
      expect(sent.containsKey('baseUrl'), isTrue);
      expect(sent['baseUrl'], isNull);
      expect(sent['mqttUrl'], isNull);
      expect(sent['mqttClientIdPrefix'], isNull);
    });

    test('setBaseUrl', () async {
      await platform.setBaseUrl('https://api.example.com/');
      expect(single().method, 'setBaseUrl');
      expect(args(), <String, Object?>{'url': 'https://api.example.com/'});
    });

    test('setMqttUrl', () async {
      await platform.setMqttUrl('ssl://broker.example.com:8883');
      expect(single().method, 'setMqttUrl');
      expect(
        args(),
        <String, Object?>{'url': 'ssl://broker.example.com:8883'},
      );
    });

    test('setMqttClientIdPrefix', () async {
      await platform.setMqttClientIdPrefix('fleet-');
      expect(single().method, 'setMqttClientIdPrefix');
      expect(args(), <String, Object?>{'prefix': 'fleet-'});
    });

    test('resetUrls takes no arguments', () async {
      await platform.resetUrls();
      expect(single().method, 'resetUrls');
      expect(single().arguments, isNull);
    });
  });

  group('user', () {
    test('setOrCreateUser sends all three fields and decodes the user',
        () async {
      final TraceUser user = await platform.setOrCreateUser(
        name: 'Jane',
        email: 'jane@example.com',
        phone: '01700000000',
      );

      expect(single().method, 'setOrCreateUser');
      expect(args(), <String, Object?>{
        'name': 'Jane',
        'email': 'jane@example.com',
        'phone': '01700000000',
      });
      expect(user.userId, 'u-1');
      expect(user.companyId, 'c-1');
      expect(user.updatedAt.millisecondsSinceEpoch, 1700000000000);
    });

    test('setOrCreateUser sends explicit nulls for the optional fields',
        () async {
      await platform.setOrCreateUser(phone: '01700000000');
      final Map<String, Object?> sent = args();
      expect(sent.containsKey('name'), isTrue);
      expect(sent['name'], isNull);
      expect(sent['email'], isNull);
      expect(sent['phone'], '01700000000');
    });

    test('setOrCreateUser throws NO_DATA when the platform returns null',
        () async {
      respond = (MethodCall call) => null;
      await expectLater(
        platform.setOrCreateUser(phone: '01700000000'),
        throwsA(
          isA<TraceException>()
              .having((TraceException e) => e.code, 'code', 'NO_DATA'),
        ),
      );
    });

    test('getUser decodes a user', () async {
      final TraceUser? user = await platform.getUser();
      expect(single().method, 'getUser');
      expect(single().arguments, isNull);
      expect(user?.userId, 'u-1');
    });

    test('getUser returns null when no user exists', () async {
      respond = (MethodCall call) => null;
      expect(await platform.getUser(), isNull);
    });

    test('getUserId', () async {
      expect(await platform.getUserId(), 'u-1');
      expect(single().method, 'getUserId');
      expect(single().arguments, isNull);
    });

    test('getUserId returns null when there is no user', () async {
      respond = (MethodCall call) => null;
      expect(await platform.getUserId(), isNull);
    });
  });

  group('permissions & settings', () {
    test('each boolean call sends no arguments and returns the platform value',
        () async {
      final Map<String, Future<bool> Function()> calls =
          <String, Future<bool> Function()>{
        'isLocationPermissionsGranted': platform.isLocationPermissionsGranted,
        'isLocationSettingsOn': platform.isLocationSettingsOn,
        'hasBackgroundPermission': platform.hasBackgroundPermission,
        'requestLocationPermissions': platform.requestLocationPermissions,
        'requestBackgroundLocationPermission':
            platform.requestBackgroundLocationPermission,
        'openLocationSettings': platform.openLocationSettings,
        'openAppSettings': platform.openAppSettings,
        'isBackgroundTrackingDegraded': platform.isBackgroundTrackingDegraded,
        'isLocationTracking': platform.isLocationTracking,
        'isOnTrip': platform.isOnTrip,
      };

      for (final MapEntry<String, Future<bool> Function()> entry
          in calls.entries) {
        log.clear();
        expect(await entry.value(), isTrue, reason: entry.key);
        expect(single().method, entry.key);
        expect(single().arguments, isNull, reason: entry.key);
      }
    });

    test('a null platform answer degrades to false, never to an exception',
        () async {
      respond = (MethodCall call) => null;
      expect(await platform.isLocationPermissionsGranted(), isFalse);
      expect(await platform.isLocationSettingsOn(), isFalse);
      expect(await platform.hasBackgroundPermission(), isFalse);
      expect(await platform.isBackgroundTrackingDegraded(), isFalse);
      expect(await platform.isLocationTracking(), isFalse);
      expect(await platform.isOnTrip(), isFalse);
    });
  });

  group('tracking', () {
    test('setTraceMode nests the mode under "mode"', () async {
      await platform.setTraceMode(TraceMode.passive);
      expect(single().method, 'setTraceMode');
      expect(
        Codecs.asWireMap(args()['mode']),
        TraceMode.passive.toMap(),
      );
    });

    test('startTracking defaults withTrip to false', () async {
      await platform.startTracking(TraceMode.active);
      expect(single().method, 'startTracking');
      expect(args()['withTrip'], isFalse);
      expect(Codecs.asWireMap(args()['mode']), TraceMode.active.toMap());
    });

    test('startTracking passes withTrip through', () async {
      await platform.startTracking(TraceMode.active, withTrip: true);
      expect(args()['withTrip'], isTrue);
    });

    test('startTracking preserves the null time sentinel', () async {
      final TraceMode mode = TraceModeBuilder()
          .setUpdateInterval(30)
          .setStartTime(const TraceTimeOfDay(hour: 9))
          .build();

      await platform.startTracking(mode);
      final Map<String, Object?> sent = Codecs.asWireMap(args()['mode']);
      expect(sent['startTime'], '09:00:00');
      expect(sent.containsKey('endTime'), isTrue);
      expect(sent['endTime'], isNull);
    });

    test('stopTracking / refreshTracking / uploadOfflineData take no args',
        () async {
      final Map<String, Future<void> Function()> calls =
          <String, Future<void> Function()>{
        'stopTracking': platform.stopTracking,
        'refreshTracking': platform.refreshTracking,
        'uploadOfflineData': platform.uploadOfflineData,
      };

      for (final MapEntry<String, Future<void> Function()> entry
          in calls.entries) {
        log.clear();
        await entry.value();
        expect(single().method, entry.key);
        expect(single().arguments, isNull, reason: entry.key);
      }
    });

    test('the three toggles all send {"enabled": bool}', () async {
      final Map<String, Future<void> Function(bool)> calls =
          <String, Future<void> Function(bool)>{
        'setOfflineTracking': platform.setOfflineTracking,
        'setLoggingEnabled': platform.setLoggingEnabled,
        'setBroadcastingEnabled': platform.setBroadcastingEnabled,
      };

      for (final MapEntry<String, Future<void> Function(bool)> entry
          in calls.entries) {
        log.clear();
        await entry.value(true);
        expect(single().method, entry.key);
        expect(args(), <String, Object?>{'enabled': true}, reason: entry.key);
      }
    });
  });

  group('trips & location', () {
    test('getTripId', () async {
      expect(await platform.getTripId(), 'trip-1');
      expect(single().method, 'getTripId');
      expect(single().arguments, isNull);
    });

    test('getTripId is null when no trip is open', () async {
      respond = (MethodCall call) => null;
      expect(await platform.getTripId(), isNull);
    });

    test('updateCurrentLocation decodes a fix', () async {
      final TraceLocation fix = await platform.updateCurrentLocation();
      expect(single().method, 'updateCurrentLocation');
      expect(single().arguments, isNull);
      expect(fix.latitude, 23.8103);
      expect(fix.longitude, 90.4125);
      expect(fix.accuracy, 9.5);
      expect(fix.provider, 'fused');
      expect(fix.timestamp.millisecondsSinceEpoch, 1700000000000);
    });

    test('updateCurrentLocation throws LOCATION on a null answer', () async {
      respond = (MethodCall call) => null;
      await expectLater(
        platform.updateCurrentLocation(),
        throwsA(
          isA<TraceException>()
              .having((TraceException e) => e.code, 'code', 'LOCATION'),
        ),
      );
    });

    test('getSettingsFromRemote decodes a mode', () async {
      final TraceMode mode = await platform.getSettingsFromRemote();
      expect(single().method, 'getSettingsFromRemote');
      expect(single().arguments, isNull);
      expect(mode, TraceMode.reactive);
    });

    test('getSettingsFromRemote throws NO_DATA on a null answer', () async {
      respond = (MethodCall call) => null;
      await expectLater(
        platform.getSettingsFromRemote(),
        throwsA(
          isA<TraceException>()
              .having((TraceException e) => e.code, 'code', 'NO_DATA'),
        ),
      );
    });
  });

  group('platform-specific methods are namespaced', () {
    test('android.requestNotificationPermission', () async {
      expect(await platform.androidRequestNotificationPermission(), isTrue);
      expect(single().method, 'android.requestNotificationPermission');
      expect(single().arguments, isNull);
    });

    test('android.requestDisableBatteryOptimization', () async {
      await platform.androidRequestDisableBatteryOptimization();
      expect(single().method, 'android.requestDisableBatteryOptimization');
      expect(args(), <String, Object?>{'onlyIfNeeded': false});

      log.clear();
      await platform.androidRequestDisableBatteryOptimization(
        onlyIfNeeded: true,
      );
      expect(args(), <String, Object?>{'onlyIfNeeded': true});
    });

    test('android.isIgnoringBatteryOptimizations', () async {
      expect(await platform.androidIsIgnoringBatteryOptimizations(), isTrue);
      expect(single().method, 'android.isIgnoringBatteryOptimizations');
      expect(single().arguments, isNull);
    });

    test('android.openAutostartSettings', () async {
      await platform.androidOpenAutostartSettings();
      expect(single().method, 'android.openAutostartSettings');
      expect(single().arguments, isNull);
    });

    test('ios.setLocationDisabledNotificationEnabled', () async {
      await platform.iosSetLocationDisabledNotificationEnabled(false);
      expect(single().method, 'ios.setLocationDisabledNotificationEnabled');
      expect(args(), <String, Object?>{'enabled': false});
    });
  });

  group('error mapping', () {
    test('a PlatformException becomes a TraceException, code verbatim',
        () async {
      respond = (MethodCall call) {
        throw PlatformException(
          code: 'NO_KEY',
          message: 'API key not set. Call initialize() first.',
        );
      };

      await expectLater(
        platform.getSettingsFromRemote(),
        throwsA(
          isA<TraceException>()
              .having((TraceException e) => e.code, 'code', 'NO_KEY')
              .having(
                (TraceException e) => e.message,
                'message',
                'API key not set. Call initialize() first.',
              ),
        ),
      );
    });

    test('an unmodelled code is passed through rather than remapped', () async {
      respond = (MethodCall call) {
        throw PlatformException(code: 'SOMETHING_NEW', message: 'from native');
      };

      await expectLater(
        platform.stopTracking(),
        throwsA(
          isA<TraceException>()
              .having((TraceException e) => e.code, 'code', 'SOMETHING_NEW')
              .having((TraceException e) => e.message, 'message', 'from native'),
        ),
      );
    });

    test('a null native message becomes an empty string', () async {
      respond = (MethodCall call) {
        throw PlatformException(code: 'INTERNAL');
      };

      await expectLater(
        platform.uploadOfflineData(),
        throwsA(
          isA<TraceException>()
              .having((TraceException e) => e.code, 'code', 'INTERNAL')
              .having((TraceException e) => e.message, 'message', ''),
        ),
      );
    });

    test('every entry point funnels through the same mapping', () async {
      respond = (MethodCall call) {
        throw PlatformException(code: 'PERMISSION', message: 'denied');
      };

      final List<Future<void> Function()> calls = <Future<void> Function()>[
        () => platform.initialize(const TraceConfig(
              apiKey: 'k',
              mqttUsername: 'u',
              mqttPassword: 'p',
            )),
        () => platform.setBaseUrl('https://x/'),
        () => platform.setMqttUrl('ssl://x:8883'),
        () => platform.setMqttClientIdPrefix('p-'),
        () => platform.resetUrls(),
        () => platform.setOrCreateUser(phone: '017'),
        () => platform.getUser(),
        () => platform.getUserId(),
        () => platform.isLocationPermissionsGranted(),
        () => platform.isLocationSettingsOn(),
        () => platform.hasBackgroundPermission(),
        () => platform.requestLocationPermissions(),
        () => platform.requestBackgroundLocationPermission(),
        () => platform.openLocationSettings(),
        () => platform.openAppSettings(),
        () => platform.isBackgroundTrackingDegraded(),
        () => platform.setTraceMode(TraceMode.active),
        () => platform.startTracking(TraceMode.active),
        () => platform.stopTracking(),
        () => platform.refreshTracking(),
        () => platform.isLocationTracking(),
        () => platform.setOfflineTracking(true),
        () => platform.setLoggingEnabled(true),
        () => platform.setBroadcastingEnabled(true),
        () => platform.isOnTrip(),
        () => platform.getTripId(),
        () => platform.updateCurrentLocation(),
        () => platform.uploadOfflineData(),
        () => platform.getSettingsFromRemote(),
        () => platform.androidRequestNotificationPermission(),
        () => platform.androidRequestDisableBatteryOptimization(),
        () => platform.androidIsIgnoringBatteryOptimizations(),
        () => platform.androidOpenAutostartSettings(),
        () => platform.iosSetLocationDisabledNotificationEnabled(true),
      ];

      for (final Future<void> Function() call in calls) {
        await expectLater(
          call(),
          throwsA(
            isA<TraceException>()
                .having((TraceException e) => e.code, 'code', 'PERMISSION'),
          ),
        );
      }
    });
  });

  group('event channels', () {
    test('locationUpdates decodes fixes off the location channel', () async {
      messenger.setMockStreamHandler(
        _locationEvents,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            events.success(_locationMap);
            events.endOfStream();
          },
        ),
      );

      final TraceLocation fix = await platform.locationUpdates.first;
      expect(fix.latitude, 23.8103);
      expect(fix.longitude, 90.4125);
      expect(fix.speed, 1.5);
      expect(fix.bearing, 90.0);
      expect(fix.isMock, isFalse);
    });

    test('locationUpdates is broadcast and created only once', () async {
      messenger.setMockStreamHandler(
        _locationEvents,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            events.success(_locationMap);
          },
        ),
      );

      final Stream<TraceLocation> first = platform.locationUpdates;
      final Stream<TraceLocation> second = platform.locationUpdates;
      expect(identical(first, second), isTrue);
      expect(first.isBroadcast, isTrue);

      final TraceLocation fix = await first.first;
      expect(fix.latitude, 23.8103);
    });

    test('a stream error is mapped to TraceException too', () async {
      messenger.setMockStreamHandler(
        _locationEvents,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            events.error(code: 'PERMISSION', message: 'denied');
            events.endOfStream();
          },
        ),
      );

      await expectLater(
        platform.locationUpdates.first,
        throwsA(
          isA<TraceException>()
              .having((TraceException e) => e.code, 'code', 'PERMISSION')
              .having((TraceException e) => e.message, 'message', 'denied'),
        ),
      );
    });

    test('logs decodes entries off the log channel', () async {
      messenger.setMockStreamHandler(
        _logEvents,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            events.success(<String, Object?>{
              'level': 'WARN',
              'tag': 'TraceConfig',
              'message': 'mqttUrl is plaintext',
              'timestampMs': 1700000000000,
            });
            events.endOfStream();
          },
        ),
      );

      final TraceLogEntry entry = await platform.logs.first;
      expect(entry.level, 'WARN');
      expect(entry.tag, 'TraceConfig');
      expect(entry.message, 'mqttUrl is plaintext');
      expect(entry.timestamp.millisecondsSinceEpoch, 1700000000000);
      expect(platform.logs.isBroadcast, isTrue);
    });
  });
}
