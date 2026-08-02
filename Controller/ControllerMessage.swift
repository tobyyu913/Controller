//
//  ControllerMessage.swift
//  Controller
//
//  Shared model for controller state sent over the network.
//

import Foundation

struct ControllerMessage: Codable {
    var pressedButtons: [String]
    var leftStickX: Double
    var leftStickY: Double
    var rightStickX: Double
    var rightStickY: Double
    /// Analog trigger pull, 0...1. Absent from older senders, hence the default.
    var leftTrigger: Double = 0
    var rightTrigger: Double = 0

    enum CodingKeys: String, CodingKey {
        case pressedButtons, leftStickX, leftStickY, rightStickX, rightStickY
        case leftTrigger, rightTrigger
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pressedButtons = try c.decode([String].self, forKey: .pressedButtons)
        leftStickX = try c.decode(Double.self, forKey: .leftStickX)
        leftStickY = try c.decode(Double.self, forKey: .leftStickY)
        rightStickX = try c.decode(Double.self, forKey: .rightStickX)
        rightStickY = try c.decode(Double.self, forKey: .rightStickY)
        leftTrigger = try c.decodeIfPresent(Double.self, forKey: .leftTrigger) ?? 0
        rightTrigger = try c.decodeIfPresent(Double.self, forKey: .rightTrigger) ?? 0
    }

    init(pressedButtons: [String], leftStickX: Double, leftStickY: Double,
         rightStickX: Double, rightStickY: Double,
         leftTrigger: Double = 0, rightTrigger: Double = 0) {
        self.pressedButtons = pressedButtons
        self.leftStickX = leftStickX
        self.leftStickY = leftStickY
        self.rightStickX = rightStickX
        self.rightStickY = rightStickY
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) -> ControllerMessage? {
        try? JSONDecoder().decode(ControllerMessage.self, from: data)
    }
}
