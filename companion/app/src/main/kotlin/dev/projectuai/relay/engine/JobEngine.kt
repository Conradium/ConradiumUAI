package dev.projectuai.relay.engine

import dev.projectuai.relay.protocol.JobState
import dev.projectuai.relay.protocol.JobView
import dev.projectuai.relay.protocol.SubmitRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import okhttp3.Call
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okio.Buffer
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * Owns the upstream connection so every executor-visible call is a few milliseconds.
 * Idempotent by submit id, cap-bounded for a phone, and terminal-by-state exactly as
 * src/net/relay.lua expects.
 */
class JobEngine(
    private val instance: String,
    private val scope: CoroutineScope,
    private val client: OkHttpClient = OkHttpClient(),
    val limits: Limits = Limits(),
    private val clock: () -> Long = System::currentTimeMillis,
    private val onChanged: () -> Unit = {},
) {
    data class Limits(
        val bodyBytes: Long = 8L * 1024 * 1024,
        val maxJobs: Int = 200,
        val maxActive: Int = 4,
        val retainedBytes: Long = 32L * 1024 * 1024,
        val retentionMs: Long = 60_000,
        val tombstones: Int = 20_000,
    )

    private class Job(val id: String) {
        @Volatile var state = JobState.RUNNING
        @Volatile var status = 0
        @Volatile var headers: Map<String, String> = emptyMap()
        @Volatile var body: String? = null
        @Volatile var error: String? = null
        @Volatile var finishedAt = 0L
        @Volatile var retained = 0L
        @Volatile var call: Call? = null
        @Volatile var cancelled = false
    }

    sealed class Submission {
        data class Accepted(val view: JobView) : Submission()
        data class Rejected(val status: Int, val message: String) : Submission()
    }

    private val lock = Any()
    private val jobs = LinkedHashMap<String, Job>()
    private val knownFingerprints = HashMap<String, String>()
    private val tombstones = ArrayDeque<String>()
    private val tombstoneSet = HashSet<String>()
    private var retainedBytes = 0L
    @Volatile private var activeJobs = 0
    @Volatile private var totalJobs = 0

    val activeCount: Int get() = activeJobs
    val retained: Long get() = retainedBytes
    val total: Int get() = totalJobs

    fun submit(request: SubmitRequest): Submission {
        sweep()
        if (!RequestRules.ID.matches(request.id)) return Submission.Rejected(400, "invalid inference id")
        if (request.instance != instance) {
            return Submission.Rejected(409, "The relay restarted; submit a new request")
        }
        RequestRules.validateUrl(request.url)?.let { return Submission.Rejected(400, it) }
        if (request.body.toByteArray(Charsets.UTF_8).size.toLong() > limits.bodyBytes) {
            return Submission.Rejected(413, "request body exceeds the relay limit")
        }

        val headers = RequestRules.filterRequestHeaders(request.headers)
        val timeout = RequestRules.clampTimeout(request.timeout)
        val fingerprint = Fingerprint.of(request.url, headers, request.body, request.sessionId)

        var job: Job? = null
        synchronized(lock) {
            val known = knownFingerprints[request.id]
            if (known != null) {
                if (known != fingerprint) return Submission.Rejected(409, "inference id reused with a different request")
                val existing = jobs[request.id]
                if (existing != null) return Submission.Accepted(view(existing))
                return Submission.Rejected(410, "expired; do not resubmit")
            }
            if (tombstoneSet.contains(request.id)) return Submission.Rejected(410, "expired; do not resubmit")
            if (activeJobs >= limits.maxActive) return Submission.Rejected(503, "at capacity; retry shortly")
            pruneLocked()
            if (jobs.size >= limits.maxJobs) return Submission.Rejected(503, "at capacity; retry shortly")
            val created = Job(request.id)
            job = created
            jobs[request.id] = created
            knownFingerprints[request.id] = fingerprint
            activeJobs += 1
            totalJobs += 1
        }
        val started = job ?: return Submission.Rejected(503, "at capacity; retry shortly")
        scope.launch { execute(started, request, headers, timeout) }
        return Submission.Accepted(view(started))
    }

    fun poll(id: String): JobView? {
        sweep()
        synchronized(lock) {
            jobs[id]?.let { return view(it) }
            if (tombstoneSet.contains(id)) return JobView(id, JobState.EXPIRED, error = "expired; do not resubmit")
            return null
        }
    }

    fun cancel(id: String): Boolean {
        sweep()
        val job = synchronized(lock) { jobs[id] } ?: return false
        job.cancelled = true
        finish(job, JobState.CANCELLED, error = "cancelled")
        job.call?.cancel()
        return true
    }

    fun cancelAll() {
        val running = synchronized(lock) { jobs.values.filter { it.state == JobState.RUNNING } }
        running.forEach {
            it.cancelled = true
            finish(it, JobState.CANCELLED, error = "relay stopped")
            it.call?.cancel()
        }
    }

    /** Drops completed bodies past their retention window and tombstones their ids. */
    fun sweep() {
        val now = clock()
        val expired = synchronized(lock) {
            jobs.values.filter { it.state != JobState.RUNNING && now - it.finishedAt > limits.retentionMs }.map { it.id }
        }
        if (expired.isEmpty()) return
        synchronized(lock) { expired.forEach { removeLocked(it) } }
        onChanged()
    }

    private fun execute(job: Job, request: SubmitRequest, headers: Map<String, String>, timeout: Int) {
        try {
            val builder = Request.Builder().url(request.url)
            headers.forEach { (key, value) -> builder.addHeader(key, value) }
            val mediaType = headers.entries.firstOrNull { it.key.equals("content-type", true) }
                ?.value?.toMediaTypeOrNull() ?: "application/json".toMediaTypeOrNull()
            builder.method("POST", request.body.toRequestBody(mediaType))
            val call = client.newCall(builder.build())
            job.call = call
            if (job.cancelled) call.cancel()
            call.timeout().timeout(timeout.toLong() * 1000L, TimeUnit.MILLISECONDS)
            call.execute().use { response ->
                val body = response.body
                val buffer = Buffer()
                var over = false
                if (body != null) {
                    val source = body.source()
                    var total = 0L
                    while (true) {
                        val read = source.read(buffer, 64L * 1024L)
                        if (read == -1L) break
                        total += read
                        if (total > limits.bodyBytes) { over = true; break }
                    }
                }
                if (over) {
                    finish(job, JobState.FAILED, error = "response exceeds the relay body limit")
                } else {
                    val responseHeaders = RequestRules.filterResponseHeaders(
                        response.headers.toMultimap().mapValues { it.value.last() },
                    )
                    finish(job, JobState.COMPLETED, status = response.code, headers = responseHeaders, body = buffer.readUtf8())
                }
            }
        } catch (error: IOException) {
            if (job.cancelled) finish(job, JobState.CANCELLED, error = "cancelled")
            else finish(job, JobState.FAILED, error = error.message ?: "transport error")
        } catch (error: RuntimeException) {
            finish(job, JobState.FAILED, error = error.message ?: "relay failure")
        } finally {
            job.call = null
        }
    }

    private fun finish(
        job: Job,
        state: String,
        status: Int = 0,
        headers: Map<String, String> = emptyMap(),
        body: String? = null,
        error: String? = null,
    ) {
        synchronized(lock) {
            if (job.state != JobState.RUNNING) return
            job.state = state
            job.status = status
            job.headers = headers
            job.body = body
            job.error = error
            job.finishedAt = clock()
            job.retained = (body?.toByteArray(Charsets.UTF_8)?.size ?: 0).toLong() +
                (error?.toByteArray(Charsets.UTF_8)?.size ?: 0).toLong()
            retainedBytes += job.retained
            activeJobs = (activeJobs - 1).coerceAtLeast(0)
            pruneLocked()
        }
        onChanged()
    }

    private fun pruneLocked() {
        while (jobs.size >= limits.maxJobs || retainedBytes > limits.retainedBytes) {
            val victim = jobs.values.firstOrNull { it.state != JobState.RUNNING } ?: break
            removeLocked(victim.id)
        }
    }

    private fun removeLocked(id: String) {
        val job = jobs.remove(id) ?: return
        retainedBytes -= job.retained
        tombstones.addLast(id)
        tombstoneSet.add(id)
        while (tombstoneSet.size > limits.tombstones) {
            val oldest = tombstones.removeFirst()
            tombstoneSet.remove(oldest)
            knownFingerprints.remove(oldest)
        }
    }

    private fun view(job: Job): JobView {
        val completed = job.state == JobState.COMPLETED
        return JobView(
            id = job.id,
            state = job.state,
            error = job.error,
            status = job.status,
            headers = if (completed) job.headers else emptyMap(),
            body = if (completed) job.body else null,
        )
    }
}
