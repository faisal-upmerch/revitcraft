import Foundation

// W4-SHELL: geometry and persistence of the floating dock panels (left sidebar, right inspector). Pure values so the
// window shell and its tests share one definition; the UI layer only draws what this computes.

/// Which window edge a floating dock hangs from.
public enum DockEdge: String, Sendable, CaseIterable { case leading, trailing }

/// Fixed metrics of the floating docks: how far they float from the canvas edges, how wide they may be, and how much
/// canvas must stay visible between them.
public struct DockMetrics: Sendable, Equatable {
    /// Gap between a panel and the canvas region's edges.
    public var margin: Double = 10
    public var minWidth: Double = 280
    public var maxWidth: Double = 480
    /// Canvas that must stay clear of both docks (the region their overlays avoid).
    public var canvasMinWidth: Double = 480
    /// Corner radius of a panel; the window corner is concentric with it.
    public var cornerRadius: Double = 16
    /// Width of the drag zone along a panel's inner edge that resizes it.
    public var resizeHandleWidth: Double = 8
    public init() {}
}

/// One dock's requested state.
public struct DockRequest: Sendable, Equatable {
    public var edge: DockEdge
    /// The width the user last chose (before clamping).
    public var width: Double
    /// Hidden by the sidebar/inspector toggle, by the workspace, or because its panels are detached.
    public var visible: Bool
    public init(edge: DockEdge, width: Double, visible: Bool) { self.edge = edge; self.width = width; self.visible = visible }
}

/// The resolved geometry of one dock inside the canvas region (origin at the region's top-left, y down).
public struct DockPlacement: Sendable, Equatable {
    public var edge: DockEdge
    public var frame: DockFrame
    /// Horizontal inset the canvas's floating controls keep from that edge (panel width plus both margins).
    public var overlayInset: Double
    public init(edge: DockEdge, frame: DockFrame, overlayInset: Double) { self.edge = edge; self.frame = frame; self.overlayInset = overlayInset }
}

/// A rectangle in points (origin top-left, y down); CoreGraphics-free so the layer stays Foundation-only.
public struct DockFrame: Sendable, Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

/// A size in points.
public struct DockRegion: Sendable, Equatable {
    public var width: Double, height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

/// The full result: each visible dock's frame and the safe-area insets for the canvas overlays.
public struct DockLayoutResult: Sendable, Equatable {
    public var placements: [DockPlacement] = []
    public var leadingInset: Double = 0
    public var trailingInset: Double = 0
    public func placement(_ edge: DockEdge) -> DockPlacement? { placements.first { $0.edge == edge } }
}

public enum DockLayout {
    /// Clamps a requested width to the metrics and to the canvas that must stay visible beside the other dock.
    /// When even the minimum width doesn't fit the panel keeps the minimum: hiding it is the caller's decision.
    public static func clampWidth(_ requested: Double, regionWidth: Double, otherDockWidth: Double, metrics: DockMetrics = DockMetrics()) -> Double {
        let margins = metrics.margin * 2
        let room = regionWidth - metrics.canvasMinWidth - (otherDockWidth > 0 ? otherDockWidth + margins : 0) - margins
        let upper = min(metrics.maxWidth, max(metrics.minWidth, room))
        return min(max(requested.isFinite ? requested : metrics.minWidth, metrics.minWidth), upper)
    }

    /// Lays both docks out in a canvas region of `size`. Widths are clamped against each other (the leading dock has
    /// priority when both are visible in a narrow window).
    public static func layout(region size: DockRegion, leading: DockRequest?, trailing: DockRequest?, metrics: DockMetrics = DockMetrics()) -> DockLayoutResult {
        var result = DockLayoutResult()
        guard size.width > 0, size.height > metrics.margin * 2 else { return result }
        let leadingWidth = leading.flatMap { $0.visible ? clampWidth($0.width, regionWidth: size.width, otherDockWidth: 0, metrics: metrics) : nil }
        let trailingWidth = trailing.flatMap { $0.visible ? clampWidth($0.width, regionWidth: size.width, otherDockWidth: leadingWidth ?? 0, metrics: metrics) : nil }
        let height = size.height - metrics.margin * 2
        if let w = leadingWidth {
            let frame = DockFrame(x: metrics.margin, y: metrics.margin, width: w, height: height)
            result.placements.append(DockPlacement(edge: .leading, frame: frame, overlayInset: w + metrics.margin * 2))
            result.leadingInset = w + metrics.margin * 2
        }
        if let w = trailingWidth {
            let frame = DockFrame(x: size.width - metrics.margin - w, y: metrics.margin, width: w, height: height)
            result.placements.append(DockPlacement(edge: .trailing, frame: frame, overlayInset: w + metrics.margin * 2))
            result.trailingInset = w + metrics.margin * 2
        }
        return result
    }

    /// The width after dragging a panel's inner edge by `delta` points (positive = towards the canvas centre for a
    /// leading dock, i.e. wider).
    public static func resized(edge: DockEdge, startWidth: Double, dragX: Double, regionWidth: Double, otherDockWidth: Double, metrics: DockMetrics = DockMetrics()) -> Double {
        let raw = edge == .leading ? startWidth + dragX : startWidth - dragX
        return clampWidth(raw, regionWidth: regionWidth, otherDockWidth: otherDockWidth, metrics: metrics)
    }
}

/// A key/value store the dock preferences read and write (UserDefaults in the app, a dictionary in tests).
public protocol DockPreferenceStore: AnyObject {
    func savedDouble(forKey key: String) -> Double?
    func savedBool(forKey key: String) -> Bool?
    func save(_ value: Double, forKey key: String)
    func save(_ value: Bool, forKey key: String)
}

/// Persisted dock state: width and collapsed flag per edge.
public struct DockPreferences: Sendable, Equatable {
    public var leadingWidth: Double
    public var trailingWidth: Double
    public var leadingCollapsed: Bool
    public var trailingCollapsed: Bool

    public static let defaultLeadingWidth: Double = 300
    public static let defaultTrailingWidth: Double = 300
    static let keys = (leadingWidth: "dock.leading.width", trailingWidth: "dock.trailing.width",
                       leadingCollapsed: "dock.leading.collapsed", trailingCollapsed: "dock.trailing.collapsed")

    public init(leadingWidth: Double = defaultLeadingWidth, trailingWidth: Double = defaultTrailingWidth, leadingCollapsed: Bool = false, trailingCollapsed: Bool = false) {
        self.leadingWidth = leadingWidth; self.trailingWidth = trailingWidth
        self.leadingCollapsed = leadingCollapsed; self.trailingCollapsed = trailingCollapsed
    }

    /// Reads the saved state; absent or nonsensical values fall back to the defaults (widths are clamped to the metrics).
    public static func load(from store: any DockPreferenceStore, metrics: DockMetrics = DockMetrics()) -> DockPreferences {
        func width(_ key: String, _ fallback: Double) -> Double {
            guard let v = store.savedDouble(forKey: key), v.isFinite, v > 0 else { return fallback }
            return min(max(v, metrics.minWidth), metrics.maxWidth)
        }
        return DockPreferences(leadingWidth: width(keys.leadingWidth, defaultLeadingWidth), trailingWidth: width(keys.trailingWidth, defaultTrailingWidth),
                               leadingCollapsed: store.savedBool(forKey: keys.leadingCollapsed) ?? false, trailingCollapsed: store.savedBool(forKey: keys.trailingCollapsed) ?? false)
    }

    public func save(to store: any DockPreferenceStore) {
        store.save(leadingWidth, forKey: Self.keys.leadingWidth)
        store.save(trailingWidth, forKey: Self.keys.trailingWidth)
        store.save(leadingCollapsed, forKey: Self.keys.leadingCollapsed)
        store.save(trailingCollapsed, forKey: Self.keys.trailingCollapsed)
    }

    public func width(_ edge: DockEdge) -> Double { edge == .leading ? leadingWidth : trailingWidth }
    public func collapsed(_ edge: DockEdge) -> Bool { edge == .leading ? leadingCollapsed : trailingCollapsed }
    public mutating func setWidth(_ w: Double, _ edge: DockEdge) { if edge == .leading { leadingWidth = w } else { trailingWidth = w } }
    public mutating func setCollapsed(_ c: Bool, _ edge: DockEdge) { if edge == .leading { leadingCollapsed = c } else { trailingCollapsed = c } }
}

/// In-memory store for tests and previews.
public final class DictionaryDockStore: DockPreferenceStore {
    public var values: [String: Any] = [:]
    public init(_ values: [String: Any] = [:]) { self.values = values }
    public func savedDouble(forKey key: String) -> Double? { values[key] as? Double }
    public func savedBool(forKey key: String) -> Bool? { values[key] as? Bool }
    public func save(_ value: Double, forKey key: String) { values[key] = value }
    public func save(_ value: Bool, forKey key: String) { values[key] = value }
}

extension UserDefaults: DockPreferenceStore {
    public func savedDouble(forKey key: String) -> Double? { object(forKey: key) == nil ? nil : double(forKey: key) }
    public func savedBool(forKey key: String) -> Bool? { object(forKey: key) == nil ? nil : bool(forKey: key) }
    public func save(_ value: Double, forKey key: String) { set(value, forKey: key) }
    public func save(_ value: Bool, forKey key: String) { set(value, forKey: key) }
}
