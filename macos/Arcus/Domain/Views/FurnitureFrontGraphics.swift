import Foundation
import ArcusGeometry

// FM5: 2D graphics of bays, bay separators and fronts, as casework drawings show them. Bays are like rooms: no lines
// of their own, a selectable region (their tag shows the name and the opening) in the Front elevation, or in plan for
// top-access bays. Separators are thin lines like room separators. Doors and flaps show their swing at Medium and
// Fine: the dashed hinge triangle on their face in elevations (its point at the hinges) and, for doors, the swing arc
// in plan. Drawer boxes are dashed in plan at Medium (Fine shows every hidden edge, FurniturePartGraphics).

extension ViewGraphicsBuilder {
    /// The fronts and hardware a plan cuts and sees with the parts.
    func fm5PlanParts() -> [(Element, GraphicOverride)] {
        guard model.isFurniture, !model.elements(.furnitureFronts).isEmpty || !model.elements(.furnitureHardware).isEmpty else { return [] }
        return visibleModelElements().filter { $0.0.category == .furnitureFronts || $0.0.category == .furnitureHardware }
    }

    func furnitureFrontGraphics() -> [GItem] {
        guard model.isFurniture else { return [] }
        let cats: Set<Category> = [.furnitureBays, .furnitureFronts, .furnitureBaySeparators]
        guard cats.contains(where: { !model.elements($0).isEmpty }) else { return [] }
        let visible = visibleModelElements().filter { cats.contains($0.0.category) }
        guard !visible.isEmpty else { return [] }
        if data.kind.isPlan { return frontPlanItems(visible) }
        if data.kind.isVerticalCut, let fr = VerticalGraphics.frame(data) {
            // Fronts and bays are seen in the views looking at their face (FMG3: any face, canted ones too).
            return frontElevationItems(visible, fr)
        }
        return []
    }

    func swingStroke(_ e: Element, _ o: GraphicOverride) -> GStroke {
        var st = stroke(e.category, cut: false, o)
        st.weight = 1
        st.pattern = .dash
        return st
    }

    // MARK: Elevations

    func frontElevationItems(_ visible: [(Element, GraphicOverride)], _ fr: VerticalGraphics.Frame) -> [GItem] {
        var items: [GItem] = []
        var face = BayFrame.front
        // FMG3: a point of the face being drawn (u, z at depth y in its frame) in the view.
        func view(_ x: Double, _ z: Double, y: Double) -> Vec2 { Vec2(fr.u(face.world(Vec2(x, y))), z) }
        for (e, o) in visible {
            switch e.data {
            case .furnitureBay(let b):
                face = BayFrame(b)
                guard b.face == .front, face.faces(fr.forward), let op = b.opening, b.division == nil else { continue }
                let r = Rect2(points: [view(op.x0, op.z0, y: op.y0), view(op.x1, op.z1, y: op.y0)])
                var prims: [GPrimitive] = []
                if let sf = surfaceFill(o) { prims.append(.fill([.rectangle(r)], sf)) }
                items.append(GItem(elementID: e.id, category: e.category, layer: .fills, primitives: prims, hitPolygons: [.rectangle(r)]))
            case .furnitureBaySeparator(let s):
                face = BayFrame(angle: s.facing ?? 0)
                guard s.face == .front, face.faces(fr.forward) else { continue }
                let y = model.elements(.furnitureBays).compactMap { $0.furnitureBay?.opening?.y0 }.min() ?? 0
                let a = view(s.start.x, s.start.y, y: y), c = view(s.end.x, s.end.y, y: y)
                items.append(lineItem(e, a, c, stroke(e.category, cut: false, o)))
            case .furnitureFront:
                guard detailLevel(e.category) != .coarse else { continue }
                let segs = FurnitureSwings.elevation(e, model)
                guard !segs.isEmpty, let g = FurnitureFronts.geometry(e, model), g.frame.faces(fr.forward) else { continue }
                face = g.frame
                let st = swingStroke(e, o)
                let y = g.outerFace
                items.append(GItem(elementID: e.id, category: e.category, layer: .model,
                                   primitives: segs.map { .polyline([view($0.start.x, $0.start.y, y: y), view($0.end.x, $0.end.y, y: y)], closed: false, st) }, hitPolygons: []))
            default: break
            }
        }
        return items
    }

    /// A thin selectable line (separators).
    func lineItem(_ e: Element, _ a: Vec2, _ c: Vec2, _ st: GStroke) -> GItem {
        let pad = paper(0.0012)
        let seg = Segment2(a, c)
        let hit: Polygon2
        if seg.isDegenerate { hit = .rectangle(Rect2(center: a, halfSize: Vec2(pad, pad))) }
        else { let n = seg.normal * pad, d = seg.direction * pad; hit = Polygon2([a - n - d, c - n + d, c + n + d, a + n - d]) }
        return GItem(elementID: e.id, category: e.category, layer: .model, primitives: seg.isDegenerate ? [] : [.polyline([a, c], closed: false, st)], hitPolygons: [hit])
    }

    // MARK: Plans

    func frontPlanItems(_ visible: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        let cutZ = model.elevation(ofLevel: view.levelID) + data.viewRange.cutOffset
        for (e, o) in visible {
            switch e.data {
            case .furnitureBay(let b):
                guard b.face == .top, let op = b.opening, b.division == nil else { continue }
                let r = Rect2(min: Vec2(op.x0, op.y0), max: Vec2(op.x1, op.y1))
                var prims: [GPrimitive] = []
                if let sf = surfaceFill(o) { prims.append(.fill([.rectangle(r)], sf)) }
                items.append(GItem(elementID: e.id, category: e.category, layer: .fills, primitives: prims, hitPolygons: [.rectangle(r)]))
            case .furnitureBaySeparator(let s):
                guard s.face == .top else { continue }
                items.append(lineItem(e, s.start, s.end, stroke(e.category, cut: false, o)))
            case .furnitureFront(let f):
                let level = detailLevel(e.category)
                guard level != .coarse, let g = FurnitureFronts.geometry(e, model), g.face == .front else { continue }
                // Fronts above the cut plane aren't in this plan.
                guard (g.leaves.map(\.v.0.value).min() ?? 0) <= cutZ else { continue }
                var prims: [GPrimitive] = []
                var swing = stroke(e.category, cut: false, o)
                swing.weight = 1
                for c in FurnitureSwings.plan(e, model) {
                    switch c {
                    case .line(let s): prims.append(.polyline([s.start, s.end], closed: false, swing))
                    case .arc(let a): prims.append(.arc(a, swing))
                    }
                }
                if f.kind == .drawer, level == .medium, let b = FurnitureFronts.drawerBox(e, model) {
                    var st = stroke(e.category, cut: false, o)
                    st.weight = 1
                    st.pattern = .hidden
                    let outer = Rect2(min: Vec2(b.x0, b.y0), max: Vec2(b.x0 + b.width, b.y0 + b.depth))
                    let inner = Rect2(min: Vec2(b.x0 + b.side, b.y0 + b.back), max: Vec2(b.x0 + b.width - b.side, b.y0 + b.depth - b.back))
                    prims.append(.polyline(outer.corners.map(g.frame.world), closed: true, st)) // FMG3: turned with the face
                    if inner.width > 0, inner.height > 0 { prims.append(.polyline(inner.corners.map(g.frame.world), closed: true, st)) }
                }
                if !prims.isEmpty { items.append(GItem(elementID: e.id, category: e.category, layer: .model, primitives: prims, hitPolygons: [])) }
            default: break
            }
        }
        return items
    }
}
