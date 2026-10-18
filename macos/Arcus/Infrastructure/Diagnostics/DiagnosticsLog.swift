import Foundation
import OSLog
import Synchronization

/// Thread-safe in-memory diagnostics: a bounded ring buffer of log entries and timings, mirrored to OSLog.
///
/// Nothing is written to disk and nothing leaves the machine; `exportRedacted()` produces text the user can
/// choose to share. Messages must never contain file contents.
public final class DiagnosticsLog: Sendable {
    public enum Level: String, Sendable, Comparable, CaseIterable {
        case debug, info, notice, warning, error, fault
        public static func < (a: Level, b: Level) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
        var osType: OSLogType {
            switch self {
            case .debug: .debug
            case .info: .info
            case .notice, .warning: .default
            case .error: .error
            case .fault: .fault
            }
        }
    }

    public struct Entry: Sendable, Hashable {
        public var date: Date
        public var level: Level
        public var category: String
        public var message: String
    }

    private struct State {
        var entries: [Entry] = []
        var entryHead = 0
        var timings: [(name: String, seconds: Double, date: Date)] = []
        var timingHead = 0
        var projectNames: Set<String> = []
        var loggers: [String: Logger] = [:]
    }

    public static let shared = DiagnosticsLog()

    public let subsystem: String
    public let capacity: Int
    public let timingCapacity: Int
    /// Home directory and user names used for redaction (injectable for tests).
    let homeDirectory: String
    let userNames: [String]
    private let state = Mutex(State())
    /// Longest message kept (longer messages are truncated; guards against accidental content dumps).
    static let maxMessageLength = 2_000

    public init(subsystem: String = "com.local.arcus", capacity: Int = 2_000, timingCapacity: Int = 500,
                homeDirectory: String = NSHomeDirectory(), userNames: [String] = [NSUserName(), NSFullUserName()]) {
        self.subsystem = subsystem
        self.capacity = max(1, capacity)
        self.timingCapacity = max(1, timingCapacity)
        self.homeDirectory = homeDirectory
        self.userNames = userNames.filter { $0.count >= 2 }
    }

    public func log(_ category: String, _ message: String, level: Level = .info) {
        let msg = message.count > Self.maxMessageLength ? String(message.prefix(Self.maxMessageLength)) + "…" : message
        let entry = Entry(date: Date(), level: level, category: category, message: msg)
        let logger = state.withLock { s -> Logger in
            if s.entries.count < capacity { s.entries.append(entry) } else {
                s.entries[s.entryHead] = entry
                s.entryHead = (s.entryHead + 1) % capacity
            }
            if let l = s.loggers[category] { return l }
            let l = Logger(subsystem: subsystem, category: category)
            s.loggers[category] = l
            return l
        }
        logger.log(level: level.osType, "\(msg, privacy: .private)")
    }

    public func recordTiming(_ name: String, seconds: Double) {
        Signposts.signposter.emitEvent("timing", "\(name, privacy: .public) \(seconds, format: .fixed(precision: 4), privacy: .public) s")
        let t = (name: name, seconds: seconds, date: Date())
        state.withLock { s in
            if s.timings.count < timingCapacity { s.timings.append(t) } else {
                s.timings[s.timingHead] = t
                s.timingHead = (s.timingHead + 1) % timingCapacity
            }
        }
    }

    /// Timings, oldest first.
    public var recentTimings: [(name: String, seconds: Double, date: Date)] {
        state.withLock { s in Array(s.timings[s.timingHead...] + s.timings[..<s.timingHead]) }
    }

    /// Entries, oldest first.
    public var entries: [Entry] {
        state.withLock { s in Array(s.entries[s.entryHead...] + s.entries[..<s.entryHead]) }
    }

    /// Registers a project/document name so exports can redact it.
    public func registerProjectName(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard n.count >= 2 else { return }
        state.withLock { _ = $0.projectNames.insert(n) }
    }

    public func clear() {
        state.withLock { s in s.entries = []; s.entryHead = 0; s.timings = []; s.timingHead = 0 }
    }

    /// A shareable text report: entries and timings with home-directory paths shortened to `~`, `/Users/<name>`
    /// and the account names removed, document file names and registered project names replaced unless
    /// `includeProjectNames` is true.
    public func exportRedacted() -> String { exportRedacted(includeProjectNames: false) }

    public func exportRedacted(includeProjectNames: Bool) -> String {
        let (entries, timings, names) = state.withLock { s in
            (Array(s.entries[s.entryHead...] + s.entries[..<s.entryHead]),
             Array(s.timings[s.timingHead...] + s.timings[..<s.timingHead]),
             s.projectNames)
        }
        let fmt = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt)
        var out = "Arcus diagnostics (redacted)\n"
        out += "OS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        out += "Processors: \(ProcessInfo.processInfo.activeProcessorCount)\n\n"
        out += "Log (\(entries.count) entries)\n"
        for e in entries {
            out += "\(e.date.formatted(fmt)) [\(e.level.rawValue)] \(e.category): \(redact(e.message, projectNames: includeProjectNames ? [] : names, includeFileNames: includeProjectNames))\n"
        }
        out += "\nTimings (\(timings.count))\n"
        for t in timings {
            out += "\(t.date.formatted(fmt)) \(redact(t.name, projectNames: includeProjectNames ? [] : names, includeFileNames: includeProjectNames)): \(String(format: "%.4f", t.seconds)) s\n"
        }
        return out
    }

    /// Redacts one string.
    public func redact(_ s: String, projectNames: Set<String>, includeFileNames: Bool) -> String {
        var r = s
        // Home directory (also its /private and resolved forms) → ~
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        if home.count > 1 {
            r = r.replacingOccurrences(of: "/private" + home, with: "~")
            r = r.replacingOccurrences(of: home, with: "~")
        }
        // Any other /Users/<name> path prefix.
        r = r.replacing(/\/Users\/[^\/\s"'’”]+/, with: "~")
        // Account names anywhere.
        for n in userNames.sorted(by: { $0.count > $1.count }) {
            r = r.replacingOccurrences(of: n, with: "<user>", options: [.caseInsensitive])
        }
        for n in projectNames.sorted(by: { $0.count > $1.count }) {
            r = r.replacingOccurrences(of: n, with: "<project>")
        }
        if !includeFileNames {
            // Document-like file names keep only their extension: whole last path components (spaces allowed)…
            r = r.replacing(/\/[^\/\n"'“”‘’]+\.(arcus|arcusfamily|ifc|ifczip|dwg|dxf|pdf|csv)\b/.ignoresCase()) { m in "/<file>.\(m.output.1)" }
            // …and bare names.
            r = r.replacing(/[^\/\s"'“”‘’<>]+\.(arcus|arcusfamily|ifc|ifczip|dwg|dxf|pdf|csv)\b/.ignoresCase()) { m in "<file>.\(m.output.1)" }
        }
        return r
    }
}
