import Foundation
import ArcusGeometry
import ArcusDomain

/// Elements copied to the clipboard, with a snapshot of the project data they refer to (types, families,
/// materials, levels, phases, line styles…) so they can also be pasted into another open project.
public struct ClipboardPayload: Sendable {
    public var elements: [Element]
    /// Elements the copied ones refer to, keyed by their id in the source project.
    public var context: [ElementID: Element]
    public var sourceViewID: ElementID?
    public var sourceLevelID: ElementID?

    public init(elements: [Element], context: [ElementID: Element] = [:], sourceViewID: ElementID?, sourceLevelID: ElementID?) {
        self.elements = elements; self.context = context; self.sourceViewID = sourceViewID; self.sourceLevelID = sourceLevelID
    }

    /// Copies the selection (plus hosted inserts and the view's tags that travel with it) and its supporting data.
    public static func capture(_ ids: [ElementID], from model: BIMModel, viewID: ElementID?, levelID: ElementID?) -> ClipboardPayload? {
        let all = ElementOperations.dependentsToCarry(Set(ids), model, viewID: viewID)
        let elements = all.sorted().compactMap { model[$0] }.filter { ElementTransform.isTransformable($0) || $0.room != nil }
        guard !elements.isEmpty else { return nil }
        let copied = Set(elements.map(\.id))
        var context: [ElementID: Element] = [:]
        var queue = elements.flatMap { ProjectTransfer.references(of: $0) }
        while let id = queue.popLast() {
            guard !copied.contains(id), context[id] == nil, let e = model[id], ProjectTransfer.isSupporting(e) else { continue }
            context[id] = e
            queue += ProjectTransfer.references(of: e)
        }
        return ClipboardPayload(elements: elements, context: context, sourceViewID: viewID, sourceLevelID: levelID)
    }

    public var sourceLevel: Element? { context[sourceLevelID ?? ElementID(0)] }
}

/// What happened in a paste between projects.
public struct PasteReport: Sendable, Equatable {
    /// Ids of the pasted elements in the destination project.
    public var pasted: [ElementID] = []
    /// Types (as "Family: Type") that already existed in the destination with a different definition; the
    /// destination's definition is used.
    public var duplicateTypes: [String] = []
    /// Types that did not exist in the destination and were added to it.
    public var addedTypes: [String] = []
    /// Elements left out, with the reason.
    public var skipped: [String] = []

    public var summary: String {
        var parts = ["Pasted \(pasted.count) element(s) from another project."]
        if !addedTypes.isEmpty { parts.append("Added \(addedTypes.count) type(s): \(addedTypes.joined(separator: ", ")).") }
        if !duplicateTypes.isEmpty {
            parts.append("\(duplicateTypes.count) type(s) already exist here with different settings; this project's versions are used: \(duplicateTypes.joined(separator: ", ")).")
        }
        if !skipped.isEmpty { parts.append("Not pasted: \(skipped.joined(separator: "; ")).") }
        return parts.joined(separator: " ")
    }
}

/// Pastes clipboard contents copied in another project. Types, families, materials, line styles and fill patterns
/// are matched by name (types by family and type name within their category); those missing from the destination
/// are added. Levels match by name, then by elevation; phases match by name.
public enum ProjectTransfer {
    /// Kinds of element that are carried along as supporting data (never pasted as elements themselves).
    static func isSupporting(_ e: Element) -> Bool {
        switch e.data {
        case .type, .family, .material, .level, .phase, .lineStyle, .fillPattern, .revision, .areaScheme: true
        default: false
        }
    }

    /// Ids an element refers to that a paste into another project must resolve.
    static func references(of e: Element) -> [ElementID] {
        var out = [e.typeID, e.levelID, e.phaseCreated, e.phaseDemolished].compactMap { $0 }
        for v in e.params.values { if case .ref(let r?) = v { out.append(r) } }
        switch e.data {
        case .wall(let w): if let t = w.topLevelID { out.append(t) }
        case .column(let c): if let t = c.topLevelID { out.append(t) }
        case .stair(let s): if let t = s.topLevelID { out.append(t) }
        case .room(let r): out += [r.upperLimitLevelID, r.areaSchemeID].compactMap { $0 }
        case .modelLine(let l): if let s = l.styleID { out.append(s) }
        case .filledRegion(let f): if let s = f.boundaryStyleID { out.append(s) }
        case .revisionCloud(let c): if let r = c.revisionID { out.append(r) }
        case .type(let t):
            if let f = t.familyID { out.append(f) }
            out += t.assembly?.layers.compactMap(\.materialID) ?? []
            for v in t.params.values { if case .ref(let r?) = v { out.append(r) } }
        case .material(let m): out += [m.surfacePatternID, m.cutPatternID].compactMap { $0 }
        default: break
        }
        return out
    }

    /// Kinds that can be pasted into another project.
    static func isTransferable(_ e: Element) -> Bool {
        switch e.data {
        case .wall, .insert, .component, .column, .beam, .slab, .roof, .stair, .railing, .room, .modelLine, .grid, .referencePlane,
             .topography, .dimension, .tag, .textNote, .spot, .filledRegion, .detailComponent, .revisionCloud, .insulation, .group:
            true
        default:
            false
        }
    }

    /// Pastes `payload` (copied in another project) into the project of `tx`, applying `transform`. View-specific
    /// elements go to `targetView` (skipped when nil). Elements whose base level has no match go to `fallbackLevel`.
    /// With `baseLevel`, every element is placed on that level and top constraints follow by elevation difference
    /// (Paste Aligned to Selected Levels).
    @discardableResult
    public static func paste(_ payload: ClipboardPayload, into tx: TransactionContext, transform: Transform2 = .identity,
                             targetView: ElementID?, fallbackLevel: ElementID?, baseLevel: ElementID? = nil) -> PasteReport {
        var r = Resolver(payload: payload, tx: tx)
        var report = PasteReport()
        let byID = Dictionary(uniqueKeysWithValues: payload.elements.map { ($0.id, $0) })
        var skipped: [String: Int] = [:]
        func skip(_ why: String) { skipped[why, default: 0] += 1 }

        // Decide what can come across. Dependents need their host (or tagged element / references) to come too.
        var candidates: [Element] = []
        for e in payload.elements {
            guard isTransferable(e) else { skip("\(e.category.displayName.lowercased()) can't be pasted into another project"); continue }
            if e.ownerViewID != nil && targetView == nil { skip("view-specific elements need an open 2D view"); continue }
            if let t = e.typeID, r.resolve(t) == nil { skip("elements whose type couldn't be matched"); continue }
            candidates.append(e)
        }
        // Iterate until stable: dropping a host drops what it hosts.
        var changed = true
        while changed {
            changed = false
            let ids = Set(candidates.map(\.id))
            candidates = candidates.filter { e in
                let ok: Bool
                if let h = e.hostID { ok = ids.contains(h) }
                else if let t = e.tag?.taggedID { ok = ids.contains(t) }
                else if let d = e.dimension { ok = d.references.allSatisfy { $0.elementID.map(ids.contains) ?? true } }
                else { ok = true }
                if !ok { changed = true; skip("\(e.category.displayName.lowercased()) whose host or references weren't copied") }
                return ok
            }
        }

        // Pass 1: create the elements with supporting references resolved.
        var created: [ElementID: ElementID] = [:]
        for e in candidates.sorted(by: { $0.id < $1.id }) {
            let typeID = e.typeID.flatMap { r.resolve($0) }
            var copy = e
            copy.ifcGUID = .random()
            copy.pinned = false
            copy.groupID = nil
            copy.designOptionID = nil
            copy.params[.mark] = nil
            copy.params = copy.params.compactMapValues { v in
                if case .ref(let id?) = v { return r.resolve(id).map { .ref($0) } }
                return v
            }
            let level: ElementID? = e.levelID.map { baseLevel ?? r.resolveLevel($0) ?? fallbackLevel ?? tx.model.levels.first?.id } ?? nil
            r.remapData(&copy, sourceBaseLevel: e.levelID, targetBaseLevel: baseLevel)
            ElementTransform.apply(transform, to: &copy)
            let phaseCreated = e.phaseCreated.map { r.resolve($0) ?? tx.model.latestPhase?.id } ?? nil
            let phaseDemolished = e.phaseDemolished.flatMap { r.resolve($0) }
            let data = copy.data, params = copy.params, classification = copy.classification
            let newID = tx.create(e.category, name: e.name, data: data, typeID: typeID, levelID: level,
                                  ownerViewID: e.ownerViewID != nil ? targetView : nil) { ne in
                ne.params = params
                ne.classification = classification
                ne.phaseCreated = e.category.isModel ? phaseCreated : nil
                ne.phaseDemolished = phaseDemolished
            }
            created[e.id] = newID
        }

        // Pass 2: references among the pasted elements.
        for (old, new) in created {
            guard let src = byID[old], var e = tx.model[new] else { continue }
            let before = e
            if let h = src.hostID { e.hostID = created[h] }
            switch e.data {
            case .tag(var t): if let n = created[t.taggedID] { t.taggedID = n; e.data = .tag(t) }
            case .dimension(var d):
                d.references = d.references.map { ref in var ref = ref; ref.elementID = ref.elementID.flatMap { created[$0] }; return ref }
                e.data = .dimension(d)
            case .spot(var s): s.referenceID = s.referenceID.flatMap { created[$0] }; e.data = .spot(s)
            case .wall(var w):
                w.attachedTopIDs = (src.wall?.attachedTopIDs ?? []).compactMap { created[$0] }
                w.attachedBaseIDs = (src.wall?.attachedBaseIDs ?? []).compactMap { created[$0] }
                e.data = .wall(w)
            case .group(var g):
                g.members = g.members.compactMap { created[$0] }
                if var spec = g.arraySpec { spec.sourceMembers = spec.sourceMembers.compactMap { created[$0] }; g.arraySpec = spec.sourceMembers.isEmpty ? nil : spec }
                e.data = .group(g)
            default: break
            }
            if e != before { tx.update(new) { $0 = e } }
        }
        for (old, new) in created {
            guard let g = tx.model[new]?.group else { continue }
            if g.members.isEmpty { tx.delete(new); created[old] = nil; continue }
            for m in g.members { tx.update(m) { $0.groupID = new } }
        }
        report.pasted = created.values.sorted()
        report.duplicateTypes = r.duplicateTypes.sorted()
        report.addedTypes = r.addedTypes.sorted()
        report.skipped = skipped.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
        return report
    }

    /// Maps supporting elements of the source project onto the destination project, creating missing ones.
    struct Resolver {
        let payload: ClipboardPayload
        let tx: TransactionContext
        var map: [ElementID: ElementID] = [:]
        var unresolved: Set<ElementID> = []
        var duplicateTypes: Set<String> = []
        var addedTypes: Set<String> = []

        init(payload: ClipboardPayload, tx: TransactionContext) { self.payload = payload; self.tx = tx }

        var model: BIMModel { tx.model }

        mutating func resolve(_ id: ElementID) -> ElementID? {
            if let m = map[id] { return m }
            if unresolved.contains(id) { return nil }
            let result = find(id)
            if let result { map[id] = result } else { unresolved.insert(id) }
            return result
        }

        /// Level by name, then by elevation.
        mutating func resolveLevel(_ id: ElementID) -> ElementID? { resolve(id) }

        private mutating func find(_ id: ElementID) -> ElementID? {
            guard let src = payload.context[id] else { return nil }
            switch src.data {
            case .level(let l):
                return model.level(named: src.name)?.id ?? model.levels.first { abs(($0.level?.elevation ?? .nan) - l.elevation) < 1e-6 }?.id
            case .phase:
                return model.phases.first { $0.name == src.name }?.id
            case .revision:
                return model.elements(src.category).first { $0.name == src.name && $0.revisionData != nil }?.id
            case .areaScheme:
                return model.elements(src.category).first { $0.name == src.name }?.id ?? model.elements(src.category).first?.id
            case .family:
                if let f = model.family(named: src.name) { return f.id }
                return tx.create(src.category, name: src.name, data: src.data)
            case .material(var m):
                if let existing = model.material(named: src.name) { return existing.id }
                m.surfacePatternID = m.surfacePatternID.flatMap { resolve($0) }
                m.cutPatternID = m.cutPatternID.flatMap { resolve($0) }
                return tx.create(src.category, name: src.name, data: .material(m)) { $0.params = src.params.filter { if case .ref = $0.value { false } else { true } } }
            case .lineStyle, .fillPattern:
                if let existing = model.elements(src.category).first(where: { $0.name == src.name && $0.kind == src.kind }) { return existing.id }
                return tx.create(src.category, name: src.name, data: src.data)
            case .type(var td):
                let label = td.familyName.isEmpty ? src.name : "\(td.familyName): \(src.name)"
                if let existing = model.type(category: td.instanceCategory, family: td.familyName, name: src.name) {
                    if let etd = existing.typeData, signature(etd, in: model) != signature(td, in: payload.context) { duplicateTypes.insert(label) }
                    return existing.id
                }
                td.familyID = td.familyID.flatMap { resolve($0) }
                if var a = td.assembly {
                    a.layers = a.layers.map { l in var l = l; l.materialID = l.materialID.flatMap { resolve($0) }; return l }
                    td.assembly = a
                }
                var params: [ParameterID: ParamValue] = [:]
                for (k, v) in td.params {
                    if case .ref(let r?) = v { if let m = resolve(r) { params[k] = .ref(m) } } else { params[k] = v }
                }
                td.params = params
                addedTypes.insert(label)
                return tx.create(src.category, name: src.name, data: .type(td))
            default:
                return nil
            }
        }

        /// A type definition with project-specific ids replaced by the names they point to, for comparing types
        /// between projects.
        func signature(_ td: TypeData, in lookup: (ElementID) -> Element?) -> TypeData {
            var s = td
            s.familyID = nil
            func name(_ id: ElementID?) -> String { id.flatMap(lookup)?.name ?? "" }
            if var a = s.assembly {
                s.params[ParameterID("__layerMaterials")] = .text(a.layers.map { name($0.materialID) }.joined(separator: "|"))
                a.layers = a.layers.map { l in var l = l; l.materialID = nil; return l }
                s.assembly = a
            }
            for (k, v) in s.params { if case .ref(let r) = v { s.params[k] = .text("→" + name(r)) } }
            return s
        }
        func signature(_ td: TypeData, in model: BIMModel) -> TypeData { signature(td) { model[$0] } }
        func signature(_ td: TypeData, in context: [ElementID: Element]) -> TypeData { signature(td) { context[$0] } }

        /// Replaces supporting references inside the element's data with destination ids (or clears them). With a
        /// `targetBaseLevel`, top levels are the destination levels at the same height above it as in the source.
        mutating func remapData(_ e: inout Element, sourceBaseLevel: ElementID?, targetBaseLevel: ElementID? = nil) {
            let baseZ = payload.context[sourceBaseLevel ?? ElementID(0)]?.level?.elevation ?? 0
            func sourceZ(_ id: ElementID) -> Double { payload.context[id]?.level?.elevation ?? baseZ }
            let model = tx.model
            func resolveTop(_ id: ElementID) -> ElementID? {
                guard let tb = targetBaseLevel else { return resolve(id) }
                let want = model.elevation(ofLevel: tb) + sourceZ(id) - baseZ
                return model.levels.first { abs(($0.level?.elevation ?? .nan) - want) < 1e-6 }?.id
            }
            switch e.data {
            case .wall(var w):
                if let top = w.topLevelID {
                    if let t = resolveTop(top) { w.topLevelID = t } else {
                        w.unconnectedHeight = max(0.1, sourceZ(top) + w.topOffset - baseZ - w.baseOffset)
                        w.topLevelID = nil; w.topOffset = 0
                    }
                }
                e.data = .wall(w)
            case .column(var c):
                if let top = c.topLevelID {
                    if let t = resolveTop(top) { c.topLevelID = t } else {
                        c.unconnectedHeight = max(0.1, sourceZ(top) + c.topOffset - baseZ - c.baseOffset)
                        c.topLevelID = nil; c.topOffset = 0
                    }
                }
                e.data = .column(c)
            case .stair(var s):
                if let top = s.topLevelID {
                    if let t = resolveTop(top) { s.topLevelID = t } else {
                        s.unconnectedHeight = max(0.1, sourceZ(top) + s.topOffset - baseZ - s.baseOffset)
                        s.topLevelID = nil; s.topOffset = 0
                    }
                }
                e.data = .stair(s)
            case .room(var rm):
                if let up = rm.upperLimitLevelID {
                    if let t = resolveTop(up) { rm.upperLimitLevelID = t } else {
                        rm.limitOffset += sourceZ(up) - baseZ
                        rm.upperLimitLevelID = nil
                    }
                }
                rm.areaSchemeID = rm.areaSchemeID.flatMap { resolve($0) }
                e.data = .room(rm)
            case .modelLine(var l): l.styleID = l.styleID.flatMap { resolve($0) }; e.data = .modelLine(l)
            case .filledRegion(var f): f.boundaryStyleID = f.boundaryStyleID.flatMap { resolve($0) }; e.data = .filledRegion(f)
            case .revisionCloud(var c): c.revisionID = c.revisionID.flatMap { resolve($0) }; e.data = .revisionCloud(c)
            default: break
            }
        }
    }
}
