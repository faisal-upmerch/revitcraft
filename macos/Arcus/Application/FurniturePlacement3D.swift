import Foundation
import ArcusGeometry
import ArcusDomain

// FM3D: Furniture tools in 3D views. A tool runs in a 3D view exactly as in the plan or elevation that sees its work
// plane: its context is that view's (sketch map, Options Bar, owner view of tags), and the pointer meets the work plane
// in 3D, whose (u, v) are that view's coordinates. A horizontal plane (a level, Bottom/Top, a top face) uses the floor
// plan; a vertical plane square to the piece uses the elevation that looks at it (Front, Back, Left, Right, or a
// section); so every tool creates the same elements in 3D as in 2D. Tools that pick what's under the pointer (bays,
// fronts, hardware, edges, the bottom a plinth runs under) follow the face under the pointer, as Revit's Place on Face.

/// What a Furniture tool needs of its work plane in a 3D view.
public enum FurniturePlacementNeed: Sendable, Equatable {
    /// A horizontal plane (Shelf, Top, Leg, Slats, Blend, Cushion, Attach Top/Base, Edit Boundary).
    case plan
    /// The Front or Back elevation's plane (Back, Divider: they pick the carcass round the click).
    case front
    /// A vertical plane square to the piece (Revolve, Edit Profile, Opening).
    case vertical
    /// A horizontal plane, or a vertical one square to the piece (Panel, Rail, Extrusion, Sweep, Bay Separator).
    case square
    /// The face under the pointer (Bay, Bay Divide, Bay Tag, Door, Drawer, Flap, Hardware, Pick New Host, Edge
    /// Profile, Groove, Plinth).
    case face
}

/// Where a Furniture tool draws in a 3D view: the 2D view whose coordinates it uses, and the plane in model space whose
/// (u, v) are those coordinates.
public struct FurniturePlacement3D: Sendable, Equatable {
    /// The plan, elevation or section the tool's context is (its sketch map and owner view).
    public var hostViewID: ElementID
    /// The plane drawn on: `local` gives the host view's coordinates (plan x, y; elevation u, z).
    public var frame: WorkPlaneFrame
    /// The work plane's own normal: up for a level, the outside of a picked face.
    public var normal: Vec3
    /// The work plane as chosen (Work Plane ▸ Set, a picked face), for the Options Bar.
    public var reference: WorkPlaneRef?
    /// The world axis the plane is square to (z for plans, y for Front/Back, x for Left/Right; nil when canted).
    public var axis: FamilyAxis?
    /// True when the plane is a face the user picked: extrusions then grow out of it, as in Revit.
    public var onFace: Bool

    public var isPlan: Bool { frame.isHorizontal }
    /// The work plane as a sketch plane (`ToolContext.sketchPlane`).
    public var host: WorkPlaneHost { WorkPlaneHost(frame: frame, reference: reference) }
    /// A model point in the host view's coordinates (projected along the plane's normal).
    public func local(_ p: Vec3) -> Vec2 { host.local(p) }
    /// A host view point on the plane.
    public func world(_ q: Vec2) -> Vec3 { frame.point(q.x, q.y) }

    /// Where the plane is along its axis (its elevation in plans; y or x for vertical planes square to the piece).
    public var depth: Double {
        switch axis {
        case .z?: frame.origin.z
        case .y?: frame.origin.y
        case .x?: frame.origin.x
        case nil: frame.origin.dot(frame.normal)
        }
    }

    /// The same plane moved along its normal to `d` (see `depth`).
    public func atDepth(_ d: Double) -> FurniturePlacement3D {
        var p = self
        switch axis {
        case .z?: p.frame.origin.z = d
        case .y?: p.frame.origin.y = d
        case .x?: p.frame.origin.x = d
        case nil: p.frame.origin = frame.origin + frame.normal * (d - depth)
        }
        return p
    }

    /// The same plane through `point`.
    public func through(_ point: Vec3) -> FurniturePlacement3D {
        guard let a = axis else { return atDepth(point.dot(frame.normal)) }
        return atDepth(FurniturePlacements.component(point, a))
    }

    /// The sign an extrusion's depth takes along the axis: out of a picked face; nil keeps the 2D rule.
    public var extrusionSign: Double? {
        guard onFace, let a = axis else { return nil }
        return FurniturePlacements.component(normal, a) >= 0 ? 1 : -1
    }

    /// The named plane the work plane lies on, or the nearest one along its axis and the offset from it.
    public func planeBinding(_ m: BIMModel) -> (name: String, offset: Double)? {
        guard let a = axis else { return nil }
        return FurniturePlacements.binding(depth, along: a, m)
    }
}

public enum FurniturePlacements {
    public static func component(_ v: Vec3, _ a: FamilyAxis) -> Double { switch a { case .x: v.x; case .y: v.y; case .z: v.z } }
    public static func unit(_ a: FamilyAxis) -> Vec3 { switch a { case .x: .unitX; case .y: .unitY; case .z: .unitZ } }

    /// What each Furniture command needs of its work plane in 3D; nil for commands that don't draw.
    public static func need(_ id: CommandID) -> FurniturePlacementNeed? {
        switch id {
        case .furnitureShelf, .furnitureTop, .furnitureLeg, .furnitureLegsAtCorners, .furnitureSlats, .furnitureBlend, .furnitureVoidBlend,
             .furnitureCushion, .furnitureAttach, .furnitureBlendEditTop, .furnitureBlendEditBase:
            return .plan
        case .furnitureBack, .furnitureDivider: return .front
        case .furnitureRevolve, .furnitureVoidRevolve, .furnitureEditProfile, .furniturePanelOpening: return .vertical
        case .furniturePanel, .furnitureRail, .furnitureExtrusion, .furnitureVoidExtrusion, .furnitureSweep, .furnitureVoidSweep, .furnitureSweptBlend,
             .furnitureVoidSweptBlend, .furnitureBaySeparator:
            return .square
        case .furnitureBay, .furnitureBayDivide, .furnitureBayTag, .furnitureDoor, .furnitureDrawer, .furnitureFlap, .furnitureHardware,
             .furniturePickNewHost, .furnitureEdgeProfile, .furnitureGroove, .furniturePlinth:
            return .face
        default: return nil
        }
    }

    // MARK: Host views

    /// The floor plan a horizontal plane uses (the first level's).
    public static func planHost(_ m: BIMModel) -> ElementID? {
        let levels = m.levels.sorted { ($0.level?.elevation ?? 0, $0.id.raw) < ($1.level?.elevation ?? 0, $1.id.raw) }
        for l in levels { if let v = WorkPlane3D.planView(forLevel: l.id, in: m) { return v } }
        return nil
    }

    /// The elevation or section that sees a vertical plane facing `normal`: looking at it (from the normal's side)
    /// first, else from behind; elevations before sections, independent views before dependents. `square`: only views
    /// square to the piece (a sketch map).
    public static func verticalHost(normal: Vec3, _ m: BIMModel, square: Bool = false) -> ElementID? {
        let n = normal.xy
        guard n.length > 1e-9, abs(normal.z) < 1e-6 else { return nil }
        let nn = n.normalized
        var best: (rank: Int, id: ElementID)?
        for v in m.views {
            guard let vd = v.view, vd.kind.isVerticalCut, vd.planeOrigin != nil, let d = vd.viewDirection?.normalized else { continue }
            if square, FurnitureSketchMap.of(vd) == nil { continue }
            let facing = d.dot(nn)
            let side: Int
            if facing < -0.9999 { side = 0 } else if facing > 0.9999 { side = 1 } else { continue }
            let rank = side * 8 + (vd.kind == .elevation ? 0 : 2) + (vd.parentViewID == nil ? 0 : 4)
            if best.map({ (rank, v.id.raw) < ($0.rank, $0.id.raw) }) ?? true { best = (rank, v.id) }
        }
        return best?.id
    }

    /// The placement on `host` through `point` (the plane facing `normal`), or nil when the host can't see such a plane.
    public static func placement(host: ElementID, through point: Vec3, normal: Vec3, reference: WorkPlaneRef? = nil, onFace: Bool = false,
                                 _ m: BIMModel) -> FurniturePlacement3D? {
        guard let vd = m[host]?.view else { return nil }
        if vd.kind.isPlan {
            let f = WorkPlaneFrame(origin: Vec3(0, 0, point.z), u: .unitX, v: .unitY)
            return FurniturePlacement3D(hostViewID: host, frame: f, normal: normal.z < 0 ? -Vec3.unitZ : .unitZ, reference: reference, axis: .z, onFace: onFace)
        }
        guard vd.kind.isVerticalCut, let o = vd.planeOrigin, let r = vd.rightVector?.normalized, let fwd = vd.viewDirection?.normalized else { return nil }
        let k = (point.xy - o.xy).dot(fwd)
        let f = WorkPlaneFrame(origin: Vec3(o.xy + fwd * k, z: 0), u: Vec3(r, z: 0), v: .unitZ)
        let axis: FamilyAxis? = abs(abs(r.x) - 1) < 1e-6 ? .y : abs(abs(r.y) - 1) < 1e-6 ? .x : nil
        return FurniturePlacement3D(hostViewID: host, frame: f, normal: normal, reference: reference, axis: axis, onFace: onFace)
    }

    /// The placement of a work plane (frame and what it is), when a host view sees it and the need allows it.
    public static func placement(of w: WorkPlaneFrame, reference: WorkPlaneRef?, need: FurniturePlacementNeed, _ m: BIMModel) -> FurniturePlacement3D? {
        let n = w.normal
        let onFace: Bool = { if case .face? = reference { return true }; return false }()
        if abs(n.z) > 0.999 {
            guard need == .plan || need == .square || need == .face, let host = planHost(m) else { return nil }
            return placement(host: host, through: w.origin, normal: n, reference: reference, onFace: onFace, m)
        }
        guard abs(n.z) < 1e-6, need != .plan else { return nil }
        let squareToPiece = abs(abs(n.x) - 1) < 1e-6 || abs(abs(n.y) - 1) < 1e-6
        if need == .front, abs(abs(n.y) - 1) > 1e-6 { return nil }
        if need != .face, !squareToPiece { return nil }
        guard let host = verticalHost(normal: n, m, square: need != .face) else { return nil }
        return placement(host: host, through: w.origin, normal: n, reference: reference, onFace: onFace, m)
    }

    /// The placement a tool with `need` starts on: the 3D view's work plane when it suits the tool, else the tool's own
    /// default (the level for plan tools, the Front plane for Back and Divider, the Front/Back centre for vertical
    /// sketches). nil when the document has no view that sees such a plane.
    public static func resolve(_ need: FurniturePlacementNeed, workPlane: WorkPlaneFrame?, reference: WorkPlaneRef?, level: Double = 0,
                               _ m: BIMModel) -> FurniturePlacement3D? {
        if let w = workPlane, let p = placement(of: w, reference: reference, need: need, m) { return p }
        let planes = FurniturePlanes.positionsByName(m)
        switch need {
        case .plan, .square:
            guard let host = planHost(m) else { return nil }
            return placement(host: host, through: Vec3(0, 0, level), normal: .unitZ, m)
        case .front, .face:
            let n = Vec3(0, -1, 0)
            guard let host = verticalHost(normal: n, m, square: true) ?? verticalHost(normal: -n, m, square: true) else {
                return need == .face ? planHost(m).flatMap { placement(host: $0, through: Vec3(0, 0, level), normal: .unitZ, m) } : nil
            }
            return placement(host: host, through: Vec3(0, planes["Front"] ?? 0, 0), normal: n, m)
        case .vertical:
            let n = Vec3(0, -1, 0)
            guard let host = verticalHost(normal: n, m, square: true) ?? verticalHost(normal: -n, m, square: true) else { return nil }
            return placement(host: host, through: Vec3(0, planes["Center (Front/Back)"] ?? 0, 0), normal: n, m)
        }
    }

    /// The placement for a face under the pointer (Place on Face): the plan for top and bottom faces, the view that looks
    /// at a side face; nil when no view sees it.
    public static func face(_ normal: Vec3, at point: Vec3, element: ElementID?, need: FurniturePlacementNeed, _ m: BIMModel) -> FurniturePlacement3D? {
        let n = normal.normalized
        if abs(n.z) > 0.9 {
            guard need != .front && need != .vertical, let host = planHost(m) else { return nil }
            return placement(host: host, through: point, normal: n.z > 0 ? .unitZ : -Vec3.unitZ, reference: nil, onFace: true, m)
        }
        guard abs(n.z) < 0.1 else { return nil }
        let h = Vec3(n.xy.normalized, z: 0)
        let ref = element.map { WorkPlaneRef.face($0, FacePlanes.frame(normal: h, origin: point)) }
        guard let host = verticalHost(normal: h, m, square: need != .face) else { return nil }
        return placement(host: host, through: point, normal: h, reference: ref, onFace: true, m)
    }

    /// A position along an axis as a named plane and an offset from it: the plane it lies on, else the nearest.
    public static func binding(_ value: Double, along axis: FamilyAxis, _ m: BIMModel) -> (name: String, offset: Double)? {
        let planes = FurniturePartCoordinates.planes(along: axis, m)
        guard let p = planes.min(by: { (abs($0.position - value), $0.name) < (abs($1.position - value), $1.name) }) else { return nil }
        let off = value - p.position
        return (p.name, abs(off) < 1e-7 ? 0 : off)
    }

    /// The vertical placement that sees a plan-drawn panel's face (its outside face), for Edit Profile and Opening.
    public static func panelFace(_ e: Element, _ m: BIMModel) -> FurniturePlacement3D? {
        guard let p = e.furniturePanel, p.plane == .xy, p.length > Tolerance.length else { return nil }
        let t = FurniturePartTypes.values(of: e, m).thickness
        let (fo, _) = FurniturePartSolids.faceOffsets(p, thickness: t)
        let d = (p.end - p.start).normalized, side = d.perpendicular
        let outside = p.start.midpoint(p.end) + side * fo
        // The outside is the side of the outside face from the line (left of it, or right when flipped).
        let normal = Vec3((side * (p.flipped ? -1 : 1)).normalized, z: 0)
        guard let host = verticalHost(normal: normal, m, square: true) ?? verticalHost(normal: -normal, m, square: true) else { return nil }
        let mid = Vec3(outside, z: (p.base + p.top) / 2)
        return placement(host: host, through: mid, normal: normal, reference: .face(e.id, FacePlanes.frame(normal: normal, origin: mid)), onFace: true, m)
    }
}

/// FM3D: how a Furniture tool takes the 3D pointer and its work plane.
@MainActor
public protocol FurnitureTool3D: AnyObject {
    /// True while the tool picks what's under the pointer (a bay, a part, an edge) rather than drawing on the plane.
    var fm3dPicks: Bool { get }
    /// The depth the tool draws at when it follows its own options (a shelf's height, a rail's plane and offset); nil
    /// keeps the work plane's.
    var fm3dDepth: Double? { get }
    /// True while the tool is part-way through (a picked panel, a started line): the face under the pointer then doesn't
    /// change its plane.
    var fm3dBusy: Bool { get }
    /// Takes the 3D view's work plane as the tool's placement plane (its Base, Height Offset from, Depth from…).
    func fm3dAdopt(_ p: FurniturePlacement3D)
}

extension FurnitureTool3D {
    public var fm3dPicks: Bool { false }
    public var fm3dDepth: Double? { nil }
    public var fm3dBusy: Bool { false }
    public func fm3dAdopt(_ p: FurniturePlacement3D) {}
}

extension FurnitureDesignView {
    /// View ▸ 3D Design: the document's 3D Design view, made on first use in documents from before it existed.
    @MainActor public static func open(in s: DocumentSession) -> ElementID? {
        if let v = s.model.views.first(where: { $0.name == name && $0.view?.kind == .threeD }) { return v.id }
        var id: ElementID?
        s.perform("3D Design") { tx in id = ensure(in: tx) }
        return id
    }
}
