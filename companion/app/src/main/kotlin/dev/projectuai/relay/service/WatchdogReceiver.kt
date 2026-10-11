package dev.projectuai.relay.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dev.projectuai.relay.RelayApp

/**
 * An exact alarm is a documented exemption from the Android 12+ background
 * foreground-service start restriction, which is why this is the reliable
 * resurrection path rather than boot alone. It returns immediately after a Kill.
 */
class WatchdogReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val settings = (context.applicationContext as RelayApp).settings
        if (settings.userStopped) return
        if (RelayService.state.value is RelayState.Running) {
            RelayService.scheduleWatchdog(context, immediate = false)
        } else {
            RelayService.start(context)
        }
    }
}
