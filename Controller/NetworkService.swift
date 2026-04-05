//
//  NetworkService.swift
//  Controller
//
//  USB-only networking: Android sends over TCP, macOS connects via ADB port forwarding.
//

import Foundation
import Network
import SwiftUI

private let fixedPort: UInt16 = 9876

// MARK: - Controller Sender (iOS)

#if os(iOS)
@Observable
class ControllerSender {
    var isAdvertising = false
    var connectedPeer: String?

    private var listener: NWListener?
    private var connection: NWConnection?

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: fixedPort)!)

            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    self?.isAdvertising = (state == .ready)
                }
            }

            listener.newConnectionHandler = { [weak self] newConn in
                self?.connection?.cancel()
                self?.connection = newConn
                newConn.start(queue: .main)
                DispatchQueue.main.async {
                    self?.connectedPeer = newConn.endpoint.debugDescription
                }

                self?.receiveLoop(on: newConn)
            }

            listener.start(queue: .main)
            self.listener = listener
        } catch {
            print("Listener failed: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connection?.cancel()
        connection = nil
        isAdvertising = false
        connectedPeer = nil
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

    private func receiveLoop(on conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                DispatchQueue.main.async { self?.connectedPeer = nil }
            }
            if case .cancelled = state {
                DispatchQueue.main.async { self?.connectedPeer = nil }
            }
        }
    }
}
#endif

// MARK: - Controller Receiver (macOS) — USB only via ADB

#if os(macOS)
@Observable
class ControllerReceiver {
    var isSearching = false
    var connectedPeer: String?
    var connectionMethod: String?
    var latestMessage: ControllerMessage?

    private var connection: NWConnection?
    private var usbTimer: DispatchSourceTimer?
    private var isConnecting = false

    private static let adbSearchPaths = [
        "/opt/homebrew/share/android-commandlinetools/platform-tools/adb",
        "/opt/homebrew/bin/adb",
        "/usr/local/bin/adb",
        "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
        "/Applications/Android Studio.app/Contents/plugins/android/resources/platform-tools/adb",
    ]

    func start() {
        isSearching = true
        startUSBPolling()
    }

    func stop() {
        usbTimer?.cancel()
        usbTimer = nil
        connection?.cancel()
        connection = nil
        isSearching = false
        connectedPeer = nil
        connectionMethod = nil
        latestMessage = nil
        isConnecting = false
    }

    // MARK: - USB (ADB) Polling

    private func startUSBPolling() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.tryUSBConnection()
        }
        timer.resume()
        usbTimer = timer
    }

    private func tryUSBConnection() {
        guard connection == nil, !isConnecting else { return }

        guard let adb = Self.findADB() else { return }
        guard let serial = Self.getUSBDeviceSerial(adb: adb) else { return }

        // Set up port forwarding
        Self.shell(adb, args: ["-s", serial, "forward", "tcp:\(fixedPort)", "tcp:\(fixedPort)"])

        // Small delay to let adb forward stabilize
        Thread.sleep(forTimeInterval: 0.5)

        // Connect to forwarded port
        DispatchQueue.main.async { [weak self] in
            self?.connectToLocalhost(serial: serial)
        }
    }

    private static func findADB() -> String? {
        for path in adbSearchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
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
        } catch {
            return nil
        }
    }

    // MARK: - Connection

    private func connectToLocalhost(serial: String) {
        guard connection == nil, !isConnecting else { return }
        isConnecting = true

        let host = NWEndpoint.Host("127.0.0.1")
        let port = NWEndpoint.Port(rawValue: fixedPort)!

        let conn = NWConnection(host: host, port: port, using: .tcp)

        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .ready:
                    self.connectedPeer = serial
                    self.connectionMethod = "USB"
                    self.isConnecting = false
                    self.readFrame(from: conn)
                case .waiting:
                    conn.cancel()
                    self.connection = nil
                    self.isConnecting = false
                case .failed:
                    self.handleDisconnect()
                case .cancelled:
                    if self.connection === conn {
                        self.handleDisconnect()
                    } else {
                        self.isConnecting = false
                    }
                default:
                    break
                }
            }
        }

        conn.start(queue: .main)
        self.connection = conn
    }

    private func handleDisconnect() {
        connectedPeer = nil
        connectionMethod = nil
        connection?.cancel()
        connection = nil
        isConnecting = false
        latestMessage = nil
    }

    // MARK: - Read Loop

    private func readFrame(from conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let data, data.count == 4 else {
                if error == nil { self?.readFrame(from: conn) }
                else { DispatchQueue.main.async { self?.handleDisconnect() } }
                return
            }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length < 65536 else {
                self?.readFrame(from: conn)
                return
            }

            conn.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] payload, _, _, error in
                if let payload, let msg = ControllerMessage.decoded(from: payload) {
                    DispatchQueue.main.async {
                        self?.latestMessage = msg
                    }
                }
                if error == nil {
                    self?.readFrame(from: conn)
                } else {
                    DispatchQueue.main.async { self?.handleDisconnect() }
                }
            }
        }
    }
}
#endif
