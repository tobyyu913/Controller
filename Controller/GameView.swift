//
//  GameView.swift
//  Controller
//
//  Parkour game controlled by the phone controller.
//  Left stick = move, Right stick = look, O = jump, R2 = squat, L2 = sprint
//

#if os(macOS)
import SwiftUI
import SceneKit

struct GameView: View {
    let server: ControllerServer
    @State private var game = GameEngine()

    var body: some View {
        ZStack {
            SceneViewWrapper(scene: game.scene, pointOfView: game.cameraNode)
                .ignoresSafeArea()

            // Crosshair
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 16, height: 2)
                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 2, height: 16)
            }

            // HUD
            VStack {
                // Connection + stats
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(server.connectedPeer != nil ? .green : (server.isSearching ? .orange : .gray))
                            .frame(width: 8, height: 8)
                        Text(server.connectedPeer != nil ? "Controller connected" : "Waiting for controller...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    if game.checkpointIndex > 0 {
                        Text("Checkpoint \(game.checkpointIndex)/\(game.totalCheckpoints)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.yellow)
                    }

                    if game.finished {
                        Text("COURSE COMPLETE!")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }
                .padding(8)
                .background(.black.opacity(0.4))
                .cornerRadius(8)
                .padding(.top, 8)

                Spacer()

                // Sprint / speed indicator
                if game.isSprinting {
                    Text("SPRINTING")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.4))
                        .cornerRadius(6)
                        .padding(.bottom, 4)
                }

                // Controls
                HStack(spacing: 16) {
                    Label("Move", systemImage: "l.joystick")
                    Label("Look", systemImage: "r.joystick")
                    Label("Jump", systemImage: "circle")
                    Label("Sprint", systemImage: "l2.rectangle.roundedtop")
                    Label("Squat", systemImage: "r2.rectangle.roundedtop")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .padding(8)
                .background(.black.opacity(0.3))
                .cornerRadius(8)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            SoundManager.shared.playMusic()
        }
        .onDisappear {
            SoundManager.shared.stopMusic()
            SoundManager.shared.stopWalking()
        }
        .onChange(of: server.latestMessage?.pressedButtons) { game.updateInput(server.latestMessage) }
        .onChange(of: server.latestMessage?.leftStickX) { game.updateInput(server.latestMessage) }
        .onChange(of: server.latestMessage?.leftStickY) { game.updateInput(server.latestMessage) }
        .onChange(of: server.latestMessage?.rightStickX) { game.updateInput(server.latestMessage) }
        .onChange(of: server.latestMessage?.rightStickY) { game.updateInput(server.latestMessage) }
    }
}

// MARK: - SceneKit Wrapper

struct SceneViewWrapper: NSViewRepresentable {
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

// MARK: - Parkour Platform

struct ParkourPlatform {
    let position: SCNVector3
    let size: SCNVector3
    let color: NSColor
    let isCheckpoint: Bool

    init(_ x: Float, _ y: Float, _ z: Float, w: Float = 2, h: Float = 0.3, d: Float = 2, color: NSColor = .darkGray, checkpoint: Bool = false) {
        self.position = SCNVector3(x, y, z)
        self.size = SCNVector3(w, h, d)
        self.color = checkpoint ? .systemYellow : color
        self.isCheckpoint = checkpoint
    }
}

// MARK: - Game Engine

@Observable
class GameEngine {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let playerNode = SCNNode()
    private let bodyNode = SCNNode()
    private let cameraPivot = SCNNode()

    // Public state for HUD
    var checkpointIndex = 0
    var totalCheckpoints = 0
    var finished = false
    var isSprinting = false

    private var yaw: Float = 0
    private var pitch: Float = 0
    private var velocityY: Float = 0
    private var velocityX: Float = 0
    private var velocityZ: Float = 0
    private var isGrounded = false
    private var isSquatting = false
    private var canDoubleJump = true
    private var coyoteFrames: Int = 0 // grace frames after leaving a ledge
    private var lastGroundY: Float = 0
    private var jumpHeld = false // track button edge
    private var currentPlatformIndex: Int = -1 // platform we're standing on

    // Speeds
    private let walkSpeed: Float = 0.12
    private let sprintSpeed: Float = 0.25
    private let lookSpeed: Float = 0.04
    private let gravity: Float = -0.010
    private let jumpForce: Float = 0.26
    private let sprintJumpForce: Float = 0.32
    private let standHeight: Float = 1.8
    private let squatHeight: Float = 1.0
    private let airControl: Float = 0.6
    private let groundAccel: Float = 0.3 // how fast you reach target speed
    private let groundFriction: Float = 0.96 // slide when releasing stick
    private let airFriction: Float = 0.99 // barely any drag in air

    // Platforms & checkpoints
    private var platforms: [ParkourPlatform] = []
    private var platformNodes: [SCNNode] = []
    private var checkpointPositions: [SCNVector3] = []
    private var lastCheckpointPos = SCNVector3(0, 1, 0)

    private var _gameTimer: DispatchSourceTimer?
    private var lastMessage: ControllerMessage?

    init() {
        setupScene()
        buildParkourCourse()
        buildPlayer()
        setupCamera()
        startGameLoop()
    }

    // MARK: - Scene Setup

    private func setupScene() {
        // Ambient light
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(white: 0.35, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        // Sun
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = NSColor(white: 0.9, alpha: 1)
        sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred
        sun.light?.shadowSampleCount = 8
        sun.light?.shadowRadius = 3
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(sun)

        // Sky gradient
        scene.background.contents = NSColor(red: 0.45, green: 0.65, blue: 0.95, alpha: 1)

        // Fog for depth
        scene.fogStartDistance = 40
        scene.fogEndDistance = 120
        scene.fogColor = NSColor(red: 0.45, green: 0.65, blue: 0.95, alpha: 1)

        // Death plane (lava/void below)
        let deathPlane = SCNFloor()
        deathPlane.reflectivity = 0.3
        let deathNode = SCNNode(geometry: deathPlane)
        let deathMat = SCNMaterial()
        deathMat.diffuse.contents = NSColor(red: 0.15, green: 0.05, blue: 0.02, alpha: 1)
        deathMat.emission.contents = NSColor(red: 0.4, green: 0.1, blue: 0.0, alpha: 1)
        deathPlane.materials = [deathMat]
        deathNode.position = SCNVector3(0, -10, 0)
        scene.rootNode.addChildNode(deathNode)
    }

    private func buildParkourCourse() {
        platforms = [
            // === Section 1: Starting area ===
            ParkourPlatform(0, 0, 0, w: 6, h: 0.5, d: 6, color: .systemGreen, checkpoint: true),

            // Simple stepping stones
            ParkourPlatform(0, 0.5, -6, w: 3, h: 0.3, d: 2),
            ParkourPlatform(3, 1.0, -10, w: 2, h: 0.3, d: 2),
            ParkourPlatform(0, 1.5, -14, w: 2, h: 0.3, d: 2),
            ParkourPlatform(-3, 2.0, -18, w: 2, h: 0.3, d: 2),

            // === Section 2: Staircase sprint ===
            ParkourPlatform(-3, 2.5, -22, w: 4, h: 0.3, d: 4, color: .systemBlue, checkpoint: true),
            ParkourPlatform(-3, 3.0, -27, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(-3, 3.8, -30, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(-3, 4.6, -33, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(-3, 5.4, -36, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(-3, 6.0, -40, w: 2, h: 0.3, d: 2),

            // === Section 3: Long jumps (need sprint) ===
            ParkourPlatform(2, 6.0, -44, w: 2, h: 0.3, d: 2),
            ParkourPlatform(8, 6.0, -44, w: 2, h: 0.3, d: 2, color: .systemOrange, checkpoint: true),
            ParkourPlatform(14, 6.5, -44, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(20, 6.5, -44, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(25, 7.0, -44, w: 2, h: 0.3, d: 2),

            // === Section 4: Zigzag pillars ===
            ParkourPlatform(25, 7.5, -48, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(22, 8.0, -52, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(25, 8.5, -56, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(22, 9.0, -60, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(25, 9.5, -64, w: 3, h: 0.3, d: 3, color: .systemPurple, checkpoint: true),

            // === Section 5: Thin beams ===
            ParkourPlatform(25, 10.0, -68, w: 0.6, h: 0.3, d: 4),
            ParkourPlatform(25, 10.5, -74, w: 4, h: 0.3, d: 0.6),
            ParkourPlatform(22, 11.0, -74, w: 0.6, h: 0.3, d: 4),
            ParkourPlatform(22, 11.5, -80, w: 2, h: 0.3, d: 2),

            // === Section 6: Descending drops (need squat landing) ===
            ParkourPlatform(18, 9.5, -80, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(14, 7.5, -80, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(10, 5.5, -80, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(6, 4.0, -80, w: 2, h: 0.3, d: 2, color: .systemTeal, checkpoint: true),

            // === Section 7: Spiral ascent ===
            ParkourPlatform(6, 4.5, -84, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(3, 5.5, -87, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(0, 6.5, -84, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(-3, 7.5, -87, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(-6, 8.5, -84, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(-6, 9.5, -80, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(-6, 10.5, -76, w: 1.5, h: 0.3, d: 1.5),

            // === Section 8: Final sprint jump ===
            ParkourPlatform(-6, 11.0, -72, w: 4, h: 0.3, d: 3, color: .systemRed, checkpoint: true),
            ParkourPlatform(-6, 11.5, -64, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(-6, 12.0, -56, w: 1.5, h: 0.3, d: 1.5),
            ParkourPlatform(-6, 12.5, -48, w: 1.5, h: 0.3, d: 1.5),

            // === Finish platform ===
            ParkourPlatform(-6, 13.0, -42, w: 6, h: 0.5, d: 6, color: .systemGreen, checkpoint: true),
        ]

        // Count checkpoints
        checkpointPositions = []
        for plat in platforms {
            if plat.isCheckpoint {
                let cpY = plat.position.y + plat.size.y / 2 + 1
                checkpointPositions.append(SCNVector3(plat.position.x, cpY, plat.position.z))
            }
        }
        totalCheckpoints = checkpointPositions.count
        lastCheckpointPos = checkpointPositions.first ?? SCNVector3(0, 1, 0)

        // Build platform nodes
        for plat in platforms {
            let box = SCNBox(
                width: CGFloat(plat.size.x),
                height: CGFloat(plat.size.y),
                length: CGFloat(plat.size.z),
                chamferRadius: 0.02
            )
            let mat = SCNMaterial()
            mat.diffuse.contents = plat.color
            if plat.isCheckpoint {
                mat.emission.contents = NSColor.yellow.withAlphaComponent(0.15)
            }
            box.materials = [mat]
            let node = SCNNode(geometry: box)
            node.position = plat.position
            node.castsShadow = true
            scene.rootNode.addChildNode(node)
            platformNodes.append(node)

            // Add glowing ring for checkpoints
            if plat.isCheckpoint {
                let ring = SCNTorus(ringRadius: CGFloat(max(plat.size.x, plat.size.z)) * 0.6, pipeRadius: 0.04)
                let ringMat = SCNMaterial()
                ringMat.diffuse.contents = NSColor.yellow
                ringMat.emission.contents = NSColor.yellow
                ring.materials = [ringMat]
                let ringNode = SCNNode(geometry: ring)
                let ringY = plat.position.y + plat.size.y / 2 + 0.5
                ringNode.position = SCNVector3(plat.position.x, ringY, plat.position.z)
                // Slow rotation
                let spin = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 4)
                ringNode.runAction(.repeatForever(spin))
                scene.rootNode.addChildNode(ringNode)
            }
        }

        // Decorative pillars along the course
        addPillar(at: SCNVector3(5, 0, -10), height: 8)
        addPillar(at: SCNVector3(-8, 0, -20), height: 12)
        addPillar(at: SCNVector3(15, 0, -44), height: 10)
        addPillar(at: SCNVector3(30, 0, -50), height: 15)
        addPillar(at: SCNVector3(-10, 0, -80), height: 14)
        addPillar(at: SCNVector3(0, 0, -60), height: 18)
    }

    private func addPillar(at pos: SCNVector3, height: Float) {
        let pillar = SCNCylinder(radius: 0.4, height: CGFloat(height))
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(white: 0.25, alpha: 1)
        pillar.materials = [mat]
        let node = SCNNode(geometry: pillar)
        let pillarY = pos.y + CGFloat(height) / 2
        node.position = SCNVector3(pos.x, pillarY, pos.z)
        node.castsShadow = true
        scene.rootNode.addChildNode(node)
    }

    private func buildPlayer() {
        let bodyCapsule = SCNCapsule(capRadius: 0.25, height: CGFloat(standHeight))
        let bodyMat = SCNMaterial()
        bodyMat.diffuse.contents = NSColor.systemOrange
        bodyCapsule.materials = [bodyMat]
        bodyNode.geometry = bodyCapsule
        bodyNode.position = SCNVector3(0, CGFloat(standHeight) / 2, 0)
        // Player body is invisible in first person, but casts shadow
        bodyNode.opacity = 0
        bodyNode.castsShadow = true
        playerNode.addChildNode(bodyNode)

        playerNode.position = SCNVector3(0, 1, 0)
        scene.rootNode.addChildNode(playerNode)
    }

    private func setupCamera() {
        cameraPivot.position = SCNVector3(0, CGFloat(standHeight) * 0.85, 0)
        playerNode.addChildNode(cameraPivot)

        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 80
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 200
        cameraNode.position = SCNVector3(0, 0, 0)
        cameraPivot.addChildNode(cameraNode)
    }

    // MARK: - Game Loop

    func updateInput(_ message: ControllerMessage?) {
        lastMessage = message
    }

    private func startGameLoop() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        _gameTimer = timer
    }

    private func tick() {
        guard let msg = lastMessage else { return }
        let buttons = msg.pressedButtons

        // -- Look --
        let rx = Float(msg.rightStickX)
        let ry = Float(msg.rightStickY)
        if abs(rx) > 0.1 { yaw -= rx * lookSpeed }
        if abs(ry) > 0.1 { pitch -= ry * lookSpeed }
        pitch = max(-Float.pi / 2.5, min(Float.pi / 2.5, pitch))
        cameraPivot.eulerAngles = SCNVector3(CGFloat(pitch), 0, 0)
        playerNode.eulerAngles = SCNVector3(0, CGFloat(yaw), 0)

        // -- Sprint (L2) --
        let wantsSprint = buttons.contains("L2")
        isSprinting = wantsSprint && !isSquatting

        // -- Move --
        let lx = Float(msg.leftStickX)
        let ly = Float(msg.leftStickY)
        let speed: Float
        if isSquatting {
            speed = walkSpeed * 0.7
        } else if isSprinting {
            speed = sprintSpeed
        } else {
            speed = walkSpeed
        }

        let fwdX = -sin(yaw)
        let fwdZ = -cos(yaw)
        let rightX = cos(yaw)
        let rightZ = -sin(yaw)

        let hasInput = abs(lx) > 0.05 || abs(ly) > 0.05

        if hasInput {
            velocityX = (fwdX * (-ly) + rightX * lx) * speed
            velocityZ = (fwdZ * (-ly) + rightZ * lx) * speed
            if isGrounded {
                SoundManager.shared.startWalking(sprinting: isSprinting)
            } else {
                SoundManager.shared.stopWalking()
            }
        } else {
            SoundManager.shared.stopWalking()
            if isGrounded {
                velocityX = 0
                velocityZ = 0
            }
        }

        // -- Jump (Circle) — only trigger on button press, not hold --
        let jumpDown = buttons.contains("Circle")
        let jumpJustPressed = jumpDown && !jumpHeld
        jumpHeld = jumpDown

        if jumpJustPressed {
            if isGrounded || coyoteFrames > 0 {
                var force = isSprinting ? sprintJumpForce : jumpForce
                if isSquatting { force *= 0.2 }
                velocityY = force
                velocityX = 0
                velocityZ = 0
                isGrounded = false
                coyoteFrames = 0
                canDoubleJump = true
                SoundManager.shared.stopWalking()
                SoundManager.shared.playJump()
            } else if canDoubleJump && !isGrounded {
                velocityY = jumpForce * 0.7
                velocityX = 0
                velocityZ = 0
                canDoubleJump = false
                SoundManager.shared.playJump()
            }
        }

        // -- Squat (R2) --
        let wantsSquat = buttons.contains("R2")
        if wantsSquat != isSquatting {
            isSquatting = wantsSquat
            let height = isSquatting ? squatHeight : standHeight
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.1
            cameraPivot.position = SCNVector3(0, CGFloat(height) * 0.85, 0)
            SCNTransaction.commit()
        }

        // -- Gravity (5x faster when squatting mid-air) --
        let grav = (isSquatting && !isGrounded) ? gravity * 5 : gravity
        velocityY += grav

        // -- Apply movement --
        var pos = playerNode.position

        // Clamp to current platform edges while squatting (before moving)
        let playerRadius: Float = 0.25
        if isSquatting && isGrounded && currentPlatformIndex >= 0 {
            let plat = platforms[currentPlatformIndex]
            let px = Float(plat.position.x)
            let pz = Float(plat.position.z)
            let hw = Float(plat.size.x) / 2
            let hd = Float(plat.size.z) / 2
            let newX = Float(pos.x) + velocityX
            let newZ = Float(pos.z) + velocityZ
            velocityX = max(px - hw, min(px + hw, newX)) - Float(pos.x)
            velocityZ = max(pz - hd, min(pz + hd, newZ)) - Float(pos.z)
        }

        pos.x += CGFloat(velocityX)
        pos.z += CGFloat(velocityZ)
        pos.y += CGFloat(velocityY)

        // -- Platform collision --
        let wasGrounded = isGrounded
        isGrounded = false
        let feetY = Float(pos.y)

        for (i, plat) in platforms.enumerated() {
            let px = Float(plat.position.x)
            let py = Float(plat.position.y)
            let pz = Float(plat.position.z)
            let hw = Float(plat.size.x) / 2 + playerRadius
            let hh = Float(plat.size.y) / 2
            let hd = Float(plat.size.z) / 2 + playerRadius

            let onX = Float(pos.x) >= px - hw && Float(pos.x) <= px + hw
            let onZ = Float(pos.z) >= pz - hd && Float(pos.z) <= pz + hd
            let platTop = py + hh

            if onX && onZ && feetY <= platTop + 0.1 && feetY >= platTop - 0.5 && velocityY <= 0 {
                pos.y = CGFloat(platTop)
                velocityY = 0
                isGrounded = true
                lastGroundY = platTop
                canDoubleJump = true
                currentPlatformIndex = i

                // Check checkpoint
                if plat.isCheckpoint {
                    let cpIndex = checkpointPositions.firstIndex(where: {
                        abs(Float($0.x) - px) < 0.1 && abs(Float($0.z) - pz) < 0.1
                    }) ?? -1
                    if cpIndex >= 0 && cpIndex + 1 > checkpointIndex {
                        checkpointIndex = cpIndex + 1
                        lastCheckpointPos = checkpointPositions[cpIndex]
                        if checkpointIndex >= totalCheckpoints {
                            finished = true
                        }
                    }
                }
                break
            }
        }

        // Landing sound
        if !wasGrounded && isGrounded {
            SoundManager.shared.playLand()
        }

        // Coyote time
        if wasGrounded && !isGrounded {
            coyoteFrames = 6
            currentPlatformIndex = -1
        } else if coyoteFrames > 0 {
            coyoteFrames -= 1
        }

        // -- Fall respawn --
        if Float(pos.y) < -15 {
            respawn()
            return
        }

        playerNode.position = pos

        // -- FOV effect when sprinting --
        let targetFOV: CGFloat = isSprinting ? 90 : 80
        if let cam = cameraNode.camera {
            cam.fieldOfView += (targetFOV - cam.fieldOfView) * 0.1
        }
    }

    private func respawn() {
        playerNode.position = lastCheckpointPos
        velocityX = 0
        velocityY = 0
        velocityZ = 0
        isGrounded = false
        isSquatting = false
        canDoubleJump = true
        coyoteFrames = 0
    }
}
#endif
