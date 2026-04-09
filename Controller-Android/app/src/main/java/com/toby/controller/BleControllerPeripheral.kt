package com.toby.controller

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import java.util.UUID

/**
 * BLE peripheral that advertises a custom GATT service for controller input.
 * The iPad (or any BLE central) can connect and subscribe to notifications
 * to receive controller state in real time.
 *
 * Service UUID: 0000FE00-0000-1000-8000-00805F9B34FB
 * Characteristic UUID: 0000FE01-0000-1000-8000-00805F9B34FB
 * Data format: same 6-byte HID report (2 bytes buttons + 4 bytes sticks)
 */
@SuppressLint("MissingPermission")
class BleControllerPeripheral(private val context: Context) {

    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("0000FE00-0000-1000-8000-00805F9B34FB")
        val CHAR_UUID: UUID = UUID.fromString("0000FE01-0000-1000-8000-00805F9B34FB")
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805F9B34FB")
    }

    private var bluetoothManager: BluetoothManager? = null
    private var gattServer: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var controllerChar: BluetoothGattCharacteristic? = null
    private val connectedDevices = mutableSetOf<BluetoothDevice>()

    var isAdvertising = false
        private set
    var isConnected = false
        private set
    var connectedDeviceName = ""
        private set
    var statusMessage = ""
        private set
    var onStateChanged: (() -> Unit)? = null

    private val buttonBitMap = mapOf(
        "Cross" to 0, "Circle" to 1, "Square" to 2, "Triangle" to 3,
        "L1" to 4, "R1" to 5, "L2" to 6, "R2" to 7,
        "Create" to 8, "Options" to 9, "L3" to 10, "R3" to 11,
        "DPadUp" to 12, "DPadDown" to 13, "DPadLeft" to 14, "DPadRight" to 15,
    )

    fun start() {
        bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = bluetoothManager?.adapter
        if (adapter == null || !adapter.isEnabled) {
            statusMessage = "Bluetooth is OFF"
            onStateChanged?.invoke()
            return
        }

        advertiser = adapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            statusMessage = "BLE advertising not supported"
            onStateChanged?.invoke()
            return
        }

        statusMessage = "Starting GATT server..."
        onStateChanged?.invoke()

        setupGattServer()
        startAdvertising()
    }

    private fun setupGattServer() {
        val callback = object : BluetoothGattServerCallback() {
            override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED && device != null) {
                    connectedDevices.add(device)
                    isConnected = true
                    connectedDeviceName = device.name ?: device.address
                    statusMessage = "Connected: $connectedDeviceName"
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED && device != null) {
                    connectedDevices.remove(device)
                    isConnected = connectedDevices.isNotEmpty()
                    connectedDeviceName = if (isConnected) connectedDevices.first().let { it.name ?: it.address } else ""
                    statusMessage = if (isConnected) "Connected: $connectedDeviceName" else "Waiting for connection..."
                }
                onStateChanged?.invoke()
            }

            override fun onDescriptorWriteRequest(device: BluetoothDevice?, requestId: Int, descriptor: BluetoothGattDescriptor?, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?) {
                // Client enabling/disabling notifications
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
                }
            }

            override fun onCharacteristicReadRequest(device: BluetoothDevice?, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic?) {
                if (characteristic?.uuid == CHAR_UUID) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, characteristic.value ?: ByteArray(6))
                }
            }
        }

        gattServer = bluetoothManager?.openGattServer(context, callback)

        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        controllerChar = BluetoothGattCharacteristic(
            CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or
                BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        )

        // Client Characteristic Configuration Descriptor (for notifications)
        val cccd = BluetoothGattDescriptor(
            CCCD_UUID,
            BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
        )
        controllerChar?.addDescriptor(cccd)

        service.addCharacteristic(controllerChar)
        gattServer?.addService(service)
    }

    private fun startAdvertising() {
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()

        advertiser?.startAdvertising(settings, data, object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                isAdvertising = true
                statusMessage = "BLE advertising — waiting for connection..."
                onStateChanged?.invoke()
            }

            override fun onStartFailure(errorCode: Int) {
                isAdvertising = false
                statusMessage = "BLE advertise failed: error $errorCode"
                onStateChanged?.invoke()
            }
        })
    }

    fun send(message: ControllerMessage) {
        val char = controllerChar ?: return
        if (connectedDevices.isEmpty()) return

        val report = ByteArray(6)
        var buttons = 0
        for (btn in message.pressedButtons) {
            val bit = buttonBitMap[btn] ?: continue
            buttons = buttons or (1 shl bit)
        }
        report[0] = (buttons and 0xFF).toByte()
        report[1] = ((buttons shr 8) and 0xFF).toByte()
        report[2] = (message.leftStickX * 127).toInt().coerceIn(-127, 127).toByte()
        report[3] = (message.leftStickY * 127).toInt().coerceIn(-127, 127).toByte()
        report[4] = (message.rightStickX * 127).toInt().coerceIn(-127, 127).toByte()
        report[5] = (message.rightStickY * 127).toInt().coerceIn(-127, 127).toByte()

        char.value = report
        for (device in connectedDevices.toList()) {
            try {
                gattServer?.notifyCharacteristicChanged(device, char, false)
            } catch (_: Exception) {}
        }
    }

    fun stop() {
        try { advertiser?.stopAdvertising(null) } catch (_: Exception) {}
        try { gattServer?.close() } catch (_: Exception) {}
        gattServer = null
        advertiser = null
        connectedDevices.clear()
        isAdvertising = false
        isConnected = false
        connectedDeviceName = ""
        statusMessage = "Stopped"
        onStateChanged?.invoke()
    }
}
