package dev.projectuai.relay

import java.time.LocalTime

/** A small in-memory log tail for the Diagnostics screen. Never persisted. */
class RelayLog(private val capacity: Int = 200) {
    private val entries = ArrayDeque<String>()
    private val lock = Any()

    fun add(message: String) {
        val stamp = LocalTime.now().withNano(0).toString()
        synchronized(lock) {
            entries.addLast("$stamp  $message")
            while (entries.size > capacity) entries.removeFirst()
        }
    }

    fun tail(): List<String> = synchronized(lock) { entries.toList() }
}
