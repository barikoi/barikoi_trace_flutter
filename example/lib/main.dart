import 'dart:async';

import 'package:barikoi_trace_flutter/barikoi_trace_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Git-ignored. Copy `secrets.example.dart` to `secrets.dart` before running.
import 'secrets.dart';

/// Credentials come from one of two places, never from this file.
///
/// 1. **`secrets.dart`** — git-ignored, copied from `secrets.example.dart`.
///    The local-development path, and the same arrangement the iOS SDK's
///    `Examples/BasicUsage/Secrets.swift` uses.
/// 2. **`--dart-define`** — takes precedence when set, so CI can inject
///    credentials without the file existing:
///
/// ```sh
/// flutter run \
///   --dart-define=BARIKOI_API_KEY=your_key \
///   --dart-define=BARIKOI_MQTT_USERNAME=your_username \
///   --dart-define=BARIKOI_MQTT_PASSWORD=your_password
/// ```
///
/// `String.fromEnvironment` is const, so an undefined key is the empty string
/// rather than a build error — the app falls back to `Secrets`, and says so on
/// screen if both are empty rather than failing with an opaque `NO_KEY` from
/// the backend.
const String _envApiKey = String.fromEnvironment('BARIKOI_API_KEY');
const String _envMqttUsername = String.fromEnvironment('BARIKOI_MQTT_USERNAME');
const String _envMqttPassword = String.fromEnvironment('BARIKOI_MQTT_PASSWORD');
const String _envMqttUrl = String.fromEnvironment('BARIKOI_MQTT_URL');
const String _envBaseUrl = String.fromEnvironment('BARIKOI_BASE_URL');

/// `--dart-define` wins; `secrets.dart` is the fallback.
String _pick(String fromEnv, String fromFile) =>
    fromEnv.isNotEmpty ? fromEnv : fromFile;

String? _pickOptional(String fromEnv, String? fromFile) =>
    fromEnv.isNotEmpty ? fromEnv : fromFile;

final String kApiKey = _pick(_envApiKey, Secrets.barikoiApiKey);
final String kMqttUsername = _pick(_envMqttUsername, Secrets.mqttUsername);
final String kMqttPassword = _pick(_envMqttPassword, Secrets.mqttPassword);
final String? kMqttUrl = _pickOptional(_envMqttUrl, Secrets.mqttUrl);
final String? kBaseUrl = _pickOptional(_envBaseUrl, Secrets.baseUrl);

void main() {
  runApp(const TraceDemoApp());
}

class TraceDemoApp extends StatelessWidget {
  const TraceDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Barikoi Trace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF43BC5D),
      ),
      home: const TraceDemoPage(),
    );
  }
}

/// The three presets, wrapped so they can drive a `DropdownButton`.
enum ModeChoice {
  active('Active', 'high accuracy · a fix every 5 s · filter 50 m'),
  reactive('Reactive', 'high accuracy · every 100 m · ping 30 s · filter 100 m'),
  passive('Passive', 'medium accuracy · every 100 m · ping 120 s · filter 300 m');

  const ModeChoice(this.label, this.description);

  /// Shown in the picker.
  final String label;

  /// The preset's numbers, spelled out for the demo screen.
  final String description;

  /// The preset itself. Numerically identical to `TraceMode.ACTIVE` /
  /// `.REACTIVE` / `.PASSIVE` on both native SDKs.
  TraceMode get mode => switch (this) {
        ModeChoice.active => TraceMode.active,
        ModeChoice.reactive => TraceMode.reactive,
        ModeChoice.passive => TraceMode.passive,
      };
}

class TraceDemoPage extends StatefulWidget {
  const TraceDemoPage({super.key});

  @override
  State<TraceDemoPage> createState() => _TraceDemoPageState();
}

class _TraceDemoPageState extends State<TraceDemoPage>
    with WidgetsBindingObserver {
  // --- Constants ---

  /// How many fixes and log lines the demo keeps in memory. The native SDK
  /// keeps its own durable queue; this list is only what the screen shows.
  static const int _maxFixes = 50;
  static const int _maxLogLines = 300;

  // --- Form state ---

  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone =
      TextEditingController(text: '+8801700000000');

  // --- SDK state ---

  bool _initialized = false;
  bool _busy = false;
  String? _status;

  TraceUser? _user;
  ModeChoice _modeChoice = ModeChoice.active;
  bool _withTrip = false;
  bool _tracking = false;
  String? _tripId;

  bool _locationGranted = false;
  bool _backgroundGranted = false;
  bool _locationServicesOn = false;
  bool _batteryExempt = false;
  bool _degraded = false;

  final List<TraceLocation> _fixes = <TraceLocation>[];
  final List<TraceLogEntry> _logs = <TraceLogEntry>[];

  StreamSubscription<TraceLocation>? _locationSubscription;
  StreamSubscription<TraceLogEntry>? _logSubscription;

  final ScrollController _logScroll = ScrollController();

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get _hasCredentials => kApiKey.isNotEmpty;

  // --- Lifecycle ---

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame, not during it: `_bootstrap` calls `setState`
    // before its first `await`, and `setState` during `initState` runs inside
    // the build phase, which throws.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_bootstrap()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_locationSubscription?.cancel());
    unawaited(_logSubscription?.cancel());
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permissions and the degraded signal can change while the app is in the
    // background — the user can revoke "Always", switch Location Services off,
    // or turn Low Power Mode on from outside the app.
    if (state == AppLifecycleState.resumed && _initialized) {
      unawaited(_refreshEverything());
    }
  }

  /// Subscribes to the log channel first, then initializes.
  ///
  /// Order matters: both platform plugins buffer the log lines produced before
  /// a subscriber exists — including the `TraceConfig` warnings emitted from
  /// inside `initialize` — and replay them to the first listener. Subscribing
  /// afterwards would still work, but this way the console shows them in the
  /// order they happened.
  Future<void> _bootstrap() async {
    _logSubscription = BarikoiTrace.logs.listen(
      _appendLog,
      onError: (Object error) => _appendLocalLog('ERROR', 'logs', '$error'),
    );

    if (!_hasCredentials) {
      setState(() {
        _status = 'No BARIKOI_API_KEY --dart-define — see README.md.';
      });
      _appendLocalLog(
        'WARN',
        'Example',
        'Built without --dart-define=BARIKOI_API_KEY. Nothing will '
            'authenticate; every call will fail with NO_KEY.',
      );
      return;
    }

    try {
      await BarikoiTrace.initialize(TraceConfig(
        apiKey: kApiKey,
        mqttUsername: kMqttUsername,
        mqttPassword: kMqttPassword,
        // Null means "SDK default" — the endpoints are only sent when the
        // secrets file or a --dart-define actually names one.
        baseUrl: kBaseUrl,
        mqttUrl: kMqttUrl,
      ));

      // Gates the two event channels. Both default to off natively, so a demo
      // that wants a live list and a log console has to ask for them.
      await BarikoiTrace.setLoggingEnabled(true);
      await BarikoiTrace.setBroadcastingEnabled(true);

      _locationSubscription = BarikoiTrace.locationUpdates.listen(
        _appendFix,
        onError: _onStreamError,
      );

      if (!mounted) return;
      setState(() {
        _initialized = true;
        _status = 'Initialized. Native SDK ${BarikoiTrace.nativeSdkVersion}.';
      });

      await _refreshEverything();
    } on TraceException catch (e) {
      _reportError('initialize', e);
    }
  }

  // --- Stream sinks ---

  void _appendFix(TraceLocation fix) {
    if (!mounted) return;
    setState(() {
      _fixes.insert(0, fix);
      if (_fixes.length > _maxFixes) {
        _fixes.removeRange(_maxFixes, _fixes.length);
      }
    });
  }

  void _onStreamError(Object error) {
    if (error is TraceException) {
      _appendLocalLog(
        'ERROR',
        'locationUpdates',
        '${error.code}: ${error.message}',
      );
    } else {
      _appendLocalLog('ERROR', 'locationUpdates', '$error');
    }
  }

  void _appendLog(TraceLogEntry entry) {
    if (!mounted) return;
    setState(() {
      _logs.add(entry);
      if (_logs.length > _maxLogLines) {
        _logs.removeRange(0, _logs.length - _maxLogLines);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  /// A line the demo itself produced, rendered in the same console as the
  /// SDK's own output.
  void _appendLocalLog(String level, String tag, String message) {
    _appendLog(TraceLogEntry(
      level: level,
      tag: tag,
      message: message,
      timestamp: DateTime.now().toUtc(),
    ));
  }

  // --- State refresh ---

  Future<void> _refreshEverything() async {
    await _refreshPermissions();
    await _refreshTrackingState();
  }

  Future<void> _refreshPermissions() async {
    if (!_initialized) return;
    try {
      final bool location = await BarikoiTrace.isLocationPermissionsGranted();
      final bool background = await BarikoiTrace.hasBackgroundPermission();
      final bool services = await BarikoiTrace.isLocationSettingsOn();
      final bool degraded = await BarikoiTrace.isBackgroundTrackingDegraded();
      final bool battery =
          await BarikoiTrace.android.isIgnoringBatteryOptimizations();

      if (!mounted) return;
      setState(() {
        _locationGranted = location;
        _backgroundGranted = background;
        _locationServicesOn = services;
        _degraded = degraded;
        _batteryExempt = battery;
      });
    } on TraceException catch (e) {
      _reportError('permissions', e);
    }
  }

  Future<void> _refreshTrackingState() async {
    if (!_initialized) return;
    try {
      final TraceUser? user = await BarikoiTrace.getUser();
      final bool tracking = await BarikoiTrace.isLocationTracking();
      final String? tripId = await BarikoiTrace.getTripId();

      if (!mounted) return;
      setState(() {
        _user = user;
        _tracking = tracking;
        _tripId = tripId;
        if (user != null) {
          if (_name.text.isEmpty && user.name != null) _name.text = user.name!;
          if (_email.text.isEmpty && user.email != null) {
            _email.text = user.email!;
          }
          if (user.phone != null) _phone.text = user.phone!;
        }
      });
    } on TraceException catch (e) {
      _reportError('state', e);
    }
  }

  // --- Actions ---

  /// The permission order both native SDKs require.
  ///
  /// Foreground first — neither platform will grant background location
  /// without it, and asking out of order gets a silent denial. Notifications
  /// last, and only on Android, where the foreground-service notification the
  /// SDK posts needs `POST_NOTIFICATIONS` from API 33.
  Future<void> _requestPermissionsInOrder() async {
    await _run('permissions', () async {
      final bool foreground = await BarikoiTrace.requestLocationPermissions();
      _appendLocalLog('INFO', 'Example', 'Foreground location: $foreground');

      if (foreground) {
        final bool background =
            await BarikoiTrace.requestBackgroundLocationPermission();
        _appendLocalLog('INFO', 'Example', 'Background location: $background');

        final bool notifications =
            await BarikoiTrace.android.requestNotificationPermission();
        if (_isAndroid) {
          _appendLocalLog('INFO', 'Example', 'Notifications: $notifications');
        }
      }

      if (!await BarikoiTrace.isLocationSettingsOn()) {
        await BarikoiTrace.openLocationSettings();
      }

      await _refreshPermissions();
    });
  }

  Future<void> _signIn() async {
    final String phone = _phone.text.trim();
    if (phone.isEmpty) {
      _snack('Enter a phone number — it is the identity the backend looks up.');
      return;
    }

    await _run('setOrCreateUser', () async {
      final TraceUser user = await BarikoiTrace.setOrCreateUser(
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        phone: phone,
      );
      if (!mounted) return;
      setState(() {
        _user = user;
        _status = 'Signed in as ${user.userId}.';
      });
      _appendLocalLog(
        'INFO',
        'Example',
        'User ${user.userId} · company ${user.companyId} · group ${user.group}',
      );
    });
  }

  Future<void> _toggleTracking() async {
    if (_tracking) {
      await _run('stopTracking', () async {
        await BarikoiTrace.stopTracking();
        await _refreshTrackingState();
      });
      return;
    }

    await _run('startTracking', () async {
      await BarikoiTrace.startTracking(_modeChoice.mode, withTrip: _withTrip);
      await _refreshTrackingState();
      await _refreshPermissions();
    });
  }

  Future<void> _applyMode(ModeChoice choice) async {
    setState(() => _modeChoice = choice);
    if (!_tracking) return;
    // Applied live when a session is already running.
    await _run('setTraceMode', () => BarikoiTrace.setTraceMode(choice.mode));
  }

  Future<void> _updateCurrentLocation() async {
    await _run('updateCurrentLocation', () async {
      final TraceLocation fix = await BarikoiTrace.updateCurrentLocation();
      _appendFix(fix);
      if (!mounted) return;
      setState(() {
        _status = 'One-shot fix: ${_coordinates(fix)}';
      });
    });
  }

  Future<void> _uploadOfflineData() async {
    await _run('uploadOfflineData', () async {
      await BarikoiTrace.uploadOfflineData();
      if (!mounted) return;
      // Fire-and-forget by contract: the call returns once the flush is
      // scheduled, not once it has finished.
      setState(() => _status = 'Offline flush scheduled.');
    });
  }

  Future<void> _getSettingsFromRemote() async {
    await _run('getSettingsFromRemote', () async {
      final TraceMode remote = await BarikoiTrace.getSettingsFromRemote();
      _appendLocalLog('INFO', 'Example', 'Remote settings: $remote');
      if (!mounted) return;
      setState(() {
        _status = 'Remote mode fetched (${remote.trackingMode.name}). '
            'Not applied — pass it to setTraceMode to use it.';
      });
    });
  }

  Future<void> _applyRemoteSettings() async {
    await _run('getSettingsFromRemote + setTraceMode', () async {
      final TraceMode remote = await BarikoiTrace.getSettingsFromRemote();
      await BarikoiTrace.setTraceMode(remote);
      // setTraceMode already re-applies to a running session; refreshTracking
      // is here for the other path — a mode that changed outside setTraceMode.
      if (_tracking) await BarikoiTrace.refreshTracking();
      if (!mounted) return;
      setState(() => _status = 'Remote mode applied.');
    });
  }

  Future<void> _requestBatteryExemption() async {
    await _run('requestDisableBatteryOptimization', () async {
      await BarikoiTrace.android
          .requestDisableBatteryOptimization(onlyIfNeeded: true);
      await _refreshPermissions();
    });
  }

  Future<void> _openAutostartSettings() async {
    await _run('openAutostartSettings', () async {
      await BarikoiTrace.android.openAutostartSettings();
    });
  }

  Future<void> _openLocationSettings() async {
    await _run('openLocationSettings', () async {
      await BarikoiTrace.openLocationSettings();
    });
  }

  Future<void> _openAppSettings() async {
    await _run('openAppSettings', () async {
      await BarikoiTrace.openAppSettings();
    });
  }

  /// One try/catch for every SDK call the screen makes.
  ///
  /// `TraceException.code` is the platform's own code, verbatim — branch on it
  /// rather than on `message`, which is free to change between releases.
  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on TraceException catch (e) {
      _reportError(label, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reportError(String label, TraceException e) {
    final String text = '${e.code}: ${e.message}';
    _appendLocalLog('ERROR', label, text);
    if (!mounted) return;
    setState(() => _status = '$label failed — $text');
    _snack(text);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Formatting ---

  static String _coordinates(TraceLocation fix) =>
      '${fix.latitude.toStringAsFixed(5)}, ${fix.longitude.toStringAsFixed(5)}';

  static String _clock(DateTime utc) {
    final DateTime local = utc.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barikoi Trace'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh state',
            onPressed: _initialized
                ? () => unawaited(_refreshEverything())
                : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          if (!_hasCredentials) _credentialsBanner(),
          if (_degraded) _degradedBanner(),
          if (_status != null) _statusLine(),
          _permissionsCard(),
          _signInCard(),
          _trackingCard(),
          _actionsCard(),
          if (_isAndroid) _androidCard(),
          _fixesCard(),
          _logCard(),
        ],
      ),
    );
  }

  Widget _credentialsBanner() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Built without credentials.\n\n'
          'flutter run \\\n'
          '  --dart-define=BARIKOI_API_KEY=… \\\n'
          '  --dart-define=BARIKOI_MQTT_USERNAME=… \\\n'
          '  --dart-define=BARIKOI_MQTT_PASSWORD=…',
          style: TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }

  Widget _degradedBanner() {
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.warning_amber_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isAndroid
                    ? 'Background tracking is degraded — background location is '
                        'missing, the app is not exempt from battery '
                        'optimization, or Location Services are off. Fixes may '
                        'stop arriving once the app is backgrounded.'
                    : 'Background tracking is degraded — Low Power Mode, an '
                        '"Always" permission that was downgraded, or Background '
                        'App Refresh being off. Delivery in the background is '
                        'unreliable while this shows.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusLine() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        _status!,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _flag(String label, bool value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Icon(
            value ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: value ? Colors.green : Colors.redAccent,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }

  Widget _permissionsCard() {
    return _section(
      title: '1 · Permissions',
      children: <Widget>[
        _flag('Foreground location', _locationGranted),
        _flag('Background location', _backgroundGranted),
        _flag('Location services on', _locationServicesOn),
        if (_isAndroid)
          _flag('Exempt from battery optimization', _batteryExempt),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _initialized && !_busy
              ? () => unawaited(_requestPermissionsInOrder())
              : null,
          child: const Text('Request, in order'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            OutlinedButton(
              onPressed: _initialized && !_busy
                  ? () => unawaited(_openLocationSettings())
                  : null,
              child: const Text('Location settings'),
            ),
            OutlinedButton(
              onPressed: _initialized && !_busy
                  ? () => unawaited(_openAppSettings())
                  : null,
              child: const Text('App settings'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Foreground first — neither platform grants background location '
          'without it. Notifications last, and only on Android.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _signInCard() {
    return _section(
      title: '2 · Sign in',
      children: <Widget>[
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name (optional)'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'Email (optional)'),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phone,
          decoration: const InputDecoration(labelText: 'Phone (required)'),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed:
              _initialized && !_busy ? () => unawaited(_signIn()) : null,
          child: const Text('Sign in / create user'),
        ),
        if (_user != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            'userId ${_user!.userId}\n'
            'company ${_user!.companyId ?? '—'} · group ${_user!.group ?? '—'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _trackingCard() {
    return _section(
      title: '3 · Tracking',
      children: <Widget>[
        DropdownButtonFormField<ModeChoice>(
          // `value:` rather than the newer `initialValue:` — this example's
          // pubspec allows Flutter 3.22, which does not have the latter yet.
          value: _modeChoice,
          decoration: const InputDecoration(labelText: 'Mode'),
          items: ModeChoice.values
              .map((ModeChoice choice) => DropdownMenuItem<ModeChoice>(
                    value: choice,
                    child: Text(choice.label),
                  ))
              .toList(),
          onChanged: _busy
              ? null
              : (ModeChoice? choice) {
                  if (choice != null) unawaited(_applyMode(choice));
                },
        ),
        const SizedBox(height: 4),
        Text(
          _modeChoice.description,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('With trip'),
          subtitle: const Text('Opens a trip alongside the session'),
          value: _withTrip,
          onChanged: _tracking || _busy
              ? null
              : (bool value) => setState(() => _withTrip = value),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _tracking ? Colors.redAccent : null,
          ),
          onPressed: _initialized && !_busy
              ? () => unawaited(_toggleTracking())
              : null,
          child: Text(_tracking ? 'Stop tracking' : 'Start tracking'),
        ),
        const SizedBox(height: 8),
        Text(
          _tracking
              ? (_tripId != null ? 'Tracking · trip $_tripId' : 'Tracking')
              : 'Stopped',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _actionsCard() {
    return _section(
      title: '4 · One-off calls',
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton(
              onPressed: _initialized && !_busy
                  ? () => unawaited(_updateCurrentLocation())
                  : null,
              child: const Text('updateCurrentLocation'),
            ),
            OutlinedButton(
              onPressed: _initialized && !_busy
                  ? () => unawaited(_uploadOfflineData())
                  : null,
              child: const Text('uploadOfflineData'),
            ),
            OutlinedButton(
              onPressed: _initialized && !_busy
                  ? () => unawaited(_getSettingsFromRemote())
                  : null,
              child: const Text('getSettingsFromRemote'),
            ),
            OutlinedButton(
              onPressed: _initialized && !_busy
                  ? () => unawaited(_applyRemoteSettings())
                  : null,
              child: const Text('…and apply it'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _androidCard() {
    return _section(
      title: 'Android only',
      children: <Widget>[
        Text(
          'Doze and OEM autostart managers kill the tracking service even when '
          'every permission is granted. These are the two escape hatches.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton(
              onPressed: _initialized && !_busy
                  ? () => unawaited(_requestBatteryExemption())
                  : null,
              child: const Text('Disable battery optimization'),
            ),
            OutlinedButton(
              onPressed: _initialized && !_busy
                  ? () => unawaited(_openAutostartSettings())
                  : null,
              child: const Text('Autostart settings'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _fixesCard() {
    return _section(
      title: '5 · Live fixes (${_fixes.length})',
      children: <Widget>[
        if (_fixes.isEmpty)
          Text(
            'Nothing yet. The stream is silent until tracking is running and '
            'setBroadcastingEnabled(true) has been called — the demo calls it '
            'at startup.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ..._fixes.take(12).map(_fixTile),
        if (_fixes.length > 12)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '…and ${_fixes.length - 12} older.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _fixTile(TraceLocation fix) {
    final List<String> details = <String>[
      '±${fix.accuracy.toStringAsFixed(0)} m',
      if (fix.speed != null) '${fix.speed!.toStringAsFixed(1)} m/s',
      if (fix.bearing != null) '${fix.bearing!.toStringAsFixed(0)}°',
      if (fix.provider != null) fix.provider!,
      if (fix.isMock ?? false) 'MOCK',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(
              _clock(fix.timestamp),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _coordinates(fix),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                Text(
                  details.join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logCard() {
    return _section(
      title: '6 · SDK log',
      children: <Widget>[
        Container(
          height: 220,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _logs.isEmpty
              ? const Center(child: Text('No log lines yet.'))
              : ListView.builder(
                  controller: _logScroll,
                  itemCount: _logs.length,
                  itemBuilder: (BuildContext context, int index) {
                    final TraceLogEntry entry = _logs[index];
                    return Text(
                      '${_clock(entry.timestamp)} '
                      '${entry.level.padRight(5)} '
                      '${entry.tag}: ${entry.message}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: _logs.isEmpty ? null : () => setState(_logs.clear),
              child: const Text('Clear'),
            ),
          ],
        ),
      ],
    );
  }
}
