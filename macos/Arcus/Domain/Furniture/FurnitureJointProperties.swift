import Foundation
import ArcusGeometry

// FMG2: joints in Properties, for joints the rules make too. FM6 showed only joints the user had set (they are
// elements); the rules' joints aren't stored. Now:
//   - a part's Properties list its joints under Construction, one group of rows per joint ("P2 Joint", "P2 Runs
//     Through", "P2 By Rule" and the type's sizes);
//   - the Joint tool's picked joint shows in Properties (`rows(_:_:)`), set by the user or not;
//   - editing a joint the rules make creates the user's joint element (as editing a wall join in Revit does), and an
//     edit that brings it back to what the rules give removes the element again (`normalize`).

public enum FurnitureJointProperties {
    /// Ids of a part's joint rows: "furniture.partJoint.<other part>.<joint parameter>".
    static let prefix = "furniture.partJoint."

    static func partRowID(_ other: ElementID, _ jointParameter: ParameterID) -> ParameterID {
        ParameterID("\(prefix)\(other.raw).\(jointParameter.key.dropFirst("furniture.joint.".count))")
    }

    /// The joint parameter and other part a part-joint row id names.
    static func parse(_ id: ParameterID) -> (other: ElementID, jointParameter: ParameterID)? {
        guard id.key.hasPrefix(prefix) else { return nil }
        let rest = id.key.dropFirst(prefix.count)
        guard let dot = rest.firstIndex(of: "."), let raw = UInt64(rest[..<dot]) else { return nil }
        return (ElementID(raw), ParameterID("furniture.joint.\(rest[rest.index(after: dot)...])"))
    }

    // MARK: Rows

    /// The Joint tool's picked joint in Properties: the user's joint element, or (for a joint the rules make) the same
    /// rows for the joint as it would be stored, so editing it creates it.
    public static func rows(_ key: JointKey, _ m: BIMModel) -> [PropertyRow] {
        guard let e = subject(key, m) else { return [] }
        return PaletteLayout.aggregate([e], m)
    }

    /// The joint element for `key`: the user's, or the by-rule element it would be (not in the model; its parameters
    /// read the solved joint from `m`).
    static func subject(_ key: JointKey, _ m: BIMModel) -> Element? {
        guard JointSolver.solve(m).joint(key) != nil else { return nil }
        if let e = FurnitureJointOperations.element(key, m) { return e }
        let tx = TransactionContext(model: m, name: "Joint")
        let id = tx.create(.furnitureJoints, name: "Joint", data: .furnitureJoint(JointData(parts: [key.a, key.b])), hostID: key.a)
        return tx.model[id]
    }

    /// Entries the palette shows for an element, adjusted: a joint's Runs Through picks one of its two parts; a part
    /// lists its joints.
    static func adjust(_ entries: [ParameterEntry], _ e: Element, _ m: BIMModel) -> [ParameterEntry] {
        guard m.isFurniture else { return entries }
        if let d = e.furnitureJoint, d.isPair {
            let marks = d.parts.map { FurnitureJointParameters.mark($0, m) }
            return entries.map { x in
                if x.id == FurnitureJointParameters.fastener.id, let j = FurnitureJointParameters.joint(e, m) { // COMPB: the joint type's connectors
                    var y = x
                    y.type = .choice([FurnitureJointParameters.byJointType] + FurnitureJointFasteners.options(j.type).map(\.name))
                    return y
                }
                guard x.id == FurnitureJointParameters.through.id, marks.count == 2, marks[0] != marks[1] else { return x }
                var y = x
                y.type = .choice(marks)
                return y
            }
        }
        guard e.category.isFurniturePart, !e.isType else { return entries }
        return entries + partEntries(e, m)
    }

    /// A part's joint rows: for each joint, its type, Runs Through (at corners), By Rule and the type's sizes, named by
    /// the other part ("P2 Joint").
    static func partEntries(_ e: Element, _ m: BIMModel) -> [ParameterEntry] {
        let joints = JointSolver.solve(m).joints(of: e.id)
        guard !joints.isEmpty else { return [] }
        var out: [ParameterEntry] = []
        let ordered = joints.map { j in (j, j.key.a == e.id ? j.key.b : j.key.a) }
            .sorted { FurnitureJointParameters.mark($0.1, m).localizedStandardCompare(FurnitureJointParameters.mark($1.1, m)) == .orderedAscending }
        for (j, other) in ordered {
            guard let je = subject(j.key, m) else { continue }
            let name = FurnitureJointParameters.mark(other, m)
            let ctx = ParameterContext(model: m)
            var list: [BuiltInParameter] = [FurnitureJointParameters.jointType]
            if j.isCorner && j.type != .miter { list.append(FurnitureJointParameters.through) }
            list.append(FurnitureJointParameters.byRule)
            list += j.type.parameterKeys.compactMap { k in FurnitureJointParameters.values.first { $0.id == FurnitureJointParameters.value(k).id } }
            let fasteners = FurnitureJointFasteners.options(j.type) // COMPB: the joint's connector component
            if !fasteners.isEmpty { list.append(FurnitureJointParameters.fastener) }
            for b in list {
                let reason = b.lockedReason?(je, ctx)
                var type = b.type
                if b.id == FurnitureJointParameters.through.id { type = .choice([FurnitureJointParameters.mark(j.key.a, m), FurnitureJointParameters.mark(j.key.b, m)]) }
                if b.id == FurnitureJointParameters.jointType.id { type = .choice(JointType.allCases.filter { $0 != .miter || j.canMiter }.map(\.rawValue)) }
                if b.id == FurnitureJointParameters.fastener.id { type = .choice([FurnitureJointParameters.byJointType] + fasteners.map(\.name)) } // COMPB
                let label = b.id == FurnitureJointParameters.jointType.id ? "Joint" : (JointParameterKey.allCases.first { FurnitureJointParameters.value($0).id == b.id }?.label(for: j.type) ?? b.name)
                out.append(ParameterEntry(id: partRowID(other, b.id), name: "\(name) \(label)", type: type, group: .construction, isType: false,
                                          isReadOnly: b.isReadOnly || reason != nil, value: b.getter(je, ctx), formula: nil,
                                          tooltip: "\(j.pair.rawValue) joint with \(name). " + b.tooltip, readOnlyReason: reason))
            }
        }
        return out
    }

    // MARK: Setting

    /// Parameters.set hook: part joint rows and joint elements' rows. Returns false for other parameters.
    static func set(_ id: ParameterID, to value: ParamValue, on elementID: ElementID, in tx: TransactionContext) throws(ParameterError) -> Bool {
        guard tx.model.isFurniture, let e = tx.model[elementID] else { return false }
        if let (other, jp) = parse(id) {
            try FurnitureJointOperations.setProperty(JointKey(elementID, other), jp, value, in: tx)
            return true
        }
        if let d = e.furnitureJoint, d.isPair, id.key.hasPrefix("furniture.joint.") {
            try FurnitureJointOperations.setProperty(JointKey(d.parts[0], d.parts[1]), id, value, in: tx)
            return true
        }
        return false
    }
}

extension FurnitureJointOperations {
    /// FMG2: sets one of a joint's Properties (type, Runs Through, By Rule, a size), making the user's joint element
    /// when the rules made the joint, and removing it when the joint ends up as the rules give it.
    public static func setProperty(_ key: JointKey, _ id: ParameterID, _ value: ParamValue, in tx: TransactionContext) throws(ParameterError) {
        guard tx.model.isFurniture, JointSolver.solve(tx.model).joint(key) != nil else { throw ParameterError("These parts don't join.") }
        let jointID = element(key, tx.model)?.id
            ?? tx.create(.furnitureJoints, name: "Joint", data: .furnitureJoint(JointData(parts: [key.a, key.b])), hostID: key.a)
        guard let e = tx.model[jointID] else { throw ParameterError("The joint no longer exists.") }
        let ctx = ParameterContext(model: tx.model)
        guard let b = FurnitureJointParameters.instance(for: e).first(where: { $0.id == id }), let setter = b.setter else {
            throw ParameterError("This joint value can't be changed.")
        }
        if let reason = b.lockedReason?(e, ctx) { throw ParameterError(reason) }
        var copy = e
        do { try setter(&copy, value, ctx) } catch let x as ParameterError { throw x } catch { throw ParameterError("\(error)") }
        tx.update(jointID) { $0 = copy }
        normalize(key, in: tx)
    }

    /// FMG2: what equals the rules isn't an override: the rule's type, no sizes, the part that would run through anyway.
    /// A joint left with no override is removed.
    static func normalize(_ key: JointKey, in tx: TransactionContext) {
        guard let e = element(key, tx.model), var d = e.furnitureJoint, let j = JointSolver.solve(tx.model).joint(key) else { return }
        if d.type == j.ruleType { d.type = nil }
        if let p = d.parameters, p.isEmpty { d.parameters = nil }
        if let t = d.throughPartID {
            var probe = d
            probe.throughPartID = nil
            let ptx = TransactionContext(model: tx.model, name: "Probe")
            if probe.isByRule { ptx.delete(e.id) } else { ptx.update(e.id) { $0.furnitureJoint = probe } }
            if JointSolver.solve(ptx.model).joint(key)?.throughID == t { d.throughPartID = nil }
        }
        if d.isByRule { tx.delete(e.id) } else if d != e.furnitureJoint { tx.update(e.id) { $0.furnitureJoint = d } }
    }
}
