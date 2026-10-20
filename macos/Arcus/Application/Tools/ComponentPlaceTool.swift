import Foundation
import ArcusGeometry
import ArcusDomain

// COMP: Place Component. Like Revit's face-based component placement: the faces the component can go on are outlined
// in the view (doors, drawer fronts, panels, shelves, bays…), the face under the pointer is highlighted and the
// component previews on it, snapping to its alignment points (Center, edges, corners at the rule's offsets). A click
// places it, hosted, so it follows the host's size; Space turns it 90°. The Options Bar has the face, alignment,
// At Alignment, offsets and rotation. Works in plans, elevations and sections (from the face seen) and in 3D (on the
// face under the pointer). Stays active for more instances, on other hosts too; Esc ends it.

/// The face of a host under the pointer, and where on it.
public struct ComponentTarget: Sendable {
    public var host: Element
    public var face: ComponentHostFace
    /// Face coordinates (a, b) of the pointer.
    public var point: Vec2
}

/// Maps between a view's 2D coordinates and the model: plans (x, y from above), elevations and sections (u along the
/// view's right vector, z).
public struct ComponentViewMap: Sendable {
    public var isPlan: Bool
    public var origin: Vec3
    public var right: Vec2
    /// The direction the view looks (plans: down).
    public var forward: Vec3

    public init?(_ v: ViewData?) {
        guard let v else { return nil }
        if v.kind.isPlan { isPlan = true; origin = .zero; right = Vec2(1, 0); forward = Vec3(0, 0, -1); return }
        guard v.kind.isVerticalCut, let o = v.planeOrigin, let r = v.rightVector?.normalized, let d = v.viewDirection?.normalized else { return nil }
        isPlan = false; origin = o; right = r; forward = Vec3(d, z: 0)
    }

    public func toView(_ w: Vec3) -> Vec2 { isPlan ? w.xy : Vec2((w.xy - origin.xy).dot(right), w.z) }
    /// The pointer's ray: a point toward the viewer and the direction into the view.
    public func ray(_ p: Vec2) -> (Vec3, Vec3) {
        if isPlan { return (Vec3(p.x, p.y, 1000), forward) }
        return (Vec3(origin.xy + right * p.x, z: p.y) - forward * 100, forward)
    }
}

@MainActor
public final class ComponentPlaceTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .componentPlace
    public private(set) var definition: ComponentDefinition
    public private(set) var typeName: String
    /// Instance values of a preset.
    public var values: [String: ParamValue]
    /// nil = the face under the pointer (among the faces the component goes on).
    public var face: ComponentFace?
    public var alignment: ComponentAlignment
    /// Places at the alignment's point on the face the pointer is on (else where the pointer is, measured from it).
    public var atAlignment = true
    public var offsetX: Double
    public var offsetY: Double
    public var rotation = 0.0
    public var vertical: Bool
    let map: ComponentViewMap?
    var target: ComponentTarget?
    var last: ToolInput?
    var outlines: [GPrimitive]?
    var outlinesStamp: Int?
    /// Called with the ids of each placement (the panel records Recently Used).
    public var placed: (([ElementID]) -> Void)?

    public init(ctx: ToolContext, definition: ComponentDefinition, typeName: String? = nil, values: [String: ParamValue] = [:], alignment: ComponentAlignment? = nil) {
        self.definition = definition
        self.typeName = typeName ?? definition.defaultType?.name ?? ""
        self.values = values
        self.alignment = alignment ?? definition.placement.alignment
        offsetX = definition.placement.offsetX
        offsetY = definition.placement.offsetY
        vertical = definition.placement.vertical
        map = ComponentViewMap(ctx.viewData)
        super.init(ctx: ctx)
    }

    public var title: String { "Place Component" }
    public var prompt: String {
        if map == nil, ctx.viewData?.kind != .threeD { return "Place components in a plan, an elevation, a section or a 3D view." }
        let on = definition.placement.hosts.prefix(3).map { $0.rawValue.lowercased() }.joined(separator: ", ")
        return target == nil ? "Point at a \(on) to place \(definition.name)." : "Click to place \(definition.name). Space turns it."
    }

    // MARK: Options Bar

    var faceChoices: [String] { ["Auto"] + definition.placement.faces.filter { $0 != .any }.map(\.rawValue) }
    var alignmentChoices: [String] {
        let rule = definition.placement.alignments
        return (rule + ComponentAlignment.allCases.filter { !rule.contains($0) }).map(\.rawValue)
    }

    public var options: [ToolOption] {
        [ToolOption(id: "face", label: "Face", kind: .choice(faceChoices), value: .text(face?.rawValue ?? "Auto")),
         ToolOption(id: "alignment", label: "Alignment", kind: .choice(alignmentChoices), value: .text(alignment.rawValue)),
         ToolOption(id: "atAlignment", label: "At Alignment", kind: .bool, value: .bool(atAlignment)),
         ToolOption(id: "offsetX", label: "Offset X", kind: .length, value: .double(offsetX)),
         ToolOption(id: "offsetY", label: "Offset Y", kind: .length, value: .double(offsetY)),
         ToolOption(id: "rotation", label: "Rotation", kind: .angle, value: .double(rotation))]
    }

    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "face": face = value.textValue.flatMap(ComponentFace.init(rawValue:))
        case "alignment": if let a = value.textValue.flatMap(ComponentAlignment.init(rawValue:)) { alignment = a }
        case "atAlignment": atAlignment = value.boolValue ?? true
        case "offsetX": offsetX = value.doubleValue ?? offsetX
        case "offsetY": offsetY = value.doubleValue ?? offsetY
        case "rotation": rotation = value.doubleValue ?? rotation
        default: break
        }
        if let l = last { pointerMoved(l) }
    }

    /// Switches the component (the panel's selection or the Type Selector changed while placing).
    public func use(_ d: ComponentDefinition, typeName t: String? = nil, values v: [String: ParamValue] = [:]) {
        let changed = d.id != definition.id
        definition = d
        typeName = t ?? d.defaultType?.name ?? ""
        values = v
        if changed {
            alignment = d.placement.alignment; offsetX = d.placement.offsetX; offsetY = d.placement.offsetY; vertical = d.placement.vertical
            outlines = nil
        }
        if let l = last { pointerMoved(l) }
    }

    /// The Type Selector picked a loaded component type: place that.
    func adoptTypeSelector() {
        guard let t = ctx.currentTypes[.furnitureHardware], let te = ctx.model[t], te.isType, te.name != typeName || ComponentDocument.definitionID(of: te, ctx.model) != definition.id,
              let d = ComponentDocument.definition(of: te, ctx.model), d.type(named: te.name) != nil else { return }
        definition = d
        typeName = te.name
    }

    // MARK: Targets

    var settings: ComponentSettings {
        ComponentSettings(face: face ?? definition.placement.faces.first ?? .front, alignment: alignment, offsetX: offsetX, offsetY: offsetY,
                          offsetZ: definition.placement.offsetZ, rotation: rotation, vertical: vertical)
    }

    /// Hosts the component goes on, with the faces it can take.
    func candidates() -> [(Element, [ComponentHostFace])] {
        let m = ctx.model
        let cats: [Category] = [.furnitureFronts, .furnitureBays, .furniturePanels, .furnitureShelves, .furnitureLegs, .furnitureRails, .furnitureForms, .walls]
        let allowed = face.map { [$0] } ?? definition.placement.faces
        return cats.flatMap { m.elements($0) }.filter { !$0.isType }.compactMap { e in
            guard let k = ComponentPlacement.hostKind(e, m), ComponentPlacement.accepts(definition, k) else { return nil }
            if e.furnitureBay?.division != nil { return nil }
            let fs = allowed.contains(.any) ? ComponentPlacement.faces(e, m) : allowed.compactMap { ComponentPlacement.face(e, $0, m) }
            return fs.isEmpty ? nil : (e, fs)
        }
    }

    /// The face under a view point: the frontmost face seen from the view whose outline holds it (bays: their opening).
    func target(at p: Vec2) -> ComponentTarget? {
        guard let map else { return nil }
        let (r0, dir) = map.ray(p)
        var best: (ComponentTarget, Double)?
        for (host, faces) in candidates() {
            for f in faces {
                let facing = -f.n.dot(dir)
                let isBay = host.furnitureBay != nil
                var q: Vec3
                if facing > 0.5 {
                    // The pointer's ray meets the face's plane.
                    let t = (f.origin - r0).dot(f.n) / dir.dot(f.n)
                    q = r0 + dir * t
                } else if isBay {
                    // An inside face of a bay seen across: the pointer's position along the face, its depth in the middle.
                    q = f.origin
                    let along = f.u.dot(dir), up = f.v.dot(dir)
                    let onPlane = r0 + dir * ((f.origin - r0).dot(dir))
                    if abs(along) < 0.5 { q = q + f.u * (onPlane - f.origin).dot(f.u) }
                    if abs(up) < 0.5 { q = q + f.v * (onPlane - f.origin).dot(f.v) }
                } else { continue }
                let l = f.local(q)
                // Bays: the pointer must be inside the opening seen from the view.
                if isBay {
                    guard let o = host.furnitureBay?.opening else { continue }
                    let fr = BayFrame(host.furnitureBay!)
                    let corners = [Vec3(o.x0, o.y0, o.z0), Vec3(o.x1, o.y0, o.z0), Vec3(o.x1, o.y0, o.z1), Vec3(o.x0, o.y0, o.z1), Vec3(o.x0, o.y1, o.z0), Vec3(o.x1, o.y1, o.z0)]
                        .map { map.toView(fr.world($0)) }
                    guard Rect2(points: corners).contains(p) else { continue }
                } else {
                    guard f.contains(l.x, l.y, margin: ctx.pixel * 2) else { continue }
                }
                let depth = q.dot(dir) + (isBay ? 0.002 : 0) // a front before its bay
                if best == nil || depth < best!.1 - 1e-6 {
                    best = (ComponentTarget(host: host, face: f, point: Vec2(min(max(l.x, -f.width / 2), f.width / 2), min(max(l.y, -f.height / 2), f.height / 2))), depth)
                }
            }
        }
        return best?.0
    }

    /// The face under the pointer in a 3D view (the picked element and the surface point).
    func target3D(_ i: ToolInput) -> ComponentTarget? {
        guard let hitID = i.hit, let sp = i.surfacePoint, var host = ctx.model[hitID] else { return nil }
        if host.category == .furnitureHardware, let h = ctx.model[host.hostID] { host = h }
        guard let k = ComponentPlacement.hostKind(host, ctx.model), ComponentPlacement.accepts(definition, k) else { return nil }
        let allowed = face.map { [$0] } ?? definition.placement.faces
        guard let f = ComponentPlacement.nearestFace(host, to: sp, ctx.model, among: allowed) else { return nil }
        let l = f.local(sp)
        return ComponentTarget(host: host, face: f, point: Vec2(min(max(l.x, -f.width / 2), f.width / 2), min(max(l.y, -f.height / 2), f.height / 2)))
    }

    /// Where the component goes on the target: the alignment's point, a nearby snap point, or the pointer.
    func placement(_ t: ComponentTarget) -> (point: Vec2, settings: ComponentSettings) {
        var s = settings
        s.face = t.face.face
        if atAlignment { return (ComponentPlacement.anchor(t.face, s), s) }
        // Snap to the alignment points within 3/4".
        let tol = max(0.75 * 0.0254, ctx.pixel * 8)
        var snaps: [(Vec2, ComponentAlignment)] = ComponentAlignment.allCases.filter { $0 != .full }.map { a in
            var x = s; x.alignment = a
            return (ComponentPlacement.anchor(t.face, x), a)
        }
        snaps += definition.placement.snapPoints.compactMap { sp in
            let ev = FamilyEvaluator.evaluate(definition.family, typeName: typeName)
            guard let x = ComponentChecks.value(sp.x, ev), let y = ComponentChecks.value(sp.y, ev) else { return nil }
            return (Vec2(x, y), s.alignment)
        }
        if let near = snaps.min(by: { $0.0.distance(to: t.point) < $1.0.distance(to: t.point) }), near.0.distance(to: t.point) <= tol {
            var x = s; x.alignment = near.1
            return (near.0, x)
        }
        return (t.point, ComponentPlacement.settings(s, at: t.point, on: t.face))
    }

    // MARK: Preview

    func faceOutline(_ f: ComponentHostFace) -> [Vec2]? {
        guard let map else { return nil }
        let pts = [f.point(-f.width / 2, -f.height / 2), f.point(f.width / 2, -f.height / 2), f.point(f.width / 2, f.height / 2), f.point(-f.width / 2, f.height / 2)].map(map.toView)
        return Rect2(points: pts).width > ctx.pixel || Rect2(points: pts).height > ctx.pixel ? pts : nil
    }

    func compatibleOutlines() -> [GPrimitive] {
        if let o = outlines, outlinesStamp == ctx.model.contentStamp.hashValue { return o }
        guard let map else { return [] }
        let st = GStroke(weight: 1, color: RGBColor(0.25, 0.55, 0.9), pattern: .dash)
        var out: [GPrimitive] = []
        for (_, faces) in candidates() {
            for f in faces where -f.n.dot(map.forward) > 0.5 {
                if let pts = faceOutline(f) { out.append(.polyline(pts, closed: true, st)) }
            }
        }
        outlines = out
        outlinesStamp = ctx.model.contentStamp.hashValue
        return out
    }

    /// The component's outline in the view at a placement (the hull of its solids seen from the view).
    func componentOutline(_ t: ComponentTarget, _ p: Vec2, _ s: ComponentSettings) -> [Vec2] {
        guard let map else { return [] }
        let levelZ = ctx.model.elevation(ofLevel: ctx.model.levels.first?.id)
        let (data, extra) = ComponentPlacement.data(definition, on: t.face, at: p, s, ctx.model, levelZ: levelZ)
        var probe = Element(id: ElementID(UInt64.max - 2), category: .furnitureHardware, data: .component(data), levelID: ctx.model.levels.first?.id)
        for (k, v) in values.merging(extra, uniquingKeysWith: { _, b in b }) { probe.params[Parameters.familyParamID(k)] = v }
        guard let place = ComponentGeometry.placement(probe, ctx.model) else { return [] }
        let inst = Parameters.familyInstanceValues(probe)
        let ev = FamilyEvaluator.evaluate(definition.family, typeName: typeName, instance: inst)
        var pts: [Vec2] = []
        for sol in ev.solids where !sol.isVoid {
            pts += sol.familyMesh.transformed(place.world).positions.map(map.toView)
        }
        return Self.hull(pts)
    }

    /// Convex hull (monotone chain), counterclockwise.
    static func hull(_ p: [Vec2]) -> [Vec2] {
        let s = p.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard s.count > 2 else { return s }
        func cross(_ o: Vec2, _ a: Vec2, _ b: Vec2) -> Double { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [Vec2] = [], upper: [Vec2] = []
        for q in s { while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }; lower.append(q) }
        for q in s.reversed() { while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }; upper.append(q) }
        return Array(lower.dropLast() + upper.dropLast())
    }

    public func pointerMoved(_ i: ToolInput) {
        last = i
        adoptTypeSelector()
        preview = ToolPreview()
        let is3D = ctx.viewData?.kind == .threeD
        target = is3D ? target3D(i) : target(at: i.rawPoint)
        if !is3D { preview.primitives = compatibleOutlines() }
        guard let t = target else {
            preview.cursor = placesOnFloor ? .crosshairPlus : .notAllowed
            if placesOnFloor {
                let ev = FamilyEvaluator.evaluate(definition.family, typeName: typeName, instance: values)
                let rot = Transform3(Transform2.translation(i.point) * Transform2.rotation(rotation), z: 0)
                let pts = ev.solids.filter { !$0.isVoid }.flatMap { $0.familyMesh.transformed(rot).positions.map(\.xy) }
                let h = Self.hull(pts)
                if h.count >= 2 { preview.primitives.append(.polyline(h, closed: true, ctx.previewHeavy)) }
            }
            return
        }
        let (p, s) = placement(t)
        if !is3D {
            if let pts = faceOutline(t.face) {
                preview.primitives.append(.fill([Polygon2(pts)], GFill(pattern: .solid, color: RGBColor(0.25, 0.5, 0.8), transparency: 0.85)))
                preview.primitives.append(.polyline(pts, closed: true, ctx.previewStroke))
            }
            let outline = componentOutline(t, p, s)
            if outline.count >= 2 { preview.primitives.append(.polyline(outline, closed: true, ctx.previewHeavy)) }
        }
        preview.cursor = .crosshairPlus
    }

    /// Floor items (legs, bases, casters, free-standing components) go on the level where there's no host under the
    /// pointer, in plans.
    var placesOnFloor: Bool { map?.isPlan == true && definition.placement.hosts.contains(.floor) }

    public func pointerDown(_ i: ToolInput) {
        pointerMoved(i)
        if target == nil, placesOnFloor {
            let d = definition, tn = typeName, v = values, p = i.point
            let z = ctx.levelElevation
            var ids: [ElementID] = []
            ctx.session.perform("Place \(d.name)") { tx in
                ids = try ComponentPlacement.place(d, typeName: tn, hostID: nil, levelPoint: Vec3(p, z: z), values: v, in: tx)
                if let id = ids.first, self.rotation != 0 { tx.update(id) { $0.component?.rotation = self.rotation } }
            }
            if let e = ctx.session.lastError { message(e.message); return }
            ctx.session.selection.select(ids)
            placed?(ids)
            return
        }
        guard let t = target else { message(prompt); return }
        let (p, s) = placement(t)
        let d = definition, tn = typeName, v = values, hostID = t.host.id
        var ids: [ElementID] = []
        ctx.session.perform("Place \(d.name)") { tx in
            ids = try ComponentPlacement.place(d, typeName: tn, hostID: hostID, settings: s, at: atAlignment ? nil : p, values: v, in: tx)
        }
        if let e = ctx.session.lastError { message(e.message); return }
        let warnings = ComponentChecks.requirements(d, typeName: tn, host: t.host, kind: ComponentPlacement.hostKind(t.host, ctx.model) ?? .anyPart, face: s.face, ctx.model)
        if let w = warnings.first { message(w.message) }
        ctx.session.selection.select(ids)
        placed?(ids)
        outlines = nil
    }

    public func spaceBar() {
        rotation += .pi / 2
        if rotation >= 2 * .pi - 1e-9 { rotation = 0 }
        if let l = last { pointerMoved(l) }
    }
    public func escape() -> EscapeResult { .exitTool }
}
