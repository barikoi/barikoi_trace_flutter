# Background execution — the integrator contract

What `barikoi_trace_flutter` promises about background tracking, what it
cannot promise, and how to check which one you got on real hardware.

Read this before shipping. Every "the tracking just stops after a while" report
is explained somewhere on this page.

---

## The one-sentence version

**Tracking is native. The Dart streams are a foreground mirror.**

The tracking session lives entirely inside the native SDK — a foreground
service on Android, a stack of wake mechanisms on iOS. It does not need the
Flutter engine, your Dart isolate, or your UI. `BarikoiTrace.locationUpdates`
and `BarikoiTrace.logs` are event channels, and an event channel needs a live
engine at both ends; when the engine goes, they stop delivering. The session
does not stop with them, and nothing they missed is replayed.

So: the list of fixes on your screen is a view of what happened while the UI
was alive. It is not the record of the session. The record is what reached the
broker and what sits in the on-device offline queue.

---

## 1. What runs where

```
                     ┌───────────────────────────────────────────────┐
                     │  Native process — survives your UI            │
   platform ────────▶│  location engine ─▶ manager ─┬─▶ MQTT broker  │
   location          │                              └─▶ offline DB   │
   provider          └───────────────┬───────────────────────────────┘
                                     │  event channel
                                     ▼  (only while the engine is attached)
                     ┌───────────────────────────────────────────────┐
                     │  Flutter engine — your Dart isolate, your UI  │
                     └───────────────────────────────────────────────┘
```

Everything above the dashed boundary keeps working with the app backgrounded,
with the UI destroyed, and — on Android — with the app swiped out of Recents.
Everything below it is subject to the platform's rules about running your code.

### Android

The session runs in `LocTraceForegroundService`, a foreground service with an
ongoing notification. That notification is the contract with the OS: while it
is showing, the service is alive. A WorkManager job (`LocTraceDataService`,
roughly every 15 minutes) takes a fix and flushes the offline queue when the
service is being starved.

### iOS

There is no persistent background service on iOS. The SDK stacks the three
mechanisms that exist:

1. **Background location delivery** — `allowsBackgroundLocationUpdates`, active
   while the app is backgrounded and `Always` is granted.
2. **Significant-location-change monitoring** — survives termination and
   relaunches the process on roughly 500 m of movement. This is the only path
   back from a force-kill.
3. **`BGProcessingTask`**, registered under `com.barikoi.trace.offlineflush` —
   a periodic offline-queue flush, scheduled at the system's discretion. Not a
   timer; iOS decides when, and it can be hours.

---

## 2. What happens to the Dart streams

### The rules

| | `locationUpdates` | `logs` |
|---|---|---|
| Gated by | `setBroadcastingEnabled(true)` | `setLoggingEnabled(true)` |
| Buffered while nobody is listening | **No** — dropped, by contract | Yes, ~200 entries |
| Replayed to a new subscriber | **No** | Yes, once, oldest first |
| Survives the engine detaching | No | No |

`locationUpdates` explicitly has no backpressure and no buffer: the platform
side drops rather than buffers if it outpaces the channel. A fix produced while
Dart is not listening is gone *from Dart's point of view*. It was still
published to the broker, or still queued to disk if the network was down.

The `logs` buffer exists for one reason: the most useful lines the SDK produces
are the `TraceConfig` warnings emitted from inside `initialize` — empty API key,
empty broker credentials, plaintext `mqttUrl`, non-HTTPS `baseUrl` — and those
fire before any realistic subscriber exists. Subscribe to `logs` **before**
calling `initialize` and you see them in order; subscribe after and you still
see them, replayed.

### Engine detach, per platform

**Android.** The engine belongs to your `FlutterActivity`. Backgrounding the
app does not destroy it, so in practice the isolate usually keeps running and
fixes keep arriving for a while. When the Activity is actually destroyed — the
user swipes the task away, or the system reclaims it —
`onDetachedFromEngine` runs and the plugin:

- cancels the coroutine collecting `locationUpdates`, so no collector outlives
  the engine;
- drops the log sink **and clears the log backlog**, deliberately: the next
  engine gets a fresh handler, and replaying a dead engine's log into it would
  be misleading;
- answers any in-flight permission request with the permission state as it
  stands, so no Dart future is left hanging;
- removes itself as the SDK's log listener.

The foreground service is a separate component and is untouched by all of that.
Tracking continues.

**iOS.** The app being suspended stops your Dart code along with everything
else in the process. During a background wake window the isolate may run and
events may be delivered — but that is the OS's decision, not a guarantee, and
you must not design around it. `onCancel` on either stream simply drops the
sink; the log handler goes back to buffering, which is why a Dart hot restart
shows you the lines produced while it was restarting.

### There is no background Dart callback

This plugin does not spin up a background isolate and does not offer a
"headless" fix callback. If you need per-fix logic that must run even when the
UI is gone, it belongs on your server, consuming the MQTT topic. That is what
the topic is for.

---

## 3. Relaunch after the process dies

| Path | Android | iOS |
|---|---|---|
| Service killed by the system | `START_STICKY` — Android restarts it | n/a |
| Device reboot | `BootReceiver` resumes tracking if it was active | Nothing. Tracking resumes only via the paths below |
| App force-killed by the user | Foreground service is torn down; a reboot brings it back | Significant-location-change relaunch on ~500 m of movement |
| App force-killed, device stationary | Comes back at the next reboot | **Never.** Nothing on iOS can make it |
| Process restart while tracking was active | `initialize` resumes the session | `handleLaunch(options:)` at launch resumes it |

### The iOS relaunch path has a prerequisite

The significant-location-change relaunch only works because the plugin calls
`BarikoiTrace.handleLaunch(options:)` from its `UIApplicationDelegate` hook.
That hook only runs if your `AppDelegate` registers plugins **inside**
`application(_:didFinishLaunchingWithOptions:)` and **before** calling `super`:

```swift
GeneratedPluginRegistrant.register(with: self)                       // first
return super.application(application, didFinishLaunchingWithOptions: launchOptions)
```

Flutter's own template does exactly this, so the default is correct. Break it —
register after `super`, or hand-roll an AppDelegate that never forwards the
callback — and three things silently stop working: no `BGTaskScheduler` task is
registered, background offline flushing is disabled, and a
significant-location-change relaunch does not resume tracking.

**Dart cannot detect this.** The plugin logs a WARN on the `logs` stream
naming the exact fix. Watch that stream in development; it is the only signal
you get.

### The iOS first-launch API key

For the same reason — `BGTaskScheduler.register` must happen during launch and
must not happen twice — the SDK is initialized from the launch hook, not from
your Dart `initialize` call. It reconstructs its configuration from what was
persisted on a previous run.

On the **very first launch of a fresh install** nothing is persisted, so that
session starts without an API key. Your `initialize` call then persists the key
and applies what can still be applied (broker credentials, `mqttUrl`, client-id
prefix, `baseUrl`) — but the API key itself takes effect on the *next* launch,
and the plugin logs a WARN saying so. The same warning appears whenever the key
you pass differs from the one the process launched with.

Put the key in `Info.plist` under `BarikoiTraceApiKey` and the first launch
works too. Android has no equivalent problem: its `initialize` configures the
SDK in the same call, on every launch.

---

## 4. Degraded-capability signals

`isBackgroundTrackingDegraded()` is one boolean meaning "something is currently
limiting how reliably background tracking can run". It is computed from
different inputs on each platform.

| Platform | `true` when any of these hold | Source |
|---|---|---|
| iOS | Low Power Mode is on; `Always` authorization was downgraded or denied; Background App Refresh is off | The SDK's own `isBackgroundTrackingDegraded` |
| Android | Background location permission is missing; the app is not exempt from battery optimization; Location Services are off | Computed by the plugin — the Android SDK has no equivalent |

Use it for a banner, not as a gate. `startTracking` on a degraded device still
does useful work; it is just less reliable, and the user is the only one who
can fix any of the causes.

Re-read it on every app resume. Every one of these can change while your app is
in the background: the user can revoke "Always" from Settings, flip Low Power
Mode on, or turn Location Services off, and none of it produces a callback you
subscribed to. The example app does this from
`didChangeAppLifecycleState(AppLifecycleState.resumed)`.

Related signals worth surfacing next to it:

- `hasBackgroundPermission()` — the specific permission, so you can word the
  banner precisely.
- `isLocationSettingsOn()` — device-level Location Services.
- `BarikoiTrace.android.isIgnoringBatteryOptimizations()` — **positive
  polarity**: `true` means exempt, the healthy state.
- `isLocationTracking()` — whether a session is actually running. On Android
  this reads the real service state rather than a stored flag, which makes it
  the honest answer after an OEM kill.

### The remediation buttons

Android gives you two, and you will need both:

```dart
await BarikoiTrace.android.requestDisableBatteryOptimization(onlyIfNeeded: true);
await BarikoiTrace.android.openAutostartSettings();
```

Battery optimization is the single most common cause of a silently dead
session. OEM autostart managers (MIUI, EMUI, ColorOS and friends) kill
background services regardless of what Android's own rules say;
`openAutostartSettings` opens the vendor screen where a user can whitelist the
app, and is a silent no-op on stock Android.

iOS has neither, by design — there is nothing equivalent to request. What it
has instead is `BarikoiTrace.ios.setLocationDisabledNotificationEnabled(bool)`,
on by default, which posts a local notification when Location Services go off
while tracking. The first post triggers the notification-authorization prompt,
so pass `false` **before** `startTracking` if you do not want either.

---

## 5. On-device test matrix

Unit tests cannot validate any of this. Neither can a simulator or an emulator:
they do not throttle, do not enter Doze, do not run Low Power Mode, and do not
kill your process the way a real phone does.

Run the whole matrix on real hardware, with a broker subscription open so you
can see what actually arrived, before you ship.

### Both platforms

| # | Scenario | Expected |
|---|---|---|
| 1 | Sustained movement, app in the foreground, 30+ min | Fixes at the mode's cadence, on the stream and at the broker |
| 2 | Sustained movement, app backgrounded, 30+ min | Broker keeps receiving. The Dart stream may go quiet — that is correct |
| 3 | Stationary for several hours | No spurious fixes; the session is still alive when you come back |
| 4 | Airplane mode for 10 min, then back on | Nothing lost: the gap flushes from the offline queue, oldest first |
| 5 | Airplane mode, then force-kill, then reconnect | Still nothing lost — the queue is on disk, not in memory |
| 6 | Wrong MQTT credentials | A permanent-refusal log line, no retry storm, and fixes still queueing to disk |
| 7 | `stopTracking` while on a trip | A final payload with `trip_status: "completed"` at the broker |

### Android only

| # | Scenario | Expected |
|---|---|---|
| A1 | Battery optimization left **on**, app backgrounded for hours | Degraded banner shows; delivery is intermittent. This is the baseline for "why did it stop" |
| A2 | Battery optimization exempted, same test | Steady delivery |
| A3 | Background location revoked from Settings mid-session | Degraded banner appears on resume; the session reports honestly |
| A4 | Swipe the app out of Recents | Ongoing notification survives; broker keeps receiving; the Dart stream is gone until you reopen |
| A5 | Force-kill, then reboot the device | `BootReceiver` resumes tracking |
| A6 | Location Services switched off mid-session | Degraded banner; a `PERMISSION`-coded failure from `startTracking` if you try to restart |
| A7 | An OEM device (Xiaomi / Oppo / Vivo / Huawei) with autostart **not** whitelisted | Expect the session to die. Then whitelist it and confirm it does not |

### iOS only

| # | Scenario | Expected |
|---|---|---|
| I1 | Low Power Mode on, app backgrounded | Degraded banner; background refresh is suspended outright |
| I2 | Background App Refresh off | Degraded banner; `BGProcessingTask` never fires |
| I3 | `Always` downgraded to "While Using" mid-session | Degraded banner on resume; background delivery stops |
| I4 | Force-kill, then move 500 m+ | Process relaunches and tracking resumes — this is the `handleLaunch` path. If it does not, check the AppDelegate ordering in §3 |
| I5 | Force-kill, stay stationary | Does **not** resume. Expected, and not fixable |
| I6 | Fresh install, no `BarikoiTraceApiKey` in `Info.plist`, first launch | The WARN about the deferred API key on the `logs` stream; authentication works on the second launch |
| I7 | Same, with the `Info.plist` key set | Authentication works on the first launch |

### Flutter-specific

| # | Scenario | Expected |
|---|---|---|
| F1 | Subscribe to `logs`, then `initialize` with an empty API key and a plaintext `mqttUrl` | Four config warnings on the stream, in `TraceConfig.warnings` order |
| F2 | Subscribe to `logs` *after* `initialize` | Same warnings, replayed once |
| F3 | Subscribe to `locationUpdates` before `initialize` | Android: one `NOT_INITIALIZED` error, then the stream heals itself once `initialize` lands. iOS: silence until fixes start |
| F4 | Hot restart while tracking | The session survives; the streams re-subscribe; the fix list starts empty — there is no replay |
| F5 | Start tracking with no user | `TraceException` with code `NO_USER` on Android. On iOS the call succeeds and the SDK reports through the log stream instead |
| F6 | Any permission call on Android with the Activity detached | `TraceException` with code `NO_ACTIVITY` |

---

## 6. What to tell your users

A fleet operator who believes tracking is running when it is not is worse off
than one who has been told it stopped. Three things earn their place in the UI:

1. **The degraded banner**, worded per platform, with a button that goes
   straight to the setting that fixes it (`openAppSettings`,
   `openLocationSettings`, or the two Android remediation calls).
2. **The real session state** from `isLocationTracking()`, refreshed on resume
   — not a boolean you set when the user tapped Start.
3. **Honest background copy** in your `NSLocationAlwaysAndWhenInUseUsageDescription`
   and in your onboarding. A concrete, user-visible reason is both what App
   Review expects and what makes a user grant "Always" instead of "While
   Using".
