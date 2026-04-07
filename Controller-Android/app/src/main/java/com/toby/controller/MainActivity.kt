package com.toby.controller

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import kotlin.math.*

class MainActivity : ComponentActivity() {
    private var sender: ControllerSender? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val layoutStore = LayoutStore(this)
        // Migrate old "bluetooth" mode to "wifi"
        if (layoutStore.getConnectionMode() == "bluetooth") {
            layoutStore.setConnectionMode("wifi")
        }
        sender = ControllerSender(this)
        sender?.mode = layoutStore.getConnectionMode()
        sender?.serverHost = layoutStore.getServerHost()
        sender?.start()

        setContent {
            ControllerScreen(sender!!, layoutStore)
        }
    }

    override fun onDestroy() {
        sender?.stop()
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

fun computeDefaults(screenW: Float, screenH: Float): DefaultPositions {
    return DefaultPositions(
        l2 = Offset(16f, 8f),
        l1 = Offset(90f, 8f),
        r1 = Offset(screenW - 160f, 8f),
        r2 = Offset(screenW - 80f, 8f),
        dpad = Offset(20f, screenH * 0.22f),
        faceButtons = Offset(screenW - 190f, screenH * 0.15f),
        leftStick = Offset(30f, screenH * 0.58f),
        rightStick = Offset(screenW - 170f, screenH * 0.58f),
        create = Offset(screenW * 0.35f, 10f),
        touchpad = Offset(screenW * 0.5f - 65f, 10f),
        options = Offset(screenW * 0.65f - 20f, 10f),
        ps = Offset(screenW * 0.5f - 17f, screenH * 0.55f),
    )
}

// -- Main Screen --

@Composable
fun ControllerScreen(sender: ControllerSender, layoutStore: LayoutStore) {
    val state = remember { ControllerState() }
    var isConnected by remember { mutableStateOf(false) }
    var isConnecting by remember { mutableStateOf(false) }
    var connectedName by remember { mutableStateOf("") }
    var editing by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var connectionMode by remember { mutableStateOf(layoutStore.getConnectionMode()) }
    var serverHost by remember { mutableStateOf(layoutStore.getServerHost()) }

    LaunchedEffect(Unit) {
        sender.onStateChanged = {
            isConnected = sender.isConnected
            isConnecting = sender.isConnecting
            connectedName = sender.connectedServerName
        }
        // Wait for initial connection attempt
        kotlinx.coroutines.delay(500)
        isConnected = sender.isConnected
        isConnecting = sender.isConnecting
        connectedName = sender.connectedServerName
    }

    LaunchedEffect(
        state.pressedButtons.toList(),
        state.leftStick,
        state.rightStick
    ) {
        if (!editing && !showSettings) sender.send(state.toMessage())
    }

    val config = LocalConfiguration.current
    val density = LocalDensity.current
    val screenW = with(density) { config.screenWidthDp.dp.toPx() }
    val screenH = with(density) { config.screenHeightDp.dp.toPx() }
    val defaults = remember(screenW, screenH) { computeDefaults(screenW, screenH) }

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
                    else if (isConnected) "Connected to ${connectedName}"
                    else if (isConnecting) "Searching for server... (${connectionMode})"
                    else "Offline",
                color = if (editing) Color(0xFF4488FF) else Color.Gray,
                fontSize = 10.sp
            )
        }

        // Settings button (top right)
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 4.dp, end = 8.dp)
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
                    .align(Alignment.TopEnd)
                    .padding(top = 4.dp, end = 48.dp)
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

        // All controls absolutely positioned
        val inputDisabled = editing || showSettings
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

        // Settings overlay (must be LAST so it draws on top of controls)
        if (showSettings) {
            SettingsOverlay(
                connectionMode = connectionMode,
                serverHost = serverHost,
                onConnectionModeChange = { mode ->
                    connectionMode = mode
                    layoutStore.setConnectionMode(mode)
                    sender.switchMode(mode)
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
                onResetLayout = { layoutStore.clear() },
                onClose = { showSettings = false }
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
                        },
                        onDragCancel = {
                            onOffsetChange(Offset.Zero, thumbVisualOffset)
                        }
                    ) { change, _ ->
                        change.consume()
                        val center = Offset(size.width / 2f, size.height / 2f)
                        val current = change.position - center
                        val dist = sqrt(current.x * current.x + current.y * current.y)
                        val clamped = if (dist <= thumbVisualOffset) current
                        else {
                            val angle = atan2(current.y, current.x)
                            Offset(cos(angle) * thumbVisualOffset, sin(angle) * thumbVisualOffset)
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
                .background(Color.White.copy(0.15f))
                .border(1.dp, Color.White.copy(0.2f), CircleShape)
        )
    }
}

// -- Triggers & Bumpers --

@Composable
fun TriggerButton(label: String, state: ControllerState, editing: Boolean = false) {
    val pressed = !editing && state.isPressed(label)
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
    Box(
        modifier = Modifier
            .width(130.dp)
            .height(46.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(if (pressed) Color.White.copy(0.12f) else Color.White.copy(0.04f))
            .border(1.dp, Color.White.copy(0.12f), RoundedCornerShape(10.dp))
            .then(
                if (!editing) Modifier.pointerInput("Touchpad") {
                    detectTapGestures(
                        onPress = {
                            state.press("Touchpad")
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
                .width(300.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(Color(0xFF1a1a1a))
                .border(1.dp, Color.White.copy(0.1f), RoundedCornerShape(16.dp))
                .padding(20.dp),
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
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("wifi" to "WiFi", "cable" to "Cable (USB)").forEach { (mode, label) ->
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(if (connectionMode == mode) Color(0xFF4488FF).copy(0.25f) else Color.White.copy(0.06f))
                            .border(1.dp, if (connectionMode == mode) Color(0xFF4488FF).copy(0.5f) else Color.White.copy(0.1f), RoundedCornerShape(8.dp))
                            .pointerInput(mode) { detectTapGestures { onConnectionModeChange(mode) } }
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    ) {
                        Text(label, color = if (connectionMode == mode) Color(0xFF4488FF) else Color.Gray, fontSize = 13.sp, fontWeight = FontWeight.Bold)
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
