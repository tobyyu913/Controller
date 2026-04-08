//
//  ContentView.swift
//  Controller
//
//  Created by Toby Yu on 04/04/2026.
//

import SwiftUI

// MARK: - Controller State

@Observable
class ControllerState {
    var leftStick: CGSize = .zero
    var rightStick: CGSize = .zero
    var pressedButtons: Set<String> = []

    func press(_ button: String) {
        pressedButtons.insert(button)
    }

    func release(_ button: String) {
        pressedButtons.remove(button)
    }

    func isPressed(_ button: String) -> Bool {
        pressedButtons.contains(button)
    }

    func toMessage(stickRadius: CGFloat = 40) -> ControllerMessage {
        ControllerMessage(
            pressedButtons: Array(pressedButtons),
            leftStickX: Double(leftStick.width / stickRadius),
            leftStickY: Double(leftStick.height / stickRadius),
            rightStickX: Double(rightStick.width / stickRadius),
            rightStickY: Double(rightStick.height / stickRadius)
        )
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var controller = ControllerState()
    #if os(iOS)
    @State private var client = ControllerClient()
    #endif

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                #if os(iOS)
                // Connection indicator (top center)
                VStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(client.isConnected ? .green : (client.isSearching ? .orange : .gray))
                            .frame(width: 8, height: 8)
                        Text(client.isConnected ? "Connected" : (client.isSearching ? "Searching..." : "Offline"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.gray)
                    }
                    .padding(.top, 4)
                    Spacer()
                }
                #endif

                HStack(spacing: 0) {
                    // Left side: L2/L1 + D-Pad + Left Stick
                    VStack(spacing: 12) {
                        // L2 / L1
                        HStack(spacing: 10) {
                            TriggerButton(label: "L2", controller: controller)
                            BumperButton(label: "L1", controller: controller)
                        }

                        Spacer().frame(height: 4)

                        // D-Pad
                        DPadView(controller: controller)

                        Spacer().frame(height: 8)

                        // Left Stick
                        AnalogStickView(
                            stickOffset: $controller.leftStick,
                            label: "L3",
                            controller: controller
                        )
                    }
                    .frame(width: geo.size.width * 0.3)

                    // Center: Create, Touchpad, Options, PS button
                    VStack(spacing: 10) {
                        Spacer()

                        HStack(spacing: 16) {
                            SmallPillButton(label: "Create", systemIcon: "line.3.horizontal", controller: controller)

                            // Touchpad
                            TouchpadView(controller: controller)

                            SmallPillButton(label: "Options", systemIcon: "line.3.horizontal", controller: controller)
                        }

                        Spacer()

                        // PS Button + Mute
                        HStack(spacing: 20) {
                            MuteButton(controller: controller)
                            PSButton(controller: controller)
                        }

                        Spacer()
                    }
                    .frame(width: geo.size.width * 0.4)

                    // Right side: R2/R1 + Face Buttons + Right Stick
                    VStack(spacing: 12) {
                        // R1 / R2
                        HStack(spacing: 10) {
                            BumperButton(label: "R1", controller: controller)
                            TriggerButton(label: "R2", controller: controller)
                        }

                        Spacer().frame(height: 4)

                        // Face Buttons
                        FaceButtonsView(controller: controller)

                        Spacer().frame(height: 8)

                        // Right Stick
                        AnalogStickView(
                            stickOffset: $controller.rightStick,
                            label: "R3",
                            controller: controller
                        )
                    }
                    .frame(width: geo.size.width * 0.3)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { client.start() }
        .onDisappear { client.stop() }
        .onChange(of: controller.pressedButtons) { client.send(controller.toMessage()) }
        .onChange(of: controller.leftStick) { client.send(controller.toMessage()) }
        .onChange(of: controller.rightStick) { client.send(controller.toMessage()) }
        #endif
    }
}

// MARK: - D-Pad

struct DPadView: View {
    let controller: ControllerState
    let size: CGFloat = 52

    var body: some View {
        let btnSize = size
        ZStack {
            // Up
            DPadButton(label: "Up", icon: "chevron.up", controller: controller)
                .offset(y: -btnSize)
            // Down
            DPadButton(label: "Down", icon: "chevron.down", controller: controller)
                .offset(y: btnSize)
            // Left
            DPadButton(label: "Left", icon: "chevron.left", controller: controller)
                .offset(x: -btnSize)
            // Right
            DPadButton(label: "Right", icon: "chevron.right", controller: controller)
                .offset(x: btnSize)
            // Center
            Circle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: btnSize * 0.6, height: btnSize * 0.6)
        }
        .frame(width: btnSize * 3, height: btnSize * 3)
    }
}

struct DPadButton: View {
    let label: String
    let icon: String
    let controller: ControllerState

    var body: some View {
        let pressed = controller.isPressed("DPad\(label)")
        Image(systemName: icon)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(pressed ? .white : .gray)
            .frame(width: 48, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(pressed ? Color.white.opacity(0.2) : Color.gray.opacity(0.15))
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !controller.isPressed("DPad\(label)") {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                        controller.press("DPad\(label)")
                    }
                    .onEnded { _ in controller.release("DPad\(label)") }
            )
    }
}

// MARK: - Face Buttons (△ ○ ✕ □)

struct FaceButtonsView: View {
    let controller: ControllerState
    let size: CGFloat = 50

    var body: some View {
        ZStack {
            // Triangle (top)
            FaceButton(symbol: "triangle", label: "Triangle", color: .green, controller: controller)
                .offset(y: -size)
            // Circle (right)
            FaceButton(symbol: "circle", label: "Circle", color: .red, controller: controller)
                .offset(x: size)
            // Cross (bottom)
            FaceButton(symbol: "xmark", label: "Cross", color: .blue, controller: controller)
                .offset(y: size)
            // Square (left)
            FaceButton(symbol: "square", label: "Square", color: .pink, controller: controller)
                .offset(x: -size)
        }
        .frame(width: size * 3, height: size * 3)
    }
}

struct FaceButton: View {
    let symbol: String
    let label: String
    let color: Color
    let controller: ControllerState

    var body: some View {
        let pressed = controller.isPressed(label)
        ZStack {
            Circle()
                .fill(pressed ? color.opacity(0.4) : Color.gray.opacity(0.15))
                .frame(width: 48, height: 48)
            Circle()
                .stroke(color.opacity(pressed ? 1.0 : 0.6), lineWidth: 2)
                .frame(width: 48, height: 48)
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(pressed ? .white : color)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !controller.isPressed(label) {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    }
                    controller.press(label)
                }
                .onEnded { _ in controller.release(label) }
        )
    }
}

// MARK: - Analog Stick

struct AnalogStickView: View {
    @Binding var stickOffset: CGSize
    let label: String
    let controller: ControllerState
    let radius: CGFloat = 40
    @State private var wasAtEdge = false

    var body: some View {
        let pressed = controller.isPressed(label)
        ZStack {
            // Base
            Circle()
                .fill(Color.gray.opacity(0.12))
                .frame(width: radius * 2.5, height: radius * 2.5)
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 1.5)
                .frame(width: radius * 2.5, height: radius * 2.5)

            // Stick thumb
            Circle()
                .fill(pressed ? Color.white.opacity(0.35) : Color.gray.opacity(0.4))
                .frame(width: radius * 1.4, height: radius * 1.4)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .offset(stickOffset)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let translation = value.translation
                            let distance = sqrt(translation.width * translation.width + translation.height * translation.height)
                            let atEdge = distance > radius * 0.95
                            if distance <= radius {
                                stickOffset = translation
                            } else {
                                let angle = atan2(translation.height, translation.width)
                                stickOffset = CGSize(
                                    width: cos(angle) * radius,
                                    height: sin(angle) * radius
                                )
                            }
                            #if os(iOS)
                            if atEdge && !wasAtEdge {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            #endif
                            wasAtEdge = atEdge
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                                stickOffset = .zero
                            }
                            controller.release(label)
                        }
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.3)
                        .onEnded { _ in
                            controller.press(label)
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                        }
                )
        }
    }
}

// MARK: - Triggers & Bumpers

struct TriggerButton: View {
    let label: String
    let controller: ControllerState

    var body: some View {
        let pressed = controller.isPressed(label)
        Text(label)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(pressed ? .white : .gray)
            .frame(width: 64, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(pressed ? Color.white.opacity(0.2) : Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !controller.isPressed(label) {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                        controller.press(label)
                    }
                    .onEnded { _ in controller.release(label) }
            )
    }
}

struct BumperButton: View {
    let label: String
    let controller: ControllerState

    var body: some View {
        let pressed = controller.isPressed(label)
        Text(label)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(pressed ? .white : .gray)
            .frame(width: 64, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(pressed ? Color.white.opacity(0.2) : Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !controller.isPressed(label) {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                        controller.press(label)
                    }
                    .onEnded { _ in controller.release(label) }
            )
    }
}

// MARK: - Touchpad

struct TouchpadView: View {
    let controller: ControllerState

    var body: some View {
        let pressed = controller.isPressed("Touchpad")
        RoundedRectangle(cornerRadius: 10)
            .fill(pressed ? Color.white.opacity(0.15) : Color.gray.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .frame(width: 140, height: 50)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !controller.isPressed("Touchpad") {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                        controller.press("Touchpad")
                    }
                    .onEnded { _ in controller.release("Touchpad") }
            )
    }
}

// MARK: - Small Pill Buttons (Create / Options)

struct SmallPillButton: View {
    let label: String
    let systemIcon: String
    let controller: ControllerState

    var body: some View {
        let pressed = controller.isPressed(label)
        VStack(spacing: 2) {
            Image(systemName: systemIcon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundColor(pressed ? .white : .gray)
        .frame(width: 44, height: 28)
        .background(
            Capsule()
                .fill(pressed ? Color.white.opacity(0.2) : Color.gray.opacity(0.12))
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !controller.isPressed(label) {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    }
                    controller.press(label)
                }
                .onEnded { _ in controller.release(label) }
        )
    }
}

// MARK: - PS Button

struct PSButton: View {
    let controller: ControllerState

    var body: some View {
        let pressed = controller.isPressed("PS")
        ZStack {
            Circle()
                .fill(pressed ? Color.blue.opacity(0.4) : Color.gray.opacity(0.12))
                .frame(width: 36, height: 36)
            Circle()
                .stroke(Color.blue.opacity(pressed ? 0.8 : 0.4), lineWidth: 1.5)
                .frame(width: 36, height: 36)
            Text("PS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(pressed ? .white : .blue)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !controller.isPressed("PS") {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    }
                    controller.press("PS")
                }
                .onEnded { _ in controller.release("PS") }
        )
    }
}

// MARK: - Mute Button

struct MuteButton: View {
    let controller: ControllerState
    @State private var muted = false

    var body: some View {
        ZStack {
            Circle()
                .fill(muted ? Color.orange.opacity(0.3) : Color.gray.opacity(0.12))
                .frame(width: 30, height: 30)
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 11))
                .foregroundColor(muted ? .orange : .gray)
        }
        .onTapGesture {
            muted.toggle()
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }
}

// MARK: - Preview

#Preview(traits: .landscapeLeft) {
    ContentView()
}
