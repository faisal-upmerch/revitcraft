import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// F34: sketch-mode finishes of Structure ▸ Beam System and the boundary-based reinforcement (Area, Path,
// Fabric Area), as RevitCraft's finish_sketch does them.

/// What an F34 sketch creates.
public enum F34SketchTarget: Sendable, Equatable {
    case beamSystem
    case areaReinforcement(host: ElementID)
    case pathReinforcement(host: ElementID)
    case fabricArea(host: ElementID)

    public var title: String {
        switch self {
        case .beamSystem: "Beam System Boundary"
        case .areaReinforcement: "Area Reinforcement Boundary"
        case .pathReinforcement: "Path Reinforcement"
        case .fabricArea: "Fabric Area Boundary"
        }
    }
    public var isOpenPath: Bool { if case .pathReinforcement = self { return true }; return false }
    public var host: ElementID? {
        switch self {
        case .beamSystem: nil
        case .areaReinforcement(let h), .pathReinforcement(let h), .fabricArea(let h): h
        }
    }
}

extension SketchTool {
    /// RevitCraft's default bar spacing (300 mm / 1'-0") and path bar length (1800 mm / 6'-0").
    var f34Spacing: Double { ctx.units.system == .imperial ? 0.3048 : 0.3 }
    var f34PathLength: Double { ctx.units.system == .imperial ? 1.8288 : 1.8 }

    /// Sketch points in the host's reinforcement coordinates: plan points for floors, face points for walls.
    func f34HostPoints(_ pts: [Vec2], host: ElementID) -> [Vec2]? {
        guard Reinforcement.isWallHosted(ctx.model, host) else { return pts }
        guard let v = ctx.viewData else { return nil }
        let out = pts.compactMap { Reinforcement.wallFacePoint($0, view: v, host: host, ctx.model) }
        return out.count == pts.count ? out : nil
    }

    /// The direction of the first sketched line (the major direction / beam direction), in host coordinates.
    func f34FirstDirection(host: ElementID?) -> Vec2 {
        guard let c = curves.first else { return .unitX }
        let ends = host.flatMap { f34HostPoints([c.start, c.end], host: $0) } ?? [c.start, c.end]
        let d = ends[1] - ends[0]
        return d.lengthSquared > 1e-12 ? d.normalized : .unitX
    }

    /// Closed sketches: beam systems, area reinforcement and fabric areas.
    func f34Commit(_ t: F34SketchTarget, _ sketch: Sketch, view: ElementID, level: ElementID?) {
        guard case .success(let polys) = sketch.polygons(), let outline = polys.max(by: { $0.area < $1.area })?.counterClockwise else { return }
        let model = ctx.model
        let inPlan = ctx.isPlan
        var created: ElementID?
        switch t {
        case .beamSystem:
            let type = ctx.type(for: .structuralFraming)
            let spacing = StructuralFraming.beamSystemSpacing(model)
            var pts = outline.points
            // The beams run along the first sketched line: start the boundary there.
            if let first = curves.first, let k = pts.firstIndex(where: { $0.isAlmostEqual(first.start, tolerance: 1e-6) || $0.isAlmostEqual(first.end, tolerance: 1e-6) }) {
                pts = Array(pts[k...] + pts[..<k])
            }
            let dir = f34FirstDirection(host: nil)
            ctx.session.perform("Create Beam System") { tx in
                let id = try StructuralFraming.beamSystem(boundary: pts, spacing: spacing, beamType: type, level: level, in: tx)
                tx.update(id) { $0.beamSystem?.direction = dir }
                // Its symbol, as the reference app places it.
                if inPlan { tx.create(.genericAnnotations, data: .structuralSymbol(StructuralSymbolData(kind: .beamSystem, position: outline.centroid)), hostID: id, ownerViewID: view) }
                created = id
            }
        case .areaReinforcement(let host), .fabricArea(let host):
            guard let boundary = f34HostPoints(outline.points, host: host) else { message("Sketch wall reinforcement in a section or elevation of the wall."); return }
            let major = f34FirstDirection(host: host)
            let spacing = f34Spacing
            let hostLevel = model[host]?.levelID
            let wallHosted = Reinforcement.isWallHosted(model, host)
            ctx.session.perform(t == .fabricArea(host: host) ? "Create Fabric Area" : "Create Area Reinforcement") { tx in
                let ccw = Polygon2(boundary).counterClockwise.points
                if case .fabricArea = t {
                    let ft = Reinforcement.ensureFabricType(in: tx)
                    let p = tx.model[ft]?.typeData?.params ?? [:]
                    let data = FabricAreaData(boundary: ccw, major: major, fabricTypeID: ft,
                                              majorLap: p[Reinforcement.fabricMajorLapParameter]?.doubleValue ?? 0.2, minorLap: p[Reinforcement.fabricMinorLapParameter]?.doubleValue ?? 0.2)
                    created = tx.create(.fabricAreas, data: .fabricArea(data), levelID: hostLevel, hostID: host)
                } else {
                    Reinforcement.ensureBarTypes(in: tx)
                    let bt = Reinforcement.defaultBarType(tx.model)
                    let data = AreaReinforcementData(boundary: ccw, major: major, layers: Array(repeating: RebarLayer(barTypeID: bt, spacing: spacing), count: 4))
                    let id = tx.create(.areaReinforcement, data: .areaReinforcement(data), levelID: hostLevel, hostID: host)
                    // Its symbol and tag (floors; wall reinforcement shows its tag on the wall).
                    if !wallHosted, inPlan { tx.create(.genericAnnotations, data: .structuralSymbol(StructuralSymbolData(kind: .areaReinforcement, position: outline.centroid)), hostID: id, ownerViewID: view) }
                    created = id
                }
            }
        case .pathReinforcement:
            return
        }
        if ctx.session.lastError == nil, let created { ctx.session.selection.select([created]) }
    }

    /// Path reinforcement: one or more connected lines.
    func f34FinishPath(_ t: F34SketchTarget) -> Bool {
        guard case .pathReinforcement(let host) = t else { return false }
        guard let chain = F34Sketch.chain(curves) else { message("Sketch the path: one or more connected lines."); return false }
        guard let path = f34HostPoints(chain, host: host) else { message("Sketch wall reinforcement in a section or elevation of the wall."); return false }
        let (spacing, length) = (f34Spacing, f34PathLength)
        let view = ctx.viewID, inPlan = ctx.isPlan
        let hostLevel = ctx.model[host]?.levelID
        let wallHosted = Reinforcement.isWallHosted(ctx.model, host)
        var created: ElementID?
        ctx.session.perform("Create Path Reinforcement") { tx in
            Reinforcement.ensureBarTypes(in: tx)
            let data = PathReinforcementData(path: path, barTypeID: Reinforcement.defaultBarType(tx.model), spacing: spacing, length: length)
            let id = tx.create(.pathReinforcement, data: .pathReinforcement(data), levelID: hostLevel, hostID: host)
            if !wallHosted, inPlan {
                tx.create(.genericAnnotations, data: .structuralSymbol(StructuralSymbolData(kind: .pathReinforcement, position: (chain[0] + chain[1]) / 2)), hostID: id, ownerViewID: view)
            }
            created = id
        }
        if ctx.session.lastError == nil, let created { ctx.session.selection.select([created]) }
        return ctx.session.lastError == nil
    }
}

enum F34Sketch {
    /// The points of an open chain of lines drawn end to end (arcs are tessellated); nil when the lines don't connect.
    static func chain(_ curves: [Curve2]) -> [Vec2]? {
        guard let first = curves.first else { return nil }
        let tol = Tolerance.length * 10
        var pts = first.tessellate(chordTolerance: 0.01)
        for c in curves.dropFirst() {
            var q = c.tessellate(chordTolerance: 0.01)
            if let last = pts.last, q.last?.isAlmostEqual(last, tolerance: tol) == true, q.first?.isAlmostEqual(last, tolerance: tol) != true { q.reverse() }
            guard let last = pts.last, let head = q.first, head.isAlmostEqual(last, tolerance: tol) else { return nil }
            pts += q.dropFirst()
        }
        var out: [Vec2] = []
        for p in pts where out.last.map({ $0.distance(to: p) > 0.001 }) ?? true { out.append(p) }
        return out.count >= 2 ? out : nil
    }
}
