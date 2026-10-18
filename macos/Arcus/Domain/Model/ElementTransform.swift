import Foundation
import ArcusGeometry

/// Applies plan transforms (move, rotate, mirror, array) to elements.
public enum ElementTransform {
    /// Whether an element can be transformed in plan by Move/Rotate/Mirror/Copy.
    public static func isTransformable(_ e: Element) -> Bool {
        switch e.data {
        case .view, .sheet, .schedule, .type, .family, .material, .phase, .designOption, .revision, .projectInfo,
             .viewTemplate, .filter, .lineStyle, .fillPattern, .areaScheme, .constraint, .level, .colorScheme:
            return false
        default:
            return true
        }
    }

    /// Transforms an element's plan geometry. Returns false if the element cannot be transformed this way.
    @discardableResult
    public static func apply(_ t: Transform2, to e: inout Element) -> Bool {
        let rot = t.rotationAngle
        let mirror = t.isMirroring
        switch e.data {
        case .wall(var w):
            w.location = t.apply(w.location)
            if mirror { w.flipped.toggle() }
            if var p = w.profile, mirror {
                let L = w.location.length
                p = Polygon2(p.points.map { Vec2(L - $0.x, $0.y) })
                w.profile = p
            }
            e.data = .wall(w)
        case .insert(var i):
            // The insert's frame follows its host; mirroring the host (reversed direction / flipped wall) already
            // mirrors the insert, so its hand must not be toggled as well.
            i.location = t.apply(i.location)
            e.data = .insert(i)
        case .component(var c):
            // A reflection is M = R(φ)·diag(1, −1), so M·R(θ) = R(φ − θ + π)·diag(−1, 1): with the mirrored flag
            // toggled (placement applies it as scale(−1, 1)) the new rotation is φ − θ + π.
            c.location = t.apply(c.location)
            c.rotation = mirror ? Angle.normalize(-c.rotation + rot + .pi) : c.rotation + rot
            if mirror { c.mirrored.toggle() }
            e.data = .component(c)
        case .column(var c):
            c.location = t.apply(c.location)
            c.rotation = mirror ? -c.rotation + rot : c.rotation + rot
            e.data = .column(c)
        case .beam(var b):
            b.curve = t.apply(b.curve)
            e.data = .beam(b)
        case .slab(var s):
            s.boundary = s.boundary.transformed(t)
            if var a = s.slopeArrow { a.tail = t.apply(a.tail); a.head = t.apply(a.head); s.slopeArrow = a }
            s.shapePoints = s.shapePoints?.map { ShapePoint(position: t.apply($0.position), offset: $0.offset) }
            e.data = .slab(s)
        case .roof(var r):
            r.footprint = r.footprint.transformed(t)
            if var x = r.extrusion {
                // A reflection reverses the work plane's normal (left of its direction), so depths change sign.
                x.origin = t.apply(x.origin)
                x.direction = t.applyVector(x.direction).normalized
                if mirror { x.start = -x.start; x.end = -x.end }
                r.extrusion = x
            }
            r.shapePoints = r.shapePoints?.map { ShapePoint(position: t.apply($0.position), offset: $0.offset) }
            e.data = .roof(r)
        case .stair(var s):
            s.origin = t.apply(s.origin)
            let d = t.applyVector(Vec2.fromAngle(s.direction))
            s.direction = d.angle
            if mirror { s.turnsLeft.toggle() }
            e.data = .stair(s)
        case .ramp(var r):
            r.path = r.path.map(t.apply)
            e.data = .ramp(r)
        case .railing(var r):
            r.path = r.path.map { t.apply($0) }
            if mirror { r.hostSideLeft.toggle() }
            e.data = .railing(r)
        case .room(var r):
            r.point = t.apply(r.point)
            e.data = .room(r)
        case .modelLine(var l):
            l.curve = t.apply(l.curve)
            e.data = .modelLine(l)
        case .grid(var g):
            g.curve = t.apply(g.curve)
            e.data = .grid(g)
        case .referencePlane(var p):
            p.line = p.line.transformed(t)
            e.data = .referencePlane(p)
        case .topography(var tp):
            tp.points = tp.points.map { Vec3(t.apply($0.xy), z: $0.z) }
            tp.boundary = tp.boundary?.map(t.apply) // W2-DWG
            if let o = tp.solid?.outline { tp.solid?.outline = o.map(t.apply) } // BL-SITE
            e.data = .topography(tp)
        case .dimension(var d):
            d.linePoint = t.apply(d.linePoint)
            d.references = d.references.map { r in var r = r; if let p = r.point { r.point = t.apply(p) }; return r }
            d.fallbackPoints = d.fallbackPoints.map(t.apply)
            if let a = d.direction { d.direction = t.applyVector(Vec2.fromAngle(a)).angle }
            d.textOffsets = d.textOffsets?.map(t.applyVector)
            e.data = .dimension(d)
        case .tag(var g):
            g.head = t.apply(g.head)
            g.leaderEnd = g.leaderEnd.map(t.apply)
            g.leaderElbow = g.leaderElbow.map(t.apply)
            if let a = g.angle { g.angle = t.applyVector(Vec2.fromAngle(a)).angle }
            e.data = .tag(g)
        case .textNote(var n):
            n.position = t.apply(n.position)
            n.leaders = n.leaders.map(t.apply)
            n.leaderElbows = n.leaderElbows?.map { $0.map(t.apply) }
            n.rotation += rot
            e.data = .textNote(n)
        case .spot(var s):
            s.point = t.apply(s.point)
            s.leaderHead = t.apply(s.leaderHead)
            e.data = .spot(s)
        case .filledRegion(var f):
            f.boundary = f.boundary.transformed(t)
            e.data = .filledRegion(f)
        case .detailComponent(var d):
            d.location = t.apply(d.location)
            d.repeatEnd = d.repeatEnd.map(t.apply)
            d.rotation = mirror ? Angle.normalize(-d.rotation + rot + .pi) : d.rotation + rot
            if mirror { d.mirrored.toggle() }
            e.data = .detailComponent(d)
        case .revisionCloud(var c):
            c.outline = c.outline.transformed(t)
            e.data = .revisionCloud(c)
        case .insulation(var i):
            i.line = i.line.transformed(t)
            e.data = .insulation(i)
        case .viewport(var vp):
            vp.center = t.apply(vp.center)
            e.data = .viewport(vp)
        case .link(var l):
            l.placement = t * l.placement
            e.data = .link(l)
        case .group(var g):
            g.origin = t.apply(g.origin)
            g.arraySpec = g.arraySpec?.transformed(by: t)
            e.data = .group(g)
        case .referenceGeometry(var r):
            let t3 = Transform3(t)
            r.positions = r.positions.map(t3.apply)
            e.data = .referenceGeometry(r)
        case .scopeBox(let b): // WP6a
            e.data = .scopeBox(b.transformed(t))
        case .colorFillLegend(var l):
            l.position = t.apply(l.position)
            e.data = .colorFillLegend(l)
        case .opening(let o): // WP3: shafts move with their sketch; wall openings are positioned relative to their host
            if case .shaft(var sh) = o { sh.boundary = sh.boundary.transformed(t); e.data = .opening(.shaft(sh)) }
        case .rebar, .areaReinforcement, .pathReinforcement, .fabricArea, .fabricSheet, .rebarCoupler, .beamSystem, .structuralSymbol: // F34
            return ReinforcementTransform.apply(t, to: &e)
        case .matchline(var m): // F810
            m.start = t.apply(m.start); m.end = t.apply(m.end)
            e.data = .matchline(m)
            return true
        case .cutProfile(var c): // F810: moves with its wall
            c.region = c.region.map(t.apply)
            if mirror { c.region.reverse() }
            e.data = .cutProfile(c)
            return true
        default:
            return false
        }
        return true
    }
}

extension Transform2 {
    public func apply(_ c: Curve2) -> Curve2 { c.transformed(self) }
}
