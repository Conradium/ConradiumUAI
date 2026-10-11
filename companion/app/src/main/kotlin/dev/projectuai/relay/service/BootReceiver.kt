package dev.projectuai.relay.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dev.projectuai.relay.RelayApp

/** Resurrects a relay that was running when the device rebooted or the app updated. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val settings = (context.applicationContext as RelayApp).settings
        if (settings.autoStart && !settings.userStopped) RelayService.start(context)
    }
}
