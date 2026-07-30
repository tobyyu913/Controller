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
import AppKit

// CGCursorIsVisible was dropped from the SDK headers but the symbol still exists
// in CoreGraphics; games hide the cursor in camera mode, which is our signal to
// pin the pointer and send pure deltas.
@_silgen_name("CGCursorIsVisible")
private func CG_CursorIsVisible() -> boolean_t

// MARK: - Mouse button pseudo key codes
// Sentinel values far above any real CGKeyCode; postKey turns them into mouse clicks.

enum MouseCode {
    static let left: CGKeyCode = 0xF001
    static let right: CGKeyCode = 0xF002
    static let middle: CGKeyCode = 0xF003
}

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
        MouseCode.left: "Mouse L", MouseCode.right: "Mouse R", MouseCode.middle: "Mouse M",
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
    /// Camera smoothing time constant in seconds. Larger = smoother but more
    /// floaty; 0.001 is effectively off.
    var smoothing: Double = 0.030

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
        case wuwa = "WuWa"

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

        case .wuwa:
            // Wuthering Waves — mirrors the game's own PS5 layout on its PC keybinds:
            // Square=attack, Triangle=skill, R1=dash, R2=liberation, L1=echo,
            // D-Pad=switch resonators, R3=target lock
            m.setKey("lstickUp", to: CGKeyCode(kVK_ANSI_W))
            m.setKey("lstickDown", to: CGKeyCode(kVK_ANSI_S))
            m.setKey("lstickLeft", to: CGKeyCode(kVK_ANSI_A))
            m.setKey("lstickRight", to: CGKeyCode(kVK_ANSI_D))
            m.setKey("square", to: MouseCode.left)             // normal attack
            m.setKey("cross", to: CGKeyCode(kVK_Space))        // jump
            m.setKey("circle", to: CGKeyCode(kVK_ANSI_F))      // interact (O on PS5)
            m.setKey("triangle", to: CGKeyCode(kVK_ANSI_E))    // resonance skill
            m.setKey("r1", to: CGKeyCode(kVK_Shift))           // dash/dodge
            m.setKey("r2", to: CGKeyCode(kVK_ANSI_R))          // resonance liberation
            m.setKey("l1", to: CGKeyCode(kVK_ANSI_Q))          // echo skill
            m.setKey("l2", to: CGKeyCode(kVK_ANSI_T))          // utility (grapple etc.)
            m.setKey("l3", to: CGKeyCode(kVK_Control))         // walk toggle
            m.setKey("r3", to: MouseCode.middle)               // target lock
            m.setKey("dpadUp", to: CGKeyCode(kVK_ANSI_1))      // resonator 1
            m.setKey("dpadLeft", to: CGKeyCode(kVK_ANSI_2))    // resonator 2
            m.setKey("dpadRight", to: CGKeyCode(kVK_ANSI_3))   // resonator 3
            m.setKey("dpadDown", to: CGKeyCode(kVK_ANSI_4))    // resonator 4
            m.setKey("create", to: CGKeyCode(kVK_Tab))         // utilities wheel
            m.setKey("options", to: CGKeyCode(kVK_Escape))     // menu
            m.setKey("ps", to: CGKeyCode(kVK_ANSI_M))          // map
            m.setKey("touchpad", to: CGKeyCode(kVK_ANSI_B))    // backpack
            m.mouseSensitivity = 15.0
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
        defaults.set(smoothing, forKey: "\(prefix)smoothing")
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
        if let s = defaults.object(forKey: "\(prefix)smoothing") as? Double {
            smoothing = s
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
    /// WuWa mode: post events straight into the frontmost game's process
    /// (CGEvent.postToPid), bypassing system-wide pointer routing entirely.
    var gameInjectionMode = UserDefaults.standard.bool(forKey: "gameInjectionMode")
    /// Route mouse motion through the virtual HID device (real hardware path)
    /// instead of synthetic CGEvents.
    var virtualMouseMode = UserDefaults.standard.bool(forKey: "virtualMouseMode")
    @ObservationIgnored private var targetPid: pid_t = 0

    @ObservationIgnored private var pressedKeys: Set<CGKeyCode> = []
    @ObservationIgnored private var rightX = 0.0
    @ObservationIgnored private var rightY = 0.0
    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var tickStopped = false
    // HID-system event source: synthetic events indistinguishable from hardware
    // for games that filter by source state
    @ObservationIgnored private let eventSource = CGEventSource(stateID: .hidSystemState)
    @ObservationIgnored private var activityToken: NSObjectProtocol?

    /// While mapping is on, hold a latency-critical activity assertion. Without it,
    /// App Nap throttles our timers ~1s after the game occludes this app — camera
    /// was buttery for exactly that first second, then coalesced into laggy batches.
    func updateActivityAssertion() {
        if isEnabled, activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "Low-latency controller input"
            )
        } else if !isEnabled, let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    init() {
        mapping.load()
        startTickThread()
    }

    deinit {
        tickStopped = true
    }

    /// Camera loop on a REAL-TIME thread (same scheduling class as pro audio).
    /// Ordinary background-app threads get starved when a game saturates the
    /// machine — that read as camera stutter that vanished for ~1s whenever the
    /// app was touched. Time-constraint scheduling guarantees our 8ms cadence
    /// regardless of app frontmost state or system load.
    private func startTickThread() {
        let thread = Thread { [weak self] in
            var tbinfo = mach_timebase_info_data_t()
            mach_timebase_info(&tbinfo)
            let nsPerTick = Double(tbinfo.numer) / Double(tbinfo.denom)

            // 1000 Hz — matches a gaming mouse's report rate, so each rendered
            // frame receives a consistent slice of motion instead of an uneven
            // 1-2-3 reports/frame beat against the game's frame rate.
            var policy = thread_time_constraint_policy(
                period: UInt32(1_000_000 / nsPerTick),        // every 1ms
                computation: UInt32(200_000 / nsPerTick),     // ~0.2ms of work
                constraint: UInt32(500_000 / nsPerTick),      // finish within 0.5ms
                preemptible: 1
            )
            let count = mach_msg_type_number_t(
                MemoryLayout<thread_time_constraint_policy>.size / MemoryLayout<integer_t>.size)
            withUnsafeMutablePointer(to: &policy) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                    _ = thread_policy_set(mach_thread_self(),
                                          thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY),
                                          intPtr, count)
                }
            }

            let step = UInt64(1_000_000 / nsPerTick)
            var next = mach_absolute_time()
            while true {
                guard let self, !self.tickStopped else { break }
                self.mouseTick()
                next += step
                mach_wait_until(next)
            }
        }
        thread.name = "controller.mouse.rt"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    @ObservationIgnored private var cachedPos = CGPoint.zero
    @ObservationIgnored private var cachedCenter = CGPoint.zero
    @ObservationIgnored private var cursorHidden = false
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var carryX = 0.0
    @ObservationIgnored private var carryY = 0.0
    @ObservationIgnored private var smoothX = 0.0
    @ObservationIgnored private var smoothY = 0.0

    private func mouseTick() {
        guard isEnabled else { return }
        lock.lock()
        let rx = rightX
        let ry = rightY
        let heldLeft = pressedKeys.contains(MouseCode.left)
        let heldRight = pressedKeys.contains(MouseCode.right)
        lock.unlock()

        // The tick thread runs at 1000 Hz for the HID path; CGEvents are posted at
        // 125 Hz (flooding the event system does not help and costs CPU).
        let hidPath = virtualMouseMode
        tickCount += 1
        if !hidPath && tickCount % 8 != 0 { return }

        // Query the window system RARELY (every ~200ms), never per tick: synchronous
        // queries stall randomly while the GPU is loaded, clumping our event stream.
        if tickCount % 200 == 1 {
            cursorHidden = CG_CursorIsVisible() == 0
            if !cursorHidden || cachedPos == .zero {
                cachedPos = CGEvent(source: nil)?.location ?? cachedPos
            }
            let b = displayBounds(for: cachedPos)
            cachedCenter = CGPoint(x: b.midX, y: b.midY)
            // Track the frontmost app for WuWa/injection mode (never ourselves)
            DispatchQueue.main.async { [weak self] in
                if let app = NSWorkspace.shared.frontmostApplication,
                   app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    self?.targetPid = app.processIdentifier
                }
            }
        }

        // A thumb on glass is sampled far more coarsely than a mouse sensor, and
        // packets arrive with jitter (measured p50 8ms / p99 22ms). Feeding those
        // steps straight through makes velocity jump every packet. Ease the stick
        // value toward its target with a time constant instead: the camera keeps
        // moving smoothly between samples and gaps stop being visible.
        let dt = hidPath ? 0.001 : 0.008
        let tau = max(0.001, mapping.smoothing)
        let alpha = 1 - exp(-dt / tau)
        smoothX += (rx - smoothX) * alpha
        smoothY += (ry - smoothY) * alpha

        // Deadzone on the target, but let the smoothed value coast to a stop
        if abs(rx) < 0.1 && abs(ry) < 0.1 && abs(smoothX) < 0.004 && abs(smoothY) < 0.004 {
            smoothX = 0
            smoothY = 0
            carryX = 0
            carryY = 0
            return
        }

        // Sensitivity is calibrated as pixels per 1/60s frame; convert to this tick's
        // share. Fractional remainders carry over so slow pans don't quantize.
        let perTick = mapping.mouseSensitivity * 60.0 / (hidPath ? 1000.0 : 125.0)
        carryX += smoothX * perTick
        carryY += smoothY * perTick
        let ix = Int64(carryX.rounded())
        let iy = Int64(carryY.rounded())
        carryX -= Double(ix)
        carryY -= Double(iy)
        if ix != 0 || iy != 0 {
            if virtualMouseMode {
                lock.lock()
                let heldMiddle = pressedKeys.contains(MouseCode.middle)
                lock.unlock()
                var btns = 0
                if heldLeft { btns |= 1 }
                if heldRight { btns |= 2 }
                if heldMiddle { btns |= 4 }
                VirtualMouse.shared.send(buttons: btns, dx: Int(ix), dy: Int(iy))
            } else {
                moveMouse(ix: ix, iy: iy, heldLeft: heldLeft, heldRight: heldRight)
            }
        }
    }

    /// Thread-safe: called from the network queue (hot path), not the main thread.
    func process(_ message: ControllerMessage?) {
        guard isEnabled, let msg = message else { return }

        let buttons = Set(msg.pressedButtons)

        lock.lock()
        defer { lock.unlock() }

        // Left stick → directional keys
        setKey(mapping.keyCode(for: "lstickUp"), pressed: msg.leftStickY < -mapping.stickThreshold)
        setKey(mapping.keyCode(for: "lstickDown"), pressed: msg.leftStickY > mapping.stickThreshold)
        setKey(mapping.keyCode(for: "lstickLeft"), pressed: msg.leftStickX < -mapping.stickThreshold)
        setKey(mapping.keyCode(for: "lstickRight"), pressed: msg.leftStickX > mapping.stickThreshold)

        // Buttons
        for (button, id) in buttonToMappingId {
            setKey(mapping.keyCode(for: id), pressed: buttons.contains(button))
        }

        // Right stick → remembered for the mouse loop
        rightX = msg.rightStickX
        rightY = msg.rightStickY
    }

    func releaseAll() {
        lock.lock()
        defer { lock.unlock() }
        for key in pressedKeys {
            postKey(key, down: false)
        }
        pressedKeys.removeAll()
        rightX = 0
        rightY = 0
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
        // Mouse button pseudo-codes → click at the current cursor position
        let mouse: (type: CGEventType, button: CGMouseButton)?
        switch keyCode {
        case MouseCode.left: mouse = (down ? .leftMouseDown : .leftMouseUp, .left)
        case MouseCode.right: mouse = (down ? .rightMouseDown : .rightMouseUp, .right)
        case MouseCode.middle: mouse = (down ? .otherMouseDown : .otherMouseUp, .center)
        default: mouse = nil
        }
        // Virtual mouse mode: clicks ride the HID device too (button state, no motion)
        if virtualMouseMode, keyCode == MouseCode.left || keyCode == MouseCode.right || keyCode == MouseCode.middle {
            var btns = 0
            if pressedKeys.contains(MouseCode.left) { btns |= 1 }
            if pressedKeys.contains(MouseCode.right) { btns |= 2 }
            if pressedKeys.contains(MouseCode.middle) { btns |= 4 }
            VirtualMouse.shared.send(buttons: btns, dx: 0, dy: 0)
            return
        }

        if let mouse {
            let pos = cursorHidden && cachedCenter != .zero
                ? cachedCenter
                : (CGEvent(source: nil)?.location ?? .zero)
            guard let event = CGEvent(mouseEventSource: eventSource, mouseType: mouse.type, mouseCursorPosition: pos, mouseButton: mouse.button) else { return }
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.timestamp = CGEventTimestamp(DispatchTime.now().uptimeNanoseconds)
            postEvent(event)
            return
        }
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: down) else { return }
        event.timestamp = CGEventTimestamp(DispatchTime.now().uptimeNanoseconds)
        postEvent(event)
    }

    private func moveMouse(ix: Int64, iy: Int64, heldLeft: Bool, heldRight: Bool) {
        // Captured games hold the hidden cursor at display center (re-warping it
        // constantly). Pin there too so our position writes and the game's warps
        // agree instead of fighting 120x/s.
        var newPos = cursorHidden && cachedCenter != .zero ? cachedCenter : cachedPos

        if !cursorHidden {
            // Cursor visible (desktop / game menus): move the pointer normally,
            // stopping at the display edge exactly like a real mouse.
            let bounds = displayBounds(for: cachedPos)
            newPos = CGPoint(x: cachedPos.x + Double(ix), y: cachedPos.y + Double(iy))
            newPos.x = min(max(newPos.x, bounds.minX), bounds.maxX - 1)
            newPos.y = min(max(newPos.y, bounds.minY), bounds.maxY - 1)
            cachedPos = newPos
        }
        // Cursor hidden = game camera mode: PIN the pointer at cachedPos — it never
        // travels, never hits an edge — the delta fields carry all the motion.

        // While a mouse button is held, real mice emit *dragged* events, not moves
        let type: CGEventType
        let button: CGMouseButton
        if heldLeft {
            type = .leftMouseDragged; button = .left
        } else if heldRight {
            type = .rightMouseDragged; button = .right
        } else {
            type = .mouseMoved; button = .left
        }

        guard let moveEvent = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: newPos, mouseButton: button) else { return }
        // Games lock the cursor and read RELATIVE deltas — position alone is invisible to them
        moveEvent.setIntegerValueField(.mouseEventDeltaX, value: ix)
        moveEvent.setIntegerValueField(.mouseEventDeltaY, value: iy)
        // Real mice carry hardware timestamps; engines weight camera velocity by them
        moveEvent.timestamp = CGEventTimestamp(DispatchTime.now().uptimeNanoseconds)
        postEvent(moveEvent)
    }

    /// System-wide post by default; WuWa mode injects straight into the game's pid.
    private func postEvent(_ event: CGEvent) {
        if gameInjectionMode, targetPid > 0 {
            event.postToPid(targetPid)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    private func displayBounds(for point: CGPoint) -> CGRect {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        if CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 {
            return CGDisplayBounds(display)
        }
        return CGDisplayBounds(CGMainDisplayID())
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
