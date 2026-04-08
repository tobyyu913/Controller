//
//  iPadReceiverView.swift
//  Controller
//
//  iPad receiver: runs a server, phones connect as clients. Shows parkour game + debug.
//

#if os(iOS)
import SwiftUI
import SceneKit
import Network
import GameController

// MARK: - Bluetooth Gamepad Receiver (uses GCController to detect BT HID gamepads)

@Observable
class BluetoothGamepadReceiver {
    var connectedControllers: [String] = []
    var latestMessage: ControllerMessage?
    var isActive = false

    private var pollTimer: DispatchSourceTimer?

    func start() {
        isActive = true
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            self?.updateControllerList()
            if let gc = note.object as? GCController {
                self?.bindController(gc)
            }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.updateControllerList()
        }
        GCController.startWirelessControllerDiscovery {}
        // Bind any already-connected controllers
        for gc in GCController.controllers() {
            bindController(gc)
        }
        updateControllerList()
    }

    func stop() {
        isActive = false
        GCController.stopWirelessControllerDiscovery()
        NotificationCenter.default.removeObserver(self)
        connectedControllers = []
        latestMessage = nil
    }

    private func updateControllerList() {
        connectedControllers = GCController.controllers().map { $0.vendorName ?? "Controller" }
    }

    private func bindController(_ gc: GCController) {
        guard let gamepad = gc.extendedGamepad else { return }

        gamepad.valueChangedHandler = { [weak self] pad, _ in
            var buttons: [String] = []

            if pad.buttonA.isPressed { buttons.append("Cross") }
            if pad.buttonB.isPressed { buttons.append("Circle") }
            if pad.buttonX.isPressed { buttons.append("Square") }
            if pad.buttonY.isPressed { buttons.append("Triangle") }
            if pad.leftShoulder.isPressed { buttons.append("L1") }
            if pad.rightShoulder.isPressed { buttons.append("R1") }
            if pad.leftTrigger.isPressed { buttons.append("L2") }
            if pad.rightTrigger.isPressed { buttons.append("R2") }
            if pad.dpad.up.isPressed { buttons.append("DPadUp") }
            if pad.dpad.down.isPressed { buttons.append("DPadDown") }
            if pad.dpad.left.isPressed { buttons.append("DPadLeft") }
            if pad.dpad.right.isPressed { buttons.append("DPadRight") }
            if pad.leftThumbstickButton?.isPressed == true { buttons.append("L3") }
            if pad.rightThumbstickButton?.isPressed == true { buttons.append("R3") }
            if pad.buttonOptions?.isPressed == true { buttons.append("Create") }
            if pad.buttonMenu.isPressed { buttons.append("Options") }
            if pad.buttonHome?.isPressed == true { buttons.append("PS") }

            let msg = ControllerMessage(
                pressedButtons: buttons,
                leftStickX: Double(pad.leftThumbstick.xAxis.value),
                leftStickY: Double(-pad.leftThumbstick.yAxis.value),
                rightStickX: Double(pad.rightThumbstick.xAxis.value),
                rightStickY: Double(-pad.rightThumbstick.yAxis.value)
            )

            DispatchQueue.main.async {
                self?.latestMessage = msg
            }
        }
    }
}

// MARK: - iPad Root View

struct iPadReceiverView: View {
    @State private var server = ControllerServer()
    @State private var btReceiver = BluetoothGamepadReceiver()
    @State private var selectedTab = 0
    @State private var useWifi = true  // true = WiFi server, false = Bluetooth gamepad

    var body: some View {
        VStack(spacing: 0) {
            // WiFi / Bluetooth toggle
            HStack(spacing: 12) {
                Spacer()

                Text("Input Source:")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)

                Picker("", selection: $useWifi) {
                    Text("WiFi").tag(true)
                    Text("Bluetooth").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .onChange(of: useWifi) {
                    if useWifi {
                        btReceiver.stop()
                        server.start()
                    } else {
                        server.stop()
                        btReceiver.start()
                    }
                }

                if !useWifi {
                    let count = btReceiver.connectedControllers.count
                    HStack(spacing: 4) {
                        Circle()
                            .fill(count > 0 ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(count > 0 ? "\(count) gamepad\(count == 1 ? "" : "s")" : "Scanning...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .background(Color(.systemBackground).opacity(0.95))

            TabView(selection: $selectedTab) {
                iPadUniversalView(server: server)
                    .tabItem { Label("Universal", systemImage: "keyboard") }
                    .tag(0)
                iPadGameView(server: server)
                    .tabItem { Label("Parkour", systemImage: "gamecontroller") }
                    .tag(1)
                DualGameView(server: server)
                    .tabItem { Label("Co-op", systemImage: "person.2") }
                    .tag(2)
                iPadDebugView(server: server)
                    .tabItem { Label("Debug", systemImage: "antenna.radiowaves.left.and.right") }
                    .tag(3)
            }
        }
        .onAppear {
            if useWifi { server.start() } else { btReceiver.start() }
        }
        .onDisappear {
            server.stop()
            btReceiver.stop()
        }
        // Feed BT gamepad input into the server's latestMessage so all tabs work
        .onChange(of: btReceiver.latestMessage?.pressedButtons) {
            if !useWifi { server.latestMessage = btReceiver.latestMessage }
        }
        .onChange(of: btReceiver.latestMessage?.leftStickX) {
            if !useWifi { server.latestMessage = btReceiver.latestMessage }
        }
        .onChange(of: btReceiver.latestMessage?.leftStickY) {
            if !useWifi { server.latestMessage = btReceiver.latestMessage }
        }
        .onChange(of: btReceiver.latestMessage?.rightStickX) {
            if !useWifi { server.latestMessage = btReceiver.latestMessage }
        }
        .onChange(of: btReceiver.latestMessage?.rightStickY) {
            if !useWifi { server.latestMessage = btReceiver.latestMessage }
        }
    }
}

// MARK: - iPad Game View (SceneKit Parkour)

struct iPadGameView: View {
    let server: ControllerServer
    @State private var game = iPadGameEngine()

    var body: some View {
        ZStack {
            iPadSceneView(scene: game.scene, pointOfView: game.cameraNode)
                .ignoresSafeArea()

            // Crosshair
            ZStack {
                Rectangle().fill(Color.white.opacity(0.8)).frame(width: 16, height: 2)
                Rectangle().fill(Color.white.opacity(0.8)).frame(width: 2, height: 16)
            }

            VStack {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(server.connectedPeer != nil ? .green : (server.isSearching ? .orange : .gray))
                            .frame(width: 8, height: 8)
                        Text(server.connectedPeer != nil ? "Controller connected" : "Server running — waiting...")
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
                .padding(8).background(.black.opacity(0.4)).cornerRadius(8).padding(.top, 8)

                Spacer()

                if game.isSprinting {
                    Text("SPRINTING")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.black.opacity(0.4)).cornerRadius(6).padding(.bottom, 4)
                }

                HStack(spacing: 16) {
                    Label("Move", systemImage: "l.joystick")
                    Label("Look", systemImage: "r.joystick")
                    Label("Jump", systemImage: "circle")
                    Label("Sprint", systemImage: "l2.rectangle.roundedtop")
                    Label("Squat", systemImage: "r2.rectangle.roundedtop")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .padding(8).background(.black.opacity(0.3)).cornerRadius(8).padding(.bottom, 8)
            }
        }
        .onChange(of: server.latestMessage?.pressedButtons) { game.updateInput(server.latestMessage) }
        .onChange(of: server.latestMessage?.leftStickX) { game.updateInput(server.latestMessage) }
        .onChange(of: server.latestMessage?.leftStickY) { game.updateInput(server.latestMessage) }
        .onChange(of: server.latestMessage?.rightStickX) { game.updateInput(server.latestMessage) }
        .onChange(of: server.latestMessage?.rightStickY) { game.updateInput(server.latestMessage) }
    }
}

struct iPadSceneView: UIViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(); v.scene = scene; v.pointOfView = pointOfView
        v.backgroundColor = .black; v.antialiasingMode = .multisampling4X; v.isPlaying = true; return v
    }
    func updateUIView(_ v: SCNView, context: Context) { v.pointOfView = pointOfView }
}

// MARK: - iPad Game Engine

@Observable
class iPadGameEngine {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let playerNode = SCNNode()
    private let cameraPivot = SCNNode()

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
    private var coyoteFrames: Int = 0
    private var lastGroundY: Float = 0
    private var jumpHeld = false
    private var currentPlatformIndex: Int = -1

    private let walkSpeed: Float = 0.12, sprintSpeed: Float = 0.25, lookSpeed: Float = 0.04
    private let gravity: Float = -0.010, jumpForce: Float = 0.26, sprintJumpForce: Float = 0.32
    private let standHeight: Float = 1.8, squatHeight: Float = 1.0

    private var platforms: [(pos: SCNVector3, size: SCNVector3, checkpoint: Bool)] = []
    private var checkpointPositions: [SCNVector3] = []
    private var lastCheckpointPos = SCNVector3(0, 1, 0)
    private var _gameTimer: DispatchSourceTimer?
    private var lastMessage: ControllerMessage?

    init() { setupScene(); buildCourse(); buildPlayer(); setupCamera(); startLoop() }

    private func setupScene() {
        let a = SCNNode(); a.light = SCNLight(); a.light?.type = .ambient
        a.light?.color = UIColor(white: 0.35, alpha: 1); scene.rootNode.addChildNode(a)
        let s = SCNNode(); s.light = SCNLight(); s.light?.type = .directional
        s.light?.color = UIColor(white: 0.9, alpha: 1); s.light?.castsShadow = true
        s.eulerAngles = SCNVector3(-Float.pi/3, Float.pi/4, 0); scene.rootNode.addChildNode(s)
        scene.background.contents = UIColor(red: 0.45, green: 0.65, blue: 0.95, alpha: 1)
        scene.fogStartDistance = 40; scene.fogEndDistance = 120
        scene.fogColor = UIColor(red: 0.45, green: 0.65, blue: 0.95, alpha: 1)
        let dp = SCNFloor(); dp.reflectivity = 0.3; let dn = SCNNode(geometry: dp)
        let dm = SCNMaterial(); dm.diffuse.contents = UIColor(red:0.15,green:0.05,blue:0.02,alpha:1)
        dm.emission.contents = UIColor(red:0.4,green:0.1,blue:0,alpha:1); dp.materials = [dm]
        dn.position = SCNVector3(0,-10,0); scene.rootNode.addChildNode(dn)
    }

    private func buildCourse() {
        let d: [(Float,Float,Float,Float,Float,Float,Bool)] = [
            (0,0,0,6,0.5,6,true),(0,0.5,-6,3,0.3,2,false),(3,1,-10,2,0.3,2,false),
            (0,1.5,-14,2,0.3,2,false),(-3,2,-18,2,0.3,2,false),(-3,2.5,-22,4,0.3,4,true),
            (-3,3,-27,1.5,0.3,1.5,false),(-3,3.8,-30,1.5,0.3,1.5,false),
            (-3,4.6,-33,1.5,0.3,1.5,false),(-3,5.4,-36,1.5,0.3,1.5,false),(-3,6,-40,2,0.3,2,false),
            (2,6,-44,2,0.3,2,false),(8,6,-44,2,0.3,2,true),(14,6.5,-44,1.5,0.3,1.5,false),
            (20,6.5,-44,1.5,0.3,1.5,false),(25,7,-44,2,0.3,2,false),
            (25,7.5,-48,1.5,0.3,1.5,false),(22,8,-52,1.5,0.3,1.5,false),
            (25,8.5,-56,1.5,0.3,1.5,false),(22,9,-60,1.5,0.3,1.5,false),(25,9.5,-64,3,0.3,3,true),
            (25,10,-68,0.6,0.3,4,false),(25,10.5,-74,4,0.3,0.6,false),
            (22,11,-74,0.6,0.3,4,false),(22,11.5,-80,2,0.3,2,false),
            (18,9.5,-80,1.5,0.3,1.5,false),(14,7.5,-80,1.5,0.3,1.5,false),
            (10,5.5,-80,1.5,0.3,1.5,false),(6,4,-80,2,0.3,2,true),
            (6,4.5,-84,1.5,0.3,1.5,false),(3,5.5,-87,1.5,0.3,1.5,false),
            (0,6.5,-84,1.5,0.3,1.5,false),(-3,7.5,-87,1.5,0.3,1.5,false),
            (-6,8.5,-84,1.5,0.3,1.5,false),(-6,9.5,-80,1.5,0.3,1.5,false),
            (-6,10.5,-76,1.5,0.3,1.5,false),(-6,11,-72,4,0.3,3,true),
            (-6,11.5,-64,1.5,0.3,1.5,false),(-6,12,-56,1.5,0.3,1.5,false),
            (-6,12.5,-48,1.5,0.3,1.5,false),(-6,13,-42,6,0.5,6,true),
        ]
        for p in d {
            let pos = SCNVector3(p.0,p.1,p.2); let sz = SCNVector3(p.3,p.4,p.5)
            platforms.append((pos:pos, size:sz, checkpoint:p.6))
            let b = SCNBox(width:CGFloat(p.3),height:CGFloat(p.4),length:CGFloat(p.5),chamferRadius:0.02)
            let m = SCNMaterial(); m.diffuse.contents = p.6 ? UIColor.systemYellow : UIColor.darkGray
            if p.6 { m.emission.contents = UIColor.yellow.withAlphaComponent(0.15) }
            b.materials = [m]; let n = SCNNode(geometry:b); n.position = pos; n.castsShadow = true
            scene.rootNode.addChildNode(n)
            if p.6 {
                checkpointPositions.append(SCNVector3(p.0, p.1+p.4/2+1, p.2))
                let r = SCNTorus(ringRadius:CGFloat(max(p.3,p.5))*0.6, pipeRadius:0.04)
                let rm = SCNMaterial(); rm.diffuse.contents = UIColor.yellow; rm.emission.contents = UIColor.yellow
                r.materials = [rm]; let rn = SCNNode(geometry:r)
                rn.position = SCNVector3(p.0, p.1+p.4/2+0.5, p.2)
                rn.runAction(.repeatForever(.rotateBy(x:0,y:.pi*2,z:0,duration:4)))
                scene.rootNode.addChildNode(rn)
            }
        }
        totalCheckpoints = checkpointPositions.count
        lastCheckpointPos = checkpointPositions.first ?? SCNVector3(0,1,0)
    }

    private func buildPlayer() {
        let c = SCNCapsule(capRadius:0.25, height:CGFloat(standHeight))
        let m = SCNMaterial(); m.diffuse.contents = UIColor.systemOrange; c.materials = [m]
        let bn = SCNNode(geometry:c); bn.position = SCNVector3(0,standHeight/2,0)
        bn.opacity = 0; bn.castsShadow = true; playerNode.addChildNode(bn)
        playerNode.position = SCNVector3(0,1,0); scene.rootNode.addChildNode(playerNode)
    }

    private func setupCamera() {
        cameraPivot.position = SCNVector3(0, standHeight*0.85, 0)
        playerNode.addChildNode(cameraPivot)
        cameraNode.camera = SCNCamera(); cameraNode.camera?.fieldOfView = 80
        cameraNode.camera?.zNear = 0.1; cameraNode.camera?.zFar = 200
        cameraPivot.addChildNode(cameraNode)
    }

    func updateInput(_ msg: ControllerMessage?) { lastMessage = msg }

    private func startLoop() {
        let t = DispatchSource.makeTimerSource(queue:.main)
        t.schedule(deadline:.now(), repeating:.milliseconds(16))
        t.setEventHandler { [weak self] in self?.tick() }; t.resume(); _gameTimer = t
    }

    private func tick() {
        guard let msg = lastMessage else { return }
        let buttons = msg.pressedButtons
        let rx = Float(msg.rightStickX), ry = Float(msg.rightStickY)
        if abs(rx)>0.1 { yaw -= rx*lookSpeed }; if abs(ry)>0.1 { pitch -= ry*lookSpeed }
        pitch = max(-Float.pi/2.5, min(Float.pi/2.5, pitch))
        cameraPivot.eulerAngles = SCNVector3(pitch,0,0)
        playerNode.eulerAngles = SCNVector3(0,yaw,0)

        isSprinting = buttons.contains("L2") && !isSquatting
        let lx = Float(msg.leftStickX), ly = Float(msg.leftStickY)
        let spd: Float = isSquatting ? walkSpeed*0.7 : (isSprinting ? sprintSpeed : walkSpeed)
        let fX = -sin(yaw), fZ = -cos(yaw), rX = cos(yaw), rZ = -sin(yaw)
        let has = abs(lx)>0.05 || abs(ly)>0.05
        if has { velocityX = (fX*(-ly)+rX*lx)*spd; velocityZ = (fZ*(-ly)+rZ*lx)*spd }
        else if isGrounded { velocityX = 0; velocityZ = 0 }

        let jd = buttons.contains("Circle"); let jp = jd && !jumpHeld; jumpHeld = jd
        if jp {
            if isGrounded || coyoteFrames>0 {
                var f = isSprinting ? sprintJumpForce : jumpForce
                if isSquatting { f *= 0.2 }
                velocityY = f; velocityX = 0; velocityZ = 0
                isGrounded = false; coyoteFrames = 0; canDoubleJump = true
            } else if canDoubleJump && !isGrounded {
                velocityY = jumpForce*0.7; velocityX = 0; velocityZ = 0; canDoubleJump = false
            }
        }

        let ws = buttons.contains("R2")
        if ws != isSquatting {
            isSquatting = ws; let h = isSquatting ? squatHeight : standHeight
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.1
            cameraPivot.position = SCNVector3(0, h*0.85, 0); SCNTransaction.commit()
        }

        let g = (isSquatting && !isGrounded) ? gravity*5 : gravity; velocityY += g
        var pos = playerNode.position; let pr: Float = 0.25
        if isSquatting && isGrounded && currentPlatformIndex >= 0 {
            let p = platforms[currentPlatformIndex]
            let px=p.pos.x, pz=p.pos.z, hw=p.size.x/2, hd=p.size.z/2
            velocityX = max(px-hw, min(px+hw, pos.x+velocityX)) - pos.x
            velocityZ = max(pz-hd, min(pz+hd, pos.z+velocityZ)) - pos.z
        }
        pos.x += velocityX; pos.z += velocityZ; pos.y += velocityY

        let wg = isGrounded; isGrounded = false
        for (i,p) in platforms.enumerated() {
            let px=p.pos.x, py=p.pos.y, pz=p.pos.z
            let hw=p.size.x/2+pr, hh=p.size.y/2, hd=p.size.z/2+pr, pt=py+hh
            if pos.x>=px-hw && pos.x<=px+hw && pos.z>=pz-hd && pos.z<=pz+hd &&
               pos.y<=pt+0.1 && pos.y>=pt-0.5 && velocityY<=0 {
                pos.y = pt; velocityY = 0; isGrounded = true; canDoubleJump = true
                currentPlatformIndex = i
                if p.checkpoint {
                    let ci = checkpointPositions.firstIndex(where:{abs($0.x-px)<0.1 && abs($0.z-pz)<0.1}) ?? -1
                    if ci>=0 && ci+1>checkpointIndex {
                        checkpointIndex = ci+1; lastCheckpointPos = checkpointPositions[ci]
                        if checkpointIndex>=totalCheckpoints { finished = true }
                    }
                }; break
            }
        }
        if wg && !isGrounded { coyoteFrames = 6; currentPlatformIndex = -1 }
        else if coyoteFrames>0 { coyoteFrames -= 1 }
        if pos.y < -15 { respawn(); return }
        playerNode.position = pos
        let fov: CGFloat = isSprinting ? 90 : 80
        if let c = cameraNode.camera { c.fieldOfView += (fov - c.fieldOfView)*0.1 }
    }

    private func respawn() {
        playerNode.position = lastCheckpointPos
        velocityX=0; velocityY=0; velocityZ=0; isGrounded=false; isSquatting=false; canDoubleJump=true; coyoteFrames=0
    }
}

// MARK: - iPad Universal View

struct iPadUniversalView: View {
    let server: ControllerServer

    // Default mapping table (matches Mac Universal defaults)
    private let mappings: [(String, String)] = [
        ("Left Stick Up", "W"),
        ("Left Stick Down", "S"),
        ("Left Stick Left", "A"),
        ("Left Stick Right", "D"),
        ("Right Stick", "Mouse"),
        ("D-Pad Up", "Arrow Up"),
        ("D-Pad Down", "Arrow Down"),
        ("D-Pad Left", "Arrow Left"),
        ("D-Pad Right", "Arrow Right"),
        ("Cross", "Space"),
        ("Circle", "E"),
        ("Triangle", "Q"),
        ("Square", "F"),
        ("L1", "1"),
        ("L2", "Shift"),
        ("R1", "2"),
        ("R2", "Ctrl"),
        ("L3", "V"),
        ("R3", "B"),
        ("Options", "Escape"),
        ("Create", "Tab"),
        ("PS", "P"),
        ("Touchpad", "M"),
    ]

    var body: some View {
        VStack(spacing: 12) {
            // Connection status
            HStack(spacing: 8) {
                Circle()
                    .fill(server.connectedPeer != nil ? .green : (server.isSearching ? .orange : .gray))
                    .frame(width: 10, height: 10)
                Text(server.connectedPeer != nil ? "Connected: \(server.connectedPeer!)" : "Server running — waiting for controllers...")
                    .font(.system(.body, design: .monospaced))
            }

            // Connected clients list
            if !server.connectedClients.isEmpty {
                HStack(spacing: 8) {
                    ForEach(server.connectedClients) { client in
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            Text(client.name)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }

            Divider()

            // Info banner
            HStack {
                Image(systemName: "keyboard")
                    .foregroundStyle(.blue)
                Text("Keyboard/Mouse Emulation")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Spacer()
                Text("macOS only")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(4)
            }

            Divider()

            // Mapping table header
            HStack {
                Text("Controller")
                    .frame(width: 160, alignment: .leading)
                Text("Mapped Key")
                    .frame(width: 120, alignment: .leading)
                Text("")
                    .frame(width: 40)
                Spacer()
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.15))

            // Mapping rows with live activity indicators
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(mappings.enumerated()), id: \.offset) { i, mapping in
                        HStack {
                            Text(mapping.0)
                                .font(.system(size: 13, design: .monospaced))
                                .frame(width: 160, alignment: .leading)

                            Text(mapping.1)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.blue)
                                .frame(width: 120, alignment: .leading)

                            // Live activity indicator
                            Circle()
                                .fill(isActive(mapping.0) ? .green : .clear)
                                .frame(width: 8, height: 8)
                                .frame(width: 40)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(i % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
                    }
                }
            }
        }
        .padding()
    }

    private func isActive(_ label: String) -> Bool {
        guard let msg = server.latestMessage else { return false }
        let b = msg.pressedButtons
        switch label {
        case "Left Stick Up": return msg.leftStickY < -0.3
        case "Left Stick Down": return msg.leftStickY > 0.3
        case "Left Stick Left": return msg.leftStickX < -0.3
        case "Left Stick Right": return msg.leftStickX > 0.3
        case "Right Stick": return abs(msg.rightStickX) > 0.1 || abs(msg.rightStickY) > 0.1
        case "D-Pad Up": return b.contains("DPadUp")
        case "D-Pad Down": return b.contains("DPadDown")
        case "D-Pad Left": return b.contains("DPadLeft")
        case "D-Pad Right": return b.contains("DPadRight")
        case "Cross": return b.contains("Cross")
        case "Circle": return b.contains("Circle")
        case "Triangle": return b.contains("Triangle")
        case "Square": return b.contains("Square")
        case "L1": return b.contains("L1")
        case "L2": return b.contains("L2")
        case "R1": return b.contains("R1")
        case "R2": return b.contains("R2")
        case "L3": return b.contains("L3")
        case "R3": return b.contains("R3")
        case "Options": return b.contains("Options")
        case "Create": return b.contains("Create")
        case "PS": return b.contains("PS")
        case "Touchpad": return b.contains("Touchpad")
        default: return false
        }
    }
}

// MARK: - iPad Debug View

struct iPadDebugView: View {
    let server: ControllerServer

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle().fill(server.connectedPeer != nil ? .green : (server.isSearching ? .orange : .gray))
                    .frame(width: 12, height: 12)
                Text(statusText)
                    .font(.system(.body, design: .monospaced))
            }.padding(.top, 20)

            // Connected clients list
            if !server.connectedClients.isEmpty {
                HStack(spacing: 8) {
                    ForEach(server.connectedClients) { client in
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            Text(client.name)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }

            Divider()

            if let msg = server.latestMessage {
                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment:.leading, spacing:12) {
                        stickV("L Stick", msg.leftStickX, msg.leftStickY)
                        btnV("Triggers", ["L1","L2"], msg.pressedButtons)
                        btnV("D-Pad", ["DPadUp","DPadDown","DPadLeft","DPadRight"], msg.pressedButtons)
                    }
                    VStack(spacing:12) { btnV("System", ["Create","Options","PS","Touchpad"], msg.pressedButtons) }
                    VStack(alignment:.leading, spacing:12) {
                        stickV("R Stick", msg.rightStickX, msg.rightStickY)
                        btnV("Triggers", ["R1","R2"], msg.pressedButtons)
                        btnV("Face", ["Triangle","Circle","Cross","Square"], msg.pressedButtons)
                    }
                }
            } else {
                Spacer()
                VStack(spacing:8) {
                    Image(systemName:"gamecontroller").font(.system(size:48)).foregroundStyle(.secondary)
                    Text("Waiting for Controller").font(.title2)
                    Text("Open Controller app on phone.\nServer running on port 9876.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }; Spacer()
            }
            Spacer()
        }.padding()
    }

    private var statusText: String {
        if let peer = server.connectedPeer {
            return "Connected: \(peer)"
        } else if server.isSearching {
            let ip = server.getLocalIP()
            return "Server running (\(ip):9876)"
        } else if let error = server.errorMessage {
            return "Error: \(error)"
        } else {
            return "Starting server..."
        }
    }

    func stickV(_ l: String, _ x: Double, _ y: Double) -> some View {
        VStack(spacing:4) {
            Text(l).font(.caption.bold())
            ZStack {
                Circle().stroke(Color.gray.opacity(0.3),lineWidth:1).frame(width:80,height:80)
                Circle().fill(Color.blue).frame(width:14,height:14).offset(x:x*35,y:y*35)
            }
            Text(String(format:"%.2f, %.2f",x,y)).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
        }
    }
    func btnV(_ t: String, _ bs: [String], _ p: [String]) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(t).font(.caption.bold())
            HStack(spacing:4) {
                ForEach(bs,id:\.self) { b in
                    Text(b.replacingOccurrences(of:"DPad",with:""))
                        .font(.system(size:11,design:.monospaced))
                        .padding(.horizontal,6).padding(.vertical,3)
                        .background(p.contains(b) ? Color.blue : Color.gray.opacity(0.15))
                        .foregroundStyle(p.contains(b) ? .white : .primary).cornerRadius(4)
                }
            }
        }
    }
}
#endif
