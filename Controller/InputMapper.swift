//
//  InputMapper.swift
//  Controller
//
//  Maps controller inputs to keyboard/mouse events so the controller works with any game.
//  Requires Accessibility permission in System Settings > Privacy & Security > Accessibility.
//

#if os(macOS)
import Foundation
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI

// MARK: - Key Code ↔ Name

struct KeyNames {
    static let map: [CGKeyCode: String] = [
        CGKeyCode(kVK_ANSI_A): "A", CGKeyCode(kVK_ANSI_B): "B", CGKeyCode(kVK_ANSI_C): "C",
        CGKeyCode(kVK_ANSI_D): "D", CGKeyCode(kVK_ANSI_E): "E", CGKeyCode(kVK_ANSI_F): "F",
        CGKeyCode(kVK_ANSI_G): "G", CGKeyCode(kVK_ANSI_H): "H", CGKeyCode(kVK_ANSI_I): "I",
        CGKeyCode(kVK_ANSI_J): "J", CGKeyCode(kVK_ANSI_K): "K", CGKeyCode(kVK_ANSI_L): "L",
        CGKeyCode(kVK_ANSI_M): "M", CGKeyCode(kVK_ANSI_N): "N", CGKeyCode(kVK_ANSI_O): "O",
        CGKeyCode(kVK_ANSI_P): "P", CGKeyCode(kVK_ANSI_Q): "Q", CGKeyCode(kVK_ANSI_R): "R",
        CGKeyCode(kVK_ANSI_S): "S", CGKeyCode(kVK_ANSI_T): "T", CGKeyCode(kVK_ANSI_U): "U",
        CGKeyCode(kVK_ANSI_V): "V", CGKeyCode(kVK_ANSI_W): "W", CGKeyCode(kVK_ANSI_X): "X",
        CGKeyCode(kVK_ANSI_Y): "Y", CGKeyCode(kVK_ANSI_Z): "Z",
        CGKeyCode(kVK_ANSI_0): "0", CGKeyCode(kVK_ANSI_1): "1", CGKeyCode(kVK_ANSI_2): "2",
        CGKeyCode(kVK_ANSI_3): "3", CGKeyCode(kVK_ANSI_4): "4", CGKeyCode(kVK_ANSI_5): "5",
        CGKeyCode(kVK_ANSI_6): "6", CGKeyCode(kVK_ANSI_7): "7", CGKeyCode(kVK_ANSI_8): "8",
        CGKeyCode(kVK_ANSI_9): "9",
        CGKeyCode(kVK_Space): "Space", CGKeyCode(kVK_Return): "Return", CGKeyCode(kVK_Tab): "Tab",
        CGKeyCode(kVK_Escape): "Escape", CGKeyCode(kVK_Delete): "Backspace",
        CGKeyCode(kVK_Shift): "Shift", CGKeyCode(kVK_RightShift): "R-Shift",
        CGKeyCode(kVK_Control): "Ctrl", CGKeyCode(kVK_RightControl): "R-Ctrl",
        CGKeyCode(kVK_Option): "Option", CGKeyCode(kVK_RightOption): "R-Option",
        CGKeyCode(kVK_Command): "Cmd", CGKeyCode(0x36): "R-Cmd",
        CGKeyCode(kVK_UpArrow): "Up", CGKeyCode(kVK_DownArrow): "Down",
        CGKeyCode(kVK_LeftArrow): "Left", CGKeyCode(kVK_RightArrow): "Right",
        CGKeyCode(kVK_F1): "F1", CGKeyCode(kVK_F2): "F2", CGKeyCode(kVK_F3): "F3",
        CGKeyCode(kVK_F4): "F4", CGKeyCode(kVK_F5): "F5", CGKeyCode(kVK_F6): "F6",
        CGKeyCode(kVK_F7): "F7", CGKeyCode(kVK_F8): "F8", CGKeyCode(kVK_F9): "F9",
        CGKeyCode(kVK_F10): "F10", CGKeyCode(kVK_F11): "F11", CGKeyCode(kVK_F12): "F12",
        CGKeyCode(kVK_ANSI_Minus): "-", CGKeyCode(kVK_ANSI_Equal): "=",
        CGKeyCode(kVK_ANSI_LeftBracket): "[", CGKeyCode(kVK_ANSI_RightBracket): "]",
        CGKeyCode(kVK_ANSI_Semicolon): ";", CGKeyCode(kVK_ANSI_Quote): "'",
        CGKeyCode(kVK_ANSI_Comma): ",", CGKeyCode(kVK_ANSI_Period): ".",
        CGKeyCode(kVK_ANSI_Slash): "/", CGKeyCode(kVK_ANSI_Backslash): "\\",
        CGKeyCode(kVK_ANSI_Grave): "`",
    ]

    static func name(for code: CGKeyCode) -> String {
        map[code] ?? "Key\(code)"
    }

    static func code(for name: String) -> CGKeyCode? {
        map.first(where: { $0.value == name })?.key
    }
}

// MARK: - Mapping Entry

struct MappingEntry: Identifiable {
    let id: String        // storage key e.g. "cross"
    let label: String     // display name e.g. "Cross (X)"
    var keyCode: CGKeyCode
}

// MARK: - Controller Mapping

struct ControllerMapping {
    // All mappable buttons with their default key codes
    var entries: [MappingEntry] = [
        MappingEntry(id: "lstickUp", label: "L-Stick Up", keyCode: CGKeyCode(kVK_ANSI_W)),
        MappingEntry(id: "lstickDown", label: "L-Stick Down", keyCode: CGKeyCode(kVK_ANSI_S)),
        MappingEntry(id: "lstickLeft", label: "L-Stick Left", keyCode: CGKeyCode(kVK_ANSI_A)),
        MappingEntry(id: "lstickRight", label: "L-Stick Right", keyCode: CGKeyCode(kVK_ANSI_D)),
        MappingEntry(id: "dpadUp", label: "D-Pad Up", keyCode: CGKeyCode(kVK_UpArrow)),
        MappingEntry(id: "dpadDown", label: "D-Pad Down", keyCode: CGKeyCode(kVK_DownArrow)),
        MappingEntry(id: "dpadLeft", label: "D-Pad Left", keyCode: CGKeyCode(kVK_LeftArrow)),
        MappingEntry(id: "dpadRight", label: "D-Pad Right", keyCode: CGKeyCode(kVK_RightArrow)),
        MappingEntry(id: "cross", label: "Cross (X)", keyCode: CGKeyCode(kVK_Space)),
        MappingEntry(id: "circle", label: "Circle (O)", keyCode: CGKeyCode(kVK_ANSI_E)),
        MappingEntry(id: "triangle", label: "Triangle", keyCode: CGKeyCode(kVK_ANSI_Q)),
        MappingEntry(id: "square", label: "Square", keyCode: CGKeyCode(kVK_ANSI_F)),
        MappingEntry(id: "l1", label: "L1", keyCode: CGKeyCode(kVK_ANSI_1)),
        MappingEntry(id: "l2", label: "L2", keyCode: CGKeyCode(kVK_Shift)),
        MappingEntry(id: "r1", label: "R1", keyCode: CGKeyCode(kVK_ANSI_2)),
        MappingEntry(id: "r2", label: "R2", keyCode: CGKeyCode(kVK_Control)),
        MappingEntry(id: "l3", label: "L3", keyCode: CGKeyCode(kVK_ANSI_V)),
        MappingEntry(id: "r3", label: "R3", keyCode: CGKeyCode(kVK_ANSI_B)),
        MappingEntry(id: "options", label: "Options", keyCode: CGKeyCode(kVK_Escape)),
        MappingEntry(id: "create", label: "Create", keyCode: CGKeyCode(kVK_Tab)),
        MappingEntry(id: "ps", label: "PS", keyCode: CGKeyCode(kVK_ANSI_P)),
        MappingEntry(id: "touchpad", label: "Touchpad", keyCode: CGKeyCode(kVK_ANSI_M)),
    ]

    var mouseSensitivity: Double = 15.0
    var stickThreshold: Double = 0.3

    func keyCode(for id: String) -> CGKeyCode {
        entries.first(where: { $0.id == id })?.keyCode ?? 0
    }

    mutating func setKey(_ id: String, to code: CGKeyCode) {
        if let idx = entries.firstIndex(where: { $0.id == id }) {
            entries[idx].keyCode = code
        }
    }

    // MARK: - Presets

    enum Preset: String, CaseIterable, Identifiable {
        case fps = "FPS"
        case racing = "Racing"
        case platformer = "Platformer"

        var id: String { rawValue }
    }

    static func preset(_ preset: Preset) -> ControllerMapping {
        var m = ControllerMapping()
        switch preset {
        case .fps:
            // Standard FPS: WASD, mouse look, Space=jump, Shift=sprint, Ctrl=crouch
            m.setKey("lstickUp", to: CGKeyCode(kVK_ANSI_W))
            m.setKey("lstickDown", to: CGKeyCode(kVK_ANSI_S))
            m.setKey("lstickLeft", to: CGKeyCode(kVK_ANSI_A))
            m.setKey("lstickRight", to: CGKeyCode(kVK_ANSI_D))
            m.setKey("cross", to: CGKeyCode(kVK_Space))
            m.setKey("circle", to: CGKeyCode(kVK_ANSI_E))
            m.setKey("triangle", to: CGKeyCode(kVK_ANSI_Q))
            m.setKey("square", to: CGKeyCode(kVK_ANSI_F))
            m.setKey("l2", to: CGKeyCode(kVK_Shift))
            m.setKey("r2", to: CGKeyCode(kVK_Control))
            m.setKey("l1", to: CGKeyCode(kVK_ANSI_G))
            m.setKey("r1", to: CGKeyCode(kVK_ANSI_R))
            m.setKey("options", to: CGKeyCode(kVK_Escape))
            m.setKey("create", to: CGKeyCode(kVK_Tab))
            m.mouseSensitivity = 15.0

        case .racing:
            // Racing: WASD for steer/accel/brake, Shift=nitro, Space=handbrake
            m.setKey("lstickUp", to: CGKeyCode(kVK_ANSI_W))
            m.setKey("lstickDown", to: CGKeyCode(kVK_ANSI_S))
            m.setKey("lstickLeft", to: CGKeyCode(kVK_ANSI_A))
            m.setKey("lstickRight", to: CGKeyCode(kVK_ANSI_D))
            m.setKey("cross", to: CGKeyCode(kVK_Space))       // handbrake
            m.setKey("circle", to: CGKeyCode(kVK_ANSI_B))     // look back
            m.setKey("triangle", to: CGKeyCode(kVK_ANSI_Y))   // rewind
            m.setKey("square", to: CGKeyCode(kVK_ANSI_X))     // nitro
            m.setKey("l2", to: CGKeyCode(kVK_ANSI_S))         // brake (duplicate)
            m.setKey("r2", to: CGKeyCode(kVK_ANSI_W))         // accelerate (duplicate)
            m.setKey("l1", to: CGKeyCode(kVK_ANSI_Q))         // shift down
            m.setKey("r1", to: CGKeyCode(kVK_ANSI_E))         // shift up
            m.setKey("options", to: CGKeyCode(kVK_Escape))
            m.setKey("create", to: CGKeyCode(kVK_Tab))
            m.mouseSensitivity = 8.0

        case .platformer:
            // Platformer: Arrow keys for move, Z=jump, X=attack, C=special
            m.setKey("lstickUp", to: CGKeyCode(kVK_UpArrow))
            m.setKey("lstickDown", to: CGKeyCode(kVK_DownArrow))
            m.setKey("lstickLeft", to: CGKeyCode(kVK_LeftArrow))
            m.setKey("lstickRight", to: CGKeyCode(kVK_RightArrow))
            m.setKey("dpadUp", to: CGKeyCode(kVK_ANSI_W))
            m.setKey("dpadDown", to: CGKeyCode(kVK_ANSI_S))
            m.setKey("dpadLeft", to: CGKeyCode(kVK_ANSI_A))
            m.setKey("dpadRight", to: CGKeyCode(kVK_ANSI_D))
            m.setKey("cross", to: CGKeyCode(kVK_ANSI_Z))      // jump
            m.setKey("circle", to: CGKeyCode(kVK_ANSI_X))     // attack
            m.setKey("triangle", to: CGKeyCode(kVK_ANSI_C))   // special
            m.setKey("square", to: CGKeyCode(kVK_ANSI_V))     // grab
            m.setKey("l2", to: CGKeyCode(kVK_Shift))          // run
            m.setKey("r2", to: CGKeyCode(kVK_ANSI_Z))         // jump alt
            m.setKey("l1", to: CGKeyCode(kVK_ANSI_A))
            m.setKey("r1", to: CGKeyCode(kVK_ANSI_S))
            m.setKey("options", to: CGKeyCode(kVK_Escape))
            m.setKey("create", to: CGKeyCode(kVK_Return))
            m.mouseSensitivity = 10.0
        }
        return m
    }

    // MARK: - Persistence (per-slot: "current", or preset name)

    func save(slot: String = "current") {
        let defaults = UserDefaults.standard
        let prefix = "mapping_\(slot)_"
        for entry in entries {
            defaults.set(Int(entry.keyCode), forKey: "\(prefix)\(entry.id)")
        }
        defaults.set(mouseSensitivity, forKey: "\(prefix)mouseSens")
        defaults.set(stickThreshold, forKey: "\(prefix)stickThresh")
    }

    mutating func load(slot: String = "current") {
        let defaults = UserDefaults.standard
        let prefix = "mapping_\(slot)_"
        for i in entries.indices {
            let key = "\(prefix)\(entries[i].id)"
            if let val = defaults.object(forKey: key) as? Int {
                entries[i].keyCode = CGKeyCode(val)
            }
        }
        if let sens = defaults.object(forKey: "\(prefix)mouseSens") as? Double {
            mouseSensitivity = sens
        }
        if let thresh = defaults.object(forKey: "\(prefix)stickThresh") as? Double {
            stickThreshold = thresh
        }
    }

    mutating func resetDefaults() {
        let fresh = ControllerMapping()
        entries = fresh.entries
        mouseSensitivity = fresh.mouseSensitivity
        stickThreshold = fresh.stickThreshold
        save()
    }
}

// MARK: - Controller input → mapping id

private let buttonToMappingId: [String: String] = [
    "DPadUp": "dpadUp", "DPadDown": "dpadDown", "DPadLeft": "dpadLeft", "DPadRight": "dpadRight",
    "Cross": "cross", "Circle": "circle", "Triangle": "triangle", "Square": "square",
    "L1": "l1", "L2": "l2", "R1": "r1", "R2": "r2",
    "L3": "l3", "R3": "r3",
    "Options": "options", "Create": "create", "PS": "ps", "Touchpad": "touchpad",
]

// MARK: - Input Mapper

@Observable
class InputMapper {
    var mapping = ControllerMapping()
    var isEnabled = false

    private var pressedKeys: Set<CGKeyCode> = []

    init() {
        mapping.load()
    }

    func process(_ message: ControllerMessage?) {
        guard isEnabled, let msg = message else { return }

        let buttons = Set(msg.pressedButtons)

        // Left stick → directional keys
        setKey(mapping.keyCode(for: "lstickUp"), pressed: msg.leftStickY < -mapping.stickThreshold)
        setKey(mapping.keyCode(for: "lstickDown"), pressed: msg.leftStickY > mapping.stickThreshold)
        setKey(mapping.keyCode(for: "lstickLeft"), pressed: msg.leftStickX < -mapping.stickThreshold)
        setKey(mapping.keyCode(for: "lstickRight"), pressed: msg.leftStickX > mapping.stickThreshold)

        // Buttons
        for (button, id) in buttonToMappingId {
            setKey(mapping.keyCode(for: id), pressed: buttons.contains(button))
        }

        // Right stick → mouse
        let rx = msg.rightStickX
        let ry = msg.rightStickY
        if abs(rx) > 0.1 || abs(ry) > 0.1 {
            moveMouse(dx: rx * mapping.mouseSensitivity, dy: ry * mapping.mouseSensitivity)
        }
    }

    func releaseAll() {
        for key in pressedKeys {
            postKey(key, down: false)
        }
        pressedKeys.removeAll()
    }

    // MARK: - CGEvent helpers

    private func setKey(_ keyCode: CGKeyCode, pressed: Bool) {
        let wasPressed = pressedKeys.contains(keyCode)
        if pressed && !wasPressed {
            pressedKeys.insert(keyCode)
            postKey(keyCode, down: true)
        } else if !pressed && wasPressed {
            pressedKeys.remove(keyCode)
            postKey(keyCode, down: false)
        }
    }

    private func postKey(_ keyCode: CGKeyCode, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func moveMouse(dx: Double, dy: Double) {
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let newPos = CGPoint(x: currentPos.x + dx, y: currentPos.y + dy)
        guard let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newPos, mouseButton: .left) else { return }
        moveEvent.post(tap: .cghidEventTap)
    }
}

// MARK: - Global Key Listener for Rebinding

@Observable
class KeyListener {
    var capturedKeyCode: CGKeyCode? = nil
    var isListening = false
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start() {
        stop()
        capturedKeyCode = nil
        isListening = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            if event.type == .keyDown {
                self?.capturedKeyCode = event.keyCode
                self?.stop()
            } else if event.type == .flagsChanged {
                // Capture modifier keys (Shift, Ctrl, etc.)
                let code = event.keyCode
                if code == CGKeyCode(kVK_Shift) || code == CGKeyCode(kVK_RightShift)
                    || code == CGKeyCode(kVK_Control) || code == CGKeyCode(kVK_RightControl)
                    || code == CGKeyCode(kVK_Option) || code == CGKeyCode(kVK_RightOption)
                    || code == CGKeyCode(kVK_Command) || code == 0x36 {
                    self?.capturedKeyCode = code
                    self?.stop()
                }
            }
            return nil
        }

        // Also listen globally in case the window lost focus
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.capturedKeyCode = event.keyCode
            self?.stop()
        }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        isListening = false
    }
}
#endif
