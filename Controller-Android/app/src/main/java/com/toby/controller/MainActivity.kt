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
import androidx.compose.foundation.background
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
        // v2: DualSense-style default layout — reset old saved positions once
        if (layoutStore.getLayoutVersion() < 2) {
            layoutStore.clearLayout()
            layoutStore.setLayoutVersion(2)
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

    fun press(button: String) { if (button !in pressedButtons) pressedButtons.add(button) }
    fun release(button: String) { pressedButtons.remove(button) }
    fun isPressed(button: String) = button in pressedButtons

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
    var pos by remember {
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
)

fun computeDefaults(screenW: Float, screenH: Float, d: Float): DefaultPositions {
    // Element sizes in px (must match the composables' dp sizes), d = px per dp
    val trigW = 60f * d; val trigH = 34f * d
    val bumpW = 60f * d; val bumpH = 28f * d
    val dpadS = 132f * d
    val faceS = 138f * d
    val stickS = 130f * d
    val padW = 210f * d; val padH = 84f * d
    val pillW = 44f * d
    val psS = 34f * d
    val m = 12f * d          // screen edge margin
    val gap = 8f * d

    // Real DualSense geometry, scaled to the screen: shoulders in the corners,
    // D-Pad / face buttons outboard, symmetric sticks low and toward the center,
    // big touchpad top-center with Create/Options flanking it, PS between the sticks.
    return DefaultPositions(
        l2 = Offset(m, m),
        l1 = Offset(m + trigW + gap, m + (trigH - bumpH) / 2),
        r1 = Offset(screenW - m - trigW - gap - bumpW, m + (trigH - bumpH) / 2),
        r2 = Offset(screenW - m - trigW, m),
        dpad = Offset(max(m, 0.16f * screenW - dpadS / 2), 0.44f * screenH - dpadS / 2),
        faceButtons = Offset(min(screenW - m - faceS, 0.84f * screenW - faceS / 2), 0.44f * screenH - faceS / 2),
        leftStick = Offset(0.35f * screenW - stickS / 2, min(screenH - m - stickS, 0.74f * screenH - stickS / 2)),
        rightStick = Offset(0.65f * screenW - stickS / 2, min(screenH - m - stickS, 0.74f * screenH - stickS / 2)),
        create = Offset(screenW / 2 - padW / 2 - gap - pillW, 0.14f * screenH + 8f * d),
        touchpad = Offset(screenW / 2 - padW / 2, 0.14f * screenH),
        options = Offset(screenW / 2 + padW / 2 + gap, 0.14f * screenH + 8f * d),
        ps = Offset(screenW / 2 - psS / 2, 0.66f * screenH - psS / 2),
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

    LaunchedEffect(
        state.pressedButtons.toList(),
        state.leftStick,
        state.rightStick
    ) {
        if (!editing && !showSettings) {
            val msg = state.toMessage()
            when (connectionMode) {
                "bluetooth" -> blePeripheral.send(msg)
                "gamepad" -> btController.send(msg)
                else -> sender.send(msg)
            }
        }
    }

    val config = LocalConfiguration.current
    val density = LocalDensity.current
    val screenW = with(density) { config.screenWidthDp.dp.toPx() }
    val screenH = with(density) { config.screenHeightDp.dp.toPx() }
    val defaults = remember(screenW, screenH, density) { computeDefaults(screenW, screenH, density.density) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .systemBarsPadding()
    ) {
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
                color = if (editing) Color(0xFF4488FF) else Color.Gray,
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
                .background(if (showSettings || editing) Color(0xFF4488FF).copy(0.3f) else Color.White.copy(0.08f))
                .pointerInput("settings") {
                    detectTapGestures { showSettings = !showSettings; if (showSettings) editing = false }
                },
            contentAlignment = Alignment.Center
        ) {
            Text("\u2699", color = if (showSettings || editing) Color(0xFF4488FF) else Color.Gray, fontSize = 16.sp)
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
                onOffsetChange = { offset, radius ->
                    state.leftStick = offset
                    state.stickRadiusPx = radius
                },
                editing = inputDisabled,
            )
        }
        DraggableElement("rstick", layoutStore, editing, defaults.rightStick) {
            AnalogStick(
                offset = state.rightStick,
                onOffsetChange = { offset, radius ->
                    state.rightStick = offset
                    state.stickRadiusPx = radius
                },
                editing = inputDisabled,
            )
        }
        DraggableElement("create", layoutStore, editing, defaults.create) {
            SmallPillButton("Create", state, inputDisabled)
        }
        DraggableElement("touchpad", layoutStore, editing, defaults.touchpad) {
            Touchpad(state, inputDisabled)
        }
        DraggableElement("options", layoutStore, editing, defaults.options) {
            SmallPillButton("Options", state, inputDisabled)
        }
        DraggableElement("ps", layoutStore, editing, defaults.ps) {
            PSButton(state, inputDisabled)
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
                onClose = { showSettings = false },
                btController = btController,
                onMakeDiscoverable = {
                    val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).apply {
                        putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300)
                    }
                    try { activity.startActivity(intent) } catch (_: Exception) {}
                },
            )
        }
    }
}

// -- D-Pad --

@Composable
fun DPad(state: ControllerState, editing: Boolean = false) {
    val btnSize = 44.dp
    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(btnSize * 3)) {
        Box(
            modifier = Modifier
                .size(20.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.05f))
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
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(42.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (pressed) Color.White.copy(0.2f) else Color.White.copy(0.06f))
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
        Text(symbol, color = if (pressed) Color.White else Color.Gray, fontSize = 16.sp)
    }
}

// -- Face Buttons --

@Composable
fun FaceButtons(state: ControllerState, editing: Boolean = false) {
    val spacing = 46.dp
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
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .background(if (pressed) color.copy(0.4f) else Color.White.copy(0.06f))
            .border(2.dp, color.copy(if (pressed) 1f else 0.5f), CircleShape)
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
        Text(symbol, color = if (pressed) Color.White else color, fontSize = 16.sp, fontWeight = FontWeight.Bold)
    }
}

// -- Analog Stick --

@Composable
fun AnalogStick(
    offset: Offset,
    onOffsetChange: (Offset, Float) -> Unit,
    editing: Boolean = false,
) {
    val density = LocalDensity.current
    val baseSizeDp = 130.dp
    val thumbSizeDp = 56.dp
    val thumbVisualOffset = with(density) { ((baseSizeDp - thumbSizeDp) / 2).toPx() }
    val view = LocalView.current
    var wasAtEdge by remember { mutableStateOf(false) }

    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(baseSizeDp)
            .clip(CircleShape)
            .background(Color.White.copy(0.04f))
            .border(1.dp, Color.White.copy(0.1f), CircleShape)
            .then(
                if (!editing) Modifier.pointerInput(Unit) {
                    detectDragGestures(
                        onDragEnd = {
                            onOffsetChange(Offset.Zero, thumbVisualOffset)
                            wasAtEdge = false
                        },
                        onDragCancel = {
                            onOffsetChange(Offset.Zero, thumbVisualOffset)
                            wasAtEdge = false
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
                            vibrateLight(view)
                        }
                        wasAtEdge = atEdge
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
                .background(Color.White.copy(0.15f))
                .border(1.dp, Color.White.copy(0.2f), CircleShape)
        )
    }
}

// -- Triggers & Bumpers --

@Composable
fun TriggerButton(label: String, state: ControllerState, editing: Boolean = false) {
    val pressed = !editing && state.isPressed(label)
    val view = LocalView.current
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .width(60.dp)
            .height(34.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(if (pressed) Color.White.copy(0.2f) else Color.White.copy(0.06f))
            .border(1.dp, Color.White.copy(0.12f), RoundedCornerShape(6.dp))
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
        Text(label, color = if (pressed) Color.White else Color.Gray, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun BumperButton(label: String, state: ControllerState, editing: Boolean = false) {
    val pressed = !editing && state.isPressed(label)
    val view = LocalView.current
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .width(60.dp)
            .height(28.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(if (pressed) Color.White.copy(0.2f) else Color.White.copy(0.06f))
            .border(1.dp, Color.White.copy(0.12f), RoundedCornerShape(4.dp))
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
        Text(label, color = if (pressed) Color.White else Color.Gray, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

// -- Touchpad --

@Composable
fun Touchpad(state: ControllerState, editing: Boolean = false) {
    val pressed = !editing && state.isPressed("Touchpad")
    val view = LocalView.current
    Box(
        modifier = Modifier
            .width(210.dp)
            .height(84.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(if (pressed) Color.White.copy(0.12f) else Color.White.copy(0.04f))
            .border(1.dp, Color.White.copy(0.12f), RoundedCornerShape(14.dp))
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
    )
}

// -- Small Pill Buttons --

@Composable
fun SmallPillButton(label: String, state: ControllerState, editing: Boolean = false) {
    val pressed = !editing && state.isPressed(label)
    val view = LocalView.current
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .width(44.dp)
            .height(26.dp)
            .clip(RoundedCornerShape(13.dp))
            .background(if (pressed) Color.White.copy(0.2f) else Color.White.copy(0.06f))
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
        Text(label, color = if (pressed) Color.White else Color.Gray, fontSize = 7.sp, fontWeight = FontWeight.Medium)
    }
}

// -- PS Button --

@Composable
fun PSButton(state: ControllerState, editing: Boolean = false) {
    val pressed = !editing && state.isPressed("PS")
    val view = LocalView.current
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(if (pressed) Color(0xFF4488FF).copy(0.4f) else Color.White.copy(0.06f))
            .border(1.5.dp, Color(0xFF4488FF).copy(if (pressed) 0.8f else 0.3f), CircleShape)
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
        Text("PS", color = if (pressed) Color.White else Color(0xFF4488FF), fontSize = 10.sp, fontWeight = FontWeight.Bold)
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
