//
//  DualGameView.swift
//  Controller
//
//  Split-screen dual-player co-op platformer. Each player gets their own camera view.
//  Player 1 (orange) = left screen, Player 2 (cyan) = right screen.
//  Works on both macOS and iPad.
//

import SwiftUI
import SceneKit

#if os(macOS)
import AppKit
private typealias PlatformColor = NSColor
private typealias PlatformFont = NSFont
#else
import UIKit
private typealias PlatformColor = UIColor
private typealias PlatformFont = UIFont
#endif

struct DualGameView: View {
    let server: ControllerServer
    @State private var engine = DualGameEngine()

    var body: some View {
        ZStack {
            // Split screen: two SceneKit views side by side
            HStack(spacing: 0) {
                // P1 — left half
                ZStack {
                    SplitSceneView(scene: engine.scene, pointOfView: engine.p1CameraNode)

                    // P1 HUD
                    VStack {
                        HStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(server.connectedClients.count >= 1 ? Color.orange : .gray)
                                    .frame(width: 8, height: 8)
                                Text("P1")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.orange)
                            }
                            .padding(6)
                            .background(.black.opacity(0.5))
                            .cornerRadius(6)
                            .padding(8)

                            Spacer()
                        }

                        Spacer()

                        // Crosshair
                        ZStack {
                            Rectangle().fill(Color.orange.opacity(0.6)).frame(width: 12, height: 2)
                            Rectangle().fill(Color.orange.opacity(0.6)).frame(width: 2, height: 12)
                        }

                        Spacer()

                        if engine.p1Sprinting {
                            Text("SPRINTING")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.black.opacity(0.4)).cornerRadius(4)
                                .padding(.bottom, 8)
                        }
                    }
                }

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 2)

                // P2 — right half
                ZStack {
                    SplitSceneView(scene: engine.scene, pointOfView: engine.p2CameraNode)

                    // P2 HUD
                    VStack {
                        HStack {
                            Spacer()

                            HStack(spacing: 6) {
                                Text("P2")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.cyan)
                                Circle()
                                    .fill(server.connectedClients.count >= 2 ? Color.cyan : .gray)
                                    .frame(width: 8, height: 8)
                            }
                            .padding(6)
                            .background(.black.opacity(0.5))
                            .cornerRadius(6)
                            .padding(8)
                        }

                        Spacer()

                        // Crosshair
                        ZStack {
                            Rectangle().fill(Color.cyan.opacity(0.6)).frame(width: 12, height: 2)
                            Rectangle().fill(Color.cyan.opacity(0.6)).frame(width: 2, height: 12)
                        }

                        Spacer()

                        if engine.p2Sprinting {
                            Text("SPRINTING")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.black.opacity(0.4)).cornerRadius(4)
                                .padding(.bottom, 8)
                        }
                    }
                }
            }

            // Shared HUD overlay (centered top)
            VStack {
                HStack(spacing: 16) {
                    if server.connectedClients.count < 2 {
                        Text("Connect \(2 - server.connectedClients.count) more controller\(server.connectedClients.count == 1 ? "" : "s")")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    if engine.checkpointIndex > 0 {
                        Text("Checkpoint \(engine.checkpointIndex)/\(engine.totalCheckpoints)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.yellow)
                    }

                    if engine.finished {
                        Text("COURSE COMPLETE!")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }
                .padding(8)
                .background(.black.opacity(0.6))
                .cornerRadius(8)
                .padding(.top, 8)

                Spacer()

                // Controls hint
                HStack(spacing: 20) {
                    Label("Move", systemImage: "l.joystick")
                    Label("Jump", systemImage: "circle")
                    Label("Sprint", systemImage: "l2.rectangle.roundedtop")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .padding(6)
                .background(.black.opacity(0.3))
                .cornerRadius(6)
                .padding(.bottom, 6)
            }
        }
        .onChange(of: server.player1Message?.pressedButtons) { engine.updateP1(server.player1Message) }
        .onChange(of: server.player1Message?.leftStickX) { engine.updateP1(server.player1Message) }
        .onChange(of: server.player1Message?.leftStickY) { engine.updateP1(server.player1Message) }
        .onChange(of: server.player1Message?.rightStickX) { engine.updateP1(server.player1Message) }
        .onChange(of: server.player1Message?.rightStickY) { engine.updateP1(server.player1Message) }
        .onChange(of: server.player2Message?.pressedButtons) { engine.updateP2(server.player2Message) }
        .onChange(of: server.player2Message?.leftStickX) { engine.updateP2(server.player2Message) }
        .onChange(of: server.player2Message?.leftStickY) { engine.updateP2(server.player2Message) }
        .onChange(of: server.player2Message?.rightStickX) { engine.updateP2(server.player2Message) }
        .onChange(of: server.player2Message?.rightStickY) { engine.updateP2(server.player2Message) }
    }
}

// MARK: - Split Scene View (one SCNView per player)

#if os(macOS)
struct SplitSceneView: NSViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.pointOfView = pointOfView
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        view.pointOfView = pointOfView
    }
}
#else
struct SplitSceneView: UIViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.pointOfView = pointOfView
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        view.pointOfView = pointOfView
    }
}
#endif

// MARK: - Player State

private class PlayerState {
    let node = SCNNode()
    let bodyNode = SCNNode()
    let cameraNode = SCNNode()
    let cameraPivot = SCNNode()
    let color: PlatformColor
    let label: String

    var velocityX: Float = 0
    var velocityY: Float = 0
    var velocityZ: Float = 0
    var isGrounded = false
    var canDoubleJump = true
    var coyoteFrames: Int = 0
    var jumpHeld = false
    var isSprinting = false
    var currentPlatformIndex: Int = -1
    var lastCheckpointPos = SCNVector3(0, 1.5, 0)
    var lastMessage: ControllerMessage?

    // Camera orbit (horizontal only, fixed elevation)
    var yaw: Float = 0
    let camDistance: Float = 12
    let camHeight: Float = 5

    init(color: PlatformColor, label: String, startPos: SCNVector3) {
        self.color = color
        self.label = label

        // Capsule body
        let capsule = SCNCapsule(capRadius: 0.3, height: 1.6)
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color.withAlphaComponent(0.2)
        capsule.materials = [mat]
        bodyNode.geometry = capsule
        bodyNode.position = SCNVector3(0, 0.8, 0)
        bodyNode.castsShadow = true
        node.addChildNode(bodyNode)

        // Label above head
        let text = SCNText(string: label, extrusionDepth: 0.05)
        text.font = PlatformFont.systemFont(ofSize: 0.4, weight: .bold)
        text.flatness = 0.1
        let textMat = SCNMaterial()
        textMat.diffuse.contents = color
        textMat.emission.contents = color
        text.materials = [textMat]
        let textNode = SCNNode(geometry: text)
        let (min, max) = textNode.boundingBox
        let textW = max.x - min.x
        textNode.position = SCNVector3(-textW / 2, 2.0, 0)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        textNode.constraints = [billboard]
        node.addChildNode(textNode)

        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 65
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 200

        node.position = startPos
        lastCheckpointPos = startPos
    }
}

// MARK: - Dual Game Engine

@Observable
class DualGameEngine {
    let scene = SCNScene()
    let p1CameraNode = SCNNode()
    let p2CameraNode = SCNNode()

    var checkpointIndex = 0
    var totalCheckpoints = 0
    var finished = false
    var p1Sprinting = false
    var p2Sprinting = false

    private var p1: PlayerState!
    private var p2: PlayerState!
    private var platforms: [(pos: SCNVector3, size: SCNVector3, checkpoint: Bool)] = []
    private var checkpointPositions: [SCNVector3] = []
    private var _timer: DispatchSourceTimer?

    // Physics
    private let walkSpeed: Float = 0.14
    private let sprintSpeed: Float = 0.28
    private let gravity: Float = -0.012
    private let jumpForce: Float = 0.28
    private let sprintJumpForce: Float = 0.34
    private let playerRadius: Float = 0.3

    init() {
        setupScene()
        buildCourse()

        p1 = PlayerState(color: .systemOrange, label: "P1", startPos: SCNVector3(-1, 1.5, 0))
        p2 = PlayerState(color: .systemCyan, label: "P2", startPos: SCNVector3(1, 1.5, 0))
        scene.rootNode.addChildNode(p1.node)
        scene.rootNode.addChildNode(p2.node)

        p1CameraNode.camera = SCNCamera()
        p1CameraNode.camera?.fieldOfView = 65
        p1CameraNode.camera?.zNear = 0.1
        p1CameraNode.camera?.zFar = 200
        p1CameraNode.position = SCNVector3(-1, 5, 16)
        scene.rootNode.addChildNode(p1CameraNode)

        p2CameraNode.camera = SCNCamera()
        p2CameraNode.camera?.fieldOfView = 65
        p2CameraNode.camera?.zNear = 0.1
        p2CameraNode.camera?.zFar = 200
        p2CameraNode.position = SCNVector3(1, 5, 16)
        scene.rootNode.addChildNode(p2CameraNode)

        startLoop()
    }

    // MARK: - Scene

    private func setupScene() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = PlatformColor(white: 0.4, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = PlatformColor(white: 0.9, alpha: 1)
        sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred
        sun.light?.shadowSampleCount = 8
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(sun)

        scene.background.contents = PlatformColor(red: 0.3, green: 0.5, blue: 0.85, alpha: 1)
        scene.fogStartDistance = 50
        scene.fogEndDistance = 150
        scene.fogColor = PlatformColor(red: 0.3, green: 0.5, blue: 0.85, alpha: 1)

        let floor = SCNFloor()
        floor.reflectivity = 0.2
        let floorMat = SCNMaterial()
        floorMat.diffuse.contents = PlatformColor(red: 0.1, green: 0.05, blue: 0.15, alpha: 1)
        floorMat.emission.contents = PlatformColor(red: 0.2, green: 0.05, blue: 0.1, alpha: 1)
        floor.materials = [floorMat]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, -12, 0)
        scene.rootNode.addChildNode(floorNode)
    }

    private func buildCourse() {
        let defs: [(Float, Float, Float, Float, Float, Float, Bool, PlatformColor)] = [
            (0, 0, 0, 8, 0.5, 4, true, .systemGreen),
            (8, 0.5, 0, 3, 0.3, 3, false, .darkGray),
            (14, 1.0, 0, 3, 0.3, 3, false, .darkGray),
            (20, 1.5, 0, 3, 0.3, 3, false, .darkGray),
            (27, 2.0, 0, 5, 0.4, 4, true, .systemBlue),
            (32, 2.8, -2, 2.5, 0.3, 2.5, false, .darkGray),
            (37, 3.6, 2, 2.5, 0.3, 2.5, false, .darkGray),
            (42, 4.4, -2, 2.5, 0.3, 2.5, false, .darkGray),
            (47, 5.2, 0, 2.5, 0.3, 2.5, false, .darkGray),
            (53, 5.5, 0, 5, 0.4, 4, true, .systemOrange),
            (61, 5.5, 0, 2, 0.3, 3, false, .darkGray),
            (70, 5.5, 0, 2, 0.3, 3, false, .darkGray),
            (79, 6.0, 0, 2, 0.3, 3, false, .darkGray),
            (86, 6.5, 0, 5, 0.4, 4, true, .systemPurple),
            (91, 7.2, 0, 2, 0.3, 3, false, .darkGray),
            (95, 8.0, 0, 2, 0.3, 3, false, .darkGray),
            (99, 8.8, 0, 2, 0.3, 3, false, .darkGray),
            (103, 9.6, 0, 2, 0.3, 3, false, .darkGray),
            (108, 10.0, 0, 6, 0.3, 0.8, false, .gray),
            (116, 10.0, 0, 6, 0.3, 0.8, false, .gray),
            (124, 10.0, 0, 8, 0.5, 5, true, .systemGreen),
        ]

        for d in defs {
            let pos = SCNVector3(d.0, d.1, d.2)
            let size = SCNVector3(d.3, d.4, d.5)
            platforms.append((pos: pos, size: size, checkpoint: d.6))

            let box = SCNBox(width: CGFloat(d.3), height: CGFloat(d.4), length: CGFloat(d.5), chamferRadius: 0.03)
            let mat = SCNMaterial()
            mat.diffuse.contents = d.7
            if d.6 { mat.emission.contents = d.7.withAlphaComponent(0.15) }
            box.materials = [mat]
            let node = SCNNode(geometry: box)
            node.position = pos
            node.castsShadow = true
            scene.rootNode.addChildNode(node)

            if d.6 {
                let cpY = d.1 + d.4 / 2 + 1.5
                checkpointPositions.append(SCNVector3(d.0, cpY, d.2))

                let ring = SCNTorus(ringRadius: CGFloat(max(d.3, d.5)) * 0.5, pipeRadius: 0.05)
                let ringMat = SCNMaterial()
                ringMat.diffuse.contents = PlatformColor.systemYellow
                ringMat.emission.contents = PlatformColor.systemYellow
                ring.materials = [ringMat]
                let ringNode = SCNNode(geometry: ring)
                ringNode.position = SCNVector3(d.0, d.1 + d.4 / 2 + 0.6, d.2)
                ringNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 3)))
                scene.rootNode.addChildNode(ringNode)
            }
        }

        totalCheckpoints = checkpointPositions.count

        for x in stride(from: Float(10), through: 120, by: 20) {
            let pillar = SCNCylinder(radius: 0.5, height: CGFloat(Float.random(in: 10...20)))
            let mat = SCNMaterial()
            mat.diffuse.contents = PlatformColor(white: 0.2, alpha: 1)
            pillar.materials = [mat]
            let node = SCNNode(geometry: pillar)
            let h = Float(pillar.height) / 2
            node.position = SCNVector3(x + Float.random(in: -5...5), h - 12, Float.random(in: -8 ... -4))
            node.castsShadow = true
            scene.rootNode.addChildNode(node)
        }
    }

    // MARK: - Input

    func updateP1(_ msg: ControllerMessage?) { p1.lastMessage = msg }
    func updateP2(_ msg: ControllerMessage?) { p2.lastMessage = msg }

    // MARK: - Game Loop

    private func startLoop() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        _timer = timer
    }

    private func tick() {
        tickPlayer(p1)
        tickPlayer(p2)
        updateCameras()
        p1Sprinting = p1.isSprinting
        p2Sprinting = p2.isSprinting
    }

    // MARK: - Camera (orbit around player, controlled by right stick)

    private let lookSpeed: Float = 0.04

    private func updateCameras() {
        updatePlayerCamera(p1CameraNode, player: p1)
        updatePlayerCamera(p2CameraNode, player: p2)
    }

    private func updatePlayerCamera(_ cam: SCNNode, player: PlayerState) {
        guard let msg = player.lastMessage else { return }

        let rx = Float(msg.rightStickX)
        if abs(rx) > 0.1 { player.yaw += rx * lookSpeed }
        player.yaw = max(-Float.pi / 3, min(Float.pi / 3, player.yaw))

        if msg.pressedButtons.contains("R3") { player.yaw = 0 }

        let px = Float(player.node.position.x)
        let py = Float(player.node.position.y) + 1.0
        let pz = Float(player.node.position.z)

        let camX = px + sin(player.yaw) * player.camDistance
        let camZ = pz + cos(player.yaw) * player.camDistance
        let camY = py + player.camHeight

        let targetPos = SCNVector3(camX, camY, camZ)

        let cur = cam.position
        cam.position = SCNVector3(
            cur.x + (targetPos.x - cur.x) * 0.12,
            cur.y + (targetPos.y - cur.y) * 0.12,
            cur.z + (targetPos.z - cur.z) * 0.12
        )

        cam.look(at: SCNVector3(px, py, pz))
    }

    // MARK: - Player Physics

    private func tickPlayer(_ player: PlayerState) {
        guard let msg = player.lastMessage else { return }
        let buttons = msg.pressedButtons

        player.isSprinting = buttons.contains("L2")
        let speed = player.isSprinting ? sprintSpeed : walkSpeed

        let lx = Float(msg.leftStickX)
        let ly = Float(msg.leftStickY)
        if abs(lx) > 0.05 || abs(ly) > 0.05 {
            let fwdX = -sin(player.yaw)
            let fwdZ = -cos(player.yaw)
            let rightX = cos(player.yaw)
            let rightZ = -sin(player.yaw)
            player.velocityX = (fwdX * (-ly) + rightX * lx) * speed
            player.velocityZ = (fwdZ * (-ly) + rightZ * lx) * speed
        } else if player.isGrounded {
            player.velocityX = 0
            player.velocityZ = 0
        }

        let jumpDown = buttons.contains("Circle")
        let jumpJustPressed = jumpDown && !player.jumpHeld
        player.jumpHeld = jumpDown

        if jumpJustPressed {
            if player.isGrounded || player.coyoteFrames > 0 {
                let force = player.isSprinting ? sprintJumpForce : jumpForce
                player.velocityY = force
                player.isGrounded = false
                player.coyoteFrames = 0
                player.canDoubleJump = true
            } else if player.canDoubleJump && !player.isGrounded {
                player.velocityY = jumpForce * 0.7
                player.canDoubleJump = false
            }
        }

        player.velocityY += gravity

        var posX = Float(player.node.position.x) + player.velocityX
        var posY = Float(player.node.position.y) + player.velocityY
        var posZ = Float(player.node.position.z) + player.velocityZ

        let wasGrounded = player.isGrounded
        player.isGrounded = false

        for (i, plat) in platforms.enumerated() {
            let px = Float(plat.pos.x), py = Float(plat.pos.y), pz = Float(plat.pos.z)
            let hw = Float(plat.size.x) / 2 + playerRadius
            let hh = Float(plat.size.y) / 2
            let hd = Float(plat.size.z) / 2 + playerRadius
            let platTop = py + hh

            let onX = posX >= px - hw && posX <= px + hw
            let onZ = posZ >= pz - hd && posZ <= pz + hd

            if onX && onZ && posY <= platTop + 0.1 && posY >= platTop - 0.5 && player.velocityY <= 0 {
                posY = platTop
                player.velocityY = 0
                player.isGrounded = true
                player.canDoubleJump = true
                player.currentPlatformIndex = i

                if plat.checkpoint {
                    let cpIdx = checkpointPositions.firstIndex(where: {
                        abs(Float($0.x) - px) < 0.1 && abs(Float($0.z) - pz) < 0.1
                    }) ?? -1
                    if cpIdx >= 0 && cpIdx + 1 > checkpointIndex {
                        checkpointIndex = cpIdx + 1
                        let cpPos = checkpointPositions[cpIdx]
                        p1.lastCheckpointPos = SCNVector3(cpPos.x - 1, cpPos.y, cpPos.z)
                        p2.lastCheckpointPos = SCNVector3(cpPos.x + 1, cpPos.y, cpPos.z)
                        if checkpointIndex >= totalCheckpoints { finished = true }
                    }
                }
                break
            }
        }

        if wasGrounded && !player.isGrounded {
            player.coyoteFrames = 6
            player.currentPlatformIndex = -1
        } else if player.coyoteFrames > 0 {
            player.coyoteFrames -= 1
        }

        if posY < -15 {
            respawn(player)
            return
        }

        player.node.position = SCNVector3(posX, posY, posZ)
    }

    private func respawn(_ player: PlayerState) {
        player.node.position = player.lastCheckpointPos
        player.velocityX = 0
        player.velocityY = 0
        player.velocityZ = 0
        player.isGrounded = false
        player.canDoubleJump = true
        player.coyoteFrames = 0
    }
}
