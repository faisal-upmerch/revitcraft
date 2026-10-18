import Foundation

/// System memory pressure as seen by the viewport.
nonisolated public enum MemoryPressureLevel: Int, Sendable, Comparable {
    case normal, warning, critical
    public static func < (a: MemoryPressureLevel, b: MemoryPressureLevel) -> Bool { a.rawValue < b.rawValue }
}

/// Watches system memory pressure so viewports can shed optional GPU memory (ambient occlusion, large shadow maps,
/// offscreen targets) on 8 GB Macs before the system starts compressing or swapping.
@MainActor final class MemoryPressureMonitor {
    static let shared = MemoryPressureMonitor()
    static let didChange = Notification.Name("ArcusViewportMemoryPressureDidChange")

    private(set) var level: MemoryPressureLevel = .normal
    private let source: any DispatchSourceMemoryPressure

    private init() {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let e = self.source.data
                self.set(e.contains(.critical) ? .critical : e.contains(.warning) ? .warning : .normal)
            }
        }
        source.activate()
    }

    /// Updates the level and notifies viewports (also used by tests to simulate pressure).
    func set(_ newLevel: MemoryPressureLevel) {
        guard newLevel != level else { return }
        level = newLevel
        NotificationCenter.default.post(name: MemoryPressureMonitor.didChange, object: nil)
    }
}
