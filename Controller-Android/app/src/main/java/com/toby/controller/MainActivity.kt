package com.toby.controller

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.compose.ui.platform.LocalView
import kotlin.math.*

// Haptic feedback helper
fun vibrateLight(view: android.view.View) {
    view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK)
}

fun vibrateHeavy(view: android.view.View) {
    view.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY)
}

class MainActivity : ComponentActivity() {
    private var sender: ControllerSender? = null
    private var btController: BluetoothHidController? = null
    private var blePeripheral: BleControllerPeripheral? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Request BT permissions on Android 12+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            requestPermissions(
                arrayOf(
                    android.Manifest.permission.BLUETOOTH_CONNECT,
                    android.Manifest.permission.BLUETOOTH_ADVERTISE,
                ), 1
            )
        }

        val layoutStore = LayoutStore(this)
        // v6: DualSense proportions (touchpad, face buttons, d-pad) — reset once
        if (layoutStore.getLayoutVersion() < 7) {
            layoutStore.clearLayout()
            layoutStore.setLayoutVersion(7)
        }
        sender = ControllerSender(this)
        btController = BluetoothHidController(this, layoutStore)
        blePeripheral = BleControllerPeripheral(this)

        val mode = layoutStore.getConnectionMode()
        when (mode) {
            "bluetooth" -> blePeripheral?.start()
            "gamepad" -> btController?.start()
            else -> {
                sender?.mode = mode
                sender?.serverHost = layoutStore.getServerHost()
                sender?.start()
            }
        }

        setContent {
            ControllerScreen(sender!!, btController!!, blePeripheral!!, layoutStore, this)
        }
    }

    override fun onDestroy() {
        sender?.stop()
        btController?.stop()
        blePeripheral?.stop()
        super.onDestroy()
    }
}

// -- State --

class ControllerState {
    val pressedButtons = mutableStateListOf<String>()
    var leftStick by mutableStateOf(Offset.Zero)
    var rightStick by mutableStateOf(Offset.Zero)
    var stickRadiusPx: Float = 1f

    // Fires on every input mutation so sends happen immediately,
    // not a UI frame later via recomposition
    var onInput: (() -> Unit)? = null

    fun press(button: String) {
        if (button !in pressedButtons) pressedButtons.add(button)
        onInput?.invoke()
    }
    fun release(button: String) {
        pressedButtons.remove(button)
        onInput?.invoke()
    }
    fun isPressed(button: String) = button in pressedButtons

    fun setLeftStick(offset: Offset, radius: Float) {
        leftStick = offset
        stickRadiusPx = radius
        onInput?.invoke()
    }
    fun setRightStick(offset: Offset, radius: Float) {
        rightStick = offset
        stickRadiusPx = radius
        onInput?.invoke()
    }

    fun toMessage() = ControllerMessage(
        pressedButtons = pressedButtons.toList(),
        leftStickX = (leftStick.x / stickRadiusPx).toDouble().coerceIn(-1.0, 1.0),
        leftStickY = (leftStick.y / stickRadiusPx).toDouble().coerceIn(-1.0, 1.0),
        rightStickX = (rightStick.x / stickRadiusPx).toDouble().coerceIn(-1.0, 1.0),
        rightStickY = (rightStick.y / stickRadiusPx).toDouble().coerceIn(-1.0, 1.0),
    )
}

// -- Draggable wrapper for edit mode --

@Composable
fun DraggableElement(
    key: String,
    layoutStore: LayoutStore,
    editing: Boolean,
    defaultOffset: Offset,
    content: @Composable () -> Unit,
) {
    // Keyed on defaultOffset: the activity can compose one frame in portrait
    // before the landscape lock applies, and an unkeyed remember would freeze
    // every control at those portrait coordinates for the whole session.
    var pos by remember(key, defaultOffset) {
        mutableStateOf(layoutStore.loadOffset(key) ?: defaultOffset)
    }

    Box(
        modifier = Modifier
            .offset { IntOffset(pos.x.roundToInt(), pos.y.roundToInt()) }
            .then(
                if (editing) {
                    Modifier
                        .border(1.5.dp, Color(0xFF4488FF).copy(0.6f), RoundedCornerShape(6.dp))
                        .pointerInput(key) {
                            detectDragGestures { change, dragAmount ->
                                change.consume()
                                pos += dragAmount
                                layoutStore.saveOffset(key, pos)
                            }
                        }
                } else Modifier
            )
    ) {
        content()
    }
}

// -- Default positions (fractions of screen) --

data class DefaultPositions(
    val l2: Offset,
    val l1: Offset,
    val r1: Offset,
    val r2: Offset,
    val dpad: Offset,
    val faceButtons: Offset,
    val leftStick: Offset,
    val rightStick: Offset,
    val create: Offset,
    val touchpad: Offset,
    val options: Offset,
    val ps: Offset,
    val mute: Offset,
)

fun computeDefaults(screenW: Float, screenH: Float, d: Float): DefaultPositions {
    // Element sizes in px (must match the composables' dp sizes), d = px per dp
    val trigW = 60f * d; val trigH = 34f * d
    val bumpW = 60f * d; val bumpH = 28f * d
    val dpadS = 126f * d
    val faceS = 132f * d
    val stickS = 174f * d  // stick (130) + 22dp band each side — constant in every stick-click mode
    val padW = 214f * d; val padH = 96f * d
    val pillW = 13f * d
    val psS = 34f * d
    val m = 12f * d          // screen edge margin
    val gap = 8f * d

    // Real DualSense geometry, scaled to the screen: shoulders in the corners,
    // D-Pad / face buttons outboard, symmetric sticks low and toward the center,
    // big touchpad top-center with Create/Options flanking it, PS between the sticks.
    // Shoulders follow the index finger curling over the top corner: L2/R2 sit at
    // the very corner (pressed with the middle of the finger), L1/R1 sit lower and
    // further inward where the fingertip naturally lands.
    val trigInset = 34f * d  // L2/R2 pulled inward from the corner (long fingers)
    val tipInset = 64f * d   // fingertip lands further inward still...
    val tipDrop = trigH + 14f * d  // ...and below the trigger row
    return DefaultPositions(
        l2 = Offset(m + trigInset, m),
        l1 = Offset(m + tipInset, m + tipDrop),
        r1 = Offset(screenW - m - tipInset - bumpW, m + tipDrop),
        r2 = Offset(screenW - m - trigInset - trigW, m),
        dpad = Offset(max(m, 0.16f * screenW - dpadS / 2), 0.44f * screenH - dpadS / 2),
        faceButtons = Offset(min(screenW - m - faceS, 0.84f * screenW - faceS / 2), 0.44f * screenH - faceS / 2),
        leftStick = Offset(0.35f * screenW - stickS / 2, min(screenH - m - stickS, 0.74f * screenH - stickS / 2)),
        rightStick = Offset(0.65f * screenW - stickS / 2, min(screenH - m - stickS, 0.74f * screenH - stickS / 2)),
        create = Offset(screenW / 2 - padW / 2 - 20f * d - pillW, 0.14f * screenH + padH / 2 - 26f * d),
        touchpad = Offset(screenW / 2 - padW / 2, 0.14f * screenH),
        options = Offset(screenW / 2 + padW / 2 + 20f * d, 0.14f * screenH + padH / 2 - 26f * d),
        ps = Offset(screenW / 2 - psS / 2, 0.66f * screenH - psS / 2),
        // DualSense mute button: just under the touchpad
        mute = Offset(screenW / 2 - 14f * d, 0.14f * screenH + padH + 6f * d),
    )
}

// -- Main Screen --

@Composable
fun ControllerScreen(sender: ControllerSender, btController: BluetoothHidController, blePeripheral: BleControllerPeripheral, layoutStore: LayoutStore, activity: ComponentActivity) {
    val state = remember { ControllerState() }
    var isConnected by remember { mutableStateOf(false) }
    var isConnecting by remember { mutableStateOf(false) }
    var connectedName by remember { mutableStateOf("") }
    var editing by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var connectionMode by remember { mutableStateOf(layoutStore.getConnectionMode()) }
    var serverHost by remember { mutableStateOf(layoutStore.getServerHost()) }
    var layoutTick by remember { mutableStateOf(0) }
    var stickClick by remember { mutableStateOf(layoutStore.getStickClickMode()) }
    var themeId by remember { mutableStateOf(layoutStore.getTheme()) }
    var wallpaperId by remember { mutableStateOf(layoutStore.getWallpaper()) }
    var wallpaperUri by remember { mutableStateOf(layoutStore.getWallpaperUri()) }
    val theme = remember(themeId) { Themes.byId(themeId) }

    // Custom backdrop picker (OpenDocument so the grant survives restarts)
    val pickImage = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            try {
                activity.contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: Exception) {}
            wallpaperUri = uri.toString()
            layoutStore.setWallpaperUri(wallpaperUri)
            wallpaperId = "custom"
            layoutStore.setWallpaper("custom")
        }
    }

    // Sync state from whichever controller is active
    fun syncState() {
        when (connectionMode) {
            "bluetooth" -> {
                isConnected = blePeripheral.isConnected
                isConnecting = blePeripheral.isAdvertising && !blePeripheral.isConnected
                connectedName = blePeripheral.connectedDeviceName
            }
            "gamepad" -> {
                isConnected = btController.isConnected
                isConnecting = btController.isRegistered && !btController.isConnected
                connectedName = btController.connectedDeviceName
            }
            else -> {
                isConnected = sender.isConnected
                isConnecting = sender.isConnecting
                connectedName = sender.connectedServerName
            }
        }
    }

    LaunchedEffect(Unit) {
        sender.onStateChanged = { syncState() }
        blePeripheral.onStateChanged = { syncState() }
        btController.onStateChanged = { syncState() }
        kotlinx.coroutines.delay(500)
        syncState()
    }

    LaunchedEffect(connectionMode) {
        sender.onStateChanged = { syncState() }
        blePeripheral.onStateChanged = { syncState() }
        btController.onStateChanged = { syncState() }
        syncState()
    }

    // Send immediately on every input mutation (no recomposition delay)
    SideEffect {
        state.onInput = {
            if (!editing && !showSettings) {
                val msg = state.toMessage()
                when (connectionMode) {
                    "bluetooth" -> blePeripheral.send(msg)
                    "gamepad" -> btController.send(msg)
                    else -> sender.send(msg)
                }
            }
        }
    }

    val config = LocalConfiguration.current
    val density = LocalDensity.current
    val screenW = with(density) { config.screenWidthDp.dp.toPx() }
    val screenH = with(density) { config.screenHeightDp.dp.toPx() }
    val defaults = remember(screenW, screenH, density) { computeDefaults(screenW, screenH, density.density) }

    CompositionLocalProvider(
        LocalControllerTheme provides theme,
        LocalConnState provides ConnState(isConnected, isConnecting),
    ) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(theme.bodyColor)
            .systemBarsPadding()
    ) {
        // Backdrop: user image, built-in gradient, or plain black
        if (wallpaperId == "custom" && wallpaperUri.isNotEmpty()) {
            val bmp = remember(wallpaperUri) { loadBitmap(activity, wallpaperUri) }
            if (bmp != null) {
                Image(
                    bitmap = bmp,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.matchParentSize()
                )
            }
        } else {
            Wallpapers.byId(wallpaperId).brush?.let { brush ->
                Box(modifier = Modifier.matchParentSize().background(brush))
            }
        }

        // Connection status
        Row(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(
                        if (isConnected) Color.Green
                        else if (isConnecting) Color(0xFFFFA500)
                        else Color.Gray
                    )
            )
            Text(
                text = if (editing) "EDIT MODE — drag to reposition"
                    else if (isConnected) "Connected to ${connectedName}" + if (connectionMode == "bluetooth" || connectionMode == "gamepad") " (BT)" else ""
                    else if (connectionMode == "bluetooth") blePeripheral.statusMessage.ifEmpty { "Bluetooth — starting..." }
                    else if (connectionMode == "gamepad") btController.statusMessage.ifEmpty { "Gamepad — starting..." }
                    else if (isConnecting) "Searching for server... (${connectionMode})"
                    else "Offline",
                color = if (editing) theme.accent else theme.onBody,
                fontSize = 10.sp
            )
        }

        // Settings button (bottom right, out of the way of R2)
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .zIndex(10f)
                .padding(bottom = 6.dp, end = 8.dp)
                .size(32.dp)
                .clip(CircleShape)
                .background(if (showSettings || editing) theme.accent.copy(0.3f) else theme.onBody.copy(0.12f))
                .pointerInput("settings") {
                    detectTapGestures { showSettings = !showSettings; if (showSettings) editing = false }
                },
            contentAlignment = Alignment.Center
        ) {
            Text("\u2699", color = if (showSettings || editing) theme.accent else theme.onBody, fontSize = 16.sp)
        }

        // Done button when editing
        if (editing) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .zIndex(10f)
                    .padding(bottom = 8.dp, end = 48.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color(0xFF4488FF).copy(0.3f))
                    .pointerInput("done") {
                        detectTapGestures { editing = false }
                    }
                    .padding(horizontal = 10.dp, vertical = 6.dp),
                contentAlignment = Alignment.Center
            ) {
                Text("Done", color = Color(0xFF4488FF), fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
        }

        // (Settings overlay moved to end of Box for correct Z-order)

        // All controls absolutely positioned (key() forces re-read of saved positions on reset)
        val inputDisabled = editing || showSettings
        key(layoutTick) {
        DraggableElement("l2", layoutStore, editing, defaults.l2) {
            TriggerButton("L2", state, inputDisabled)
        }
        DraggableElement("l1", layoutStore, editing, defaults.l1) {
            BumperButton("L1", state, inputDisabled)
        }
        DraggableElement("r1", layoutStore, editing, defaults.r1) {
            BumperButton("R1", state, inputDisabled)
        }
        DraggableElement("r2", layoutStore, editing, defaults.r2) {
            TriggerButton("R2", state, inputDisabled)
        }
        DraggableElement("dpad", layoutStore, editing, defaults.dpad) {
            DPad(state, inputDisabled)
        }
        DraggableElement("face", layoutStore, editing, defaults.faceButtons) {
            FaceButtons(state, inputDisabled)
        }
        DraggableElement("lstick", layoutStore, editing, defaults.leftStick) {
            AnalogStick(
                offset = state.leftStick,
                onOffsetChange = { offset, radius -> state.setLeftStick(offset, radius) },
                editing = inputDisabled,
                clickButton = if (stickClick != "off") "L3" else null,
                clickStyle = stickClick,
                state = state,
            )
        }
        DraggableElement("rstick", layoutStore, editing, defaults.rightStick) {
            AnalogStick(
                offset = state.rightStick,
                onOffsetChange = { offset, radius -> state.setRightStick(offset, radius) },
                editing = inputDisabled,
                clickButton = if (stickClick != "off") "R3" else null,
                clickStyle = stickClick,
                state = state,
            )
        }
        DraggableElement("create", layoutStore, editing, defaults.create) {
            SystemGlyphButton("Create", state, inputDisabled, lean = -10f)
        }
        DraggableElement("touchpad", layoutStore, editing, defaults.touchpad) {
            Touchpad(state, inputDisabled)
        }
        DraggableElement("options", layoutStore, editing, defaults.options) {
            SystemGlyphButton("Options", state, inputDisabled, lean = 10f)
        }
        DraggableElement("ps", layoutStore, editing, defaults.ps) {
            PSButton(state, inputDisabled)
        }
        if (theme.showMute) {
            DraggableElement("mute", layoutStore, editing, defaults.mute) {
                MuteButton(state, inputDisabled)
            }
        }
        }

        // Settings overlay (must be LAST so it draws on top of controls)
        if (showSettings) {
            SettingsOverlay(
                connectionMode = connectionMode,
                serverHost = serverHost,
                onConnectionModeChange = { mode ->
                    // Stop current mode
                    when (connectionMode) {
                        "bluetooth" -> blePeripheral.stop()
                        "gamepad" -> btController.stop()
                        else -> sender.stop()
                    }
                    connectionMode = mode
                    layoutStore.setConnectionMode(mode)
                    // Start new mode
                    when (mode) {
                        "bluetooth" -> blePeripheral.start()
                        "gamepad" -> btController.start()
                        else -> {
                            sender.mode = mode
                            sender.serverHost = layoutStore.getServerHost()
                            sender.start()
                        }
                    }
                    syncState()
                },
                onServerHostChange = { host ->
                    serverHost = host
                    layoutStore.setServerHost(host)
                },
                onConnect = {
                    sender.connectDirect(serverHost)
                    showSettings = false
                },
                onEditLayout = {
                    showSettings = false
                    editing = true
                },
                onResetLayout = { layoutStore.clearLayout(); layoutTick++ },
                stickClick = stickClick,
                onStickClickChange = { mode ->
                    stickClick = mode
                    layoutStore.setStickClickMode(mode)
                },
                onClose = { showSettings = false },
                btController = btController,
                onMakeDiscoverable = {
                    val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).apply {
                        putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300)
                    }
                    try { activity.startActivity(intent) } catch (_: Exception) {}
                },
                themeId = themeId,
                onThemeChange = { id -> themeId = id; layoutStore.setTheme(id) },
                wallpaperId = wallpaperId,
                onWallpaperChange = { id -> wallpaperId = id; layoutStore.setWallpaper(id) },
                onPickWallpaper = { pickImage.launch(arrayOf("image/*")) },
            )
        }
    }
    }
}

/** Load a user-picked backdrop from a persisted content URI. */
fun loadBitmap(context: android.content.Context, uriString: String): androidx.compose.ui.graphics.ImageBitmap? {
    return try {
        context.contentResolver.openInputStream(android.net.Uri.parse(uriString)).use { input ->
            android.graphics.BitmapFactory.decodeStream(input)?.asImageBitmap()
        }
    } catch (_: Exception) { null }
}

// -- D-Pad --

@Composable
fun DPad(state: ControllerState, editing: Boolean = false) {
    val btnSize = 42.dp
    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(btnSize * 3)) {
        Box(
            modifier = Modifier
                .size(20.dp)
                .clip(CircleShape)
                .background(LocalControllerTheme.current.buttonFill)
        )
        Box(modifier = Modifier.offset(y = -btnSize)) {
            DPadBtn("\u25B2", "DPadUp", state, editing)
        }
        Box(modifier = Modifier.offset(y = btnSize)) {
            DPadBtn("\u25BC", "DPadDown", state, editing)
        }
        Box(modifier = Modifier.offset(x = -btnSize)) {
            DPadBtn("\u25C0", "DPadLeft", state, editing)
        }
        Box(modifier = Modifier.offset(x = btnSize)) {
            DPadBtn("\u25B6", "DPadRight", state, editing)
        }
    }
}

@Composable
fun DPadBtn(symbol: String, name: String, state: ControllerState, editing: Boolean) {
    val pressed = !editing && state.isPressed(name)
    val view = LocalView.current
    val t = LocalControllerTheme.current
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(40.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (pressed) t.buttonFillPressed else t.buttonFill)
            .then(
                if (!editing) Modifier.pointerInput(name) {
                    detectTapGestures(
                        onPress = {
                            state.press(name)
                            vibrateLight(view)
                            tryAwaitRelease()
                            state.release(name)
                        }
                    )
                } else Modifier
            )
    ) {
        Text(symbol, color = if (pressed) t.text else t.textDim, fontSize = 16.sp)
    }
}

// -- Face Buttons --

@Composable
fun FaceButtons(state: ControllerState, editing: Boolean = false) {
    val spacing = 44.dp
    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(spacing * 3)) {
        Box(modifier = Modifier.offset(y = -spacing)) {
            FaceBtn("\u25B3", "Triangle", Color(0xFF00CC66), state, editing)
        }
        Box(modifier = Modifier.offset(x = spacing)) {
            FaceBtn("\u25CB", "Circle", Color(0xFFFF4444), state, editing)
        }
        Box(modifier = Modifier.offset(y = spacing)) {
            FaceBtn("\u2715", "Cross", Color(0xFF4488FF), state, editing)
        }
        Box(modifier = Modifier.offset(x = -spacing)) {
            FaceBtn("\u25A1", "Square", Color(0xFFFF77AA), state, editing)
        }
    }
}

@Composable
fun FaceBtn(symbol: String, name: String, color: Color, state: ControllerState, editing: Boolean) {
    val pressed = !editing && state.isPressed(name)
    val view = LocalView.current
    val t = LocalControllerTheme.current
    val ring = if (t.faceGlyphOnly) t.border else color
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(40.dp)
            .clip(CircleShape)
            .background(if (pressed) color.copy(0.4f) else t.buttonFill)
            .border(2.dp, if (pressed) (if (t.faceGlyphOnly) t.borderPressed else color) else ring.copy(if (t.faceGlyphOnly) 1f else 0.5f), CircleShape)
            .then(
                if (!editing) Modifier.pointerInput(name) {
                    detectTapGestures(
                        onPress = {
                            state.press(name)
                            vibrateLight(view)
                            tryAwaitRelease()
                            state.release(name)
                        }
                    )
                } else Modifier
            )
    ) {
        Text(symbol, color = if (pressed) t.text else color, fontSize = 16.sp, fontWeight = FontWeight.Bold)
    }
}

// -- Analog Stick --

@Composable
fun AnalogStick(
    offset: Offset,
    onOffsetChange: (Offset, Float) -> Unit,
    editing: Boolean = false,
    clickButton: String? = null,   // "L3"/"R3", or null when stick-click is off
    clickStyle: String = "ring",   // "ring" (full ring + push-through) or "button" (inner arc)
    state: ControllerState? = null,
) {
    val density = LocalDensity.current
    val baseSizeDp = 130.dp
    val ringWidthDp = 22.dp
    // Footprint is CONSTANT across off/button/ring so the stick's centre never
    // shifts when the mode changes (computeDefaults positions it by this size).
    val bandDp = ringWidthDp
    val outerSizeDp = baseSizeDp + bandDp * 2
    val isRing = clickStyle == "ring"
    // The arc button sits on the inner side (toward the screen centre)
    val innerIsRight = clickButton == "L3"
    val thumbSizeDp = 56.dp
    val thumbVisualOffset = with(density) { ((baseSizeDp - thumbSizeDp) / 2).toPx() }
    val view = LocalView.current
    val t = LocalControllerTheme.current
    var wasAtEdge by remember { mutableStateOf(false) }

    // Push-through click: dragging past the stick's edge presses L3/R3,
    // pulling back inside releases it (with hysteresis so it doesn't chatter)
    var ringEngaged by remember { mutableStateOf(false) }
    val pressRadius = with(density) { (baseSizeDp / 2).toPx() }
    val releaseRadius = with(density) { (baseSizeDp / 2 - 10.dp).toPx() }

    val ringPressed = !editing && clickButton != null && state?.isPressed(clickButton) == true

    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(outerSizeDp)) {
        // L3/R3 ring — a touch screen can't feel a stick press-in, so the ring
        // around the stick stands in for clicking it
        if (clickButton != null && isRing) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .clip(CircleShape)
                    .background(if (ringPressed) t.accent.copy(0.3f) else t.buttonFill)
                    .border(1.dp, if (ringPressed) t.accent.copy(0.8f) else t.border, CircleShape)
                    .then(
                        if (!editing && state != null) {
                            Modifier.pointerInput(clickButton) {
                                detectTapGestures(
                                    onPress = {
                                        state.press(clickButton)
                                        vibrateHeavy(view)
                                        tryAwaitRelease()
                                        state.release(clickButton)
                                    }
                                )
                            }
                        } else Modifier
                    )
            )
            Text(
                clickButton,
                color = if (ringPressed) t.text else t.textDim,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 3.dp)
            )
        } else if (clickButton != null) {
            // Curved button hugging the stick on its inner side
            val arcColor = if (ringPressed) t.accent else t.border
            val strokePx = with(density) { 15.dp.toPx() }
            Canvas(modifier = Modifier.matchParentSize()) {
                val r = (size.minDimension - strokePx) / 2f
                drawArc(
                    color = arcColor,
                    startAngle = if (innerIsRight) -34f else 146f,
                    sweepAngle = 68f,
                    useCenter = false,
                    topLeft = Offset(size.width / 2f - r, size.height / 2f - r),
                    size = androidx.compose.ui.geometry.Size(r * 2, r * 2),
                    style = androidx.compose.ui.graphics.drawscope.Stroke(
                        width = strokePx,
                        cap = androidx.compose.ui.graphics.StrokeCap.Round
                    )
                )
            }
            // Hit area confined to the arc's side so it can't swallow stray taps
            Box(
                modifier = Modifier
                    .align(if (innerIsRight) Alignment.CenterEnd else Alignment.CenterStart)
                    .width(bandDp + 12.dp)
                    .height(baseSizeDp * 0.62f)
                    .then(
                        if (!editing && state != null) {
                            Modifier.pointerInput(clickButton) {
                                detectTapGestures(
                                    onPress = {
                                        state.press(clickButton)
                                        vibrateHeavy(view)
                                        tryAwaitRelease()
                                        state.release(clickButton)
                                    }
                                )
                            }
                        } else Modifier
                    )
            )
        }

        // Stick base (drawn on top: its touches never reach the ring)
        Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(baseSizeDp)
            .clip(CircleShape)
            .background(t.stickBase)
            .border(1.dp, t.border, CircleShape)
            .then(
                if (!editing) Modifier.pointerInput(Unit) {
                    detectDragGestures(
                        onDragStart = {
                            // Android batches touch samples to the display refresh by
                            // default, so thumb motion arrives in frame-sized clumps.
                            // Opt out for this gesture to get raw, full-rate samples.
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                try {
                                    view.requestUnbufferedDispatch(android.view.InputDevice.SOURCE_TOUCHSCREEN)
                                } catch (_: Exception) {}
                            }
                        },
                        onDragEnd = {
                            onOffsetChange(Offset.Zero, thumbVisualOffset)
                            wasAtEdge = false
                            if (ringEngaged) {
                                ringEngaged = false
                                clickButton?.let { state?.release(it) }
                            }
                        },
                        onDragCancel = {
                            onOffsetChange(Offset.Zero, thumbVisualOffset)
                            wasAtEdge = false
                            if (ringEngaged) {
                                ringEngaged = false
                                clickButton?.let { state?.release(it) }
                            }
                        }
                    ) { change, _ ->
                        change.consume()
                        val center = Offset(size.width / 2f, size.height / 2f)
                        val current = change.position - center
                        val dist = sqrt(current.x * current.x + current.y * current.y)
                        val atEdge = dist > thumbVisualOffset * 0.95f
                        val clamped = if (dist <= thumbVisualOffset) current
                        else {
                            val angle = atan2(current.y, current.x)
                            Offset(cos(angle) * thumbVisualOffset, sin(angle) * thumbVisualOffset)
                        }
                        if (atEdge && !wasAtEdge) {
                            vibrateLight(view) // detent: thumb stops at the edge
                        }
                        wasAtEdge = atEdge

                        // Push-through click (ring mode only): push past the edge -> L3/R3
                        if (clickButton != null && isRing && state != null) {
                            if (!ringEngaged && dist > pressRadius) {
                                ringEngaged = true
                                state.press(clickButton)
                                vibrateHeavy(view)
                            } else if (ringEngaged && dist < releaseRadius) {
                                ringEngaged = false
                                state.release(clickButton)
                            }
                        }

                        onOffsetChange(clamped, thumbVisualOffset)
                    }
                } else Modifier
            )
    ) {
        Box(
            modifier = Modifier
                .size(thumbSizeDp)
                .offset { IntOffset(offset.x.roundToInt(), offset.y.roundToInt()) }
                .clip(CircleShape)
                .background(t.stickThumb)
                .border(1.dp, t.border, CircleShape)
        )
        }

        // Arc label last, so the stick base can't cover it. Sits on the outer
        // side of each arc — away from the sticks, toward the screen edges.
        if (clickButton != null && !isRing) {
            Text(
                clickButton,
                color = if (ringPressed) t.accent else t.onBody,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .align(if (innerIsRight) Alignment.CenterEnd else Alignment.CenterStart)
                    .offset(x = if (innerIsRight) 20.dp else -(bandDp + 2.dp))
            )
        }
    }
}

// -- Triggers & Bumpers --

@Composable
fun TriggerButton(label: String, state: ControllerState, editing: Boolean = false) {
    val pressed = !editing && state.isPressed(label)
    val view = LocalView.current
    val t = LocalControllerTheme.current
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .width(60.dp)
            .height(34.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(if (pressed) t.buttonFillPressed else t.buttonFill)
            .border(1.dp, if (pressed) t.borderPressed else t.border, RoundedCornerShape(6.dp))
            .then(
                if (!editing) Modifier.pointerInput(label) {
                    detectTapGestures(
                        onPress = {
                            state.press(label)
                            vibrateLight(view)
                            tryAwaitRelease()
                            state.release(label)
                        }
                    )
                } else Modifier
            )
    ) {
        Text(label, color = if (pressed) t.text else t.textDim, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun BumperButton(label: String, state: ControllerState, editing: Boolean = false) {
    val pressed = !editing && state.isPressed(label)
    val view = LocalView.current
    val t = LocalControllerTheme.current
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .width(60.dp)
            .height(28.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(if (pressed) t.buttonFillPressed else t.buttonFill)
            .border(1.dp, if (pressed) t.borderPressed else t.border, RoundedCornerShape(4.dp))
            .then(
                if (!editing) Modifier.pointerInput(label) {
                    detectTapGestures(
                        onPress = {
                            state.press(label)
                            vibrateLight(view)
                            tryAwaitRelease()
                            state.release(label)
                        }
                    )
                } else Modifier
            )
    ) {
        Text(label, color = if (pressed) t.text else t.textDim, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

// -- Touchpad --

@Composable
fun Touchpad(state: ControllerState, editing: Boolean = false) {
    val pressed = !editing && state.isPressed("Touchpad")
    val view = LocalView.current
    val t = LocalControllerTheme.current
    val conn = LocalConnState.current

    // Pulse used while the link is still coming up
    val pulse = if (conn.connecting && !conn.connected) {
        val transition = rememberInfiniteTransition(label = "led")
        transition.animateFloat(
            initialValue = 0.15f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween(700, easing = LinearEasing),
                repeatMode = RepeatMode.Reverse
            ),
            label = "ledAlpha"
        ).value
    } else 1f

    val padW = 214.dp       // widest at the top
    val padH = 96.dp
    // 10 degrees of lean, matching the Create/Options pills:
    // 96dp * tan(10deg) ~= 17dp of inset per side at the bottom
    val taper = 17.dp
    val corner = 18.dp

    Box(contentAlignment = Alignment.Center) {
        // Light bar: a strip down each slanted side only — the real pad has no
        // light across the top or bottom. Each strip follows the touchpad edge
        // and curves in with the top corner.
        if (t.ledColor != null) {
            val barAlpha = when {
                conn.connected -> 1f
                conn.connecting -> pulse * 0.5f
                else -> 0.12f
            }
            Canvas(modifier = Modifier.size(padW + 16.dp, padH + 10.dp)) {
                val w = padW.toPx(); val h = padH.toPx()
                val tp = taper.toPx(); val r = corner.toPx()
                val cx = size.width / 2f; val cy = size.height / 2f
                val gap = 3.5.dp.toPx()
                val l = cx - w / 2f - gap
                val rt = cx + w / 2f + gap
                val top = cy - h / 2f
                val bot = cy + h / 2f
                val stroke = androidx.compose.ui.graphics.drawscope.Stroke(
                    width = 4.dp.toPx(),
                    cap = androidx.compose.ui.graphics.StrokeCap.Round
                )
                val color = t.ledColor.copy(barAlpha)

                // Left strip: up the slanted edge, easing into the top corner
                drawPath(
                    androidx.compose.ui.graphics.Path().apply {
                        moveTo(l + tp, bot)
                        lineTo(l + r * 0.18f, top + r * 0.75f)
                        quadraticBezierTo(l, top + r * 0.15f, l + r * 0.55f, top)
                    },
                    color, style = stroke
                )
                // Right strip: mirrored
                drawPath(
                    androidx.compose.ui.graphics.Path().apply {
                        moveTo(rt - tp, bot)
                        lineTo(rt - r * 0.18f, top + r * 0.75f)
                        quadraticBezierTo(rt, top + r * 0.15f, rt - r * 0.55f, top)
                    },
                    color, style = stroke
                )
            }
        }

        // Touchpad surface: rounded trapezoid, wider at the top
        Box(
            modifier = Modifier
                .width(padW)
                .height(padH)
                .then(
                    if (!editing) Modifier.pointerInput("Touchpad") {
                        detectTapGestures(
                            onPress = {
                                state.press("Touchpad")
                                vibrateLight(view)
                                tryAwaitRelease()
                                state.release("Touchpad")
                            }
                        )
                    } else Modifier
                )
        ) {
            Canvas(modifier = Modifier.matchParentSize()) {
                val w = size.width; val h = size.height
                val tp = taper.toPx(); val r = corner.toPx()
                val path = androidx.compose.ui.graphics.Path().apply {
                    moveTo(r, 0f)
                    lineTo(w - r, 0f)
                    quadraticBezierTo(w, 0f, w - r * 0.3f, r * 0.85f)
                    lineTo(w - tp, h - r * 0.45f)
                    quadraticBezierTo(w - tp, h, w - tp - r * 0.45f, h)
                    lineTo(tp + r * 0.45f, h)
                    quadraticBezierTo(tp, h, tp, h - r * 0.45f)
                    lineTo(r * 0.3f, r * 0.85f)
                    quadraticBezierTo(0f, 0f, r, 0f)
                    close()
                }
                drawPath(path, if (pressed) t.buttonFillPressed else t.buttonFill)
                drawPath(
                    path,
                    if (pressed) t.borderPressed else t.border,
                    style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.dp.toPx())
                )
            }
        }

        // Player indicator under the touchpad: flashes white while connecting,
        // stays lit once connected
        if (t.ledColor != null) {
            val ledAlpha = when {
                conn.connected -> 0.95f
                conn.connecting -> pulse
                else -> 0.12f
            }
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .offset(y = 8.dp)
                    .width(52.dp)
                    .height(4.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(Color.White.copy(ledAlpha))
            )
        }
    }
}

/** DualSense mute/mic button — small round button under the touchpad. */
@Composable
fun MuteButton(state: ControllerState, editing: Boolean = false) {
    val pressed = !editing && state.isPressed("Mute")
    val view = LocalView.current
    val t = LocalControllerTheme.current
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(28.dp)
            .clip(CircleShape)
            .background(if (pressed) t.buttonFillPressed else t.buttonFill)
            .border(1.dp, if (pressed) t.borderPressed else t.border, CircleShape)
            .then(
                if (!editing) Modifier.pointerInput("Mute") {
                    detectTapGestures(
                        onPress = {
                            state.press("Mute")
                            vibrateLight(view)
                            tryAwaitRelease()
                            state.release("Mute")
                        }
                    )
                } else Modifier
            )
    ) {
        Text("\u1F3A4".let { "\u25CF" }, color = if (pressed) t.text else t.textDim, fontSize = 9.sp)
    }
}

/**
 * DualSense Create / Options buttons. Options is three horizontal lines;
 * Create is the capture glyph (a frame with a segmented left edge).
 */
@Composable
fun SystemGlyphButton(label: String, state: ControllerState, editing: Boolean = false, lean: Float = 0f) {
    val pressed = !editing && state.isPressed(label)
    val view = LocalView.current
    val t = LocalControllerTheme.current
    val glyph = if (pressed) t.text else t.onBody

    // Like the real pad: the icon is printed ABOVE the button, and the button
    // itself is a plain vertical pill leaning slightly inward.
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Canvas(modifier = Modifier.size(13.dp, 10.dp)) {
            val w = size.width
            val h = size.height
            val stroke = h * 0.13f
            if (label == "Options") {
                for (i in 0..2) {
                    val y = h * (0.2f + 0.3f * i)
                    drawLine(
                        color = glyph,
                        start = Offset(0f, y),
                        end = Offset(w, y),
                        strokeWidth = stroke,
                        cap = androidx.compose.ui.graphics.StrokeCap.Round
                    )
                }
            } else {
                // Create: three short rays fanning upward
                val cx = w / 2f
                listOf(-38f, 0f, 38f).forEach { deg ->
                    val rad = Math.toRadians(deg.toDouble())
                    val dx = sin(rad).toFloat()
                    val dy = -cos(rad).toFloat()
                    drawLine(
                        color = glyph,
                        start = Offset(cx + dx * h * 0.28f, h * 0.85f + dy * h * 0.28f),
                        end = Offset(cx + dx * h * 0.85f, h * 0.85f + dy * h * 0.85f),
                        strokeWidth = stroke,
                        cap = androidx.compose.ui.graphics.StrokeCap.Round
                    )
                }
            }
        }
        Box(
            modifier = Modifier
                .rotate(lean)
                .width(13.dp)
                .height(34.dp)
                .clip(RoundedCornerShape(7.dp))
                .background(if (pressed) t.buttonFillPressed else t.buttonFill)
                .border(1.dp, if (pressed) t.borderPressed else t.border, RoundedCornerShape(7.dp))
                .then(
                    if (!editing) Modifier.pointerInput(label) {
                        detectTapGestures(
                            onPress = {
                                state.press(label)
                                vibrateLight(view)
                                tryAwaitRelease()
                                state.release(label)
                            }
                        )
                    } else Modifier
                )
        )
    }
}

// -- Small Pill Buttons --

@Composable
fun SmallPillButton(label: String, state: ControllerState, editing: Boolean = false) {
    val pressed = !editing && state.isPressed(label)
    val view = LocalView.current
    val t = LocalControllerTheme.current
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .width(44.dp)
            .height(26.dp)
            .clip(RoundedCornerShape(13.dp))
            .background(if (pressed) t.buttonFillPressed else t.buttonFill)
            .then(
                if (!editing) Modifier.pointerInput(label) {
                    detectTapGestures(
                        onPress = {
                            state.press(label)
                            vibrateLight(view)
                            tryAwaitRelease()
                            state.release(label)
                        }
                    )
                } else Modifier
            )
    ) {
        Text(label, color = if (pressed) t.text else t.textDim, fontSize = 7.sp, fontWeight = FontWeight.Medium)
    }
}

// -- PS Button --

@Composable
fun PSButton(state: ControllerState, editing: Boolean = false) {
    val pressed = !editing && state.isPressed("PS")
    val view = LocalView.current
    val t = LocalControllerTheme.current
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(if (pressed) t.accent.copy(0.4f) else t.buttonFill)
            .border(1.5.dp, t.accent.copy(if (pressed) 0.9f else 0.45f), CircleShape)
            .then(
                if (!editing) Modifier.pointerInput("PS") {
                    detectTapGestures(
                        onPress = {
                            state.press("PS")
                            vibrateLight(view)
                            tryAwaitRelease()
                            state.release("PS")
                        }
                    )
                } else Modifier
            )
    ) {
        Text("PS", color = if (pressed) t.text else t.accent, fontSize = 10.sp, fontWeight = FontWeight.Bold)
    }
}

// -- Settings Overlay --

@Composable
fun SettingsOverlay(
    connectionMode: String,
    serverHost: String,
    onConnectionModeChange: (String) -> Unit,
    onServerHostChange: (String) -> Unit,
    onConnect: () -> Unit,
    onEditLayout: () -> Unit,
    onResetLayout: () -> Unit,
    onClose: () -> Unit,
    btController: BluetoothHidController,
    onMakeDiscoverable: () -> Unit,
    stickClick: String,
    onStickClickChange: (String) -> Unit,
    themeId: String,
    onThemeChange: (String) -> Unit,
    wallpaperId: String,
    onWallpaperChange: (String) -> Unit,
    onPickWallpaper: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(0.9f))
            .pointerInput("settingsBg") { detectTapGestures { /* consume all touch */ } },
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .width(340.dp)
                .heightIn(max = 360.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(Color(0xFF1a1a1a))
                .border(1.dp, Color.White.copy(0.1f), RoundedCornerShape(16.dp))
                .padding(20.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Title + X close
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Settings", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(0.1f))
                        .pointerInput("closeX") { detectTapGestures { onClose() } },
                    contentAlignment = Alignment.Center
                ) {
                    Text("\u2715", color = Color.White, fontSize = 14.sp)
                }
            }

            // -- Connection Mode --
            Text("Connection", color = Color.Gray, fontSize = 11.sp, fontWeight = FontWeight.Medium)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf("wifi" to "WiFi", "cable" to "USB", "bluetooth" to "iPad BT", "gamepad" to "Gamepad").forEach { (mode, label) ->
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(if (connectionMode == mode) Color(0xFF4488FF).copy(0.25f) else Color.White.copy(0.06f))
                            .border(1.dp, if (connectionMode == mode) Color(0xFF4488FF).copy(0.5f) else Color.White.copy(0.1f), RoundedCornerShape(8.dp))
                            .pointerInput(mode) { detectTapGestures { onConnectionModeChange(mode) } }
                            .padding(horizontal = 10.dp, vertical = 8.dp)
                    ) {
                        Text(label, color = if (connectionMode == mode) Color(0xFF4488FF) else Color.Gray, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }

            if (connectionMode == "wifi") {
                // Server IP entry for WiFi
                Text("Mac/iPad Server IP", color = Color.Gray, fontSize = 10.sp)
                var hostText by remember { mutableStateOf(serverHost) }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    androidx.compose.material3.OutlinedTextField(
                        value = hostText,
                        onValueChange = { hostText = it; onServerHostChange(it) },
                        placeholder = { Text("e.g. 192.168.1.100", fontSize = 12.sp) },
                        singleLine = true,
                        modifier = Modifier.weight(1f).height(48.dp),
                        textStyle = androidx.compose.ui.text.TextStyle(
                            color = Color.White,
                            fontSize = 13.sp,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        ),
                        colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Color(0xFF4488FF),
                            unfocusedBorderColor = Color.White.copy(0.2f),
                            cursorColor = Color(0xFF4488FF),
                        )
                    )
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(Color(0xFF4488FF).copy(0.25f))
                            .border(1.dp, Color(0xFF4488FF).copy(0.5f), RoundedCornerShape(8.dp))
                            .pointerInput("connect") { detectTapGestures { onConnect() } }
                            .padding(horizontal = 12.dp, vertical = 10.dp)
                    ) {
                        Text("Connect", color = Color(0xFF4488FF), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                }
                Text(
                    "Leave empty to auto-discover via Bonjour",
                    color = Color.Gray, fontSize = 9.sp
                )
            } else if (connectionMode == "bluetooth") {
                Text(
                    "Bluetooth link to the iPad Controller app.\nOpen Controller on the iPad and it will find this phone.",
                    color = Color.Gray, fontSize = 10.sp
                )
            } else if (connectionMode == "gamepad") {
                Text(
                    "Phone acts as a real Bluetooth gamepad — works with any Mac, PC, or Android TV, no app needed on the other side.\n(Not iPhone/iPad — Apple only allows Xbox/PS pads. Use iPad BT for that.)",
                    color = Color.Gray, fontSize = 10.sp
                )
                // First time: make phone visible so the computer can pair with it
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color(0xFF4488FF).copy(0.15f))
                        .border(1.dp, Color(0xFF4488FF).copy(0.4f), RoundedCornerShape(8.dp))
                        .pointerInput("discoverable") { detectTapGestures { onMakeDiscoverable() } }
                        .padding(horizontal = 12.dp, vertical = 8.dp)
                ) {
                    Text("Make phone discoverable (new pairing)", color = Color(0xFF4488FF), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
                // Already paired: tap to connect
                val paired = remember { btController.pairedDevices() }
                if (paired.isNotEmpty()) {
                    Text("Paired devices — tap to connect:", color = Color.Gray, fontSize = 10.sp)
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        paired.take(5).forEach { device ->
                            val name = try { device.name ?: device.address } catch (_: SecurityException) { device.address }
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(Color.White.copy(0.06f))
                                    .border(1.dp, Color.White.copy(0.1f), RoundedCornerShape(8.dp))
                                    .pointerInput(device.address) {
                                        detectTapGestures {
                                            btController.connectTo(device)
                                            onClose()
                                        }
                                    }
                                    .padding(horizontal = 12.dp, vertical = 8.dp)
                            ) {
                                Text(name, color = Color.White.copy(0.8f), fontSize = 12.sp)
                            }
                        }
                    }
                }
            } else {
                Text(
                    "Connect USB cable and open Controller on Mac.\nADB reverse forwarding is automatic.",
                    color = Color.Gray, fontSize = 10.sp
                )
            }

            Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(0.1f)))

            // -- Controls --
            Text("Controls", color = Color.Gray, fontSize = 11.sp, fontWeight = FontWeight.Medium)
            Text("Stick click (L3/R3)", color = Color.White, fontSize = 13.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("off" to "Off", "button" to "Button", "ring" to "Ring").forEach { (mode, label) ->
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(if (stickClick == mode) Color(0xFF4488FF).copy(0.25f) else Color.White.copy(0.06f))
                            .border(1.dp, if (stickClick == mode) Color(0xFF4488FF).copy(0.5f) else Color.White.copy(0.1f), RoundedCornerShape(8.dp))
                            .pointerInput(mode) { detectTapGestures { onStickClickChange(mode) } }
                            .padding(horizontal = 14.dp, vertical = 8.dp)
                    ) {
                        Text(label, color = if (stickClick == mode) Color(0xFF4488FF) else Color.Gray, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
            Text(
                when (stickClick) {
                    "off" -> "No stick click."
                    "button" -> "A curved button on the inner side of each stick."
                    else -> "A ring around each stick — tap it, or push the stick past its edge."
                },
                color = Color.Gray, fontSize = 9.sp
            )

            Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(0.1f)))

            Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(0.1f)))

            // -- Appearance --
            Text("Theme", color = Color.Gray, fontSize = 11.sp, fontWeight = FontWeight.Medium)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Themes.all.forEach { th ->
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(if (themeId == th.id) Color(0xFF4488FF).copy(0.25f) else Color.White.copy(0.06f))
                            .border(1.dp, if (themeId == th.id) Color(0xFF4488FF).copy(0.5f) else Color.White.copy(0.1f), RoundedCornerShape(8.dp))
                            .pointerInput(th.id) { detectTapGestures { onThemeChange(th.id) } }
                            .padding(horizontal = 10.dp, vertical = 8.dp)
                    ) {
                        Text(th.label, color = if (themeId == th.id) Color(0xFF4488FF) else Color.Gray, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }

            Text("Wallpaper", color = Color.Gray, fontSize = 11.sp, fontWeight = FontWeight.Medium)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Wallpapers.all.forEach { wp ->
                    Box(
                        modifier = Modifier
                            .size(34.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .then(if (wp.brush != null) Modifier.background(wp.brush) else Modifier.background(Color.Black))
                            .border(
                                if (wallpaperId == wp.id) 2.dp else 1.dp,
                                if (wallpaperId == wp.id) Color(0xFF4488FF) else Color.White.copy(0.15f),
                                RoundedCornerShape(8.dp)
                            )
                            .pointerInput(wp.id) { detectTapGestures { onWallpaperChange(wp.id) } }
                    )
                }
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(if (wallpaperId == "custom") Color(0xFF4488FF).copy(0.25f) else Color.White.copy(0.06f))
                        .border(1.dp, if (wallpaperId == "custom") Color(0xFF4488FF).copy(0.5f) else Color.White.copy(0.1f), RoundedCornerShape(8.dp))
                        .pointerInput("pickwp") { detectTapGestures { onPickWallpaper() } }
                        .padding(horizontal = 10.dp, vertical = 9.dp)
                ) {
                    Text("Photo...", color = if (wallpaperId == "custom") Color(0xFF4488FF) else Color.Gray, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                }
            }

            Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(0.1f)))

            // -- Layout --
            Text("Layout", color = Color.Gray, fontSize = 11.sp, fontWeight = FontWeight.Medium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color(0xFF4488FF).copy(0.15f))
                        .border(1.dp, Color(0xFF4488FF).copy(0.4f), RoundedCornerShape(8.dp))
                        .pointerInput("editLayout") { detectTapGestures { onEditLayout() } }
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                ) {
                    Text("Edit Layout", color = Color(0xFF4488FF), fontSize = 13.sp, fontWeight = FontWeight.Bold)
                }
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color.Red.copy(0.15f))
                        .border(1.dp, Color.Red.copy(0.4f), RoundedCornerShape(8.dp))
                        .pointerInput("resetLayout") { detectTapGestures { onResetLayout() } }
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                ) {
                    Text("Reset Layout", color = Color.Red, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}
