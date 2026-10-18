import Foundation
import ArcusGeometry

/// Views in which a piece of family geometry is shown (the family editor's visibility settings).
public struct FamilyViewSet: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let threeD = FamilyViewSet(rawValue: 1)
    /// Elevations and sections looking at the family's front or back.
    public static let frontBack = FamilyViewSet(rawValue: 2)
    /// Elevations and sections looking at the family's left or right side.
    public static let leftRight = FamilyViewSet(rawValue: 4)
    public static let all: FamilyViewSet = [.threeD, .frontBack, .leftRight]
}

/// A piece of element geometry with its material, for shading, quantities and IFC.
public struct MeshPart: Sendable {
    public var mesh: Mesh
    public var materialID: ElementID?
    public var subcategory: FamilySubcategory
    /// Views that show this part (family visibility settings); quantities always count every part.
    public var views: FamilyViewSet
    /// World plan direction of the family's front (+Y) axis, for front/back vs left/right visibility.
    public var frontAxis: Vec2?
    /// F67: a display colour that replaces the material colour (linked models, point clouds, decal images).
    public var color: RGBColor? = nil
    /// F67: visual styles that show this part in 3D views (decal images show only in Realistic).
    public var styles: MeshPartStyles = .all
    public init(mesh: Mesh, materialID: ElementID?, subcategory: FamilySubcategory = .general, views: FamilyViewSet = .all, frontAxis: Vec2? = nil) {
        self.mesh = mesh; self.materialID = materialID; self.subcategory = subcategory; self.views = views; self.frontAxis = frontAxis
    }

    /// Shown in 3D views.
    public var isVisibleIn3D: Bool { views.contains(.threeD) }

    /// Shown in an elevation or section looking along the plan direction `d`.
    public func isVisible(lookingAlong d: Vec2) -> Bool {
        guard views != .all else { return true }
        guard let f = frontAxis, d.lengthSquared > 0 else { return views.contains(.frontBack) || views.contains(.leftRight) }
        let dir = d.normalized
        return abs(dir.dot(f)) >= abs(dir.cross(f)) ? views.contains(.frontBack) : views.contains(.leftRight)
    }
}

/// F67: which 3D visual styles show a mesh part.
public enum MeshPartStyles: Sendable {
    case all, realisticOnly, exceptRealistic
    public func shows(realistic: Bool) -> Bool {
        switch self {
        case .all: true
        case .realisticOnly: realistic
        case .exceptRealistic: !realistic
        }
    }
}

/// A 2D symbolic line in world plan coordinates.
public struct PlanSymbol: Sendable {
    public var curve: Curve2
    public var subcategory: FamilySubcategory
    public var visibleAt: Set<DetailLevel>
}

public enum FamilyInstanceGeometry {
    /// Evaluates the family for an instance, supplying host-derived parameters.
    public static func evaluate(_ e: Element, _ model: BIMModel) -> EvaluatedFamily? {
        let typeElement = e.isType ? e : model.type(of: e)
        guard let famID = (e.typeData ?? typeElement?.typeData)?.familyID, let famElement = model[famID], let fam = famElement.family else { return nil }
        var instance = Parameters.familyInstanceValues(e)
        if fam.parameter(named: "Host Thickness") != nil, let host = model[e.hostID], let f = WallGeometry.frame(host, model) {
            instance["Host Thickness"] = .double(f.thickness)
        }
        var h = Hasher()
        h.combine(famID); h.combine(famElement.revision)
        h.combine(typeElement?.id); h.combine(typeElement?.revision)
        for (k, v) in instance.sorted(by: { $0.key < $1.key }) { h.combine(k); h.combine(v) }
        h.combine(model.units)
        let key = h.finalize()
        if let hit = FamilyEvalCache.shared.get(key) { return hit }
        let r = FamilyEvaluator.evaluate(Parameters.effectiveFamily(fam, for: e, model), typeName: "project", instance: instance, units: model.units)
        FamilyEvalCache.shared.put(key, r)
        return r
    }

    /// Material for a solid: the material parameter's value, else the type material, else nil (category default).
    static func material(_ s: EvaluatedFamily.Solid, _ ev: EvaluatedFamily, _ e: Element, _ model: BIMModel) -> ElementID? {
        if let m = s.resolvedMaterial, model[m]?.material != nil { return m }
        if let p = s.materialParameter {
            if case .quantity(let raw, _)? = ev.values[p], raw > 0 { return ElementID(UInt64(raw)) }
            if let v = Parameters.value(Parameters.familyParamID(p), of: e, model)?.refValue { return v }
        }
        return model.typeParam(e, ParameterID("type.material"))?.refValue
    }

    public static func meshParts(_ e: Element, _ model: BIMModel, transform t: Transform3, detail: DetailLevel = .fine) -> [MeshPart] {
        guard let ev = evaluate(e, model) else { return [] }
        let front = Vec2(t.yAxis.x, t.yAxis.y)
        let frontAxis = front.lengthSquared > 0 ? front.normalized : nil
        return ev.solids.filter { !$0.isVoid && $0.visibleAt.contains(detail) }.map { s in
            MeshPart(mesh: s.familyMesh.transformed(t), materialID: material(s, ev, e, model), subcategory: s.subcategory,
                     views: views(s), frontAxis: frontAxis)
        }
    }

    static func views(_ s: EvaluatedFamily.Solid) -> FamilyViewSet {
        var v: FamilyViewSet = []
        if s.visibleIn3D { v.insert(.threeD) }
        if s.visibleInFrontBack { v.insert(.frontBack) }
        if s.visibleInLeftRight { v.insert(.leftRight) }
        return v
    }

    public static func planSymbols(_ e: Element, _ model: BIMModel, transform t: Transform2) -> [PlanSymbol] {
        guard let ev = evaluate(e, model) else { return [] }
        return ev.planLines.map { PlanSymbol(curve: $0.curve.transformed(t), subcategory: $0.subcategory, visibleAt: $0.visibleAt) }
    }
}

public enum InsertGeometry {
    /// Opening width and height of a door/window.
    public static func openingSize(_ e: Element, _ model: BIMModel) -> (width: Double, height: Double)? {
        guard let o = FamilyInstanceGeometry.evaluate(e, model)?.opening else { return nil }
        return (o.xMax - o.xMin, o.zMax - o.zMin)
    }

    /// Placement of the insert on its host: origin at the host center line (plan) at the sill elevation.
    public static func placement(_ e: Element, _ model: BIMModel) -> (plan: Transform2, world: Transform3)? {
        guard let ins = e.insert, let host = model[e.hostID], let f = WallGeometry.frame(host, model) else { return nil }
        let s = WallGeometry.station(of: ins.location, on: f.location)
        let t = f.length > 0 ? min(1, max(0, s / f.length)) : 0
        let centerCurve = f.location.offset(by: f.centerOffset)
        let origin = centerCurve.point(at: t)
        var xDir = f.location.tangent(at: t)
        var yDir = f.location.normal(at: t) * (f.flipped ? -1 : 1)
        if ins.facingFlipped { yDir = -yDir }
        if ins.handFlipped { xDir = -xDir }
        let plan = Transform2(a: xDir.x, b: yDir.x, c: xDir.y, d: yDir.y, tx: origin.x, ty: origin.y)
        let z = f.baseZ + ins.sillHeight
        let world = Transform3(plan, z: z)
        return (plan, world)
    }

    /// Opening in host stations/elevations.
    public static func openingInHost(_ e: Element, host f: WallFrame, _ model: BIMModel) -> (Double, Double, Double, Double)? {
        guard let ins = e.insert, let o = FamilyInstanceGeometry.evaluate(e, model)?.opening else { return nil }
        let s = WallGeometry.station(of: ins.location, on: f.location)
        // Hand flip mirrors the opening about the insertion point; the opening is symmetric in most families.
        let a = ins.handFlipped ? s - o.xMax : s + o.xMin
        let b = ins.handFlipped ? s - o.xMin : s + o.xMax
        let z = f.baseZ + ins.sillHeight
        return (a, b, z + o.zMin, z + o.zMax)
    }

    public static func meshParts(_ e: Element, _ model: BIMModel, detail: DetailLevel = .fine) -> [MeshPart] {
        guard let p = placement(e, model) else { return [] }
        return FamilyInstanceGeometry.meshParts(e, model, transform: p.world, detail: detail)
    }

    public static func planSymbols(_ e: Element, _ model: BIMModel) -> [PlanSymbol] {
        guard let p = placement(e, model) else { return [] }
        return FamilyInstanceGeometry.planSymbols(e, model, transform: p.plan)
    }

    /// Projects a point onto a host wall's location curve, clamped so the opening stays inside the wall.
    public static func constrainToHost(_ p: Vec2, width: Double, host: WallFrame) -> Vec2? {
        let L = host.length
        guard L > width + Tolerance.shortCurve else { return nil }
        var s = WallGeometry.station(of: host.location.closestPoint(to: p), on: host.location)
        s = min(max(s, width / 2), L - width / 2)
        return WallGeometry.point(atStation: s, on: host.location)
    }
}

public enum ComponentGeometry {
    public static func placement(_ e: Element, _ model: BIMModel) -> (plan: Transform2, world: Transform3)? {
        let loc: Vec2, rot: Double, mirrored: Bool
        switch e.data {
        case .component(let c): loc = c.location; rot = c.rotation; mirrored = c.mirrored
        case .column(let c): loc = c.location; rot = c.rotation; mirrored = false
        case .detailComponent(let d): loc = d.location; rot = d.rotation; mirrored = d.mirrored
        default: return nil
        }
        var plan = Transform2.translation(loc) * Transform2.rotation(rot)
        if mirrored { plan = plan * Transform2.scale(-1, 1) }
        let z = model.baseElevation(of: e)
        return (plan, Transform3(plan, z: z))
    }

    public static func meshParts(_ e: Element, _ model: BIMModel, detail: DetailLevel = .fine) -> [MeshPart] {
        guard let p = placement(e, model) else { return [] }
        if case .column(let c) = e.data {
            let base = model.baseElevation(of: e)
            let top = model.topElevation(base: base, topLevelID: c.topLevelID, topOffset: c.topOffset, unconnectedHeight: c.unconnectedHeight)
            let h = max(top - base, Tolerance.shortCurve)
            if Parameters.familyDefinition(for: e, model) == nil {
                let prof = columnProfile(e, model)
                return [MeshPart(mesh: MeshBuilder.extrude(prof, bottom: 0, top: h).transformed(p.world),
                                 materialID: model.typeParam(e, ParameterID("type.material"))?.refValue)]
            }
            // Family columns: scale the family's height to the level-to-level height via the "Height" instance value.
            var copy = e
            copy.params[Parameters.familyParamID("Height")] = .double(h)
            return FamilyInstanceGeometry.meshParts(copy, model, transform: p.world, detail: detail)
        }
        return FamilyInstanceGeometry.meshParts(e, model, transform: p.world, detail: detail)
    }

    public static func columnProfile(_ e: Element, _ model: BIMModel) -> Profile2 {
        let d = model.typeLength(e, ParameterID("column.diameter"), default: 0)
        if d > Tolerance.length {
            let pts = Arc2(center: .zero, radius: d / 2, startAngle: 0, sweep: Angle.twoPi).tessellate(chordTolerance: 0.002)
            return Profile2(outer: Polygon2(Array(pts.dropLast())))
        }
        let w = model.typeLength(e, ParameterID("column.width"), default: 0.4)
        let h = model.typeLength(e, ParameterID("column.depth"), default: 0.4)
        return Profile2(outer: .rectangle(Rect2(center: .zero, halfSize: Vec2(w / 2, h / 2))))
    }

    /// Plan outline of a column/component at cut height (profile in world plan). With `detail`, family forms hidden at
    /// that detail level are left out.
    public static func planOutline(_ e: Element, _ model: BIMModel, detail: DetailLevel? = nil) -> [Polygon2] {
        guard let p = placement(e, model) else { return [] }
        if case .column = e.data, Parameters.familyDefinition(for: e, model) == nil {
            return [columnProfile(e, model).outer.transformed(p.plan)]
        }
        guard let ev = FamilyInstanceGeometry.evaluate(e, model) else { return [] }
        return ev.solids.filter { !$0.isVoid && $0.visibleInPlan && detail.map($0.visibleAt.contains) != false }.map { $0.profile.outer.transformed(p.plan) }
    }

    public static func planSymbols(_ e: Element, _ model: BIMModel) -> [PlanSymbol] {
        guard let p = placement(e, model) else { return [] }
        return FamilyInstanceGeometry.planSymbols(e, model, transform: p.plan)
    }

    /// Like `planOutline`, but with the holes of hollow profiles (tubes, pipes) as extra loops, for cut fills and
    /// outlines drawn with an even-odd rule. // W2-TYPES
    public static func planLoops(_ e: Element, _ model: BIMModel, detail: DetailLevel? = nil) -> [Polygon2] {
        guard let p = placement(e, model) else { return [] }
        if case .column = e.data, Parameters.familyDefinition(for: e, model) == nil {
            return [columnProfile(e, model).outer.transformed(p.plan)]
        }
        guard let ev = FamilyInstanceGeometry.evaluate(e, model) else { return [] }
        return ev.solids.filter { !$0.isVoid && $0.visibleInPlan && detail.map($0.visibleAt.contains) != false }
            .flatMap { $0.profile.loops.map { $0.transformed(p.plan) } }
    }
}

public enum BeamGeometry {
    public static func section(_ e: Element, _ model: BIMModel) -> (width: Double, depth: Double) {
        (model.typeLength(e, ParameterID("beam.width"), default: 0.3), model.typeLength(e, ParameterID("beam.depth"), default: 0.5))
    }
    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        guard let b = e.beam, let seg = b.curve.asSegment, seg.length > Tolerance.shortCurve else { return [] }
        let (w, d) = section(e, model)
        let lv = model.elevation(ofLevel: e.levelID)
        let z0 = lv + b.startOffset, z1 = lv + b.endOffset
        let top0: Double, top1: Double
        switch b.zJustification {
        case .top: top0 = z0; top1 = z1
        case .center: top0 = z0 + d / 2; top1 = z1 + d / 2
        case .bottom: top0 = z0 + d; top1 = z1 + d
        }
        let n = seg.normal * (w / 2)
        let pts3 = [Vec3(seg.start - n, z: top0), Vec3(seg.end - n, z: top1), Vec3(seg.end + n, z: top1), Vec3(seg.start + n, z: top0)]
        var m = Mesh()
        let bot = pts3.map { $0 - Vec3(0, 0, d) }
        m.addConvexFace(pts3, normal: .unitZ)
        m.addConvexFace(bot.reversed(), normal: -.unitZ)
        for i in 0..<4 {
            let j = (i + 1) % 4
            let normal = (pts3[j] - pts3[i]).cross(bot[i] - pts3[i]).normalized
            m.addConvexFace([pts3[i], bot[i], bot[j], pts3[j]], normal: -normal)
        }
        WallGeometry.recomputeFlatNormals(&m)
        return [MeshPart(mesh: m, materialID: model.typeParam(e, ParameterID("type.material"))?.refValue)]
    }
    public static func planOutline(_ e: Element, _ model: BIMModel) -> Polygon2? {
        guard let b = e.beam, let seg = b.curve.asSegment else { return nil }
        let n = seg.normal * (section(e, model).width / 2)
        return Polygon2([seg.start - n, seg.end - n, seg.end + n, seg.start + n])
    }
}

/// Memoizes evaluated families by (family revision, type revision, instance values). Bounded LRU-ish.
final class FamilyEvalCache: @unchecked Sendable {
    static let shared = FamilyEvalCache()
    private let lock = NSLock()
    private var entries: [Int: EvaluatedFamily] = [:]
    private var order: [Int] = []
    func get(_ k: Int) -> EvaluatedFamily? { lock.lock(); defer { lock.unlock() }; return entries[k] }
    func put(_ k: Int, _ v: EvaluatedFamily) {
        lock.lock(); defer { lock.unlock() }
        if entries[k] == nil { order.append(k) }
        entries[k] = v
        if order.count > 4096 { for old in order.prefix(1024) { entries.removeValue(forKey: old) }; order.removeFirst(1024) }
    }
    func purge() { lock.lock(); entries.removeAll(); order.removeAll(); lock.unlock() }
}
