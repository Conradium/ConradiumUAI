package dev.projectuai.relay.engine

import java.security.MessageDigest

/**
 * The idempotency key for one submitted inference: a re-submit of the same id with the
 * same fingerprint is the same job; anything else under the same id is a client bug.
 */
object Fingerprint {
    fun of(url: String, headers: Map<String, String>, body: String, sessionId: String?): String {
        val digest = MessageDigest.getInstance("SHA-256")
        fun field(text: String) {
            digest.update(text.toByteArray(Charsets.UTF_8))
            digest.update(0.toByte())
        }
        field(url)
        headers.entries
            .sortedWith(compareBy({ it.key.lowercase() }, { it.value }))
            .forEach { field(it.key.lowercase()); field(it.value) }
        field(body)
        field(sessionId ?: "")
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
