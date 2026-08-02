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
    val leftTrigger: Double = 0.0,    // analog L2, 0..1
    val rightTrigger: Double = 0.0,   // analog R2, 0..1
) {
    fun toFramedBytes(): ByteArray {
        val json = JSONObject().apply {
            put("pressedButtons", JSONArray(pressedButtons))
            put("leftStickX", leftStickX)
            put("leftStickY", leftStickY)
            put("rightStickX", rightStickX)
            put("rightStickY", rightStickY)
            put("leftTrigger", leftTrigger)
            put("rightTrigger", rightTrigger)
        }
        val payload = json.toString().toByteArray(Charsets.UTF_8)
        val frame = ByteBuffer.allocate(4 + payload.size)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(payload.size)
            .put(payload)
        return frame.array()
    }
}
