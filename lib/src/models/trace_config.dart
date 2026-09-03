/// Everything the SDK needs to start, in one value.
///
/// Field-for-field equivalent to `TraceConfig.kt` and `TraceConfig.swift`,
/// with one deliberate difference: the three endpoint fields are **nullable
/// here and null by default**. Null means "use the native SDK's own default"
/// — the plugin omits the key from the wire map and the platform side simply
/// does not call the corresponding setter. Defaulting them to strings in Dart
/// would freeze today's native defaults into this package and silently
/// override any future change to them.
///
/// ```dart
/// await BarikoiTrace.initialize(const TraceConfig(
///   apiKey: '…',
///   mqttUsername: '…',
///   mqttPassword: '…',
/// ));
/// ```
///
/// Self-hosted or staging deployments override the endpoints:
///
/// ```dart
/// await BarikoiTrace.initialize(const TraceConfig(
///   apiKey: '…',
///   mqttUsername: '…',
///   mqttPassword: '…',
///   baseUrl: 'https://api.staging.example.com/api/v1/',
///   mqttUrl: 'ssl://broker.staging.example.com:8883',
///   mqttClientIdPrefix: 'fleet-flutter-',
/// ));
/// ```
class TraceConfig {
  /// Creates a configuration. Only the API key and the two broker credentials
  /// are required.
  const TraceConfig({
    required this.apiKey,
    required this.mqttUsername,
    required this.mqttPassword,
    this.baseUrl,
    this.mqttUrl,
    this.mqttClientIdPrefix,
  });

  /// Barikoi API key, from the Barikoi dashboard. Used for
  /// `POST /sdk/authenticate` and the company-settings call.
  final String apiKey;

  /// MQTT broker username. Issued per company, separately from [apiKey] — it
  /// is not derivable from it. Must match the broker ACL, or CONNECT is
  /// refused with `notAuthorized`.
  final String mqttUsername;

  /// MQTT broker password. Treat as a server secret: fetch it at runtime
  /// rather than compiling it into the app bundle.
  final String mqttPassword;

  /// REST base URL, or null to keep the native default
  /// ([defaultBaseUrl] at the time of writing). Trailing slash is normalized
  /// by the native SDKs.
  final String? baseUrl;

  /// Broker URL, `scheme://host[:port]`, or null to keep the native default
  /// ([defaultMqttUrl] at the time of writing).
  ///
  /// Recognized schemes: `tcp`, `mqtt`, `ws` (plaintext) and `ssl`, `mqtts`,
  /// `tls`, `wss` (TLS). The native default is **plaintext** — every fix and
  /// both broker credentials cross the network unencrypted. Point this at a
  /// TLS endpoint for anything carrying real user locations.
  final String? mqttUrl;

  /// Client-id prefix, or null to keep the per-platform native default
  /// (`AndroidClient-` / `iOSClient-`).
  ///
  /// The full client id is `{prefix}{userId}-{deviceId}`. Only worth changing
  /// when the broker ACL authorizes by client-id pattern — the symptom is
  /// `notAuthorized` on a CONNECT whose username and password are correct.
  final String? mqttClientIdPrefix;

  /// The REST base URL both native SDKs default to.
  ///
  /// Mirrored here purely so [warnings] and [isMqttTransportEncrypted] can
  /// reason about a null [baseUrl]. It is never sent across the channel.
  static const String defaultBaseUrl = 'https://api.trace.bmapsbd.com/api/v1/';

  /// The broker URL both native SDKs default to — note the plaintext `tcp://`
  /// scheme, which is why a config that leaves [mqttUrl] null still reports a
  /// plaintext-transport warning.
  ///
  /// Mirrored here purely for [warnings] and [isMqttTransportEncrypted]. It is
  /// never sent across the channel.
  static const String defaultMqttUrl = 'tcp://broker.trace.bmapsbd.com:1883';

  /// Schemes that mean "TLS" to both native SDKs.
  static const Set<String> _encryptedSchemes = <String>{
    'ssl',
    'mqtts',
    'tls',
    'wss',
  };

  /// The broker URL that will actually be used: [mqttUrl] when set, otherwise
  /// the native default.
  String get effectiveMqttUrl => mqttUrl ?? defaultMqttUrl;

  /// The REST base URL that will actually be used: [baseUrl] when set,
  /// otherwise the native default.
  String get effectiveBaseUrl => baseUrl ?? defaultBaseUrl;

  /// Whether [effectiveMqttUrl] names a TLS scheme.
  ///
  /// Surfaced so a host app can assert on it in a release build rather than
  /// discovering plaintext transport in production. A null [mqttUrl] resolves
  /// to the native `tcp://` default and therefore reports `false`.
  bool get isMqttTransportEncrypted {
    final Uri? uri = Uri.tryParse(effectiveMqttUrl);
    if (uri == null) return false;
    final String scheme = uri.scheme.toLowerCase();
    if (scheme.isEmpty) return false;
    return _encryptedSchemes.contains(scheme);
  }

  /// Non-fatal configuration problems, in the order they should be fixed.
  ///
  /// Same four checks, same order, same wording as `TraceConfig.warnings` on
  /// both platforms. The plugin logs these at `initialize`; check them
  /// yourself if you would rather fail a release build.
  List<String> get warnings {
    final List<String> found = <String>[];
    if (apiKey.trim().isEmpty) {
      found.add('apiKey is empty — /sdk/authenticate will fail with NO_KEY.');
    }
    if (mqttUsername.trim().isEmpty || mqttPassword.trim().isEmpty) {
      found.add(
        'MQTT credentials are empty — the broker will refuse CONNECT with '
        'notAuthorized.',
      );
    }
    if (!isMqttTransportEncrypted) {
      found.add(
        "mqttUrl '$effectiveMqttUrl' is plaintext — credentials and location "
        'data are sent unencrypted. Use ssl:// (port 8883).',
      );
    }
    if (!effectiveBaseUrl.startsWith('https://')) {
      found.add("baseUrl '$effectiveBaseUrl' is not HTTPS.");
    }
    return found;
  }

  /// Returns a copy with the given fields replaced. Passing null for an
  /// endpoint keeps the current value; construct a new [TraceConfig] to reset
  /// one back to the native default.
  TraceConfig copyWith({
    String? apiKey,
    String? mqttUsername,
    String? mqttPassword,
    String? baseUrl,
    String? mqttUrl,
    String? mqttClientIdPrefix,
  }) {
    return TraceConfig(
      apiKey: apiKey ?? this.apiKey,
      mqttUsername: mqttUsername ?? this.mqttUsername,
      mqttPassword: mqttPassword ?? this.mqttPassword,
      baseUrl: baseUrl ?? this.baseUrl,
      mqttUrl: mqttUrl ?? this.mqttUrl,
      mqttClientIdPrefix: mqttClientIdPrefix ?? this.mqttClientIdPrefix,
    );
  }

  /// Encodes to the wire map documented in `docs/WIRE_CONTRACT.md`.
  ///
  /// Unset endpoints are sent as explicit nulls; the platform side must treat
  /// null as "leave the native default alone".
  Map<String, Object?> toMap() => <String, Object?>{
        'apiKey': apiKey,
        'mqttUsername': mqttUsername,
        'mqttPassword': mqttPassword,
        'baseUrl': baseUrl,
        'mqttUrl': mqttUrl,
        'mqttClientIdPrefix': mqttClientIdPrefix,
      };

  /// Redacts the two secrets, so a config is safe to log.
  @override
  String toString() => 'TraceConfig(apiKey: ${_redact(apiKey)}, '
      'mqttUsername: ${_redact(mqttUsername)}, '
      'mqttPassword: ${_redact(mqttPassword)}, '
      'baseUrl: $baseUrl, mqttUrl: $mqttUrl, '
      'mqttClientIdPrefix: $mqttClientIdPrefix)';

  static String _redact(String value) => value.isEmpty ? "''" : '<set>';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceConfig &&
          other.apiKey == apiKey &&
          other.mqttUsername == mqttUsername &&
          other.mqttPassword == mqttPassword &&
          other.baseUrl == baseUrl &&
          other.mqttUrl == mqttUrl &&
          other.mqttClientIdPrefix == mqttClientIdPrefix;

  @override
  int get hashCode => Object.hash(
        apiKey,
        mqttUsername,
        mqttPassword,
        baseUrl,
        mqttUrl,
        mqttClientIdPrefix,
      );
}
