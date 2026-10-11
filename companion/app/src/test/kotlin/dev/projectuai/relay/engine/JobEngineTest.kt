package dev.projectuai.relay.engine

import dev.projectuai.relay.protocol.JobState
import dev.projectuai.relay.protocol.JobView
import dev.projectuai.relay.protocol.SubmitRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.TimeUnit

class JobEngineTest {
    private lateinit var upstream: MockWebServer
    private lateinit var scope: CoroutineScope
    private val instance = "inst-test"

    @Before
    fun setUp() {
        upstream = MockWebServer()
        upstream.start()
        scope = CoroutineScope(Dispatchers.IO)
    }

    @After
    fun tearDown() {
        scope.cancel()
        upstream.shutdown()
    }

    private fun engine(limits: JobEngine.Limits = JobEngine.Limits()) = JobEngine(instance, scope, limits = limits)

    private fun submitRequest(
        id: String = "inference_abcdef12",
        url: String? = null,
        timeout: Int = 180,
        headers: Map<String, String> = mapOf("Authorization" to "Bearer key"),
        instanceValue: String = instance,
        body: String = "{\"model\":\"m\"}",
    ) = SubmitRequest(
        id = id,
        instance = instanceValue,
        url = url ?: upstream.url("/v1/chat/completions").toString(),
        headers = headers,
        body = body,
        timeout = timeout,
    )

    private fun waitFor(engine: JobEngine, id: String): JobView? {
        val deadline = System.currentTimeMillis() + 5000
        while (System.currentTimeMillis() < deadline) {
            val view = engine.poll(id)
            if (view != null && view.state != JobState.RUNNING) return view
            Thread.sleep(20)
        }
        return engine.poll(id)
    }

    @Test
    fun `completes a forwarded request with filtered headers`() {
        upstream.enqueue(MockResponse().setResponseCode(200).setBody("{\"answer\":1}"))
        val engine = engine()
        assertTrue(engine.submit(submitRequest()) is JobEngine.Submission.Accepted)
        val view = waitFor(engine, "inference_abcdef12")!!
        assertEquals(JobState.COMPLETED, view.state)
        assertEquals(200, view.status)
        assertEquals("{\"answer\":1}", view.body)
        val recorded = upstream.takeRequest()
        assertEquals("/v1/chat/completions", recorded.path)
        assertEquals("identity", recorded.getHeader("accept-encoding"))
        assertEquals("Bearer key", recorded.getHeader("authorization"))
    }

    @Test
    fun `is idempotent for the same id and fingerprint`() {
        upstream.enqueue(MockResponse().setResponseCode(200).setBody("{}"))
        val engine = engine()
        engine.submit(submitRequest())
        waitFor(engine, "inference_abcdef12")
        assertTrue(engine.submit(submitRequest()) is JobEngine.Submission.Accepted)
        assertEquals(1, upstream.requestCount)
    }

    @Test
    fun `rejects the same id with a different request`() {
        upstream.enqueue(MockResponse().setResponseCode(200).setBody("{}"))
        val engine = engine()
        engine.submit(submitRequest())
        waitFor(engine, "inference_abcdef12")
        val conflict = engine.submit(submitRequest(body = "{\"changed\":true}"))
        assertTrue(conflict is JobEngine.Submission.Rejected)
        assertEquals(409, (conflict as JobEngine.Submission.Rejected).status)
    }

    @Test
    fun `rejects a stale instance without touching the provider`() {
        val engine = engine()
        val result = engine.submit(submitRequest(instanceValue = "other"))
        assertTrue(result is JobEngine.Submission.Rejected)
        assertEquals(409, (result as JobEngine.Submission.Rejected).status)
        assertEquals(0, upstream.requestCount)
    }

    @Test
    fun `rejects an unsafe url`() {
        val result = engine().submit(submitRequest(url = "http://169.254.169.254/latest"))
        assertTrue(result is JobEngine.Submission.Rejected)
        assertEquals(400, (result as JobEngine.Submission.Rejected).status)
    }

    @Test
    fun `answers at capacity with 503`() {
        upstream.enqueue(MockResponse().setResponseCode(200).setBody("{}").setBodyDelay(2, TimeUnit.SECONDS))
        val engine = engine(JobEngine.Limits(maxActive = 1))
        assertTrue(engine.submit(submitRequest(id = "inference_first000")) is JobEngine.Submission.Accepted)
        val second = engine.submit(submitRequest(id = "inference_second00"))
        assertTrue(second is JobEngine.Submission.Rejected)
        assertEquals(503, (second as JobEngine.Submission.Rejected).status)
    }

    @Test
    fun `cancels a running job`() {
        upstream.enqueue(MockResponse().setResponseCode(200).setBody("{}").setBodyDelay(2, TimeUnit.SECONDS))
        val engine = engine()
        engine.submit(submitRequest())
        Thread.sleep(100)
        assertTrue(engine.cancel("inference_abcdef12"))
        assertEquals(JobState.CANCELLED, waitFor(engine, "inference_abcdef12")!!.state)
    }

    @Test
    fun `tombstones an evicted job as expired`() {
        upstream.enqueue(MockResponse().setResponseCode(200).setBody("{}"))
        val engine = engine(JobEngine.Limits(retentionMs = 0))
        engine.submit(submitRequest())
        waitFor(engine, "inference_abcdef12")
        Thread.sleep(20)
        engine.sweep()
        assertEquals(JobState.EXPIRED, engine.poll("inference_abcdef12")?.state)
    }

    @Test
    fun `unknown id reads as null for a 404`() {
        assertNull(engine().poll("inference_missing"))
    }

    @Test
    fun `carries an upstream error status without resubmitting`() {
        upstream.enqueue(MockResponse().setResponseCode(500).setBody("boom"))
        val engine = engine()
        engine.submit(submitRequest())
        val view = waitFor(engine, "inference_abcdef12")!!
        assertEquals(JobState.COMPLETED, view.state)
        assertEquals(500, view.status)
        assertEquals(1, upstream.requestCount)
    }
}
