import Foundation
import UIKit

import BarikoiTrace

/// Plugin-owned persistence. Everything the SDK persists for itself lives in
/// `TraceDataStore`; this holds the one piece of `TraceConfig` the SDK does
/// **not** write down.
///
/// `TraceManager.setMqttClientIdPrefix(_:)` keeps the prefix in memory only,
/// so without this the launch-time `TraceConfig` would silently revert to
/// `iOSClient-` on every cold start — and on a broker whose ACL authorizes by
/// client-id pattern, that means every relaunch reconnects as `notAuthorized`.
enum PluginPreferences {
    private static let suiteName = "com.barikoi.trace.flutter"
    private static let prefixKey = "bkoi_trace_flutter_mqtt_client_id_prefix"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static var mqttClientIdPrefix: String? {
        get { defaults.string(forKey: prefixKey) }
        set {
            if let newValue = newValue {
                defaults.set(newValue, forKey: prefixKey)
            } else {
                defaults.removeObject(forKey: prefixKey)
            }
        }
    }
}

/// The one place `BarikoiTrace.initialize` is called.
///
/// **Why not from the `initialize` channel method.**
/// `TraceManager.initialize(apiKey:)` unconditionally calls
/// `TraceBackgroundCoordinator.registerBackgroundTasks(manager:)`, which calls
/// `BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:)`.
/// That API has two hard rules: registration must happen before
/// `application(_:didFinishLaunchingWithOptions:)` returns, and the same
/// identifier must not be registered twice (the second call raises an
/// `NSInternalInconsistencyException` and terminates the app). A Dart method
/// call arrives long after launch has finished and can arrive repeatedly — a
/// hot restart alone re-runs the host app's `main()` — so routing the SDK's
/// `initialize` through it would break both rules.
///
/// So the SDK is initialized here, from the plugin's `UIApplicationDelegate`
/// hook, reconstructing the config entirely from persisted state:
///
/// | `TraceConfig` field  | Source                                        |
/// | -------------------- | --------------------------------------------- |
/// | `apiKey`             | `TraceDataStore.getApiKey()`, else the host app's `BarikoiTraceApiKey` Info.plist entry, else empty |
/// | `mqttUsername`       | `TraceDataStore.getMqttUsername()`            |
/// | `mqttPassword`       | `TraceDataStore.getMqttPassword()`            |
/// | `baseURL`            | `TraceDataStore.getBaseURL()`, else the SDK default |
/// | `mqttURL`            | `TraceDataStore.getMqttURL()`, else the SDK default |
/// | `mqttClientIdPrefix` | `PluginPreferences.mqttClientIdPrefix`, else the SDK default |
///
/// The consequence, and it is unavoidable rather than incidental: on the very
/// first launch of a fresh install there is nothing persisted, so the SDK
/// starts this session without credentials. The Dart `initialize` call then
/// persists them and applies everything that *can* be applied post-launch; the
/// API key alone waits for the next launch, and the plugin logs a WARN saying
/// so. Host apps that want a working first launch put their key in
/// `Info.plist` under `BarikoiTraceApiKey`.
enum LaunchBootstrap {

    /// Info.plist key an integrator can set so the very first launch of a
    /// fresh install already has an API key.
    static let apiKeyInfoPlistKey = "BarikoiTraceApiKey"

    /// Whether the AppDelegate hook ran. Read by the `initialize` channel
    /// method: if this is still false by the time Dart calls `initialize`, the
    /// host app registered its plugins after `super.application(...)` (or
    /// hand-rolled an AppDelegate that never forwards the callback), and no
    /// background task is registered. There is no way to detect that from
    /// Dart, so it is logged.
    private(set) static var didFireLaunchHook = false

    /// Guards against a double `initialize` if the hook is somehow delivered
    /// twice (two Flutter engines in one process each register the plugin).
    private static var didInitialize = false

    static func run(launchOptions: [AnyHashable: Any], log: LogStreamHandler) {
        didFireLaunchHook = true
        guard !didInitialize else { return }
        didInitialize = true

        let store = TraceDataStore()

        let persistedKey = store.getApiKey()
        let infoPlistKey = Bundle.main.object(forInfoDictionaryKey: apiKeyInfoPlistKey) as? String
        let apiKey = firstNonEmpty(persistedKey, infoPlistKey) ?? ""

        var config = TraceConfig(
            apiKey: apiKey,
            mqttUsername: store.getMqttUsername() ?? "",
            mqttPassword: store.getMqttPassword() ?? ""
        )
        // Only overridden when something was actually persisted — assigning
        // the SDK's own default back would be indistinguishable from a host
        // app pinning today's default forever.
        if let baseURL = firstNonEmpty(store.getBaseURL()) { config.baseURL = baseURL }
        if let mqttURL = firstNonEmpty(store.getMqttURL()) { config.mqttURL = mqttURL }
        if let prefix = firstNonEmpty(PluginPreferences.mqttClientIdPrefix) {
            config.mqttClientIdPrefix = prefix
        }

        // `BarikoiTrace.initialize` logs these itself, but through
        // `TraceManager.log`, which drops everything until
        // `TraceManager.initialize` turns logging on — i.e. exactly these
        // lines, on exactly the fresh install where they matter. Emitted here
        // instead, into the buffer the `logs` channel replays.
        for warning in config.warnings {
            log.emit(level: "WARN", tag: "TraceConfig", message: warning)
        }
        if apiKey.isEmpty {
            log.emit(
                level: "WARN",
                tag: "BarikoiTraceFlutterPlugin",
                message: "No API key available at launch. Nothing is persisted yet and Info.plist "
                    + "carries no '\(apiKeyInfoPlistKey)' entry, so this session starts unauthenticated. "
                    + "Calling initialize() from Dart stores the key for the next launch."
            )
        }

        BarikoiTrace.initialize(config)
        // Must follow `initialize`: it is what resumes tracking after a
        // significant-location-change relaunch of a killed process, and it
        // needs the manager already wired up.
        BarikoiTrace.handleLaunch(options: launchOptions)
    }

    private static func firstNonEmpty(_ candidates: String?...) -> String? {
        for candidate in candidates {
            if let candidate = candidate, !candidate.isEmpty { return candidate }
        }
        return nil
    }
}
