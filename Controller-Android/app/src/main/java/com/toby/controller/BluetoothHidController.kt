package com.toby.controller

import android.annotation.SuppressLint
import android.bluetooth.*
import android.content.Context
import java.util.concurrent.Executors

/**
 * Registers the phone as a real Bluetooth HID gamepad, so it works with ANY host
 * (Mac, Windows, Linux, Android TV, Quest...) — no receiver app needed.
 *
 * Uses the Android 9+ BluetoothHidDevice profile. The host pairs with the phone
 * from its normal Bluetooth settings, exactly like a real controller.
 */
@SuppressLint("MissingPermission")
class BluetoothHidController(private val context: Context, private val layoutStore: LayoutStore) {

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var hidDevice: BluetoothHidDevice? = null
    private var hostDevice: BluetoothDevice? = null
    private val executor = Executors.newSingleThreadExecutor()

    var isRegistered = false
        private set
    var isConnected = false
        private set
    var connectedDeviceName = ""
        private set
    var statusMessage = ""
        private set
    var onStateChanged: (() -> Unit)? = null

    // Last report sent — replayed when the host asks via GET_REPORT
    private val lastReport = ByteArray(9).also {
        it[2] = HAT_NEUTRAL
        it[3] = 128.toByte(); it[4] = 128.toByte(); it[5] = 128.toByte(); it[6] = 128.toByte()
    }

    /** Vibrate when the host sends a rumble report (games in Gamepad mode). */
    var rumbleEnabled = true

    // HID Report Descriptor: standard gamepad, report ID 1.
    // 14 buttons + hat switch (D-Pad) + 4 axes (X/Y = left stick, Z/Rz = right stick).
    // Report: [buttons lo][buttons hi][hat][X][Y][Z][Rz] = 7 bytes.
    private val hidDescriptor = byteArrayOf(
        0x05, 0x01,                          // Usage Page (Generic Desktop)
        0x09, 0x05,                          // Usage (Gamepad)
        0xA1.toByte(), 0x01,                 // Collection (Application)
        0x85.toByte(), REPORT_ID,            //   Report ID (1)

        // 14 Buttons + 2 bits padding
        0x05, 0x09,                          //   Usage Page (Button)
        0x19, 0x01,                          //   Usage Minimum (1)
        0x29, 0x0E,                          //   Usage Maximum (14)
        0x15, 0x00,                          //   Logical Minimum (0)
        0x25, 0x01,                          //   Logical Maximum (1)
        0x75, 0x01,                          //   Report Size (1)
        0x95.toByte(), 0x0E,                 //   Report Count (14)
        0x81.toByte(), 0x02,                 //   Input (Data, Variable, Absolute)
        0x75, 0x01,                          //   Report Size (1)
        0x95.toByte(), 0x02,                 //   Report Count (2)
        0x81.toByte(), 0x03,                 //   Input (Constant) — padding

        // Hat switch (D-Pad), 8 directions, null state
        0x05, 0x01,                          //   Usage Page (Generic Desktop)
        0x09, 0x39,                          //   Usage (Hat switch)
        0x15, 0x00,                          //   Logical Minimum (0)
        0x25, 0x07,                          //   Logical Maximum (7)
        0x35, 0x00,                          //   Physical Minimum (0)
        0x46, 0x3B, 0x01,                    //   Physical Maximum (315)
        0x65, 0x14,                          //   Unit (degrees)
        0x75, 0x04,                          //   Report Size (4)
        0x95.toByte(), 0x01,                 //   Report Count (1)
        0x81.toByte(), 0x42,                 //   Input (Data, Variable, Absolute, Null State)
        0x75, 0x04,                          //   Report Size (4)
        0x95.toByte(), 0x01,                 //   Report Count (1)
        0x81.toByte(), 0x03,                 //   Input (Constant) — padding

        // Axes: X, Y (left stick), Z, Rz (right stick), 0..255 centered at 128
        0x09, 0x30,                          //   Usage (X)
        0x09, 0x31,                          //   Usage (Y)
        0x09, 0x32,                          //   Usage (Z)
        0x09, 0x35,                          //   Usage (Rz)
        0x15, 0x00,                          //   Logical Minimum (0)
        0x26, 0xFF.toByte(), 0x00,           //   Logical Maximum (255)
        0x75, 0x08,                          //   Report Size (8)
        0x95.toByte(), 0x04,                 //   Report Count (4)
        0x81.toByte(), 0x02,                 //   Input (Data, Variable, Absolute)

        // Analog triggers: Rx / Ry, 0..255
        0x09, 0x33,                          //   Usage (Rx) — L2
        0x09, 0x34,                          //   Usage (Ry) — R2
        0x15, 0x00,                          //   Logical Minimum (0)
        0x26, 0xFF.toByte(), 0x00,           //   Logical Maximum (255)
        0x75, 0x08,                          //   Report Size (8)
        0x95.toByte(), 0x02,                 //   Report Count (2)
        0x81.toByte(), 0x02,                 //   Input (Data, Variable, Absolute)

        // Rumble: two output bytes (strong, weak) the host can push to us
        0x85.toByte(), REPORT_ID_RUMBLE,     //   Report ID (2)
        0x06, 0x00, 0xFF.toByte(),           //   Usage Page (Vendor Defined)
        0x09, 0x01,                          //   Usage (Vendor 1)
        0x15, 0x00,                          //   Logical Minimum (0)
        0x26, 0xFF.toByte(), 0x00,           //   Logical Maximum (255)
        0x75, 0x08,                          //   Report Size (8)
        0x95.toByte(), 0x02,                 //   Report Count (2)
        0x91.toByte(), 0x02,                 //   Output (Data, Variable, Absolute)

        0xC0.toByte()                        // End Collection
    )

    // Button name → bit position in the 16-bit button field (D-Pad is the hat switch, not a button)
    private val buttonBitMap = mapOf(
        "Cross" to 0,
        "Circle" to 1,
        "Square" to 2,
        "Triangle" to 3,
        "L1" to 4,
        "R1" to 5,
        "L2" to 6,
        "R2" to 7,
        "Create" to 8,
        "Options" to 9,
        "L3" to 10,
        "R3" to 11,
        "PS" to 12,
        "Touchpad" to 13,
    )

    fun start() {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        if (manager == null) {
            statusMessage = "No Bluetooth manager"
            onStateChanged?.invoke()
            return
        }
        bluetoothAdapter = manager.adapter
        if (bluetoothAdapter == null) {
            statusMessage = "No Bluetooth adapter"
            onStateChanged?.invoke()
            return
        }
        if (bluetoothAdapter?.isEnabled != true) {
            statusMessage = "Bluetooth is OFF — enable it in Settings"
            onStateChanged?.invoke()
            return
        }

        statusMessage = "Getting HID profile..."
        onStateChanged?.invoke()

        bluetoothAdapter?.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile?) {
                if (profile == BluetoothProfile.HID_DEVICE) {
                    hidDevice = proxy as? BluetoothHidDevice
                    statusMessage = "Registering as gamepad..."
                    onStateChanged?.invoke()
                    registerHidDevice()
                }
            }

            override fun onServiceDisconnected(profile: Int) {
                if (profile == BluetoothProfile.HID_DEVICE) {
                    hidDevice = null
                    isRegistered = false
                    isConnected = false
                    statusMessage = "HID profile disconnected"
                    onStateChanged?.invoke()
                }
            }
        }, BluetoothProfile.HID_DEVICE)
    }

    private fun registerHidDevice() {
        val hid = hidDevice ?: return

        val sdp = BluetoothHidDeviceAppSdpSettings(
            "Controller",
            "PS5-style Gamepad",
            "Controller App",
            BluetoothHidDevice.SUBCLASS2_GAMEPAD,
            hidDescriptor
        )

        val callback = object : BluetoothHidDevice.Callback() {
            override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
                isRegistered = registered
                if (registered) {
                    statusMessage = "Gamepad ready — pair from the other device, or tap a paired device in Settings"
                    // Auto-reconnect: try the plugged device, else the last host we talked to
                    val target = pluggedDevice ?: lastHostDevice()
                    if (target != null) {
                        statusMessage = "Gamepad ready — connecting to ${target.name ?: target.address}..."
                        hidDevice?.connect(target)
                    }
                } else {
                    statusMessage = "Registration failed — this phone's Bluetooth may not support HID device mode"
                }
                onStateChanged?.invoke()
            }

            override fun onConnectionStateChanged(device: BluetoothDevice?, state: Int) {
                when (state) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        hostDevice = device
                        isConnected = true
                        connectedDeviceName = device?.name ?: device?.address ?: "device"
                        statusMessage = "Connected to $connectedDeviceName"
                        device?.address?.let { layoutStore.setLastBtHost(it) }
                    }
                    BluetoothProfile.STATE_CONNECTING -> {
                        statusMessage = "Connecting to ${device?.name ?: device?.address}..."
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        hostDevice = null
                        isConnected = false
                        connectedDeviceName = ""
                        statusMessage = "Disconnected — waiting for host"
                    }
                }
                onStateChanged?.invoke()
            }

            // Hosts (macOS/Windows) query the current report during setup.
            // Not answering stalls enumeration — this was missing before.
            override fun onGetReport(device: BluetoothDevice?, type: Byte, id: Byte, bufferSize: Int) {
                val hid2 = hidDevice ?: return
                if (device == null) return
                if (type == BluetoothHidDevice.REPORT_TYPE_INPUT) {
                    hid2.replyReport(device, type, REPORT_ID, lastReport)
                } else {
                    hid2.reportError(device, BluetoothHidDevice.ERROR_RSP_UNSUPPORTED_REQ)
                }
            }

            override fun onSetReport(device: BluetoothDevice?, type: Byte, id: Byte, data: ByteArray?) {
                val hid2 = hidDevice ?: return
                if (device == null) return
                if (id == REPORT_ID_RUMBLE) playRumble(data)
                hid2.reportError(device, BluetoothHidDevice.ERROR_RSP_SUCCESS)
            }

        }

        val result = hid.registerApp(sdp, null, null, executor, callback)
        if (!result) {
            statusMessage = "registerApp() failed — another app may be using BT HID"
            onStateChanged?.invoke()
        }
    }

    /** Bonded devices the user can tap to connect to (most recent host first). */
    fun pairedDevices(): List<BluetoothDevice> {
        val bonded = bluetoothAdapter?.bondedDevices?.toList() ?: emptyList()
        val last = layoutStore.getLastBtHost()
        return bonded.sortedByDescending { it.address == last }
    }

    /** Initiate a connection to an already-paired host. */
    fun connectTo(device: BluetoothDevice) {
        val hid = hidDevice
        if (hid == null || !isRegistered) {
            statusMessage = "Gamepad not registered yet"
            onStateChanged?.invoke()
            return
        }
        statusMessage = "Connecting to ${device.name ?: device.address}..."
        onStateChanged?.invoke()
        hid.connect(device)
    }

    private fun lastHostDevice(): BluetoothDevice? {
        val addr = layoutStore.getLastBtHost().takeIf { it.isNotEmpty() } ?: return null
        return bluetoothAdapter?.bondedDevices?.firstOrNull { it.address == addr }
    }

    fun send(message: ControllerMessage) {
        val hid = hidDevice ?: return
        val device = hostDevice ?: return
        if (!isConnected) return

        val report = ByteArray(9)

        // 14-bit button field (2 bytes)
        var buttons = 0
        for (btn in message.pressedButtons) {
            val bit = buttonBitMap[btn] ?: continue
            buttons = buttons or (1 shl bit)
        }
        report[0] = (buttons and 0xFF).toByte()
        report[1] = ((buttons shr 8) and 0xFF).toByte()

        // Hat switch from D-Pad buttons: 0=N 1=NE 2=E 3=SE 4=S 5=SW 6=W 7=NW, 8=neutral
        val up = "DPadUp" in message.pressedButtons
        val down = "DPadDown" in message.pressedButtons
        val left = "DPadLeft" in message.pressedButtons
        val right = "DPadRight" in message.pressedButtons
        report[2] = when {
            up && right -> 1
            down && right -> 3
            down && left -> 5
            up && left -> 7
            up -> 0
            right -> 2
            down -> 4
            left -> 6
            else -> HAT_NEUTRAL.toInt()
        }.toByte()

        // Sticks: -1.0..1.0 → 0..255 centered at 128 (Y down = positive, matches HID)
        report[3] = axis(message.leftStickX)
        report[4] = axis(message.leftStickY)
        report[5] = axis(message.rightStickX)
        report[6] = axis(message.rightStickY)
        report[7] = (message.leftTrigger * 255).toInt().coerceIn(0, 255).toByte()
        report[8] = (message.rightTrigger * 255).toInt().coerceIn(0, 255).toByte()

        report.copyInto(lastReport)
        hid.sendReport(device, REPORT_ID.toInt(), report)
    }

    /** data = [strong, weak], 0..255 each. */
    private fun playRumble(data: ByteArray?) {
        if (!rumbleEnabled || data == null || data.isEmpty()) return
        val strong = (data.getOrNull(0)?.toInt() ?: 0) and 0xFF
        val weak = (data.getOrNull(1)?.toInt() ?: 0) and 0xFF
        val amplitude = maxOf(strong, weak)
        if (amplitude <= 0) return
        try {
            val vib = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                    as android.os.VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
            }
            vib.vibrate(
                android.os.VibrationEffect.createOneShot(60L, amplitude.coerceIn(1, 255))
            )
        } catch (_: Exception) {}
    }

    private fun axis(v: Double): Byte = (128 + v * 127).toInt().coerceIn(0, 255).toByte()

    fun stop() {
        try { hidDevice?.unregisterApp() } catch (_: Exception) {}
        isRegistered = false
        isConnected = false
        connectedDeviceName = ""
        hostDevice = null
        try {
            bluetoothAdapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, hidDevice)
        } catch (_: Exception) {}
        hidDevice = null
    }

    companion object {
        const val REPORT_ID: Byte = 1
        const val REPORT_ID_RUMBLE: Byte = 2
        const val HAT_NEUTRAL: Byte = 8
    }
}
