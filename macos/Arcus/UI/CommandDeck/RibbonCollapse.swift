import SwiftUI
import AppKit
import ArcusApplication

// POLISH: Revit-style ribbon panel collapsing. When a window is too narrow for a tab's panels, the panels shrink from
// the right: large buttons become small ones (stacked three high), then icons, and finally whole panels collapse into
// a single button (panel title and chevron) that opens the panel in a popover. Every command stays one or two clicks
// away at any window width, instead of being cut off at the strip's edge. Used by the project ribbon (Ribbon.swift)
// and the Family Editor ribbon (FamilyRibbon.swift).

/// How densely a ribbon panel draws its buttons: 0 as designed, 1 large buttons drawn small, 2 every button an icon.
extension EnvironmentValues {
    @Entry var ribbonDensity: Int = 0
    /// Where the ribbon records its laid-out panels (QA checks and tests), if anywhere.
    @Entry var ribbonFrames: RibbonFrames? = nil
    /// False inside the More popover: panels shown there don't report frames as the ribbon's.
    @Entry var ribbonRecording: Bool = true
}

/// Marks the row's More button (the last resort when even collapsed panels don't fit).
nonisolated struct RibbonOverflowKey: LayoutValueKey { static let defaultValue = false }

extension RibbonItem.Size {
    /// The size a button of this size draws at `density`.
    func at(density: Int) -> RibbonItem.Size {
        switch density {
        case ...0: self
        case 1: self == .large ? .small : self
        default: .icon
        }
    }
}

/// The frames (window coordinates) of a ribbon's panel row and its panels as last laid out, and which panels are
/// collapsed or shrunk; for the QA check that no panel is clipped.
@MainActor
final class RibbonFrames {
    var row: CGRect = .zero
    /// Keyed "<index> <title>", in row order.
    var panels: [String: CGRect] = [:]
    /// Each panel's density as laid out (3 = collapsed into its button).
    var density: [String: Int] = [:]
    func reset() { panels = [:]; density = [:]; overflow = nil }

    /// The project ribbon's frames of a document window.
    static func of(_ state: DocumentState) -> RibbonFrames {
        let key = ObjectIdentifier(state)
        if let f = byState[key] { return f }
        let f = RibbonFrames()
        byState[key] = f
        return f
    }
    private static var byState: [ObjectIdentifier: RibbonFrames] = [:]

    /// The More button's frame, when the row shows it.
    var overflow: CGRect?
    /// Panels in the More popover (parked out of sight because not even their collapsed buttons fit).
    var inOverflow: [String] { overflowShown ? panels.filter { $0.value.maxX < RibbonPanelRow.parking / 2 }.map(\.key).sorted() : [] }
    var overflowShown: Bool { overflow.map { $0.minX >= row.minX - 0.5 && $0.maxX <= row.maxX + 0.5 } ?? false }

    /// Panels that stick out of the row (with half a point of slack), as "title: frame"; panels in the More popover
    /// are reachable and don't count.
    func clipped() -> [String] {
        let parked = Set(inOverflow)
        return panels.filter { k, r in !parked.contains(k) && (r.minX < row.minX - 0.5 || r.maxX > row.maxX + 0.5 || r.minY < row.minY - 0.5 || r.maxY > row.maxY + 0.5) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { "\($0.key) \(Int($0.value.minX))–\(Int($0.value.maxX)) (row \(Int(row.minX))–\(Int(row.maxX)))" }
    }
}

/// Lays ribbon panels out in a row that fits the width it's offered. Each panel is a `ViewThatFits` of its variants
/// (as designed, compact, icons, collapsed); the row probes each panel's variant widths and picks, from the right, the
/// densest variants needed: first every panel compact, then icons, then panels collapse, until the row fits.
struct RibbonPanelRow: Layout {
    var spacing: CGFloat = 4
    /// Where panels that only the More popover shows are put (far out of sight).
    static let parking: CGFloat = -100_000

    struct Cache { var widths: [[CGFloat]]; var height: CGFloat; var overflow: Int? }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(widths: subviews.map(Self.variantWidths), height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0,
              overflow: subviews.firstIndex { $0[RibbonOverflowKey.self] })
    }

    /// Each panel's variant (nil: in the More popover) and whether the More button shows.
    static func arrangement(_ cache: Cache, available: CGFloat, spacing: CGFloat) -> (levels: [Int?], overflow: Bool) {
        let panels = cache.widths.indices.filter { $0 != cache.overflow }
        let widths = panels.map { cache.widths[$0] }
        var levels: [Int?] = cache.widths.map { _ in nil }
        let plan = plan(widths, available: available, spacing: spacing)
        let used = zip(widths, plan).map { $0[$1] }
        let total = used.reduce(0, +) + spacing * CGFloat(max(0, used.filter { $0 > 0.5 }.count - 1))
        guard let o = cache.overflow, total > available else {
            for (k, i) in panels.enumerated() { levels[i] = plan[k] }
            return (levels, false)
        }
        // Not even collapsed panels fit: as many as fit before the More button, which shows them all.
        var x = (cache.widths[o].first ?? 0)
        for (k, i) in panels.enumerated() {
            let w = widths[k].last ?? 0
            guard x + spacing + w <= available else { break }
            x += spacing + w
            levels[i] = widths[k].count - 1
        }
        return (levels, true)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = makeCache(subviews: subviews) }

    /// A panel's variant widths, widest first: what it takes unconstrained, then what it takes when offered a little
    /// less than each, until it can get no narrower.
    static func variantWidths(_ s: LayoutSubview) -> [CGFloat] {
        var ws = [s.sizeThatFits(.unspecified).width]
        while ws.count < 6, let last = ws.last, last > 1 {
            let next = s.sizeThatFits(ProposedViewSize(width: last - 0.5, height: nil)).width
            guard next < last - 0.25 else { break }
            ws.append(next)
        }
        return ws
    }

    /// The variant of each panel for `available` points: every panel as designed when it fits; else, a step at a time
    /// and from the right, the next denser variant short of collapsing; then panels collapse, from the right; then any
    /// room left over goes back to the leftmost panels.
    static func plan(_ widths: [[CGFloat]], available: CGFloat, spacing: CGFloat) -> [Int] {
        var level = widths.map { _ in 0 }
        func total() -> CGFloat {
            let shown = widths.indices.map { widths[$0][level[$0]] }
            return shown.reduce(0, +) + spacing * CGFloat(max(0, shown.filter { $0 > 0.5 }.count - 1))
        }
        guard total() > available else { return level }
        // Once it fits, give back what the room left over allows, leftmost panels first (a big step such as a
        // collapse can free more than was needed).
        func relaxed() -> [Int] {
            for i in widths.indices {
                while level[i] > 0 {
                    level[i] -= 1
                    if total() > available { level[i] += 1; break }
                }
            }
            return level
        }
        let deepest = widths.map(\.count).max() ?? 1
        for step in 1..<max(1, deepest - 1) {
            for i in widths.indices.reversed() where widths[i].count - 1 > step && level[i] < step {
                level[i] = step
                if total() <= available { return relaxed() }
            }
        }
        for i in widths.indices.reversed() where widths[i].count > 1 && level[i] < widths[i].count - 1 {
            level[i] = widths[i].count - 1
            if total() <= available { return relaxed() }
        }
        return level
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let available = proposal.width ?? .infinity
        let total = cache.widths.indices.filter { $0 != cache.overflow }.map { cache.widths[$0][0] }.reduce(0, +)
        return CGSize(width: available.isFinite ? max(available, 0) : total + spacing * CGFloat(max(0, cache.widths.count - 2)), height: cache.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let (levels, overflow) = Self.arrangement(cache, available: bounds.width, spacing: spacing)
        var x = bounds.minX
        for (i, s) in subviews.enumerated() where i != cache.overflow {
            guard let level = levels[i] else {
                s.place(at: CGPoint(x: Self.parking, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: cache.widths[i].last, height: nil))
                continue
            }
            let w = cache.widths[i][level]
            s.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: w + 0.1, height: nil))
            if w > 0.5 { x += w + spacing }
        }
        if let o = cache.overflow {
            subviews[o].place(at: CGPoint(x: overflow ? x : Self.parking, y: bounds.minY), anchor: .topLeading, proposal: .unspecified)
        }
    }

}

/// A panel that can shrink and collapse inside a `RibbonPanelRow`: its content as designed, then drawn compact and as
/// icons (through `ribbonDensity`), then the collapsed button. `variants` gives the content at a density when the
/// panel draws its own (the project ribbon repacks its columns); otherwise the density goes down the environment.
struct CollapsibleRibbonPanel<Content: View>: View {
    let key: String
    let title: String
    var symbol: String = "square.grid.2x2"
    var tint: Color = .accentColor
    var contextual = false
    let content: (Int) -> Content
    @Environment(\.ribbonFrames) private var frames

    var body: some View {
        ViewThatFits(in: .horizontal) {
            variant(0)
            variant(1)
            variant(2)
            RibbonCollapsedPanel(title: title, symbol: symbol, tint: tint, contextual: contextual) { content(0).environment(\.ribbonDensity, 0) }
                .fixedSize()
                .modifier(RibbonFrameRecorder(key: key, density: 3, frames: frames))
        }
    }

    func variant(_ d: Int) -> some View {
        content(d).environment(\.ribbonDensity, d).fixedSize().modifier(RibbonFrameRecorder(key: key, density: d, frames: frames))
    }
}

/// Records a laid-out panel's frame (window coordinates) and density.
struct RibbonFrameRecorder: ViewModifier {
    let key: String
    let density: Int
    let frames: RibbonFrames?
    @Environment(\.ribbonRecording) private var recording
    func body(content: Content) -> some View {
        if let frames, recording {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
                frames.panels[key] = r
                frames.density[key] = density
            }
        } else {
            content
        }
    }
}

extension View {
    /// Makes a ribbon panel collapsible in a `RibbonPanelRow` (its buttons follow `ribbonDensity`).
    func ribbonCollapsible(_ key: String, title: String, symbol: String = "square.grid.2x2", tint: Color = .accentColor, contextual: Bool = false) -> some View {
        CollapsibleRibbonPanel(key: key, title: title, symbol: symbol, tint: tint, contextual: contextual) { _ in self }
    }

    /// Records the frame of a ribbon's panel row.
    func ribbonRowFrame(_ frames: RibbonFrames?) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in frames?.row = r }
    }
}

/// A collapsed panel: its title, as a button the height of the ribbon, with a chevron; clicking it shows the whole
/// panel in a popover under it (Revit's collapsed panel slide-out).
struct RibbonCollapsedPanel<Panel: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    var contextual = false
    @ViewBuilder let panel: () -> Panel
    @State private var open = false

    var body: some View {
        PanelCard(title: title, contextual: contextual) {
            Button { open.toggle() } label: {
                VStack(spacing: 2) {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: RibbonMetrics.largeIcon))
                        .foregroundStyle(tint)
                        .frame(width: 30, height: 26)
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary).frame(height: 12)
                }
                .frame(minWidth: 40, maxHeight: RibbonMetrics.contentHeight, alignment: .top)
                .padding(.horizontal, 4).padding(.top, 2)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(RibbonPressStyle())
            .modifier(HoverBackground(active: open, tint: tint, radius: 8))
            .popover(isPresented: $open, arrowEdge: .bottom) {
                panel().padding(6)
            }
        }
        .help("\(title): the window is too narrow for this panel. Click to show its tools.")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) panel, collapsed")
    }
}

/// The row's last resort, when the window is too narrow even for collapsed panels: a More button at the end of the
/// row that shows all of the tab's panels in a popover, wrapped into rows.
struct RibbonOverflowButton<Panels: View>: View {
    @ViewBuilder let panels: () -> Panels
    @Environment(\.ribbonFrames) private var frames
    @State private var open = false

    var body: some View {
        PanelCard(title: "More") {
            Button { open.toggle() } label: {
                VStack(spacing: 2) {
                    Image(systemName: "chevron.right.2").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary).frame(width: 30, height: 26)
                }
                .frame(minWidth: 32, maxHeight: RibbonMetrics.contentHeight, alignment: .top)
                .padding(.top, 2)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(RibbonPressStyle())
            .modifier(HoverBackground(active: open, radius: 8))
            .popover(isPresented: $open, arrowEdge: .bottom) {
                RibbonFlow(spacing: 4, maxWidth: 760) { panels() }
                    .environment(\.ribbonRecording, false)
                    .padding(8)
            }
        }
        .fixedSize()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in frames?.overflow = r }
        .help("More of this tab's tools: the window is too narrow to show them all.")
        .accessibilityLabel("More ribbon panels")
        .layoutValue(key: RibbonOverflowKey.self, value: true)
    }
}

/// Panels wrapped into rows no wider than `maxWidth` (the More popover).
struct RibbonFlow: Layout {
    var spacing: CGFloat = 4
    var maxWidth: CGFloat = 760

    func rows(_ subviews: Subviews) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let size = s.sizeThatFits(.unspecified)
            guard size.width > 0.5 else { continue }
            if x > 0, x + size.width > maxWidth { rows.append([]); x = 0 }
            rows[rows.count - 1].append((i, size))
            x += size.width + spacing
        }
        return rows.filter { !$0.isEmpty }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let r = rows(subviews)
        let w = r.map { row in row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, row.count - 1)) }.max() ?? 0
        let h = r.map { row in row.map(\.1.height).max() ?? 0 }.reduce(0, +) + spacing * CGFloat(max(0, r.count - 1))
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var placed = Set<Int>()
        for row in rows(subviews) {
            var x = bounds.minX
            for (i, size) in row {
                subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                placed.insert(i)
                x += size.width + spacing
            }
            y += (row.map(\.1.height).max() ?? 0) + spacing
        }
        for i in subviews.indices where !placed.contains(i) { subviews[i].place(at: .zero, anchor: .topLeading, proposal: .zero) }
    }
}

extension RibbonCollapse {
    /// The symbols the collapsing code draws itself (checked by the symbol test).
    static let ownSymbols = ["square.grid.2x2", "chevron.down", "chevron.right.2"]
}

/// Namespace for the collapsing ribbon's constants.
enum RibbonCollapse {}
