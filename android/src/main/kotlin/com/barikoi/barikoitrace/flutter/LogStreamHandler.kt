package com.barikoi.barikoitrace.flutter

import android.os.Handler
import android.os.Looper
import com.barikoi.barikoitrace.BarikoiTrace
import io.flutter.plugin.common.EventChannel

/**
 * `barikoi_trace_flutter/logs` — one `TraceLogEntry` map per native log line.
 *
 * Installed as the single `BarikoiTrace.TraceLogListener` for the process and
 * fanned out to whatever is currently listening on the event channel.
 *
 * Why the ring buffer: the most useful log lines the SDK produces are the
 * `TraceConfig.warnings` it emits from inside `initialize()` — empty API key,
 * empty broker credentials, plaintext `mqttUrl`, non-HTTPS `baseUrl`. Those
 * fire before any realistic Dart subscriber exists (the host has to call
 * `initialize` to have a plugin worth listening to). Without a replay they are
 * simply lost, which is the opposite of what a diagnostics channel is for. So
 * entries accumulate while nobody is listening, capped at [MAX_BUFFERED], and
 * are handed to the next subscriber before live traffic.
 *
 * Threading, per WIRE_CONTRACT §7.2: `onLog` can fire from any thread — an
 * OkHttp callback, the foreground service, the MQTT client — and it can fire
 * re-entrantly from inside SDK code the plugin itself called. Everything
 * therefore hops to the main thread, and delivery runs as a drain loop guarded
 * by [draining], so a log line emitted from inside `EventSink.success` is
 * queued and flushed by the loop already running rather than recursing.
 */
internal class LogStreamHandler : EventChannel.StreamHandler, BarikoiTrace.TraceLogListener {

    private val mainHandler = Handler(Looper.getMainLooper())

    private val bufferLock = Any()
    private val buffered = ArrayDeque<Map<String, Any?>>()

    /** Touched on the main thread only. */
    private var sink: EventChannel.EventSink? = null
    private var draining = false

    // --- TraceLogListener ---

    override fun onLog(level: String, tag: String, message: String) {
        // Stamped here, at callback time: the native callback carries no
        // timestamp of its own (WIRE_CONTRACT §4.5).
        val entry = Codecs.encodeLogEntry(level, tag, message, System.currentTimeMillis())

        synchronized(bufferLock) {
            buffered.addLast(entry)
            while (buffered.size > MAX_BUFFERED) {
                buffered.removeFirst()
            }
        }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            drain()
        } else {
            mainHandler.post { drain() }
        }
    }

    // --- EventChannel.StreamHandler ---

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        // Replays whatever accumulated before this subscriber arrived —
        // initialize-time warnings above all — then continues live.
        drain()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /**
     * Called when the engine detaches. Drops the sink and the backlog: the next
     * engine gets a fresh handler, and replaying a previous engine's log into
     * it would be misleading.
     */
    fun dispose() {
        sink = null
        synchronized(bufferLock) { buffered.clear() }
    }

    // --- Delivery ---

    /** Main thread only. */
    private fun drain() {
        if (draining) return
        val target = sink ?: return

        draining = true
        try {
            while (true) {
                val next = synchronized(bufferLock) { buffered.removeFirstOrNull() } ?: break
                try {
                    target.success(next)
                } catch (_: Throwable) {
                    // The sink is gone or the messenger is shutting down. The
                    // log channel must never fail the stream (§7.2), and it must
                    // never log from inside the sink, so this is swallowed on
                    // purpose.
                    sink = null
                    break
                }
            }
        } finally {
            draining = false
        }
    }

    private companion object {
        /**
         * Roughly one screen of scrollback. Large enough to hold every
         * initialize-time warning plus the first burst of session logs, small
         * enough that an app which never listens cannot grow it without bound.
         */
        const val MAX_BUFFERED = 200
    }
}
