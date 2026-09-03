package com.barikoi.barikoitrace.flutter

import com.barikoi.barikoitrace.BarikoiTrace
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * `barikoi_trace_flutter/location_updates` — one `TraceLocation` map per fix.
 *
 * The source is `BarikoiTrace.locationUpdates`, a `SharedFlow<Location>` with
 * `replay = 0` that the SDK's foreground service emits into while broadcasting
 * is enabled. A SharedFlow has no completion, so the collection runs until the
 * job is cancelled in [onCancel] or the plugin scope dies.
 *
 * [scope] is the plugin's `Dispatchers.Main.immediate` scope, so every
 * `EventSink` call already happens on the platform thread, as the sink requires.
 */
internal class LocationStreamHandler(
    private val scope: CoroutineScope
) : EventChannel.StreamHandler {

    private var job: Job? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        // Dart creates this stream once per plugin instance and treats it as a
        // broadcast stream, so onListen can be entered while a previous session
        // is still winding down. Cancel first; never run two collectors.
        job?.cancel()
        job = null

        val sink = events ?: return

        job = scope.launch {
            // `BarikoiTrace.locationUpdates` reads through
            // BarikoiTrace.getInstance(), which throws IllegalStateException
            // until initialize() has run. A Dart app that subscribes before it
            // initializes is a normal ordering, not a fatal one — report it
            // once so the subscriber is not left guessing, then keep retrying
            // so the stream heals itself when initialize() lands.
            var reportedNotInitialized = false
            var backoffMs = 250L

            while (isActive) {
                val flow = try {
                    BarikoiTrace.locationUpdates
                } catch (e: IllegalStateException) {
                    if (!reportedNotInitialized) {
                        reportedNotInitialized = true
                        sink.error(
                            BarikoiTraceFlutterPlugin.CODE_NOT_INITIALIZED,
                            e.message
                                ?: "BarikoiTrace is not initialized. Call initialize() first.",
                            null
                        )
                    }
                    delay(backoffMs)
                    backoffMs = (backoffMs * 2).coerceAtMost(MAX_BACKOFF_MS)
                    continue
                }

                // Suspends forever; only cancellation gets us out.
                flow.collect { location ->
                    sink.success(Codecs.encodeLocation(location))
                }
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        job?.cancel()
        job = null
    }

    /** Called when the engine detaches, so a stray collector cannot outlive it. */
    fun dispose() {
        job?.cancel()
        job = null
    }

    private companion object {
        const val MAX_BACKOFF_MS = 2_000L
    }
}
