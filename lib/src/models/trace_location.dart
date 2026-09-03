/// A single location fix.
///
/// Flattens `android.location.Location` and `CLLocation` into one shape. The
/// fields the two platforms do not share are nullable: [verticalAccuracy] and
/// [isMock] can be absent on either side depending on the fix's provider, and
/// [speed]/[bearing] are null when the platform reports them as invalid
/// (Android's `hasSpeed()`/`hasBearing()` returning false, iOS reporting a
/// negative value) rather than being flattened to a misleading `0`.
class TraceLocation {
  /// Creates a location fix.
  TraceLocation({
    required this.latitude,
    required this.longitude,
    this.altitude = 0,
    this.accuracy = 0,
    this.verticalAccuracy,
    this.speed,
    this.bearing,
    required this.timestamp,
    this.isMock,
    this.provider,
  });

  /// Degrees north, WGS 84.
  final double latitude;

  /// Degrees east, WGS 84.
  final double longitude;

  /// Meters above the WGS 84 reference ellipsoid. `0` when unavailable.
  final double altitude;

  /// Horizontal accuracy radius in meters. Compared against
  /// `TraceMode.accuracyFilter` by the native SDKs.
  final double accuracy;

  /// Vertical accuracy in meters, or null when the platform does not report
  /// it.
  final double? verticalAccuracy;

  /// Ground speed in meters per second, or null when invalid/unavailable.
  final double? speed;

  /// Heading in degrees clockwise from true north, or null when
  /// invalid/unavailable.
  final double? bearing;

  /// When the fix was taken. Decoded from the platform's epoch milliseconds,
  /// in UTC.
  final DateTime timestamp;

  /// Whether the fix came from a mock provider, or null when the platform does
  /// not say. Android reports this; iOS reports it only for simulated
  /// locations it can detect.
  final bool? isMock;

  /// Provider name (`gps`, `fused`, `network` on Android; a synthetic label on
  /// iOS), or null when unavailable.
  final String? provider;

  /// Decodes the wire map documented in `docs/WIRE_CONTRACT.md`.
  ///
  /// Missing coordinates decode to `0` and a missing `timestampMs` to the
  /// epoch, so one malformed event never tears down the stream.
  static TraceLocation fromMap(Map<String, Object?> map) {
    return TraceLocation(
      latitude: _double(map['latitude']) ?? 0,
      longitude: _double(map['longitude']) ?? 0,
      altitude: _double(map['altitude']) ?? 0,
      accuracy: _double(map['accuracy']) ?? 0,
      verticalAccuracy: _double(map['verticalAccuracy']),
      speed: _double(map['speed']),
      bearing: _double(map['bearing']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestampMs'] is num ? (map['timestampMs']! as num).toInt() : 0,
        isUtc: true,
      ),
      isMock: map['isMock'] is bool ? map['isMock']! as bool : null,
      provider: map['provider'] is String ? map['provider']! as String : null,
    );
  }

  /// Encodes back to the wire map. Present for symmetry and for tests.
  Map<String, Object?> toMap() => <String, Object?>{
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'accuracy': accuracy,
        'verticalAccuracy': verticalAccuracy,
        'speed': speed,
        'bearing': bearing,
        'timestampMs': timestamp.millisecondsSinceEpoch,
        'isMock': isMock,
        'provider': provider,
      };

  static double? _double(Object? value) =>
      value is num ? value.toDouble() : null;

  @override
  String toString() => 'TraceLocation($latitude, $longitude, '
      'accuracy: $accuracy, speed: $speed, bearing: $bearing, '
      'timestamp: $timestamp, provider: $provider, isMock: $isMock)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceLocation &&
          other.latitude == latitude &&
          other.longitude == longitude &&
          other.altitude == altitude &&
          other.accuracy == accuracy &&
          other.verticalAccuracy == verticalAccuracy &&
          other.speed == speed &&
          other.bearing == bearing &&
          other.timestamp == timestamp &&
          other.isMock == isMock &&
          other.provider == provider;

  @override
  int get hashCode => Object.hash(
        latitude,
        longitude,
        altitude,
        accuracy,
        verticalAccuracy,
        speed,
        bearing,
        timestamp,
        isMock,
        provider,
      );
}
