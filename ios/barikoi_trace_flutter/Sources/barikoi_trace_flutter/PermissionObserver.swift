import CoreLocation
import Foundation
import UIKit

import BarikoiTrace

/// Turns the SDK's fire-and-forget authorization prompts into the
/// resolve-after-the-prompt-settles contract the channel needs.
///
/// `BarikoiTrace.requestLocationPermissions()` and
/// `requestBackgroundLocationPermission()` return `Void`: they ask
/// CoreLocation and the answer arrives later, on the SDK's own internal
/// delegate. This class stands up a second `CLLocationManager` purely to
/// observe `locationManagerDidChangeAuthorization` — authorization callbacks
/// are broadcast to *every* live manager in the process, so watching from
/// here costs nothing and does not disturb the SDK's engine.
///
/// Three things resolve a pending request, because on iOS a "request" does not
/// always produce a dialog:
///
///  - **The authorization callback**, the normal path.
///  - **Return to foreground.** A system permission alert makes the app resign
///    active; the matching `didBecomeActive` is a reliable "the dialog is
///    gone" signal, and it also covers a trip out to Settings.
///  - **A timeout.** The case with no signal at all: asking for `Always` when
///    the user already declined it shows nothing and changes nothing. Without
///    this the Dart future would never complete.
///
/// Every path resolves to the *current* authorization state, so a request that
/// was silently ignored answers `false` rather than hanging.
final class PermissionObserver: NSObject, CLLocationManagerDelegate {

    enum Kind {
        case whenInUse
        case always
    }

    private struct PendingRequest {
        let kind: Kind
        let completion: (Bool) -> Void
    }

    /// Long enough for a user to read a dialog, short enough that a prompt
    /// that never appears does not look like a hang.
    private static let requestTimeout: TimeInterval = 15

    /// The authorization change and `didBecomeActive` race each other after a
    /// dialog is dismissed. This delay lets the change land first, so the
    /// foreground path only ever resolves requests the callback did not.
    private static let foregroundSettleDelay: TimeInterval = 0.75

    private let manager = CLLocationManager()
    private var pending: [PendingRequest] = []
    private var foregroundObserver: NSObjectProtocol?
    private var timeoutWorkItem: DispatchWorkItem?

    override init() {
        super.init()
        // Installed up front, not at request time: iOS delivers one
        // `locationManagerDidChangeAuthorization` immediately when a delegate
        // is set, and that callback must not be mistaken for the answer to a
        // request. With no request pending it is ignored.
        manager.delegate = self
    }

    deinit {
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        timeoutWorkItem?.cancel()
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    var isForegroundGranted: Bool {
        let status = manager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    // MARK: - Requests

    /// Prompts for When In Use. Resolves immediately — without prompting —
    /// when the permission is already granted, and equally when it has been
    /// denied or restricted, since iOS never re-prompts after a decision.
    func requestWhenInUse(_ completion: @escaping (Bool) -> Void) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            completion(true)
            return
        }
        guard status == .notDetermined else {
            // Denied or restricted: report the current state rather than
            // waiting for a dialog that will never appear.
            completion(false)
            return
        }

        enqueue(PendingRequest(kind: .whenInUse, completion: completion))
        BarikoiTrace.requestLocationPermissions()
    }

    /// Prompts for Always. iOS only grants it on top of When In Use, so a
    /// missing foreground permission resolves `false` without prompting —
    /// matching the contract and the Android side.
    func requestAlways(_ completion: @escaping (Bool) -> Void) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways {
            completion(true)
            return
        }
        guard status == .authorizedWhenInUse else {
            completion(false)
            return
        }

        enqueue(PendingRequest(kind: .always, completion: completion))
        BarikoiTrace.requestBackgroundLocationPermission()
    }

    // MARK: - Resolution

    private func enqueue(_ request: PendingRequest) {
        pending.append(request)
        guard pending.count == 1 else { return }

        let observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + PermissionObserver.foregroundSettleDelay) {
                self?.resolveAll()
            }
        }
        foregroundObserver = observer

        let work = DispatchWorkItem { [weak self] in self?.resolveAll() }
        timeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PermissionObserver.requestTimeout, execute: work)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        resolveDecided()
    }

    /// Resolves only the requests the current status actually answers, leaving
    /// the still-undecided ones waiting. `notDetermined` never answers a
    /// When In Use request, and "still When In Use" never answers an Always
    /// request — iOS can deliver an authorization change for an unrelated
    /// reason while a prompt is on screen.
    private func resolveDecided() {
        guard !pending.isEmpty else { return }
        let status = manager.authorizationStatus

        var stillPending: [PendingRequest] = []
        var answered: [(PendingRequest, Bool)] = []

        for request in pending {
            switch request.kind {
            case .whenInUse:
                if status == .notDetermined {
                    stillPending.append(request)
                } else {
                    answered.append((request, status == .authorizedWhenInUse || status == .authorizedAlways))
                }
            case .always:
                if status == .authorizedAlways {
                    answered.append((request, true))
                } else if status == .denied || status == .restricted {
                    answered.append((request, false))
                } else {
                    stillPending.append(request)
                }
            }
        }

        pending = stillPending
        if pending.isEmpty { cancelWatchdogs() }
        for (request, granted) in answered { request.completion(granted) }
    }

    /// The watchdog paths: resolve everything against the current state,
    /// whatever it is.
    private func resolveAll() {
        guard !pending.isEmpty else { return }
        let status = manager.authorizationStatus
        let requests = pending
        pending = []
        cancelWatchdogs()

        for request in requests {
            switch request.kind {
            case .whenInUse:
                request.completion(status == .authorizedWhenInUse || status == .authorizedAlways)
            case .always:
                request.completion(status == .authorizedAlways)
            }
        }
    }

    private func cancelWatchdogs() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
    }
}
