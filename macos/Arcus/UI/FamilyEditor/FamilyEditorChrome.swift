import AppKit
import SwiftUI
import ArcusApplication

// FES: the Family Editor's window shell state (Docs/FurnitureMode.md §5). The editor uses the project window's shell:
// the canvas fills the window and the ribbon tab pill, the controls pill, the ribbon strip, the Options Bar, the view
// tabs, the bottom pill and the two docks float over it as Liquid Glass. Geometry comes from the same `DockLayout` and
// `ShellLayout` (Application layer) the project window uses; this holds the editor's own choices.

/// Ribbon, dock and status state of one Family Editor window.
@MainActor
@Observable
final class FamilyEditorChrome {
    /// The task tab shown when the contextual tab isn't.
    var ribbonTab: FamilyRibbonTab = .create
    /// The contextual "Modify | …" tab is showing (it opens when a sketch, tool or selection begins).
    var ribbonShowsContextual = false
    /// The ribbon is minimized to its tab pill (double-click a tab, or the chevron).
    var ribbonCollapsed = false
    /// Dock widths and collapsed flags, persisted apart from the project window's.
    let docks: DockLayoutState
    /// The controls pill's measured width (the ribbon tabs get the rest of the top row).
    var controlsWidth: Double = 0
    /// The canvas zoom in points per metre (the bottom pill's zoom readout).
    var zoomScale: Double = 400
    /// The canvas grid step in metres.
    var gridStep: Double = 0.1
    /// A zoom the bottom pill asks the canvas for (points per metre), consumed by the canvas.
    var zoomRequest: Double?
    /// The problems card (flex test, evaluation errors and warnings) over the bottom pill.
    var problemsShown = false
    /// The window this chrome belongs to (traffic lights, dock toggles).
    @ObservationIgnored weak var windowController: FamilyEditorWindowController?
    /// QA: the measured frames of the ribbon tabs and panels, in the window's shell coordinates (top-left origin).
    @ObservationIgnored var measuredTabs: [String: CGRect] = [:]
    @ObservationIgnored var measuredPanels: [String: CGRect] = [:]
    @ObservationIgnored var measuredStrip: CGRect = .zero
    @ObservationIgnored var measuredPanelRow: CGRect = .zero

    init(store: FamilyDockStore = FamilyDockStore()) {
        docks = DockLayoutState(store: store)
        docks.prefs = DockPreferences.load(from: store, metrics: .familyEditor) // the editor's narrower minimum
    }

    /// The left dock (Project Browser) is showing.
    var browserShown: Bool { !docks.prefs.leadingCollapsed }
    /// The right dock (Properties) is showing.
    var propertiesShown: Bool { !docks.prefs.trailingCollapsed }

    func toggleBrowser() { docks.setCollapsed(browserShown, .leading) }
    func toggleProperties() { docks.setCollapsed(propertiesShown, .trailing) }

    /// The smallest window: both docks at their minimum still leave the canvas and every ribbon tab name in view.
    static let minimumSize = NSSize(width: 1200, height: 700)
    /// Name of the shell's coordinate space (the window's content, top-left origin).
    nonisolated static let space = "familyEditor.shell"
}

extension DockMetrics {
    /// The Family Editor's docks: a little narrower than the project window's, so the six task tabs fit beside them.
    static let familyEditor: DockMetrics = {
        var m = DockMetrics.arcus
        m.minWidth = 250
        m.canvasMinWidth = 520
        return m
    }()
}

/// The Family Editor's dock preferences: the project window's keys under their own prefix, with narrower default
/// widths.
final class FamilyDockStore: DockPreferenceStore {
    private let defaults: UserDefaults
    private let prefix = "familyEditor."
    static let defaultLeadingWidth: Double = 260
    static let defaultTrailingWidth: Double = 280

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func savedDouble(forKey key: String) -> Double? {
        if let v = defaults.savedDouble(forKey: prefix + key) { return v }
        switch key {
        case "dock.leading.width": return Self.defaultLeadingWidth
        case "dock.trailing.width": return Self.defaultTrailingWidth
        default: return nil
        }
    }
    func savedBool(forKey key: String) -> Bool? { defaults.savedBool(forKey: prefix + key) }
    func save(_ value: Double, forKey key: String) { defaults.save(value, forKey: prefix + key) }
    func save(_ value: Bool, forKey key: String) { defaults.save(value, forKey: prefix + key) }
}
