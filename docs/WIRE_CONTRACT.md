# `barikoi_trace_flutter` wire contract

Normative specification of the platform-channel surface between the Dart layer
of `barikoi_trace_flutter` and its Android and iOS implementations.

The Dart side is already written against this document
(`lib/src/method_channel/method_channel_barikoi_trace.dart`). Native
implementations must match it exactly — method-name strings, argument keys and
result shapes are all part of the contract.

---

## 1. Channels

| Channel | Name | Codec |
| --- | --- | --- |
| Method | `barikoi_trace_flutter/methods` | `StandardMethodCodec` |
| Event | `barikoi_trace_flutter/location_updates` | `StandardMethodCodec` |
| Event | `barikoi_trace_flutter/logs` | `StandardMethodCodec` |

All three use the default standard codec. Do **not** install a JSON codec.

Register all three from the same plugin class
(`com.barikoi.barikoitrace.flutter.BarikoiTraceFlutterPlugin` on Android,
`BarikoiTraceFlutterPlugin` on iOS) on the plugin binary messenger.

---

## 2. Type mapping

Standard-codec types only. In the tables below:

| Contract type | Android (Kotlin) | iOS (Swift) | Dart |
| --- | --- | --- | --- |
| `bool` | `Boolean` | `Bool` | `bool` |
| `int` | `Int`/`Long` | `Int` | `int` |
| `int64` | `Long` | `Int` (64-bit) | `int` |
| `double` | `Double` | `Double` | `double` |
| `string` | `String` | `String` | `String` |
| `map` | `HashMap<String, Any?>` | `[String: Any?]` | `Map<Object?, Object?>` |

Rules that hold everywhere:

1. **Every map key is a `String`.** The Dart side drops non-string keys.
2. **Nullable fields are sent as explicit nulls, not omitted keys.** The Dart
   side tolerates a missing key (it falls back to the documented default), but
   native implementations must send the key.
3. **`int` vs `double` is not load-bearing.** The Dart decoders accept any
   numeric type for any numeric field and convert. Prefer the natural type.
4. **Timestamps are `int64` epoch milliseconds, UTC.** Never a formatted date
   string. Dart decodes them with `DateTime.fromMillisecondsSinceEpoch(ms,
   isUtc: true)`.
5. **Times of day are `"HH:mm:ss"` strings, zero-padded, 24-hour, or `null`.**
   See §5.

---

## 3. Method channel — the complete method list

Exactly 34 methods. The names are the literal strings passed to
`MethodChannel.invokeMethod`.

```
initialize
setBaseUrl
setMqttUrl
setMqttClientIdPrefix
resetUrls
setOrCreateUser
getUser
getUserId
isLocationPermissionsGranted
isLocationSettingsOn
hasBackgroundPermission
requestLocationPermissions
requestBackgroundLocationPermission
openLocationSettings
openAppSettings
isBackgroundTrackingDegraded
setTraceMode
startTracking
stopTracking
refreshTracking
isLocationTracking
setOfflineTracking
setLoggingEnabled
setBroadcastingEnabled
isOnTrip
getTripId
updateCurrentLocation
uploadOfflineData
getSettingsFromRemote
android.requestNotificationPermission
android.requestDisableBatteryOptimization
android.isIgnoringBatteryOptimizations
android.openAutostartSettings
ios.setLocationDisabledNotificationEnabled
```

Anything not on this list must be answered with `notImplemented()` /
`FlutterMethodNotImplemented`.

The five namespaced methods are the only asymmetric ones: the four
`android.*` methods need only exist in the Android plugin, and
`ios.setLocationDisabledNotificationEnabled` only in the iOS plugin. The Dart
layer already short-circuits them on the wrong platform (it checks
`defaultTargetPlatform` before invoking), so they will not be called there —
but answering `notImplemented()` is still the correct fallback.

`arguments` is `null` for every method whose row below says "none". Otherwise
it is a `map` with exactly the listed keys.

### 3.1 Initialization & configuration

| Method | Arguments | Result |
| --- | --- | --- |
| `initialize` | `TraceConfig` map (§4.1) | `null` |
| `setBaseUrl` | `{ "url": string }` | `null` |
| `setMqttUrl` | `{ "url": string }` | `null` |
| `setMqttClientIdPrefix` | `{ "prefix": string }` | `null` |
| `resetUrls` | none | `null` |

`initialize` must, in this order:

1. Log each entry of the config's `warnings` (both native `TraceConfig` types
   compute these) through the SDK log sink, so they reach the `logs` event
   channel.
2. Apply `baseUrl`, `mqttUrl` and `mqttClientIdPrefix` **only when non-null**.
   A null value means "leave the native default in place" — do not call the
   corresponding setter with an empty string.
3. Call the native `initialize` with the API key and MQTT credentials
   (`BarikoiTrace.initialize(context, TraceConfig(...))` on Android;
   `BarikoiTrace.initialize(TraceConfig(...))` on iOS).

Calling `initialize` twice must be safe (idempotent re-configuration), and
every other method must fail with `NOT_INITIALIZED` until it has succeeded
once.

iOS additionally calls `BarikoiTrace.handleLaunch(options:)` from
`application(_:didFinishLaunchingWithOptions:)`; that is an app-delegate
concern with no channel method.

### 3.2 User

| Method | Arguments | Result |
| --- | --- | --- |
| `setOrCreateUser` | `{ "name": string?, "email": string?, "phone": string }` | `TraceUser` map (§4.2), non-null |
| `getUser` | none | `TraceUser` map, or `null` when no user is set |
| `getUserId` | none | `string`, or `null` |

`setOrCreateUser` returning `null` is a contract violation; the Dart side
raises `TraceException(NO_DATA)` if it happens.

### 3.3 Permissions & settings

| Method | Arguments | Result |
| --- | --- | --- |
| `isLocationPermissionsGranted` | none | `bool` |
| `isLocationSettingsOn` | none | `bool` |
| `hasBackgroundPermission` | none | `bool` |
| `requestLocationPermissions` | none | `bool` |
| `requestBackgroundLocationPermission` | none | `bool` |
| `openLocationSettings` | none | `bool` |
| `openAppSettings` | none | `bool` |
| `isBackgroundTrackingDegraded` | none | `bool` |

A `null` result is decoded as `false` rather than throwing, but implementations
must always return a real `bool`.

Per-method semantics:

- **`requestLocationPermissions`** — prompts for foreground/when-in-use
  permission and resolves **after the prompt settles**, to whether the
  permission is now granted. Android: `ACCESS_FINE_LOCATION` +
  `ACCESS_COARSE_LOCATION` via the activity's permission result callback; the
  result must be delivered exactly once even across an activity recreation.
  iOS: `requestWhenInUseAuthorization`, resolved from the
  `locationManagerDidChangeAuthorization` callback. If permission is already
  granted, return `true` immediately without prompting. If the user previously
  chose "don't ask again" / "never", return the current (false) state rather
  than hanging.
- **`requestBackgroundLocationPermission`** — same protocol for
  `ACCESS_BACKGROUND_LOCATION` / `requestAlwaysAuthorization`. Both platforms
  require foreground permission first; when it is missing, return `false`
  without prompting.
- **`openLocationSettings`** — Android opens the system location settings
  screen (`Settings.ACTION_LOCATION_SOURCE_SETTINGS`, or the SDK's
  `requestLocationServices` flow). iOS has no deep link to that toggle, so it
  opens the app's own settings page, which carries the Location row. Returns
  whether a screen was actually opened.
- **`openAppSettings`** — the app's system settings page on both platforms
  (`Settings.ACTION_APPLICATION_DETAILS_SETTINGS` /
  `UIApplication.openSettingsURLString`). Returns whether it opened.
- **`isBackgroundTrackingDegraded`** — a single "background tracking may be
  unreliable" signal. iOS returns
  `BarikoiTrace.isBackgroundTrackingDegraded` directly (Low Power Mode, a
  downgraded/denied `Always` authorization, or Background App Refresh off).
  Android has no native equivalent and must compute the same idea: `true` when
  **any** of these hold — background location permission missing, the app is
  not exempt from battery optimization, or location services are off.

Both `request*` methods need a foreground `Activity` on Android. When the
plugin is not attached to one, fail with `NO_ACTIVITY` (§6) rather than
returning `false`.

### 3.4 Tracking

| Method | Arguments | Result |
| --- | --- | --- |
| `setTraceMode` | `{ "mode": TraceMode map (§4.3) }` | `null` |
| `startTracking` | `{ "mode": TraceMode map, "withTrip": bool }` | `null` |
| `stopTracking` | none | `null` |
| `refreshTracking` | none | `null` |
| `isLocationTracking` | none | `bool` |
| `setOfflineTracking` | `{ "enabled": bool }` | `null` |
| `setLoggingEnabled` | `{ "enabled": bool }` | `null` |
| `setBroadcastingEnabled` | `{ "enabled": bool }` | `null` |

`withTrip` is always present — the Dart side defaults it to `false` and never
omits the key.

`refreshTracking` maps to `BarikoiTrace.refreshTracking()` on iOS. Android's
facade has no such method; call `LocTraceManager.refreshTracking()`, or
re-apply the stored mode to the running session, to get the same behaviour.

`setBroadcastingEnabled(true)` is what makes the `location_updates` event
channel produce anything; `setLoggingEnabled(true)` is what makes `logs`
produce anything.

### 3.5 Trips

| Method | Arguments | Result |
| --- | --- | --- |
| `isOnTrip` | none | `bool` |
| `getTripId` | none | `string`, or `null` when not on a trip |

Android's redundant `getCurrentTrip()` is deliberately not bridged.

### 3.6 Location

| Method | Arguments | Result |
| --- | --- | --- |
| `updateCurrentLocation` | none | `TraceLocation` map (§4.4), non-null |
| `uploadOfflineData` | none | `null` |
| `getSettingsFromRemote` | none | `TraceMode` map (§4.3), non-null |

`updateCurrentLocation` requests a single fresh fix independently of any
tracking session. Fail with `PERMISSION` when permission is missing and
`LOCATION` when no fix could be obtained — do not return `null`.

`uploadOfflineData` is fire-and-forget: return as soon as the upload has been
scheduled, do not block on it.

`getSettingsFromRemote` returns the company settings. Note that both native
SDKs also **persist** them as a side effect (`setTraceModeWithTiming`), so the
returned mode is already the stored one — the plugin cannot prevent that and
must not pretend otherwise. Passing the result to `setTraceMode` is therefore
optional, and only matters for applying it to a *running* session.

### 3.7 Android-only

| Method | Arguments | Result |
| --- | --- | --- |
| `android.requestNotificationPermission` | none | `bool` |
| `android.requestDisableBatteryOptimization` | `{ "onlyIfNeeded": bool }` | `null` |
| `android.isIgnoringBatteryOptimizations` | none | `bool` |
| `android.openAutostartSettings` | none | `null` |

- `android.requestNotificationPermission` — requests `POST_NOTIFICATIONS`,
  resolving after the prompt to whether it is granted. On API < 33 return
  `true` without prompting.
- `android.requestDisableBatteryOptimization` — with `onlyIfNeeded: true`,
  check `PowerManager.isIgnoringBatteryOptimizations` first and skip the dialog
  when the app is already exempt.
- `android.isIgnoringBatteryOptimizations` — `true` means the app **is** exempt
  (the healthy state). Pass the native value through **unchanged**: the SDK's
  `isBatteryOptimizationEnabled()` is a misnomer that already returns
  `PowerManager.isIgnoringBatteryOptimizations()`. Only the name is corrected
  here, not the polarity — inverting it would report the opposite of the truth.
- `android.openAutostartSettings` — opens the OEM autostart / protected-apps
  screen where one exists; a silent no-op on stock Android.

### 3.8 iOS-only

| Method | Arguments | Result |
| --- | --- | --- |
| `ios.setLocationDisabledNotificationEnabled` | `{ "enabled": bool }` | `null` |

Maps to `BarikoiTrace.setLocationDisabledNotificationEnabled(_:)`. Default is
enabled; the host calls this with `false` before `startTracking` to suppress
both the notification and its authorization prompt.

---

## 4. Map schemas

### 4.1 `TraceConfig` (Dart → platform, `initialize` arguments)

| Key | Type | Notes |
| --- | --- | --- |
| `apiKey` | `string` | Never null. May be empty (warned about, not rejected). |
| `mqttUsername` | `string` | Never null. |
| `mqttPassword` | `string` | Never null. |
| `baseUrl` | `string?` | **`null` means "keep the native default"** — do not substitute a URL. |
| `mqttUrl` | `string?` | Same. |
| `mqttClientIdPrefix` | `string?` | Same. Native defaults are `AndroidClient-` / `iOSClient-`. |

The map always carries all six keys.

### 4.2 `TraceUser` (platform → Dart)

| Key | Type | Dart fallback if absent |
| --- | --- | --- |
| `userId` | `string` | `""` |
| `name` | `string?` | `null` |
| `email` | `string?` | `null` |
| `phone` | `string?` | `null` |
| `companyId` | `string?` | `null` |
| `group` | `string?` | `null` |
| `lastLat` | `double` | `0.0` |
| `lastLon` | `double` | `0.0` |
| `updatedAt` | `int64` | epoch `0` |

`updatedAt` is epoch **milliseconds** — Android's `TraceUser.updatedAt` as-is;
iOS's `Double` epoch-millis rounded to an integer.

### 4.3 `TraceMode` (both directions)

| Key | Type | Values |
| --- | --- | --- |
| `desiredAccuracy` | `string` | `"HIGH"` \| `"MEDIUM"` \| `"LOW"` |
| `updateInterval` | `int` | Seconds. `0` = distance-based instead. |
| `distanceFilter` | `int` | Meters. `0` = interval-based instead. |
| `stopDuration` | `int` | Seconds. |
| `accuracyFilter` | `int` | Meters. |
| `trackingMode` | `int` | `0` passive, `1` reactive, `2` active, `3` custom. |
| `offline` | `bool` | |
| `debug` | `bool` | |
| `pingSyncInterval` | `int` | Seconds. `0` = no pinging. |
| `startTime` | `string?` | `"HH:mm:ss"` or `null`. See §5. |
| `endTime` | `string?` | `"HH:mm:ss"` or `null`. See §5. |

All eleven keys are always present in both directions.

Unrecognized `desiredAccuracy` decodes to `HIGH` and unrecognized
`trackingMode` to `3` (custom), matching both natives' lenient `fromString`.

The Dart presets encode exactly as the native ones, and native code must decode
them to the identical values:

| Preset | accuracy | updateInterval | distanceFilter | stopDuration | accuracyFilter | trackingMode | offline | debug | pingSyncInterval |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `active` | `HIGH` | 5 | 0 | 0 | 50 | 2 | true | false | 0 |
| `passive` | `MEDIUM` | 0 | 100 | 0 | 300 | 0 | true | false | 120 |
| `reactive` | `HIGH` | 0 | 100 | 0 | 100 | 1 | true | false | 30 |

### 4.4 `TraceLocation` (platform → Dart)

| Key | Type | Dart fallback if absent | Source |
| --- | --- | --- | --- |
| `latitude` | `double` | `0.0` | `Location.latitude` / `coordinate.latitude` |
| `longitude` | `double` | `0.0` | `Location.longitude` / `coordinate.longitude` |
| `altitude` | `double` | `0.0` | `Location.altitude` / `altitude` |
| `accuracy` | `double` | `0.0` | `Location.accuracy` / `horizontalAccuracy` |
| `verticalAccuracy` | `double?` | `null` | `Location.verticalAccuracyMeters` (API 26+) / `verticalAccuracy` |
| `speed` | `double?` | `null` | m/s |
| `bearing` | `double?` | `null` | degrees clockwise from true north |
| `timestampMs` | `int64` | epoch `0` | `Location.time` / `timestamp.timeIntervalSince1970 * 1000` |
| `isMock` | `bool?` | `null` | `Location.isMock` / `isSimulatedBySoftware` |
| `provider` | `string?` | `null` | `Location.provider`, or a synthetic label on iOS |

Send `null` — not `0` — for `speed`, `bearing`, `verticalAccuracy` and
`isMock` when the platform does not have a valid value:

- Android: `hasSpeed()` / `hasBearing()` / `hasVerticalAccuracy()` returning
  false, or the API level being below the accessor's minimum.
- iOS: `CLLocation` reports `speed`, `course` and `verticalAccuracy` as
  **negative** when invalid.

Flattening those to `0` would be read as "stationary, facing north", which is
why the contract keeps them nullable.

### 4.5 `TraceLogEntry` (platform → Dart)

| Key | Type | Dart fallback if absent |
| --- | --- | --- |
| `level` | `string` | `""` |
| `tag` | `string` | `""` |
| `message` | `string` | `""` |
| `timestampMs` | `int64` | epoch `0` |

`level`, `tag` and `message` come straight from the native
`TraceLogListener.onLog(level:tag:message:)` callback. `timestampMs` is added
by the plugin at emit time — the native callback does not carry it. Levels in
practice are `DEBUG`, `INFO`, `WARN`, `ERROR`, but the field is a free string
and Dart does not validate it.

---

## 5. The daily-window time sentinel

`TraceMode.startTime` / `endTime` describe an optional daily tracking window.

**`null` means "no daily window" — track all day.** It is a sentinel, not a
missing value, and it must survive the round trip in both directions.

| Dart | Wire | Android | iOS |
| --- | --- | --- | --- |
| `null` | `null` | `LocalTime.MIN` (`00:00`) | `TraceMode.dayStart` (`00:00:00`) |
| `null` (end) | `null` | `LocalTime.MAX` (`23:59:59.999999999`) | `TraceMode.dayEnd` (`23:59:59`) |
| `TraceTimeOfDay(hour: 9)` | `"09:00:00"` | `LocalTime.of(9, 0, 0)` | `DateComponents(hour: 9, minute: 0, second: 0)` |

Rules:

1. **Dart → platform.** A `null` on the wire means "apply the native
   full-day default" (`LocalTime.MIN`/`MAX`, `dayStart`/`dayEnd`). A string is
   parsed as `HH:mm:ss` and applied literally.
2. **Platform → Dart.** When the native value equals the full-day default, send
   `null`. Send a `"HH:mm:ss"` string only for a real, narrower window.
   Android must treat `LocalTime.MAX` as the sentinel even though its string
   form carries nanoseconds; do not send `"23:59:59.999999999"`.
3. `"00:00:00"` and `"23:59:59"` sent explicitly are **not** the sentinel —
   they are a real (if full-day-shaped) window, and Dart keeps them
   distinguishable from `null`.
4. Dart accepts `"HH:mm"` as well as `"HH:mm:ss"` when decoding, and truncates
   fractional seconds, but always **emits** `"HH:mm:ss"`.
5. An unparseable or out-of-range string decodes to `null` (the sentinel)
   rather than throwing.

---

## 6. Errors

Every failure is reported as a channel error — `result.error(code, message,
details)` on Android, `FlutterError(code:message:details:)` on iOS — never as a
success value carrying an error payload, and never as an uncaught native
exception.

The Dart layer converts each `PlatformException` into
`TraceException(code: e.code, message: e.message ?? '')` **verbatim**. There is
no mapping table: whatever `code` string the platform sends is what host apps
branch on, so a code added natively later needs no plugin release.

`details` is ignored by the Dart layer. Put everything the caller needs in
`message`.

### 6.1 Codes from the native SDKs

Pass the native `TraceError.code` through unchanged. On Android, unwrap
`TraceException.error.code`; on iOS, read `TraceError.code`.

| Code | Meaning |
| --- | --- |
| `NO_USER` | No user found. Create a user first. |
| `NO_KEY` | API key not set. |
| `NO_DATA` | Required data is missing. |
| `NETWORK` | No network connection available. |
| `PERMISSION` | Location permission not granted. |
| `LOCATION` | Could not determine location. |
| `SERVER` | Server error occurred. |
| `TRIP` | Trip-state precondition failed. |
| `MOCK` | Mock location detected. |
| `JSON` | Response parsing error. |
| `NO_COMPANY` | User has no company association. |

### 6.2 Plugin-only codes

Raised by the bridge, never by the tracking SDKs.

| Code | Raise it when |
| --- | --- |
| `NOT_INITIALIZED` | Any method other than `initialize` is called before `initialize` has succeeded. Android's facade throws `IllegalStateException` for this — catch it and report this code. |
| `NO_ACTIVITY` | Android only: a call needing a foreground `Activity` (`requestLocationPermissions`, `requestBackgroundLocationPermission`, `openLocationSettings`, `openAppSettings`, `android.requestNotificationPermission`, `android.requestDisableBatteryOptimization`, `android.openAutostartSettings`) arrives while the plugin is detached from one. |
| `INTERNAL` | Any other native throwable that maps to none of the above. Put the throwable's message in `message`. |

### 6.3 Threading

Every `result.success` / `result.error` must be delivered **once** and on the
platform's main thread. Suspend/async work must not answer twice — in
particular, a permission request that is cancelled and re-issued must not
complete an already-completed result.

---

## 7. Event channels

### 7.1 `barikoi_trace_flutter/location_updates`

- **Payload:** one `TraceLocation` map (§4.4) per `success` event.
- **Source:** `BarikoiTrace.locationUpdates` — a `SharedFlow<Location>` on
  Android, an `AsyncStream<CLLocation>` on iOS.
- **Gating:** silent until `setBroadcastingEnabled(true)`.
- **Lifecycle:** `onListen` subscribes to the native flow/stream; `onCancel`
  unsubscribes. Dart treats the stream as broadcast and creates it once per
  plugin instance, so `onListen` may be entered with an already-running
  session.
- **Errors:** `sink.error(code, message, details)` with the §6 codes. Dart maps
  these to `TraceException` exactly as it does method errors. Prefer not to end
  the stream on a recoverable error.
- **Backpressure:** none. Drop rather than buffer if the native side outpaces
  the channel.

### 7.2 `barikoi_trace_flutter/logs`

- **Payload:** one `TraceLogEntry` map (§4.5) per `success` event.
- **Source:** the native `TraceLogListener` — `BarikoiTrace.setLogListener` on
  both platforms. The plugin installs exactly one listener and fans it out.
- **Gating:** what the listener receives is governed by `setLoggingEnabled`.
  The `initialize` config warnings (§3.1) must reach this channel too.
- **`timestampMs`:** stamped by the plugin when the callback fires
  (`System.currentTimeMillis()` / `Date().timeIntervalSince1970 * 1000`).
- **Errors:** the log channel should not emit errors. If the listener cannot be
  installed, emit nothing rather than failing the stream.
- **Re-entrancy:** the log callback can fire on any thread, and can fire from
  inside SDK code that the plugin itself called. Hop to the main thread before
  touching the event sink, and never log from inside the sink.

---

## 8. Version pin

The Dart layer exposes `BarikoiTrace.nativeSdkVersion = '0.4.0'`. Both native
implementations must depend on that version of their respective SDK. Bump the
constant and this line together.
