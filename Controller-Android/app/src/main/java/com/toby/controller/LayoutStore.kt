package com.toby.controller

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.ui.geometry.Offset

class LayoutStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("controller_layout", Context.MODE_PRIVATE)

    fun saveOffset(key: String, offset: Offset) {
        prefs.edit()
            .putFloat("${key}_x", offset.x)
            .putFloat("${key}_y", offset.y)
            .apply()
    }

    fun loadOffset(key: String): Offset? {
        if (!prefs.contains("${key}_x")) return null
        return Offset(
            prefs.getFloat("${key}_x", 0f),
            prefs.getFloat("${key}_y", 0f)
        )
    }

    fun saveScale(key: String, scale: Float) {
        prefs.edit().putFloat("${key}_scale", scale).apply()
    }

    fun loadScale(key: String): Float {
        return prefs.getFloat("${key}_scale", 1f)
    }

    fun clear() {
        val mode = getConnectionMode() // preserve setting across reset
        prefs.edit().clear().apply()
        setConnectionMode(mode)
    }

    fun setConnectionMode(mode: String) {
        prefs.edit().putString("connection_mode", mode).apply()
    }

    fun getConnectionMode(): String {
        return prefs.getString("connection_mode", "wifi") ?: "wifi"
    }

    fun setServerHost(host: String) {
        prefs.edit().putString("server_host", host).apply()
    }

    fun getServerHost(): String {
        return prefs.getString("server_host", "") ?: ""
    }

    fun getPairingCode(): String {
        var code = prefs.getString("pairing_code", null)
        if (code == null) {
            code = (1000..9999).random().toString()
            prefs.edit().putString("pairing_code", code).apply()
        }
        return code
    }

    fun regeneratePairingCode(): String {
        val code = (1000..9999).random().toString()
        prefs.edit().putString("pairing_code", code).apply()
        return code
    }
}
