import '../models/trace_config.dart';
import '../models/trace_location.dart';
import '../models/trace_log_entry.dart';
import '../models/trace_mode.dart';
import '../models/trace_user.dart';

/// Conversions between the standard-message-codec values that cross the
/// platform channels and this package's model types.
///
/// The platform side speaks `Map<Object?, Object?>` (that is what
/// `StandardMessageCodec` decodes a map into, on both Android and iOS), so
/// every decode starts by normalizing the key type. Decoders are deliberately
/// lenient: a missing or wrongly typed field falls back to the model's default
/// instead of throwing, because a single malformed event on the location or
/// log stream must not tear the stream down.
abstract final class Codecs {
  // --- Primitives ---

  /// Normalizes any channel map into a `Map<String, Object?>`, dropping
  /// non-string keys. Returns an empty map for null or non-map input.
  static Map<String, Object?> asWireMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map<Object?, Object?>) {
      final Map<String, Object?> result = <String, Object?>{};
      value.forEach((Object? key, Object? entry) {
        if (key is String) result[key] = entry;
      });
      return result;
    }
    return <String, Object?>{};
  }

  /// Reads a `bool`, falling back to [fallback].
  static bool asBool(Object? value, {bool fallback = false}) =>
      value is bool ? value : fallback;

  /// Reads a `String`, or null when absent or not a string.
  static String? asStringOrNull(Object? value) =>
      value is String ? value : null;

  /// Reads a `double`, or null when absent or not numeric.
  static double? asDoubleOrNull(Object? value) =>
      value is num ? value.toDouble() : null;

  /// Reads an `int`, falling back to [fallback]. Accepts any `num`, since iOS
  /// may encode a whole number as a double.
  static int asInt(Object? value, {int fallback = 0}) =>
      value is num ? value.toInt() : fallback;

  // --- The daily-window time sentinel ---
  //
  // A null start/end time means "no daily window": Android maps it to
  // LocalTime.MIN / LocalTime.MAX and iOS to TraceMode.dayStart /
  // TraceMode.dayEnd. Encoding therefore has to preserve null rather than
  // substituting 00:00:00 / 23:59:59, and decoding has to turn anything
  // unparseable back into null rather than into an arbitrary time.

  /// Encodes a time of day as `"HH:mm:ss"`, preserving the null sentinel.
  static String? encodeTime(TraceTimeOfDay? time) => time?.format();

  /// Decodes a `"HH:mm:ss"` (or `"HH:mm"`) string, mapping null, non-strings
  /// and unparseable strings back to the null sentinel.
  static TraceTimeOfDay? decodeTime(Object? value) {
    if (value is! String) return null;
    return TraceTimeOfDay.tryParse(value);
  }

  // --- Models ---

  /// Encodes a config for the `initialize` call.
  static Map<String, Object?> encodeConfig(TraceConfig config) =>
      config.toMap();

  /// Encodes a trace mode for `setTraceMode` / `startTracking`.
  static Map<String, Object?> encodeMode(TraceMode mode) => mode.toMap();

  /// Decodes a trace mode, e.g. the result of `getSettingsFromRemote`.
  static TraceMode decodeMode(Object? value) =>
      TraceMode.fromMap(asWireMap(value));

  /// Decodes a user. Returns null for a null payload, which is how
  /// `getUser` reports "no user yet".
  static TraceUser? decodeUserOrNull(Object? value) {
    if (value == null) return null;
    return TraceUser.fromMap(asWireMap(value));
  }

  /// Decodes a user that the contract guarantees is present.
  static TraceUser decodeUser(Object? value) =>
      TraceUser.fromMap(asWireMap(value));

  /// Decodes a location fix.
  static TraceLocation decodeLocation(Object? value) =>
      TraceLocation.fromMap(asWireMap(value));

  /// Decodes a log line.
  static TraceLogEntry decodeLogEntry(Object? value) =>
      TraceLogEntry.fromMap(asWireMap(value));
}
