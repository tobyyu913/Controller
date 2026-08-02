package com.toby.controller

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import kotlinx.coroutines.*
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicReference

class ControllerSender(private val context: Context) {
    private var socket: Socket? = null
    private var outputStream: OutputStream? = null
    private var scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val writeLock = Any()
    private val latest = AtomicReference<ControllerMessage?>(null)
    /// Called with 0..1 when the receiver pushes a rumble level
    var onRumble: ((Double) -> Unit)? = null
    private var senderJob: Job? = null

    private var nsdManager: NsdManager? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    var mode = "wifi" // "wifi" or "cable"
    var serverHost = "" // manual server IP for wifi mode
    var isConnecting = false
        private set
    var isConnected = false
        private set
    var connectedServerName = ""
        private set
    var onStateChanged: (() -> Unit)? = null

    private var wifiLock: WifiManager.WifiLock? = null

    fun start() {
        scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        isConnecting = true
        onStateChanged?.invoke()

        // Low-latency WiFi mode: stops Android (esp. Xiaomi) from napping the radio
        // between packets, which added wake-up delay to every input burst.
        try {
            val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            wifiLock = wm?.createWifiLock(WifiManager.WIFI_MODE_FULL_LOW_LATENCY, "controller-input")
            wifiLock?.acquire()
        } catch (_: Exception) {}

        when {
            mode == "cable" -> scope.launch { connectLoop("localhost", FIXED_PORT) }
            serverHost.isNotBlank() -> scope.launch { connectLoop(serverHost, FIXED_PORT) }
            else -> startDiscovery()
        }
    }

    private suspend fun connectLoop(host: String, port: Int) {
        while (scope.isActive) {
            try {
                val s = Socket()
                s.tcpNoDelay = true // disable Nagle: send tiny controller packets immediately
                s.connect(InetSocketAddress(host, port), 3000)
                synchronized(this) {
                    socket = s
                    outputStream = s.getOutputStream()
                    isConnected = true
                    isConnecting = false
                    connectedServerName = host
                }
                onStateChanged?.invoke()

                // Send initial empty state so server has data immediately
                send(ControllerMessage(emptyList(), 0.0, 0.0, 0.0, 0.0))

                // Single ordered send pump at ~120 Hz: always transmits the LATEST
                // state, in order, on a steady clock — never one task per message
                // (unordered) and never tied to the UI frame cadence.
                senderJob?.cancel()
                senderJob = scope.launch { sendPump() }
                scope.launch { readLoop(s) }

                // Stay connected until socket is closed by send failure or stop()
                while (scope.isActive && isConnected) {
                    delay(200)
                }
            } catch (_: Exception) {
                synchronized(this) {
                    closeClient()
                    isConnecting = true
                }
                onStateChanged?.invoke()
            }
            delay(2000)
        }
    }

    // MARK: - NSD Discovery (WiFi)

    private fun startDiscovery() {
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                nsdManager?.resolveService(service, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(s: NsdServiceInfo, e: Int) {}
                    override fun onServiceResolved(s: NsdServiceInfo) {
                        val host = s.host?.hostAddress ?: return
                        val port = s.port
                        stopDiscovery()
                        scope.launch { connectLoop(host, port) }
                    }
                })
            }
            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, e: Int) {}
            override fun onStopDiscoveryFailed(type: String, e: Int) {}
        }
        nsdManager?.discoverServices("_ps5ctrl._tcp", NsdManager.PROTOCOL_DNS_SD, discoveryListener)
    }

    private fun stopDiscovery() {
        try { discoveryListener?.let { nsdManager?.stopServiceDiscovery(it) } } catch (_: Exception) {}
        discoveryListener = null
    }

    fun switchMode(newMode: String) {
        if (newMode == mode) return
        stop()
        mode = newMode
        start()
    }

    fun connectDirect(host: String) {
        stop()
        serverHost = host
        mode = "wifi"
        start()
    }

    /** Cheap and thread-safe: just records the newest state; sendPump transmits it. */
    fun send(message: ControllerMessage) {
        latest.set(message)
    }

    /** Reads frames the receiver sends back (currently just rumble levels). */
    private fun readLoop(sock: Socket) {
        try {
            val input = sock.getInputStream()
            val header = ByteArray(4)
            while (scope.isActive && isConnected) {
                var read = 0
                while (read < 4) {
                    val n = input.read(header, read, 4 - read)
                    if (n < 0) return
                    read += n
                }
                val len = ((header[0].toInt() and 0xFF) shl 24) or
                        ((header[1].toInt() and 0xFF) shl 16) or
                        ((header[2].toInt() and 0xFF) shl 8) or
                        (header[3].toInt() and 0xFF)
                if (len <= 0 || len > 65536) return
                val payload = ByteArray(len)
                read = 0
                while (read < len) {
                    val n = input.read(payload, read, len - read)
                    if (n < 0) return
                    read += n
                }
                try {
                    val obj = org.json.JSONObject(String(payload, Charsets.UTF_8))
                    if (obj.has("rumble")) onRumble?.invoke(obj.getDouble("rumble"))
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
    }

    private suspend fun sendPump() {
        while (scope.isActive && isConnected) {
            // Send unconditionally every tick: constant traffic keeps the WiFi
            // radio in active mode (no power-save wake-up latency spikes).
            val msg = latest.get()
            if (msg != null) {
                val ok = synchronized(writeLock) {
                    val os = outputStream ?: return@synchronized false
                    try {
                        os.write(msg.toFramedBytes())
                        os.flush()
                        true
                    } catch (_: Exception) {
                        closeClient()
                        false
                    }
                }
                if (!ok) {
                    onStateChanged?.invoke()
                    return
                }
            }
            // 250 Hz: matches the touch digitizer's sampling rate, so no sample
            // waits on the pump. Cheap over USB, and fine over WiFi with Nagle
            // off and the radio held in low-latency mode.
            delay(4)
        }
    }

    @Synchronized
    private fun closeClient() {
        try { outputStream?.close() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        outputStream = null
        socket = null
        isConnected = false
        connectedServerName = ""
    }

    fun stop() {
        stopDiscovery()
        scope.cancel()
        closeClient()
        isConnecting = false
        try { wifiLock?.release() } catch (_: Exception) {}
        wifiLock = null
    }

    fun getLocalIP(): String {
        try {
            val interfaces = java.net.NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val iface = interfaces.nextElement()
                val addrs = iface.inetAddresses
                while (addrs.hasMoreElements()) {
                    val addr = addrs.nextElement()
                    if (!addr.isLoopbackAddress && addr is java.net.Inet4Address) {
                        return addr.hostAddress ?: "?"
                    }
                }
            }
        } catch (_: Exception) {}
        return "?"
    }

    companion object {
        const val FIXED_PORT = 9876
    }
}
