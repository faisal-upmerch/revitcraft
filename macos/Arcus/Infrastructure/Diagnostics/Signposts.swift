import Foundation
import OSLog

/// Performance intervals visible in Instruments (Points of Interest / os_signpost) and recorded as timings in
/// `DiagnosticsLog.shared`.
public enum Signposts {
    public static let signposter = OSSignposter(subsystem: "com.local.arcus", category: .pointsOfInterest)

    /// Runs `body` inside a signpost interval and records its duration.
    public static func interval<T>(_ name: StaticString, log: DiagnosticsLog = .shared, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        let start = ContinuousClock.now
        defer {
            signposter.endInterval(name, state)
            log.recordTiming(String(describing: name), seconds: seconds(ContinuousClock.now - start))
        }
        return try body()
    }

    /// Async variant; `body` runs on the caller's isolation.
    public static func intervalAsync<T>(_ name: StaticString, log: DiagnosticsLog = .shared, isolation: isolated (any Actor)? = #isolation,
                                        _ body: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        let start = ContinuousClock.now
        defer {
            signposter.endInterval(name, state)
            log.recordTiming(String(describing: name), seconds: seconds(ContinuousClock.now - start))
        }
        return try await body()
    }

    static func seconds(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) + Double(c.attoseconds) * 1e-18
    }
}
