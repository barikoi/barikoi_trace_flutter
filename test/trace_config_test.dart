import 'package:barikoi_trace_flutter/barikoi_trace_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const TraceConfig _valid = TraceConfig(
  apiKey: 'key',
  mqttUsername: 'user',
  mqttPassword: 'pass',
  baseUrl: 'https://api.example.com/api/v1/',
  mqttUrl: 'ssl://broker.example.com:8883',
);

void main() {
  group('isMqttTransportEncrypted', () {
    test('TLS schemes are encrypted', () {
      for (final String scheme in <String>['ssl', 'mqtts', 'tls', 'wss']) {
        expect(
          _valid.copyWith(mqttUrl: '$scheme://broker.example.com:8883')
              .isMqttTransportEncrypted,
          isTrue,
          reason: '$scheme should count as encrypted',
        );
      }
    });

    test('scheme comparison is case-insensitive', () {
      expect(
        _valid.copyWith(mqttUrl: 'SSL://broker.example.com:8883')
            .isMqttTransportEncrypted,
        isTrue,
      );
    });

    test('plaintext schemes are not encrypted', () {
      for (final String scheme in <String>['tcp', 'mqtt', 'ws']) {
        expect(
          _valid.copyWith(mqttUrl: '$scheme://broker.example.com:1883')
              .isMqttTransportEncrypted,
          isFalse,
          reason: '$scheme should count as plaintext',
        );
      }
    });

    test('a schemeless or unparseable URL is not encrypted', () {
      expect(
        _valid.copyWith(mqttUrl: 'broker.example.com:1883')
            .isMqttTransportEncrypted,
        isFalse,
      );
      expect(
        _valid.copyWith(mqttUrl: '::::').isMqttTransportEncrypted,
        isFalse,
      );
    });

    test('a null mqttUrl resolves to the native tcp:// default, so false', () {
      const TraceConfig config = TraceConfig(
        apiKey: 'key',
        mqttUsername: 'user',
        mqttPassword: 'pass',
      );
      expect(config.mqttUrl, isNull);
      expect(config.effectiveMqttUrl, TraceConfig.defaultMqttUrl);
      expect(TraceConfig.defaultMqttUrl, startsWith('tcp://'));
      expect(config.isMqttTransportEncrypted, isFalse);
    });
  });

  group('warnings', () {
    test('a fully valid config warns about nothing', () {
      expect(_valid.warnings, isEmpty);
    });

    test('empty apiKey warns first', () {
      final List<String> warnings = _valid.copyWith(apiKey: '').warnings;
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('apiKey is empty'));
      expect(warnings.first, contains('NO_KEY'));
    });

    test('blank apiKey counts as empty, matching Kotlin isBlank()', () {
      expect(
        _valid.copyWith(apiKey: '   ').warnings.single,
        contains('apiKey is empty'),
      );
    });

    test('either missing MQTT credential warns', () {
      expect(
        _valid.copyWith(mqttUsername: '').warnings.single,
        contains('MQTT credentials are empty'),
      );
      expect(
        _valid.copyWith(mqttPassword: '').warnings.single,
        contains('MQTT credentials are empty'),
      );
      expect(
        _valid.copyWith(mqttUsername: '', mqttPassword: '').warnings,
        hasLength(1),
      );
    });

    test('plaintext transport warns and names the URL', () {
      final List<String> warnings =
          _valid.copyWith(mqttUrl: 'tcp://broker.example.com:1883').warnings;
      expect(warnings, hasLength(1));
      expect(warnings.single, contains("mqttUrl 'tcp://broker.example.com:1883'"));
      expect(warnings.single, contains('plaintext'));
      expect(warnings.single, contains('ssl://'));
    });

    test('non-HTTPS base URL warns and names the URL', () {
      final List<String> warnings =
          _valid.copyWith(baseUrl: 'http://api.example.com/api/v1/').warnings;
      expect(warnings, hasLength(1));
      expect(
        warnings.single,
        "baseUrl 'http://api.example.com/api/v1/' is not HTTPS.",
      );
    });

    test('warnings come back in fix-it order', () {
      const TraceConfig broken = TraceConfig(
        apiKey: '',
        mqttUsername: '',
        mqttPassword: '',
        baseUrl: 'http://api.example.com/',
        mqttUrl: 'tcp://broker.example.com:1883',
      );
      final List<String> warnings = broken.warnings;
      expect(warnings, hasLength(4));
      expect(warnings[0], contains('apiKey'));
      expect(warnings[1], contains('MQTT credentials'));
      expect(warnings[2], contains('plaintext'));
      expect(warnings[3], contains('not HTTPS'));
    });

    test('an all-defaults config warns only about the plaintext default', () {
      const TraceConfig config = TraceConfig(
        apiKey: 'key',
        mqttUsername: 'user',
        mqttPassword: 'pass',
      );
      expect(config.warnings, hasLength(1));
      expect(config.warnings.single, contains('plaintext'));
      expect(TraceConfig.defaultBaseUrl, startsWith('https://'));
    });
  });

  group('toMap', () {
    test('sends null for unset endpoints rather than a Dart-side default', () {
      const TraceConfig config = TraceConfig(
        apiKey: 'key',
        mqttUsername: 'user',
        mqttPassword: 'pass',
      );
      expect(config.toMap(), <String, Object?>{
        'apiKey': 'key',
        'mqttUsername': 'user',
        'mqttPassword': 'pass',
        'baseUrl': null,
        'mqttUrl': null,
        'mqttClientIdPrefix': null,
        'notificationTitle': null,
        'notificationContent': null,
      });
    });

    test('sends overrides verbatim', () {
      expect(
        _valid.copyWith(
          mqttClientIdPrefix: 'fleet-',
          notificationTitle: 'Track App',
          notificationContent: 'Tracking active',
        ).toMap(),
        <String, Object?>{
          'apiKey': 'key',
          'mqttUsername': 'user',
          'mqttPassword': 'pass',
          'baseUrl': 'https://api.example.com/api/v1/',
          'mqttUrl': 'ssl://broker.example.com:8883',
          'mqttClientIdPrefix': 'fleet-',
          'notificationTitle': 'Track App',
          'notificationContent': 'Tracking active',
        },
      );
    });
  });

  test('equality and hashCode cover notification fields', () {
    final TraceConfig a = _valid.copyWith(
      notificationTitle: 'Title A',
      notificationContent: 'Content A',
    );
    final TraceConfig b = _valid.copyWith(
      notificationTitle: 'Title A',
      notificationContent: 'Content A',
    );
    final TraceConfig c = _valid.copyWith(
      notificationTitle: 'Title B',
      notificationContent: 'Content A',
    );

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
    expect(a, isNot(equals(c)));
  });

  test('toString redacts the secrets and contains notification fields', () {
    final String text = _valid.copyWith(
      notificationTitle: 'Title A',
      notificationContent: 'Content A',
    ).toString();
    expect(text, isNot(contains('pass')));
    expect(text, contains('<set>'));
    expect(text, contains('ssl://broker.example.com:8883'));
    expect(text, contains('Title A'));
    expect(text, contains('Content A'));
  });
}
