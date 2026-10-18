import Foundation
import Synchronization
import ArcusGeometry
import ArcusCalc

/// The complete state of a project: an immutable-by-convention snapshot of elements plus project-wide data.
///
/// `BIMModel` is a value type. Background work (tessellation, schedules, export) receives a snapshot copy;
/// the document's authoritative model is only mutated by committing transactions.
public struct BIMModel: Sendable {
    public private(set) var elements: [ElementID: Element] = [:]
    public private(set) var nextID: UInt64 = 1
    /// Content-addressed immutable reference drawings (converted CAD/PDF content).
    public var referenceDrawings: [String: ReferenceDrawing] = [:]
    public var projectParameters: [ParameterDefinition] = []
    public var viewSheetSets: [ViewSheetSet] = []
    /// Monotonic model revision (incremented per committed transaction).
    public private(set) var revision: UInt64 = 0
    /// Process-unique stamp of this snapshot's element content: every element mutation assigns a fresh value, so two
    /// models with equal stamps have identical elements. Derived-data caches use it as a cheap first-level key.
    public private(set) var contentStamp: UInt64 = BIMModel.nextStamp()
    private static let stampCounter = Atomic<UInt64>(1)
    static func nextStamp() -> UInt64 { stampCounter.add(1, ordering: .relaxed).newValue }

    // Indexes (rebuilt on load, maintained incrementally).
    private var byCategory: [Category: Set<ElementID>] = [:]
    private var byHost: [ElementID: Set<ElementID>] = [:]
    private var byOwnerView: [ElementID: Set<ElementID>] = [:]
    private var byLevel: [ElementID: Set<ElementID>] = [:]
    private var byType: [ElementID: Set<ElementID>] = [:]
    private var tagsByTarget: [ElementID: Set<ElementID>] = [:]
    private var viewportsByView: [ElementID: Set<ElementID>] = [:]
    /// Uniform plan grid over linear model elements (walls, model/separation lines) so neighbour queries such as
    /// wall-join candidates and room boundary collection cost O(local) instead of O(n).
    private var planGrid = PlanGrid()

    public init() {}

    public init(elements: [Element], nextID: UInt64, referenceDrawings: [String: ReferenceDrawing] = [:],
                projectParameters: [ParameterDefinition] = [], viewSheetSets: [ViewSheetSet] = [], revision: UInt64 = 0) {
        self.nextID = nextID
        self.referenceDrawings = referenceDrawings
        self.projectParameters = projectParameters
        self.viewSheetSets = viewSheetSets
        self.revision = revision
        for var e in elements {
            if e.revision < Element.legacyRevisionLimit { e.revision = Element.nextRevision() }
            put(e)
        }
    }

    public var count: Int { elements.count }

    public subscript(_ id: ElementID?) -> Element? {
        guard let id else { return nil }
        return elements[id]
    }

    public func contains(_ id: ElementID) -> Bool { elements[id] != nil }

    // MARK: Mutation (used only by TransactionContext / persistence)

    mutating func allocateID() -> ElementID {
        defer { nextID += 1 }
        return ElementID(nextID)
    }
    mutating func reserveIDs(through raw: UInt64) { nextID = max(nextID, raw + 1) }
    mutating func bumpRevision() { revision += 1 }

    mutating func put(_ e: Element) {
        contentStamp = BIMModel.nextStamp()
        if let old = elements[e.id] { unindex(old) }
        elements[e.id] = e
        index(e)
        nextID = max(nextID, e.id.raw + 1)
    }
    mutating func remove(_ id: ElementID) {
        contentStamp = BIMModel.nextStamp()
        if let old = elements.removeValue(forKey: id) { unindex(old) }
    }

    private mutating func index(_ e: Element) {
        byCategory[e.category, default: []].insert(e.id)
        if let h = e.hostID { byHost[h, default: []].insert(e.id) }
        if let v = e.ownerViewID { byOwnerView[v, default: []].insert(e.id) }
        if let l = e.levelID { byLevel[l, default: []].insert(e.id) }
        if let t = e.typeID { byType[t, default: []].insert(e.id) }
        if case .tag(let t) = e.data { tagsByTarget[t.taggedID, default: []].insert(e.id) }
        if case .viewport(let vp) = e.data { viewportsByView[vp.viewID, default: []].insert(e.id) }
        if let b = PlanGrid.bounds(of: e) { planGrid.insert(e.id, b) }
    }
    private mutating func unindex(_ e: Element) {
        byCategory[e.category]?.remove(e.id)
        if let h = e.hostID { byHost[h]?.remove(e.id) }
        if let v = e.ownerViewID { byOwnerView[v]?.remove(e.id) }
        if let l = e.levelID { byLevel[l]?.remove(e.id) }
        if let t = e.typeID { byType[t]?.remove(e.id) }
        if case .tag(let t) = e.data { tagsByTarget[t.taggedID]?.remove(e.id) }
        if case .viewport(let vp) = e.data { viewportsByView[vp.viewID]?.remove(e.id) }
        if let b = PlanGrid.bounds(of: e) { planGrid.remove(e.id, b) }
    }

    // MARK: Queries

    /// Linear model elements (walls, model lines, room separation and area boundary lines) of `category` whose plan
    /// bounds intersect `rect`, sorted by id. Uses the incremental plan grid.
    public func elements(_ category: Category, intersecting rect: Rect2) -> [Element] {
        planGrid.query(rect).sorted().compactMap { id in elements[id].flatMap { $0.category == category ? $0 : nil } }
    }

    /// Elements of a category sorted by id (deterministic).
    public func elements(_ category: Category) -> [Element] {
        (byCategory[category] ?? []).sorted().compactMap { elements[$0] }
    }
    public func ids(_ category: Category) -> [ElementID] { (byCategory[category] ?? []).sorted() }
    public func elements(_ categories: [Category]) -> [Element] { categories.flatMap { elements($0) } }
    public func elements(kind: ElementKind) -> [Element] { elements.values.filter { $0.kind == kind }.sorted { $0.id < $1.id } }
    public var allElements: [Element] { elements.values.sorted { $0.id < $1.id } }

    public func hosted(by host: ElementID) -> [Element] { (byHost[host] ?? []).sorted().compactMap { elements[$0] } }
    public func owned(byView view: ElementID) -> [Element] { (byOwnerView[view] ?? []).sorted().compactMap { elements[$0] } }
    public func onLevel(_ level: ElementID) -> [Element] { (byLevel[level] ?? []).sorted().compactMap { elements[$0] } }
    public func instances(ofType type: ElementID) -> [Element] { (byType[type] ?? []).sorted().compactMap { elements[$0] } }
    public func instanceCount(ofType type: ElementID) -> Int { byType[type]?.count ?? 0 }
    public func tags(of target: ElementID) -> [Element] { (tagsByTarget[target] ?? []).sorted().compactMap { elements[$0] } }
    public func viewports(showing view: ElementID) -> [Element] { (viewportsByView[view] ?? []).sorted().compactMap { elements[$0] } }

    public func type(of e: Element) -> Element? { self[e.typeID] }
    public func typeData(of e: Element) -> TypeData? { self[e.typeID]?.typeData }

    /// Levels sorted by elevation.
    public var levels: [Element] {
        elements(.levels).sorted { ($0.level?.elevation ?? 0, $0.id.raw) < ($1.level?.elevation ?? 0, $1.id.raw) }
    }
    public func elevation(ofLevel id: ElementID?) -> Double { self[id]?.level?.elevation ?? 0 }
    /// The level directly above the given level, if any.
    public func levelAbove(_ id: ElementID?) -> Element? {
        let ls = levels
        guard let i = ls.firstIndex(where: { $0.id == id }), i + 1 < ls.count else { return nil }
        return ls[i + 1]
    }
    public func level(named n: String) -> Element? { levels.first { $0.name == n } }

    public var phases: [Element] { elements(.phases).sorted { ($0.phase?.order ?? 0) < ($1.phase?.order ?? 0) } }
    public var latestPhase: Element? { phases.last }
    public func phaseOrder(_ id: ElementID?) -> Int? { self[id]?.phase?.order }

    public var projectInfoElement: Element? { elements(.projectInfo).first }
    public var projectInfo: ProjectInfoData { projectInfoElement?.projectInfo ?? ProjectInfoData() }
    public var units: UnitsSettings { projectInfo.units }

    public func types(for category: Category) -> [Element] {
        elements(.elementTypes).filter { $0.typeData?.instanceCategory == category }
            .sorted { ($0.typeData?.familyName ?? "", $0.name) < ($1.typeData?.familyName ?? "", $1.name) }
    }
    public func types(systemFamily: SystemFamily) -> [Element] {
        elements(.elementTypes).filter { $0.typeData?.systemFamily == systemFamily }.sorted { $0.name < $1.name }
    }
    public func type(category: Category, family: String? = nil, name: String) -> Element? {
        types(for: category).first { $0.name == name && (family == nil || $0.typeData?.familyName == family) }
    }
    public var materials: [Element] { elements(.materials).sorted { $0.name < $1.name } }
    public func material(named n: String) -> Element? { elements(.materials).first { $0.name == n } }
    public func family(named n: String) -> Element? { elements(.families).first { $0.name == n } }
    public var views: [Element] { elements(.views) }
    public var sheets: [Element] {
        elements(.sheets).sorted { ($0.sheet?.number ?? "").localizedStandardCompare($1.sheet?.number ?? "") == .orderedAscending }
    }
    public var schedules: [Element] { elements(.schedules).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    public var revisions: [Element] { elements(.revisions).sorted { ($0.revisionData?.sequence ?? 0) < ($1.revisionData?.sequence ?? 0) } }
    public func lineStyle(named n: String) -> Element? { elements(.lineStyles).first { $0.name == n } }
    public func fillPattern(named n: String) -> Element? { elements(.fillPatterns).first { $0.name == n } }

    /// The sheet a view is placed on, if any.
    public func sheet(containing view: ElementID) -> Element? {
        viewports(showing: view).first.flatMap { self[$0.ownerViewID] }
    }

    /// Resolves the base elevation of an element that has a level plus an offset.
    public func baseElevation(of e: Element) -> Double {
        let lv = elevation(ofLevel: e.levelID)
        switch e.data {
        case .wall(let w): return lv + w.baseOffset
        case .column(let c): return lv + c.baseOffset
        case .stair(let s): return lv + s.baseOffset
        case .ramp(let r): return lv + r.baseOffset
        case .component(let c): return lv + c.offset
        case .slab(let s): return lv + s.offset
        case .roof(let r): return lv + r.baseOffset
        case .room(let r): return lv + r.baseOffset
        case .railing(let r): return lv + r.baseOffset
        case .insert(let i):
            let host = self[e.hostID]
            let hostBase = host.map(baseElevation(of:)) ?? lv
            return hostBase + i.sillHeight
        default: return lv
        }
    }

    /// Top elevation for level-constrained vertical elements.
    public func topElevation(base: Double, topLevelID: ElementID?, topOffset: Double, unconnectedHeight: Double) -> Double {
        if let t = topLevelID, let lv = self[t]?.level { return lv.elevation + topOffset }
        return base + unconnectedHeight
    }

    /// Parameter value helpers on types.
    public func typeParam(_ e: Element, _ id: ParameterID) -> ParamValue? { typeData(of: e)?.params[id] }
    public func typeLength(_ e: Element, _ id: ParameterID, default d: Double) -> Double { typeParam(e, id)?.doubleValue ?? d }
}

/// Sparse uniform grid of element plan bounds (cell size 8 m). Elements spanning more than `maxCells` cells are kept
/// in an overflow set that every query returns, so very long elements stay correct without flooding the grid.
struct PlanGrid: Sendable {
    static let cell = 8.0
    static let maxCells = 256
    private var cells: [SIMD2<Int32>: Set<ElementID>] = [:]
    private var overflow: Set<ElementID> = []

    static func bounds(of e: Element) -> Rect2? {
        switch e.data {
        case .wall(let w): return w.location.bounds
        case .modelLine(let l) where e.category != .propertyLines: return l.drawnBounds // F1: splines and ellipses
        default: return nil
        }
    }
    private static func range(_ r: Rect2) -> (SIMD2<Int32>, SIMD2<Int32>)? {
        guard !r.isEmpty, r.min.x.isFinite, r.min.y.isFinite, r.max.x.isFinite, r.max.y.isFinite,
              abs(r.min.x) < 1e7, abs(r.min.y) < 1e7, abs(r.max.x) < 1e7, abs(r.max.y) < 1e7 else { return nil }
        let a = SIMD2<Int32>(Int32((r.min.x / cell).rounded(.down)), Int32((r.min.y / cell).rounded(.down)))
        let b = SIMD2<Int32>(Int32((r.max.x / cell).rounded(.down)), Int32((r.max.y / cell).rounded(.down)))
        return (a, b)
    }
    mutating func insert(_ id: ElementID, _ r: Rect2) {
        guard let (a, b) = Self.range(r), Int(b.x - a.x + 1) * Int(b.y - a.y + 1) <= Self.maxCells else { overflow.insert(id); return }
        for x in a.x...b.x { for y in a.y...b.y { cells[SIMD2(x, y), default: []].insert(id) } }
    }
    mutating func remove(_ id: ElementID, _ r: Rect2) {
        guard let (a, b) = Self.range(r), Int(b.x - a.x + 1) * Int(b.y - a.y + 1) <= Self.maxCells else { overflow.remove(id); return }
        for x in a.x...b.x {
            for y in a.y...b.y {
                let k = SIMD2(x, y)
                cells[k]?.remove(id)
                if cells[k]?.isEmpty == true { cells.removeValue(forKey: k) }
            }
        }
    }
    func query(_ r: Rect2) -> Set<ElementID> {
        var out = overflow
        guard let (a, b) = Self.range(r) else { return out.union(cells.values.joined()) }
        if Int(b.x - a.x + 1) * Int(b.y - a.y + 1) > cells.count {
            for set in cells.values { out.formUnion(set) }
            return out
        }
        for x in a.x...b.x { for y in a.y...b.y { if let s = cells[SIMD2(x, y)] { out.formUnion(s) } } }
        return out
    }
}
