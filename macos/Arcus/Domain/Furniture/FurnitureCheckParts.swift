import Foundation
import ArcusGeometry

// FM7: Fabricate ▸ Check Parts. Before cutting, the piece is checked for:
//   - parts too thin for their hardware or machining (hinge cups, cam locks, blind holes and grooves that would break
//     through the other face, dowels wider than the edge they go into);
//   - parts larger than their stock sheet (they can't be nested);
//   - parts without a material;
//   - parts that overlap without a joint (they would be cut as drawn and collide);
//   - edges that show (front, sides, top) but aren't banded on parts whose type is banded.
// Results are ordinary warnings (Severity, message, the elements to select), shown as Review Warnings shows them.

public enum FurnitureCheckParts {
    static let inch = 0.0254

    /// Edge names of a box part: L1/L2 are the long edges, W1/W2 the short ones; within each pair the first is the one
    /// facing front (−Y), then up (+Z), then left (−X).
    public enum Edge: String, CaseIterable, Sendable { case l1 = "L1", l2 = "L2", w1 = "W1", w2 = "W2" }

    /// The outward normals of a box part's four edges, by name.
    static func edges(_ f: FurnitureCNC.Frame) -> [Edge: (normal: Vec3, rect: (lo: Vec3, hi: Vec3))] {
        func score(_ n: Vec3) -> Double { -n.y * 4 + n.z * 2 - n.x }
        func face(_ a: FamilyAxis, max: Bool) -> (Vec3, (Vec3, Vec3)) {
            var lo = f.lo, hi = f.hi
            switch a {
            case .x: if max { lo.x = hi.x } else { hi.x = lo.x }
            case .y: if max { lo.y = hi.y } else { hi.y = lo.y }
            case .z: if max { lo.z = hi.z } else { hi.z = lo.z }
            }
            return (a.unit * (max ? 1 : -1), (lo, hi))
        }
        let longs = [face(f.w, max: false), face(f.w, max: true)].sorted { score($0.0) > score($1.0) }
        let shorts = [face(f.l, max: false), face(f.l, max: true)].sorted { score($0.0) > score($1.0) }
        return [.l1: (longs[0].0, longs[0].1), .l2: (longs[1].0, longs[1].1), .w1: (shorts[0].0, shorts[0].1), .w2: (shorts[1].0, shorts[1].1)]
    }

    /// Every check's findings, worst first.
    public static func check(_ m: BIMModel) -> [ModelWarning] {
        guard m.isFurniture else { return [] }
        var out: [ModelWarning] = []
        let parts = FurnitureFabrication.parts(m)
        let size = { (d: Double) in FurnitureSizeText.inches(d) }

        // Missing materials.
        for p in parts where p.materialID == nil || m[p.materialID] == nil {
            out.append(ModelWarning(.warning, code: "fm7.material", "\(p.mark) (\(p.name)) has no material: it isn't costed or nested.", elements: [p.elementID]))
        }

        // Larger than the stock.
        for g in FurnitureFabrication.nesting(m) {
            for it in g.result.oversize {
                let id = g.partKeys[it.key].flatMap { k in parts.first { $0.key == k }?.elementID }
                out.append(ModelWarning(.error, code: "fm7.stock",
                                        "\(it.label) (\(size(it.length)) x \(size(it.width))) is larger than its \(g.size.name) stock of \(g.title)\(it.grain != .none ? " with the grain" : "").",
                                        elements: id.map { [$0] } ?? []))
            }
        }

        // Too thin for hardware and machining.
        let byKey = Dictionary(parts.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var thin: Set<String> = []
        for e in FurnitureMachining.entries(m) {
            let key = "\(e.partID.raw)"
            let t: Double
            if let p = byKey[key] { t = p.thickness } else if let f = m[e.partID], f.category == .furnitureFronts { t = FurnitureFrontTypes.values(of: f, m).thickness } else { continue }
            let mark = byKey[key]?.mark ?? (m[e.partID]?.mark ?? "")
            var problem: String?
            switch e.op {
            case .drill(_, _, let dia, let depth):
                let isCup = e.label.hasPrefix("Hinge cup"), isCam = e.label == "Cam lock"
                if isCup, t < depth + 0.003 {
                    problem = "\(mark) is \(size(t)) thick: its \(e.label.lowercased()) (\(Int((depth * 1000).rounded())) mm deep) needs at least \(size(depth + 0.003))."
                } else if isCam, t < 0.016 - 1e-6 {
                    problem = "\(mark) is \(size(t)) thick: cam locks need panels 5/8\" (16 mm) or thicker."
                } else if e.label == "Dowel", dia > t * 0.6 + 1e-6, isEdge(e, m) {
                    problem = "\(mark) is \(size(t)) thick: a \(Int((dia * 1000).rounded())) mm dowel in its edge leaves too little wall."
                } else if depth < t - 1e-4, depth > t - 0.0015, !isEdge(e, m) {
                    problem = "\(mark): the \(e.label.lowercased()) (\(size(depth)) deep) almost breaks through its \(size(t)) thickness."
                }
            case .groove(_, _, _, _, let depth), .pocket(_, _, let depth):
                if depth > t - 0.003 { problem = "\(mark) is \(size(t)) thick: its \(e.label.lowercased()) (\(size(depth)) deep) leaves less than 1/8\"." }
            }
            if let problem, thin.insert(problem).inserted {
                out.append(ModelWarning(.warning, code: "fm7.thin", problem, elements: [e.partID]))
            }
        }

        // Overlapping without a joint, and unbanded visible edges.
        let sol = JointSolver.solve(m)
        let boxes: [(Element, FurnitureCNC.Frame)] = m.elements(Category.furnitureParts.filter { $0 != .furnitureEdgeProfiles && $0 != .furnitureForms })
            .filter { !$0.isType }.sorted { $0.id < $1.id }.compactMap { e in FurnitureCNC.frame(e, m).map { (e, $0) } }
        let tol = 0.001
        for i in boxes.indices {
            for j in boxes.indices where j > i {
                let (a, fa) = boxes[i], (b, fb) = boxes[j]
                let ox = min(fa.hi.x, fb.hi.x) - max(fa.lo.x, fb.lo.x), oy = min(fa.hi.y, fb.hi.y) - max(fa.lo.y, fb.lo.y), oz = min(fa.hi.z, fb.hi.z) - max(fa.lo.z, fb.lo.z)
                guard ox > tol, oy > tol, oz > tol else { continue }
                if sol.joint(JointKey(a.id, b.id)) != nil { continue }
                out.append(ModelWarning(.warning, code: "fm7.overlap", "\(label(a)) and \(label(b)) overlap but aren't joined.", elements: [a.id, b.id]))
            }
        }
        for (e, f) in boxes {
            let tv = FurniturePartTypes.values(of: e, m)
            guard tv.edgeMaterial != nil, let p = byKey["\(e.id.raw)"] else { continue }
            for (edge, info) in edges(f).sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let banded: Bool = switch edge { case .l1: p.banding.l1; case .l2: p.banding.l2; case .w1: p.banding.w1; case .w2: p.banding.w2 }
                // Backs face the wall and undersides the floor.
                guard !banded, info.normal.y < 0.5, info.normal.z > -0.5 else { continue }
                guard !covered(info.rect, normal: info.normal, by: boxes.filter { $0.0.id != e.id }.map(\.1)) else { continue }
                out.append(ModelWarning(.info, code: "fm7.banding", "\(p.mark): the \(direction(info.normal)) edge (\(edge.rawValue)) shows and isn't banded.", elements: [e.id]))
            }
        }
        out += ComponentChecks.check(m) // COMP: component compatibility rules and hardware overlaps
        return out.sorted { a, b in a.severity != b.severity ? a.severity > b.severity : a.message.localizedStandardCompare(b.message) == .orderedAscending }
    }

    static func label(_ e: Element) -> String { e.mark.isEmpty ? (e.furniturePartKind?.rawValue ?? "Part") : e.mark }

    /// Whether a machining operation enters through an edge (its axis lies in the part's face).
    static func isEdge(_ e: MachiningEntry, _ m: BIMModel) -> Bool {
        guard let el = m[e.partID], let f = FurnitureCNC.frame(el, m) else { return false }
        let axis: Vec3
        switch e.op { case .drill(_, let a, _, _), .groove(_, _, let a, _, _), .pocket(_, let a, _): axis = a }
        return abs(f.c(axis, f.t)) < 0.5
    }

    static func direction(_ n: Vec3) -> String {
        if n.y < -0.5 { return "front" }
        if n.z > 0.5 { return "top" }
        return n.x < 0 ? "left" : "right"
    }

    /// Whether another part touches the edge face over at least half its area.
    static func covered(_ r: (lo: Vec3, hi: Vec3), normal n: Vec3, by others: [FurnitureCNC.Frame]) -> Bool {
        let tol = 0.0008
        // The edge face's area along its two in-plane axes.
        let axes = FamilyAxis.allCases.filter { abs(n.dot($0.unit)) < 0.5 }
        func ext(_ a: FamilyAxis, _ lo: Vec3, _ hi: Vec3) -> (Double, Double) { (a == .x ? lo.x : (a == .y ? lo.y : lo.z), a == .x ? hi.x : (a == .y ? hi.y : hi.z)) }
        let area = axes.reduce(1.0) { acc, a in let e = ext(a, r.lo, r.hi); return acc * max(0, e.1 - e.0) }
        guard area > 1e-9 else { return true }
        var coveredArea = 0.0
        for o in others {
            // The other part must reach the edge face's plane (touch or overlap it).
            let na = FamilyAxis.allCases.first { abs(n.dot($0.unit)) > 0.5 }!
            let plane = ext(na, r.lo, r.hi).0, span = ext(na, o.lo, o.hi)
            guard span.0 <= plane + tol, span.1 >= plane - tol else { continue }
            let a = axes.reduce(1.0) { acc, ax in
                let e = ext(ax, r.lo, r.hi), q = ext(ax, o.lo, o.hi)
                return acc * max(0, min(e.1, q.1) - max(e.0, q.0))
            }
            coveredArea += a
        }
        return coveredArea >= area * 0.5
    }
}
