# barikoi_trace_flutter example

One screen covering the whole flow: permission requests in the order both
platforms require, sign-in, a tracking-mode picker, start/stop with a trip, a
live list of incoming fixes, a scrolling console fed by the SDK's own log, the
degraded-tracking banner, and buttons for `updateCurrentLocation`,
`uploadOfflineData` and `getSettingsFromRemote`.

All of it is in [`lib/main.dart`](lib/main.dart).

---

## Run it

Credentials are compile-time defines. They are never in source, never in the
repository, and never in a checked-in properties file:

```sh
flutter run \
  --dart-define=BARIKOI_API_KEY=your_api_key \
  --dart-define=BARIKOI_MQTT_USERNAME=your_mqtt_username \
  --dart-define=BARIKOI_MQTT_PASSWORD=your_mqtt_password
```

The API key comes from the Barikoi dashboard. The **MQTT username and password
are issued separately, per company** — they are not derivable from the API key,
and they have to match the broker's ACL. A mismatch surfaces as a broker
refusal (`notAuthorized`), not as an authentication error.

Build without them and the app still starts: it shows a red banner naming the
missing define instead of failing with an opaque `NO_KEY` from the backend.

If you would rather not retype them, put them in a git-ignored file and source
it:

```sh
# secrets.env — already in .gitignore
export BARIKOI_API_KEY=…
export BARIKOI_MQTT_USERNAME=…
export BARIKOI_MQTT_PASSWORD=…
```

```sh
source secrets.env
flutter run \
  --dart-define=BARIKOI_API_KEY=$BARIKOI_API_KEY \
  --dart-define=BARIKOI_MQTT_USERNAME=$BARIKOI_MQTT_USERNAME \
  --dart-define=BARIKOI_MQTT_PASSWORD=$BARIKOI_MQTT_PASSWORD
```

`--dart-define` values are compiled into the binary. That is fine for the
Barikoi API key, which is scoped and rotatable; it is *not* how a production
app should ship the MQTT password. See the plugin README's configuration
section for the alternative — have your own backend issue the broker
credentials at runtime and pass them to `initialize`.

---

## What the screen does

| Section | Calls |
|---|---|
| 1 · Permissions | `requestLocationPermissions` → `requestBackgroundLocationPermission` → `android.requestNotificationPermission`, then `openLocationSettings` if Location Services are off. Status flags come from `isLocationPermissionsGranted`, `hasBackgroundPermission`, `isLocationSettingsOn`, `android.isIgnoringBatteryOptimizations`. |
| 2 · Sign in | `setOrCreateUser(name:, email:, phone:)`, then `getUser` on every refresh. |
| 3 · Tracking | `setTraceMode`, `startTracking(mode, withTrip:)`, `stopTracking`, `isLocationTracking`, `getTripId`. |
| 4 · One-off calls | `updateCurrentLocation`, `uploadOfflineData`, `getSettingsFromRemote` (and a second button that passes the result to `setTraceMode` + `refreshTracking`, since the fetch deliberately does not apply anything). |
| Android only | `android.requestDisableBatteryOptimization(onlyIfNeeded: true)`, `android.openAutostartSettings`. |
| 5 · Live fixes | `BarikoiTrace.locationUpdates`, after `setBroadcastingEnabled(true)`. |
| 6 · SDK log | `BarikoiTrace.logs`, after `setLoggingEnabled(true)`. |
| Degraded banner | `isBackgroundTrackingDegraded`, re-read on every app resume. |

Two ordering details in `_bootstrap()` are worth copying rather than
rediscovering:

- **Subscribe to `logs` before calling `initialize`.** Both platform plugins
  buffer the lines produced before a subscriber exists — including the
  `TraceConfig` warnings emitted from inside `initialize`, which are the ones
  an integrator most needs — and replay them to the first listener.
- **`locationUpdates` and `logs` are gated.** Both are silent until
  `setBroadcastingEnabled(true)` / `setLoggingEnabled(true)`. The demo enables
  both immediately after `initialize`.

Every SDK call goes through one `_run(label, action)` helper that catches
`TraceException` and renders it as `code: message` — in a snackbar, in the
status line and in the log console. Branch on `code` (the platform's own string,
passed through verbatim), never on `message`.

---

## Platform scaffolding

These files are hand-authored and carry settings a fresh `flutter create` does
**not** produce. If you regenerate the platform folders, re-apply them:

| File | Why it is not the default |
|---|---|
| `android/app/build.gradle` | `minSdk 24`, `coreLibraryDesugaringEnabled = true` and the `desugar_jdk_libs` dependency. Desugaring is **not** transitive — the native SDK uses `java.time.LocalTime` at minSdk 24, so the *application* module must desugar too or the app crashes with `NoClassDefFoundError: java.time.LocalTime` the first time a `TraceMode` is built. |
| `android/build.gradle` | The JitPack repository. `com.github.barikoi:barikoitrace:0.4.0` does not resolve without it. |
| `android/settings.gradle` | Kotlin 2.0.21. The native SDK is compiled with Kotlin 2.0, and 1.9.x refuses to read its metadata. |
| `android/app/src/main/AndroidManifest.xml` | The app's own location, background-location, foreground-service and notification permissions. |
| `ios/Runner/Info.plist` | The two usage descriptions, `UIBackgroundModes`, `BGTaskSchedulerPermittedIdentifiers`, and the optional `BarikoiTraceApiKey` the plugin reads at launch. |
| `ios/Podfile` | `platform :ios, '15.0'` and the post-install deployment-target floor. |

The rest of `android/` and `ios/` is the stock Flutter template. If this
checkout is missing it (no `Runner.xcodeproj`, no Gradle wrapper), regenerate
the scaffolding and then restore the files above:

```sh
cd example
flutter create --platforms=android,ios --project-name barikoi_trace_flutter_example .
git checkout -- android ios      # put the hand-authored files back
flutter pub get
```

iOS additionally needs the SDK itself. Prefer Swift Package Manager:

```sh
flutter config --enable-swift-package-manager
```

The plugin's `ios/barikoi_trace_flutter/Package.swift` then resolves
`BarikoiTrace` 0.4.0 for you. On CocoaPods you must supply a podspec yourself —
the Podfile explains how.

---

## On-device notes

- Background behaviour cannot be validated in a simulator or emulator. Work
  through the matrix in [`../docs/BACKGROUND_EXECUTION.md`](../docs/BACKGROUND_EXECUTION.md)
  on real hardware.
- The live-fix list is a **foreground mirror**. Background the app and the Dart
  isolate stops receiving events; tracking itself keeps running natively and
  keeps publishing to MQTT. Nothing is replayed when you come back — the list
  resumes from the next fix.
- On Android the ongoing notification is the sign that the foreground service
  is alive. If it disappears, the OEM killed the process; try the two buttons
  in the Android section.
