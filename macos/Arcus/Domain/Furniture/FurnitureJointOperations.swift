import Foundation
import ArcusGeometry

// FM6: the model operations behind the Joint tool, Joint Rules and Allow/Disallow Join. A joint the user changes is
// stored as a `furnitureJoint` element (hosted by its first part, so deleting the part deletes it); one changed back to
// what the rules give is removed again, as Revit keeps only the joins the user edited.

public enum FurnitureJointOperations {
    static func requireFurniture(_ tx: TransactionContext) throws(TransactionError) {
        guard tx.model.isFurniture else { throw TransactionError("Joints are made in Furniture documents.") }
    }

    /// The user's joint element for a pair.
    public static func element(_ key: JointKey, _ m: BIMModel) -> Element? {
        m.elements(.furnitureJoints).first { e in
            guard let d = e.furnitureJoint, d.isPair else { return false }
            return JointKey(d.parts[0], d.parts[1]) == key
        }
    }

    /// Changes the user's joint for `key` (making it when needed, removing it when nothing is left overridden).
    static func edit(_ key: JointKey, in tx: TransactionContext, _ change: (inout JointData, FurnitureJoint) -> Void) throws(TransactionError) {
        try requireFurniture(tx)
        guard let j = JointSolver.solve(tx.model).joint(key) else { throw TransactionError("These parts don't join.", resolution: "Pick a joint marker with the Joint tool.") }
        let existing = element(key, tx.model)
        var d = existing?.furnitureJoint ?? JointData(parts: [key.a, key.b])
        change(&d, j)
        // A value equal to what the rules give isn't an override.
        if d.type == j.ruleType { d.type = nil }
        if let p = d.parameters, p.isEmpty { d.parameters = nil }
        if let e = existing {
            if d.isByRule { tx.delete(e.id) } else { tx.update(e.id) { $0.furnitureJoint = d } }
        } else if !d.isByRule {
            tx.create(.furnitureJoints, name: "Joint", data: .furnitureJoint(d), hostID: key.a)
        }
    }

    /// Sets the joint's type (Options Bar ▸ Joint); nil returns it to the rule.
    public static func set(_ key: JointKey, type: JointType?, in tx: TransactionContext) throws(TransactionError) {
        try edit(key, in: tx) { d, j in
            if type == .miter && !j.canMiter { return } // FMG2
            if d.type != type { d.parameters = nil }
            d.type = type
        }
    }

    /// Sets which part runs through (corners only).
    public static func set(_ key: JointKey, through: ElementID?, in tx: TransactionContext) throws(TransactionError) {
        try edit(key, in: tx) { d, j in
            guard let t = through else { d.throughPartID = nil; return }
            guard j.isCorner, t == key.a || t == key.b else { return }
            d.throughPartID = t
        }
    }

    /// Sets parameter values over the rule's (nil values are left as they are).
    public static func set(_ key: JointKey, parameters p: JointParameters, in tx: TransactionContext) throws(TransactionError) {
        try edit(key, in: tx) { d, _ in d.parameters = p.over(d.parameters ?? JointParameters()) }
    }

    /// Sets one parameter (nil = the rule's).
    public static func set(_ key: JointKey, _ k: JointParameterKey, _ v: Double?, in tx: TransactionContext) throws(TransactionError) {
        try edit(key, in: tx) { d, _ in
            var p = d.parameters ?? JointParameters()
            p.set(k, v)
            d.parameters = p
        }
    }

    /// Back to the rule: removes the user's joint.
    public static func reset(_ key: JointKey, in tx: TransactionContext) {
        if let e = element(key, tx.model) { tx.delete(e.id) }
    }

    /// Previous / Next: the joint's next configuration (each type with each part running through at corners). The
    /// configuration the rules give ends up as no override.
    public static func cycle(_ key: JointKey, by step: Int, in tx: TransactionContext) throws(TransactionError) {
        guard let j = JointSolver.solve(tx.model).joint(key) else { throw TransactionError("These parts don't join.") }
        let configs = j.configurations
        guard !configs.isEmpty else { return }
        let next = configs[((j.configurationIndex + step) % configs.count + configs.count) % configs.count]
        try edit(key, in: tx) { d, jj in
            if d.type ?? jj.ruleType != next.type { d.parameters = nil }
            d.type = next.type
            d.throughPartID = jj.isCorner ? next.through : nil
        }
        // The configuration the parts would have without an override needs none.
        if let e = element(key, tx.model), let d = e.furnitureJoint, d.type == nil, d.parameters == nil, let t = d.throughPartID {
            let probe = TransactionContext(model: tx.model, name: "Probe")
            probe.delete(e.id)
            if JointSolver.solve(probe.model).joint(key)?.throughID == t { tx.delete(e.id) }
        }
    }

    // MARK: Allow / Disallow Join

    /// Disallow Join at a joint: the end of the part that butts there joins nothing.
    public static func disallow(_ key: JointKey, in tx: TransactionContext) throws(TransactionError) {
        try requireFurniture(tx)
        guard let j = JointSolver.solve(tx.model).joint(key) else { throw TransactionError("These parts don't join.") }
        reset(key, in: tx)
        let end = PartEnd(axis: j.a1, atMax: j.bEndAtMax)
        guard !tx.model.elements(.furnitureJoints).contains(where: { $0.furnitureJoint == JointData(parts: [j.b], disallowedEnd: end) }) else { return }
        tx.create(.furnitureJoints, name: "Disallow Join", data: .furnitureJoint(JointData(parts: [j.b], disallowedEnd: end)), hostID: j.b)
    }

    /// Disallow Join on parts: none of their ends join.
    public static func disallowJoins(_ ids: [ElementID], in tx: TransactionContext) {
        allowJoins(ids, in: tx)
        for id in ids where tx.model[id]?.category.isFurniturePart == true {
            tx.create(.furnitureJoints, name: "Disallow Join", data: .furnitureJoint(JointData(parts: [id])), hostID: id)
        }
    }

    /// Allow Join: the parts' ends join again.
    public static func allowJoins(_ ids: [ElementID], in tx: TransactionContext) {
        let set = Set(ids)
        for e in tx.model.elements(.furnitureJoints) {
            guard let d = e.furnitureJoint, d.parts.count == 1, set.contains(d.parts[0]) else { continue }
            tx.delete(e.id)
        }
    }

    /// True when some end of the part is disallowed.
    public static func hasDisallowedEnds(_ id: ElementID, _ m: BIMModel) -> Bool {
        m.elements(.furnitureJoints).contains { $0.furnitureJoint?.parts == [id] && $0.furnitureJoint?.isPair == false }
    }

    // MARK: Joint Rules

    /// Manage ▸ Joint Rules: stores the table with the document.
    public static func setRules(_ rules: FurnitureJointRules, in tx: TransactionContext) throws(TransactionError) {
        try requireFurniture(tx)
        try FurnitureParameters.edit(tx) { $0.jointRules = rules }
    }

    // MARK: Tags

    /// The Cut Size Tag: Mark over the cut size (W x L), for every part category (idempotent).
    public static func ensureCutSizeTag(in tx: TransactionContext) {
        guard tx.model.isFurniture, !tx.model.elements(.families).contains(where: { $0.name == "Cut Size Tag" }) else { return }
        var f = FamilyDefinition(name: "Cut Size Tag", template: .tag)
        f.taggedCategories = Category.furnitureParts
        f.types = [FamilyTypeDefinition(name: "Mark and Cut Size", values: [:])]
        let w = "0.0105", h = "0.0035"
        f.annotationLines = [
            FamilyLine(shape: .line(FamilyPoint("-\(w)", "-\(h)"), FamilyPoint(w, "-\(h)"))), FamilyLine(shape: .line(FamilyPoint(w, "-\(h)"), FamilyPoint(w, h))),
            FamilyLine(shape: .line(FamilyPoint(w, h), FamilyPoint("-\(w)", h))), FamilyLine(shape: .line(FamilyPoint("-\(w)", h), FamilyPoint("-\(w)", "-\(h)"))),
            FamilyLine(shape: .line(FamilyPoint("-\(w)", "0"), FamilyPoint(w, "0"))),
        ]
        f.fills = [FamilyFill(points: [FamilyPoint("-\(w)", "-\(h)"), FamilyPoint(w, "-\(h)"), FamilyPoint(w, h), FamilyPoint("-\(w)", h)], isMasking: true)]
        f.labels = [
            FamilyLabel(position: FamilyPoint("0", "0.0017"), parameterName: "Mark", height: 0.0022, bold: true, sample: "P1"),
            FamilyLabel(position: FamilyPoint("0", "-0.0018"), parameterName: "Cut Size", height: 0.0018, sample: "11 3/4\" x 34 1/2\""),
        ]
        let fid = tx.create(.families, name: f.name, data: .family(f))
        tx.create(.elementTypes, name: "Mark and Cut Size", data: .type(TypeData(instanceCategory: .tags, familyID: fid, familyName: f.name)))
    }

    // MARK: Regeneration

    /// Joint elements whose parts are gone (or copies that lost them) go.
    public static func regenerate(_ tx: TransactionContext) {
        for e in tx.model.elements(.furnitureJoints) {
            guard let d = e.furnitureJoint else { continue }
            let ok = !d.parts.isEmpty && d.parts.allSatisfy { tx.model[$0]?.category.isFurniturePart == true } && (e.hostID.map(d.parts.contains) ?? true)
            if !ok { tx.delete(e.id) }
        }
    }
}
