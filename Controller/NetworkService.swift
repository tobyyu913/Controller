//
//  NetworkService.swift
//  Controller
//
//  Server-client networking: macOS/iPad runs a TCP server, phones connect as clients.
//

import Foundation
import Network
import SwiftUI

private let fixedPort: UInt16 = 9876

// MARK: - Controller Server (macOS & iPad — accepts multiple phone clients)

// Lightweight diagnostics: records message arrival times, dumps timing stats
// to /tmp/controller_input_stats.txt every ~2s while input flows.
final class InputTrace {
    static let shared = InputTrace()
    private var times: [Double] = []
    private let q = DispatchQueue(label: "controller.trace")

    func record() {
        let now = CFAbsoluteTimeGetCurrent()
        q.async {
            self.times.append(now)
            if self.times.count % 256 == 0 { self.dump() }
            if self.times.count > 20000 { self.times.removeFirst(10000) }
        }
    }

    private func dump() {
        let arr = Array(times.suffix(2000))
        guard arr.count > 50 else { return }
        var gaps: [Double] = []
        for i in 1..<arr.count { gaps.append((arr[i] - arr[i - 1]) * 1000) }
        gaps.sort()
        let n = gaps.count
        let line = String(
            format: "msgs:%d p50:%.1fms p95:%.1fms p99:%.1fms max:%.1fms >25ms:%d >50ms:%d >100ms:%d\n",
            arr.count, gaps[n / 2], gaps[Int(Double(n) * 0.95)], gaps[Int(Double(n) * 0.99)],
            gaps.last ?? 0, gaps.filter { $0 > 25 }.count, gaps.filter { $0 > 50 }.count,
            gaps.filter { $0 > 100 }.count
        )
        try? line.write(toFile: "/tmp/controller_input_stats.txt", atomically: true, encoding: .utf8)
    }
}

// TCP without Nagle's algorithm — controller packets are tiny and latency-critical
func lowLatencyTCP() -> NWParameters {
    let tcp = NWProtocolTCP.Options()
    tcp.noDelay = true
    return NWParameters(tls: nil, tcp: tcp)
}

@Observable
class ControllerServer {
    var isRunning = false
    var connectedClients: [ClientInfo] = []
    var latestMessage: ControllerMessage?
    var errorMessage: String?

    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]

    // Hot path: called on the network queue for EVERY message, bypassing SwiftUI.
    // UI state (latestMessage) is published separately, throttled.
    @ObservationIgnored var onMessage: ((ControllerMessage) -> Void)?
    @ObservationIgnored private let netQueue = DispatchQueue(label: "controller.net", qos: .userInteractive)
    @ObservationIgnored private var lastUIPublish = Date.distantPast
    @ObservationIgnored private var lastUIButtons: [String]? = nil

    #if os(macOS)
    private var usbTimer: DispatchSourceTimer?

    // USB (ADB reverse tunnel) state, surfaced in the macOS UI
    var usbEnabled = UserDefaults.standard.object(forKey: "usbEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(usbEnabled, forKey: "usbEnabled")
            if usbEnabled {
                DispatchQueue.global(qos: .utility).async { [weak self] in self?.refreshUSB() }
            } else {
                usbAdbFound = false
                usbDeviceSerial = nil
                usbForwarded = false
            }
        }
    }
    var usbAdbFound = false
    var usbDeviceSerial: String?
    var usbForwarded = false
    /// When a USB link is live, shut Wi‑Fi out: stop advertising over Bonjour and
    /// drop/refuse non-loopback clients so only the cable path is used.
    var usbExclusive = UserDefaults.standard.object(forKey: "usbExclusive") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(usbExclusive, forKey: "usbExclusive")
            applyUSBExclusivity()
        }
    }
    /// True when a phone is actually connected through the cable (loopback client).
    var usbLinkActive: Bool {
        usbEnabled && usbForwarded && connectedClients.contains { Self.isLoopback($0.name) }
    }
    var wifiClosed = false

    static func isLoopback(_ host: String) -> Bool {
        let h = host.split(separator: "%").first.map(String.init) ?? host
        return h == "127.0.0.1" || h == "::1" || h == "localhost"
    }

    /// Close Wi‑Fi while the cable is live; reopen it when the cable goes away.
    private func applyUSBExclusivity() {
        #if os(macOS)
        let shouldClose = usbExclusive && usbLinkActive
        guard shouldClose != wifiClosed else { return }
        wifiClosed = shouldClose

        if shouldClose {
            listener?.service = nil // stop Bonjour advertising
            for client in connectedClients where !Self.isLoopback(client.name) {
                removeClient(id: client.id)
            }
        } else {
            listener?.service = NWListener.Service(name: "Controller", type: "_ps5ctrl._tcp")
        }
        #endif
    }
    #endif

    struct ClientInfo: Identifiable {
        let id: String
        var name: String
        var latestMessage: ControllerMessage?
    }

    var connectedPeer: String? {
        if connectedClients.isEmpty { return nil }
        if connectedClients.count == 1 { return connectedClients[0].name }
        return "\(connectedClients.count) controllers"
    }

    var isSearching: Bool { isRunning }

    /// Message from nth connected controller (0-indexed)
    func message(forPlayer index: Int) -> ControllerMessage? {
        guard index >= 0, index < connectedClients.count else { return nil }
        return connectedClients[index].latestMessage
    }

    var player1Message: ControllerMessage? { message(forPlayer: 0) }
    var player2Message: ControllerMessage? { message(forPlayer: 1) }

    func start() {
        guard listener == nil else { return }
        errorMessage = nil
        do {
            let params = lowLatencyTCP()
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: fixedPort)!)
            #if os(macOS)
            l.service = NWListener.Service(name: "Controller", type: "_ps5ctrl._tcp")
            #endif

            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.errorMessage = nil
                    case .failed(let error):
                        self?.isRunning = false
                        self?.errorMessage = "Listener failed: \(error)"
                    case .waiting(let error):
                        self?.errorMessage = "Waiting: \(error)"
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }

            l.newConnectionHandler = { [weak self] conn in
                self?.handleNewConnection(conn)
            }

            l.start(queue: .main)
            self.listener = l

            #if os(macOS)
            startUSBPolling()
            #endif
        } catch {
            errorMessage = "Start failed: \(error)"
        }
    }

    func stop() {
        #if os(macOS)
        usbTimer?.cancel()
        usbTimer = nil
        #endif
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        connectedClients.removeAll()
        listener?.cancel()
        listener = nil
        isRunning = false
        latestMessage = nil
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ conn: NWConnection) {
        let id = UUID().uuidString

        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .ready:
                    let name: String
                    switch conn.endpoint {
                    case .hostPort(let host, _):
                        name = "\(host)"
                    default:
                        name = conn.endpoint.debugDescription
                    }
                    #if os(macOS)
                    // USB is exclusive while linked: refuse Wi‑Fi clients so input
                    // can't arrive over both paths at once.
                    if self.usbExclusive, self.usbLinkActive, !Self.isLoopback(name) {
                        conn.cancel()
                        return
                    }
                    #endif
                    let client = ClientInfo(id: id, name: name)
                    self.connectedClients.append(client)
                    self.connections[id] = conn
                    self.readFrame(from: conn, clientId: id)
                    #if os(macOS)
                    // A cable client just arrived — close Wi‑Fi behind it
                    self.applyUSBExclusivity()
                    #endif
                case .failed, .cancelled:
                    self.removeClient(id: id)
                default: break
                }
            }
        }

        conn.start(queue: netQueue)
    }

    func removeClient(id: String) {
        connections[id]?.cancel()
        connections.removeValue(forKey: id)
        connectedClients.removeAll { $0.id == id }
        if connectedClients.isEmpty {
            latestMessage = nil
        }
        #if os(macOS)
        // Cable unplugged / phone left — reopen Wi‑Fi
        applyUSBExclusivity()
        #endif
    }

    // MARK: - Read Loop

    private func readFrame(from conn: NWConnection, clientId: String) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let data, data.count == 4 else {
                if error == nil { self?.readFrame(from: conn, clientId: clientId) }
                else { DispatchQueue.main.async { self?.removeClient(id: clientId) } }
                return
            }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length < 65536 else {
                self?.readFrame(from: conn, clientId: clientId)
                return
            }

            conn.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] payload, _, _, error in
                if let payload, let msg = ControllerMessage.decoded(from: payload) {
                    InputTrace.shared.record()
                    // Hot path first: feed the input mapper immediately, off the main thread
                    self?.onMessage?(msg)
                    self?.publishToUI(msg, clientId: clientId)
                }
                if error == nil {
                    self?.readFrame(from: conn, clientId: clientId)
                } else {
                    DispatchQueue.main.async { self?.removeClient(id: clientId) }
                }
            }
        }
    }

    /// Push a rumble level (0...1) to every connected phone. Same framing as
    /// inbound messages: 4-byte big-endian length + JSON.
    func sendRumble(_ level: Double) {
        guard !connections.isEmpty else { return }
        let json = "{\"rumble\":\(String(format: "%.3f", level))}"
        guard let payload = json.data(using: .utf8) else { return }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        for (_, conn) in connections {
            conn.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    // Publish to SwiftUI at most ~30x/s (button changes always go through immediately).
    // Input never waits on this — the mapper is fed directly via onMessage.
    private func publishToUI(_ msg: ControllerMessage, clientId: String) {
        let now = Date()
        let buttonsChanged = msg.pressedButtons != lastUIButtons
        guard buttonsChanged || now.timeIntervalSince(lastUIPublish) >= 0.033 else { return }
        lastUIPublish = now
        lastUIButtons = msg.pressedButtons
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let idx = self.connectedClients.firstIndex(where: { $0.id == clientId }) {
                self.connectedClients[idx].latestMessage = msg
            }
            self.latestMessage = msg
        }
    }

    // MARK: - Local IP

    func getLocalIP() -> String {
        var address = "?"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard interface.ifa_addr != nil else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // en0 = WiFi on macOS/iPad, en1 = secondary, pdp_ip0 = cellular
                if name == "en0" || name == "en1" || name == "en2" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    let ip = String(cString: hostname)
                    if !ip.hasPrefix("127.") {
                        address = ip
                        break
                    }
                }
            }
        }
        return address
    }

    #if os(macOS)
    // MARK: - USB (ADB) Reverse Forwarding

    private static let adbSearchPaths = [
        "/opt/homebrew/share/android-commandlinetools/platform-tools/adb",
        "/opt/homebrew/bin/adb",
        "/usr/local/bin/adb",
        "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
        "/Applications/Android Studio.app/Contents/plugins/android/resources/platform-tools/adb",
    ]

    private func startUSBPolling() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self, self.usbEnabled else { return }
            self.refreshUSB()
        }
        timer.resume()
        usbTimer = timer
    }

    /// Re-detect ADB + device and (re)apply the reverse tunnel. Safe to call often.
    func refreshUSB() {
        guard let adb = Self.findADB() else {
            publishUSB(adbFound: false, device: nil, forwarded: false)
            return
        }
        guard let serial = Self.getUSBDeviceSerial(adb: adb) else {
            publishUSB(adbFound: true, device: nil, forwarded: false)
            return
        }
        let ok = Self.shell(adb, args: ["-s", serial, "reverse", "tcp:\(fixedPort)", "tcp:\(fixedPort)"]) != nil
        publishUSB(adbFound: true, device: serial, forwarded: ok)
    }

    private func publishUSB(adbFound: Bool, device: String?, forwarded: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.usbAdbFound = adbFound
            self.usbDeviceSerial = device
            self.usbForwarded = forwarded
            self.applyUSBExclusivity()
        }
    }

    private static func findADB() -> String? {
        for path in adbSearchPaths {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private static func getUSBDeviceSerial(adb: String) -> String? {
        guard let output = shell(adb, args: ["devices"]) else { return nil }
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("\tdevice") && !trimmed.hasPrefix("emulator-") {
                return trimmed.components(separatedBy: "\t").first
            }
        }
        return nil
    }

    @discardableResult
    private static func shell(_ path: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = NSHomeDirectory()
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard proc.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }
    #endif
}

// MARK: - Controller Client (iPhone — connects to server and sends input)

#if os(iOS)
@Observable
class ControllerClient {
    var isConnected = false
    var serverName: String?
    var isSearching = false

    private var connection: NWConnection?
    private var browser: NWBrowser?

    func start() {
        guard browser == nil, connection == nil else { return }
        isSearching = true
        startBrowsing()
    }

    func stop() {
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
        isConnected = false
        serverName = nil
        isSearching = false
    }

    func connectDirect(host: String, port: UInt16 = fixedPort) {
        stop()
        connect(host: host, port: port)
    }

    func send(_ message: ControllerMessage) {
        guard let conn = connection, conn.state == .ready,
              let data = message.encoded() else { return }

        var length = UInt32(data.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(data)

        conn.send(content: frame, completion: .contentProcessed { error in
            if let error { print("Send error: \(error)") }
        })
    }

    // MARK: - Bonjour Discovery

    private func startBrowsing() {
        let b = NWBrowser(for: .bonjour(type: "_ps5ctrl._tcp", domain: nil), using: .tcp)

        b.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isSearching = true
                case .failed, .cancelled:
                    self?.isSearching = false
                default: break
                }
            }
        }

        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, self.connection == nil else { return }
            if let result = results.first {
                self.browser?.cancel()
                self.browser = nil
                self.connectToEndpoint(result.endpoint)
            }
        }

        b.start(queue: .main)
        self.browser = b
    }

    private func connectToEndpoint(_ endpoint: NWEndpoint) {
        let conn = NWConnection(to: endpoint, using: lowLatencyTCP())
        setupConnection(conn, name: endpoint.debugDescription)
    }

    private func connect(host: String, port: UInt16) {
        isSearching = true
        let h = NWEndpoint.Host(host)
        let p = NWEndpoint.Port(rawValue: port)!
        let conn = NWConnection(host: h, port: p, using: .tcp)
        setupConnection(conn, name: host)
    }

    private func setupConnection(_ conn: NWConnection, name: String) {
        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.serverName = name
                    self.isSearching = false
                case .waiting:
                    conn.cancel()
                    self.connection = nil
                    self.handleDisconnect()
                case .failed, .cancelled:
                    if self.connection === conn {
                        self.handleDisconnect()
                    }
                default: break
                }
            }
        }

        conn.start(queue: .main)
        self.connection = conn
    }

    private func handleDisconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        serverName = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.isConnected, self.connection == nil else { return }
            self.start()
        }
    }
}
#endif
