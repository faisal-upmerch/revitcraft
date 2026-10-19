import Foundation
import ArcusGeometry
import ArcusCalc

// FM3: Family Types in a Furniture document. Values come from the current type (formulas through `FormulaSystem`, as
// in families); the planes are placed by the same constraint solver the Family Editor uses, so labelled dimensions,
// EQ and locks behave as they do there.

/// Parameters, types and plane solving for Furniture documents.
public enum FurnitureParameters {
    /// The document as a family without geometry: the setup's parameters and types, one reference plane per furniture
    /// plane (offset: its formula, else its current position) and the labelled, EQ and locked dimensions between them.
    /// `planeIDs` maps the family's plane names back to elements.
    public static func frame(_ m: BIMModel, setup: FurnitureSetupData? = nil) -> (family: FamilyDefinition, planeIDs: [String: ElementID])? {
        guard let setup = setup ?? m.furnitureSetup else { return nil }
        var f = setup.family
        f.referencePlanes = []
        f.dimensions = []
        let names = FurniturePlanes.names(m)
        var ids: [String: ElementID] = [:]
        for p in FurniturePlanes.all(m) {
            guard let rp = p.referencePlane, let fp = rp.furniture, let name = names[p.id] else { continue }
            let formula = fp.offsetFormula?.trimmingCharacters(in: .whitespaces)
            let offset = (formula?.isEmpty == false ? formula : nil) ?? String(FurniturePlanes.position(rp) ?? 0)
            f.referencePlanes.append(FamilyReferencePlane(name: name, axis: fp.axis, offset: offset, strength: fp.strength, definesOrigin: fp.definesOrigin))
            ids[name] = p.id
        }
        f.dimensions = dimensions(m, names: names)
        return (f, ids)
    }

    /// The document's linear and aligned dimensions between furniture planes, as family dimensions (duplicates dropped:
    /// the same Width label in plan and in an elevation is one constraint).
    static func dimensions(_ m: BIMModel, names: [ElementID: String]) -> [FamilyDimension] {
        var out: [FamilyDimension] = []
        var seen: Set<String> = []
        func add(_ d: FamilyDimension, key: String) { if seen.insert(key).inserted { out.append(d) } }
        for e in m.elements(.dimensions).sorted(by: { $0.id < $1.id }) {
            guard let d = e.dimension, d.kind == .linear || d.kind == .aligned else { continue }
            let planes = d.references.compactMap { r in r.elementID.flatMap { names[$0] } }
            guard planes.count == d.references.count, planes.count >= 2 else { continue }
            if d.equality, planes.count >= 3 {
                for i in 1..<(planes.count - 1) {
                    let trio = [planes[i - 1], planes[i], planes[i + 1]]
                    add(.equality(trio[0], trio[1], trio[2]), key: "eq|" + (trio[0] < trio[2] ? trio : trio.reversed()).joined(separator: "|"))
                }
            } else if planes.count == 2, let label = d.labelParameter {
                add(FamilyDimension(planeA: planes[0], planeB: planes[1], labelParameter: label), key: "label|\(label)|" + planes.sorted().joined(separator: "|"))
            } else if planes.count == 2, d.locked {
                var fd = FamilyDimension(planeA: planes[0], planeB: planes[1])
                fd.isLocked = true
                add(fd, key: "lock|" + planes.sorted().joined(separator: "|"))
            }
        }
        return out
    }

    /// Solved plane positions (by element), parameter values and problems for the current type.
    public struct Solution: Sendable {
        public var planes: [ElementID: Double]
        public var values: [String: FormulaValue]
        public var errors: [String]
        public var conflicts: Set<String>
    }

    /// Solves the planes for the current type (or `typeName`) of `setup` (default: the document's).
    public static func solve(_ m: BIMModel, setup: FurnitureSetupData? = nil, typeName: String? = nil) -> Solution? {
        guard let s = setup ?? m.furnitureSetup, let (family, ids) = frame(m, setup: s) else { return nil }
        let ev = FamilyEvaluator.evaluate(family, typeName: typeName ?? s.currentType, units: m.units)
        var planes: [ElementID: Double] = [:]
        for (name, id) in ids { if let v = ev.planes[name] { planes[id] = v } }
        return Solution(planes: planes, values: ev.values, errors: ev.errors, conflicts: ev.conflictingDimensions)
    }

    // MARK: Values

    /// A parameter's stored value in the current type (nil for formula parameters and unknown names).
    public static func storedValue(_ name: String, _ m: BIMModel) -> ParamValue? {
        guard let s = m.furnitureSetup else { return nil }
        return s.family.type(named: s.currentType)?.values[name]
    }

    /// A parameter's evaluated value in the current type (formulas included).
    public static func value(_ name: String, _ m: BIMModel) -> FormulaValue? {
        guard let s = m.furnitureSetup else { return nil }
        return FamilyEvaluator.parameterValues(s.family, typeName: s.currentType, units: m.units).values[name]
    }

    /// Edits the document's setup in a transaction (regeneration then moves the planes).
    public static func edit(_ tx: TransactionContext, _ mutate: (inout FurnitureSetupData) -> Void) throws(TransactionError) {
        guard let info = tx.model.projectInfoElement, var setup = info.projectInfo?.furniture, tx.model.isFurniture else {
            throw TransactionError("This is not a Furniture document.")
        }
        mutate(&setup)
        tx.update(info.id) { $0.projectInfo?.furniture = setup }
    }

    /// Sets a parameter's value in the current type. Formula parameters can't be set.
    public static func setValue(_ name: String, _ value: ParamValue, in tx: TransactionContext) throws(TransactionError) {
        guard let s = tx.model.furnitureSetup, let p = s.family.parameter(named: name) else {
            throw TransactionError("There is no parameter named “\(name)”.")
        }
        if let f = p.formula, !f.trimmingCharacters(in: .whitespaces).isEmpty {
            throw TransactionError("“\(name)” is driven by a formula.", resolution: "Change the formula in Family Types.")
        }
        if p.type == .length, let v = value.doubleValue, v <= Tolerance.length {
            throw TransactionError("“\(name)” must be greater than zero.")
        }
        try edit(tx) { setup in
            guard let i = setup.family.types.firstIndex(where: { $0.name == setup.currentType }) else { return }
            setup.family.types[i].values[name] = value
        }
    }

    /// Makes `typeName` the type that drives the planes.
    public static func setCurrentType(_ typeName: String, in tx: TransactionContext) throws(TransactionError) {
        guard tx.model.furnitureSetup?.family.type(named: typeName) != nil else { throw TransactionError("There is no type named “\(typeName)”.") }
        try edit(tx) { $0.currentType = typeName }
    }

    /// Renames a parameter and everything that names it: type values, formulas (parameters and plane offsets) and
    /// dimension labels. False when the new name is invalid or taken.
    @discardableResult
    public static func renameParameter(_ old: String, to new: String, in tx: TransactionContext) throws(TransactionError) -> Bool {
        guard var setup = tx.model.furnitureSetup else { return false }
        let n = new.trimmingCharacters(in: .whitespaces)
        let known = setup.family.parameters.map(\.name)
        guard FamilyEditing.renameParameter(&setup.family, old, to: n) else { return false }
        try edit(tx) { $0 = setup }
        for p in FurniturePlanes.all(tx.model) {
            guard let f = p.referencePlane?.furniture?.offsetFormula else { continue }
            let g = FamilyEditing.replacingName(in: f, old, with: n, known: known)
            if g != f { tx.update(p.id) { $0.referencePlane?.furniture?.offsetFormula = g } }
        }
        for d in tx.model.elements(.dimensions) where d.dimension?.labelParameter == old {
            tx.update(d.id) { $0.dimension?.labelParameter = n }
        }
        return true
    }

    /// Deletes a parameter; dimensions labelled with it lose their label (plane formulas keep the name and are
    /// reported by Flex).
    public static func deleteParameter(_ name: String, in tx: TransactionContext) throws(TransactionError) {
        guard var setup = tx.model.furnitureSetup, let p = setup.family.parameter(named: name) else { return }
        if p.isBuiltIn { throw TransactionError("“\(name)” is a built-in parameter and can't be deleted.") }
        FamilyEditing.deleteParameter(&setup.family, name)
        try edit(tx) { $0 = setup }
        for d in tx.model.elements(.dimensions) where d.dimension?.labelParameter == name {
            tx.update(d.id) { $0.dimension?.labelParameter = nil }
        }
    }

    /// Labels a dimension between two furniture planes with a length parameter (nil removes the label).
    public static func label(_ dimensionID: ElementID, with name: String?, in tx: TransactionContext) throws(TransactionError) {
        guard let d = tx.model[dimensionID]?.dimension else { throw TransactionError("Select a dimension.") }
        if let name {
            guard let p = tx.model.furnitureSetup?.family.parameter(named: name), p.type == .length else {
                throw TransactionError("Label dimensions with a length parameter.")
            }
            let names = FurniturePlanes.names(tx.model)
            guard d.references.count == 2, d.references.allSatisfy({ $0.elementID.flatMap { names[$0] } != nil }) else {
                throw TransactionError("Only a dimension between two reference planes can be labelled.")
            }
        }
        tx.update(dimensionID) { $0.dimension?.labelParameter = name; if name != nil { $0.dimension?.locked = false; $0.dimension?.equality = false } }
    }

    // MARK: Flex

    /// Flex: every type, and each length parameter at 50% and 150%, as the Family Editor's Flex Test (problems found).
    public static func flex(_ m: BIMModel) -> [String] {
        guard let (family, _) = frame(m) else { return ["This is not a Furniture document."] }
        var problems = FamilyEvaluator.flexTest(family, units: m.units)
        // Planes that a flexed type would push through their neighbours (Left past Right…).
        for t in family.types {
            let ev = FamilyEvaluator.evaluate(family, typeName: t.name, units: m.units)
            for (a, b) in [("Left", "Right"), ("Front", "Back"), ("Bottom", "Top")] {
                if let pa = ev.planes[a], let pb = ev.planes[b], pb - pa <= Tolerance.length {
                    problems.append("Type “\(t.name)”: \(b) is not beyond \(a).")
                }
            }
        }
        return problems
    }
}
