package com.toby.controller

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * Visual theme for the on-screen controller. Everything the controls draw
 * (fills, borders, face-button colours, LED light bar) comes from here, so a
 * theme can restyle the whole pad without touching layout.
 */
data class ControllerTheme(
    val id: String,
    val label: String,
    val accent: Color,
    val buttonFill: Color,
    val buttonFillPressed: Color,
    val border: Color,
    val borderPressed: Color,
    val text: Color,
    val textDim: Color,
    val triangle: Color,
    val circle: Color,
    val cross: Color,
    val square: Color,
    val faceGlyphOnly: Boolean,   // PS5 pads tint only the glyph, not the ring
    val stickBase: Color,
    val stickThumb: Color,
    val ledColor: Color?,         // light bar beside the touchpad; null = none
    val showMute: Boolean,        // DualSense has a mute button under the touchpad
)

object Themes {
    val dualsense = ControllerTheme(
        id = "dualsense",
        label = "DualSense",
        accent = Color(0xFF2E6FF2),
        buttonFill = Color(0xFF1C1F26),
        buttonFillPressed = Color(0xFF3A4250),
        border = Color(0xFF6E7683).copy(0.55f),
        borderPressed = Color(0xFFAEB6C2),
        text = Color(0xFFE8ECF2),
        textDim = Color(0xFF9AA3B0),
        triangle = Color(0xFF4ED6B0),
        circle = Color(0xFFF2545B),
        cross = Color(0xFF5B8DEF),
        square = Color(0xFFE888C4),
        faceGlyphOnly = true,
        stickBase = Color(0xFF15181E),
        stickThumb = Color(0xFF2A2F38),
        ledColor = Color(0xFF2E6FF2),
        showMute = true,
    )

    val minimal = ControllerTheme(
        id = "minimal",
        label = "Minimal",
        accent = Color(0xFF4488FF),
        buttonFill = Color.White.copy(0.06f),
        buttonFillPressed = Color.White.copy(0.2f),
        border = Color.White.copy(0.12f),
        borderPressed = Color.White.copy(0.35f),
        text = Color.White,
        textDim = Color.Gray,
        triangle = Color(0xFF00CC66),
        circle = Color(0xFFFF4444),
        cross = Color(0xFF4488FF),
        square = Color(0xFFFF77AA),
        faceGlyphOnly = false,
        stickBase = Color(0xFF0D0D0D),
        stickThumb = Color.White.copy(0.15f),
        ledColor = null,
        showMute = false,
    )

    val neon = ControllerTheme(
        id = "neon",
        label = "Neon",
        accent = Color(0xFF00E5FF),
        buttonFill = Color(0xFF0A0E1A),
        buttonFillPressed = Color(0xFF00E5FF).copy(0.35f),
        border = Color(0xFF00E5FF).copy(0.6f),
        borderPressed = Color(0xFF00E5FF),
        text = Color(0xFFE0FBFF),
        textDim = Color(0xFF00E5FF).copy(0.75f),
        triangle = Color(0xFF39FF88),
        circle = Color(0xFFFF3D71),
        cross = Color(0xFF00E5FF),
        square = Color(0xFFC08AFF),
        faceGlyphOnly = false,
        stickBase = Color(0xFF070B14),
        stickThumb = Color(0xFF00E5FF).copy(0.25f),
        ledColor = Color(0xFF00E5FF),
        showMute = false,
    )

    val stealth = ControllerTheme(
        id = "stealth",
        label = "Stealth",
        accent = Color(0xFFBFC4CC),
        buttonFill = Color.White.copy(0.03f),
        buttonFillPressed = Color.White.copy(0.14f),
        border = Color.White.copy(0.18f),
        borderPressed = Color.White.copy(0.5f),
        text = Color(0xFFE6E8EC),
        textDim = Color(0xFF7C828C),
        triangle = Color(0xFFBFC4CC),
        circle = Color(0xFFBFC4CC),
        cross = Color(0xFFBFC4CC),
        square = Color(0xFFBFC4CC),
        faceGlyphOnly = false,
        stickBase = Color(0xFF0B0B0C),
        stickThumb = Color.White.copy(0.1f),
        ledColor = null,
        showMute = false,
    )

    val all = listOf(dualsense, minimal, neon, stealth)

    fun byId(id: String): ControllerTheme = all.firstOrNull { it.id == id } ?: dualsense
}

/** Built-in backdrops. "custom" means the user picked their own image. */
data class Wallpaper(val id: String, val label: String, val brush: Brush?)

object Wallpapers {
    val all = listOf(
        Wallpaper("black", "Black", null),
        Wallpaper("slate", "Slate", Brush.verticalGradient(listOf(Color(0xFF11141A), Color(0xFF05060A)))),
        Wallpaper("midnight", "Midnight", Brush.verticalGradient(listOf(Color(0xFF0A1330), Color(0xFF03050D)))),
        Wallpaper("ember", "Ember", Brush.verticalGradient(listOf(Color(0xFF2A0F12), Color(0xFF070405)))),
        Wallpaper("forest", "Forest", Brush.verticalGradient(listOf(Color(0xFF06231C), Color(0xFF03090A)))),
    )

    fun byId(id: String): Wallpaper = all.firstOrNull { it.id == id } ?: all[0]
}

val LocalControllerTheme = staticCompositionLocalOf { Themes.dualsense }
