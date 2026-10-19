import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

/// Dimensions: pick references in sequence, then click in empty space to place the dimension line.
@MainActor
public final class DimensionTool: BaseTool, InteractiveTool {
    public let kind: DimensionKind
    public var commandID: CommandID {
        switch kind {
        case .aligned: .alignedDimension
        case .linear: .linearDimension
        case .angular: .angularDimension
        case .radial: .radialDimension
        case .diameter: .diameterDimension
        case .arcLength: .arcLengthDimension
        }
    }
    public var title: String { "\(kind.rawValue) Dimension" }
    public enum Preference: String, CaseIterable, Sendable { case wallCenterlines = "Wall centerlines", wallFaces = "Wall faces", coreFaces = "Wall core faces" }
    /// Individual references (one click per reference) or every reference of a picked wall at once.
    public enum Pick: String, CaseIterable, Sendable { case individual = "Individual References", entireWalls = "Entire Walls" }
    public var preference: Preference = .wallFaces
    public var pick: Pick = .individual
    /// Continuous, baseline (stacked from the first reference) or ordinate strings.
    public var chainStyle: DimensionChainStyle = .continuous
    public var entireWallOptions = EntireWallOptions()
    var refs: [GeometryReference] = []
    var points: [Vec2] = []
    /// The wall whose references were collected in Entire Walls mode.
    var pickedWall: ElementID?
    var supportsEntireWalls: Bool { kind == .aligned || kind == .linear }

    public init(ctx: ToolContext, kind: DimensionKind) { self.kind = kind; super.init(ctx: ctx) }
    var needed: Int { kind == .radial || kind == .diameter || kind == .arcLength ? 1 : 2 }
    public var prompt: String {
        switch kind {
        case .radial, .diameter, .arcLength: return refs.isEmpty ? "Click an arc wall, grid or line." : "Click to place the dimension."
        case .angular: return refs.count < 2 ? "Click two lines or walls that form an angle." : "Click to place the angle dimension."
        default:
            if pick == .entireWalls && supportsEntireWalls { return pickedWall == nil ? "Click a straight wall to dimension it end to end." : "Click to place the dimension line." }
            return refs.count < 2 ? "Click references (walls, grids, lines, points). Click empty space to place after two or more." : "Click another reference, or click in empty space to place the dimension."
        }
    }
    public var options: [ToolOption] {
        guard supportsEntireWalls else { return [] }
        var o = [ToolOption(id: "pref", label: "Prefer", kind: .choice(Preference.allCases.map(\.rawValue)), value: .text(preference.rawValue)),
                 ToolOption(id: "pick", label: "Pick", kind: .choice(Pick.allCases.map(\.rawValue)), value: .text(pick.rawValue)),
                 ToolOption(id: "style", label: "Style", kind: .choice(DimensionChainStyle.allCases.map(\.rawValue)), value: .text(chainStyle.rawValue))]
        if pick == .entireWalls {
            o += [ToolOption(id: "openings", label: "Openings", kind: .choice(EntireWallOptions.Openings.allCases.map(\.rawValue)), value: .text(entireWallOptions.openings.rawValue)),
                  ToolOption(id: "walls", label: "Intersecting Walls", kind: .bool, value: .bool(entireWallOptions.intersectingWalls)),
                  ToolOption(id: "grids", label: "Intersecting Grids", kind: .bool, value: .bool(entireWallOptions.intersectingGrids))]
        }
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "pref": if let p = Preference(rawValue: value.textValue ?? "") { preference = p }
        case "pick":
            if let p = Pick(rawValue: value.textValue ?? ""), p != pick { pick = p; refs = []; points = []; pickedWall = nil; preview = ToolPreview() }
        case "style": if let c = DimensionChainStyle(rawValue: value.textValue ?? "") { chainStyle = c }
        case "openings": if let o = EntireWallOptions.Openings(rawValue: value.textValue ?? "") { entireWallOptions.openings = o }
        case "walls": entireWallOptions.intersectingWalls = value.boolValue ?? false
        case "grids": entireWallOptions.intersectingGrids = value.boolValue ?? false
        default: break
        }
    }

    /// Entire Walls: collects the picked wall's references (ends, openings, intersecting walls and grids).
    func pickEntireWall(_ i: ToolInput) -> Bool {
        guard let id = i.hit ?? i.hitCandidates.first(where: { ctx.model[$0]?.wall != nil }), let wall = ctx.model[id], wall.wall != nil else {
            message("Click a wall."); return false
        }
        var options = entireWallOptions
        options.preference = preference
        guard let found = EntireWallDimension.references(wall: wall, options: options, ctx.model), found.count >= 2 else {
            message("Entire Walls dimensions need a straight wall."); return false
        }
        refs = found
        points = found.map { DimensionQueries.resolve($0, ctx.model)?.point ?? i.rawPoint }
        pickedWall = id
        return true
    }

    /// Converts a click into a geometry reference.
    func reference(for i: ToolInput) -> (GeometryReference, Vec2)? {
        if let r = fmg1PartFaceReference(i) { return r } // FMG1: furniture part faces
        if let id = i.hit, let e = ctx.model[id] {
            switch e.data {
            case .wall:
                guard let f = WallGeometry.frame(e, ctx.model) else { break }
                let kinds: [GeometryReference.Kind]
                switch preference {
                case .wallCenterlines: kinds = [.location]
                case .wallFaces: kinds = [.exteriorFace, .interiorFace]
                case .coreFaces: kinds = [.coreExterior, .coreInterior]
                }
                // W2-ANNOT: faces are compared in the view (vertical lines at their station in sections and elevations).
                let best = kinds.min { a, b in
                    (AnnotationGeometry.resolve(GeometryReference(id, a), ctx.model, view: ctx.view).map { lineDistance($0, i.rawPoint) } ?? .infinity) <
                    (AnnotationGeometry.resolve(GeometryReference(id, b), ctx.model, view: ctx.view).map { lineDistance($0, i.rawPoint) } ?? .infinity)
                }
                _ = f
                if let k = best, AnnotationGeometry.resolve(GeometryReference(id, k), ctx.model, view: ctx.view) != nil { return (GeometryReference(id, k), i.rawPoint) }
            case .grid, .referencePlane, .modelLine:
                if AnnotationGeometry.resolve(GeometryReference(id, .location), ctx.model, view: ctx.view) != nil { return (GeometryReference(id, .location), i.rawPoint) }
            case .level:
                return (GeometryReference(id, .levelPlane), i.rawPoint)
            case .insert:
                let refL = GeometryReference(id, .openingLeft), refR = GeometryReference(id, .openingRight)
                let dl = AnnotationGeometry.resolve(refL, ctx.model, view: ctx.view).map { lineDistance($0, i.rawPoint) } ?? .infinity
                let dr = AnnotationGeometry.resolve(refR, ctx.model, view: ctx.view).map { lineDistance($0, i.rawPoint) } ?? .infinity
                if dl.isFinite || dr.isFinite { return (dl < dr ? refL : refR, i.rawPoint) }
            case .column, .component:
                if AnnotationGeometry.resolve(GeometryReference(id, .center), ctx.model, view: ctx.view) != nil { return (GeometryReference(id, .center), i.rawPoint) }
            default: break
            }
        }
        if let s = i.snap { return (.fixed(s.point), s.point) }
        return nil
    }

    func lineDistance(_ r: (point: Vec2, direction: Vec2?), _ p: Vec2) -> Double {
        guard let d = r.direction else { return r.point.distance(to: p) }
        return abs(d.cross(p - r.point))
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        preview.cursor = .crosshair
        if pick == .entireWalls && supportsEntireWalls && pickedWall == nil {
            if let id = i.hit, ctx.model[id]?.wall != nil { preview.highlight = [id]; preview.cursor = .pick }
            return
        }
        guard refs.count >= needed else {
            if let (r, _) = reference(for: i), let id = r.elementID { preview.highlight = [id]; preview.cursor = .pick }
            return
        }
        var d = DimensionData(kind: kind, references: refs, linePoint: i.rawPoint, fallbackPoints: points)
        d.chainStyle = supportsEntireWalls && chainStyle != .continuous ? chainStyle : nil
        if let w = pickedWall, let dir = ctx.model[w]?.wall?.location.asSegment?.direction { d.direction = kind == .linear ? nil : dir.angle }
        if kind == .linear {
            let v = i.rawPoint - (points.first ?? .zero)
            d.direction = abs(v.x) > abs(v.y) ? .pi / 2 : 0
        }
        let probe = Element(id: ElementID(UInt64.max - 3), category: .dimensions, data: .dimension(d), typeID: ctx.type(for: .dimensions), ownerViewID: ctx.viewID)
        if let prims = AnnotationRenderer.previewItem(probe, model: ctx.model, scale: ctx.isSheet ? 1 : ctx.scale) {
            preview.primitives = AnnotationPreview.tinted(prims, ctx.previewStroke.color)
        }
    }

    public func pointerDown(_ i: ToolInput) {
        if pick == .entireWalls && supportsEntireWalls && pickedWall == nil { _ = pickEntireWall(i); return }
        let r = reference(for: i)
        let placing = refs.count >= needed && (pickedWall != nil || r == nil || r?.0.kind == .point || kind == .radial || kind == .diameter || kind == .arcLength || kind == .angular)
        if placing {
            var d = DimensionData(kind: kind, references: refs, linePoint: i.rawPoint, fallbackPoints: points)
            d.chainStyle = supportsEntireWalls && chainStyle != .continuous ? chainStyle : nil
            if let w = pickedWall, let dir = ctx.model[w]?.wall?.location.asSegment?.direction, kind == .aligned { d.direction = dir.angle }
            if kind == .linear {
                let v = i.rawPoint - (points.first ?? .zero)
                d.direction = abs(v.x) > abs(v.y) ? .pi / 2 : 0
            }
            let view = ctx.viewID
            let type = ctx.type(for: .dimensions) // W2-ANNOT: the type selector's dimension type
            ctx.session.perform("Create Dimension") { tx in tx.create(.dimensions, data: .dimension(d), typeID: type, ownerViewID: view) }
            if let err = ctx.session.lastError { message(err.message) }
            refs = []; points = []; pickedWall = nil
            preview = ToolPreview()
            return
        }
        guard let (ref, p) = r else { message("Click a wall, grid, line or snap point."); return }
        if kind == .angular, ref.elementID == nil { message("Angular dimensions need two lines."); return }
        refs.append(ref)
        points.append(p)
    }
    public func escape() -> EscapeResult {
        if !refs.isEmpty { refs = []; points = []; pickedWall = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Entire-wall dimensions

/// What an Entire Walls dimension references besides the wall ends.
public struct EntireWallOptions: Sendable, Hashable {
    public enum Openings: String, CaseIterable, Sendable { case none = "None", centers = "Centers", widths = "Widths" }
    public var openings: Openings = .widths
    public var intersectingWalls = false
    public var intersectingGrids = false
    /// Which wall lines count as references (faces, centerlines or core faces).
    public var preference: DimensionTool.Preference = .wallFaces
    public init(openings: Openings = .widths, intersectingWalls: Bool = false, intersectingGrids: Bool = false, preference: DimensionTool.Preference = .wallFaces) {
        self.openings = openings; self.intersectingWalls = intersectingWalls; self.intersectingGrids = intersectingGrids; self.preference = preference
    }
}

/// References for dimensioning a straight wall end to end: its ends (the outer face of a wall joined at a corner, the
/// near face of a wall it tees into, otherwise the wall end), door and window centres or both edges, walls crossing or
/// teeing into it, and grids crossing it. Sorted along the wall; references at the same position are merged.
public enum EntireWallDimension {
    public static func references(wall: Element, options: EntireWallOptions, _ model: BIMModel) -> [GeometryReference]? {
        guard let f = WallGeometry.frame(wall, model), let seg = f.location.offset(by: f.centerOffset).asSegment, seg.length > Tolerance.length else { return nil }
        let dir = seg.direction
        func station(_ r: GeometryReference) -> Double? { DimensionQueries.resolve(r, model).map { ($0.point - seg.start).dot(dir) } }
        var found: [(GeometryReference, Double)] = []
        func add(_ r: GeometryReference) { if let s = station(r) { found.append((r, s)) } }
        let lineKinds: [GeometryReference.Kind]
        switch options.preference {
        case .wallCenterlines: lineKinds = [.location]
        case .wallFaces: lineKinds = [.exteriorFace, .interiorFace]
        case .coreFaces: lineKinds = [.coreExterior, .coreInterior]
        }
        let endPartners = Set([false, true].flatMap { WallGeometry.endJoin(wall, atEnd: $0, model).others })

        // Ends.
        for atEnd in [false, true] {
            let join = WallGeometry.endJoin(wall, atEnd: atEnd, model)
            let own = GeometryReference(wall.id, atEnd ? .endPoint : .startPoint)
            guard join.kind != .free, let other = join.others.first.flatMap({ model[$0] }), other.wall != nil else { add(own); continue }
            let candidates = lineKinds.compactMap { k -> (GeometryReference, Double)? in
                let r = GeometryReference(other.id, k)
                return station(r).map { (r, $0) }
            }
            guard !candidates.isEmpty else { add(own); continue }
            // Outward = away from the wall's middle. A corner uses the partner's outer line; a tee its near line.
            let outward: (Double) -> Double = { atEnd ? $0 : -$0 }
            let sorted = candidates.sorted { outward($0.1) < outward($1.1) }
            let primary = join.kind == .corner ? sorted.last! : sorted.first!
            found.append(primary)
            if options.intersectingWalls { for c in sorted where c.0 != primary.0 { found.append(c) } }
        }

        // Openings.
        if options.openings != .none {
            for ins in model.hosted(by: wall.id) where ins.insert != nil {
                if options.openings == .centers { add(GeometryReference(ins.id, .center)) } else {
                    add(GeometryReference(ins.id, .openingLeft)); add(GeometryReference(ins.id, .openingRight))
                }
            }
        }

        // Walls crossing or teeing into this wall between its ends.
        let margin = f.thickness / 2 + 0.01
        if options.intersectingWalls {
            for w in model.elements(.walls) where w.id != wall.id && w.levelID == wall.levelID && !endPartners.contains(w.id) {
                guard let of = WallGeometry.frame(w, model), let os = of.location.offset(by: of.centerOffset).asSegment, os.length > Tolerance.length,
                      !os.isParallel(to: seg), let hit = os.lineIntersection(seg) else { continue }
                let reach = margin / os.length
                guard hit.t >= -reach, hit.t <= 1 + reach, hit.u > 1e-4, hit.u < 1 - 1e-4 else { continue }
                for k in lineKinds { add(GeometryReference(w.id, k)) }
            }
        }
        if options.intersectingGrids {
            for g in model.elements(.grids) {
                guard g.grid?.isMultiSegment != true, let gs = g.grid?.curve.asSegment, !gs.isParallel(to: seg), let hit = gs.lineIntersection(seg),
                      hit.t >= -0.001, hit.t <= 1.001, hit.u >= -1e-4, hit.u <= 1 + 1e-4 else { continue }
                add(GeometryReference(g.id, .location))
            }
        }

        var out: [(GeometryReference, Double)] = []
        for item in found.sorted(by: { $0.1 < $1.1 }) where !out.contains(where: { abs($0.1 - item.1) < 1e-4 }) { out.append(item) }
        return out.map(\.0)
    }
}

/// Section: two clicks in plan define the section line; the view looks to the left of the drawn direction.
@MainActor
public final class SectionTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.section
    public let title = "Section"
    var start: Vec2?
    public var farClip = 12.0
    public var flip = false
    public var prompt: String { start == nil ? "Click the start of the section line." : "Click the end of the section line (it looks to the left; Space flips)." }
    public var snapFrom: Vec2? { start }
    public var options: [ToolOption] { [ToolOption(id: "far", label: "Far Clip", kind: .length, value: .double(farClip))] }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "far", let d = value.doubleValue, d > 0 { farClip = d } }
    public func spaceBar() { flip.toggle() }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let s = start, s.distance(to: i.point) > 1e-6 else { return }
        let dir = (i.point - s).normalized
        let look = flip ? -dir.perpendicular : dir.perpendicular
        preview.primitives = [ctx.line(s, i.point, heavy: true),
                              .polyline([s, s + look * farClip, i.point + look * farClip, i.point], closed: false, GStroke(weight: 1, color: RGBColor(0.18, 0.43, 0.66), pattern: .dash))]
        preview.tempDims = [tempDim(s, i.point)]
    }
    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Draw sections in a plan view."); return }
        guard let s = start else { start = i.point; return }
        guard s.distance(to: i.point) > 0.1 else { return }
        let dir = (i.point - s).normalized
        let look = flip ? -dir.perpendicular : dir.perpendicular
        // Origin at the start when looking left; at the end when flipped so that u runs left→right on screen.
        var v = ViewData(kind: .section, scale: ctx.scale)
        v.viewDirection = look
        let right = v.rightVector ?? dir
        let origin = right.dot(dir) > 0 ? s : i.point
        v.planeOrigin = Vec3(origin, z: 0)
        let length = s.distance(to: i.point)
        let zs = ctx.model.levels.compactMap { $0.level?.elevation }
        v.cropRegion = Rect2(min: Vec2(0, (zs.min() ?? 0) - 1.5), max: Vec2(length, (zs.max() ?? 3) + 3))
        v.cropActive = true
        v.farClip = farClip
        v.phaseID = ctx.model.latestPhase?.id
        let n = ctx.model.views.filter { $0.view?.kind == .section }.count + 1
        ctx.session.perform("Create Section") { tx in tx.create(.views, name: "Section \(n)", data: .view(v)) }
        if let e = ctx.session.lastError { message(e.message) } else { message("Created “Section \(n)”. Double-click the section head to open it.") }
        start = nil
        preview = ToolPreview()
    }
    public func escape() -> EscapeResult { if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }; return .exitTool }
}

