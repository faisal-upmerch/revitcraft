import Foundation
import ArcusGeometry
import ArcusCalc

/// One parameter row as shown in the Properties inspector, schedules, tags and IFC property sets.
public struct ParameterEntry: Sendable, Identifiable, Hashable {
    public var id: ParameterID
    public var name: String
    public var type: ParamType
    public var group: ParameterGroup
    /// True when the value lives on the element's type (edited through Type Properties).
    public var isType: Bool
    public var isReadOnly: Bool
    public var value: ParamValue?
    public var formula: String?
    public var tooltip: String
    /// Why a read-only parameter cannot be edited (shown as help).
    public var readOnlyReason: String?
}

public struct ParameterError: Error, Hashable, Sendable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Context passed to parameter getters.
public struct ParameterContext: Sendable {
    public let model: BIMModel
    public init(model: BIMModel) { self.model = model }
    public var units: UnitsSettings { model.units }
    public func quantities(_ e: Element) -> ElementQuantities { QuantityEngine.quantities(for: e, in: model) }
}

/// Definition of a built-in parameter with accessors.
public struct BuiltInParameter: Sendable {
    public let id: ParameterID
    public let name: String
    public let type: ParamType
    public let group: ParameterGroup
    public let tooltip: String
    let getter: @Sendable (Element, ParameterContext) -> ParamValue?
    let setter: (@Sendable (inout Element, ParamValue, ParameterContext) throws -> Void)?
    /// Returns a reason when the parameter is read-only for this particular element (e.g. Unconnected Height with a top level).
    let lockedReason: (@Sendable (Element, ParameterContext) -> String?)?

    public var isReadOnly: Bool { setter == nil }

    init(_ key: String, _ name: String, _ type: ParamType, _ group: ParameterGroup, tooltip: String = "",
         get: @escaping @Sendable (Element, ParameterContext) -> ParamValue?,
         set: (@Sendable (inout Element, ParamValue, ParameterContext) throws -> Void)? = nil,
         locked: (@Sendable (Element, ParameterContext) -> String?)? = nil) {
        id = ParameterID(key); self.name = name; self.type = type; self.group = group; self.tooltip = tooltip
        self.getter = get; self.setter = set; lockedReason = locked
    }
}

/// Central parameter access used by the inspector, schedules, tags, filters, IFC and CSV exchange.
public enum Parameters {
    // MARK: Lookup

    /// All instance parameters for an element (built-in + project parameters + family instance parameters).
    public static func instanceEntries(_ e: Element, _ model: BIMModel) -> [ParameterEntry] {
        let ctx = ParameterContext(model: model)
        var out: [ParameterEntry] = []
        for b in BuiltInCatalog.instance(for: e) {
            let reason = b.lockedReason?(e, ctx)
            out.append(ParameterEntry(id: b.id, name: b.name, type: b.type, group: b.group, isType: false,
                                      isReadOnly: b.isReadOnly || reason != nil, value: b.getter(e, ctx), formula: nil, tooltip: b.tooltip,
                                      readOnlyReason: b.isReadOnly ? "Calculated from the model." : reason))
        }
        // Family instance parameters.
        if let fam = familyDefinition(for: e, model) {
            let evaluated = evaluatedFamilyValues(for: e, model)
            for p in fam.parameters where p.isInstance {
                let id = familyParamID(p.name)
                let v = p.formula != nil ? evaluated[p.name].map { FamilyEvaluator.paramValue($0, type: p.type) } : (e.params[id] ?? defaultFamilyValue(p, e, model))
                out.append(ParameterEntry(id: id, name: p.name, type: p.type, group: p.group, isType: false, isReadOnly: p.formula != nil,
                                          value: v, formula: p.formula, tooltip: "", readOnlyReason: p.formula != nil ? "Driven by a formula." : nil))
            }
        }
        // Project parameters bound to the category.
        for d in model.projectParameters where d.isInstance && d.categories.contains(e.category) {
            out.append(ParameterEntry(id: d.id, name: d.name, type: d.type, group: d.group, isType: false, isReadOnly: d.formula != nil,
                                      value: e.params[d.id] ?? d.defaultValue, formula: d.formula, tooltip: d.tooltip,
                                      readOnlyReason: d.formula != nil ? "Driven by a formula." : nil))
        }
        out = GlobalParameters.lock(out, of: e, model) // F11: parameters associated with a global parameter are read-only
        return out.sorted { ($0.group, $0.orderKey) < ($1.group, $1.orderKey) }
    }

    /// Type parameters for a type element.
    public static func typeEntries(_ type: Element, _ model: BIMModel) -> [ParameterEntry] {
        guard let td = type.typeData else { return [] }
        let ctx = ParameterContext(model: model)
        var out: [ParameterEntry] = []
        for b in BuiltInCatalog.type(for: td) {
            out.append(ParameterEntry(id: b.id, name: b.name, type: b.type, group: b.group, isType: true, isReadOnly: b.isReadOnly,
                                      value: b.getter(type, ctx), formula: nil, tooltip: b.tooltip,
                                      readOnlyReason: b.isReadOnly ? "Calculated from the type's structure." : nil))
        }
        if let famID = td.familyID, let fam = model[famID]?.family {
            // BL-SITE: formulas read the project type's values (as instances do), not the values stored in the family.
            let evaluated = FamilyEvaluator.parameterValues(effectiveFamily(fam, for: type, model), typeName: "project", instance: [:], units: model.units).values
            for p in fam.parameters where !p.isInstance {
                let id = familyParamID(p.name)
                let v = p.formula != nil ? evaluated[p.name].map { FamilyEvaluator.paramValue($0, type: p.type) } : (td.params[id] ?? p.type.defaultValue)
                out.append(ParameterEntry(id: id, name: p.name, type: p.type, group: p.group, isType: true, isReadOnly: p.formula != nil,
                                          value: v, formula: p.formula, tooltip: "", readOnlyReason: p.formula != nil ? "Driven by a formula." : nil))
            }
        }
        for d in model.projectParameters where !d.isInstance && d.categories.contains(td.instanceCategory) {
            out.append(ParameterEntry(id: d.id, name: d.name, type: d.type, group: d.group, isType: true, isReadOnly: false,
                                      value: td.params[d.id] ?? d.defaultValue, formula: nil, tooltip: d.tooltip, readOnlyReason: nil))
        }
        return out.sorted { ($0.group, $0.orderKey) < ($1.group, $1.orderKey) }
    }

    /// Every parameter (instance + type) available on an element, for schedules, filters and tags.
    public static func allEntries(_ e: Element, _ model: BIMModel) -> [ParameterEntry] {
        var out = instanceEntries(e, model)
        if let t = model.type(of: e) { out += typeEntries(t, model) }
        return out
    }

    /// The built-in definition that applies to this element. Several built-ins share an id with different rules
    /// (e.g. "name" for rooms, sheets, levels and views); the element's own catalog entry wins over `byID`.
    static func builtIn(_ id: ParameterID, for e: Element, _ model: BIMModel) -> BuiltInParameter? {
        guard let any = BuiltInCatalog.byID[id] else { return nil }
        if let own = BuiltInCatalog.instance(for: e).first(where: { $0.id == id }) { return own }
        if let td = e.typeData ?? model.typeData(of: e), let own = BuiltInCatalog.type(for: td).first(where: { $0.id == id }) { return own }
        return any
    }

    /// Value of a parameter by id, looking at the instance first and then its type.
    public static func value(_ id: ParameterID, of e: Element, _ model: BIMModel) -> ParamValue? {
        let ctx = ParameterContext(model: model)
        if let b = builtIn(id, for: e, model) {
            if let t = model.type(of: e), BuiltInCatalog.isTypeParameter(id) { return b.getter(t, ctx) }
            if e.isType || !BuiltInCatalog.isTypeParameter(id) { return b.getter(e, ctx) }
        }
        if id.key.hasPrefix(familyPrefix) {
            let name = String(id.key.dropFirst(familyPrefix.count))
            if let fam = familyDefinition(for: e, model), let p = fam.parameter(named: name) {
                if p.formula != nil { return evaluatedFamilyValues(for: e, model)[name].map { FamilyEvaluator.paramValue($0, type: p.type) } }
                if p.isInstance { return e.params[id] ?? defaultFamilyValue(p, e, model) }
                return (e.typeData ?? model.typeData(of: e))?.params[id] ?? p.type.defaultValue // BL-SITE: a type element reads its own values
            }
            if e.isType { return e.typeData?.params[id] }
            return nil
        }
        if let v = e.params[id] { return v }
        if let d = model.projectParameters.first(where: { $0.id == id }) {
            if !d.isInstance { return model.typeData(of: e)?.params[id] ?? e.typeData?.params[id] ?? d.defaultValue }
            return d.defaultValue
        }
        return model.typeData(of: e)?.params[id]
    }

    /// Whether a parameter can be edited on an element — the same answer as the `isReadOnly` flag of its first entry
    /// in `allEntries`, without evaluating any values (schedules call this per cell).
    public static func isEditable(_ id: ParameterID, on e: Element, _ model: BIMModel) -> Bool {
        let ctx = ParameterContext(model: model)
        let fam = familyDefinition(for: e, model)
        let familyName: String? = id.key.hasPrefix(familyPrefix) ? String(id.key.dropFirst(familyPrefix.count)) : nil
        if GlobalParameters.association(e.id, id, model) != nil { return false } // F11
        // Instance side, in allEntries order: built-ins, family instance parameters, project instance parameters.
        if let b = BuiltInCatalog.instance(for: e).first(where: { $0.id == id }) { return !b.isReadOnly && b.lockedReason?(e, ctx) == nil }
        if let familyName, let p = fam?.parameter(named: familyName), p.isInstance { return p.formula == nil }
        if let d = model.projectParameters.first(where: { $0.id == id && $0.isInstance && $0.categories.contains(e.category) }) { return d.formula == nil }
        // Type side.
        guard let t = model.type(of: e), let td = t.typeData else { return false }
        if let b = BuiltInCatalog.type(for: td).first(where: { $0.id == id }) { return !b.isReadOnly }
        if let familyName, let famID = td.familyID, let p = model[famID]?.family?.parameter(named: familyName), !p.isInstance { return p.formula == nil }
        return model.projectParameters.contains { $0.id == id && !$0.isInstance && $0.categories.contains(td.instanceCategory) }
    }

    /// Id and type of the parameter named `name` on an element (first match in `allEntries` order), without
    /// evaluating values. Tags use this with `value(_:of:_:)` so each label costs one getter, not every getter.
    public static func descriptor(named name: String, for e: Element, _ model: BIMModel) -> (id: ParameterID, type: ParamType)? {
        if let b = BuiltInCatalog.instance(for: e).first(where: { $0.name == name }) { return (b.id, b.type) }
        if let p = familyDefinition(for: e, model)?.parameters.first(where: { $0.isInstance && $0.name == name }) { return (familyParamID(p.name), p.type) }
        if let d = model.projectParameters.first(where: { $0.isInstance && $0.name == name && $0.categories.contains(e.category) }) { return (d.id, d.type) }
        guard let t = model.type(of: e), let td = t.typeData else { return nil }
        if let b = BuiltInCatalog.type(for: td).first(where: { $0.name == name }) { return (b.id, b.type) }
        if let famID = td.familyID, let p = model[famID]?.family?.parameters.first(where: { !$0.isInstance && $0.name == name }) { return (familyParamID(p.name), p.type) }
        if let d = model.projectParameters.first(where: { !$0.isInstance && $0.name == name && $0.categories.contains(td.instanceCategory) }) { return (d.id, d.type) }
        return nil
    }

    /// Finds a parameter id by display name for an element (used by tags, formulas and CSV import).
    public static func id(named name: String, for e: Element, _ model: BIMModel) -> ParameterID? {
        allEntries(e, model).first { $0.name == name }?.id
    }

    // MARK: Setting

    /// Sets a parameter inside a transaction. Type parameters are written to the element's type.
    public static func set(_ id: ParameterID, to value: ParamValue, on elementID: ElementID, in tx: TransactionContext) throws(ParameterError) {
        guard let e = tx.model[elementID] else { throw ParameterError("The element no longer exists.") }
        let ctx = ParameterContext(model: tx.model)
        if let b = builtIn(id, for: e, tx.model) {
            let targetID: ElementID
            if BuiltInCatalog.isTypeParameter(id) && !e.isType {
                guard let t = e.typeID else { throw ParameterError("This element has no type.") }
                targetID = t
            } else { targetID = elementID }
            guard let target = tx.model[targetID], let setter = b.setter else { throw ParameterError("“\(b.name)” is read-only.") }
            if let reason = b.lockedReason?(target, ctx) { throw ParameterError(reason) }
            var copy = target
            do { try setter(&copy, value, ctx) } catch let e as ParameterError { throw e } catch { throw ParameterError("\(error)") }
            tx.update(targetID) { $0 = copy }
            return
        }
        if id.key.hasPrefix(familyPrefix) {
            let name = String(id.key.dropFirst(familyPrefix.count))
            guard let fam = familyDefinition(for: e, tx.model), let p = fam.parameter(named: name) else {
                if e.isType { tx.update(elementID) { $0.typeData?.params[id] = value }; return }
                throw ParameterError("Unknown family parameter “\(name)”.")
            }
            guard p.formula == nil else { throw ParameterError("“\(name)” is driven by a formula and cannot be edited.") }
            try validate(value, type: p.type, name: name)
            if p.isInstance && !e.isType {
                tx.update(elementID) { $0.params[id] = value }
            } else {
                let tid = e.isType ? elementID : e.typeID
                guard let tid else { throw ParameterError("This element has no type.") }
                tx.update(tid) { $0.typeData?.params[id] = value }
            }
            return
        }
        if let d = tx.model.projectParameters.first(where: { $0.id == id }) {
            guard d.formula == nil else { throw ParameterError("“\(d.name)” is calculated and cannot be edited.") }
            try validate(value, type: d.type, name: d.name)
            if d.isInstance && !e.isType {
                tx.update(elementID) { $0.params[id] = value }
            } else {
                let tid = e.isType ? elementID : e.typeID
                guard let tid else { throw ParameterError("This element has no type.") }
                tx.update(tid) { $0.typeData?.params[id] = value }
            }
            return
        }
        tx.update(elementID) { $0.params[id] = value }
    }

    static func validate(_ v: ParamValue, type: ParamType, name: String) throws(ParameterError) {
        switch type {
        case .integer: if v.intValue == nil { throw ParameterError("“\(name)” needs a whole number.") }
        case .bool: if v.boolValue == nil { throw ParameterError("“\(name)” needs Yes or No.") }
        case .length, .area, .volume, .angle, .slope, .number, .percentage, .currency:
            guard let d = v.doubleValue, d.isFinite else { throw ParameterError("“\(name)” needs a number.") }
        case .url:
            if let s = v.textValue, !s.isEmpty, URL(string: s) == nil { throw ParameterError("“\(name)” is not a valid URL.") }
        case .choice(let options):
            if let s = v.textValue, !options.contains(s) { throw ParameterError("“\(s)” is not an option for “\(name)”.") }
        default: break
        }
    }

    // MARK: Formatting & parsing

    public static func format(_ v: ParamValue?, type: ParamType, model: BIMModel) -> String {
        guard let v else { return "" }
        switch type {
        case .bool: return (v.boolValue ?? false) ? "Yes" : "No"
        case .text, .multilineText, .url, .choice: return v.textValue ?? v.description
        case .integer: return v.intValue.map(String.init) ?? ""
        case .elementRef(let c):
            guard let id = v.refValue else { return c == .levels ? "Unconnected" : "<None>" }
            guard let e = model[id] else { return "<Missing>" }
            if let s = e.sheet { return "\(s.number) - \(e.name)" }
            if let td = e.typeData, !td.familyName.isEmpty { return "\(td.familyName): \(e.name)" }
            return e.name
        default:
            guard let k = type.unitKind, let d = v.doubleValue else { return v.description }
            return QuantityFormatter.format(d, kind: k, units: model.units)
        }
    }

    /// Parses user text for a parameter type.
    public static func parse(_ text: String, type: ParamType, model: BIMModel) throws(ParameterError) -> ParamValue {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .text, .multilineText, .url: return .text(text)
        case .choice(let o):
            guard let m = o.first(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { throw ParameterError("Choose one of: \(o.joined(separator: ", ")).") }
            return .text(m)
        case .bool:
            switch t.lowercased() {
            case "yes", "y", "true", "1", "on": return .bool(true)
            case "no", "n", "false", "0", "off": return .bool(false)
            default: throw ParameterError("Type Yes or No.")
            }
        case .elementRef(let c):
            if t.isEmpty || t == "<None>" || t == "Unconnected" { return .ref(nil) }
            let candidates = model.elements(c)
            if let e = candidates.first(where: { $0.name == t }) { return .ref(e.id) }
            // Accept the formatted forms produced by `format`: "Family: Type" and "A101 - Sheet Name".
            if let e = candidates.first(where: { e in
                if let td = e.typeData, "\(td.familyName): \(e.name)" == t { return true }
                if let sd = e.sheet, "\(sd.number) - \(e.name)" == t || sd.number == t { return true }
                return false
            }) { return .ref(e.id) }
            throw ParameterError("No \(c.singularName.lowercased()) named “\(t)”.")
        default:
            guard let k = type.unitKind else { return .text(text) }
            do {
                let d = try QuantityParser.parse(t, kind: k, units: model.units)
                return k == .integer ? .int(Int(d)) : .double(d)
            } catch {
                throw ParameterError("\(error)")
            }
        }
    }

    // MARK: Families

    static let familyPrefix = "family:"
    public static func familyParamID(_ name: String) -> ParameterID { ParameterID(familyPrefix + name) }

    public static func familyDefinition(for e: Element, _ model: BIMModel) -> FamilyDefinition? {
        let td = e.typeData ?? model.typeData(of: e)
        guard let fid = td?.familyID else { return nil }
        return model[fid]?.family
    }

    static func defaultFamilyValue(_ p: FamilyParameter, _ e: Element, _ model: BIMModel) -> ParamValue {
        guard let fam = familyDefinition(for: e, model), let tname = model.type(of: e)?.name else { return p.type.defaultValue }
        return fam.type(named: tname)?.values[p.name] ?? fam.types.first?.values[p.name] ?? p.type.defaultValue
    }

    /// Family parameter values for an instance (type values from the project type + instance overrides).
    public static func evaluatedFamilyValues(for e: Element, _ model: BIMModel) -> [String: FormulaValue] {
        guard let fam = familyDefinition(for: e, model) else { return [:] }
        return FamilyEvaluator.parameterValues(effectiveFamily(fam, for: e, model), typeName: "project",
                                               instance: familyInstanceValues(e), units: model.units).values
    }

    /// The family with a synthetic "project" type holding the project type's current values.
    public static func effectiveFamily(_ fam: FamilyDefinition, for e: Element, _ model: BIMModel) -> FamilyDefinition {
        let typeElement = e.isType ? e : model.type(of: e)
        var values = fam.type(named: typeElement?.name ?? "")?.values ?? fam.types.first?.values ?? [:]
        if let td = typeElement?.typeData {
            for (k, v) in td.params where k.key.hasPrefix(familyPrefix) { values[String(k.key.dropFirst(familyPrefix.count))] = v }
        }
        var f = fam
        f.types = [FamilyTypeDefinition(name: "project", values: values)]
        return f
    }

    public static func familyInstanceValues(_ e: Element) -> [String: ParamValue] {
        var out: [String: ParamValue] = [:]
        for (k, v) in e.params where k.key.hasPrefix(familyPrefix) { out[String(k.key.dropFirst(familyPrefix.count))] = v }
        return out
    }
}

extension ParameterEntry {
    var orderKey: Int { BuiltInCatalog.order[id] ?? 10_000 }
}
