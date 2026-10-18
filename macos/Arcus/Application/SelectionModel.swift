import Foundation
import Observation
import ArcusGeometry
import ArcusDomain

/// Current selection, preselection and selection filter.
@MainActor
@Observable
public final class SelectionModel {
    public private(set) var ids: [ElementID] = []
    public var preselection: ElementID?
    /// Categories allowed by the selection filter (nil = all).
    public var filter: Set<Category>? = nil
    /// Whether pinned elements can be selected, links can be selected, etc.
    public var selectPinned = true
    public var selectLinks = true
    public var selectUnderlay = false
    /// Candidates under the cursor for Tab cycling.
    public private(set) var cycleCandidates: [ElementID] = []
    public private(set) var cycleIndex = 0
    /// Walls joined end to end with the wall under the cursor: the last Tab entry preselects the whole chain.
    public private(set) var cycleChain: [ElementID] = []
    /// The last non-empty selection before the current one (Select Previous).
    public private(set) var previous: [ElementID] = []

    public init() {}

    public var set: Set<ElementID> { Set(ids) }
    public var isEmpty: Bool { ids.isEmpty }
    public var count: Int { ids.count }
    public var single: ElementID? { ids.count == 1 ? ids[0] : nil }
    public func contains(_ id: ElementID) -> Bool { ids.contains(id) }

    public func allows(_ e: Element) -> Bool {
        if let f = filter, !f.contains(e.category) { return false }
        if !selectPinned && e.pinned { return false }
        if !selectLinks && e.category == .importedCAD { return false }
        return true
    }

    /// Every change goes through here so the last non-empty selection is remembered for Select Previous.
    private func setIDs(_ newIDs: [ElementID]) {
        guard newIDs != ids else { return }
        if !ids.isEmpty { previous = ids }
        ids = newIDs
    }

    public func select(_ newIDs: [ElementID]) {
        var seen = Set<ElementID>()
        setIDs(newIDs.filter { seen.insert($0).inserted })
    }
    public func add(_ newIDs: [ElementID]) { select(ids + newIDs) }
    public func remove(_ remove: [ElementID]) { let r = Set(remove); setIDs(ids.filter { !r.contains($0) }) }
    public func toggle(_ id: ElementID) { if contains(id) { remove([id]) } else { add([id]) } }
    public func clear() { setIDs([]); cycleCandidates = []; cycleChain = []; cycleIndex = 0 }

    /// Select Previous: restores the last non-empty selection (elements deleted since are skipped).
    /// Returns false when there is nothing to restore.
    @discardableResult
    public func selectPrevious(in model: BIMModel) -> Bool {
        let restore = previous.filter { model[$0] != nil }
        guard !restore.isEmpty else { return false }
        select(restore)
        return true
    }

    /// How modifier keys combine with clicks and window selections.
    /// `.bim`: ⌘ (or ⌃) adds, ⇧ removes — the convention of mainstream BIM tools.
    /// `.mac`: ⇧ adds, ⌘ toggles — the Finder convention.
    public enum ModifierStyle: String, CaseIterable, Sendable { case bim, mac }
    /// Process-wide style; the app sets it from the user's setting at launch. Library default is `.mac`.
    public static var modifierStyle: ModifierStyle = .mac

    public enum Operation: Equatable { case replace, add, remove, toggle }
    /// The operation a click or window selection performs for the held modifiers.
    public static func operation(shift: Bool, command: Bool) -> Operation {
        switch modifierStyle {
        case .bim: return command ? .add : (shift ? .remove : .replace)
        case .mac: return command ? .toggle : (shift ? .add : .replace)
        }
    }

    public func apply(_ op: Operation, _ newIDs: [ElementID]) {
        switch op {
        case .replace: select(newIDs)
        case .add: add(newIDs)
        case .remove: remove(newIDs)
        case .toggle: for id in newIDs { toggle(id) }
        }
    }

    /// Applies a click with modifiers (see `ModifierStyle`). A plain click on nothing clears the selection.
    public func click(_ id: ElementID?, shift: Bool, command: Bool) {
        let op = Self.operation(shift: shift, command: command)
        guard let id else { if op == .replace { clear() }; return }
        apply(op, [id])
    }

    /// Sets candidates under the cursor (sorted by priority) and preselects the first. With a model, a wall among the
    /// candidates that is joined end to end with other walls adds its whole chain as the last Tab entry.
    public func setCycleCandidates(_ c: [ElementID], model: BIMModel? = nil) {
        // Pointer moves over the same stack of candidates keep the Tab position; a new stack starts at the top.
        if c != cycleCandidates {
            cycleCandidates = c
            cycleIndex = 0
            cycleChain = []
            if let model, let wall = c.first(where: { model[$0]?.wall != nil }) {
                let chain = Self.wallChain(from: wall, in: model)
                if chain.count > 1 { cycleChain = chain }
            }
        }
        if cycleIndex >= cycleEntryCount { cycleIndex = 0 }
        preselection = c.isEmpty ? nil : c[min(cycleIndex, c.count - 1)]
    }
    private var cycleEntryCount: Int { cycleCandidates.count + (cycleChain.isEmpty ? 0 : 1) }
    /// True when Tab has reached the chain entry: a click selects every wall in `cycleChain`.
    public var isChainPreselected: Bool { !cycleChain.isEmpty && cycleIndex == cycleCandidates.count }
    /// Elements a click would pick (highlighted as preselection).
    public var preselectedIDs: [ElementID] {
        if isChainPreselected { return cycleChain }
        return preselection.map { [$0] } ?? []
    }
    /// Tab: advances preselection to the next overlapping candidate, then to the chain of joined walls.
    public func cycle() {
        guard !cycleCandidates.isEmpty else { return }
        cycleIndex = (cycleIndex + 1) % cycleEntryCount
        preselection = cycleCandidates[min(cycleIndex, cycleCandidates.count - 1)]
    }

    /// Walls connected end to end with `id` (joins allowed at the shared ends), walking through corners and
    /// multi-way end joins. Sorted by id; contains `id` itself.
    public static func wallChain(from id: ElementID, in model: BIMModel) -> [ElementID] {
        guard let start = model[id], start.wall != nil else { return [] }
        let tol = Tolerance.length * 100 // the same 1 mm capture wall end joins use
        var seen: Set<ElementID> = [id]
        var queue = [start]
        while let e = queue.popLast() {
            guard let w = e.wall else { continue }
            let ends = [(w.location.start, w.allowJoinAtStart), (w.location.end, w.allowJoinAtEnd)].filter(\.1).map(\.0)
            guard !ends.isEmpty else { continue }
            for o in WallGeometry.joinCandidates(e, model) where !seen.contains(o.id) {
                guard let ow = o.wall else { continue }
                let joined = ends.contains { p in
                    (ow.allowJoinAtStart && ow.location.start.isAlmostEqual(p, tolerance: tol))
                        || (ow.allowJoinAtEnd && ow.location.end.isAlmostEqual(p, tolerance: tol))
                }
                if joined { seen.insert(o.id); queue.append(o) }
            }
        }
        return seen.sorted()
    }

    func retainExisting(in model: BIMModel) {
        let before = ids.count
        // Deleted elements drop out silently: this is not a new selection, so `previous` is left alone.
        ids.removeAll { model[$0] == nil }
        if let p = preselection, model[p] == nil { preselection = nil }
        if ids.count != before { cycleCandidates.removeAll { model[$0] == nil }; cycleChain.removeAll { model[$0] == nil } }
    }

    /// Categories of the selection with counts (for the selection filter UI and status bar).
    public func categoryCounts(_ model: BIMModel) -> [(Category, Int)] {
        var d: [Category: Int] = [:]
        for id in ids { if let e = model[id] { d[e.category, default: 0] += 1 } }
        return d.sorted { $0.key < $1.key }
    }

    /// Status text: "Walls : Basic Wall : Exterior - Brick on CMU" for one, "3 elements selected" for many.
    public func statusDescription(_ model: BIMModel) -> String {
        guard !ids.isEmpty else { return "" }
        if let id = single, let e = model[id] {
            if let t = model.type(of: e), let td = t.typeData { return "\(e.category.displayName) : \(td.familyName) : \(t.name)" }
            return "\(e.category.displayName)" + (e.name.isEmpty ? "" : " : \(e.name)")
        }
        return "\(ids.count) elements selected"
    }
}
