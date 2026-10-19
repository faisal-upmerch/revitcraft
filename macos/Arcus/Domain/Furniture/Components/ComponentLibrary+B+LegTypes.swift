import Foundation
import ArcusGeometry

// COMPB: legs, feet and bases from the Component Library in the Leg tool's Type Selector (the Leg Type role). A
// component leg type is an ordinary Leg type (TypeData in Furniture Legs, Type Selector group = the component's name)
// that names its component definition and type; the leg is drawn by nesting that family, foot on the floor and top
// under the part, with its Height bound to the leg's height (Revit-style: a loaded leg family in a system-family-like
// part). Its Width and Depth (for joints, cut lists and At Corners insets) are the component's footprint.

public enum ComponentLegTypes {
    /// Type parameters of a component leg type: the definition id and its type's name.
    public static let componentParam = ParameterID("furniture.legComponent")
    public static let componentTypeParam = ParameterID("furniture.legComponentType")

    /// Definitions the Leg tool offers (the Leg Type role), browser order.
    public static var definitions: [ComponentDefinition] { ComponentCatalog.current.all.filter { $0.roles.contains(.legType) } }

    /// The component and type a leg type uses, or nil for the built-in shapes.
    public static func component(_ tv: FurniturePartTypes.Values) -> (ComponentDefinition, String)? {
        guard let id = tv.td?.params[componentParam]?.textValue, let d = ComponentCatalog.current.definition(id: id) else { return nil }
        let t = tv.td?.params[componentTypeParam]?.textValue.flatMap { d.type(named: $0)?.name } ?? d.defaultType?.name
        return t.map { (d, $0) }
    }

    /// The local family a component leg draws: the component nested with its top at Height (it hangs below its
    /// origin in the plan frame), Height and its leg material bound to the leg's.
    public static func family(_ tv: FurniturePartTypes.Values, height: Double) -> FamilyDefinition? {
        guard let (d, typeName) = component(tv) else { return nil }
        var f = FamilyDefinition(name: "Component Leg \(d.id) \(typeName)", template: .furniture)
        f.parameters = [FamilyParameter(name: "Height", type: .length), FamilyParameter(name: "Material", type: .elementRef(.materials), group: .materials)]
        var values: [String: ParamValue] = ["Height": .double(height)]
        if let mat = tv.material { values["Material"] = .ref(mat) }
        f.types = [FamilyTypeDefinition(name: "Leg", values: values)]
        f.nestedFamilies = [d.family]
        var inst = NestedFamilyInstance(familyName: d.family.name, typeName: typeName, z: .expr("Height"))
        inst.id = "component-leg"
        // The component's height parameter (group B writes "Height"; others may write "Leg Height").
        if let h = ["Height", "Leg Height", "Overall Height"].first(where: { d.family.parameter(named: $0) != nil }) { inst.bindings[h] = "Height" }
        if tv.material != nil, d.family.parameter(named: ComponentLibrary.legMaterial) != nil { inst.bindings[ComponentLibrary.legMaterial] = "Material" }
        f.nestedInstances = [inst]
        return f
    }

    /// The turn (a multiple of 90°) that points a component leg's outside corner (its local −X, −Y: splays, inside
    /// tapers, bracket feet) away from the middle of the piece; nil for the built-in shapes.
    public static func outwardTurn(_ tv: FurniturePartTypes.Values, at p: Vec2, _ m: BIMModel) -> Double? {
        guard component(tv) != nil else { return nil }
        let c = ComponentPlacement.pieceCenter(m)
        let right = p.x > c.x + 1e-6, back = p.y > c.y + 1e-6
        switch (right, back) {
        case (false, false): return 0
        case (true, false): return .pi / 2
        case (true, true): return .pi
        case (false, true): return 3 * .pi / 2
        }
    }

    /// The footprint (width along X, depth along Y) of a component's type, from its solids at Fine.
    static func footprint(_ d: ComponentDefinition, _ typeName: String) -> (Double, Double) {
        let ev = FamilyEvaluator.evaluate(d.family, typeName: typeName)
        var lo = Vec2(.infinity, .infinity), hi = Vec2(-.infinity, -.infinity)
        for s in ev.solids where !s.isVoid && s.visibleAt.contains(.fine) {
            let b = s.bounds
            lo = Vec2(min(lo.x, b.min.x), min(lo.y, b.min.y)); hi = Vec2(max(hi.x, b.max.x), max(hi.y, b.max.y))
        }
        guard lo.x.isFinite, hi.x > lo.x else { return (0.0381, 0.0381) }
        return (hi.x - lo.x, hi.y - lo.y)
    }

    /// The Leg type for a component's type, made (with its material) when missing; its id.
    @discardableResult
    public static func ensureType(_ d: ComponentDefinition, typeName: String, in tx: TransactionContext) -> ElementID? {
        guard d.roles.contains(.legType), d.type(named: typeName) != nil else { return nil }
        if let t = type(d, typeName, tx.model) { return t }
        let (w, dp) = footprint(d, typeName)
        let mat = d.materials.first { $0.name == ComponentLibrary.legMaterial }?.finish ?? d.materials.first?.finish
        var params: [ParameterID: ParamValue] = [
            FurniturePartTypes.legShape: .text(LegShape.round.rawValue), FurniturePartTypes.width: .double(w), FurniturePartTypes.depth: .double(dp),
            componentParam: .text(d.id), componentTypeParam: .text(typeName),
        ]
        if let mat { params[FurniturePartTypes.coreMaterial] = .ref(ComponentDocument.material(mat, in: tx)) }
        if let t = d.type(named: typeName) {
            params[ParameterID("type.cost")] = .double(t.cost)
            params[ParameterID("type.manufacturer")] = .text(t.manufacturer)
            params[ParameterID("type.model")] = .text(t.model)
            params[ComponentKit.skuParam] = .text(t.sku)
            params[ParameterID("type.description")] = .text(t.description)
        }
        return tx.create(.elementTypes, name: typeName, data: .type(TypeData(instanceCategory: .furnitureLegs, familyName: d.name, params: params)))
    }

    /// Loads a component as Leg types (Insert ▸ Load Family for a leg): every type, or the named ones.
    @discardableResult
    public static func load(_ d: ComponentDefinition, typeNames: [String]? = nil, in tx: TransactionContext) -> [ElementID] {
        (typeNames ?? d.types.map(\.name)).compactMap { ensureType(d, typeName: $0, in: tx) }
    }

    /// The Leg type of a component's type in the document.
    public static func type(_ d: ComponentDefinition, _ typeName: String, _ m: BIMModel) -> ElementID? {
        m.types(for: .furnitureLegs).first {
            $0.typeData?.params[componentParam]?.textValue == d.id && $0.typeData?.params[componentTypeParam]?.textValue == typeName
        }?.id
    }

    /// The Leg tool's starting set: each Leg Type component's default type (called with the standard part types).
    static func ensureStandard(in tx: TransactionContext) {
        guard tx.model.isFurniture else { return }
        for d in definitions { if let t = d.defaultType { ensureType(d, typeName: t.name, in: tx) } }
    }
}
