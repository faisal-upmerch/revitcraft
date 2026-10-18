import Foundation
import ArcusGeometry

// BL-PROPS: how the Properties palette and Type Properties present parameters — which rows show, in which group and
// order, reference-tool placeholders, and aggregation over a selection. Parameter ids, schedules, tags and IFC property
// sets are unaffected: they keep reading `Parameters.instanceEntries` / `typeEntries`.

/// One palette row: a parameter entry plus whether its value differs across the elements shown.
public struct PropertyRow: Sendable, Hashable, Identifiable {
    public var entry: ParameterEntry
    /// True only when several elements are shown and their values differ (never for a single element).
    public var varies: Bool
    public var id: ParameterID { entry.id }
    public init(entry: ParameterEntry, varies: Bool = false) { self.entry = entry; self.varies = varies }
}

public enum PaletteLayout {
    /// Rows the palette hides although schedules, tags and IFC keep them: Family, Type and Family and Type are carried by
    /// the Type Selector; the element id is shown in the palette footer instead.
    public static let hiddenIDs: Set<ParameterID> = [ParameterID("familyName"), ParameterID("typeName"), ParameterID("familyAndType"), elementIDParameter]
    public static let elementIDParameter = ParameterID("elementID")
    /// Prefix of placeholder rows (parameters the reference tool shows that Arcus does not model). They are read-only.
    public static let placeholderPrefix = "palette."
    public static func isPlaceholder(_ id: ParameterID) -> Bool { id.key.hasPrefix(placeholderPrefix) }
    static let placeholderReason = "Shown for familiarity. Arcus does not model this parameter yet."

    // MARK: Element rows

    /// Palette rows of an existing element: instance entries minus hidden rows, plus placeholders, in reference order.
    public static func entries(_ e: Element, _ model: BIMModel) -> [ParameterEntry] {
        arrange(Parameters.instanceEntries(e, model).filter { !hiddenIDs.contains($0.id) }, for: e)
    }

    /// Rows of an element that doesn't exist yet (the "New <Category>" state of a placement tool): only parameters that
    /// can be set before placement. Calculated parameters are left out and their getters never run, since the
    /// prototype isn't in the model.
    public static func prototypeEntries(_ e: Element, _ model: BIMModel) -> [ParameterEntry] {
        let ctx = ParameterContext(model: model)
        var out: [ParameterEntry] = []
        for b in BuiltInCatalog.instance(for: e) where !b.isReadOnly && !hiddenIDs.contains(b.id) {
            let reason = b.lockedReason?(e, ctx)
            out.append(ParameterEntry(id: b.id, name: b.name, type: b.type, group: b.group, isType: false, isReadOnly: reason != nil,
                                      value: reason == nil ? b.getter(e, ctx) : nil, formula: nil, tooltip: b.tooltip, readOnlyReason: reason))
        }
        if let fam = Parameters.familyDefinition(for: e, model) {
            for p in fam.parameters where p.isInstance && p.formula == nil {
                let id = Parameters.familyParamID(p.name)
                out.append(ParameterEntry(id: id, name: p.name, type: p.type, group: p.group, isType: false, isReadOnly: false,
                                          value: e.params[id] ?? Parameters.defaultFamilyValue(p, e, model), formula: nil, tooltip: "", readOnlyReason: nil))
            }
        }
        for d in model.projectParameters where d.isInstance && d.formula == nil && d.categories.contains(e.category) {
            out.append(ParameterEntry(id: d.id, name: d.name, type: d.type, group: d.group, isType: false, isReadOnly: false,
                                      value: e.params[d.id] ?? d.defaultValue, formula: nil, tooltip: d.tooltip, readOnlyReason: nil))
        }
        return arrange(out.sorted { ($0.group, $0.orderKey) < ($1.group, $1.orderKey) }, for: e)
    }

    // MARK: Aggregation

    /// Rows for the elements shown in the palette. One element: its own values (never "varies"). Several: the
    /// parameters every element has (by id — the "Common (n)" set when categories differ), marked "varies" where the
    /// values differ; a row read-only on any element is read-only for all. When names differ between categories the
    /// generic name is used (walls call "level" Base Constraint; the common row says Level).
    public static func aggregate(_ elements: [Element], _ model: BIMModel, prototype: Bool = false) -> [PropertyRow] {
        guard let first = elements.first else { return [] }
        let rowsOf: (Element) -> [ParameterEntry] = { prototype ? prototypeEntries($0, model) : entries($0, model) }
        var rows = rowsOf(first).map { PropertyRow(entry: $0) }
        guard elements.count > 1 else { return rows }
        for other in elements.dropFirst() {
            let theirs = Dictionary(rowsOf(other).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            rows = rows.compactMap { row in
                guard let o = theirs[row.id], o.type == row.entry.type else { return nil }
                var row = row
                if o.value != row.entry.value { row.varies = true }
                if o.isReadOnly && !row.entry.isReadOnly { row.entry.isReadOnly = true; row.entry.readOnlyReason = o.readOnlyReason }
                if o.name != row.entry.name { row.entry.name = BuiltInCatalog.byID[row.id]?.name ?? row.entry.name }
                return row
            }
        }
        return rows
    }

    /// Rows grouped in palette order (groups by `ParameterGroup` order; rows keep their order within a group).
    public static func grouped(_ rows: [PropertyRow]) -> [(ParameterGroup, [PropertyRow])] {
        var order: [ParameterGroup] = []
        var byGroup: [ParameterGroup: [PropertyRow]] = [:]
        for r in rows {
            if byGroup[r.entry.group] == nil { order.append(r.entry.group) }
            byGroup[r.entry.group, default: []].append(r)
        }
        return order.sorted().map { ($0, byGroup[$0]!) }
    }

    // MARK: Type rows

    /// Type Properties rows: type entries grouped in reference order, Identity Data ordered as BIM users expect.
    public static func typeEntries(_ type: Element, _ model: BIMModel) -> [ParameterEntry] {
        stableSorted(Parameters.typeEntries(type, model)) { e in
            e.group == .identity ? typeIdentityOrder.firstIndex(of: e.id.key) ?? typeIdentityOrder.count : 0
        }
    }
    static let typeIdentityOrder = ["type.keynote", "type.model", "type.manufacturer", "type.comments", "type.url", "type.description",
                                    "type.assemblyCode", "type.mark", "type.fireRating", "type.cost"]

    /// The "Family" row of Type Properties: "System Family: Basic Wall" for system families, else the family name.
    public static func familyLabel(_ type: Element) -> String {
        guard let td = type.typeData else { return "" }
        if td.familyID == nil, let s = td.systemFamily { return "System Family: \(s.rawValue)" }
        if td.familyID == nil && td.curtain != nil { return "System Family: Curtain Wall" }
        return td.familyName.isEmpty ? td.instanceCategory.singularName : td.familyName
    }

    // MARK: Arrangement

    /// A placeholder row definition: inserted after `anchor` (or at the end of its group when the anchor is absent).
    struct Placeholder: Sendable {
        let key: String, name: String, type: ParamType, group: ParameterGroup, anchor: String?
        let value: @Sendable (Element) -> ParamValue
    }

    static let image = Placeholder(key: "palette.image", name: "Image", type: .text, group: .identity, anchor: nil) { _ in .text("") }

    static func placeholders(for e: Element) -> [Placeholder] {
        var out: [Placeholder] = []
        switch e.data {
        case .wall(let w) where w.curtain == nil:
            out = [
                Placeholder(key: "palette.wall.baseExtension", name: "Base Extension Distance", type: .length, group: .constraints, anchor: "wall.baseAttached") { _ in .double(0) },
                Placeholder(key: "palette.wall.topExtension", name: "Top Extension Distance", type: .length, group: .constraints, anchor: "wall.topAttached") { _ in .double(0) },
                Placeholder(key: "palette.relatedToMass", name: "Related to Mass", type: .bool, group: .constraints, anchor: "wall.roomBounding") { _ in .bool(false) },
                Placeholder(key: "palette.wall.crossSection", name: "Cross-Section", type: .choice(["Vertical", "Slanted", "Tapered"]), group: .crossSection, anchor: nil) { e in
                    .text(abs(e.wall?.slantAngle ?? 0) > Tolerance.angle ? "Slanted" : "Vertical")
                },
                Placeholder(key: "palette.structuralUsage", name: "Structural Usage", type: .text, group: .structural, anchor: "wall.structural") { e in
                    .text(e.wall?.structural == true ? "Bearing" : "Non-bearing")
                },
            ]
        case .slab where e.category == .floors:
            out = [Placeholder(key: "palette.relatedToMass", name: "Related to Mass", type: .bool, group: .constraints, anchor: "slab.roomBounding") { _ in .bool(false) }]
        case .insert where e.category == .doors:
            out = [Placeholder(key: "palette.door.frameType", name: "Frame Type", type: .text, group: .construction, anchor: nil) { _ in .text("") }]
        default: break
        }
        if e.category.isModel, !e.isType, BuiltInCatalog.instance(for: e).contains(where: { $0.id == BuiltInCatalog.comments.id }) { out.append(image) }
        return out
    }

    /// Adds placeholders and orders rows: groups in palette order, anchors respected, Identity Data led by Image,
    /// Comments, Mark.
    static func arrange(_ entries: [ParameterEntry], for e: Element) -> [ParameterEntry] {
        var list = entries
        for p in placeholders(for: e) {
            let row = ParameterEntry(id: ParameterID(p.key), name: p.name, type: p.type, group: p.group, isType: false, isReadOnly: true,
                                     value: p.value(e), formula: nil, tooltip: "", readOnlyReason: placeholderReason)
            if let a = p.anchor, let i = list.firstIndex(where: { $0.id.key == a }) {
                list.insert(row, at: i + 1)
            } else if p.group == .crossSection, let i = list.firstIndex(where: { $0.group == .crossSection }) {
                list.insert(row, at: i) // Cross-Section leads its group
            } else {
                list.append(row)
            }
        }
        return stableSorted(list) { e in e.group == .identity ? identityOrder.firstIndex(of: e.id.key) ?? identityOrder.count : 0 }
    }
    static let identityOrder = ["palette.image", "comments", "mark"]

    /// Sorts by group then `rank`, keeping the incoming order among equals.
    static func stableSorted(_ list: [ParameterEntry], rank: (ParameterEntry) -> Int) -> [ParameterEntry] {
        list.enumerated().sorted { a, b in
            (a.element.group, rank(a.element), a.offset) < (b.element.group, rank(b.element), b.offset)
        }.map(\.element)
    }
}

// MARK: - Wall Base Constraint

extension BuiltInCatalog {
    /// BL-PROPS: the wall's base level, named as BIM users know it. Same id ("level") and behaviour as `levelParam`, so
    /// schedules, persistence and filters are unchanged; `byID` keeps the generic "Level" definition.
    static let wallBaseConstraint = P("level", "Base Constraint", .elementRef(.levels), .constraints,
                                      tooltip: "Level the base of the wall is placed on.",
                                      get: { e, _ in .ref(e.levelID) },
                                      set: { e, v, ctx in
                                          guard let id = v.refValue else { throw ParameterError("A level is required.") }
                                          guard ctx.model[id]?.level != nil else { throw ParameterError("The chosen element is not a level.") }
                                          e.levelID = id
                                      })
}

// MARK: - Structure editor rows

extension CompoundAssembly {
    /// BL-PROPS: a row of the structure editor — a layer or one of the two core boundaries (layers above the first
    /// boundary and below the second lie outside the core).
    public enum StructureRow: Hashable, Sendable {
        case layer(Int), coreTop, coreBottom
    }

    /// Layers from exterior (top) to interior with the core boundaries in place.
    public var structureRows: [StructureRow] {
        var rows: [StructureRow] = []
        let core = safeCore
        for i in 0...layers.count {
            if i == core.lowerBound { rows.append(.coreTop) }
            if i == core.upperBound { rows.append(.coreBottom) }
            if i < layers.count { rows.append(.layer(i)) }
        }
        return rows
    }

    /// The assembly with its layers and core boundaries in the order of `rows` (a permutation of `structureRows`, e.g.
    /// after a boundary row was dragged). Boundaries dragged past each other swap roles.
    public func reordered(_ rows: [StructureRow]) -> CompoundAssembly {
        var a = self
        a.layers = []
        var marks: [Int] = []
        for r in rows {
            switch r {
            case .layer(let i) where layers.indices.contains(i): a.layers.append(layers[i])
            case .coreTop, .coreBottom: marks.append(a.layers.count)
            default: break
            }
        }
        a.coreStart = marks.min() ?? 0
        a.coreEnd = marks.max() ?? a.layers.count
        return a
    }

    /// Moves rows as a list's drag-to-reorder does (`source` indices to before `destination`).
    public func moving(rows source: IndexSet, to destination: Int) -> CompoundAssembly {
        var rows = structureRows
        let moving = source.sorted().map { rows[$0] }
        let before = source.filter { $0 < destination }.count
        for i in source.sorted(by: >) { rows.remove(at: i) }
        rows.insert(contentsOf: moving, at: max(0, min(rows.count, destination - before)))
        return reordered(rows)
    }
}
