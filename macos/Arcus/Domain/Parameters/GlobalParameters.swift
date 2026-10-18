import Foundation
import ArcusCalc

// F11: Manage ▸ Global Parameters (RevitCraft rc-core constraints.rs `apply_globals`, model.rs `GlobalParameter`).

/// An element parameter driven by a global parameter. `dimension.value` on a dimension is its label: the global's
/// value drives the distance between the dimension's two references.
public struct GlobalParameterAssociation: Hashable, Codable, Sendable {
    public var elementID: ElementID
    public var parameterID: ParameterID
    public init(elementID: ElementID, parameterID: ParameterID) { self.elementID = elementID; self.parameterID = parameterID }
}

/// A project-wide value that can drive element parameters and label dimensions. Its value is typed, or computed from
/// other global parameters by a formula.
public struct GlobalParameter: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var type: ParamType
    public var group: ParameterGroup
    public var value: ParamValue
    /// When set, the value is computed from other global parameters (formula language, by name).
    public var formula: String?
    public var associations: [GlobalParameterAssociation]
    public init(name: String, type: ParamType, group: ParameterGroup = .dimensions, value: ParamValue? = nil, formula: String? = nil) {
        id = UUID().uuidString; self.name = name; self.type = type; self.group = group
        self.value = value ?? type.defaultValue; self.formula = formula; associations = []
    }
    public var isComputed: Bool { !(formula?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }
}

/// Evaluation and association of global parameters.
public enum GlobalParameters {
    /// The association key of a dimension's label.
    public static let dimensionLabel = ParameterID("dimension.value")
    /// The labelled value cached on a dimension, so the constraint solver sees the dimension change when the global does.
    public static let labelValueKey = ParameterID("dimension.globalValue")

    /// Types a global parameter can have (RevitCraft `ParamKind::USER`, without element references).
    public static let types: [ParamType] = [.length, .area, .volume, .angle, .slope, .number, .integer, .percentage, .currency, .text, .bool]

    public static func all(_ model: BIMModel) -> [GlobalParameter] { model.manageData.globalParameters }
    public static func named(_ name: String, _ model: BIMModel) -> GlobalParameter? { all(model).first { $0.name == name } }

    /// Values of the numeric, yes/no and text globals for formulas (schedule calculated fields, other globals).
    public static func formulaInputs(_ model: BIMModel) -> [String: FormulaValue] {
        var out: [String: FormulaValue] = [:]
        for g in all(model) { out[g.name] = FamilyEvaluator.formulaValue(g.value, type: g.type) }
        return out
    }

    /// Computes formula globals from the others, to a fixed point. Throws for unknown names, type mismatches, a global
    /// that refers to itself, and formulas that refer to each other in a loop.
    public static func evaluate(_ list: [GlobalParameter], units: UnitsSettings) throws(ParameterError) -> [GlobalParameter] {
        var out = list
        let names = Set(list.map(\.name))
        func pass() throws(ParameterError) -> Bool {
            var changed = false
            for i in out.indices where out[i].isComputed {
                let g = out[i]
                let src = g.formula!.trimmingCharacters(in: .whitespaces).trimmingPrefix("=").trimmingCharacters(in: .whitespaces)
                let formula: Formula
                do { formula = try Formula(src, knownNames: names.subtracting([g.name])) } catch {
                    if (try? Formula(src, knownNames: names)) != nil { throw ParameterError("Global parameter “\(g.name)” can't refer to itself.") }
                    throw ParameterError("Global parameter “\(g.name)”: \(error)")
                }
                var inputs: [String: FormulaValue] = [:]
                for o in out where o.name != g.name { inputs[o.name] = FamilyEvaluator.formulaValue(o.value, type: o.type) }
                let r: FormulaValue
                do { r = try formula.evaluate(units: units) { inputs[$0] } }
                catch { throw ParameterError("Global parameter “\(g.name)”: \(error)") }
                if case .quantity(_, let d) = r, let want = g.type.dimension, d != want, d != .none {
                    throw ParameterError("Global parameter “\(g.name)”: the formula doesn't give a \(g.type.displayName.lowercased()) value.")
                }
                let v = FamilyEvaluator.paramValue(r, type: g.type)
                if !same(v, out[i].value) { out[i].value = v; changed = true }
            }
            return changed
        }
        for _ in 0...max(1, out.count) { if try !pass() { return out } }
        throw ParameterError("Global parameter formulas refer to each other in a loop.")
    }

    static func same(_ a: ParamValue, _ b: ParamValue) -> Bool {
        if let x = a.doubleValue, let y = b.doubleValue, a.textValue == nil || b.textValue == nil { return abs(x - y) < 1e-9 }
        return a == b
    }

    /// Replaces the project's globals (evaluating formulas) and pushes their values into associated parameters and
    /// labelled dimensions, in the current transaction.
    public static func set(_ list: [GlobalParameter], in tx: TransactionContext) throws(TransactionError) {
        var seen = Set<String>()
        for g in list {
            let n = g.name.trimmingCharacters(in: .whitespaces)
            if n.isEmpty { throw TransactionError("Enter a name for every global parameter.") }
            if !seen.insert(n).inserted { throw TransactionError("A global parameter named “\(n)” already exists.") }
        }
        let evaluated: [GlobalParameter]
        do { evaluated = try evaluate(list, units: tx.model.units) } catch { throw TransactionError(error.message) }
        tx.updateManageData { $0.globalParameters = evaluated }
        try apply(in: tx)
    }

    /// Pushes every global's value into its associated element parameters and labelled dimensions; associations of
    /// deleted elements are dropped. RevitCraft does this on every regeneration; here it runs whenever globals or
    /// associations change.
    public static func apply(in tx: TransactionContext) throws(TransactionError) {
        var list = all(tx.model)
        guard !list.isEmpty else { return }
        for gi in list.indices {
            list[gi].associations.removeAll { tx.model[$0.elementID] == nil }
            let g = list[gi]
            for a in g.associations {
                guard let e = tx.model[a.elementID] else { continue }
                if a.parameterID == dimensionLabel {
                    guard let v = g.value.doubleValue, g.type == .length || g.type == .angle else { continue }
                    if v <= 0 { throw TransactionError("Global parameter “\(g.name)” must be greater than zero to drive a dimension.", elements: [e.id]) }
                    if e.params[labelValueKey]?.doubleValue != v { tx.update(e.id) { $0.params[labelValueKey] = .double(v) } }
                    continue
                }
                let current = Parameters.value(a.parameterID, of: e, tx.model)
                if let current, same(current, g.value) { continue }
                do { try Parameters.set(a.parameterID, to: g.value, on: e.id, in: tx) }
                catch { throw TransactionError("Global parameter “\(g.name)”: \(error.message)", elements: [e.id]) }
            }
        }
        if list != all(tx.model) { tx.updateManageData { $0.globalParameters = list } }
    }

    /// The global associated with an element parameter, if any.
    public static func association(_ elementID: ElementID, _ parameterID: ParameterID, _ model: BIMModel) -> GlobalParameter? {
        let list = all(model)
        guard !list.isEmpty else { return nil }
        return list.first { g in g.associations.contains { $0.elementID == elementID && $0.parameterID == parameterID } }
    }

    /// Why an associated parameter is read-only, or nil.
    public static func lockedReason(_ elementID: ElementID, _ parameterID: ParameterID, _ model: BIMModel) -> String? {
        association(elementID, parameterID, model).map { "Associated with the global parameter “\($0.name)”." }
    }

    /// Globals that can drive a parameter of `type` (the same type; dimensions take length globals, angular ones angles).
    public static func compatible(with type: ParamType, _ model: BIMModel) -> [GlobalParameter] {
        all(model).filter { $0.type == type }
    }

    /// Associates (or, with nil, frees) an element parameter and pushes the value. A dimension label needs a linear or
    /// aligned dimension between two references.
    public static func associate(_ elementID: ElementID, _ parameterID: ParameterID, with globalID: String?, in tx: TransactionContext) throws(TransactionError) {
        guard let e = tx.model[elementID] else { throw TransactionError("The element no longer exists.") }
        if parameterID == dimensionLabel, globalID != nil {
            guard let d = e.dimension, d.kind == .linear || d.kind == .aligned, d.references.count == 2 else {
                throw TransactionError("Only a linear or aligned dimension between two references can be labelled.", elements: [elementID])
            }
        }
        var list = all(tx.model)
        for i in list.indices { list[i].associations.removeAll { $0.elementID == elementID && $0.parameterID == parameterID } }
        if let globalID {
            guard let i = list.firstIndex(where: { $0.id == globalID }) else { throw TransactionError("That global parameter no longer exists.") }
            list[i].associations.append(GlobalParameterAssociation(elementID: elementID, parameterID: parameterID))
        }
        tx.updateManageData { $0.globalParameters = list }
        if parameterID == dimensionLabel && globalID == nil { tx.update(elementID) { $0.params.removeValue(forKey: labelValueKey) } }
        try apply(in: tx)
    }

    /// The distance a labelled dimension holds (for the constraint solver), or nil.
    public static func labelledValue(_ dimension: Element, _ model: BIMModel) -> Double? {
        guard let v = dimension.params[labelValueKey]?.doubleValue, association(dimension.id, dimensionLabel, model) != nil else { return nil }
        return v
    }

    /// Marks associated instance parameters read-only (Properties palette).
    public static func lock(_ entries: [ParameterEntry], of e: Element, _ model: BIMModel) -> [ParameterEntry] {
        guard !all(model).isEmpty else { return entries }
        return entries.map { entry in
            guard let reason = lockedReason(e.id, entry.id, model) else { return entry }
            var x = entry
            x.isReadOnly = true
            x.readOnlyReason = reason
            return x
        }
    }
}

private extension String {
    func trimmingPrefix(_ p: String) -> String { hasPrefix(p) ? String(dropFirst(p.count)) : self }
}
