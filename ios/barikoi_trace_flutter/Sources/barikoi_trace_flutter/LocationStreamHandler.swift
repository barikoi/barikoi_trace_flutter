import CoreLocation
import Flutter
import Foundation

import BarikoiTrace

/// A `FlutterEventSink` is a plain closure, and closures are not `Sendable`.
/// Wrapping it in a reference type that owns the main-thread hop keeps the
/// sink out of the `Task`'s captured state and gives every emitter a single
/// place that guarantees "delivered on the platform thread".
final class EventSinkBox: @unchecked Sendable {
    private let sink: FlutterEventSink

    init(_ sink: @escaping FlutterEventSink) {
        self.sink = sink
    }

    func send(_ value: Any?) {
        if Thread.isMainThread {
            sink(value)
        } else {
            DispatchQueue.main.async { self.sink(value) }
        }
    }
}

/// Backs `barikoi_trace_flutter/location_updates`.
///
/// `BarikoiTrace.locationUpdates` is an `AsyncStream<CLLocation>` — a fresh
/// multi-consumer stream per access, produced by the SDK's `AsyncBroadcast`.
/// Consuming it needs a `Task`, so `onListen` starts one and `onCancel`
/// cancels it; cancelling ends the `for await` loop, which tears the
/// broadcast's registration down.
///
/// The stream is silent until `setBroadcastingEnabled(true)` — the gate lives
/// in `TraceManager.handleLocation`, not here — so `onListen` on a
/// non-broadcasting SDK is a no-op that costs one suspended task.
///
/// No backpressure and no buffering: the contract says drop rather than
/// buffer, and `AsyncBroadcast`'s continuations already do exactly that.
final class LocationStreamHandler: NSObject, FlutterStreamHandler {

    private var task: Task<Void, Never>?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        // Dart treats this as a broadcast stream and builds it once per plugin
        // instance, so `onListen` can legitimately be entered while a previous
        // session is still running. Cancel it rather than leaking a second
        // consumer that would double every fix.
        task?.cancel()

        let box = EventSinkBox(events)
        task = Task {
            for await location in BarikoiTrace.locationUpdates {
                if Task.isCancelled { break }
                box.send(Codecs.encodeLocation(location))
            }
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        task?.cancel()
        task = nil
        return nil
    }

    /// Belt and braces for a plugin torn down without an `onCancel` — a
    /// detached `Task` holding an `AsyncStream` iterator would otherwise stay
    /// registered with the SDK's broadcast for the life of the process.
    deinit {
        task?.cancel()
    }
}
