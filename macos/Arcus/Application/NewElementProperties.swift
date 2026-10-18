import Foundation
import ArcusGeometry
import ArcusDomain

// BL-PROPS: the Properties palette's "New <Category>" state — the instance parameters of the element a placement tool
// is about to create, editable before placement and honoured by the placed element.

/// Instance values chosen in the Properties palette before placement. While set on the session, every element of
/// `categories` created by a transaction receives them (inside that transaction, so one undo step removes both).
public struct CreationDefaults: Sendable, Hashable {
    public struct Value: Sendable, Hashable {
        public var id: ParameterID
        public var value: ParamValue
    }
    public var categories: Set<Category>
    /// In the order they were set (a later value may depend on an earlier one, e.g. Top Offset after Top Constraint).
    public private(set) var values: [Value] = []

    public init(categories: Set<Category>, values: [Value] = []) { self.categories = categories; self.values = values }

    public var isEmpty: Bool { values.isEmpty }
    public subscript(id: ParameterID) -> ParamValue? { values.first { $0.id == id }?.value }

    public mutating func set(_ id: ParameterID, _ value: ParamValue) {
        if let i = values.firstIndex(where: { $0.id == id }) { values[i].value = value } else { values.append(Value(id: id, value: value)) }
    }
    public mutating func remove(_ id: ParameterID) { values.removeAll { $0.id == id } }

    /// Applies the values to the elements of `categories` created in `tx` (absent from `before`). A value that doesn't
    /// apply to a particular element (locked, out of range for it) is skipped rather than failing the placement.
    public func apply(in tx: TransactionContext, createdSince before: BIMModel) {
        guard !values.isEmpty else { return }
        for id in tx.driven.sorted() where before[id] == nil {
            guard let e = tx.model[id], !e.isType, categories.contains(e.category) else { continue }
            for v in values { try? Parameters.set(v.id, to: v.value, on: id, in: tx) }
        }
    }
}

/// Builds the pending element a placement tool will create and routes palette edits of it.
@MainActor
public enum NewElementProperties {
    /// The element about to be created (not in the session's model) and a scratch model containing it, against which its
    /// parameter getters run. Tool state (wall height and location line, door sill) and `defaults` are applied.
    public static func prototype(category: Category, typeID: ElementID?, tool: (any InteractiveTool)?, levelID: ElementID?,
                                 model: BIMModel, defaults: CreationDefaults?) -> (element: Element, model: BIMModel)? {
        guard let data = prototypeData(category: category, typeID: typeID, tool: tool, model: model) else { return nil }
        let tx = TransactionContext(model: model, name: "Prototype")
        let id = tx.create(category, data: data, typeID: typeID, levelID: levelID)
        for v in defaults?.values ?? [] { try? Parameters.set(v.id, to: v.value, on: id, in: tx) }
        guard let e = tx.model[id] else { return nil }
        return (e, tx.model)
    }

    /// Palette rows of the pending element.
    public static func rows(category: Category, typeID: ElementID?, tool: (any InteractiveTool)?, levelID: ElementID?,
                            model: BIMModel, defaults: CreationDefaults?) -> [PropertyRow] {
        guard let p = prototype(category: category, typeID: typeID, tool: tool, levelID: levelID, model: model, defaults: defaults) else { return [] }
        var rows = PaletteLayout.aggregate([p.element], p.model, prototype: true)
        if tool is InsertTool, let i = rows.firstIndex(where: { $0.id == ParameterID("level") }) {
            rows[i].entry.isReadOnly = true
            rows[i].entry.readOnlyReason = "Doors and windows take the level of the wall they are placed in."
        }
        return rows
    }

    /// Applies a palette edit to the pending element. Parameters the tool owns (wall height, top constraint, location
    /// line and base offset; door and window sill/head height) go to the tool so its Options Bar stays in step; the
    /// rest become creation defaults. Throws when the value is invalid for the element.
    public static func set(_ id: ParameterID, value: ParamValue, category: Category, typeID: ElementID?, tool: (any InteractiveTool)?,
                           levelID: ElementID?, model: BIMModel, defaults: inout CreationDefaults) throws(ParameterError) {
        guard let data = prototypeData(category: category, typeID: typeID, tool: tool, model: model) else { throw ParameterError("Nothing to place.") }
        let tx = TransactionContext(model: model, name: "Prototype")
        let pid = tx.create(category, data: data, typeID: typeID, levelID: levelID)
        for v in defaults.values where v.id != id { try? Parameters.set(v.id, to: v.value, on: pid, in: tx) }
        try Parameters.set(id, to: value, on: pid, in: tx)
        guard let e = tx.model[pid] else { return }
        if let w = tool as? WallTool, w.extent == .height, let wd = e.wall, wallToolOwned.contains(id) {
            w.locationLine = wd.locationLine
            w.baseOffset = wd.baseOffset
            w.topLevelID = wd.topLevelID
            w.unconnectedHeight = wd.unconnectedHeight
            defaults.remove(id)
            if id == ParameterID("wall.topConstraint"), wd.topLevelID != nil { defaults.remove(ParameterID("wall.unconnectedHeight")) }
            return
        }
        if let t = tool as? InsertTool, let d = e.insert, insertToolOwned.contains(id) {
            t.sillHeight = d.sillHeight
            for k in insertToolOwned { defaults.remove(k) }
            return
        }
        defaults.set(id, value)
    }

    static let wallToolOwned: Set<ParameterID> = [ParameterID("wall.locationLine"), ParameterID("wall.baseOffset"),
                                                  ParameterID("wall.topConstraint"), ParameterID("wall.unconnectedHeight")]
    static let insertToolOwned: Set<ParameterID> = [ParameterID("insert.sillHeight"), ParameterID("insert.headHeight")]

    /// Element data of the pending element, or nil for categories without a placement prototype.
    static func prototypeData(category: Category, typeID: ElementID?, tool: (any InteractiveTool)?, model: BIMModel) -> ElementData? {
        let unit = Segment2(.zero, Vec2(1, 0))
        switch category {
        case .walls:
            var w = WallData(location: .line(unit))
            if let t = tool as? WallTool {
                w.locationLine = t.locationLine
                w.baseOffset = t.baseOffset
                w.unconnectedHeight = t.unconnectedHeight
                w.topLevelID = t.extent == .height ? t.topLevelID : nil
            }
            if model[typeID]?.typeData?.curtain != nil { w.curtain = CurtainInstanceData() }
            return .wall(w)
        case .doors, .windows:
            var sill = (tool as? InsertTool)?.sillHeight ?? 0
            if !(tool is InsertTool), category == .windows,
               let v = model[typeID]?.typeData?.params[Parameters.familyParamID("Default Sill Height")]?.doubleValue { sill = v }
            return .insert(InsertData(location: .zero, sillHeight: sill))
        case .columns, .structuralColumns: return .column(ColumnData(location: .zero))
        case .structuralFraming: return .beam(BeamData(curve: .line(unit)))
        case .floors, .ceilings, .buildingPads: return .slab(SlabData(boundary: Sketch(loops: [])))
        case .roofs: return .roof(RoofData(footprint: Sketch(loops: []), edgeSlopes: []))
        case .stairs: return .stair(StairData(origin: .zero, direction: 0))
        case .railings: return .railing(RailingData(path: []))
        case .ramps: return .ramp(RampData(path: []))
        default:
            return category.isComponentCategory ? .component(ComponentData(location: .zero)) : nil
        }
    }
}
