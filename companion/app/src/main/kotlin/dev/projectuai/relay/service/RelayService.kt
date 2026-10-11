package dev.projectuai.relay.service

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import dev.projectuai.relay.MainActivity
import dev.projectuai.relay.R
import dev.projectuai.relay.RelayApp
import dev.projectuai.relay.RelayLog
import dev.projectuai.relay.data.RelaySettings
import dev.projectuai.relay.engine.JobEngine
import dev.projectuai.relay.server.RelayServer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.OkHttpClient
import java.util.UUID
import java.util.concurrent.TimeUnit

sealed interface RelayState {
    data object Stopped : RelayState
    data class Running(
        val port: Int,
        val instance: String,
        val paired: Boolean,
        val startedAt: Long,
    ) : RelayState
}

/**
 * The foreground service that owns the loopback server and the upstream connections.
 * It must not die under normal pressure: `specialUse` (no Android 15 six-hour cap),
 * START_STICKY, an exact-alarm watchdog and a wakelock held only while a job is in
 * flight. `userStopped` is the one flag watchdogs respect, so Kill stays down.
 */
class RelayService : Service() {
    private lateinit var settings: RelaySettings
    private lateinit var log: RelayLog
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var engine: JobEngine? = null
    private var server: RelayServer? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .callTimeout(0, TimeUnit.MILLISECONDS)
        .retryOnConnectionFailure(false)
        .build()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val app = application as RelayApp
        settings = app.settings
        log = app.log
        createChannel()
        ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(settings.port, false), foregroundType())
        _state.value = RelayState.Stopped
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_KILL -> {
                kill()
                return START_NOT_STICKY
            }
            else -> start()
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Swiping the app out of Recents is not a Kill.
        if (!settings.userStopped) {
            scheduleWatchdog(this, immediate = true)
            log.add("Task removed; the relay keeps running")
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        shutdown()
        scope.cancel()
        super.onDestroy()
    }

    private fun start() {
        settings.userStopped = false
        if (server != null) return
        val instance = UUID.randomUUID().toString()
        val createdEngine = JobEngine(instance, scope, client, onChanged = { updateNotification() })
        val createdServer = RelayServer(settings.port, instance, settings, createdEngine, log,
            onPaired = { token, place -> _token.value = token; _place.value = place })
        createdServer.start()
        engine = createdEngine
        server = createdServer
        _token.value = settings.token
        _state.value = RelayState.Running(settings.port, instance, settings.token.isNotEmpty(), System.currentTimeMillis())
        log.add("Relay service started on port ${settings.port}")
        scheduleWatchdog(this, immediate = false)
        updateNotification()
    }

    private fun kill() {
        settings.userStopped = true
        shutdown()
        log.add("Relay stopped by the user")
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun shutdown() {
        server?.stop()
        server = null
        engine?.cancelAll()
        engine = null
        cancelWatchdog(this)
        releaseWakeLock()
        _state.value = RelayState.Stopped
    }

    private fun updateNotification() {
        val engine = engine ?: return
        val working = engine.activeCount > 0
        if (working) acquireWakeLock() else releaseWakeLock()
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(NOTIFICATION_ID, buildNotification(settings.port, working))
    }

    private fun createChannel() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(CHANNEL_ID, getString(R.string.notification_channel), NotificationManager.IMPORTANCE_LOW)
        channel.description = getString(R.string.notification_channel_description)
        channel.setShowBadge(false)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(port: Int, working: Boolean) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(if (working) "Inference running on port $port" else "Listening on 127.0.0.1:$port")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(
                PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE),
            )
            .addAction(0, getString(R.string.notification_stop),
                PendingIntent.getService(this, 2, Intent(this, RelayService::class.java).setAction(ACTION_KILL),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val manager = getSystemService(PowerManager::class.java) ?: return
        wakeLock = manager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "uai-relay:job")
        wakeLock?.acquire(10 * 60_000L)
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun foregroundType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }

    companion object {
        const val ACTION_START = "dev.projectuai.relay.action.START"
        const val ACTION_KILL = "dev.projectuai.relay.action.KILL"
        private const val NOTIFICATION_ID = 41
        private const val CHANNEL_ID = "relay"
        private const val WATCHDOG_REQUEST = 7
        private const val WATCHDOG_INTERVAL_MS = 15 * 60 * 1000L

        private val _state = MutableStateFlow<RelayState>(RelayState.Stopped)
        val state: StateFlow<RelayState> = _state.asStateFlow()
        private val _token = MutableStateFlow("")
        val token: StateFlow<String> = _token.asStateFlow()
        private val _place = MutableStateFlow(0L)
        val place: StateFlow<Long> = _place.asStateFlow()

        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, RelayService::class.java).setAction(ACTION_START))
        }

        fun kill(context: Context) {
            context.startService(Intent(context, RelayService::class.java).setAction(ACTION_KILL))
        }

        fun scheduleWatchdog(context: Context, immediate: Boolean) {
            val alarm = context.getSystemService(AlarmManager::class.java) ?: return
            val pending = watchdogIntent(context)
            val at = System.currentTimeMillis() + if (immediate) 1_000L else WATCHDOG_INTERVAL_MS
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarm.canScheduleExactAlarms()) {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
            } else {
                alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
            }
        }

        fun cancelWatchdog(context: Context) {
            context.getSystemService(AlarmManager::class.java)?.cancel(watchdogIntent(context))
        }

        private fun watchdogIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(context, WATCHDOG_REQUEST, Intent(context, WatchdogReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}
