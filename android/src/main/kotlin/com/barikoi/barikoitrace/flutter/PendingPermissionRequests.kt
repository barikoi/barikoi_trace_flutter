package com.barikoi.barikoitrace.flutter

/**
 * Request-code → in-flight permission request bookkeeping.
 *
 * A runtime permission prompt answers through
 * `Activity.onRequestPermissionsResult`, which carries nothing but the request
 * code the prompt was issued with — so the plugin has to remember, per code,
 * which channel calls are still waiting on it.
 *
 * Three things this exists to guarantee (WIRE_CONTRACT §6.3):
 *
 *  1. **Exactly once.** [Entry.resolve] latches, so a result cannot be
 *     delivered twice — not by a system callback that arrives after a timeout
 *     already answered, and not by an activity detach racing the callback.
 *  2. **All waiters answered.** Two Dart calls to `requestLocationPermissions`
 *     before the first prompt settles share one system request code; both get
 *     the same answer instead of one hanging forever.
 *  3. **Nothing leaks.** [takeEverything] lets the plugin drain and answer
 *     every waiter with the current permission state when the Activity goes
 *     away for good.
 *
 * Entries are added and resolved on the main thread, but the map is guarded
 * anyway: an SDK callback is free to land on any thread and the cost is nil.
 */
internal class PendingPermissionRequests {

    /** One waiting channel call. */
    internal class Entry internal constructor(
        /** The system request code this entry is waiting on. */
        val requestCode: Int,
        private val onResolved: (Boolean) -> Unit
    ) {
        private var resolved = false

        /**
         * Delivers [granted] to the waiter, once. Returns false when this entry
         * had already been resolved, so callers can tell a real delivery from a
         * late duplicate.
         */
        fun resolve(granted: Boolean): Boolean {
            synchronized(this) {
                if (resolved) return false
                resolved = true
            }
            onResolved(granted)
            return true
        }

        /** Whether [resolve] has already run. */
        val isResolved: Boolean
            get() = synchronized(this) { resolved }
    }

    private val lock = Any()
    private val byRequestCode = LinkedHashMap<Int, MutableList<Entry>>()

    /** Registers a waiter for [requestCode] and returns its handle. */
    fun add(requestCode: Int, onResolved: (Boolean) -> Unit): Entry {
        val entry = Entry(requestCode, onResolved)
        synchronized(lock) {
            byRequestCode.getOrPut(requestCode) { mutableListOf() }.add(entry)
        }
        return entry
    }

    /**
     * Forgets [entry] without resolving it. Used when the caller's coroutine is
     * cancelled, or when issuing the prompt itself threw.
     */
    fun remove(entry: Entry) {
        synchronized(lock) {
            val waiters = byRequestCode[entry.requestCode] ?: return
            waiters.remove(entry)
            if (waiters.isEmpty()) byRequestCode.remove(entry.requestCode)
        }
    }

    /**
     * Removes and returns every waiter on [requestCode]. Removal and read are
     * one atomic step, so a concurrent system callback and detach cannot both
     * hand out the same entry.
     */
    fun takeAll(requestCode: Int): List<Entry> = synchronized(lock) {
        byRequestCode.remove(requestCode)?.toList() ?: emptyList()
    }

    /** Removes and returns every waiter, for any code. */
    fun takeEverything(): List<Entry> = synchronized(lock) {
        val all = byRequestCode.values.flatten()
        byRequestCode.clear()
        all
    }

    /** Whether anything is waiting on [requestCode]. */
    fun hasPending(requestCode: Int): Boolean = synchronized(lock) {
        byRequestCode[requestCode]?.isNotEmpty() == true
    }
}
