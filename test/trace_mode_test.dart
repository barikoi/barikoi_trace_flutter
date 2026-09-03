import 'package:barikoi_trace_flutter/barikoi_trace_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('presets match the native SDK values exactly', () {
    // Numbers below are read straight off TraceMode.kt's companion object and
    // TraceMode.swift's static lets. If either native changes, this test is
    // the thing that must be updated first.

    test('active', () {
      const TraceMode mode = TraceMode.active;
      expect(mode.desiredAccuracy, DesiredAccuracy.high);
      expect(mode.updateInterval, 5);
      expect(mode.distanceFilter, 0);
      expect(mode.stopDuration, 0);
      expect(mode.accuracyFilter, 50);
      expect(mode.trackingMode, TrackingMode.active);
      expect(mode.offline, isTrue);
      expect(mode.debug, isFalse);
      expect(mode.pingSyncInterval, 0);
      expect(mode.startTime, isNull);
      expect(mode.endTime, isNull);
    });

    test('passive', () {
      const TraceMode mode = TraceMode.passive;
      expect(mode.desiredAccuracy, DesiredAccuracy.medium);
      expect(mode.updateInterval, 0);
      expect(mode.distanceFilter, 100);
      expect(mode.stopDuration, 0);
      expect(mode.accuracyFilter, 300);
      expect(mode.trackingMode, TrackingMode.passive);
      expect(mode.offline, isTrue);
      expect(mode.debug, isFalse);
      expect(mode.pingSyncInterval, 120);
    });

    test('reactive', () {
      const TraceMode mode = TraceMode.reactive;
      expect(mode.desiredAccuracy, DesiredAccuracy.high);
      expect(mode.updateInterval, 0);
      expect(mode.distanceFilter, 100);
      expect(mode.stopDuration, 0);
      expect(mode.accuracyFilter, 100);
      expect(mode.trackingMode, TrackingMode.reactive);
      expect(mode.offline, isTrue);
      expect(mode.debug, isFalse);
      expect(mode.pingSyncInterval, 30);
    });

    test('default constructor matches the natives’ defaults', () {
      const TraceMode mode = TraceMode();
      expect(mode.desiredAccuracy, DesiredAccuracy.high);
      expect(mode.updateInterval, 0);
      expect(mode.distanceFilter, 0);
      expect(mode.stopDuration, 0);
      expect(mode.accuracyFilter, 100);
      expect(mode.trackingMode, TrackingMode.custom);
      expect(mode.offline, isTrue);
      expect(mode.debug, isFalse);
      expect(mode.pingSyncInterval, 0);
    });
  });

  group('wire enum values', () {
    test('DesiredAccuracy encodes as the native uppercase names', () {
      expect(DesiredAccuracy.high.wireValue, 'HIGH');
      expect(DesiredAccuracy.medium.wireValue, 'MEDIUM');
      expect(DesiredAccuracy.low.wireValue, 'LOW');
    });

    test('DesiredAccuracy.fromWire falls back to high', () {
      expect(DesiredAccuracy.fromWire('MEDIUM'), DesiredAccuracy.medium);
      expect(DesiredAccuracy.fromWire('medium'), DesiredAccuracy.medium);
      expect(DesiredAccuracy.fromWire('NOPE'), DesiredAccuracy.high);
      expect(DesiredAccuracy.fromWire(null), DesiredAccuracy.high);
      expect(DesiredAccuracy.fromWire(3), DesiredAccuracy.high);
    });

    test('TrackingMode options match the native ordinals', () {
      expect(TrackingMode.passive.option, 0);
      expect(TrackingMode.reactive.option, 1);
      expect(TrackingMode.active.option, 2);
      expect(TrackingMode.custom.option, 3);
    });

    test('TrackingMode.fromWire falls back to custom', () {
      expect(TrackingMode.fromWire(2), TrackingMode.active);
      expect(TrackingMode.fromWire(2.0), TrackingMode.active);
      expect(TrackingMode.fromWire(9), TrackingMode.custom);
      expect(TrackingMode.fromWire(null), TrackingMode.custom);
    });
  });

  group('TraceModeBuilder floors', () {
    test('updateInterval is floored at 5', () {
      expect(TraceModeBuilder().setUpdateInterval(0).build().updateInterval, 5);
      expect(TraceModeBuilder().setUpdateInterval(4).build().updateInterval, 5);
      expect(TraceModeBuilder().setUpdateInterval(5).build().updateInterval, 5);
      expect(TraceModeBuilder().setUpdateInterval(60).build().updateInterval, 60);
      expect(
        TraceModeBuilder().setUpdateInterval(-100).build().updateInterval,
        5,
      );
    });

    test('distanceFilter is floored at 10', () {
      expect(TraceModeBuilder().setDistanceFilter(0).build().distanceFilter, 10);
      expect(TraceModeBuilder().setDistanceFilter(9).build().distanceFilter, 10);
      expect(
        TraceModeBuilder().setDistanceFilter(10).build().distanceFilter,
        10,
      );
      expect(
        TraceModeBuilder().setDistanceFilter(250).build().distanceFilter,
        250,
      );
    });

    test('accuracyFilter is floored at 20', () {
      expect(TraceModeBuilder().setAccuracyFilter(0).build().accuracyFilter, 20);
      expect(
        TraceModeBuilder().setAccuracyFilter(19).build().accuracyFilter,
        20,
      );
      expect(
        TraceModeBuilder().setAccuracyFilter(20).build().accuracyFilter,
        20,
      );
      expect(
        TraceModeBuilder().setAccuracyFilter(500).build().accuracyFilter,
        500,
      );
    });

    test('stopDuration and pingSyncInterval are not floored', () {
      final TraceMode mode = TraceModeBuilder()
          .setStopDuration(1)
          .setPingSyncInterval(2)
          .build();
      expect(mode.stopDuration, 1);
      expect(mode.pingSyncInterval, 2);
    });

    test('build() always stamps trackingMode custom', () {
      expect(TraceModeBuilder().build().trackingMode, TrackingMode.custom);
      expect(
        TraceModeBuilder()
            .setDesiredAccuracy(DesiredAccuracy.low)
            .setUpdateInterval(900)
            .build()
            .trackingMode,
        TrackingMode.custom,
      );
    });

    test('builder defaults match the native builders', () {
      final TraceMode mode = TraceModeBuilder().build();
      expect(mode.desiredAccuracy, DesiredAccuracy.high);
      expect(mode.updateInterval, 0);
      expect(mode.distanceFilter, 0);
      expect(mode.stopDuration, 0);
      expect(mode.accuracyFilter, 100);
      expect(mode.offline, isTrue);
      expect(mode.debug, isFalse);
      expect(mode.pingSyncInterval, 0);
      expect(mode.startTime, isNull);
      expect(mode.endTime, isNull);
    });

    test('setDebugModeOn and setOfflineSync', () {
      final TraceMode mode =
          TraceModeBuilder().setDebugModeOn().setOfflineSync(false).build();
      expect(mode.debug, isTrue);
      expect(mode.offline, isFalse);
    });
  });

  group('TraceTimeOfDay', () {
    test('formats as HH:mm:ss', () {
      expect(const TraceTimeOfDay(hour: 0).format(), '00:00:00');
      expect(
        const TraceTimeOfDay(hour: 9, minute: 5, second: 3).format(),
        '09:05:03',
      );
      expect(TraceTimeOfDay.endOfDay.format(), '23:59:59');
    });

    test('parses HH:mm:ss and HH:mm', () {
      expect(
        TraceTimeOfDay.parse('09:05:03'),
        const TraceTimeOfDay(hour: 9, minute: 5, second: 3),
      );
      expect(
        TraceTimeOfDay.parse('18:30'),
        const TraceTimeOfDay(hour: 18, minute: 30),
      );
    });

    test('truncates fractional seconds, so LocalTime.MAX round-trips', () {
      expect(
        TraceTimeOfDay.parse('23:59:59.999999999'),
        TraceTimeOfDay.endOfDay,
      );
    });

    test('tryParse rejects nonsense; parse throws', () {
      expect(TraceTimeOfDay.tryParse(''), isNull);
      expect(TraceTimeOfDay.tryParse('nope'), isNull);
      expect(TraceTimeOfDay.tryParse('24:00:00'), isNull);
      expect(TraceTimeOfDay.tryParse('12:60:00'), isNull);
      expect(TraceTimeOfDay.tryParse('12:00:60'), isNull);
      expect(TraceTimeOfDay.tryParse('1:2:3:4'), isNull);
      expect(() => TraceTimeOfDay.parse('nope'), throwsFormatException);
    });

    test('orders by seconds of day', () {
      expect(const TraceTimeOfDay(hour: 1).secondsOfDay, 3600);
      expect(
        const TraceTimeOfDay(hour: 9).compareTo(const TraceTimeOfDay(hour: 18)),
        lessThan(0),
      );
    });
  });

  group('toMap / fromMap', () {
    test('null times survive the round trip as the no-window sentinel', () {
      const TraceMode mode = TraceMode.active;
      final Map<String, Object?> map = mode.toMap();

      expect(map.containsKey('startTime'), isTrue);
      expect(map.containsKey('endTime'), isTrue);
      expect(map['startTime'], isNull);
      expect(map['endTime'], isNull);

      final TraceMode decoded = TraceMode.fromMap(map);
      expect(decoded.startTime, isNull);
      expect(decoded.endTime, isNull);
      expect(decoded, mode);
    });

    test('explicit times survive the round trip as HH:mm:ss', () {
      final TraceMode mode = TraceModeBuilder()
          .setStartTime(const TraceTimeOfDay(hour: 9))
          .setEndTime(const TraceTimeOfDay(hour: 18, minute: 30, second: 15))
          .build();

      final Map<String, Object?> map = mode.toMap();
      expect(map['startTime'], '09:00:00');
      expect(map['endTime'], '18:30:15');

      expect(TraceMode.fromMap(map), mode);
    });

    test('midnight is distinguishable from "no window"', () {
      final TraceMode windowed =
          TraceModeBuilder().setStartTime(TraceTimeOfDay.midnight).build();
      final TraceMode unwindowed = TraceModeBuilder().build();

      expect(windowed.toMap()['startTime'], '00:00:00');
      expect(unwindowed.toMap()['startTime'], isNull);
      expect(windowed, isNot(unwindowed));
    });

    test('full map shape', () {
      expect(TraceMode.passive.toMap(), <String, Object?>{
        'desiredAccuracy': 'MEDIUM',
        'updateInterval': 0,
        'distanceFilter': 100,
        'stopDuration': 0,
        'accuracyFilter': 300,
        'trackingMode': 0,
        'offline': true,
        'debug': false,
        'pingSyncInterval': 120,
        'startTime': null,
        'endTime': null,
      });
    });

    test('fromMap falls back to defaults on missing/garbage fields', () {
      final TraceMode mode = TraceMode.fromMap(<String, Object?>{
        'desiredAccuracy': 'WAT',
        'updateInterval': 'twelve',
        'accuracyFilter': 42.0,
        'offline': 'yes',
        'startTime': 'not a time',
      });

      expect(mode.desiredAccuracy, DesiredAccuracy.high);
      expect(mode.updateInterval, 0);
      expect(mode.distanceFilter, 0);
      expect(mode.accuracyFilter, 42);
      expect(mode.trackingMode, TrackingMode.custom);
      expect(mode.offline, isTrue);
      expect(mode.startTime, isNull);
    });

    test('equality and hashCode cover every field', () {
      expect(TraceMode.active, TraceMode.active);
      expect(TraceMode.active.hashCode, TraceMode.active.hashCode);
      expect(TraceMode.active, isNot(TraceMode.passive));
      expect(
        TraceMode.active.copyWith(pingSyncInterval: 7),
        isNot(TraceMode.active),
      );
    });
  });
}
