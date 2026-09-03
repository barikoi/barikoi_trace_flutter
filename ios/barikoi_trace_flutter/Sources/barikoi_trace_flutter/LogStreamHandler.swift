import Flutter
import Foundation

import BarikoiTrace

/// Backs `barikoi_trace_flutter/logs`.
///
/// Three things make this more than a straight adapter:
///
///  1. **`TraceManager.logListener` is `weak`.** `BarikoiTrace.setLogListener`
///     assigns straight into it, so nothing in the SDK keeps this object
///     alive. The plugin instance holds it strongly (and the plugin instance
///     is itself retained by `addMethodCallDelegate`), which is the only
///     reason logs keep arriving after `register(with:)` returns.
///  2. **A replay buffer.** The launch-time and `initialize`-time
///     configuration warnings are produced before Dart has had any chance to
///     subscribe — they are, in fact, exactly the diagnostics an integrator
///     needs most. They are buffered and flushed to the first subscriber.
///  3. **Everything happens on the main thread.** The SDK's log callback fires
///     on whatever thread produced the line, including from inside SDK code
///     the plugin itself called. Hopping to main before touching the sink
///     satisfies the channel's threading rule and, as a side effect, makes the
///     buffer/sink pair single-threaded so it needs no lock.
final class LogStreamHandler: NSObject, FlutterStreamHandler, TraceLogListener {

    /// Roughly a screenful of scrollback. Old entries are dropped, not the new
    /// ones — a full buffer means the interesting lines are the recent ones.
    private static let bufferCapacity = 200

    /// Main-thread only. See the class comment.
    private var buffer: [[String: Any]] = []
    private var sink: FlutterEventSink?

    // MARK: - TraceLogListener

    func onLog(level: String, tag: String, message: String) {
        emit(level: level, tag: tag, message: message)
    }

    // MARK: - Plugin-authored entries

    /// Emits a line the plugin itself produced (config warnings, AppDelegate
    /// ordering diagnostics).
    ///
    /// These deliberately do **not** go through `TraceManager.log`, for two
    /// reasons: that method drops everything while `setLoggingEnabled(false)`
    /// — which is the state on a fresh install, before the SDK's own
    /// `initialize` turns logging on — and it would then call back into this
    /// object as the registered listener, duplicating every entry.
    func emit(level: String, tag: String, message: String) {
        let entry = Codecs.encodeLogEntry(level: level, tag: tag, message: message)
        if Thread.isMainThread {
            deliver(entry)
        } else {
            DispatchQueue.main.async { [weak self] in self?.deliver(entry) }
        }
    }

    /// Main thread only.
    private func deliver(_ entry: [String: Any]) {
        if let sink = sink {
            sink(entry)
        } else {
            if buffer.count >= LogStreamHandler.bufferCapacity {
                buffer.removeFirst(buffer.count - LogStreamHandler.bufferCapacity + 1)
            }
            buffer.append(entry)
        }
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        let replay = buffer
        buffer.removeAll()
        for entry in replay {
            events(entry)
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        // Back to buffering. A Dart-side hot restart cancels and re-listens,
        // and the lines produced in between are still worth showing.
        sink = nil
        return nil
    }
}
