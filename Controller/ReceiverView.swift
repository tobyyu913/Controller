//
//  ReceiverView.swift
//  Controller
//
//  macOS receiver: shows live controller input from the connected iPhone.
//

#if os(macOS)
import SwiftUI

struct ReceiverView: View {
    @State private var receiver = ControllerReceiver()

    var body: some View {
        VStack(spacing: 20) {
            // Connection status
            HStack(spacing: 8) {
                Circle()
                    .fill(receiver.connectedPeer != nil ? .green : (receiver.isSearching ? .orange : .gray))
                    .frame(width: 10, height: 10)
                Text(statusText)
                    .font(.system(.body, design: .monospaced))
            }

            Divider()

            if let msg = receiver.latestMessage {
                HStack(alignment: .top, spacing: 40) {
                    // Left side
                    VStack(alignment: .leading, spacing: 12) {
                        stickDisplay(label: "L Stick", x: msg.leftStickX, y: msg.leftStickY)
                        buttonGroup(title: "Triggers", buttons: ["L1", "L2"], pressed: msg.pressedButtons)
                        buttonGroup(title: "D-Pad", buttons: ["DPadUp", "DPadDown", "DPadLeft", "DPadRight"], pressed: msg.pressedButtons)
                    }

                    // Center
                    VStack(spacing: 12) {
                        buttonGroup(title: "System", buttons: ["Create", "Options", "PS", "Touchpad"], pressed: msg.pressedButtons)
                        liveControllerVisual(msg: msg)
                    }

                    // Right side
                    VStack(alignment: .leading, spacing: 12) {
                        stickDisplay(label: "R Stick", x: msg.rightStickX, y: msg.rightStickY)
                        buttonGroup(title: "Triggers", buttons: ["R1", "R2"], pressed: msg.pressedButtons)
                        buttonGroup(title: "Face", buttons: ["Triangle", "Circle", "Cross", "Square"], pressed: msg.pressedButtons)
                    }
                }
                .padding()
            } else {
                ContentUnavailableView(
                    "Waiting for Controller",
                    systemImage: "gamecontroller",
                    description: Text("Open the Controller app on your iPhone.\nMake sure both devices are on the same network.")
                )
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
        .onAppear { receiver.start() }
        .onDisappear { receiver.stop() }
    }

    private var statusText: String {
        if let peer = receiver.connectedPeer {
            let method = receiver.connectionMethod ?? "Unknown"
            return "Connected via \(method): \(peer)"
        } else if receiver.isSearching {
            return "Searching for USB controller..."
        } else {
            return "Offline"
        }
    }

    // MARK: - Sub-views

    private func stickDisplay(label: String, x: Double, y: Double) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption.bold())
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    .frame(width: 60, height: 60)
                // Crosshair
                Path { path in
                    path.move(to: CGPoint(x: 30, y: 0))
                    path.addLine(to: CGPoint(x: 30, y: 60))
                    path.move(to: CGPoint(x: 0, y: 30))
                    path.addLine(to: CGPoint(x: 60, y: 30))
                }
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
                .frame(width: 60, height: 60)
                // Stick position
                Circle()
                    .fill(Color.blue)
                    .frame(width: 12, height: 12)
                    .offset(x: x * 25, y: y * 25)
            }
            Text(String(format: "%.1f, %.1f", x, y))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func buttonGroup(title: String, buttons: [String], pressed: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold())
            FlowLayout(spacing: 4) {
                ForEach(buttons, id: \.self) { btn in
                    let isPressed = pressed.contains(btn)
                    Text(shortName(btn))
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isPressed ? Color.blue : Color.gray.opacity(0.15))
                        )
                        .foregroundStyle(isPressed ? .white : .primary)
                }
            }
        }
    }

    private func shortName(_ name: String) -> String {
        switch name {
        case "DPadUp": return "Up"
        case "DPadDown": return "Down"
        case "DPadLeft": return "Left"
        case "DPadRight": return "Right"
        case "Triangle": return "\u{25B3}"
        case "Circle": return "\u{25CB}"
        case "Cross": return "\u{2715}"
        case "Square": return "\u{25A1}"
        default: return name
        }
    }

    private func liveControllerVisual(msg: ControllerMessage) -> some View {
        // Mini visual controller
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.08))
                .frame(width: 200, height: 100)

            // Left stick dot
            Circle()
                .fill(Color.blue.opacity(0.7))
                .frame(width: 10, height: 10)
                .offset(x: -55 + msg.leftStickX * 15, y: 15 + msg.leftStickY * 15)

            // Right stick dot
            Circle()
                .fill(Color.blue.opacity(0.7))
                .frame(width: 10, height: 10)
                .offset(x: 55 + msg.rightStickX * 15, y: 15 + msg.rightStickY * 15)

            // D-Pad indicator
            Text("+")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(msg.pressedButtons.contains(where: { $0.hasPrefix("DPad") }) ? .blue : .gray)
                .offset(x: -55, y: -20)

            // Face buttons indicator
            let faceActive = ["Triangle", "Circle", "Cross", "Square"].contains(where: { msg.pressedButtons.contains($0) })
            Text("\u{25CB}")
                .font(.system(size: 16))
                .foregroundStyle(faceActive ? .blue : .gray)
                .offset(x: 55, y: -20)
        }
    }
}

// Simple flow layout for button pills
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, pos) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

// MARK: - Universal Mode View

struct UniversalView: View {
    @State private var receiver = ControllerReceiver()
    @State private var mapper = InputMapper()
    @State private var sensitivity: Double = 15.0
    @State private var rebindingId: String? = nil
    @State private var keyListener = KeyListener()
    @State private var activePreset: String = "Custom"

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                // Connection status
                HStack(spacing: 8) {
                    Circle()
                        .fill(receiver.connectedPeer != nil ? .green : (receiver.isSearching ? .orange : .gray))
                        .frame(width: 10, height: 10)
                    Text(receiver.connectedPeer != nil ? "Connected via USB" : "Searching for USB controller...")
                        .font(.system(.body, design: .monospaced))
                }

                Divider()

                // Toggle
                HStack {
                    Toggle("Enable Keyboard/Mouse Mapping", isOn: $mapper.isEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: mapper.isEnabled) {
                            if !mapper.isEnabled { mapper.releaseAll() }
                        }

                    Spacer()

                    if mapper.isEnabled {
                        Text("ACTIVE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15))
                            .cornerRadius(4)
                    }
                }

                // Presets
                HStack(spacing: 8) {
                    Text("Presets:")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))

                    ForEach(ControllerMapping.Preset.allCases) { preset in
                        Button {
                            activePreset = preset.rawValue
                            mapper.mapping = ControllerMapping.preset(preset)
                            mapper.mapping.save()
                            sensitivity = mapper.mapping.mouseSensitivity
                        } label: {
                            Text(preset.rawValue)
                                .font(.system(size: 11, weight: activePreset == preset.rawValue ? .bold : .regular, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(activePreset == preset.rawValue ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                .foregroundStyle(activePreset == preset.rawValue ? .blue : .primary)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(activePreset == preset.rawValue ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        activePreset = "Custom"
                    } label: {
                        Text("Custom")
                            .font(.system(size: 11, weight: activePreset == "Custom" ? .bold : .regular, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(activePreset == "Custom" ? Color.purple.opacity(0.2) : Color.gray.opacity(0.1))
                            .foregroundStyle(activePreset == "Custom" ? .purple : .primary)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(activePreset == "Custom" ? Color.purple.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button("Reset") {
                        mapper.mapping.resetDefaults()
                        sensitivity = mapper.mapping.mouseSensitivity
                        activePreset = "Custom"
                    }
                    .font(.system(size: 11))
                }

                // Sensitivity
                HStack {
                    Text("Mouse Sensitivity")
                        .font(.system(size: 12, design: .monospaced))
                    Slider(value: $sensitivity, in: 2...50, step: 1)
                        .frame(width: 200)
                        .onChange(of: sensitivity) {
                            mapper.mapping.mouseSensitivity = sensitivity
                            mapper.mapping.save()
                        }
                    Text("\(Int(sensitivity))")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 30)
                }

                Divider()

                // Mapping table header
                HStack {
                    Text("Controller")
                        .frame(width: 130, alignment: .leading)
                    Text("Key")
                        .frame(width: 100, alignment: .leading)
                    Text("")
                        .frame(width: 60)
                    Spacer()
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.15))

                // Right stick (not rebindable, always mouse)
                HStack {
                    Text("Right Stick")
                        .frame(width: 130, alignment: .leading)
                    Text("Mouse")
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text("")
                        .frame(width: 60)
                    Spacer()
                    if let msg = receiver.latestMessage, abs(msg.rightStickX) > 0.1 || abs(msg.rightStickY) > 0.1 {
                        Circle().fill(.green).frame(width: 8, height: 8)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 3)

                // Rebindable entries
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(mapper.mapping.entries.enumerated()), id: \.element.id) { i, entry in
                            HStack {
                                Text(entry.label)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 130, alignment: .leading)

                                // Key button — click to rebind
                                Button {
                                    rebindingId = entry.id
                                    keyListener.start()
                                } label: {
                                    Text(rebindingId == entry.id ? "Press a key..." : KeyNames.name(for: entry.keyCode))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(rebindingId == entry.id ? .orange : .blue)
                                        .frame(width: 100, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                // Active indicator
                                let active = isEntryActive(entry, msg: receiver.latestMessage)
                                Circle()
                                    .fill(active ? .green : .clear)
                                    .frame(width: 8, height: 8)
                                    .frame(width: 60)

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .background(i % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
                        }
                    }
                }

                Text("Click a key binding to change it, then press the new key.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text("Requires Accessibility permission: System Settings > Privacy & Security > Accessibility")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding()

            // Dimmed overlay when rebinding
            if rebindingId != nil {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        keyListener.stop()
                        rebindingId = nil
                    }
                VStack(spacing: 8) {
                    Text("Press any key to bind")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("or click anywhere to cancel")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(20)
                .background(.black.opacity(0.8))
                .cornerRadius(12)
            }
        }
        .frame(minWidth: 500, minHeight: 550)
        .onAppear {
            receiver.start()
            sensitivity = mapper.mapping.mouseSensitivity
        }
        .onDisappear {
            keyListener.stop()
            mapper.releaseAll()
            receiver.stop()
        }
        .onChange(of: keyListener.capturedKeyCode) {
            guard let keyCode = keyListener.capturedKeyCode,
                  let id = rebindingId,
                  let idx = mapper.mapping.entries.firstIndex(where: { $0.id == id })
            else { return }
            mapper.mapping.entries[idx].keyCode = keyCode
            mapper.mapping.save()
            rebindingId = nil
            activePreset = "Custom"
        }
        .onChange(of: receiver.latestMessage?.pressedButtons) { mapper.process(receiver.latestMessage) }
        .onChange(of: receiver.latestMessage?.leftStickX) { mapper.process(receiver.latestMessage) }
        .onChange(of: receiver.latestMessage?.leftStickY) { mapper.process(receiver.latestMessage) }
        .onChange(of: receiver.latestMessage?.rightStickX) { mapper.process(receiver.latestMessage) }
        .onChange(of: receiver.latestMessage?.rightStickY) { mapper.process(receiver.latestMessage) }
    }

    private func isEntryActive(_ entry: MappingEntry, msg: ControllerMessage?) -> Bool {
        guard let msg else { return false }
        let buttons = msg.pressedButtons
        switch entry.id {
        case "lstickUp": return msg.leftStickY < -0.3
        case "lstickDown": return msg.leftStickY > 0.3
        case "lstickLeft": return msg.leftStickX < -0.3
        case "lstickRight": return msg.leftStickX > 0.3
        case "dpadUp": return buttons.contains("DPadUp")
        case "dpadDown": return buttons.contains("DPadDown")
        case "dpadLeft": return buttons.contains("DPadLeft")
        case "dpadRight": return buttons.contains("DPadRight")
        case "cross": return buttons.contains("Cross")
        case "circle": return buttons.contains("Circle")
        case "triangle": return buttons.contains("Triangle")
        case "square": return buttons.contains("Square")
        case "l1": return buttons.contains("L1")
        case "l2": return buttons.contains("L2")
        case "r1": return buttons.contains("R1")
        case "r2": return buttons.contains("R2")
        case "l3": return buttons.contains("L3")
        case "r3": return buttons.contains("R3")
        case "options": return buttons.contains("Options")
        case "create": return buttons.contains("Create")
        case "ps": return buttons.contains("PS")
        case "touchpad": return buttons.contains("Touchpad")
        default: return false
        }
    }
}

// MARK: - Mac Content View (tab switcher)

struct MacContentView: View {
    @State private var selectedTab = "universal"

    var body: some View {
        TabView(selection: $selectedTab) {
            UniversalView()
                .tabItem { Label("Universal", systemImage: "keyboard") }
                .tag("universal")
            GameView()
                .tabItem { Label("Parkour", systemImage: "gamecontroller") }
                .tag("game")
            ReceiverView()
                .tabItem { Label("Debug", systemImage: "antenna.radiowaves.left.and.right") }
                .tag("debug")
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}
#endif
