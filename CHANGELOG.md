# Changelog

All notable changes to `barikoi_trace_flutter`.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the package follows [semantic versioning](https://semver.org/) — below
`1.0.0`, treat a minor bump as breaking.

---

## 0.1.0

Initial release. Wraps native SDK **0.4.0** on both platforms
(`com.github.barikoi.BarikoiTrace-android-sdk:barikoitrace:0.4.0` and the `BarikoiTrace` Swift package
`0.4.0`), exposed as `BarikoiTrace.nativeSdkVersion`.

### Added

**One static facade.** `BarikoiTrace` mirrors `BarikoiTrace.kt` and
`BarikoiTrace.swift` method for method, so a call site reads the same on all
three platforms. Every call is asynchronous, including the ones whose native
counterpart is synchronous, because each crosses a platform channel.

- **Lifecycle and configuration** — `initialize`, `setBaseUrl`, `setMqttUrl`,
  `setMqttClientIdPrefix`, `resetUrls`.
- **User** — `setOrCreateUser`, `getUser`, `getUserId`.
- **Permissions and settings** — `isLocationPermissionsGranted`,
  `isLocationSettingsOn`, `hasBackgroundPermission`,
  `requestLocationPermissions`, `requestBackgroundLocationPermission`,
  `openLocationSettings`, `openAppSettings`, `isBackgroundTrackingDegraded`.
- **Tracking** — `setTraceMode`, `startTracking` (with an optional trip),
  `stopTracking`, `refreshTracking`, `isLocationTracking`, `setOfflineTracking`,
  `setLoggingEnabled`, `setBroadcastingEnabled`.
- **Trips** — `isOnTrip`, `getTripId`.
- **Location and sync** — `updateCurrentLocation`, `uploadOfflineData`,
  `getSettingsFromRemote`.
- **Streams** — `locationUpdates` (broadcast, gated by
  `setBroadcastingEnabled`) and `logs` (broadcast, gated by
  `setLoggingEnabled`), both delivering typed models and mapping platform
  errors to `TraceException` exactly as method calls do.
- **Platform escape hatches** — `BarikoiTrace.android`
  (`requestNotificationPermission`, `requestDisableBatteryOptimization`,
  `isIgnoringBatteryOptimizations`, `openAutostartSettings`) and
  `BarikoiTrace.ios` (`setLocationDisabledNotificationEnabled`). Each no-ops
  with a benign value on the other platform, so cross-platform code can call
  them unconditionally.

**Models.** `TraceConfig`, `TraceMode` (with `TraceModeBuilder`,
`DesiredAccuracy`, `TrackingMode` and the plugin's own `TraceTimeOfDay`),
`TraceUser`, `TraceLocation`, `TraceLogEntry`, `TraceException` /
`TraceErrorCode`. Every one is an immutable value type with `==`, `hashCode`
and a readable `toString` — `TraceConfig.toString` redacts its two secrets.

- The three `TraceConfig` endpoint fields are **nullable and null by default**;
  null means "use the native SDK's own default" rather than freezing today's
  defaults into this package. `effectiveBaseUrl`, `effectiveMqttUrl`,
  `isMqttTransportEncrypted` and `warnings` let a host app assert on its
  configuration before shipping.
- `TraceMode`'s three presets are numerically identical to the native
  `ACTIVE` / `REACTIVE` / `PASSIVE`, and `TraceModeBuilder` applies the same
  floors (interval ≥ 5 s, distance ≥ 10 m, accuracy ≥ 20 m).
- A null `startTime` / `endTime` is the sentinel for "no daily window" and
  round-trips as null, keeping "unset" distinguishable from "explicitly
  midnight".
- `TraceLocation.speed`, `.bearing`, `.verticalAccuracy` and `.isMock` are
  nullable rather than flattened to `0`, which would read as "stationary,
  facing north".

**Error handling.** Native error codes are passed through **verbatim** — no
translation table — so a code the native SDKs add later reaches host apps
without a plugin release. `TraceErrorCode` names the eleven shared codes plus
three plugin-only ones: `NOT_INITIALIZED`, `NO_ACTIVITY` (Android) and
`INTERNAL`.

**Android implementation.** Kotlin, one method channel and two event channels,
every handler on a `Main.immediate` scope with SDK work moved to
`Dispatchers.IO`. Permission prompts resolve after the prompt settles and
survive a configuration change; a detach answers every waiter with the current
state rather than leaving a Dart future hanging. `startTracking` pre-checks the
preconditions the native call fails silently on and raises the SDK's own codes
instead. The log channel replays up to 200 buffered lines to its first
subscriber, so `initialize`-time configuration warnings are not lost.

**iOS implementation.** Swift, sources laid out as a Swift package so one copy
serves both SPM and CocoaPods, with a `PrivacyInfo.xcprivacy` manifest. The SDK
is initialized from the plugin's `UIApplicationDelegate` hook — the only place
`BGTaskScheduler.register` can legally run — and `handleLaunch(options:)` is
called there too, which is what resumes tracking after a
significant-location-change relaunch. The plugin persists the MQTT client-id
prefix, which the SDK keeps in memory only. Every `FlutterResult` is delivered
exactly once, on the main thread.

**Documentation.**

- `README.md` — installation (including the JitPack requirement and the iOS
  SPM/CocoaPods situation), configuration, platform setup, API reference with
  per-platform availability, modes, offline behaviour, the MQTT contract, error
  codes and platform differences.
- `docs/WIRE_CONTRACT.md` — the normative platform-channel specification: 34
  methods, the map schemas, the time sentinel, error and threading rules.
- `docs/BACKGROUND_EXECUTION.md` — what each platform can and cannot promise,
  what happens to the Dart streams when the engine detaches, the
  relaunch-after-kill paths, and the on-device test matrix.
- `example/` — a single-screen demo covering permissions in the correct order,
  sign-in, the mode picker, start/stop with a trip, live fixes, the log console
  and the degraded banner, with credentials supplied through `--dart-define`.

### Known limitations

- **The Dart streams are a foreground mirror.** Tracking runs natively and
  survives the UI, but `locationUpdates` and `logs` need a live Flutter engine.
  `locationUpdates` has no buffer and no replay; there is no background-isolate
  callback for a fix delivered while the engine is gone.
- **iOS defers the API key by one launch.** Because the SDK must be initialized
  during app launch, the key passed to `initialize` from Dart is persisted and
  takes effect on the next launch. Set `BarikoiTraceApiKey` in `Info.plist` to
  make the first launch of a fresh install work.
- **iOS requires plugin registration before `super`** in
  `didFinishLaunchingWithOptions`, which is Flutter's default. Otherwise no
  background task is registered and relaunch-after-kill does not resume
  tracking. The plugin logs a WARN; Dart cannot detect it any other way.
- **Android needs core library desugaring in the application module.** It is
  not transitive, and the native SDK uses `java.time` at minSdk 24.
- **CocoaPods needs a `BarikoiTrace.podspec` you supply.** The iOS SDK ships as
  a Swift Package only; Swift Package Manager is the supported path.
- **`TraceMode.copyWith` cannot clear `startTime` / `endTime`.** Omitting them
  keeps the current value; construct a new `TraceMode` to reset a window to
  all-day.
- **`TraceMqttState` is reserved and never emitted.** Neither native SDK
  exposes a connection-state callback yet; the enum exists so that adding one
  is additive.
