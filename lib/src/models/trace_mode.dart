/// Horizontal-accuracy class requested from the platform location provider.
///
/// Wire values are the uppercase names used by both native SDKs
/// (`TraceMode.DesiredAccuracy` on Android, `TraceMode.DesiredAccuracy` on
/// iOS).
enum DesiredAccuracy {
  /// Best available fix. Highest battery cost.
  high('HIGH'),

  /// Balanced power/accuracy.
  medium('MEDIUM'),

  /// Coarse, low-power fixes.
  low('LOW');

  const DesiredAccuracy(this.wireValue);

  /// The string sent across the method channel.
  final String wireValue;

  /// Parses a wire value, falling back to [DesiredAccuracy.high] for null or
  /// unrecognized input — the same lenient behaviour as both natives'
  /// `fromString`.
  static DesiredAccuracy fromWire(Object? value) {
    if (value is! String) return DesiredAccuracy.high;
    final String normalized = value.trim().toUpperCase();
    for (final DesiredAccuracy candidate in DesiredAccuracy.values) {
      if (candidate.wireValue == normalized) return candidate;
    }
    return DesiredAccuracy.high;
  }
}

/// Which preset (or none) a [TraceMode] came from.
///
/// The integer [option] is the wire value and matches
/// `TraceMode.TrackingMode(val option: Int)` on Android and
/// `TraceMode.TrackingMode: Int` on iOS.
enum TrackingMode {
  /// Low-power, distance-triggered tracking.
  passive(0),

  /// Distance-triggered tracking at high accuracy.
  reactive(1),

  /// Continuous, interval-driven tracking.
  active(2),

  /// Anything built through [TraceModeBuilder].
  custom(3);

  const TrackingMode(this.option);

  /// The integer sent across the method channel.
  final int option;

  /// Parses a wire value, falling back to [TrackingMode.custom] for null or
  /// unrecognized input.
  static TrackingMode fromWire(Object? value) {
    if (value is! num) return TrackingMode.custom;
    final int option = value.toInt();
    for (final TrackingMode candidate in TrackingMode.values) {
      if (candidate.option == option) return candidate;
    }
    return TrackingMode.custom;
  }
}

/// A wall-clock time of day, with no date and no time zone.
///
/// Stands in for `java.time.LocalTime` on Android and `DateComponents` on
/// iOS. Dart's own `TimeOfDay` lives in the `material` library and has no
/// seconds field, so the plugin carries its own value type rather than
/// dragging a widget dependency into the model layer.
class TraceTimeOfDay implements Comparable<TraceTimeOfDay> {
  /// Creates a time of day. [hour] must be 0-23, [minute] and [second] 0-59.
  const TraceTimeOfDay({
    required this.hour,
    this.minute = 0,
    this.second = 0,
  })  : assert(hour >= 0 && hour <= 23, 'hour must be in 0..23'),
        assert(minute >= 0 && minute <= 59, 'minute must be in 0..59'),
        assert(second >= 0 && second <= 59, 'second must be in 0..59');

  /// Hour of day, 0-23.
  final int hour;

  /// Minute of hour, 0-59.
  final int minute;

  /// Second of minute, 0-59.
  final int second;

  /// Midnight, `00:00:00`.
  static const TraceTimeOfDay midnight = TraceTimeOfDay(hour: 0);

  /// The last representable second of the day, `23:59:59`.
  static const TraceTimeOfDay endOfDay =
      TraceTimeOfDay(hour: 23, minute: 59, second: 59);

  /// Parses `"HH:mm:ss"` or `"HH:mm"`.
  ///
  /// Throws a [FormatException] when [value] is not one of those shapes or
  /// carries out-of-range components. Fractional seconds are accepted and
  /// truncated, so Android's `LocalTime.MAX` string (`23:59:59.999999999`)
  /// round-trips to `23:59:59`.
  static TraceTimeOfDay parse(String value) {
    final TraceTimeOfDay? parsed = tryParse(value);
    if (parsed == null) {
      throw FormatException('Not a valid HH:mm:ss time of day', value);
    }
    return parsed;
  }

  /// Like [parse] but returns null instead of throwing.
  static TraceTimeOfDay? tryParse(String value) {
    final List<String> parts = value.trim().split(':');
    if (parts.length < 2 || parts.length > 3) return null;

    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    int? second = 0;
    if (parts.length == 3) {
      final String secondPart = parts[2];
      final int dot = secondPart.indexOf('.');
      second = int.tryParse(dot == -1 ? secondPart : secondPart.substring(0, dot));
    }

    if (hour == null || minute == null || second == null) return null;
    if (hour < 0 || hour > 23) return null;
    if (minute < 0 || minute > 59) return null;
    if (second < 0 || second > 59) return null;

    return TraceTimeOfDay(hour: hour, minute: minute, second: second);
  }

  /// Renders `"HH:mm:ss"` — the wire format.
  String format() =>
      '${_pad(hour)}:${_pad(minute)}:${_pad(second)}';

  static String _pad(int value) => value.toString().padLeft(2, '0');

  /// Seconds since midnight. Handy for ordering and for comparing windows.
  int get secondsOfDay => hour * 3600 + minute * 60 + second;

  @override
  int compareTo(TraceTimeOfDay other) =>
      secondsOfDay.compareTo(other.secondsOfDay);

  @override
  String toString() => format();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceTimeOfDay &&
          other.hour == hour &&
          other.minute == minute &&
          other.second == second;

  @override
  int get hashCode => Object.hash(hour, minute, second);
}

/// Tracking configuration.
///
/// Mirrors `TraceMode.kt` and `TraceMode.swift` field for field, including
/// their preset values and builder floors, so the same [TraceMode] behaves
/// identically on both platforms.
///
/// ```dart
/// await BarikoiTrace.startTracking(TraceMode.active);
///
/// final custom = TraceModeBuilder()
///     .setDesiredAccuracy(DesiredAccuracy.medium)
///     .setUpdateInterval(30)
///     .setStartTime(const TraceTimeOfDay(hour: 9))
///     .setEndTime(const TraceTimeOfDay(hour: 18))
///     .build();
/// await BarikoiTrace.startTracking(custom);
/// ```
class TraceMode {
  /// Creates a trace mode. Defaults match both natives' primary constructors.
  const TraceMode({
    this.desiredAccuracy = DesiredAccuracy.high,
    this.updateInterval = 0,
    this.distanceFilter = 0,
    this.stopDuration = 0,
    this.accuracyFilter = 100,
    this.trackingMode = TrackingMode.custom,
    this.offline = true,
    this.debug = false,
    this.pingSyncInterval = 0,
    this.startTime,
    this.endTime,
  });

  /// Accuracy class requested from the platform location provider.
  final DesiredAccuracy desiredAccuracy;

  /// Seconds between location requests when interval-based. `0` means
  /// distance-based instead.
  final int updateInterval;

  /// Meters of movement required before a new fix is requested. `0` means
  /// interval-based instead.
  final int distanceFilter;

  /// Seconds of no movement after which the session is considered stopped.
  final int stopDuration;

  /// Meters — fixes with worse horizontal accuracy than this are rejected.
  final int accuracyFilter;

  /// Which preset this mode came from, or [TrackingMode.custom].
  final TrackingMode trackingMode;

  /// Whether fixes are persisted while offline and uploaded later.
  final bool offline;

  /// Whether the SDK emits verbose debug logs.
  final bool debug;

  /// Seconds between keep-alive pings. `0` disables pinging.
  final int pingSyncInterval;

  /// Start of the daily tracking window, or null for **no daily window**.
  ///
  /// Null is the sentinel for "track all day": the native layer maps it to
  /// `LocalTime.MIN` on Android and `TraceMode.dayStart` (`00:00:00`) on iOS.
  /// It is deliberately not defaulted to `00:00:00` here so that "unset" and
  /// "explicitly midnight" stay distinguishable on the Dart side.
  final TraceTimeOfDay? startTime;

  /// End of the daily tracking window, or null for **no daily window**.
  ///
  /// Null maps to `LocalTime.MAX` on Android and `TraceMode.dayEnd`
  /// (`23:59:59`) on iOS.
  final TraceTimeOfDay? endTime;

  // --- Presets: numerically identical to TraceMode.kt's and
  // TraceMode.swift's ACTIVE / PASSIVE / REACTIVE. ---

  /// High accuracy, a fix every 5 seconds, 50 m accuracy filter, no pinging.
  static const TraceMode active = TraceMode(
    desiredAccuracy: DesiredAccuracy.high,
    updateInterval: 5,
    distanceFilter: 0,
    stopDuration: 0,
    accuracyFilter: 50,
    trackingMode: TrackingMode.active,
    offline: true,
    debug: false,
    pingSyncInterval: 0,
  );

  /// Medium accuracy, a fix every 100 m, 300 m accuracy filter, ping every
  /// 120 s.
  static const TraceMode passive = TraceMode(
    desiredAccuracy: DesiredAccuracy.medium,
    updateInterval: 0,
    distanceFilter: 100,
    stopDuration: 0,
    accuracyFilter: 300,
    trackingMode: TrackingMode.passive,
    offline: true,
    debug: false,
    pingSyncInterval: 120,
  );

  /// High accuracy, a fix every 100 m, 100 m accuracy filter, ping every 30 s.
  static const TraceMode reactive = TraceMode(
    desiredAccuracy: DesiredAccuracy.high,
    updateInterval: 0,
    distanceFilter: 100,
    stopDuration: 0,
    accuracyFilter: 100,
    trackingMode: TrackingMode.reactive,
    offline: true,
    debug: false,
    pingSyncInterval: 30,
  );

  /// Returns a copy with the given fields replaced.
  ///
  /// Note that [startTime] and [endTime] cannot be cleared through this
  /// method — omitting them keeps the current value. Construct a new
  /// [TraceMode] to reset a window to "all day".
  TraceMode copyWith({
    DesiredAccuracy? desiredAccuracy,
    int? updateInterval,
    int? distanceFilter,
    int? stopDuration,
    int? accuracyFilter,
    TrackingMode? trackingMode,
    bool? offline,
    bool? debug,
    int? pingSyncInterval,
    TraceTimeOfDay? startTime,
    TraceTimeOfDay? endTime,
  }) {
    return TraceMode(
      desiredAccuracy: desiredAccuracy ?? this.desiredAccuracy,
      updateInterval: updateInterval ?? this.updateInterval,
      distanceFilter: distanceFilter ?? this.distanceFilter,
      stopDuration: stopDuration ?? this.stopDuration,
      accuracyFilter: accuracyFilter ?? this.accuracyFilter,
      trackingMode: trackingMode ?? this.trackingMode,
      offline: offline ?? this.offline,
      debug: debug ?? this.debug,
      pingSyncInterval: pingSyncInterval ?? this.pingSyncInterval,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  /// Encodes to the wire map documented in `docs/WIRE_CONTRACT.md`.
  ///
  /// Times are `"HH:mm:ss"` strings, or null for "no daily window".
  Map<String, Object?> toMap() => <String, Object?>{
        'desiredAccuracy': desiredAccuracy.wireValue,
        'updateInterval': updateInterval,
        'distanceFilter': distanceFilter,
        'stopDuration': stopDuration,
        'accuracyFilter': accuracyFilter,
        'trackingMode': trackingMode.option,
        'offline': offline,
        'debug': debug,
        'pingSyncInterval': pingSyncInterval,
        'startTime': startTime?.format(),
        'endTime': endTime?.format(),
      };

  /// Decodes the wire map produced by [toMap] or by the native side.
  ///
  /// Missing or malformed fields fall back to this class's defaults rather
  /// than throwing, matching both natives' lenient parsing of remote settings.
  static TraceMode fromMap(Map<String, Object?> map) {
    return TraceMode(
      desiredAccuracy: DesiredAccuracy.fromWire(map['desiredAccuracy']),
      updateInterval: _int(map['updateInterval'], 0),
      distanceFilter: _int(map['distanceFilter'], 0),
      stopDuration: _int(map['stopDuration'], 0),
      accuracyFilter: _int(map['accuracyFilter'], 100),
      trackingMode: TrackingMode.fromWire(map['trackingMode']),
      offline: _bool(map['offline'], true),
      debug: _bool(map['debug'], false),
      pingSyncInterval: _int(map['pingSyncInterval'], 0),
      startTime: _time(map['startTime']),
      endTime: _time(map['endTime']),
    );
  }

  static int _int(Object? value, int fallback) =>
      value is num ? value.toInt() : fallback;

  static bool _bool(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  static TraceTimeOfDay? _time(Object? value) =>
      value is String ? TraceTimeOfDay.tryParse(value) : null;

  @override
  String toString() => 'TraceMode(${toMap()})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceMode &&
          other.desiredAccuracy == desiredAccuracy &&
          other.updateInterval == updateInterval &&
          other.distanceFilter == distanceFilter &&
          other.stopDuration == stopDuration &&
          other.accuracyFilter == accuracyFilter &&
          other.trackingMode == trackingMode &&
          other.offline == offline &&
          other.debug == debug &&
          other.pingSyncInterval == pingSyncInterval &&
          other.startTime == startTime &&
          other.endTime == endTime;

  @override
  int get hashCode => Object.hash(
        desiredAccuracy,
        updateInterval,
        distanceFilter,
        stopDuration,
        accuracyFilter,
        trackingMode,
        offline,
        debug,
        pingSyncInterval,
        startTime,
        endTime,
      );
}

/// Fluent builder for a custom [TraceMode].
///
/// Applies exactly the floors both native builders apply — update interval
/// >= 5 s, distance filter >= 10 m, accuracy filter >= 20 m — and always
/// stamps [TrackingMode.custom] on the result.
class TraceModeBuilder {
  /// Creates a builder pre-loaded with the native builders' defaults.
  TraceModeBuilder();

  DesiredAccuracy _desiredAccuracy = DesiredAccuracy.high;
  int _updateInterval = 0;
  int _distanceFilter = 0;
  int _stopDuration = 0;
  int _accuracyFilter = 100;
  bool _offline = true;
  bool _debug = false;
  int _pingSyncInterval = 0;
  TraceTimeOfDay? _startTime;
  TraceTimeOfDay? _endTime;

  /// Sets the accuracy class.
  TraceModeBuilder setDesiredAccuracy(DesiredAccuracy accuracy) {
    _desiredAccuracy = accuracy;
    return this;
  }

  /// Sets the update interval in seconds. Floored at 5.
  TraceModeBuilder setUpdateInterval(int seconds) {
    _updateInterval = seconds < 5 ? 5 : seconds;
    return this;
  }

  /// Sets the distance filter in meters. Floored at 10.
  TraceModeBuilder setDistanceFilter(int meters) {
    _distanceFilter = meters < 10 ? 10 : meters;
    return this;
  }

  /// Sets the stop duration in seconds. Not floored, matching both natives.
  TraceModeBuilder setStopDuration(int seconds) {
    _stopDuration = seconds;
    return this;
  }

  /// Sets the accuracy filter in meters. Floored at 20.
  TraceModeBuilder setAccuracyFilter(int meters) {
    _accuracyFilter = meters < 20 ? 20 : meters;
    return this;
  }

  /// Enables or disables offline persistence of fixes.
  TraceModeBuilder setOfflineSync(bool enabled) {
    _offline = enabled;
    return this;
  }

  /// Turns debug logging on. Matches the natives' argument-less
  /// `setDebugModeOn()`.
  TraceModeBuilder setDebugModeOn() {
    _debug = true;
    return this;
  }

  /// Sets the keep-alive ping interval in seconds. Not floored.
  TraceModeBuilder setPingSyncInterval(int seconds) {
    _pingSyncInterval = seconds;
    return this;
  }

  /// Sets the start of the daily tracking window. Pass null for no window.
  TraceModeBuilder setStartTime(TraceTimeOfDay? time) {
    _startTime = time;
    return this;
  }

  /// Sets the end of the daily tracking window. Pass null for no window.
  TraceModeBuilder setEndTime(TraceTimeOfDay? time) {
    _endTime = time;
    return this;
  }

  /// Builds the mode. [TraceMode.trackingMode] is always
  /// [TrackingMode.custom].
  TraceMode build() => TraceMode(
        desiredAccuracy: _desiredAccuracy,
        updateInterval: _updateInterval,
        distanceFilter: _distanceFilter,
        stopDuration: _stopDuration,
        accuracyFilter: _accuracyFilter,
        trackingMode: TrackingMode.custom,
        offline: _offline,
        debug: _debug,
        pingSyncInterval: _pingSyncInterval,
        startTime: _startTime,
        endTime: _endTime,
      );
}
