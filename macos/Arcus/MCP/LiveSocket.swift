import Foundation
import Darwin

// MCP: live mode's local socket (Docs/MCP.md §3). A Unix domain socket in the user's Application Support folder,
// 0600 inside a 0700 folder, peers checked with getpeereid. Newline-delimited JSON, one response per request.

public enum LiveSocket {
    public static let protocolVersion = 1
    /// Requests over 8 MB are refused.
    public static let maxMessage = 8 * 1024 * 1024

    /// `~/Library/Application Support/Arcus/MCP/arcus.sock`.
    public static var defaultPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Arcus/MCP/arcus.sock").path
    }

    public struct Failure: Error, CustomStringConvertible, Sendable {
        public var description: String
        init(_ s: String) { description = s }
    }

    static func address(_ path: String) throws(Failure) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw Failure("Socket path too long: \(path)") }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return addr
    }

    /// Connects to the app's socket; nil when nothing listens there.
    static func connect(_ path: String, timeout: TimeInterval) -> Int32? {
        guard FileManager.default.fileExists(atPath: path), var addr = try? address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let r = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard r == 0 else { close(fd); return nil }
        return fd
    }

    static func writeLine(_ fd: Int32, _ text: String) -> Bool {
        let data = Array((text + "\n").utf8)
        let total = data.count
        var off = 0
        while off < total {
            let n = data.withUnsafeBytes { write(fd, $0.baseAddress! + off, total - off) }
            if n <= 0 { return false }
            off += n
        }
        return true
    }

    /// Reads one line (without the newline). nil on EOF, timeout or an over-long message.
    static func readLine(_ fd: Int32, buffer: inout [UInt8]) -> String? {
        while true {
            if let nl = buffer.firstIndex(of: 10) {
                let line = String(decoding: buffer[..<nl], as: UTF8.self)
                buffer.removeSubrange(...nl)
                return line
            }
            if buffer.count > maxMessage { return nil }
            var chunk = [UInt8](repeating: 0, count: 65_536)
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress!, 65_536) }
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[..<n])
        }
    }

    /// One request/response with the app. Throws when the app isn't listening or doesn't answer in time.
    public static func request(_ message: JSONValue, path: String = defaultPath, timeout: TimeInterval = 120) throws(Failure) -> JSONValue {
        guard let fd = connect(path, timeout: timeout) else { throw Failure("Arcus isn't listening (open Arcus and turn on Settings ▸ Claude (MCP)).") }
        defer { close(fd) }
        guard writeLine(fd, message.jsonText) else { throw Failure("Could not send to Arcus.") }
        var buf: [UInt8] = []
        guard let line = readLine(fd, buffer: &buf) else { throw Failure("Arcus didn't answer within \(Int(timeout)) s.") }
        do { return try JSONValue.parse(line) } catch { throw Failure("Arcus sent an unreadable answer.") }
    }

    /// True when the app answers `hello` on the socket.
    public static func isReachable(path: String = defaultPath) -> Bool {
        (try? request(["v": .int(protocolVersion), "id": 0, "op": "hello"], path: path, timeout: 1.5))?["ok"]?.boolValue == true
    }
}

/// The app side: accepts connections from the same user and answers each request line with `handler`.
public final class LiveSocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (JSONValue) async -> JSONValue
    public let path: String
    let handler: Handler
    private let lock = NSLock()
    private var listenFD: Int32 = -1

    public init(path: String = LiveSocket.defaultPath, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    public var isRunning: Bool { lock.withLock { listenFD >= 0 } }

    /// Creates the folder (0700) and socket (0600) and starts accepting. Replaces a stale socket file left by a crash,
    /// but refuses to take over one another process is serving.
    public func start() throws(LiveSocket.Failure) {
        guard !isRunning else { return }
        let dir = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)
        } catch { throw LiveSocket.Failure("Can't create \(dir): \(error.localizedDescription)") }
        if FileManager.default.fileExists(atPath: path) {
            if LiveSocket.connect(path, timeout: 0.5).map({ close($0); return true }) == true { throw LiveSocket.Failure("Another Arcus is already serving \(path).") }
            unlink(path)
        }
        var addr = try LiveSocket.address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LiveSocket.Failure("socket() failed: \(String(cString: strerror(errno)))") }
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0 else { close(fd); throw LiveSocket.Failure("bind(\(path)) failed: \(String(cString: strerror(errno)))") }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else { close(fd); unlink(path); throw LiveSocket.Failure("listen() failed.") }
        lock.withLock { listenFD = fd }
        let t = Thread { [weak self] in self?.acceptLoop(fd) }
        t.name = "Arcus MCP socket"
        t.start()
    }

    /// Stops accepting and removes the socket file.
    public func stop() {
        let fd = lock.withLock { () -> Int32 in let f = listenFD; listenFD = -1; return f }
        guard fd >= 0 else { return }
        shutdown(fd, SHUT_RDWR)
        close(fd)
        unlink(path)
    }

    deinit { stop() }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            // Only the user who runs the app may talk to it.
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { close(client); continue }
            var one: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            let t = Thread { [weak self] in self?.serve(client) }
            t.name = "Arcus MCP connection"
            t.start()
        }
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        var buf: [UInt8] = []
        while let line = LiveSocket.readLine(fd, buffer: &buf) {
            let reply: JSONValue
            if let req = try? JSONValue.parse(line) {
                reply = Self.wait { [handler] in await handler(req) }
            } else {
                reply = ["v": .int(LiveSocket.protocolVersion), "id": .null, "ok": false, "error": "Unreadable request."]
            }
            guard LiveSocket.writeLine(fd, reply.jsonText) else { return }
        }
    }

    /// Runs async work from this connection's thread and waits for it.
    private static func wait(_ work: @escaping @Sendable () async -> JSONValue) -> JSONValue {
        final class Box: @unchecked Sendable { var value: JSONValue = .null }
        let box = Box()
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await work()
            sem.signal()
        }
        sem.wait()
        return box.value
    }
}
