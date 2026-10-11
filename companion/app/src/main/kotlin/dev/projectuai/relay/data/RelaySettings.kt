package dev.projectuai.relay.data

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Persisted relay state. The token is stable across restarts so a killed-and-restarted
 * service never forces a re-pair; `userStopped` is the one flag watchdogs must respect.
 */
interface RelaySettings {
    var port: Int
    var token: String
    var userStopped: Boolean
    var autoStart: Boolean
    fun rotateToken() { token = "" }
}

class PrefsSettings(context: Context) : RelaySettings {
    private val prefs = EncryptedSharedPreferences.create(
        context,
        "relay",
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    override var port: Int
        get() = prefs.getInt("port", DEFAULT_PORT)
        set(value) = prefs.edit().putInt("port", value.coerceIn(1, 65535)).apply()

    override var token: String
        get() = prefs.getString("token", "") ?: ""
        set(value) = prefs.edit().putString("token", value).apply()

    override var userStopped: Boolean
        get() = prefs.getBoolean("userStopped", false)
        set(value) = prefs.edit().putBoolean("userStopped", value).apply()

    override var autoStart: Boolean
        get() = prefs.getBoolean("autoStart", true)
        set(value) = prefs.edit().putBoolean("autoStart", value).apply()

    companion object {
        const val DEFAULT_PORT = 8790
    }
}

/** JVM tests and previews: no Android dependency. */
class MemorySettings(
    override var port: Int = 8790,
    override var token: String = "",
    override var userStopped: Boolean = false,
    override var autoStart: Boolean = true,
) : RelaySettings
