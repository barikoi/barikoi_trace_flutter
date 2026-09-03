/// One line from the native SDK's internal debug log.
///
/// The natives expose this as a listener interface — `TraceLogListener` in
/// both `BarikoiTrace.kt` and `BarikoiTrace.swift`, with an
/// `onLog(level:tag:message:)` callback. The plugin adapts that listener to
/// the `barikoi_trace_flutter/logs` event channel and stamps each line with
/// the time the platform emitted it, which the native callback does not carry.
class TraceLogEntry {
  /// Creates a log entry.
  TraceLogEntry({
    required this.level,
    required this.tag,
    required this.message,
    required this.timestamp,
  });

  /// Severity as the native SDK spelled it — `DEBUG`, `INFO`, `WARN`,
  /// `ERROR`. Left as a string rather than an enum because neither native
  /// constrains it.
  final String level;

  /// Source component, e.g. `TraceConfig`, `MqttManager`.
  final String tag;

  /// The log text.
  final String message;

  /// When the platform emitted the line, in UTC.
  final DateTime timestamp;

  /// Decodes the wire map documented in `docs/WIRE_CONTRACT.md`.
  static TraceLogEntry fromMap(Map<String, Object?> map) {
    return TraceLogEntry(
      level: map['level'] is String ? map['level']! as String : '',
      tag: map['tag'] is String ? map['tag']! as String : '',
      message: map['message'] is String ? map['message']! as String : '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestampMs'] is num ? (map['timestampMs']! as num).toInt() : 0,
        isUtc: true,
      ),
    );
  }

  /// Encodes back to the wire map. Present for symmetry and for tests.
  Map<String, Object?> toMap() => <String, Object?>{
        'level': level,
        'tag': tag,
        'message': message,
        'timestampMs': timestamp.millisecondsSinceEpoch,
      };

  @override
  String toString() => '[$level] $tag: $message';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceLogEntry &&
          other.level == level &&
          other.tag == tag &&
          other.message == message &&
          other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(level, tag, message, timestamp);
}
