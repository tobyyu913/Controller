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

@Observable
class ControllerServer {
    var isRunning = false
    var connectedClients: [ClientInfo] = []
    var latestMessage: ControllerMessage?

    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]

    #if os(macOS)
    private var usbTimer: DispatchSourceTimer?
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
        do {
            let params = NWParameters.tcp
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: fixedPort)!)
            l.service = NWListener.Service(name: "Controller", type: "_ps5ctrl._tcp")

            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    self?.isRunning = (state == .ready)
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
            print("Server start failed: \(error)")
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
                    let client = ClientInfo(id: id, name: name)
                    self.connectedClients.append(client)
                    self.connections[id] = conn
                    self.readFrame(from: conn, clientId: id)
                case .failed, .cancelled:
                    self.removeClient(id: id)
                default: break
                }
            }
        }

        conn.start(queue: .main)
    }

    func removeClient(id: String) {
        connections[id]?.cancel()
        connections.removeValue(forKey: id)
        connectedClients.removeAll { $0.id == id }
        if connectedClients.isEmpty {
            latestMessage = nil
        }
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
                    DispatchQueue.main.async {
                        if let idx = self?.connectedClients.firstIndex(where: { $0.id == clientId }) {
                            self?.connectedClients[idx].latestMessage = msg
                        }
                        self?.latestMessage = msg
                    }
                }
                if error == nil {
                    self?.readFrame(from: conn, clientId: clientId)
                } else {
                    DispatchQueue.main.async { self?.removeClient(id: clientId) }
                }
            }
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
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
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
            guard self != nil else { return }
            Self.setupADBReverse()
        }
        timer.resume()
        usbTimer = timer
    }

    private static func setupADBReverse() {
        guard let adb = findADB() else { return }
        guard let serial = getUSBDeviceSerial(adb: adb) else { return }
        shell(adb, args: ["-s", serial, "reverse", "tcp:\(fixedPort)", "tcp:\(fixedPort)"])
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
        let conn = NWConnection(to: endpoint, using: .tcp)
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
