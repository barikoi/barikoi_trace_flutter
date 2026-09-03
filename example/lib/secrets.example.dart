/// Template. Copy to `secrets.dart` (which is git-ignored) and fill in the
/// real values:
///
/// ```sh
/// cp example/lib/secrets.example.dart example/lib/secrets.dart
/// ```
///
/// Same arrangement as the iOS SDK's `Examples/BasicUsage/Secrets.swift` and
/// the Android sample's `local.properties` → `BuildConfig.*`.
///
/// `--dart-define` still wins when it is set, so CI can inject credentials
/// without this file existing at all — see `main.dart`.
library;

abstract final class Secrets {
  /// Barikoi API key — the one used for `POST /sdk/authenticate`.
  static const String barikoiApiKey = 'YOUR_BARIKOI_API_KEY';

  /// Broker credentials. Per app and per environment, issued by your backend.
  /// These must match what the MQTT broker's ACL expects — a mismatch surfaces
  /// as `Broker refused the connection (notAuthorized)` on the log stream.
  static const String mqttUsername = 'YOUR_MQTT_USERNAME';
  static const String mqttPassword = 'YOUR_MQTT_PASSWORD';

  /// Broker endpoint. `tcp://` is plaintext — credentials and every location
  /// fix cross the network unencrypted. Use `ssl://host:8883` wherever the
  /// broker offers TLS.
  ///
  /// Leave as `null` to accept the SDK's own default.
  static const String? mqttUrl = 'tcp://broker.trace.bmapsbd.com:1883';

  /// REST base URL. `null` accepts the SDK default
  /// (`https://api.trace.bmapsbd.com/api/v1/`).
  static const String? baseUrl = null;
}
