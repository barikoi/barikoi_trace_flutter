package com.barikoi.barikoitrace.flutter

import android.location.Location
import android.os.Build
import com.barikoi.barikoitrace.TraceMode
import com.barikoi.barikoitrace.model.TraceUser
import java.time.LocalTime
import java.util.Locale

/**
 * Conversions between the `StandardMessageCodec` values that cross the platform
 * channels and the native SDK's model types.
 *
 * Mirrors `lib/src/method_channel/codecs.dart` and is normative against
 * `docs/WIRE_CONTRACT.md` §4 and §5. Decoders are lenient by design — a missing
 * or wrongly typed field falls back to the documented default rather than
 * throwing, because one malformed remote-settings payload must not take down a
 * whole call, and one malformed fix must not tear down an event stream.
 */
internal object Codecs {

    // ---------------------------------------------------------------------
    // Primitives
    // ---------------------------------------------------------------------

    /**
     * Normalizes any channel value into a `Map<String, Any?>`, dropping
     * non-String keys. Returns an empty map for null or non-map input, which
     * lets every caller read arguments without a null check.
     */
    fun asWireMap(value: Any?): Map<String, Any?> {
        if (value !is Map<*, *>) return emptyMap()
        val result = HashMap<String, Any?>(value.size)
        for ((key, entry) in value) {
            if (key is String) result[key] = entry
        }
        return result
    }

    /** Reads an Int from any [Number] (Dart may send either an int or a double). */
    fun asInt(value: Any?, fallback: Int): Int =
        if (value is Number) value.toInt() else fallback

    /** Reads a Boolean, falling back to [fallback]. */
    fun asBool(value: Any?, fallback: Boolean): Boolean =
        if (value is Boolean) value else fallback

    /** Reads a String, or null when absent or not a String. */
    fun asStringOrNull(value: Any?): String? = value as? String

    // ---------------------------------------------------------------------
    // The daily-window time sentinel (WIRE_CONTRACT §5)
    // ---------------------------------------------------------------------
    //
    // `null` on the wire is a *sentinel* meaning "no daily window — track all
    // day", not a missing value. Android spells that as LocalTime.MIN for the
    // start and LocalTime.MAX for the end, so the mapping is asymmetric per
    // field and has to be preserved in both directions.
    //
    // LocalTime.MAX is 23:59:59.999999999. Its own toString() carries the
    // nanoseconds, which Dart would decode as a real 23:59:59 window rather
    // than the sentinel — hence the explicit identity check on the way out and
    // the hand-rolled HH:mm:ss formatter (LocalTime.toString() also drops the
    // seconds field entirely when it is zero, printing "09:00").

    /**
     * Decodes a `"HH:mm:ss"` / `"HH:mm"` string. Returns null for the sentinel
     * (a null or non-String value) and for anything unparseable or out of
     * range, matching Dart's `TraceTimeOfDay.tryParse` leniency.
     */
    fun decodeTime(value: Any?): LocalTime? {
        val text = (value as? String)?.trim() ?: return null
        if (text.isEmpty()) return null
        return try {
            // ISO_LOCAL_TIME accepts HH:mm, HH:mm:ss and fractional seconds.
            LocalTime.parse(text)
        } catch (_: Exception) {
            null
        }
    }

    /** Decodes a window start: the sentinel becomes [LocalTime.MIN]. */
    fun decodeStartTime(value: Any?): LocalTime = decodeTime(value) ?: LocalTime.MIN

    /** Decodes a window end: the sentinel becomes [LocalTime.MAX]. */
    fun decodeEndTime(value: Any?): LocalTime = decodeTime(value) ?: LocalTime.MAX

    /** Encodes a window start, collapsing [LocalTime.MIN] back to the sentinel. */
    fun encodeStartTime(time: LocalTime): String? =
        if (time == LocalTime.MIN) null else formatTime(time)

    /** Encodes a window end, collapsing [LocalTime.MAX] back to the sentinel. */
    fun encodeEndTime(time: LocalTime): String? =
        if (time == LocalTime.MAX) null else formatTime(time)

    /** Always `HH:mm:ss`, zero padded, 24-hour, locale independent. */
    private fun formatTime(time: LocalTime): String =
        "%02d:%02d:%02d".format(Locale.US, time.hour, time.minute, time.second)

    // ---------------------------------------------------------------------
    // TraceMode (WIRE_CONTRACT §4.3)
    // ---------------------------------------------------------------------

    /**
     * Decodes a trace mode through [TraceMode]'s **primary constructor**.
     *
     * Deliberately not `TraceMode.Builder`: the builder floors updateInterval
     * at 5 s, distanceFilter at 10 m and accuracyFilter at 20 m, and hardcodes
     * `TrackingMode.CUSTOM` on the result. Feeding it the `passive` preset
     * (updateInterval 0, distanceFilter 100, trackingMode 0) would silently
     * come back as a custom mode with a 5 s interval — a different tracking
     * strategy than the one the Dart caller asked for.
     */
    fun decodeMode(value: Any?): TraceMode {
        val map = asWireMap(value)
        return TraceMode(
            desiredAccuracy = decodeDesiredAccuracy(map["desiredAccuracy"]),
            updateInterval = asInt(map["updateInterval"], 0),
            distanceFilter = asInt(map["distanceFilter"], 0),
            stopDuration = asInt(map["stopDuration"], 0),
            accuracyFilter = asInt(map["accuracyFilter"], 100),
            trackingMode = decodeTrackingMode(map["trackingMode"]),
            offline = asBool(map["offline"], true),
            debug = asBool(map["debug"], false),
            pingSyncInterval = asInt(map["pingSyncInterval"], 0),
            startTime = decodeStartTime(map["startTime"]),
            endTime = decodeEndTime(map["endTime"])
        )
    }

    /** Encodes a trace mode. All eleven keys are always present. */
    fun encodeMode(mode: TraceMode): HashMap<String, Any?> {
        val map = HashMap<String, Any?>(11)
        map["desiredAccuracy"] = mode.desiredAccuracy.name
        map["updateInterval"] = mode.updateInterval
        map["distanceFilter"] = mode.distanceFilter
        map["stopDuration"] = mode.stopDuration
        map["accuracyFilter"] = mode.accuracyFilter
        map["trackingMode"] = mode.trackingMode.option
        map["offline"] = mode.offline
        map["debug"] = mode.debug
        map["pingSyncInterval"] = mode.pingSyncInterval
        map["startTime"] = encodeStartTime(mode.startTime)
        map["endTime"] = encodeEndTime(mode.endTime)
        return map
    }

    /**
     * `DesiredAccuracy.fromString` is `valueOf` based, so it is case sensitive
     * and does not trim. Normalize first, then let it apply the documented
     * HIGH fallback for anything unrecognized.
     */
    private fun decodeDesiredAccuracy(value: Any?): TraceMode.DesiredAccuracy =
        TraceMode.DesiredAccuracy.fromString(
            (value as? String)?.trim()?.uppercase(Locale.US)
        )

    /** Unrecognized values decode to CUSTOM (3), matching the Dart decoder. */
    private fun decodeTrackingMode(value: Any?): TraceMode.TrackingMode {
        if (value !is Number) return TraceMode.TrackingMode.CUSTOM
        val option = value.toInt()
        for (candidate in TraceMode.TrackingMode.values()) {
            if (candidate.option == option) return candidate
        }
        return TraceMode.TrackingMode.CUSTOM
    }

    // ---------------------------------------------------------------------
    // TraceUser (WIRE_CONTRACT §4.2)
    // ---------------------------------------------------------------------

    /** `updatedAt` is epoch milliseconds — the SDK's Long, passed through. */
    fun encodeUser(user: TraceUser): HashMap<String, Any?> {
        val map = HashMap<String, Any?>(9)
        map["userId"] = user.userId
        map["name"] = user.name
        map["email"] = user.email
        map["phone"] = user.phone
        map["companyId"] = user.companyId
        map["group"] = user.group
        map["lastLat"] = user.lastLat
        map["lastLon"] = user.lastLon
        map["updatedAt"] = user.updatedAt
        return map
    }

    // ---------------------------------------------------------------------
    // TraceLocation (WIRE_CONTRACT §4.4)
    // ---------------------------------------------------------------------

    /**
     * Encodes a fix.
     *
     * `speed`, `bearing` and `verticalAccuracy` are sent as **null** when the
     * platform has no valid value — `Location` returns a bare 0f for an unset
     * speed or bearing, which Dart would read as "stationary, facing north".
     */
    fun encodeLocation(location: Location): HashMap<String, Any?> {
        val map = HashMap<String, Any?>(10)
        map["latitude"] = location.latitude
        map["longitude"] = location.longitude
        map["altitude"] = if (location.hasAltitude()) location.altitude else 0.0
        map["accuracy"] = if (location.hasAccuracy()) location.accuracy.toDouble() else 0.0
        map["verticalAccuracy"] =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && location.hasVerticalAccuracy()) {
                location.verticalAccuracyMeters.toDouble()
            } else {
                null
            }
        map["speed"] = if (location.hasSpeed()) location.speed.toDouble() else null
        map["bearing"] = if (location.hasBearing()) location.bearing.toDouble() else null
        map["timestampMs"] = location.time
        map["isMock"] = isMock(location)
        map["provider"] = location.provider
        return map
    }

    /**
     * Same branch as the SDK's `SystemSettingsManager.checkIfMockProvider`,
     * inlined so this object needs no Context. Both accessors exist below the
     * plugin's minSdk of 24, so this is never null on Android.
     */
    @Suppress("DEPRECATION")
    private fun isMock(location: Location): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            location.isMock
        } else {
            location.isFromMockProvider
        }

    // ---------------------------------------------------------------------
    // TraceLogEntry (WIRE_CONTRACT §4.5)
    // ---------------------------------------------------------------------

    /**
     * The native `TraceLogListener.onLog` callback carries no timestamp, so the
     * plugin stamps one at the moment the callback fires.
     */
    fun encodeLogEntry(
        level: String,
        tag: String,
        message: String,
        timestampMs: Long
    ): HashMap<String, Any?> {
        val map = HashMap<String, Any?>(4)
        map["level"] = level
        map["tag"] = tag
        map["message"] = message
        map["timestampMs"] = timestampMs
        return map
    }
}
