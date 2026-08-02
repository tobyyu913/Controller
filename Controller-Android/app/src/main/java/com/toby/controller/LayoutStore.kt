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

    /** Remove only saved element positions/scales, keeping connection settings. */
    fun clearLayout() {
        val editor = prefs.edit()
        prefs.all.keys
            .filter { it.endsWith("_x") || it.endsWith("_y") || it.endsWith("_scale") }
            .forEach { editor.remove(it) }
        editor.apply()
    }

    fun getLayoutVersion(): Int = prefs.getInt("layout_version", 1)

    fun setLayoutVersion(v: Int) {
        prefs.edit().putInt("layout_version", v).apply()
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

    /** L3/R3 style: "off", "button" (inner arc) or "ring" (full ring + push-through). */
    fun setStickClickMode(mode: String) {
        prefs.edit().putString("stick_click_mode", mode).apply()
    }

    fun getStickClickMode(): String {
        prefs.getString("stick_click_mode", null)?.let { return it }
        // Migrate the old on/off switch
        return if (prefs.getBoolean("stick_click_enabled", true)) "ring" else "off"
    }

    // -- Appearance --

    fun setTheme(id: String) = prefs.edit().putString("theme", id).apply()
    fun getTheme(): String = prefs.getString("theme", "dualsense") ?: "dualsense"

    fun setWallpaper(id: String) = prefs.edit().putString("wallpaper", id).apply()
    // "theme" = follow the theme's own body colour (white for DualSense)
    fun getWallpaper(): String = prefs.getString("wallpaper", "theme") ?: "theme"

    /** Content URI of a user-picked backdrop image, or "" for none. */
    fun setWallpaperUri(uri: String) = prefs.edit().putString("wallpaper_uri", uri).apply()
    fun getWallpaperUri(): String = prefs.getString("wallpaper_uri", "") ?: ""

    // -- Gameplay --

    fun setDeadzoneEnabled(v: Boolean) = prefs.edit().putBoolean("dz_on", v).apply()
    fun getDeadzoneEnabled(): Boolean = prefs.getBoolean("dz_on", true)
    fun setDeadzone(v: Float) = prefs.edit().putFloat("dz", v).apply()
    fun getDeadzone(): Float = prefs.getFloat("dz", 0.08f)

    fun setGyroEnabled(v: Boolean) = prefs.edit().putBoolean("gyro_on", v).apply()
    fun getGyroEnabled(): Boolean = prefs.getBoolean("gyro_on", false)
    fun setGyroSens(v: Float) = prefs.edit().putFloat("gyro_sens", v).apply()
    fun getGyroSens(): Float = prefs.getFloat("gyro_sens", 0.5f)

    fun setTurboEnabled(v: Boolean) = prefs.edit().putBoolean("turbo_on", v).apply()
    fun getTurboEnabled(): Boolean = prefs.getBoolean("turbo_on", false)
    fun setTurboRate(v: Int) = prefs.edit().putInt("turbo_rate", v).apply()
    fun getTurboRate(): Int = prefs.getInt("turbo_rate", 12)   // presses per second

    fun setAnalogTriggers(v: Boolean) = prefs.edit().putBoolean("analog_trig", v).apply()
    fun getAnalogTriggers(): Boolean = prefs.getBoolean("analog_trig", true)

    fun setRumbleEnabled(v: Boolean) = prefs.edit().putBoolean("rumble_on", v).apply()
    fun getRumbleEnabled(): Boolean = prefs.getBoolean("rumble_on", true)

    fun setLastBtHost(address: String) {
        prefs.edit().putString("last_bt_host", address).apply()
    }

    fun getLastBtHost(): String {
        return prefs.getString("last_bt_host", "") ?: ""
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
