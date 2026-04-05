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

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) -> ControllerMessage? {
        try? JSONDecoder().decode(ControllerMessage.self, from: data)
    }
}
