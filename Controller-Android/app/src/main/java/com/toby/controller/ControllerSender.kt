package com.toby.controller

import kotlinx.coroutines.*
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket

class ControllerSender {
    private var serverSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private var outputStream: OutputStream? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    var isListening = false
        private set
    var isConnected = false
        private set
    var onStateChanged: (() -> Unit)? = null

    fun start() {
        scope.launch {
            try {
                val socket = ServerSocket(FIXED_PORT)
                socket.reuseAddress = true
                serverSocket = socket
                isListening = true
                onStateChanged?.invoke()

                // Accept loop — always ready for a new connection
                while (isActive) {
                    try {
                        val client = socket.accept()
                        // Close any previous connection
                        closeClient()
                        clientSocket = client
                        outputStream = client.getOutputStream()
                        isConnected = true
                        onStateChanged?.invoke()

                        // Wait until this client disconnects
                        // We detect disconnection in send() which calls closeClient()
                        while (isActive && isConnected) {
                            delay(200)
                        }
                    } catch (_: Exception) {
                        // accept() failed or was interrupted
                    }
                    closeClient()
                    onStateChanged?.invoke()
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    fun send(message: ControllerMessage) {
        val stream = outputStream ?: return
        scope.launch {
            try {
                val data = message.toFramedBytes()
                stream.write(data)
                stream.flush()
            } catch (_: Exception) {
                // Write failed — connection is dead, close so accept loop restarts
                closeClient()
                onStateChanged?.invoke()
            }
        }
    }

    @Synchronized
    private fun closeClient() {
        try { outputStream?.close() } catch (_: Exception) {}
        try { clientSocket?.close() } catch (_: Exception) {}
        outputStream = null
        clientSocket = null
        isConnected = false
    }

    fun stop() {
        scope.cancel()
        closeClient()
        try { serverSocket?.close() } catch (_: Exception) {}
        serverSocket = null
        isListening = false
    }

    companion object {
        const val FIXED_PORT = 9876
    }
}
