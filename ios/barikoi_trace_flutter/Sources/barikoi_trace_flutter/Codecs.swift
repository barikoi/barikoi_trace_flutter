import CoreLocation
import Flutter
import Foundation

import BarikoiTrace

/// Conversions between the standard-message-codec values that cross the
/// platform channels and the native SDK's model types.
///
/// The wire shapes are normative and documented in `docs/WIRE_CONTRACT.md`.
/// Two rules drive most of the code below:
///
///  1. **Nullable fields are sent as explicit nulls, not omitted keys.** On
///     this platform "null" on the wire is `NSNull()`, not a Swift `nil`
///     stuffed into an `Any?` — `FlutterStandardWriter` writes `NSNull` as the
///     nil token, and a `[String: Any?]` bridged to `NSDictionary` cannot
///     carry a `nil` value at all. So every map produced here is
///     `[String: Any]` with `NSNull()` in the null slots.
///  2. **`startTime`/`endTime` carry a sentinel.** `null` on the wire means
///     "no daily window", which on this platform is `TraceMode.dayStart` /
///     `TraceMode.dayEnd`. Decoding maps `null` (and anything unparseable)
///     onto those; encoding maps them back to `null`. An explicit
///     `"00:00:00"` / `"23:59:59"` decodes to `dayStart`/`dayEnd`, which are
///     the same values the sentinel maps to — so it re-encodes as null rather
///     than round-tripping as an explicit window. Both mean "track all day", so
///     behavior is unaffected; only the reported value differs. (Android's
///     `LocalTime.MAX` carries nanoseconds, so `"23:59:59"` survives as a real
///     window there — an asymmetry in the reported value, not in behavior.)
///     Encoding compares against the SDK's own constants rather than against
///     formatted strings, so the comparison stays correct if those change.
enum Codecs {

    // MARK: - Primitives

    /// Wraps an optional for the wire: `nil` becomes the codec's null token.
    ///
    /// Generic rather than taking `Any?`, so that passing a `String?` cannot
    /// be read as a non-nil `Any` wrapping `Optional.none`.
    static func wire<T>(_ value: T?) -> Any {
        guard let value = value else { return NSNull() }
        return value
    }

    /// Normalizes any channel argument into a `[String: Any]`, dropping
    /// non-string keys. `NSNull` values are kept as-is; every accessor below
    /// reads an `NSNull` exactly like an absent key.
    static func wireMap(_ value: Any?) -> [String: Any] {
        if let typed = value as? [String: Any] { return typed }
        if let loose = value as? [AnyHashable: Any] {
            var result: [String: Any] = [:]
            for (key, entry) in loose {
                if let key = key as? String { result[key] = entry }
            }
            return result
        }
        return [:]
    }

    /// Reads a `String`, or nil when absent, null or not a string.
    static func string(_ value: Any?) -> String? {
        if value is NSNull { return nil }
        return value as? String
    }

    /// Reads an `Int`, accepting any numeric representation the codec may
    /// have produced.
    static func int(_ value: Any?, _ fallback: Int = 0) -> Int {
        if value is NSNull { return fallback }
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        if let double = value as? Double, double.isFinite { return Int(double) }
        return fallback
    }

    /// Reads a `Bool`, accepting `NSNumber`-boxed booleans.
    static func bool(_ value: Any?, _ fallback: Bool) -> Bool {
        if value is NSNull { return fallback }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return fallback
    }

    /// Clamps a floating-point epoch-milliseconds value into a safe `Int`.
    /// `TraceUser.updatedAt` and `Date.timeIntervalSince1970` are both
    /// `Double`, and `Int(_:)` traps on NaN/infinity.
    static func millis(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded()
        if rounded >= 9_007_199_254_740_992 { return 9_007_199_254_740_992 }
        if rounded <= -9_007_199_254_740_992 { return -9_007_199_254_740_992 }
        return Int(rounded)
    }

    /// CoreLocation reports `speed`, `course` and `verticalAccuracy` as
    /// **negative** when it has no valid value. Flattening those to `0` would
    /// read as "stationary, facing north", so they go across as null.
    static func nonNegative(_ value: CLLocationDistance) -> Any {
        guard value.isFinite, value >= 0 else { return NSNull() }
        return value
    }

    // MARK: - Times of day

    /// `"HH:mm:ss"`, zero-padded, 24-hour.
    static func formatTime(_ components: DateComponents) -> String {
        String(
            format: "%02d:%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    /// Parses `"HH:mm:ss"` or `"HH:mm"`, truncating fractional seconds.
    /// Returns nil for null, non-strings, unparseable and out-of-range values
    /// — the caller substitutes the full-day sentinel.
    static func parseTime(_ value: Any?) -> DateComponents? {
        guard let raw = string(value) else { return nil }
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }

        var second = 0
        if parts.count == 3 {
            // "12.500" — Dart never emits this, but the contract says decoders
            // truncate fractional seconds rather than reject them.
            let fields = parts[2].split(separator: ".", omittingEmptySubsequences: false)
            guard let field = fields.first, let parsed = Int(field) else { return nil }
            second = parsed
        }

        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            return nil
        }
        return DateComponents(hour: hour, minute: minute, second: second)
    }

    /// `TraceMode.dayStart` means "no daily window" and goes across as null.
    private static func encodeStartTime(_ components: DateComponents) -> Any {
        if components == TraceMode.dayStart { return NSNull() }
        return formatTime(components)
    }

    /// `TraceMode.dayEnd` means "no daily window" and goes across as null.
    private static func encodeEndTime(_ components: DateComponents) -> Any {
        if components == TraceMode.dayEnd { return NSNull() }
        return formatTime(components)
    }

    // MARK: - TraceMode

    static func encodeMode(_ mode: TraceMode) -> [String: Any] {
        [
            "desiredAccuracy": mode.desiredAccuracy.rawValue,
            "updateInterval": mode.updateInterval,
            "distanceFilter": mode.distanceFilter,
            "stopDuration": mode.stopDuration,
            "accuracyFilter": mode.accuracyFilter,
            "trackingMode": mode.trackingMode.rawValue,
            "offline": mode.offline,
            "debug": mode.debug,
            "pingSyncInterval": mode.pingSyncInterval,
            "startTime": encodeStartTime(mode.startTime),
            "endTime": encodeEndTime(mode.endTime),
        ]
    }

    /// Decodes via `TraceMode`'s primary initializer, deliberately **not** via
    /// `TraceMode.Builder`: the builder floors `updateInterval` at 5s,
    /// `distanceFilter` at 10m and `accuracyFilter` at 20m, and forces
    /// `trackingMode` to `.custom`. Any of those would silently rewrite a mode
    /// the Dart side sent — `TraceMode.passive` (interval 0, distance 100)
    /// would come back interval-gated at 5s, and every preset would lose its
    /// tracking mode.
    static func decodeMode(_ value: Any?) -> TraceMode {
        let map = wireMap(value)
        return TraceMode(
            desiredAccuracy: TraceMode.DesiredAccuracy.fromString(string(map["desiredAccuracy"])),
            updateInterval: int(map["updateInterval"]),
            distanceFilter: int(map["distanceFilter"]),
            stopDuration: int(map["stopDuration"]),
            accuracyFilter: int(map["accuracyFilter"], 100),
            // Unrecognized tracking modes decode to `custom`, matching the
            // lenient `fromString` behaviour of `desiredAccuracy` above.
            trackingMode: TraceMode.TrackingMode(rawValue: int(map["trackingMode"], 3)) ?? .custom,
            offline: bool(map["offline"], true),
            debug: bool(map["debug"], false),
            pingSyncInterval: int(map["pingSyncInterval"]),
            startTime: parseTime(map["startTime"]) ?? TraceMode.dayStart,
            endTime: parseTime(map["endTime"]) ?? TraceMode.dayEnd
        )
    }

    // MARK: - TraceUser

    static func encodeUser(_ user: TraceUser) -> [String: Any] {
        [
            "userId": user.userId,
            "name": wire(user.name),
            "email": wire(user.email),
            "phone": wire(user.phone),
            "companyId": wire(user.companyId),
            "group": wire(user.group),
            "lastLat": user.lastLat,
            "lastLon": user.lastLon,
            // `TraceUser.updatedAt` is already epoch milliseconds, as a Double.
            "updatedAt": millis(user.updatedAt),
        ]
    }

    // MARK: - TraceLocation

    /// Synthetic `provider` label. Android sends the real
    /// `Location.provider`; CoreLocation has no equivalent, and the contract
    /// explicitly allows "a synthetic label on iOS".
    static let locationProvider = "ios-corelocation"

    static func encodeLocation(_ location: CLLocation) -> [String: Any] {
        var isMock: Any = NSNull()
        if let source = location.sourceInformation {
            // `isSimulatedBySoftware` only — `isProducedByAccessory` would
            // flag every fix from a legitimate external MFi/Bluetooth GPS.
            // Same rule the SDK's own mock rejection uses.
            isMock = source.isSimulatedBySoftware
        }

        return [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "accuracy": location.horizontalAccuracy,
            "verticalAccuracy": nonNegative(location.verticalAccuracy),
            "speed": nonNegative(location.speed),
            "bearing": nonNegative(location.course),
            "timestampMs": millis(location.timestamp.timeIntervalSince1970 * 1000),
            "isMock": isMock,
            "provider": locationProvider,
        ]
    }

    // MARK: - TraceLogEntry

    /// `timestampMs` is stamped here — the native
    /// `TraceLogListener.onLog(level:tag:message:)` callback does not carry a
    /// timestamp.
    static func encodeLogEntry(level: String, tag: String, message: String) -> [String: Any] {
        [
            "level": level,
            "tag": tag,
            "message": message,
            "timestampMs": millis(Date().timeIntervalSince1970 * 1000),
        ]
    }

    // MARK: - Errors

    /// The single mapping from a native failure to a channel error.
    /// `TraceError.code` is passed through verbatim so a code the SDK adds
    /// later reaches host apps without a plugin release; anything else is
    /// `INTERNAL` with the throwable's message.
    static func flutterError(from error: Error) -> FlutterError {
        if let traceError = error as? TraceError {
            return FlutterError(code: traceError.code, message: traceError.message, details: nil)
        }
        return FlutterError(
            code: TraceErrorCodes.internalError,
            message: error.localizedDescription,
            details: nil
        )
    }
}

/// The two codes the bridge itself raises. Everything else comes from
/// `TraceError`.
enum TraceErrorCodes {
    static let notInitialized = "NOT_INITIALIZED"
    static let internalError = "INTERNAL"
    /// Raised by the plugin's own `startTracking` pre-checks, mirroring the
    /// codes the SDK uses for the same conditions elsewhere.
    static let noUser = "NO_USER"
    static let permission = "PERMISSION"
}
