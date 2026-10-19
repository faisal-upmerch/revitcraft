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
