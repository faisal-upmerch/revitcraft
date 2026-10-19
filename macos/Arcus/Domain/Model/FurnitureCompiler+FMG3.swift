import Foundation
import ArcusGeometry

// FMG3: Load into Project for fronts on any face. Elevation swings are model lines on the face they're drawn on: the
// front's and the back's on XZ, the sides' on YZ, a canted face's in a small nested family turned to the face (model
// lines lie on XY, XZ or YZ). Swings shown only for some types (a door that is single or a pair by type) go in nested
// families too, shown by a yes/no parameter.

extension FurnitureCompiler {
    /// Adds a front's elevation swing lines to `f`.
    static func addElevationSwings(_ front: Element, _ m: BIMModel, to f: inout FamilyDefinition, visibility: String? = nil) {
        guard let g = FurnitureFronts.geometry(front, m) else { return }
        if g.face == .top { addLidSwings(front, m, to: &f, visibility: visibility); return }
        if g.frame.isIdentity, visibility == nil { f.modelLines += elevationSwings(front, m); return }
        let segs = FurnitureSwings.elevationLines(front, m)
        guard !segs.isEmpty else { return }
        if g.frame.isSquare, visibility == nil {
            f.modelLines += segs.map { squareModelLine($0.0, $0.1, g.frame) }
            return
        }
        // A nested family in the face's frame, placed turned to it.
        let mark = front.mark.isEmpty ? "Front \(front.id.raw)" : front.mark
        var nf = FamilyDefinition(name: "\(mark) Elevation Swing\(visibility.map { " (\($0))" } ?? "")", template: .genericModel)
        nf.types = [FamilyTypeDefinition(name: "Swing", values: [:])]
        nf.modelLines = segs.map { a, b in
            let la = g.frame.local(a), lb = g.frame.local(b)
            var l = FamilyModelLine(plane: .xz, offset: .expr(PartSolidContext.number(la.y)), start: FamilyPoint(PartSolidContext.number(la.x), PartSolidContext.number(la.z)),
                                    end: FamilyPoint(PartSolidContext.number(lb.x), PartSolidContext.number(lb.z)))
            l.subcategory = .elevationSwing
            l.visibleAt = [.medium, .fine]
            return l
        }
        var name = nf.name
        var k = 2
        while f.nestedFamily(named: name) != nil { name = "\(nf.name) \(k)"; k += 1 }
        nf.name = name
        f.nestedFamilies.append(nf)
        var inst = NestedFamilyInstance(familyName: nf.name, typeName: "Swing", x: .expr("0"), y: .expr("0"), z: .expr("0"),
                                        rotation: PartSolidContext.number(g.frame.angle * 180 / .pi), mirrored: false)
        inst.visibleAt = [.medium, .fine]
        inst.visibilityParameter = visibility
        f.nestedInstances.append(inst)
    }

    /// A model segment on a face square to the piece as a model line on XZ (front, back) or YZ (sides).
    static func squareModelLine(_ a: Vec3, _ b: Vec3, _ fr: BayFrame) -> FamilyModelLine {
        let n = PartSolidContext.number
        let onYZ = (fr.quarter ?? 0) % 2 == 1
        var l = onYZ ? FamilyModelLine(plane: .yz, offset: .expr(n(a.x)), start: FamilyPoint(n(a.y), n(a.z)), end: FamilyPoint(n(b.y), n(b.z)))
                     : FamilyModelLine(plane: .xz, offset: .expr(n(a.y)), start: FamilyPoint(n(a.x), n(a.z)), end: FamilyPoint(n(b.x), n(b.z)))
        l.subcategory = .elevationSwing
        l.visibleAt = [.medium, .fine]
        return l
    }

    /// A lid's swing as model lines on the side plane (YZ) through its middle: shown in the side elevations.
    static func addLidSwings(_ front: Element, _ m: BIMModel, to f: inout FamilyDefinition, visibility: String?) {
        let n = PartSolidContext.number
        var lines: [FamilyModelLine] = []
        for poly in FurnitureSwings.lidElevation(front, m) {
            for (a, b) in zip(poly, poly.dropFirst()) {
                var l = FamilyModelLine(plane: .yz, offset: .expr(n(a.x)), start: FamilyPoint(n(a.y), n(a.z)), end: FamilyPoint(n(b.y), n(b.z)))
                l.subcategory = .elevationSwing
                l.visibleAt = [.medium, .fine]
                lines.append(l)
            }
        }
        guard !lines.isEmpty else { return }
        guard let visibility else { f.modelLines += lines; return }
        let mark = front.mark.isEmpty ? "Front \(front.id.raw)" : front.mark
        var nf = FamilyDefinition(name: "\(mark) Lid Swing (\(visibility))", template: .genericModel)
        nf.types = [FamilyTypeDefinition(name: "Swing", values: [:])]
        nf.modelLines = lines
        f.nestedFamilies.append(nf)
        var inst = NestedFamilyInstance(familyName: nf.name, typeName: "Swing", x: .expr("0"), y: .expr("0"), z: .expr("0"), rotation: "0", mirrored: false)
        inst.visibilityParameter = visibility
        inst.visibleAt = [.medium, .fine]
        f.nestedInstances.append(inst)
    }

    /// A coordinate as a length formula, a sum of planes (a turned face's) included; `formulas` gives the offset
    /// formulas of planes not in `f` yet (Bay Divide lines).
    static func sumExpression(_ v: PartValue, _ f: FamilyDefinition, _ formulas: [String: String] = [:]) -> String {
        guard let p = v.plane, PlaneTerms.isSum(p) || f.referencePlanes.first(where: { $0.name == p }) == nil else { return lengthExpression(v, f) }
        let offsets = Dictionary(f.referencePlanes.map { ($0.name, $0.offset) }, uniquingKeysWith: { a, _ in a }).merging(formulas) { a, _ in a }
        return PlaneTerms.expression(p, offset: v.offset) { offsets[$0] } ?? "\(FurnitureFormLocks.num(v.value)) m"
    }
}

extension FurnitureCompiler {
    /// Doors whose Leaf Count follows a family parameter: the document regenerated with the door single and as a pair,
    /// and the yes/no parameter that shows each ("<Mark> Single" = Leaf Count is 1, "<Mark> Pair" otherwise), added to
    /// `f`. The variants keep the divider planes the fronts follow (`withDividerPlanes`).
    static func leafCountVariants(_ source: BIMModel, to f: inout FamilyDefinition) -> [ElementID: [(model: BIMModel, visibility: String)]] {
        var out: [ElementID: [(model: BIMModel, visibility: String)]] = [:]
        for front in source.elements(.furnitureFronts).sorted(by: { $0.id < $1.id }) {
            guard let d = front.furnitureFront, d.kind == .door, let p = d.leafCountParameter, let fp = f.parameter(named: p) else { continue }
            let mark = front.mark.isEmpty ? "Front \(front.id.raw)" : front.mark
            for n in [1, 2] {
                let tx = TransactionContext(model: source, name: "Leaf Count \(n)")
                // At a type that is this variant (a pair's leaves are framed or slab as they are at its sizes).
                if let setup = source.furnitureSetup, let t = setup.family.types.first(where: { t in
                    FurnitureFronts.leafCount(of: FamilyEvaluator.parameterValues(setup.family, typeName: t.name, units: source.units).values[p]) == n
                }), t.name != setup.currentType { try? FurnitureParameters.setCurrentType(t.name, in: tx) }
                tx.update(front.id) { $0.furnitureFront?.leafCountParameter = nil; $0.furnitureFront?.leafCount = n }
                guard let c = try? tx.commit() else { continue }
                let name = "\(mark) \(n == 1 ? "Single" : "Pair")"
                let condition = fp.type == .bool ? (n == 2 ? p : "not(\(p))") : (n == 1 ? "\(p) = 1" : "not(\(p) = 1)")
                if f.parameter(named: name) == nil { f.parameters.append(FamilyParameter(name: name, type: .bool, group: .other, formula: condition)) }
                out[front.id, default: []].append((withDividerPlanes(c.model), name))
            }
        }
        return out
    }

    /// Concealed hinges bore their cup at Fine: a void the shape of each Cup (per mounting), cutting the fronts only. A
    /// loaded piece's doors show a bore for every hinge its height shows (FurnitureCompiler+FM8's hinge sets).
    static func addCupBores(to f: inout FamilyDefinition, cutting fronts: [String]) {
        guard FurnitureHardware.kinds[f.name] == .hinge, !fronts.isEmpty, !f.solids.contains(where: { $0.name.hasPrefix("Cup Bore") }) else { return }
        for s in f.solids where (s.name == "Cup" || s.name.hasPrefix("Cup (")) && !s.isVoid {
            var v = s
            v.id = UUID().uuidString
            v.name = "Cup Bore"
            v.isVoid = true
            v.visibleAt = [.fine]
            v.materialParameter = nil
            v.cuts = fronts
            f.solids.append(v)
        }
    }
}
