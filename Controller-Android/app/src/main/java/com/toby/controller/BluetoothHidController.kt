package com.toby.controller

import android.annotation.SuppressLint
import android.bluetooth.*
import android.content.Context
import java.util.concurrent.Executors

@SuppressLint("MissingPermission")
class BluetoothHidController(private val context: Context) {

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
    var onStateChanged: (() -> Unit)? = null

    // HID Report Descriptor: standard gamepad
    // 16 buttons + 4 axes (left stick X/Y, right stick Rx/Ry)
    // Total report size: 6 bytes
    private val hidDescriptor = byteArrayOf(
        0x05, 0x01,                    // Usage Page (Generic Desktop)
        0x09, 0x05,                    // Usage (Gamepad)
        0xA1.toByte(), 0x01,           // Collection (Application)

        // 16 Buttons
        0x05, 0x09,                    //   Usage Page (Button)
        0x19, 0x01,                    //   Usage Minimum (1)
        0x29, 0x10,                    //   Usage Maximum (16)
        0x15, 0x00,                    //   Logical Minimum (0)
        0x25, 0x01,                    //   Logical Maximum (1)
        0x95.toByte(), 0x10,           //   Report Count (16)
        0x75, 0x01,                    //   Report Size (1)
        0x81.toByte(), 0x02,           //   Input (Data, Variable, Absolute)

        // Left Stick (X, Y)
        0x05, 0x01,                    //   Usage Page (Generic Desktop)
        0x09, 0x30,                    //   Usage (X)
        0x09, 0x31,                    //   Usage (Y)
        0x15, 0x81.toByte(),           //   Logical Minimum (-127)
        0x25, 0x7F,                    //   Logical Maximum (127)
        0x95.toByte(), 0x02,           //   Report Count (2)
        0x75, 0x08,                    //   Report Size (8)
        0x81.toByte(), 0x02,           //   Input (Data, Variable, Absolute)

        // Right Stick (Rx, Ry)
        0x09, 0x33,                    //   Usage (Rx)
        0x09, 0x34,                    //   Usage (Ry)
        0x95.toByte(), 0x02,           //   Report Count (2)
        0x75, 0x08,                    //   Report Size (8)
        0x81.toByte(), 0x02,           //   Input (Data, Variable, Absolute)

        0xC0.toByte()                  // End Collection
    )

    // Button name → bit position in the 16-bit button field
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
        "DPadUp" to 12,
        "DPadDown" to 13,
        "DPadLeft" to 14,
        "DPadRight" to 15,
    )

    fun start() {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return
        bluetoothAdapter = manager.adapter ?: return

        if (bluetoothAdapter?.isEnabled != true) return

        bluetoothAdapter?.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile?) {
                if (profile == BluetoothProfile.HID_DEVICE) {
                    hidDevice = proxy as? BluetoothHidDevice
                    registerHidDevice()
                }
            }

            override fun onServiceDisconnected(profile: Int) {
                if (profile == BluetoothProfile.HID_DEVICE) {
                    hidDevice = null
                    isRegistered = false
                    isConnected = false
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
                onStateChanged?.invoke()
            }

            override fun onConnectionStateChanged(device: BluetoothDevice?, state: Int) {
                when (state) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        hostDevice = device
                        isConnected = true
                        connectedDeviceName = device?.name ?: device?.address ?: "device"
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        hostDevice = null
                        isConnected = false
                        connectedDeviceName = ""
                    }
                }
                onStateChanged?.invoke()
            }
        }

        hid.registerApp(sdp, null, null, executor, callback)
    }

    fun send(message: ControllerMessage) {
        val hid = hidDevice ?: return
        val device = hostDevice ?: return
        if (!isConnected) return

        // Build 6-byte HID report: [buttons_lo][buttons_hi][lx][ly][rx][ry]
        val report = ByteArray(6)

        // 16-bit button field
        var buttons = 0
        for (btn in message.pressedButtons) {
            val bit = buttonBitMap[btn] ?: continue
            buttons = buttons or (1 shl bit)
        }
        report[0] = (buttons and 0xFF).toByte()
        report[1] = ((buttons shr 8) and 0xFF).toByte()

        // Analog sticks: map -1.0..1.0 to -127..127
        report[2] = (message.leftStickX * 127).toInt().coerceIn(-127, 127).toByte()
        report[3] = (message.leftStickY * 127).toInt().coerceIn(-127, 127).toByte()
        report[4] = (message.rightStickX * 127).toInt().coerceIn(-127, 127).toByte()
        report[5] = (message.rightStickY * 127).toInt().coerceIn(-127, 127).toByte()

        hid.sendReport(device, 0, report)
    }

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
}
