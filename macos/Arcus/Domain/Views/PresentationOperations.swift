import Foundation
import ArcusGeometry
import ArcusCalc

// F810: model operations of the View tab features, ported from RevitCraft's rc-core `edit.rs` (show/remove hidden
// lines, add_cut_profile, new_framing_elevation, new_sketch_callout, new_walkthrough/set_walk_frame, add_matchline).

/// View ▸ Graphics ▸ Show / Remove Hidden Lines.
public enum HiddenLines {
    /// Shows the lines of `hidden` behind `obscuring` dashed in `view`.
    public static func show(_ hidden: ElementID, behind obscuring: ElementID, in view: ElementID, _ tx: TransactionContext) throws {
        guard hidden != obscuring else { throw TransactionError("Pick the element that is hidden by the first one.") }
        guard tx.model[view]?.view != nil else { throw TransactionError("No view.") }
        let pair = HiddenLinePair(obscuring: obscuring, hidden: hidden)
        tx.update(view) { e in
            var list = e.view?.hiddenLines ?? []
            list.removeAll { $0 == pair }
            list.append(pair)
            e.view?.hiddenLines = list
        }
    }

    /// Stops showing the hidden lines of `hidden` behind `obscuring` in `view`.
    public static func remove(_ hidden: ElementID, behind obscuring: ElementID, in view: ElementID, _ tx: TransactionContext) throws {
        guard hidden != obscuring else { throw TransactionError("Pick the element that is hidden by the first one.") }
        let pair = HiddenLinePair(obscuring: obscuring, hidden: hidden)
        guard let list = tx.model[view]?.view?.hiddenLines, list.contains(pair) else { throw TransactionError("These elements have no hidden lines shown.") }
        tx.update(view) { e in
            let rest = list.filter { $0 != pair }
            e.view?.hiddenLines = rest.isEmpty ? nil : rest
        }
    }
}

/// View ▸ Graphics ▸ Cut Profile.
public enum CutProfiles {
    /// The plan height at which `view` cuts.
    public static func cutZ(_ view: Element, _ m: BIMModel) -> Double {
        m.elevation(ofLevel: view.levelID) + (view.view?.viewRange.cutOffset ?? 1.2)
    }

    /// Adds a cut profile reshaping `wall` in plan `view`. A region lying mostly inside the wall cuts it away;
    /// otherwise it joins the wall. The region must touch the wall.
    @discardableResult
    public static func create(region pts: [Vec2], wall: ElementID, view: ElementID, _ tx: TransactionContext) throws -> ElementID {
        guard let v = tx.model[view], let vd = v.view, vd.kind.isPlan else { throw TransactionError("Cut profiles are sketched in plan views.") }
        guard let w = tx.model[wall], w.wall != nil else { throw TransactionError("Pick a wall cut in this view.") }
        var region = Polygon2(pts).simplified()
        guard region.count >= 3, !region.isDegenerate else { throw TransactionError("Sketch a closed profile.") }
        region = region.counterClockwise
        let cut = WallGeometry.planCut(w, atZ: cutZ(v, tx.model), tx.model).filter { $0.count >= 3 }.map { Profile2(outer: $0.counterClockwise) }
        guard !cut.isEmpty else { throw TransactionError("Pick a wall cut in this view.", elements: [wall]) }
        let r = [Profile2(outer: region)]
        let overlap = PolygonBoolean.intersection(r, cut).reduce(0) { $0 + $1.area }
        if overlap < Tolerance.area {
            // Touching counts: grow the wall a little and try again.
            let grown = cut.map { Profile2(outer: $0.outer.offset(by: 0.001).max { $0.area < $1.area } ?? $0.outer) }
            if PolygonBoolean.intersection(r, grown).reduce(0, { $0 + $1.area }) < Tolerance.area {
                throw TransactionError("The profile must touch the wall.", elements: [wall])
            }
        }
        let adds = !(overlap > region.area / 2)
        return tx.create(.cutProfiles, name: "Cut Profile", data: .cutProfile(CutProfileData(region: region.points, adds: adds)), hostID: wall, ownerViewID: view)
    }
}

/// View ▸ Create ▸ Elevation ▸ Framing Elevation.
public enum FramingElevations {
    /// Distance of the marker from the grid (RevitCraft: 1500 mm).
    public static let offset = 1.5

    /// An elevation beside `grid` on the side of `side`, looking at the grid, cropped to its length and the levels.
    @discardableResult
    public static func create(grid: ElementID, side: Vec2, scale: Int, _ tx: TransactionContext) throws -> ElementID {
        guard let g = tx.model[grid]?.grid else { throw TransactionError("Pick a grid.") }
        guard let seg = g.curve.asSegment, seg.length > Tolerance.shortCurve else { throw TransactionError("Framing elevations are placed on straight grids.", elements: [grid]) }
        let d = seg.direction
        let n = d.perpendicular
        let sign: Double = (side - seg.start).dot(n) >= 0 ? 1 : -1
        let foot = seg.closestPoint(to: side)
        let origin = foot + n * sign * offset
        let look = n * -sign
        var v = ViewData(kind: .elevation, scale: scale)
        v.planeOrigin = Vec3(origin, z: 0)
        v.viewDirection = look
        v.markerPosition = origin
        v.farClip = 40
        guard let right = v.rightVector else { throw TransactionError("Pick a grid.") }
        let ua = (seg.start - origin).dot(right), ub = (seg.end - origin).dot(right)
        let zs = tx.model.levels.compactMap { $0.level?.elevation }
        let z0 = (zs.min() ?? 0) - 1, z1 = (zs.max() ?? 3) + 3
        v.cropRegion = Rect2(min: Vec2(min(ua, ub), z0), max: Vec2(max(ua, ub), z1))
        v.cropActive = true
        v.cropVisible = true
        v.phaseID = tx.model.latestPhase?.id
        let count = tx.model.views.filter { $0.view?.kind == .elevation }.count + 1
        let names = Set(tx.model.views.map(\.name))
        var name = "Elevation \(count) - a", k = 2
        while names.contains(name) { name = "Elevation \(count) - a (\(k))"; k += 1 }
        return tx.create(.views, name: name, data: .view(v))
    }
}

/// View ▸ Create ▸ Callout ▸ Sketch.
public enum SketchedCallouts {
    /// A callout of `parent` cropped to a sketched boundary of any shape (closed, in plan coordinates).
    @discardableResult
    public static func create(parent: ElementID, shape pts: [Vec2], _ tx: TransactionContext) throws -> ElementID {
        guard let p = tx.model[parent], let pd = p.view, pd.kind.isPlan else { throw TransactionError("Callouts are created in plan views.") }
        let shape = Polygon2(pts).simplified().counterClockwise
        guard shape.count >= 3, shape.area > 0.01 else { throw TransactionError("Sketch a closed callout boundary.") }
        let n = tx.model.views.filter { $0.view?.parentViewID != nil }.count + 1
        var v = pd
        v.scale = max(1, pd.scale / 2)
        v.cropRegion = shape.bounds
        v.cropShape = shape.points
        v.cropActive = true
        v.cropVisible = true
        v.parentViewID = parent
        v.visibility = pd.visibility
        v.hiddenLines = nil
        return tx.create(.views, name: "Callout \(n) of \(p.name)", data: .view(v), levelID: p.levelID)
    }
}

/// View ▸ Create ▸ 3D View ▸ Walkthrough.
public enum Walkthroughs {
    /// RevitCraft's eye height: 1750 mm, or 5'-6" in imperial projects.
    public static func eyeHeight(_ units: UnitsSettings) -> Double { units.system == .imperial ? 1.6764 : 1.75 }

    /// "Walkthrough 1", "Walkthrough 2", … unique among views.
    public static func nextName(_ m: BIMModel) -> String {
        let names = Set(m.views.map(\.name))
        var n = 1
        while names.contains("Walkthrough \(n)") { n += 1 }
        return "Walkthrough \(n)"
    }

    /// A perspective 3D view moving along the plan points `path` at `eyeHeight` above `levelID`, over `frames` frames.
    @discardableResult
    public static func create(path: [Vec2], levelID: ElementID?, eyeHeight: Double, frames: Int = WalkthroughData.defaultFrames, _ tx: TransactionContext) throws -> ElementID {
        let z = tx.model.elevation(ofLevel: levelID) + eyeHeight
        let walk = WalkthroughData(path: path.map { Vec3($0, z: z) }, frames: max(2, frames), frame: 1)
        guard path.count >= 2, walk.length >= 0.1 else { throw TransactionError("Click at least two points along the walkthrough path.") }
        var v = ViewData(kind: .threeD)
        v.camera = walk.camera3D(frame: 1, base: nil)
        v.walkthrough = walk
        v.visualStyle = .shaded
        v.cropActive = true
        v.phaseID = tx.model.latestPhase?.id
        return tx.create(.views, name: nextName(tx.model), data: .view(v), levelID: levelID)
    }

    /// Moves a walkthrough to `frame` (clamped); its camera follows. Returns the frame shown.
    @discardableResult
    public static func setFrame(_ frame: Int, of view: ElementID, _ tx: TransactionContext) throws -> Int {
        guard let vd = tx.model[view]?.view, var w = vd.walkthrough else { throw TransactionError("Open a walkthrough view.") }
        w.frame = max(1, min(w.frames, frame))
        let cam = w.camera3D(frame: w.frame, base: vd.camera)
        let shown = w.frame
        tx.update(view) { e in e.view?.walkthrough = w; e.view?.camera = cam }
        return shown
    }
}

/// View ▸ Sheet Composition ▸ Matchline.
public enum Matchlines {
    @discardableResult
    public static func create(from a: Vec2, to b: Vec2, _ tx: TransactionContext) throws -> ElementID {
        guard a.distance(to: b) >= 0.001 else { throw TransactionError("The matchline is too short.") }
        return tx.create(.matchlines, name: "Matchline", data: .matchline(MatchlineData(start: a, end: b)))
    }
}

/// View ▸ Presentation ▸ Render ▸ Save to Project, and the Render Gallery.
public enum Renderings {
    /// The renderings saved in the project, newest first.
    public static func all(_ m: BIMModel) -> [Element] {
        m.elements(.renderings).sorted { ($0.rendering?.date ?? .distantPast) > ($1.rendering?.date ?? .distantPast) }
    }

    /// "<view>_1", "<view>_2", … unique among renderings (RevitCraft names saved renderings after their view).
    public static func nextName(for base: String, _ m: BIMModel) -> String {
        let names = Set(m.elements(.renderings).map(\.name))
        var n = 1
        while names.contains("\(base)_\(n)") { n += 1 }
        return "\(base)_\(n)"
    }

    @discardableResult
    public static func save(_ r: RenderingData, name: String, _ tx: TransactionContext) throws -> ElementID {
        guard !r.png.isEmpty, r.width > 0, r.height > 0 else { throw TransactionError("Render the view first.") }
        return tx.create(.renderings, name: name, data: .rendering(r))
    }
}

/// View ▸ Sheet Composition ▸ Guide Grid: viewports snap to the sheet's guide grid while they move.
public enum GuideGrids {
    /// Guide spacing limits of the Assign Guide Grid dialog (paper meters).
    public static let spacingRange: ClosedRange<Double> = 0.005...0.2

    /// `move` adjusted so the nearest edge or centre of `boxes` lands on a guide line, per axis, when it is within
    /// `tolerance` of one (RevitCraft's sheet drag).
    public static func snap(_ move: Vec2, boxes: [Rect2], spacing: Double, tolerance: Double) -> Vec2 {
        guard spacing > 0, !boxes.isEmpty else { return move }
        func axis(_ values: [Double], _ d: Double) -> Double {
            let shifts = values.map { v -> Double in let m = v + d; return (m / spacing).rounded() * spacing - m }
            guard let best = shifts.min(by: { abs($0) < abs($1) }), abs(best) < tolerance else { return d }
            return d + best
        }
        let xs = boxes.flatMap { [$0.min.x, $0.center.x, $0.max.x] }
        let ys = boxes.flatMap { [$0.min.y, $0.center.y, $0.max.y] }
        return Vec2(axis(xs, move.x), axis(ys, move.y))
    }

    /// The paper box of a viewport when it is known without building the view: the active crop at the view scale,
    /// else just its centre.
    public static func viewportBox(_ vp: Element, _ m: BIMModel) -> Rect2? {
        guard let d = vp.viewport else { return nil }
        guard let vd = m[d.viewID]?.view, vd.cropActive, let crop = vd.cropRegion, !crop.isEmpty else { return Rect2(center: d.center, halfSize: .zero) }
        let s = 1 / Double(max(vd.scale, 1))
        return Rect2(center: d.center, halfSize: Vec2(crop.width * s / 2, crop.height * s / 2))
    }
}
