import Foundation
import ArcusGeometry

// FM4: Load into Project for parts and forms. Every part becomes family solids bounded by the same planes it follows
// in the document (`FamilyBound.plane`), each face at an offset from a plane through a helper plane that follows it
// (by its formula, or a labelled dimension), dividers spaced by EQ dimensions, and the shapes that aren't boxes (legs,
// edge profiles) as nested families placed on the planes with their length bound to them. Each part type's material
// becomes a material parameter of the family, so the project can change it per type.

extension FurnitureCompiler {
    /// Adds the document's parts and forms to the compiled family `f` (its planes and parameters are already there).
    static func addParts(_ m: BIMModel, to f: inout FamilyDefinition) {
        let parts = Category.furnitureParts.flatMap { m.elements($0) }.filter { $0.furnitureEdgeProfile == nil }
        guard !parts.isEmpty else { return }
        var known = Set(f.referencePlanes.map(\.name))
        let ctx = PartSolidContext(symbolic: true, knownPlanes: known)
        var materialParams: [String: String] = [:] // material key → parameter name
        func materialParameter(_ id: ElementID?, label: String) -> String? {
            guard let id, m[id]?.material != nil else { return nil }
            let key = "\(label)|\(id.raw)"
            if let p = materialParams[key] { return p }
            var name = label.replacingOccurrences(of: "\"", with: " in").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces) + " Material"
            var k = 2
            while f.parameter(named: name) != nil { name = "\(label) Material \(k)"; k += 1 }
            f.parameters.append(FamilyParameter(name: name, type: .elementRef(.materials), group: .materials))
            for i in f.types.indices { f.types[i].values[name] = .ref(id) }
            materialParams[key] = name
            return name
        }

        // EQ dividers: a centre plane per divider, chained between the bay's two bounds by EQ dimensions.
        var overrides: [ElementID: Element] = [:]
        var eqPlanes: [(name: String, axis: FamilyAxis, at: Double)] = []
        var eqDims: [FamilyDimension] = []
        // FM8: a centre plane whose bounds follow formulas (or never move) gets its share of the bay as a formula, so the
        // dividers can't drift when the piece flexes (EQ chains of two or more were solved closest to the sketch).
        var eqFormulas: [String: String] = [:]
        let stable = stablePlanes(f)
        let dividers = m.elements(.furniturePanels).filter { $0.furniturePanel?.eq != nil }
        let groups = Dictionary(grouping: dividers) { e -> String in
            let q = e.furniturePanel!.eq!
            return "\(q.low)|\(q.high)|\(q.count)"
        }
        let r = FurnitureBoundResolver(m)
        for key in groups.keys.sorted() {
            guard let members = groups[key]?.sorted(by: { ($0.furniturePanel?.eq?.index ?? 0) < ($1.furniturePanel?.eq?.index ?? 0) }),
                  let first = members.first?.furniturePanel, let q = first.eq, let lo = r.resolve(q.low), let hi = r.resolve(q.high),
                  let lf = FurniturePartSolids.linearFrame(first.plane, first.start, first.end), members.count == q.count - 1 else { continue }
            func planeName(_ b: FurnitureBound, _ v: Double) -> String? {
                if case .plane(let n) = ctx.bound(PartValue(v, b)) { return n }
                return nil
            }
            guard let lowName = planeName(q.low, lo), let highName = planeName(q.high, hi) else { continue }
            let loExpr = stableExpression(PartValue(lo, q.low), f, stable), hiExpr = stableExpression(PartValue(hi, q.high), f, stable) // FM8
            var chain = [lowName]
            for e in members {
                guard var p = e.furniturePanel, let eq = p.eq else { continue }
                let c = lo + (hi - lo) * Double(eq.index) / Double(eq.count)
                let name = "\(e.mark.isEmpty ? "Divider \(e.id.raw)" : e.mark) Center"
                eqPlanes.append((name, lf.crossAxis, c))
                if let a = loExpr, let b = hiExpr { eqFormulas[name] = "(\(a)) + ((\(b)) - (\(a))) * \(eq.index) / \(eq.count)" } // FM8
                chain.append(name)
                let (fo, fi) = FurniturePartSolids.faceOffsets(p, thickness: FurniturePartTypes.values(of: e, m).thickness)
                let line = c - lf.across * (fo + fi) / 2
                let keys = lf.lineAlongU ? ["start.v", "end.v"] : ["start.u", "end.u"]
                for k in keys { p.bounds[k] = .plane(name, offset: line - c) }
                var copy = e
                copy.furniturePanel = p
                overrides[e.id] = copy
            }
            chain.append(highName)
            guard loExpr == nil || hiExpr == nil else { continue } // FM8: formula planes need no EQ chain
            for i in 1..<(chain.count - 1) { eqDims.append(.equality(chain[i - 1], chain[i], chain[i + 1])) }
        }
        for p in eqPlanes { known.insert(p.name) }
        ctx.knownPlanes = known

        var nestedNames: [String: String] = [:] // family content → nested family name
        for part in parts {
            let e = overrides[part.id] ?? part
            var ps = FurniturePartSolids.solids(e, m, ctx)
            for h in m.hosted(by: part.id) where h.furnitureEdgeProfile != nil { ps.placed += FurniturePartSolids.solids(h, m, ctx).placed }
            let label = m.type(of: e)?.name ?? (e.mark.isEmpty ? e.category.singularName : e.mark)
            for var s in ps.solids {
                if !s.isVoid { s.materialParameter = materialParameter(ps.materials[s.id] ?? nil, label: label) }
                f.solids.append(s)
            }
            for p in ps.placed {
                var nf = p.family
                // FM8: compared without the solids' ids (fresh for every part), so identical legs share one family.
                let keyed = nf.solids.map { var s = $0; s.id = ""; return s }
                let content = (try? JSONEncoder().encode(keyed)).map { String(decoding: $0, as: UTF8.self) + "|\(nf.types.map(\.values))" } ?? nf.name
                if let existing = nestedNames[content] {
                    nf.name = existing
                } else {
                    var name = nf.name
                    var k = 2
                    while f.nestedFamily(named: name) != nil { name = "\(nf.name) \(k)"; k += 1 }
                    nf.name = name
                    nestedNames[content] = name
                    f.nestedFamilies.append(nf)
                }
                var inst = NestedFamilyInstance(familyName: nf.name, typeName: nf.types.first?.name, x: ctx.bound(p.x), y: ctx.bound(p.y), z: ctx.bound(p.z),
                                                rotation: PartSolidContext.number(p.rotation), mirrored: p.mirrored)
                if let span = p.span {
                    let key = nf.parameter(named: "Height") != nil ? "Height" : "Length"
                    inst.bindings[key] = "(\(lengthExpression(span.end, f))) - (\(lengthExpression(span.start, f)))" // FM9: lengths on both sides
                }
                if nf.parameter(named: "Material") != nil, let mp = materialParameter(p.material, label: label) { inst.bindings["Material"] = mp }
                f.nestedInstances.append(inst)
            }
        }

        // Helper planes: each at its offset from the plane it follows.
        let axes = Dictionary(f.referencePlanes.map { ($0.name, $0.axis) }, uniquingKeysWith: { a, _ in a })
        let offsets = Dictionary(f.referencePlanes.map { ($0.name, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let origins = Set(f.referencePlanes.filter(\.definesOrigin).map(\.name))
        let constrained = Set(f.dimensions.flatMap { [$0.planeA, $0.planeB] + ($0.planeC.map { [$0] } ?? []) })
        var labelCount = 0
        for name in ctx.helpers.keys.sorted() {
            guard let h = ctx.helpers[name], let axis = axes[h.plane] ?? eqPlanes.first(where: { $0.name == h.plane })?.axis else { continue }
            let baseOffset = offsets[h.plane] ?? eqFormulas[h.plane] ?? PartSolidContext.number(eqPlanes.first { $0.name == h.plane }?.at ?? 0) // FM8
            let base = FurnitureBoundResolver(m).positions[h.plane] ?? eqPlanes.first { $0.name == h.plane }?.at ?? 0
            let isFormula = Double(baseOffset.trimmingCharacters(in: .whitespaces)) == nil
            // Origin planes never move; planes nothing constrains stay where they are.
            let follows = isFormula || origins.contains(h.plane) || (!constrained.contains(h.plane) && !eqPlanes.contains { $0.name == h.plane && eqFormulas[$0.name] == nil })
            if follows {
                // The helper's own formula follows the plane's (or both stay where they are).
                let formula = isFormula ? "(\(baseOffset)) \(lengthTerm(h.offset))" : PartSolidContext.number(base + h.offset)
                f.referencePlanes.append(FamilyReferencePlane(name: name, axis: axis, offset: formula, strength: .notAReference))
            } else {
                // A plane placed by dimensions: a labelled dimension keeps the helper at its distance.
                labelCount += 1
                let param = "Part Offset \(labelCount)"
                f.parameters.append(FamilyParameter(name: param, type: .length, group: .dimensions, formula: "\(PartSolidContext.number(abs(h.offset))) m"))
                f.referencePlanes.append(FamilyReferencePlane(name: name, axis: axis, offset: PartSolidContext.number(base + h.offset), strength: .notAReference))
                var d = FamilyDimension(planeA: h.plane, planeB: name, labelParameter: param)
                d.direction = h.offset >= 0 ? 1 : -1
                f.dimensions.append(d)
            }
        }
        for p in eqPlanes { f.referencePlanes.append(FamilyReferencePlane(name: p.name, axis: p.axis, offset: eqFormulas[p.name] ?? PartSolidContext.number(p.at), strength: .weak)) }
        f.dimensions += eqDims
    }

    /// A coordinate as an expression of the family's parameters (its plane's formula plus its offset), for bindings.
    static func expression(_ v: PartValue, _ f: FamilyDefinition) -> String {
        guard let p = v.plane, let plane = f.referencePlanes.first(where: { $0.name == p }) else { return PartSolidContext.number(v.value) }
        let o = plane.offset.trimmingCharacters(in: .whitespaces)
        if Double(o) != nil { return PartSolidContext.number(v.value) }
        return "(\(o)) \(lengthTerm(v.offset))"
    }

    /// "+ 0.0127 m" or "- 0.0127 m": an offset added to a length formula.
    static func lengthTerm(_ v: Double) -> String { "\(v < 0 ? "-" : "+") \(PartSolidContext.number(abs(v))) m" }
}
