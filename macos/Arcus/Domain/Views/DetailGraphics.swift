import Foundation
import ArcusGeometry

// W2-ANNOT: spot annotations that follow their surface, repeating detail components and legend components.

public enum SpotGeometry {
    /// The surface under a plan point on a level: the top of a floor or pad, else a roof, else the level itself.
    /// Returns the elevation, the element and (floors) the slope and its downhill direction.
    public static func surface(at p: Vec2, levelID: ElementID?, _ model: BIMModel) -> (elevation: Double, reference: ElementID?, slope: Double, direction: Double) {
        for f in model.elements(.floors) + model.elements(.buildingPads) where f.levelID == levelID {
            guard let prof = SlabGeometry.profile(f), prof.contains(p), let (_, top) = SlabGeometry.planes(f, model) else { continue }
            let s = (top.a * top.a + top.b * top.b).squareRoot()
            let z = SlabGeometry.topZ(f, at: p, model) ?? top.z(at: p)
            return (z, f.id, s, atan2(top.b, top.a) + .pi)
        }
        for r in model.elements(.roofs) {
            if let z = RoofGeometry.topZ(r, at: p, model) { return (z, r.id, 0, 0) }
        }
        return (model.elevation(ofLevel: levelID), nil, 0, 0)
    }

    /// A spot with its value re-measured from the element it was placed on, so it follows edits of that element.
    /// Sections and elevations measure the picked point's height directly.
    public static func live(_ sp: SpotData, _ model: BIMModel, view: Element?) -> SpotData {
        var out = sp
        if AnnotationGeometry.isVertical(view) {
            if sp.kind == .elevation { out.elevation = sp.point.y }
            return out
        }
        guard let ref = model[sp.referenceID] else { return out }
        switch ref.data {
        case .slab:
            if let z = SlabGeometry.topZ(ref, at: sp.point, model) { out.elevation = z }
            if let (_, top) = SlabGeometry.planes(ref, model) {
                out.slope = (top.a * top.a + top.b * top.b).squareRoot()
                if out.slope > 1e-9 { out.slopeDirection = atan2(top.b, top.a) + .pi }
            }
        case .roof:
            if let z = RoofGeometry.topZ(ref, at: sp.point, model) { out.elevation = z }
        default:
            break
        }
        return out
    }
}

extension AnnotationRenderer {
    /// A detail component repeated along its path (from its location to `repeatEnd`), rotated to the path.
    static func repeatingDetail(_ e: Element, _ d: DetailComponentData, model: BIMModel, st: GStroke) -> GItem? {
        guard let end = d.repeatEnd, let ev = FamilyInstanceGeometry.evaluate(e, model) else { return nil }
        let path = end - d.location
        let len = path.length
        guard len > Tolerance.length else { return nil }
        let dir = path / len
        var local = Rect2.empty
        for f in ev.fills { local.include(f.polygon.bounds) }
        for l in ev.annotationLines + ev.planLines { local.include(l.curve.bounds) }
        let natural = local.isEmpty ? 0.1 : max(local.width, Tolerance.length * 10)
        let spacing = max(d.repeatSpacing ?? natural, len / 2000)
        let count = max(1, Int((len / spacing + 1e-6).rounded(.down)))
        var prims: [GPrimitive] = []
        for i in 0..<count {
            let c = d.location + dir * (Double(i) * spacing + spacing / 2)
            var t = Transform2.translation(c) * Transform2.rotation(dir.angle)
            if d.mirrored { t = t * Transform2.scale(1, -1) }
            for f in ev.fills { prims.append(.fill([f.polygon.transformed(t)], f.isMasking ? .mask : GFill(pattern: f.pattern, color: st.color, halftone: st.halftone))) }
            for l in ev.annotationLines + ev.planLines {
                let lst = GStroke(weight: l.weight, color: st.color, halftone: st.halftone)
                switch l.curve.transformed(t) {
                case .line(let sg): prims.append(.polyline([sg.start, sg.end], closed: false, lst))
                case .arc(let a): prims.append(.arc(a, lst))
                }
            }
        }
        let n = dir.perpendicular * max(local.isEmpty ? 0.05 : local.height / 2, Tolerance.length)
        let hit = Polygon2([d.location - n, end - n, end + n, d.location + n])
        return GItem(elementID: e.id, category: e.category, layer: .annotation, primitives: prims, hitPolygons: [hit])
    }

    /// A legend component: the plan symbol of a model type (doors, windows, furniture…), or a length of a wall, floor
    /// or roof type drawn with its layers.
    static func legendComponent(_ e: Element, _ d: DetailComponentData, model: BIMModel, st: GStroke) -> GItem? {
        guard let typeID = d.legendTypeID, let type = model[typeID], let td = type.typeData else { return nil }
        var prims: [GPrimitive] = []
        let t = Transform2.translation(d.location) * Transform2.rotation(d.rotation)
        let cut = GStroke(weight: 3, color: st.color, halftone: st.halftone), thin = GStroke(weight: 1, color: st.color, halftone: st.halftone)
        if let a = td.assembly, !a.layers.isEmpty {
            // Walls (plan cut, exterior up) and floors/roofs (section, top up): layers stacked over the legend length.
            let length = d.legendLength ?? 1.0
            let total = max(a.totalThickness, 0.01)
            var y = total / 2
            for (i, l) in a.layers.enumerated() where l.thickness > 0 {
                let r = Rect2(min: Vec2(0, y - l.thickness), max: Vec2(length, y))
                let mat = model[l.materialID]?.material
                let fill = GFill(pattern: mat.map { ObjectStyles.fillKind(for: $0.materialClass) } ?? .diagonalUp, color: RGBColor(0.35, 0.35, 0.35),
                                 background: .white, halftone: st.halftone)
                prims.append(.fill([Polygon2(r.corners.map(t.apply))], fill))
                if i > 0 { prims.append(.polyline([t.apply(Vec2(0, y)), t.apply(Vec2(length, y))], closed: false, thin)) }
                y -= l.thickness
            }
            let outline = Rect2(min: Vec2(0, -total / 2), max: Vec2(length, total / 2))
            prims.append(.polyline(outline.corners.map(t.apply), closed: true, cut))
            return GItem(elementID: e.id, category: e.category, layer: .annotation, primitives: prims, hitPolygons: [Polygon2(outline.corners.map(t.apply))])
        }
        // Family types: evaluate a stand-in instance at the component's placement.
        let probe = Element(id: e.id, category: td.instanceCategory, data: .component(ComponentData(location: d.location, rotation: d.rotation)), typeID: typeID)
        guard let ev = FamilyInstanceGeometry.evaluate(probe, model) else { return nil }
        for s in ev.solids where !s.isVoid && s.visibleInPlan {
            prims.append(.polyline(s.profile.outer.transformed(t).points, closed: true, cut))
        }
        for l in ev.planLines {
            switch l.curve.transformed(t) {
            case .line(let sg): prims.append(.polyline([sg.start, sg.end], closed: false, thin))
            case .arc(let a): prims.append(.arc(a, thin))
            }
        }
        if let o = ev.opening {
            // Doors and windows: the host wall's jambs either side of the opening.
            for x in [o.xMin, o.xMax] { prims.append(.polyline([t.apply(Vec2(x, -0.1)), t.apply(Vec2(x, 0.1))], closed: false, cut)) }
        }
        guard !prims.isEmpty else { return nil }
        return GItem(elementID: e.id, category: e.category, layer: .annotation, primitives: prims)
    }
}
