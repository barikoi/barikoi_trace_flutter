/// The error type every failing plugin call throws.
///
/// Mirrors the native SDKs: Android throws `TraceException(TraceError)` and
/// iOS throws `TraceError`, both carrying the same stable string [code] plus a
/// human-readable [message]. The plugin passes the native code through
/// verbatim — there is no translation table — so `catch (e) { e.code }` reads
/// identically on all three platforms.
///
/// ```dart
/// try {
///   await BarikoiTrace.setOrCreateUser(phone: '01700000000');
/// } on TraceException catch (e) {
///   switch (e.code) {
///     case TraceErrorCode.noKey:
///       // initialize() was never called.
///     case TraceErrorCode.network:
///       // Offline.
///   }
/// }
/// ```
class TraceException implements Exception {
  /// Creates a trace exception with a stable [code] and a readable [message].
  const TraceException({required this.code, required this.message});

  /// Stable, machine-readable error code. One of the [TraceErrorCode]
  /// constants for errors the SDKs raise themselves; any other string when a
  /// platform surfaces an error the plugin does not model.
  final String code;

  /// Human-readable description. Free to change between releases — branch on
  /// [code], never on this.
  final String message;

  @override
  String toString() => 'TraceException($code): $message';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceException && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);
}

/// The string error codes carried by [TraceException.code].
///
/// The first eleven are emitted by both native SDKs (`TraceError.kt` and
/// `TraceError.swift`) and mean the same thing on each. The last three are
/// plugin-only: they are raised by the platform channel layer itself, never by
/// the native tracking SDKs.
abstract final class TraceErrorCode {
  /// No user has been created yet — call `setOrCreateUser` first.
  static const String noUser = 'NO_USER';

  /// API key not set — call `initialize` first.
  static const String noKey = 'NO_KEY';

  /// Required data is missing from a request or response.
  static const String noData = 'NO_DATA';

  /// No network connection available.
  static const String network = 'NETWORK';

  /// Location permission not granted.
  static const String permission = 'PERMISSION';

  /// A location fix could not be determined.
  static const String location = 'LOCATION';

  /// The Barikoi backend returned an error.
  static const String server = 'SERVER';

  /// A trip-state precondition failed (e.g. not currently on a trip).
  static const String trip = 'TRIP';

  /// A mock-location provider was detected.
  static const String mock = 'MOCK';

  /// A response could not be parsed.
  static const String json = 'JSON';

  /// The authenticated account has no company association, so no MQTT topic
  /// can be resolved for it.
  static const String noCompany = 'NO_COMPANY';

  // --- Plugin-only codes (not produced by the native SDKs) ---

  /// Plugin-only. A method was called before `BarikoiTrace.initialize`.
  static const String notInitialized = 'NOT_INITIALIZED';

  /// Plugin-only, Android-only. A call that needs a foreground `Activity`
  /// (permission prompts, settings screens) was made while the plugin was not
  /// attached to one.
  static const String noActivity = 'NO_ACTIVITY';

  /// Plugin-only. An unexpected failure inside the platform channel bridge
  /// that maps to none of the codes above.
  static const String internal = 'INTERNAL';

  /// Every code above, in declaration order. Useful for tests and for
  /// exhaustiveness checks in host apps.
  static const List<String> values = <String>[
    noUser,
    noKey,
    noData,
    network,
    permission,
    location,
    server,
    trip,
    mock,
    json,
    noCompany,
    notInitialized,
    noActivity,
    internal,
  ];
}
