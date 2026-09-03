# barikoi_trace_flutter

Flutter plugin for background location tracing with Barikoi Trace.
Authenticates a user against the Barikoi Trace backend, streams their location
to an MQTT broker while the app runs — foreground *or* background — and queues
fixes to disk when the network is gone, flushing them when it returns.

This package is a **binding, not an implementation**. Tracking runs entirely in
the native SDKs — [`barikoitrace`](https://github.com/barikoi/BarikoiTrace-android-sdk)
on Android and [`BarikoiTrace`](https://github.com/barikoi/BarikoiTrace-ios-sdk)
on iOS, both at `0.4.0` — and Dart drives them over one method channel and two
event channels. Nothing about tracking depends on the Flutter engine being
alive; see [Background execution](#background-execution--read-this-before-shipping).

- **Requirements:** Flutter 3.22+, Dart 3.4+, Android minSdk 24 / compileSdk 35 / Kotlin 2.0+ / Java 8 desugaring, iOS 15+
- **Wraps:** native SDK `0.4.0` on both platforms (`BarikoiTrace.nativeSdkVersion`)
- **License:** MIT

---

## Table of contents

- [Installation](#installation)
- [Configuration](#configuration)
- [Platform setup](#platform-setup)
- [Quick start](#quick-start)
- [API reference](#api-reference)
- [Tracking modes](#tracking-modes)
- [Offline behavior](#offline-behavior)
- [MQTT contract](#mqtt-contract)
- [Error handling](#error-handling)
- [Background execution — read this before shipping](#background-execution--read-this-before-shipping)
- [Platform differences](#platform-differences)
- [Example app](#example-app)
- [Versioning](#versioning)

---

## Installation

```yaml
dependencies:
  barikoi_trace_flutter: ^0.1.0
```

```dart
import 'package:barikoi_trace_flutter/barikoi_trace_flutter.dart';
```

Two things do **not** come for free with `flutter pub get`.

### Android — the JitPack repository

The native Android SDK is published through JitPack, which no stock Flutter
project declares. The plugin's own `android/build.gradle` tries to add the
repository to every project in the build, and on a default Flutter app that
works. It cannot work on a project that opts into
`RepositoriesMode.FAIL_ON_PROJECT_REPOS` — Gradle rejects the addition at the
moment it happens, and the plugin logs a warning instead of failing silently.

Declare it yourself and the question never comes up. In `android/build.gradle`:

```groovy
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = 'https://jitpack.io' }
    }
}
```

or, if your project centralizes repositories, in `android/settings.gradle`:

```groovy
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri('https://jitpack.io') }
    }
}
```

Without it, the build fails to resolve
`com.github.barikoi.BarikoiTrace-android-sdk:barikoitrace:0.4.0`. The first build of a tag is compiled
by JitPack on demand and takes a few minutes; later builds come from its cache.

### iOS — Swift Package Manager, or a podspec you supply

The iOS SDK ships as a **Swift Package only**. Its repository contains a
`Package.swift` and no `BarikoiTrace.podspec`, and nothing is published to the
CocoaPods trunk.

**Supported path — SPM.** Flutter 3.24+ can build plugins with Swift Package
Manager, and it is on by default from 3.44:

```sh
flutter config --enable-swift-package-manager
```

The plugin's `ios/barikoi_trace_flutter/Package.swift` then declares the SDK
dependency and resolves `BarikoiTrace` 0.4.0 with no CocoaPods involvement.

**On CocoaPods** the plugin's podspec declares
`s.dependency 'BarikoiTrace', '0.4.0'`, which cannot resolve out of the box —
`pod install` fails with *"Unable to find a specification for `BarikoiTrace`"*.
Until a podspec is published, point at one from your own `ios/Podfile`, where a
host-app declaration takes precedence:

```ruby
target 'Runner' do
  use_frameworks!
  pod 'BarikoiTrace',
      :podspec => 'https://raw.githubusercontent.com/barikoi/BarikoiTrace-ios-sdk/0.4.0/BarikoiTrace.podspec'
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
```

Such a podspec must also carry the SDK's own `CocoaMQTT` dependency
(`s.dependency 'CocoaMQTT', '~> 2.1.6'`) and link `libsqlite3` — `Package.swift`
declares both, and a podspec inherits neither.

Either way, `ios/Podfile` needs `platform :ios, '15.0'`.

---

## Configuration

The plugin reads no config file, no manifest `meta-data` and no environment
variable. You hand it a `TraceConfig`, and that is the entire contract:

```dart
await BarikoiTrace.initialize(const TraceConfig(
  apiKey: '…',        // Barikoi dashboard
  mqttUsername: '…',  // issued separately, per company
  mqttPassword: '…',
));
```

The API key and the two broker credentials are **three separate secrets**. None
is derivable from the others, and the broker pair is not a public identifier —
a leaked pair lets anyone publish fixes to your company's topics.

Endpoints default to production and are overridable for staging or a
self-hosted deployment:

```dart
const TraceConfig config = TraceConfig(
  apiKey: String.fromEnvironment('BARIKOI_API_KEY'),
  mqttUsername: String.fromEnvironment('BARIKOI_MQTT_USERNAME'),
  mqttPassword: String.fromEnvironment('BARIKOI_MQTT_PASSWORD'),
  baseUrl: 'https://api.staging.example.com/api/v1/',
  mqttUrl: 'ssl://broker.staging.example.com:8883',
  mqttClientIdPrefix: 'fleet-flutter-',  // only if the broker ACL matches on client id
);

assert(config.warnings.isEmpty, config.warnings.toString());
await BarikoiTrace.initialize(config);
```

| Field | Default | |
|---|---|---|
| `apiKey` | — | required |
| `mqttUsername` / `mqttPassword` | — | required |
| `baseUrl` | `https://api.trace.bmapsbd.com/api/v1/` | trailing slash normalized natively |
| `mqttUrl` | `tcp://broker.trace.bmapsbd.com:1883` | **plaintext** — see below |
| `mqttClientIdPrefix` | `AndroidClient-` / `iOSClient-` | per platform |

The three endpoint fields are **nullable in Dart and null by default**, unlike
their native counterparts. Null means "use whatever the native SDK's own
default is": the plugin sends the key as an explicit null and the platform side
does not call the corresponding setter. Freezing today's defaults into this
package as Dart string literals would silently override any future change to
them. `config.effectiveBaseUrl` and `config.effectiveMqttUrl` tell you what
will actually be used.

**The default broker is plaintext.** `mqttUrl` accepts `tcp`/`mqtt`/`ws`
(plaintext) and `ssl`/`mqtts`/`tls`/`wss` (TLS), and the SDK default is `tcp://`
— meaning both broker credentials and every location fix travel unencrypted.
`config.isMqttTransportEncrypted` tells you which you got, and
`config.warnings` names it in words. Point `mqttUrl` at a TLS listener
(port 8883) for anything carrying real user locations.

### Where the values come from

Compiling secrets into the binary keeps them out of *git*, not out of the
*app*. In increasing order of safety:

- **`--dart-define`** (what the example app uses). Values land in the binary;
  fine for local development and for the scoped, rotatable API key.
- **Per-flavor defines / `--dart-define-from-file`**, so a debug build cannot
  reach production credentials.
- **Issued by your own backend at runtime** — your service authenticates its
  user and returns the broker credentials, and you call `initialize` once they
  arrive. This is the only option where a decompiled app yields nothing, and it
  is the right one for the MQTT password.

Rotate anything that has ever been committed. Removing it from `HEAD` does not
remove it from history, and it does not un-leak a published artifact.

### Changing endpoints mid-session

`setBaseUrl`, `setMqttUrl`, `setMqttClientIdPrefix` and `resetUrls` exist for
switching a *running* app between environments. Prefer `TraceConfig`:
`initialize` resumes tracking when the previous process was tracking, and a
resumed session builds its MQTT client immediately, so an endpoint set
afterwards is too late for that first client. Note also that `setBaseUrl` is
destructive on purpose — a different backend means a different user namespace,
so the native SDK clears the cached user and stops tracking when the value
changes. `resetUrls()` does the same.

---

## Platform setup

A plugin cannot grant its own permissions or entitlements. These steps are the
host app's job, and tracking will silently underperform without them.

### Android

**1. `android/app/build.gradle` — minSdk, desugaring, Kotlin.**

```groovy
android {
    compileSdk = 35

    compileOptions {
        coreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    defaultConfig {
        minSdk = 24
    }
}

dependencies {
    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"
}
```

Core library desugaring is **required and not transitive**. The native SDK
models the daily tracking window with `java.time.LocalTime`, which does not
exist below API 26; the plugin desugars, but the application module has to as
well. Skip it and the app builds, then crashes with
`NoClassDefFoundError: java.time.LocalTime` the first time a `TraceMode` is
constructed. minSdk 24 is the native SDK's own floor and cannot go lower, and
Kotlin must be 2.0+ — the SDK is compiled with 2.0.21 and Kotlin metadata is
not backwards readable.

**2. `android/app/src/main/AndroidManifest.xml`.** The SDK's manifest already
declares its permissions, foreground service, WorkManager job and boot receiver,
and they merge into yours. Declaring them in your own manifest anyway makes what
you are asking the user for reviewable in one place:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

**3. Runtime permissions, in order.** Android will not grant background
location in the same prompt as foreground location, and asking out of order
gets a silent denial:

```dart
if (await BarikoiTrace.requestLocationPermissions()) {
  await BarikoiTrace.requestBackgroundLocationPermission();
  await BarikoiTrace.android.requestNotificationPermission();  // API 33+
}
```

Nothing else is needed in `MainActivity`: the plugin is `ActivityAware` and
registers its own `RequestPermissionsResultListener`, which `FlutterActivity`
forwards to.

**4. OEM process-kill workarounds.** Offer both, and expect to need them:

```dart
await BarikoiTrace.android.requestDisableBatteryOptimization(onlyIfNeeded: true);
await BarikoiTrace.android.openAutostartSettings();
```

### iOS

**1. `ios/Runner/Info.plist`.**

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs your location to provide location-based features.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app tracks your location in the background so [specific, real, reviewable feature] keeps working when the app isn't open.</string>

<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>processing</string>
</array>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.barikoi.trace.offlineflush</string>
</array>
```

The `NSLocationAlwaysAndWhenInUseUsageDescription` copy matters more than it
looks. App Review expects a concrete, user-visible reason for background
location; generic copy is a common rejection cause. Missing
`BGTaskSchedulerPermittedIdentifiers` makes the SDK's task registration throw
at launch.

**2. Capabilities.** Xcode → Signing & Capabilities → Background Modes →
enable **Location updates** and **Background processing**. Push Notifications
is not required.

**3. AppDelegate ordering — this one is easy to get wrong.**
iOS requires `BGTaskScheduler.register` to run before
`application(_:didFinishLaunchingWithOptions:)` returns, and forbids
registering the same identifier twice. A Dart method call arrives long after
launch and can arrive repeatedly (a hot restart alone re-runs `main()`), so the
plugin cannot initialize the SDK from the `initialize` channel method. It
initializes from its own `UIApplicationDelegate` hook instead — which only runs
if your AppDelegate registers plugins **inside**
`didFinishLaunchingWithOptions` and **before** calling `super`:

```swift
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)   // must come first
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

That is exactly what Flutter's own template does, so the default works. Move
the registration after `super`, or hand-roll an AppDelegate that never forwards
the callback, and the plugin logs a WARN on the `logs` stream saying that no
background task is registered, background offline flushing is disabled, and a
significant-location-change relaunch will not resume tracking. There is no way
to detect that from Dart — watch the log stream.

**4. The first-launch API-key caveat.** Because the SDK is initialized at
launch, it reconstructs its configuration from what was persisted on a previous
run. On the **very first launch of a fresh install** nothing is persisted, so
that session starts without an API key. Your Dart `initialize` call then
persists the key and applies everything that can still be applied
post-launch — broker credentials, `mqttUrl`, the client-id prefix, `baseUrl` —
but the API key itself only takes effect on the *next* launch, and the plugin
logs a WARN saying so. The same warning appears whenever the key passed to
`initialize` differs from the one the process launched with.

To make the first launch work, put the key in `Info.plist`:

```xml
<key>BarikoiTraceApiKey</key>
<string>$(BARIKOI_API_KEY)</string>
```

The plugin reads it at launch and uses it when nothing is persisted. It ships
inside the `.ipa` and is readable by anyone who unzips it — acceptable for the
scoped, rotatable API key, and deliberately not offered for the MQTT password.

This asymmetry is iOS-only. Android's `initialize` configures the SDK
immediately, in the same call, on every launch.

---

## Quick start

```dart
import 'package:barikoi_trace_flutter/barikoi_trace_flutter.dart';

// 1. Subscribe to the log stream *before* initializing. Both platforms buffer
//    the lines produced before a subscriber exists — including the config
//    warnings — and replay them to the first listener.
BarikoiTrace.logs.listen((TraceLogEntry e) => debugPrint('$e'));

// 2. Configure. Once, before anything else.
await BarikoiTrace.initialize(const TraceConfig(
  apiKey: String.fromEnvironment('BARIKOI_API_KEY'),
  mqttUsername: String.fromEnvironment('BARIKOI_MQTT_USERNAME'),
  mqttPassword: String.fromEnvironment('BARIKOI_MQTT_PASSWORD'),
));
await BarikoiTrace.setLoggingEnabled(true);
await BarikoiTrace.setBroadcastingEnabled(true);   // gates locationUpdates

// 3. Permissions, in order. Foreground first — neither platform grants
//    background location without it.
if (await BarikoiTrace.requestLocationPermissions()) {
  await BarikoiTrace.requestBackgroundLocationPermission();
  await BarikoiTrace.android.requestNotificationPermission();  // no-op off Android
}

// 4. Authenticate. Every upload and the MQTT topic are keyed on this user.
try {
  final TraceUser user = await BarikoiTrace.setOrCreateUser(
    name: 'Jane',
    phone: '+8801700000000',
  );
  debugPrint('signed in as ${user.userId}');
} on TraceException catch (e) {
  debugPrint('${e.code}: ${e.message}');
}

// 5. Track.
await BarikoiTrace.startTracking(TraceMode.active, withTrip: true);

// 6. Consume live fixes. Broadcast — as many listeners as you like.
BarikoiTrace.locationUpdates.listen((TraceLocation fix) {
  debugPrint('${fix.latitude}, ${fix.longitude} ±${fix.accuracy}m');
});

// 7. Tell the user when the platform is throttling you.
if (await BarikoiTrace.isBackgroundTrackingDegraded()) {
  // Show a banner. Do not use this to gate startTracking.
}

// 8. Stop.
await BarikoiTrace.stopTracking();
```

Everything on `BarikoiTrace` is static and asynchronous — including calls whose
native counterpart is synchronous, because every one of them crosses a platform
channel.

---

## API reference

Availability column: ✅ both platforms, ⚠️ behaves differently per platform,
🤖 Android only, 🍎 iOS only.

### Lifecycle and configuration

| Method | | Notes |
|---|---|---|
| `initialize(TraceConfig config)` | ⚠️ | Call once, first. Idempotent. Android configures the SDK in this call; on iOS the SDK was already initialized at launch, so this applies what can still be applied and persists the API key for the next launch — see [Platform setup](#ios). |
| `setBaseUrl(String url)` | ✅ | Destructive natively: clears the cached user and stops tracking when the value changes. |
| `setMqttUrl(String url)` | ✅ | |
| `setMqttClientIdPrefix(String prefix)` | ✅ | Call before `startTracking`. On iOS the plugin also persists it, because the SDK keeps it in memory only. |
| `resetUrls()` | ✅ | Back to the native defaults. |
| `BarikoiTrace.nativeSdkVersion` | ✅ | `'0.4.0'` — the native version this release is built against. |

There is no `setLogListener`: the `logs` stream replaces it.

### User

| Method | | Notes |
|---|---|---|
| `setOrCreateUser({String? name, String? email, required String phone})` → `TraceUser` | ✅ | Looks up by phone, creating if absent. Required before tracking. Also refreshes remote settings as a best-effort side effect that swallows its own failure. |
| `getUser()` → `TraceUser?` | ✅ | Cached, no network. |
| `getUserId()` → `String?` | ✅ | Cheaper than `getUser`. |

`TraceUser` carries `userId`, `name`, `email`, `phone`, `companyId`, `group`,
`lastLat`, `lastLon`, `updatedAt` (UTC `DateTime`). `companyId` and `group`
drive MQTT topic resolution.

### Permissions and settings

| Method | | Notes |
|---|---|---|
| `isLocationPermissionsGranted()` → `bool` | ✅ | Foreground. |
| `isLocationSettingsOn()` → `bool` | ✅ | Device-level Location Services. |
| `hasBackgroundPermission()` → `bool` | ✅ | `ACCESS_BACKGROUND_LOCATION` / `Always`. |
| `requestLocationPermissions()` → `bool` | ✅ | Resolves *after* the prompt settles, to the resulting state. Returns `true` immediately when already granted; returns the current state rather than hanging when the user chose "don't ask again". |
| `requestBackgroundLocationPermission()` → `bool` | ⚠️ | Same protocol. Returns `false` without prompting when foreground permission is missing; on Android below API 29 returns `true` without prompting, because the permission does not exist there. |
| `openLocationSettings()` → `bool` | ⚠️ | Android opens the system Location Services screen. **iOS has no deep link to that toggle**, so it opens the app's own settings page, which carries the Location row. |
| `openAppSettings()` → `bool` | ✅ | The app's system settings page. |
| `isBackgroundTrackingDegraded()` → `bool` | ⚠️ | One "tracking may be unreliable" signal, computed from different inputs per platform — see [Background execution](#background-execution--read-this-before-shipping). Use it for a banner, not to gate `startTracking`. |

Two things worth knowing about the `request*` calls:

- **They always resolve.** iOS shows no dialog at all when the user has already
  decided, and some Android OEM builds deliver no callback after "Don't ask
  again". Both sides therefore run a watchdog and answer with the permission
  state as it stands — 15 s on iOS (which also resolves on return to
  foreground, covering a trip out to Settings), 120 s on Android. A future from
  these never hangs, but on the watchdog path the answer can arrive later than
  the user's tap.
- **On Android every prompt and settings screen needs a foreground
  `Activity`.** When the plugin is detached from one, these fail with
  `NO_ACTIVITY` rather than returning `false`.

### Tracking

| Method | | Notes |
|---|---|---|
| `setTraceMode(TraceMode mode)` | ✅ | Applied live when tracking; otherwise at the next `startTracking`. |
| `startTracking(TraceMode mode, {bool withTrip = false})` | ⚠️ | `withTrip` opens a locally generated trip alongside the session. **Android pre-checks and throws** `NO_USER` / `PERMISSION` where the native call would return silently; iOS starts and lets the SDK report through the log stream. |
| `stopTracking()` | ✅ | Ends the trip too, publishing a final `trip_status: "completed"` payload. |
| `refreshTracking()` | ⚠️ | Re-applies the stored mode to a running session. `setTraceMode` already does this; use it when the mode changed by another path. iOS calls the facade's own method; Android has none, so the plugin drives `LocTraceManager.refreshTracking()`. |
| `isLocationTracking()` → `bool` | ✅ | Android reads the real service state, not a stored flag. |
| `setOfflineTracking(bool enabled)` | ✅ | Toggles the durable queue. On by default. |
| `setLoggingEnabled(bool enabled)` | ✅ | Gates the `logs` stream. |
| `setBroadcastingEnabled(bool enabled)` | ✅ | Gates the `locationUpdates` stream. Off by default — the stream stays silent until you call it. |

### Trips

| Method | | Notes |
|---|---|---|
| `isOnTrip()` → `bool` | ✅ | |
| `getTripId()` → `String?` | ✅ | Trip ids are generated on device, not issued by the server. |

Android's redundant `getCurrentTrip()` is deliberately not bridged.

### Location and sync

| Method | | Notes |
|---|---|---|
| `updateCurrentLocation()` → `TraceLocation` | ✅ | One fresh fix, independent of any session. Throws `PERMISSION` or `LOCATION`. |
| `uploadOfflineData()` | ✅ | Fire-and-forget: returns once the flush is *scheduled*, not once it has finished. |
| `getSettingsFromRemote()` → `TraceMode` | ✅ | Explicit fetch, and it **throws** on failure — unlike the implicit refresh inside `setOrCreateUser`. It does not apply the result; pass it to `setTraceMode` yourself. |

### Streams

| Member | | Notes |
|---|---|---|
| `locationUpdates` → `Stream<TraceLocation>` | ✅ | Broadcast. Silent until `setBroadcastingEnabled(true)`. No buffering and no replay — a fix produced while nothing is listening is gone from Dart's point of view (it is still published and still queued natively). |
| `logs` → `Stream<TraceLogEntry>` | ✅ | Broadcast, gated by `setLoggingEnabled`. Both platforms buffer roughly 200 lines produced before the first subscriber — the `initialize`-time warnings above all — and replay them once. |

Errors on either stream arrive as `TraceException`, mapped exactly as method
errors are. The location stream reports `NOT_INITIALIZED` if you subscribe
before `initialize` and then heals itself on Android once initialization lands.

### Platform-specific escape hatches

Both objects are always present and every method **no-ops with a benign return
value on the other platform**, so you can call them unconditionally.

| Method | | Notes |
|---|---|---|
| `BarikoiTrace.android.requestNotificationPermission()` → `bool` | 🤖 | `POST_NOTIFICATIONS`, for the foreground-service notification. `true` without prompting below API 33. `false` off Android. |
| `BarikoiTrace.android.requestDisableBatteryOptimization({bool onlyIfNeeded = false})` | 🤖 | With `onlyIfNeeded`, skips the dialog when already exempt. |
| `BarikoiTrace.android.isIgnoringBatteryOptimizations()` → `bool` | 🤖 | **Positive polarity**: `true` means exempt, the healthy state. This is the inverse of the native SDK's method name. |
| `BarikoiTrace.android.openAutostartSettings()` | 🤖 | OEM autostart / protected-apps screen. Silent no-op on stock Android. |
| `BarikoiTrace.ios.setLocationDisabledNotificationEnabled(bool enabled)` | 🍎 | On by default; posts a local notification when Location Services go off while tracking, and the first post triggers the notification-authorization prompt. Pass `false` **before** `startTracking` to suppress both. |

`TraceMqttState` is exported but **reserved** — no channel emits it yet, because
neither native SDK exposes a connection-state callback. It exists so that adding
one later is additive.

---

## Tracking modes

`TraceMode` has three presets, numerically identical to both native SDKs':

| Preset | Accuracy | Interval | Distance filter | Accuracy filter | Ping sync | `trackingMode` |
|---|---|---|---|---|---|---|
| `TraceMode.active` | high | 5 s | — | 50 m | — | 2 |
| `TraceMode.reactive` | high | — | 100 m | 100 m | 30 s | 1 |
| `TraceMode.passive` | medium | — | 100 m | 300 m | 120 s | 0 |

`updateInterval` and `distanceFilter` are mutually exclusive: whichever is
non-zero decides whether tracking is time-based or movement-based.
`accuracyFilter` rejects any fix with worse horizontal accuracy than the given
metres.

Custom modes go through the builder, which enforces the same floors as both
natives — interval ≥ 5 s, distance ≥ 10 m, accuracy ≥ 20 m — and always stamps
`TrackingMode.custom`:

```dart
final TraceMode mode = TraceModeBuilder()
    .setDesiredAccuracy(DesiredAccuracy.high)
    .setDistanceFilter(50)      // metres
    .setAccuracyFilter(30)
    .setPingSyncInterval(60)
    .setOfflineSync(true)
    .setStartTime(const TraceTimeOfDay(hour: 8))   // daily window
    .setEndTime(const TraceTimeOfDay(hour: 20))
    .build();

await BarikoiTrace.startTracking(mode);
```

`startTime` / `endTime` define a daily window; outside it the session stops
itself on Android and stays idle on iOS. **Null is the sentinel for "no daily
window"** — track all day — and it round-trips as null rather than as
`00:00:00` / `23:59:59`, so "unset" stays distinguishable from "explicitly
midnight". `TraceTimeOfDay` is the plugin's own value type: Dart's `TimeOfDay`
lives in `material` and has no seconds field.

One rough edge: `TraceMode.copyWith` cannot *clear* `startTime` or `endTime` —
omitting them keeps the current value. Construct a new `TraceMode` to reset a
window back to all-day.

---

## Offline behavior

When the network is unavailable — or the MQTT connection is down — fixes go to
a database on disk rather than a memory buffer (Room on Android, SQLite on
iOS), so they survive the app being killed or the device rebooting. On
reconnect they flush in batches of 100, oldest first, and are deleted only once
delivery is confirmed.

Disable with `setOfflineTracking(false)` or
`TraceModeBuilder().setOfflineSync(false)`. Force a flush with
`uploadOfflineData()` — which returns as soon as the flush is scheduled.

Each platform also has a background flush of its own: a WorkManager job
(~15 min) on Android, a `BGProcessingTask` registered under
`com.barikoi.trace.offlineflush` on iOS, which is why that identifier has to be
in your `Info.plist`.

---

## MQTT contract

**Location topic:** `company/{companyId}/{groupId}/{userId}/location`
**LWT topic:** `device/{userId}/status`, retained, payload `offline`
**Client ID:** `{prefix}{userId}-{deviceUuid}` — QoS 1 throughout.

Payload:

```json
{
  "latitude": 23.8103,
  "longitude": 90.4125,
  "altitude": 4.0,
  "speed": 1.4,
  "bearing": 275.0,
  "accuracy": 12.0,
  "gpx_time": "2026-09-02 11:04:38",
  "user_id": "…",
  "company_id": "…",
  "user_name": "Jane",
  "trip_id": "…",
  "trip_status": "active"
}
```

`trip_id` / `trip_status` appear only while on a trip; stopping publishes a
final full payload with `trip_status: "completed"`. `gpx_time` uses one UTC
string format on every path — live publish, offline insert and offline flush
alike.

A CONNACK of `notAuthorized`, `badUsernameOrPassword` or `identifierRejected`
is treated as permanent: the SDK stops retrying, because the same CONNECT will
be refused every time. Check the credentials, then the broker's client-id ACL —
Android connects as `AndroidClient-…` and iOS as `iOSClient-…`, so an ACL
written for one platform refuses the other. `setMqttClientIdPrefix` is the fix.

---

## Error handling

Every failing call throws `TraceException`, carrying the native error code
**verbatim**. There is no translation table, so a code the native SDKs add
later reaches your app without a plugin release — which also means you should
have a `default` branch.

```dart
try {
  await BarikoiTrace.setOrCreateUser(phone: '01700000000');
} on TraceException catch (e) {
  switch (e.code) {
    case TraceErrorCode.noKey:        // initialize() was never called
    case TraceErrorCode.noCompany:    // no company — no MQTT topic can be resolved
    case TraceErrorCode.network:      // offline
    case TraceErrorCode.permission:   // location permission not granted
    case TraceErrorCode.server:       // backend 5xx
      break;
    default:
      debugPrint('${e.code}: ${e.message}');
  }
}
```

Branch on `code`; `message` is free to change between releases.

| Code | Meaning |
|---|---|
| `NO_USER` | No user set. Call `setOrCreateUser` first. |
| `NO_KEY` | API key not set — `initialize` was never called, or has not landed yet. |
| `NO_DATA` | Required data missing from a request or response. |
| `NETWORK` | No network connection. |
| `PERMISSION` | Location permission not granted (Android also raises it for Location Services being off). |
| `LOCATION` | No fix could be obtained. |
| `SERVER` | The Barikoi backend returned an error. |
| `TRIP` | A trip-state precondition failed. |
| `MOCK` | A mock-location provider was detected. |
| `JSON` | A response could not be parsed. |
| `NO_COMPANY` | The account has no company association. |
| `NOT_INITIALIZED` | **Plugin-only.** A method other than `initialize` was called first. |
| `NO_ACTIVITY` | **Plugin-only, Android-only.** A call needing a foreground `Activity` arrived while the plugin was detached from one. |
| `INTERNAL` | **Plugin-only.** An unexpected bridge failure that maps to none of the above. |

`TraceErrorCode.values` lists all fourteen in order.

---

## Background execution — read this before shipping

Full detail, including the on-device test matrix, is in
[`docs/BACKGROUND_EXECUTION.md`](docs/BACKGROUND_EXECUTION.md). The short
version, and the part that surprises people:

**Tracking is native. The Dart stream is a foreground mirror.**

`locationUpdates` and `logs` are event channels, and an event channel needs a
live Flutter engine at both ends. When your app is backgrounded and the engine
is detached or destroyed, the streams stop delivering — and **nothing is
replayed** when it comes back. Tracking itself is unaffected: the native SDK
keeps taking fixes, keeps publishing to MQTT, and keeps queueing to disk. Your
Dart list of fixes is a view of what happened while the UI was alive, not the
record of the session. The server-side record is the record.

There is no Dart callback for a background fix. This plugin does not spin up a
background isolate, and does not pretend to.

**What each platform can promise:**

| | Android | iOS |
|---|---|---|
| Background mechanism | A persistent foreground `Service` with an ongoing notification | Bounded wake windows: background location delivery, significant-location-change monitoring, `BGProcessingTask` |
| Resume after force-kill | `START_STICKY` plus a `BOOT_COMPLETED` receiver — comes back on any reboot | Significant-location-change only (~500 m of movement). **A stationary, force-killed app does not resume, and nothing on iOS can make it.** |
| Periodic flush when starved | WorkManager, ~15 min | `BGProcessingTask`, at the system's discretion — possibly hours |
| Usual cause of a dead session | Battery optimization, or an OEM autostart manager | Low Power Mode, `Always` silently downgraded to When In Use, Background App Refresh off |

`isBackgroundTrackingDegraded()` reports whether any of the platform's
conditions is currently in effect — on iOS it is the SDK's own signal; on
Android the plugin computes the equivalent (background location missing, not
exempt from battery optimization, or Location Services off). Surface it. A
fleet operator who thinks tracking is running when it is not is worse off than
one who is told it stopped.

---

## Platform differences

By design, not oversight.

| Behavior | Android | iOS |
|---|---|---|
| Background execution | Persistent foreground service | Bounded wake windows |
| Resume after force-kill | Boot receiver, any reboot | Significant-location-change only (~500 m) |
| SDK initialization | In the `initialize` channel call | At app launch, from the plugin's AppDelegate hook — the API key from a Dart `initialize` applies on the *next* launch |
| First-launch API key | Always works | Needs `BarikoiTraceApiKey` in `Info.plist`, else the first session of a fresh install is unauthenticated |
| `openLocationSettings` | The system Location Services screen | The app's own settings page (iOS has no deep link to the toggle) |
| `startTracking` preconditions | Pre-checked; throws `NO_USER` / `PERMISSION` | Started; the SDK reports through the log stream |
| Battery-optimization exemption | Requestable | No equivalent |
| Autostart / OEM workarounds | `openAutostartSettings` | Not applicable |
| Notification permission | `POST_NOTIFICATIONS`, API 33+ | Only if `setLocationDisabledNotificationEnabled(true)` — which is the default |
| `isBackgroundTrackingDegraded` | Computed by the plugin | The SDK's own signal |
| Mock-location detection | `Location.isMock` | Only software-simulated locations it can detect |
| Missing-`Activity` failure | `NO_ACTIVITY` | Not applicable |
| Secret storage | `EncryptedSharedPreferences` | Keychain |
| Default client-id prefix | `AndroidClient-` | `iOSClient-` |

Everything else — `TraceConfig`, the modes and their floors, the topic and
payload contract, the error codes, the offline semantics — is identical on
purpose.

---

## Example app

[`example/`](example) is a single screen covering the full flow: permission
requests in the correct order, sign-in, the mode picker, start/stop with a trip,
the live fix list, the log console, the degraded banner, and the one-off calls.
Credentials come from `--dart-define`:

```sh
cd example
flutter run \
  --dart-define=BARIKOI_API_KEY=your_api_key \
  --dart-define=BARIKOI_MQTT_USERNAME=your_mqtt_username \
  --dart-define=BARIKOI_MQTT_PASSWORD=your_mqtt_password
```

See [`example/README.md`](example/README.md).

---

## Versioning

| | |
|---|---|
| Plugin | `0.1.0` |
| Android SDK | `com.github.barikoi.BarikoiTrace-android-sdk:barikoitrace:0.4.0` |
| iOS SDK | `BarikoiTrace` Swift package `0.4.0` |

The two native SDKs are released **in lockstep on the same version number** —
one number identifies a matched pair, which is what makes a single wrapper
tractable. The plugin pins that number in three places that must move together:
`BarikoiTrace.nativeSdkVersion`, `android/build.gradle`, and
`ios/barikoi_trace_flutter/Package.swift` (plus the podspec). Below `1.0.0`,
treat a minor bump as breaking.

The platform-channel surface is specified in
[`docs/WIRE_CONTRACT.md`](docs/WIRE_CONTRACT.md) — read that before changing
anything in `android/` or `ios/`.

---

## Further reading

- [`docs/WIRE_CONTRACT.md`](docs/WIRE_CONTRACT.md) — the normative channel contract
- [`docs/BACKGROUND_EXECUTION.md`](docs/BACKGROUND_EXECUTION.md) — the integrator contract for background behaviour
- [`CHANGELOG.md`](CHANGELOG.md)
