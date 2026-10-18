import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// F1: Wall: Reveal (RevitCraft `Cmd::WallReveal`, `place_wall_sweep` with reveal = true in crates/rc-app/src/canvas_tools.rs):
// click a wall face in an elevation, section or 3D view; the groove runs along the wall (Horizontal) or up it
// (Vertical) through the clicked point. The tool stays active for more reveals.

/// Places reveals on wall faces.
@MainActor
public final class WallRevealTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.wallReveal
    public let title = "Place Reveal"
    public var orientation = WallRevealData.Orientation.horizontal
    /// Groove size: RevitCraft's 50 × 20 mm (2" × 3/4" in imperial projects).
    public var width: Double
    public var depth: Double

    public override init(ctx: ToolContext) {
        let imperial = ctx.units.system == .imperial
        width = imperial ? 0.0508 : 0.05
        depth = imperial ? 0.01905 : 0.02
        super.init(ctx: ctx)
    }

    /// In 3D the tool runs in a plan context and reads the face point from the pick.
    func in3D(_ i: ToolInput) -> Bool { ctx.isPlan && i.surfacePoint != nil }

    public var prompt: String {
        guard ctx.isVertical || ctx.isPlan else { return "Reveals are placed in 3D, elevation and section views." }
        return "Click on a wall face to place the reveal."
    }

    public var options: [ToolOption] {
        [ToolOption(id: "orientation", label: "Placement", kind: .choice(WallRevealData.Orientation.allCases.map(\.rawValue)), value: .text(orientation.rawValue)),
         ToolOption(id: "width", label: "Width", kind: .length, value: .double(width)),
         ToolOption(id: "depth", label: "Depth", kind: .length, value: .double(depth))]
    }

    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "orientation": orientation = WallRevealData.Orientation(rawValue: value.textValue ?? "") ?? orientation
        case "width": if let d = value.doubleValue, d > Tolerance.length { width = d }
        case "depth": if let d = value.doubleValue, d > Tolerance.length { depth = d }
        default: break
        }
    }

    /// The clicked face: the wall, the station along it, the elevation and the side.
    struct Pick { var wall: Element; var station: Double; var z: Double; var side: WallSweep.Side }

    func pick(_ i: ToolInput) -> Pick? {
        let m = ctx.model
        if in3D(i), let p = i.surfacePoint {
            guard let w = hit(i, [.walls]), WallReveals.canHost(w, m), let f = WallGeometry.frame(w, m), let seg = f.location.asSegment else { return nil }
            let s = (p.xy - seg.start).dot(seg.direction), t = (p.xy - seg.start).dot(seg.normal)
            guard s >= -1e-6, s <= f.length + 1e-6, p.z >= f.baseZ - 1e-6, p.z <= f.topZ + 1e-6 else { return nil }
            let side: WallSweep.Side = abs(t - f.exteriorOffset) <= abs(t - f.interiorOffset) ? .exterior : .interior
            return Pick(wall: w, station: s, z: p.z, side: side)
        }
        guard ctx.isVertical, let vd = ctx.viewData, let o = vd.planeOrigin, let fwd = vd.viewDirection?.normalized else { return nil }
        // The wall under the pointer, else the nearest wall in front whose face spans the pointer.
        var candidates: [Element] = []
        if let w = hit(i, [.walls]) { candidates.append(w) }
        let rest = m.elements(.walls).filter { w in !candidates.contains { $0.id == w.id } }
            .compactMap { w -> (Element, Double)? in
                guard let f = WallGeometry.frame(w, m), let seg = f.location.asSegment, i.rawPoint.y >= f.baseZ, i.rawPoint.y <= f.topZ,
                      let s = station(i.rawPoint.x, w) else { return nil }
                let depth = (seg.point(at: s / f.length) - o.xy).dot(fwd)
                return depth >= -0.01 && depth <= vd.farClip ? (w, depth) : nil
            }
            .sorted { $0.1 < $1.1 }.map(\.0)
        for w in candidates + rest {
            guard WallReveals.canHost(w, m), let f = WallGeometry.frame(w, m), let seg = f.location.asSegment,
                  let s = station(i.rawPoint.x, w) else { continue }
            // The face looking at the viewer.
            let exteriorOut = seg.normal * (f.exteriorOffset >= f.interiorOffset ? 1 : -1)
            let side: WallSweep.Side = exteriorOut.dot(fwd) < 0 ? .exterior : .interior
            return Pick(wall: w, station: s, z: min(max(i.rawPoint.y, f.baseZ), f.topZ), side: side)
        }
        return nil
    }

    /// Station along a straight wall under view coordinate u, when the view faces the wall.
    func station(_ u: Double, _ w: Element) -> Double? {
        guard let vd = ctx.viewData, let f = WallGeometry.frame(w, ctx.model),
              let s = CurtainWallGeometry.station(ofViewU: u, view: vd, wall: f), s >= -1e-6, s <= f.length + 1e-6 else { return nil }
        return s
    }

    /// The reveal a click at `p` makes.
    func reveal(_ p: Pick) -> WallRevealData? {
        guard let f = WallGeometry.frame(p.wall, ctx.model) else { return nil }
        let offset = orientation == .horizontal ? p.z - f.baseZ : p.station
        return WallRevealData(orientation: orientation, offset: offset, side: p.side, width: width, depth: depth)
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let p = pick(i) else { return }
        preview.highlight = [p.wall.id]
        preview.cursor = .pick
        guard ctx.isVertical, let f = WallGeometry.frame(p.wall, ctx.model), let vd = ctx.viewData, let o = vd.planeOrigin, let r = vd.rightVector,
              let seg = f.location.asSegment else { return }
        // The groove's centre line on the face.
        func u(_ s: Double) -> Double { (seg.point(at: s / f.length) - o.xy).dot(r) }
        let line: [Vec2] = orientation == .horizontal ? [Vec2(u(0), p.z), Vec2(u(f.length), p.z)] : [Vec2(u(p.station), f.baseZ), Vec2(u(p.station), f.topZ)]
        preview.primitives = [.polyline(line, closed: false, ctx.previewHeavy)]
    }

    public func pointerDown(_ i: ToolInput) {
        guard let p = pick(i), let data = reveal(p) else {
            message(ctx.isVertical || in3D(i) ? "Reveals are placed on straight walls. Click a wall face." : "Open a 3D, elevation or section view and click a wall face.")
            return
        }
        Self.place(data, on: p.wall, session: ctx.session)
        if let e = ctx.session.lastError { message(e.message) }
        pointerMoved(i)
    }

    public func escape() -> EscapeResult { .exitTool }

    /// Adds a reveal to a wall (shared by the tool and tests).
    @discardableResult
    public static func place(_ data: WallRevealData, on wall: Element, session: DocumentSession) -> ElementID? {
        guard WallReveals.canHost(wall, session.model) else { return nil }
        var id: ElementID?
        session.perform("Wall Reveal") { tx in
            id = tx.create(.reveals, name: "Reveal", data: .wallReveal(data), levelID: wall.levelID, hostID: wall.id)
        }
        return session.lastError == nil ? id : nil
    }
}
