//
//  VirtualMouse.swift
//  Controller
//
//  Sends mouse motion through a REAL virtual HID device (Karabiner DriverKit
//  virtual pointing device) via the controller-vhid-bridge helper, instead of
//  synthetic CGEvents. Games that ignore or badly pace synthetic input (e.g.
//  Wuthering Waves) treat this as genuine mouse hardware.
//
//  The helper runs as root and listens on /tmp/controller-vhid.sock.
//

#if os(macOS)
import Foundation

final class VirtualMouse {
    static let shared = VirtualMouse()

    private var fd: Int32 = -1
    private let lock = NSLock()
    private let socketPath = "/tmp/controller-vhid.sock"

    /// True when connected to the bridge helper.
    private(set) var isConnected = false
    /// True when the helper reports the virtual HID device is actually usable.
    private(set) var isReady = false

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    @discardableResult
    func connect() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fd >= 0 { return true }

        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return false }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { dst in
                socketPath.withCString { src in
                    _ = strncpy(dst, src, pathCapacity - 1)
                }
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(s, sa, size)
            }
        }
        if result != 0 {
            close(s)
            isConnected = false
            return false
        }

        // Never block the real-time tick thread on a stalled write
        var flags = fcntl(s, F_GETFL, 0)
        flags |= O_NONBLOCK
        _ = fcntl(s, F_SETFL, flags)

        fd = s
        isConnected = true
        return true
    }

    /// Drain any "ready 0/1" status lines the helper sent. Call periodically.
    func pollStatus() {
        lock.lock()
        defer { lock.unlock() }
        guard fd >= 0 else { return }
        var buf = [UInt8](repeating: 0, count: 256)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            if let text = String(bytes: buf[0..<n], encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    if line.hasPrefix("ready ") { isReady = line.hasSuffix("1") }
                }
            }
            if n < buf.count { break }
        }
    }

    func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        if fd >= 0 { close(fd) }
        fd = -1
        isConnected = false
        isReady = false
    }

    /// buttons: bit0 = left, bit1 = right, bit2 = middle
    func send(buttons: Int, dx: Int, dy: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard fd >= 0 else { return }

        let line = "p \(buttons) \(dx) \(dy)\n"
        let ok = line.withCString { cstr -> Bool in
            let len = strlen(cstr)
            let written = write(fd, cstr, len)
            if written < 0 {
                // EAGAIN on a full buffer is fine — dropping one 8ms sample is
                // better than stalling; any other error means the helper died.
                return errno == EAGAIN || errno == EWOULDBLOCK
            }
            return true
        }
        if !ok {
            close(fd)
            fd = -1
            isConnected = false
            isReady = false
        }
    }
}
#endif
