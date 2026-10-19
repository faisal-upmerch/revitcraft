import Foundation
import ArcusGeometry

// COMP: the 2D symbols of placed components in plans, elevations and sections, at the view's detail level for Furniture
// Hardware (Coarse shows symbols where the solids are hidden). A symbol is drawn in the plane its view names (Face:
// the host face; Top: seen from above the face; Side: seen from its side), placed with the instance, and shows in the
// views that look at that plane.

extension ViewGraphicsBuilder {
    func componentSymbolGraphics() -> [GItem] {
        let placed = model.elements(.furnitureHardware).filter { !$0.isType && $0.params[ComponentKit.definitionParam] != nil }
        guard !placed.isEmpty, data.kind.isPlan || data.kind.isVerticalCut else { return [] }
        let frame = data.kind.isVerticalCut ? VerticalGraphics.frame(data) : nil
        if data.kind.isVerticalCut, frame == nil { return [] }
        let look: Vec3 = frame.map { Vec3($0.forward, z: 0) } ?? Vec3(0, 0, -1)
        let visible = Set(visibleModelElements().map(\.0.id))
        let level = detailLevel(.furnitureHardware)
        var items: [GItem] = []
        for e in placed where visible.contains(e.id) {
            guard let d = ComponentDocument.definition(of: e, model), !d.symbols.isEmpty, let place = ComponentGeometry.placement(e, model),
                  let ev = FamilyInstanceGeometry.evaluate(e, model) else { continue }
            let w = place.world
            func view(_ p: Vec3) -> Vec2 { frame.map { $0.uv(p) } ?? p.xy }
            var prims: [GPrimitive] = []
            for s in d.symbols where s.levels.contains(level) {
                let (lift, normal): ((Vec2) -> Vec3, Vec3) = switch s.view {
                case .face: ({ Vec3($0.x, $0.y, 0) }, Vec3(0, 0, 1))
                case .top: ({ Vec3($0.x, 0, $0.y) }, Vec3(0, 1, 0))
                case .side: ({ Vec3(0, $0.y, $0.x) }, Vec3(1, 0, 0))
                }
                let n = (w.apply(normal) - w.apply(.zero)).normalized
                guard abs(n.dot(look)) > 0.9 else { continue }
                var st = stroke(e.category, cut: false, GraphicOverride())
                st.weight = 1
                if s.dashed { st.pattern = .hidden }
                for sh in s.shapes {
                    for (a, b) in ComponentSymbols.segments(sh, ev) {
                        prims.append(.polyline([view(w.apply(lift(a))), view(w.apply(lift(b)))], closed: false, st))
                    }
                }
            }
            if !prims.isEmpty { items.append(GItem(elementID: e.id, category: e.category, layer: .model, primitives: prims, hitPolygons: [])) }
        }
        return items
    }
}

/// Evaluated symbol geometry.
public enum ComponentSymbols {
    /// Line segments of a symbol shape for an evaluated family (arcs and circles as chords).
    public static func segments(_ s: ComponentSymbolShape, _ ev: EvaluatedFamily) -> [(Vec2, Vec2)] {
        func v(_ e: FamilyBound) -> Double {
            switch e {
            case .expr(let x): return ComponentChecks.value(x, ev) ?? 0
            case .plane(let p): return ev.planes[p] ?? 0
            }
        }
        func p(_ q: FamilyPoint) -> Vec2 { Vec2(v(q.x), v(q.y)) }
        func poly(_ pts: [Vec2], closed: Bool) -> [(Vec2, Vec2)] {
            var out = zip(pts, pts.dropFirst()).map { ($0, $1) }
            if closed, pts.count > 2, let f = pts.first, let l = pts.last { out.append((l, f)) }
            return out
        }
        func arc(_ c: Vec2, _ r: Double, _ a0: Double, _ sweep: Double) -> [Vec2] {
            let n = max(8, Int(abs(sweep) / 10))
            return (0...n).map { k in let a = (a0 + sweep * Double(k) / Double(n)) * .pi / 180; return c + Vec2(cos(a), sin(a)) * r }
        }
        func num(_ x: String, _ d: Double) -> Double { ComponentChecks.value(x, ev) ?? d }
        switch s {
        case .line(let a, let b): return [(p(a), p(b))]
        case .polyline(let pts, let closed): return poly(pts.map(p), closed: closed)
        case .rectangle(let a, let b):
            let x = p(a), y = p(b)
            return poly([x, Vec2(y.x, x.y), y, Vec2(x.x, y.y)], closed: true)
        case .circle(let c, let r): return poly(arc(p(c), num(r, 0), 0, 360), closed: false)
        case .arc(let c, let r, let a0, let sw): return poly(arc(p(c), num(r, 0), num(a0, 0), num(sw, 90)), closed: false)
        }
    }
}
