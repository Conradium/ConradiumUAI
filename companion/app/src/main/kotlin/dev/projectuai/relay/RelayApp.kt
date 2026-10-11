package dev.projectuai.relay

import android.app.Application
import dev.projectuai.relay.data.PrefsSettings
import dev.projectuai.relay.data.RelaySettings

class RelayApp : Application() {
    lateinit var settings: RelaySettings
        private set
    val log = RelayLog()

    override fun onCreate() {
        super.onCreate()
        settings = PrefsSettings(this)
    }
}
