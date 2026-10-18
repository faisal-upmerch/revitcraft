import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// BL-CANVAS (ARCUS-036): doors and windows placed in elevations and sections by hovering the host wall. View points
// are (u, z): u along the view's right vector from its plane origin, z the elevation.

/// Where an insert lands when the pointer is at (u, z) in a vertical view.
public struct VerticalInsertHit: Sendable, Equatable {
    public var wallID: ElementID
    /// Point on the wall's location line (plan).
    public var location: Vec2
    /// Facing toward the viewer.
    public var facingFlipped: Bool
}

extension InsertTool {
    /// Plan frame of a vertical view: plane origin, right vector (u axis) and viewing direction.
    static func verticalFrame(_ v: ViewData?) -> (origin: Vec2, right: Vec2, forward: Vec2)? {
        guard let v, v.kind.isVerticalCut, let o = v.planeOrigin, let r = v.rightVector, let f = v.viewDirection?.normalized else { return nil }
        return (o.xy, r, f)
    }

    /// The frontmost wall seen at (u, z) — the pointer's line of sight crosses its location line between its base and
    /// top — and the point where the insert goes. Walls seen end-on are skipped. `prefer` wins when it is under the pointer.
    static func verticalHost(at p: Vec2, view: ViewData?, model: BIMModel, width: Double, prefer: ElementID? = nil) -> VerticalInsertHit? {
        guard let fr = verticalFrame(view) else { return nil }
        let eye = fr.origin + fr.right * p.x
        var best: (VerticalInsertHit, Double)?
        for w in model.elements(.walls) {
            guard let f = WallGeometry.frame(w, model), case .line(let seg) = f.location, seg.length > width + Tolerance.shortCurve else { continue }
            guard abs(seg.direction.dot(fr.forward)) < 0.985, p.y >= f.baseZ - Tolerance.length, p.y <= f.topZ + Tolerance.length else { continue }
            // Intersection of the sight line eye + forward·t with the location segment.
            let d = seg.end - seg.start
            let denom = fr.forward.cross(d)
            guard abs(denom) > 1e-12 else { continue }
            let t = (seg.start - eye).cross(d) / denom
            let s = (seg.start - eye).cross(fr.forward) / denom
            let tol = f.thickness / 2 / d.length
            guard s >= -tol, s <= 1 + tol, t > -f.thickness else { continue }
            let hitPoint = seg.start + d * min(1, max(0, s))
            guard let loc = InsertGeometry.constrainToHost(hitPoint, width: width, host: f) else { continue }
            let n = f.location.normal(at: 0.5) * (f.flipped ? -1 : 1)
            let hit = VerticalInsertHit(wallID: w.id, location: loc, facingFlipped: (-fr.forward).dot(n) < 0)
            let depth = w.id == prefer ? -Double.infinity : t
            if best == nil || depth < best!.1 { best = (hit, depth) }
        }
        return best?.0
    }

    /// Elevation/section hover: host highlight, the opening outline, and temporary dimensions to the wall ends and
    /// (for raised sills) to the host's base.
    func verticalPointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        spacing = []
        let width = probe.flatMap { InsertGeometry.openingSize($0, ctx.model)?.width } ?? 0.9
        let preferred = hit(i, [.walls])?.id
        guard let fr = Self.verticalFrame(ctx.viewData),
              let h = Self.verticalHost(at: i.rawPoint, view: ctx.viewData, model: ctx.model, width: width, prefer: preferred),
              let wall = ctx.model[h.wallID], let f = WallGeometry.frame(wall, ctx.model) else {
            hostID = nil; preview.cursor = .notAllowed; return
        }
        hostID = h.wallID
        location = h.location
        facingFlipped = h.facingFlipped
        preview.highlight = [h.wallID]
        guard let e = probe, let size = InsertGeometry.openingSize(e, ctx.model), case .line(let seg) = f.location else { return }
        func u(_ q: Vec2) -> Double { (q - fr.origin).dot(fr.right) }
        let dir = seg.direction.normalized
        let a = h.location - dir * (size.width / 2), b = h.location + dir * (size.width / 2)
        let z0 = f.baseZ + sillHeight, z1 = z0 + size.height
        let ua = u(a), ub = u(b)
        preview.primitives.append(.polyline([Vec2(ua, z0), Vec2(ub, z0), Vec2(ub, z1), Vec2(ua, z1)], closed: true, ctx.previewHeavy))
        // Distances along the wall from each jamb to the nearer wall end, drawn just below the opening.
        let zd = z0 - ctx.pixel * 18
        let (lo, hi) = ua <= ub ? (a, b) : (b, a)
        let ends = [seg.start, seg.end].sorted { u($0) < u($1) }
        var dims = [
            TemporaryDimension(from: Vec2(u(ends[0]), zd), to: Vec2(u(lo), zd), text: ctx.format(ends[0].distance(to: lo)), isAngle: false, isActive: true),
            TemporaryDimension(from: Vec2(u(hi), zd), to: Vec2(u(ends[1]), zd), text: ctx.format(hi.distance(to: ends[1])), isAngle: false, isActive: false),
        ]
        if sillHeight > Tolerance.length {
            let x = max(ua, ub) + ctx.pixel * 18
            dims.append(TemporaryDimension(from: Vec2(x, f.baseZ), to: Vec2(x, z0), text: ctx.format(sillHeight), isAngle: false, isActive: false))
        }
        preview.tempDims = dims
    }
}
