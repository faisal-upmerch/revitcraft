import Foundation
import ArcusGeometry

// BL-BROWSER: level-relative view ranges, Place View candidates, interactive viewport placement and title blocks.

/// A view-range plane measured from a level relative to the view's own ("Level Above"), or without limit.
public enum ViewRangeAnchor: String, Codable, Sendable, CaseIterable {
    case levelAbove = "Level Above", levelBelow = "Level Below", unlimited = "Unlimited"
}

/// The level a view-range plane is measured from, as offered by the View Range dialog.
public enum ViewRangeLevel: Hashable, Sendable {
    case associated, levelAbove, levelBelow, unlimited, level(ElementID)

    public var anchor: ViewRangeAnchor? {
        switch self {
        case .levelAbove: .levelAbove
        case .levelBelow: .levelBelow
        case .unlimited: .unlimited
        default: nil
        }
    }
    public var levelID: ElementID? { if case .level(let id) = self { id } else { nil } }

    public init(levelID: ElementID?, anchor: ViewRangeAnchor?, viewLevel: ElementID?) {
        switch anchor {
        case .levelAbove: self = .levelAbove
        case .levelBelow: self = .levelBelow
        case .unlimited: self = .unlimited
        case nil: self = (levelID == nil || levelID == viewLevel) ? .associated : .level(levelID!)
        }
    }

    public func title(_ m: BIMModel) -> String {
        switch self {
        case .associated: "Associated Level"
        case .levelAbove: "Level Above"
        case .levelBelow: "Level Below"
        case .unlimited: "Unlimited"
        case .level(let id): m[id]?.name ?? "Missing level"
        }
    }
}

extension ViewRange {
    /// Planes of a plan's view range.
    public enum Plane: String, Sendable, CaseIterable { case top = "Top", cut = "Cut plane", bottom = "Bottom", depth = "View depth" }

    /// Every plane is measured from the view's own level (as in files written before level-relative ranges).
    public var isAssociatedLevelOnly: Bool {
        topLevelID == nil && bottomLevelID == nil && depthLevelID == nil && topAnchor == nil && bottomAnchor == nil && depthAnchor == nil
    }

    /// Height used for "Unlimited" (and for a relative level that doesn't exist), in meters from the project zero.
    public static let unlimitedExtent = 10_000.0

    public func level(_ p: Plane, viewLevel: ElementID?) -> ViewRangeLevel {
        switch p {
        case .top: ViewRangeLevel(levelID: topLevelID, anchor: topAnchor, viewLevel: viewLevel)
        case .cut: .associated
        case .bottom: ViewRangeLevel(levelID: bottomLevelID, anchor: bottomAnchor, viewLevel: viewLevel)
        case .depth: ViewRangeLevel(levelID: depthLevelID, anchor: depthAnchor, viewLevel: viewLevel)
        }
    }

    public func offset(_ p: Plane) -> Double {
        switch p { case .top: topOffset; case .cut: cutOffset; case .bottom: bottomOffset; case .depth: depthOffset }
    }

    public mutating func set(_ p: Plane, level: ViewRangeLevel, offset: Double) {
        switch p {
        case .top: topLevelID = level.levelID; topAnchor = level.anchor; topOffset = offset
        case .cut: cutOffset = offset
        case .bottom: bottomLevelID = level.levelID; bottomAnchor = level.anchor; bottomOffset = offset
        case .depth: depthLevelID = level.levelID; depthAnchor = level.anchor; depthOffset = offset
        }
    }

    /// Absolute elevation of a plane for a plan associated with `viewLevel`.
    public func z(_ p: Plane, viewLevel: ElementID?, in m: BIMModel) -> Double {
        let base = m.elevation(ofLevel: viewLevel)
        let above = p == .top
        switch level(p, viewLevel: viewLevel) {
        case .associated: return base + offset(p)
        case .level(let id): return m[id]?.level != nil ? m.elevation(ofLevel: id) + offset(p) : base + offset(p)
        case .unlimited: return above ? Self.unlimitedExtent : -Self.unlimitedExtent
        case .levelAbove:
            guard let l = m.levelAbove(viewLevel) else { return Self.unlimitedExtent }
            return m.elevation(ofLevel: l.id) + offset(p)
        case .levelBelow:
            let ls = m.levels
            guard let i = ls.firstIndex(where: { $0.id == viewLevel }), i > 0 else { return -Self.unlimitedExtent }
            return m.elevation(ofLevel: ls[i - 1].id) + offset(p)
        }
    }

    /// Why the range is invalid (Top ≥ Cut ≥ Bottom ≥ View Depth), or nil.
    public func problem(viewLevel: ElementID?, in m: BIMModel) -> String? {
        let t = z(.top, viewLevel: viewLevel, in: m), c = z(.cut, viewLevel: viewLevel, in: m)
        let b = z(.bottom, viewLevel: viewLevel, in: m), d = z(.depth, viewLevel: viewLevel, in: m)
        let tol = Tolerance.length
        if t < c - tol { return "The top of the primary range is below the cut plane. Raise the top or lower the cut plane." }
        if c < b - tol { return "The cut plane is below the bottom of the primary range. Lower the bottom or raise the cut plane." }
        if b < d - tol { return "The view depth is above the bottom of the primary range. Set the view depth at or below the bottom." }
        return nil
    }

    /// Levels offered for a plane: Associated Level, the relative choices that apply, then every named level.
    public static func choices(for p: Plane, _ m: BIMModel) -> [ViewRangeLevel] {
        let named = m.levels.map { ViewRangeLevel.level($0.id) }
        switch p {
        case .top: return [.associated, .levelAbove, .unlimited] + named
        case .cut: return [.associated]
        case .bottom, .depth: return [.associated, .levelBelow, .unlimited] + named
        }
    }
}

/// The list of the Place View dialog: views and schedules that can go on a sheet, with type-prefixed names.
public enum PlaceViewCandidates {
    public struct Candidate: Hashable, Sendable, Identifiable {
        public var id: ElementID
        public var title: String
        public var symbol: String
    }

    /// Candidates for a sheet matching `search` (case-insensitive; empty matches all). Views already on a sheet are
    /// left out (legends and schedules may go on many sheets); sheets and view templates never appear.
    public static func list(forSheet sheetID: ElementID, _ m: BIMModel, search: String = "") -> [Candidate] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let order = ProjectBrowserTree.viewFolderOrder + [.legend]
        let views = m.views.filter { $0.view != nil && SheetPlacement.refusal($0.id, onSheet: sheetID, m) == nil }
            .sorted { a, b in
                let ka = order.firstIndex(of: a.view!.kind) ?? 99, kb = order.firstIndex(of: b.view!.kind) ?? 99
                return ka != kb ? ka < kb : a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        let schedules = m.schedules.filter { SheetPlacement.refusal($0.id, onSheet: sheetID, m) == nil }
        return (views + schedules).map { e in
            Candidate(id: e.id, title: ViewTitles.qualified(e), symbol: e.schedule != nil ? "tablecells" : (e.view?.kind.symbolName ?? "rectangle"))
        }.filter { q.isEmpty || $0.title.lowercased().contains(q) }
    }
}

extension SheetPlacement {
    /// Size on paper (meters) a view or schedule takes when placed: its region at its scale, or the schedule table.
    public static func paperSize(of viewID: ElementID, _ m: BIMModel) -> Vec2 {
        guard let v = m[viewID] else { return Vec2(0.1, 0.1) }
        if v.schedule != nil {
            let table = ScheduleEngine.compute(v, m)
            return Vec2(table.totalWidth, Double(table.rows.count + 1) * ScheduleLayout.rowHeight + ScheduleLayout.titleHeight)
        }
        guard let vd = v.view else { return Vec2(0.1, 0.1) }
        let region = SheetGraphicsBuilder.viewRegion(ViewGraphicsBuilder(model: m, view: v).build())
        let s = Double(max(vd.scale, 1))
        return Vec2(max(region.width / s, 0.01), max(region.height / s, 0.01))
    }

    /// Centres for several viewports placed together: a row, left to right, centred on `anchor`, `gap` apart.
    public static func tiledCenters(sizes: [Vec2], at anchor: Vec2, gap: Double = 0.01) -> [Vec2] {
        guard !sizes.isEmpty else { return [] }
        let total = sizes.reduce(0) { $0 + $1.x } + gap * Double(sizes.count - 1)
        var x = anchor.x - total / 2
        return sizes.map { s in
            defer { x += s.x + gap }
            return Vec2(x + s.x / 2, anchor.y)
        }
    }

    /// Places several views at once (tiled around `anchor`). Views that can't be placed are skipped and reported.
    @discardableResult
    public static func place(_ viewIDs: [ElementID], sizes: [Vec2], onSheet sheetID: ElementID, at anchor: Vec2, in tx: TransactionContext) throws -> (placed: [ElementID], refused: [String]) {
        let centers = tiledCenters(sizes: sizes, at: anchor)
        var placed: [ElementID] = [], refused: [String] = []
        for (i, v) in viewIDs.enumerated() {
            if let r = refusal(v, onSheet: sheetID, tx.model) { refused.append(r); continue }
            placed.append(try place(v, onSheet: sheetID, at: i < centers.count ? centers[i] : anchor, in: tx))
        }
        if placed.isEmpty { throw TransactionError(refused.first ?? "Nothing to place.", elements: viewIDs) }
        return (placed, refused)
    }
}

/// Title blocks set the sheet size: choosing a title block type changes the sheet's paper to match.
public enum SheetTitleBlocks {
    /// Title block types, by family then name.
    public static func types(_ m: BIMModel) -> [Element] { m.types(for: .titleBlocks) }

    /// The paper a title block type is drawn for: its name ("A1 Title Block", "ARCH D …") or, failing that, the
    /// paper closest to the extents of its linework.
    public static func paper(forTitleBlockType id: ElementID, _ m: BIMModel) -> PaperSize? {
        guard let t = m[id], let td = t.typeData else { return nil }
        let names = [t.name, td.familyName].map { $0.uppercased() }
        for p in PaperSize.allCases.sorted(by: { $0.rawValue.count > $1.rawValue.count }) {
            let key = p.rawValue.uppercased()
            if names.contains(where: { $0 == key || $0.hasPrefix(key + " ") || $0.hasPrefix(key + "-") || $0.hasPrefix(key + "_") }) { return p }
        }
        guard let famID = td.familyID, let fam = m[famID]?.family else { return nil }
        let ev = FamilyEvaluator.evaluate(Parameters.effectiveFamily(fam, for: t, m), typeName: "project", instance: [:], units: m.units)
        var r = Rect2.empty
        for l in ev.annotationLines {
            switch l.curve {
            case .line(let s): r.include(s.start); r.include(s.end)
            case .arc(let a): r.include(a.bounds)
            }
        }
        guard !r.isEmpty else { return nil }
        let size = Vec2(r.max.x + max(r.min.x, 0), r.max.y + max(r.min.y, 0))
        return PaperSize.allCases.min { $0.landscapeSize.distance(to: size) < $1.landscapeSize.distance(to: size) }
    }

    /// Sets a sheet's title block and resizes the sheet to the title block's paper.
    public static func setTitleBlock(_ typeID: ElementID?, on sheetID: ElementID, in tx: TransactionContext) throws {
        guard tx.model[sheetID]?.sheet != nil else { throw TransactionError("Choose a sheet.") }
        if let typeID, tx.model[typeID]?.typeData?.instanceCategory != .titleBlocks { throw TransactionError("That type is not a title block.") }
        let paper = typeID.flatMap { paper(forTitleBlockType: $0, tx.model) }
        tx.update(sheetID) { e in
            e.sheet?.titleBlockTypeID = typeID
            if let paper { e.sheet?.paper = paper }
        }
    }

    /// Guide grid spacings offered on sheets (paper meters; nil = none).
    public static let guideGridChoices: [(String, Double?)] = [("<None>", nil), ("5 mm", 0.005), ("10 mm", 0.01), ("25 mm", 0.025), ("50 mm", 0.05),
                                                                ("1/4\"", 0.00635), ("1/2\"", 0.0127), ("1\"", 0.0254)]
}
