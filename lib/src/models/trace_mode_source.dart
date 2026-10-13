/// The source driving the SDK's tracking mode.
///
/// Mirrors `TraceModeSource.kt` on Android and `TraceModeSource.swift` on iOS.
enum TraceModeSource {
  /// The `TraceMode` passed to `startTracking` is stored and used.
  local,

  /// The SDK queries the Barikoi backend for company settings and applies them.
  remote;

  /// Decodes a wire string. Unrecognized values fall back to [local].
  static TraceModeSource fromWire(String? value) {
    return switch (value?.toUpperCase()) {
      'REMOTE' => TraceModeSource.remote,
      _ => TraceModeSource.local,
    };
  }

  /// Encodes to the wire string expected by native platforms.
  String toWire() {
    return switch (this) {
      TraceModeSource.local => 'LOCAL',
      TraceModeSource.remote => 'REMOTE',
    };
  }
}
