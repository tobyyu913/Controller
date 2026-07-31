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

    /// Fixed 4-byte record: [sync 0xA5][buttons][int8 dx][int8 dy].
    /// Preallocated so the real-time tick thread never allocates — a malloc here
    /// can block, overrun the thread's deadline and get it demoted (= jitter).
    private var packet: [UInt8] = [0xA5, 0, 0, 0]

    /// buttons: bit0 = left, bit1 = right, bit2 = middle
    func send(buttons: Int, dx: Int, dy: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard fd >= 0 else { return }

        packet[1] = UInt8(buttons & 0xFF)
        packet[2] = UInt8(bitPattern: Int8(clamping: dx))
        packet[3] = UInt8(bitPattern: Int8(clamping: dy))

        let ok = packet.withUnsafeBytes { raw -> Bool in
            let written = write(fd, raw.baseAddress, 4)
            if written < 0 {
                // EAGAIN on a full buffer is fine — dropping one sample beats
                // stalling; any other error means the helper died.
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
