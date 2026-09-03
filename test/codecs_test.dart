import 'package:barikoi_trace_flutter/barikoi_trace_flutter.dart';
import 'package:barikoi_trace_flutter/src/method_channel/codecs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('asWireMap', () {
    test('passes an already-typed map straight through', () {
      const Map<String, Object?> map = <String, Object?>{'a': 1};
      expect(identical(Codecs.asWireMap(map), map), isTrue);
    });

    test('normalizes the Map<Object?, Object?> the channels actually deliver',
        () {
      final Map<Object?, Object?> wire = <Object?, Object?>{
        'latitude': 23.8,
        'provider': 'gps',
      };
      expect(Codecs.asWireMap(wire), <String, Object?>{
        'latitude': 23.8,
        'provider': 'gps',
      });
    });

    test('drops non-string keys instead of throwing', () {
      final Map<Object?, Object?> wire = <Object?, Object?>{
        'ok': 1,
        7: 'dropped',
        null: 'dropped',
      };
      expect(Codecs.asWireMap(wire), <String, Object?>{'ok': 1});
    });

    test('null and non-maps decode to an empty map', () {
      expect(Codecs.asWireMap(null), isEmpty);
      expect(Codecs.asWireMap('nope'), isEmpty);
      expect(Codecs.asWireMap(<Object?>[1, 2]), isEmpty);
    });
  });

  group('primitives', () {
    test('asInt accepts any num, since iOS may send a double', () {
      expect(Codecs.asInt(5), 5);
      expect(Codecs.asInt(5.9), 5);
      expect(Codecs.asInt(null), 0);
      expect(Codecs.asInt('5'), 0);
      expect(Codecs.asInt(null, fallback: 100), 100);
    });

    test('asBool', () {
      expect(Codecs.asBool(true), isTrue);
      expect(Codecs.asBool(null), isFalse);
      expect(Codecs.asBool('true'), isFalse);
      expect(Codecs.asBool(null, fallback: true), isTrue);
    });

    test('asDoubleOrNull widens ints', () {
      expect(Codecs.asDoubleOrNull(3), 3.0);
      expect(Codecs.asDoubleOrNull(3.5), 3.5);
      expect(Codecs.asDoubleOrNull(null), isNull);
      expect(Codecs.asDoubleOrNull('3.5'), isNull);
    });

    test('asStringOrNull', () {
      expect(Codecs.asStringOrNull('x'), 'x');
      expect(Codecs.asStringOrNull(null), isNull);
      expect(Codecs.asStringOrNull(7), isNull);
    });
  });

  group('the daily-window time sentinel', () {
    test('null encodes as null, never as 00:00:00 or 23:59:59', () {
      expect(Codecs.encodeTime(null), isNull);
    });

    test('a time encodes as HH:mm:ss', () {
      expect(
        Codecs.encodeTime(const TraceTimeOfDay(hour: 7, minute: 8, second: 9)),
        '07:08:09',
      );
      expect(Codecs.encodeTime(TraceTimeOfDay.midnight), '00:00:00');
      expect(Codecs.encodeTime(TraceTimeOfDay.endOfDay), '23:59:59');
    });

    test('decodeTime maps null, wrong types and garbage back to null', () {
      expect(Codecs.decodeTime(null), isNull);
      expect(Codecs.decodeTime(0), isNull);
      expect(Codecs.decodeTime('half past four'), isNull);
      expect(Codecs.decodeTime('25:00:00'), isNull);
    });

    test('decodeTime round-trips a real time', () {
      expect(
        Codecs.decodeTime('07:08:09'),
        const TraceTimeOfDay(hour: 7, minute: 8, second: 9),
      );
    });
  });

  group('models', () {
    test('encodeConfig / encodeMode delegate to the model encoders', () {
      const TraceConfig config = TraceConfig(
        apiKey: 'k',
        mqttUsername: 'u',
        mqttPassword: 'p',
      );
      expect(Codecs.encodeConfig(config), config.toMap());
      expect(Codecs.encodeMode(TraceMode.reactive), TraceMode.reactive.toMap());
    });

    test('decodeMode reads a Map<Object?, Object?>', () {
      final TraceMode mode = Codecs.decodeMode(<Object?, Object?>{
        'desiredAccuracy': 'LOW',
        'updateInterval': 30,
        'distanceFilter': 25,
        'stopDuration': 4,
        'accuracyFilter': 80,
        'trackingMode': 3,
        'offline': false,
        'debug': true,
        'pingSyncInterval': 60,
        'startTime': '09:00:00',
        'endTime': null,
      });

      expect(mode.desiredAccuracy, DesiredAccuracy.low);
      expect(mode.updateInterval, 30);
      expect(mode.distanceFilter, 25);
      expect(mode.stopDuration, 4);
      expect(mode.accuracyFilter, 80);
      expect(mode.trackingMode, TrackingMode.custom);
      expect(mode.offline, isFalse);
      expect(mode.debug, isTrue);
      expect(mode.pingSyncInterval, 60);
      expect(mode.startTime, const TraceTimeOfDay(hour: 9));
      expect(mode.endTime, isNull);
    });

    test('decodeUserOrNull returns null for a null payload', () {
      expect(Codecs.decodeUserOrNull(null), isNull);
    });

    test('decodeUser reads every field and converts epoch ms to UTC', () {
      final TraceUser user = Codecs.decodeUser(<Object?, Object?>{
        'userId': 'u-1',
        'name': 'Jane',
        'email': 'jane@example.com',
        'phone': '01700000000',
        'companyId': 'c-1',
        'group': 'riders',
        'lastLat': 23.8103,
        'lastLon': 90.4125,
        'updatedAt': 1700000000000,
      });

      expect(user.userId, 'u-1');
      expect(user.name, 'Jane');
      expect(user.email, 'jane@example.com');
      expect(user.phone, '01700000000');
      expect(user.companyId, 'c-1');
      expect(user.group, 'riders');
      expect(user.lastLat, 23.8103);
      expect(user.lastLon, 90.4125);
      expect(user.updatedAt.isUtc, isTrue);
      expect(user.updatedAt.millisecondsSinceEpoch, 1700000000000);
    });

    test('decodeUser tolerates a sparse map', () {
      final TraceUser user =
          Codecs.decodeUser(<Object?, Object?>{'userId': 'u-2'});
      expect(user.userId, 'u-2');
      expect(user.name, isNull);
      expect(user.lastLat, 0);
      expect(user.lastLon, 0);
      expect(user.updatedAt.millisecondsSinceEpoch, 0);
    });

    test('decodeLocation reads every field', () {
      final TraceLocation fix = Codecs.decodeLocation(<Object?, Object?>{
        'latitude': 23.8103,
        'longitude': 90.4125,
        'altitude': 12,
        'accuracy': 8.5,
        'verticalAccuracy': 3.0,
        'speed': 1.25,
        'bearing': 270.0,
        'timestampMs': 1700000000000,
        'isMock': false,
        'provider': 'fused',
      });

      expect(fix.latitude, 23.8103);
      expect(fix.longitude, 90.4125);
      expect(fix.altitude, 12.0);
      expect(fix.accuracy, 8.5);
      expect(fix.verticalAccuracy, 3.0);
      expect(fix.speed, 1.25);
      expect(fix.bearing, 270.0);
      expect(fix.timestamp.isUtc, isTrue);
      expect(fix.timestamp.millisecondsSinceEpoch, 1700000000000);
      expect(fix.isMock, isFalse);
      expect(fix.provider, 'fused');
    });

    test('absent optional location fields decode to null, not 0', () {
      final TraceLocation fix = Codecs.decodeLocation(<Object?, Object?>{
        'latitude': 1.0,
        'longitude': 2.0,
        'timestampMs': 5,
      });

      expect(fix.altitude, 0);
      expect(fix.accuracy, 0);
      expect(fix.verticalAccuracy, isNull);
      expect(fix.speed, isNull);
      expect(fix.bearing, isNull);
      expect(fix.isMock, isNull);
      expect(fix.provider, isNull);
    });

    test('decodeLogEntry', () {
      final TraceLogEntry entry = Codecs.decodeLogEntry(<Object?, Object?>{
        'level': 'WARN',
        'tag': 'TraceConfig',
        'message': 'mqttUrl is plaintext',
        'timestampMs': 1700000000000,
      });

      expect(entry.level, 'WARN');
      expect(entry.tag, 'TraceConfig');
      expect(entry.message, 'mqttUrl is plaintext');
      expect(entry.timestamp.millisecondsSinceEpoch, 1700000000000);
      expect(entry.toString(), '[WARN] TraceConfig: mqttUrl is plaintext');
    });

    test('log entries round-trip through toMap', () {
      final TraceLogEntry entry = TraceLogEntry(
        level: 'INFO',
        tag: 'Trace',
        message: 'hello',
        timestamp: DateTime.fromMillisecondsSinceEpoch(42, isUtc: true),
      );
      expect(Codecs.decodeLogEntry(entry.toMap()), entry);
    });
  });
}
