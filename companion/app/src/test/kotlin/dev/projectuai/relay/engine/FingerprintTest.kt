package dev.projectuai.relay.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class FingerprintTest {
    @Test
    fun `is stable and order-independent`() {
        val a = Fingerprint.of("https://x/v1", mapOf("A" to "1", "B" to "2"), "{}", "s1")
        val b = Fingerprint.of("https://x/v1", mapOf("B" to "2", "A" to "1"), "{}", "s1")
        assertEquals(a, b)
    }

    @Test
    fun `changes with any material field`() {
        val base = Fingerprint.of("https://x/v1", mapOf("A" to "1"), "{}", "s1")
        assertNotEquals(base, Fingerprint.of("https://x/v2", mapOf("A" to "1"), "{}", "s1"))
        assertNotEquals(base, Fingerprint.of("https://x/v1", mapOf("A" to "2"), "{}", "s1"))
        assertNotEquals(base, Fingerprint.of("https://x/v1", mapOf("A" to "1"), "{\"a\":1}", "s1"))
        assertNotEquals(base, Fingerprint.of("https://x/v1", mapOf("A" to "1"), "{}", "s2"))
    }

    @Test
    fun `is a 64 character hex digest`() {
        val value = Fingerprint.of("https://x/v1", emptyMap(), "", null)
        assertEquals(64, value.length)
        assertEquals(value, value.lowercase())
    }
}
