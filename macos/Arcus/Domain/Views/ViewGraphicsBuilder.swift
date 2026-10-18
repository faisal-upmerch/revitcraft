import Foundation
import ArcusGeometry

/// Builds the 2D display list for plan, ceiling, elevation, section, drafting and legend views.
/// Pure function of (model snapshot, view, temporary visibility). Safe to run off the main actor.
public struct ViewGraphicsBuilder: Sendable {
    public let model: BIMModel
    public let view: Element
    public let resolver: VisibilityResolver
    public var isCancelled: @Sendable () -> Bool
    /// The project's Object Styles (read once per build).
    public let objectStyles: ObjectStyleSettings? // BL-VG

    public init(model: BIMModel, view: Element, temporary: TemporaryVisibility = TemporaryVisibility(), isCancelled: @escaping @Sendable () -> Bool = { false }) {
        self.model = model
        self.view = view
        self.resolver = VisibilityResolver(model: model, view: view, temporary: temporary)
        self.isCancelled = isCancelled
        self.objectStyles = model.projectInfo.objectStyles // BL-VG
    }

    public var data: ViewData { resolver.data }
    public var scale: Int { data.scale }
    /// Converts a paper length (meters) to view units.
    func paper(_ p: Double) -> Double { p * Double(scale) }

    public func build() -> ViewGraphics {
        var items: [GItem]
        switch data.kind {
        case .floorPlan, .structuralPlan, .areaPlan: items = PlanGraphics(builder: self, ceiling: false).build()
        case .ceilingPlan: items = PlanGraphics(builder: self, ceiling: true).build()
        case .elevation, .section, .detail: items = VerticalGraphics(builder: self).build()
        case .drafting, .legend: items = []
        case .threeD: items = ThreeDGraphics(builder: self).build()
        }
        items += AnnotationGraphics(builder: self).build()
        if data.kind != .threeD, data.visualStyle == .wireframe { items = Self.wireframe(items) } // BL-VG: 2D visual style
        if resolver.temp.revealConstraints { items += constraintItems() } // BL-VG: Reveal Constraints
        var extents = Rect2.empty
        for i in items where i.layer != .overlay { extents.include(i.bounds) }
        items += WorkPlanes.shownItems(self, extents: extents) // F2: Work Plane ▸ Show
        let crop = data.cropActive ? (data.cropRegion ?? extents) : nil
        if let crop, data.cropActive {
            items = clip(items, to: crop, annotationCrop: data.annotationCropActive ? crop.expanded(by: paper(data.annotationCropOffset)) : nil)
        }
        if data.cropVisible, let region = data.cropRegion ?? (extents.isEmpty ? nil : extents) {
            items.append(GItem(elementID: nil, category: .views, layer: .overlay,
                               primitives: [.polyline(region.corners, closed: true, GStroke(weight: 2, color: RGBColor(0.2, 0.2, 0.2)))],
                               selectable: false))
        }
        items.sort { $0.layer < $1.layer }
        return ViewGraphics(viewID: view.id, scale: scale, items: items, extents: extents, crop: crop, modelRevision: model.revision)
    }

    // MARK: Style helpers

    func stroke(_ c: Category, cut: Bool, _ o: GraphicOverride) -> GStroke { stroke(c, cut: cut, o, subcategory: nil) }

    /// Object style (project Object Styles over the built-in defaults) with the resolved view override on top.
    func stroke(_ c: Category, cut: Bool, _ o: GraphicOverride, subcategory: String?) -> GStroke { // BL-VG
        let s = ObjectStyles.effective(c, subcategory: subcategory, objectStyles)
        var st = GStroke(weight: cut ? s.cutWeight : s.projectionWeight, color: s.color, pattern: s.pattern, halftone: o.halftone ?? false)
        if cut {
            if let w = o.cutLineWeight { st.weight = w }
            if let col = o.cutLineColor { st.color = col }
            if let p = o.cutLinePattern { st.pattern = p }
        } else {
            if let w = o.projectionLineWeight { st.weight = w }
            if let col = o.projectionLineColor { st.color = col }
            if let p = o.projectionLinePattern { st.pattern = p }
        }
        return st
    }

    func cutFill(_ c: Category, materialID: ElementID?, _ o: GraphicOverride) -> GFill? {
        cutFill(c, materialID: materialID, o, type: nil) // W4-HATCH: material cut patterns, coarse fills and overrides
    }

    func surfaceFill(_ o: GraphicOverride) -> GFill? {
        var f: GFill
        if let id = o.surfacePatternID, let d = fillPattern(id) { // W4-HATCH: project pattern override
            f = GFill(fillPattern: d, color: o.surfaceColor ?? .gray, transparency: o.transparency ?? 0, halftone: o.halftone ?? false)
        } else {
            guard let p = o.surfacePattern ?? (o.surfaceColor != nil ? .solid : nil) else { return nil }
            f = GFill(pattern: p, color: o.surfaceColor ?? .gray, transparency: o.transparency ?? 0, halftone: o.halftone ?? false)
            if p != .solid, let e = FillPatternEdits.pattern(named: p.rawValue, model), let d = e.fillPattern { f.setPattern(d) }
        }
        return f
    }

    // MARK: Crop

    func clip(_ items: [GItem], to r: Rect2, annotationCrop: Rect2?) -> [GItem] {
        items.compactMap { item in
            let box: Rect2
            if item.layer == .annotation || item.layer == .overlay {
                guard let ac = annotationCrop else { return item }
                box = ac
            } else {
                box = r
            }
            if box.contains(item.bounds) { return item }
            if !box.intersects(item.bounds) { return nil }
            var copy = item
            copy.primitives = item.primitives.flatMap { clip($0, to: box) }
            copy.bounds = GItem.computeBounds(copy.primitives, hit: [])
            return copy.primitives.isEmpty ? nil : copy
        }
    }

    func clip(_ p: GPrimitive, to r: Rect2) -> [GPrimitive] { ViewGraphicsBuilder.clipPrimitive(p, to: r, chord: paper(0.0002)) }

    /// Clips a primitive to a rectangle (lines split, fills clipped, texts kept when their anchor is inside).
    public static func clipPrimitive(_ p: GPrimitive, to r: Rect2, chord: Double = 0.01) -> [GPrimitive] {
        switch p {
        case .polyline(let pts, let closed, let st):
            var out: [GPrimitive] = []
            let n = closed ? pts.count : pts.count - 1
            guard n > 0 else { return [] }
            var run: [Vec2] = []
            for i in 0..<n {
                let s = Segment2(pts[i], pts[(i + 1) % pts.count])
                if let c = s.clipped(to: r) {
                    if let last = run.last, last.isAlmostEqual(c.start) { run.append(c.end) } else {
                        if run.count >= 2 { out.append(.polyline(run, closed: false, st)) }
                        run = [c.start, c.end]
                    }
                } else if run.count >= 2 {
                    out.append(.polyline(run, closed: false, st)); run = []
                }
            }
            if run.count >= 2 { out.append(.polyline(run, closed: false, st)) }
            return out
        case .arc(let a, let st):
            if r.contains(a.bounds) { return [p] }
            return clipPrimitive(.polyline(a.tessellate(chordTolerance: chord), closed: false, st), to: r, chord: chord)
        case .fill(let polys, let f):
            let clipped = polys.compactMap { $0.clipped(to: r) }
            return clipped.isEmpty ? [] : [.fill(clipped, f)]
        case .text(let t):
            return r.contains(t.position) ? [p] : []
        }
    }
}

// MARK: - Shared model-space helpers

extension ViewGraphicsBuilder {
    /// Model elements drawn in model views.
    var modelCategories: Set<Category> {
        Set<Category>([.walls, .doors, .windows, .floors, .ceilings, .roofs, .stairs, .railings, .columns, .structuralColumns, .structuralFraming,
         .furniture, .casework, .genericModels, .plumbingFixtures, .specialtyEquipment, .topography, .buildingPads, .parking, .ifcReference, .ramps,
         .lightingFixtures, .electricalFixtures, .mechanicalEquipment, .planting, .entourage, .site, // W2-LIB
         .linkedModels]) // F67: linked models cut in sections and elevations with the host's elements
            .union(Category.f34Structural) // F34
    }

    func visibleModelElements() -> [(Element, GraphicOverride)] {
        var out: [(Element, GraphicOverride)] = []
        for c in modelCategories.sorted() {
            for e in model.elements(c) {
                if let o = resolver.resolve(e) { out.append((e, o)) }
            }
        }
        return out
    }

    func polylineItem(_ e: Element, _ pts: [[Vec2]], closed: Bool, _ st: GStroke, layer: GItem.Layer = .model) -> GItem {
        GItem(elementID: e.id, category: e.category, layer: layer, primitives: pts.map { .polyline($0, closed: closed, st) })
    }
}

/// Hidden-line projection of 3D views for PDF export and print (vector).
struct ThreeDGraphics {
    let builder: ViewGraphicsBuilder
    func build() -> [GItem] {
        guard let cam = builder.data.camera else { return [] }
        let fwd = (cam.target - cam.eye).normalized
        var right = fwd.cross(cam.up).normalized
        if right.lengthSquared == 0 { right = .unitX }
        let up = right.cross(fwd).normalized
        let proj = ViewProjection(origin: cam.eye, right: right, up: up, near: 0.01, far: 100_000)
        var inputs: [HLRInput] = []
        var tagMap: [Int: Element] = [:]
        let box = builder.data.sectionBoxActive ? builder.data.sectionBox : nil
        for (i, (e, _)) in builder.visibleModelElements().enumerated() {
            var mesh = Mesh()
            for p in GeometryCache.shared.parts(e, builder.model, detail: builder.detailLevel(e.category)) where p.isVisibleIn3D { mesh.append(p.mesh) } // BL-VG
            if let box, !box.intersects(mesh.bounds) { continue }
            guard !mesh.isEmpty else { continue }
            inputs.append(HLRInput(tag: i, mesh: mesh))
            tagMap[i] = e
        }
        let edges = HiddenLineRenderer.render(inputs, projection: proj, isCancelled: builder.isCancelled)
        var byTag: [Int: [HLREdge]] = [:]
        for e in edges { byTag[e.tag, default: []].append(e) }
        return byTag.keys.sorted().compactMap { tag in
            guard let e = tagMap[tag] else { return nil }
            let st = builder.stroke(e.category, cut: false, builder.resolver.resolve(e) ?? GraphicOverride())
            return GItem(elementID: e.id, category: e.category, layer: .model,
                         primitives: byTag[tag]!.map { .polyline([$0.segment.start, $0.segment.end], closed: false, st) })
        }
    }
}
