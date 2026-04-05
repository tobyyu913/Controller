package com.toby.controller

import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder

data class ControllerMessage(
    val pressedButtons: List<String>,
    val leftStickX: Double,
    val leftStickY: Double,
    val rightStickX: Double,
    val rightStickY: Double,
) {
    fun toFramedBytes(): ByteArray {
        val json = JSONObject().apply {
            put("pressedButtons", JSONArray(pressedButtons))
            put("leftStickX", leftStickX)
            put("leftStickY", leftStickY)
            put("rightStickX", rightStickX)
            put("rightStickY", rightStickY)
        }
        val payload = json.toString().toByteArray(Charsets.UTF_8)
        val frame = ByteBuffer.allocate(4 + payload.size)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(payload.size)
            .put(payload)
        return frame.array()
    }
}
