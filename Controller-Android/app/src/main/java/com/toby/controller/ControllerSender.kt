package com.toby.controller

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.*
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

class ControllerSender(private val context: Context) {
    private var socket: Socket? = null
    private var outputStream: OutputStream? = null
    private var scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val writeLock = Any()

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

    fun start() {
        scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        isConnecting = true
        onStateChanged?.invoke()

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

    fun send(message: ControllerMessage) {
        if (outputStream == null) return
        scope.launch {
            synchronized(writeLock) {
                val os = outputStream ?: return@launch
                try {
                    os.write(message.toFramedBytes())
                    os.flush()
                } catch (_: Exception) {
                    closeClient()
                    onStateChanged?.invoke()
                }
            }
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
