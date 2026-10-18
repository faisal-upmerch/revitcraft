import Foundation
import ArcusGeometry

// F1415: the Family Editor's sketch mode (RevitCraft `crates/rc-app/src/family_editor.rs` `finish_sketch`): view frames for
// the six family views, sketched loops and paths whose points lock to the reference planes they snap to, and the forms,
// regions, openings and lines they become. Kept in the Domain so it can be unit-tested without the window.

extension FamilyEditing {
    // MARK: Views

    /// How a 2D family view shows the family: its sketch plane and whether its horizontal axis runs against the plane's
    /// u axis (Back and Left look the other way, as in RevitCraft, so their horizontal axis is mirrored).
    public struct ViewFrame: Equatable, Sendable {
        public var plane: FamilySketchPlane
        public var uSign: Double
        public init(plane: FamilySketchPlane, uSign: Double = 1) { self.plane = plane; self.uSign = uSign }
        public static let plan = ViewFrame(plane: .xy)
        public static let front = ViewFrame(plane: .xz)
        public static let back = ViewFrame(plane: .xz, uSign: -1)
        public static let right = ViewFrame(plane: .yz)
        public static let left = ViewFrame(plane: .yz, uSign: -1)

        public var isElevation: Bool { plane != .xy }
        /// Sketch coordinates (the plane's u, v) of a view point, and back.
        public func sketch(_ view: Vec2) -> Vec2 { Vec2(view.x * uSign, view.y) }
        public func view(_ sketch: Vec2) -> Vec2 { Vec2(sketch.x * uSign, sketch.y) }
        /// A family point seen in this view.
        public func project(_ p: Vec3) -> Vec2 {
            switch plane {
            case .xy: Vec2(p.x, p.y)
            case .xz: Vec2(p.x * uSign, p.z)
            case .yz: Vec2(p.y * uSign, p.z)
            }
        }
        /// The plan direction of the sketch plane's u axis (elevations).
        public var uAxisPlan: Vec2 { plane == .yz ? Vec2(0, 1) : Vec2(1, 0) }
        /// Sign of "into the screen" along the plane's normal: up in plan, +Y in Front, −Y in Back, −X in Right, +X in Left.
        public var depthSign: Double {
            switch plane {
            case .xy: 1
            case .xz: uSign
            case .yz: -uSign
            }
        }
    }

    // MARK: Sketch

    /// A sketched point in sketch coordinates; a coordinate snapped to a reference plane carries the plane's name and
    /// locks to it.
    public struct SketchVertex: Equatable, Sendable {
        public var u: Double, v: Double
        public var uPlane: String?, vPlane: String?
        public init(u: Double, v: Double, uPlane: String? = nil, vPlane: String? = nil) { self.u = u; self.v = v; self.uPlane = uPlane; self.vPlane = vPlane }
        public var point: Vec2 { Vec2(u, v) }
        public var familyPoint: FamilyPoint {
            FamilyPoint(uPlane.map { .plane($0) } ?? .expr(numberText(u)), vPlane.map { .plane($0) } ?? .expr(numberText(v)))
        }
    }

    /// Snaps a view point to the reference planes seen edge-on within `tolerance`, else to the millimetre, and returns it
    /// in sketch coordinates with the planes it locked to.
    public static func snapVertex(_ viewPoint: Vec2, frame: ViewFrame, planes: [PlaneLine], tolerance: Double) -> SketchVertex {
        var u = (viewPoint.x * 1000).rounded() / 1000, v = (viewPoint.y * 1000).rounded() / 1000
        var up: String?, vp: String?
        var bu = tolerance, bv = tolerance
        for pl in planes {
            if pl.vertical, abs(viewPoint.x - pl.value) < bu { bu = abs(viewPoint.x - pl.value); u = pl.value; up = pl.name }
            if !pl.vertical, abs(viewPoint.y - pl.value) < bv { bv = abs(viewPoint.y - pl.value); v = pl.value; vp = pl.name }
        }
        let s = frame.sketch(Vec2(u, v))
        return SketchVertex(u: s.x, v: s.y, uPlane: up, vPlane: vp)
    }

    /// What a sketch makes when it is finished.
    public enum SketchForm: String, Sendable, CaseIterable {
        case extrusion = "Extrusion", blend = "Blend", revolve = "Revolve", sweep = "Sweep", sweptBlend = "Swept Blend"
        case filledRegion = "Filled Region", maskingRegion = "Masking Region", opening = "Opening"
        public var isForm: Bool { [.extrusion, .blend, .revolve, .sweep, .sweptBlend].contains(self) }
    }

    /// A sketch in progress (sketch mode): the loop or path being drawn and the stages already finished.
    public struct Sketch: Equatable, Sendable {
        public var form: SketchForm
        public var isVoid: Bool
        /// Blend: 0 base, 1 top. Sweep: 0 path, 1 profile. Swept Blend: 0 path, 1 profile 1, 2 profile 2.
        public var stage = 0
        /// The view the current stage is drawn in.
        public var frame: ViewFrame
        public var vertices: [SketchVertex] = []
        /// Extrusion and blend depth (metres, into the screen from the work plane).
        public var depth: Double
        /// Where the sketch's work plane sits along its normal.
        public var offset: FamilyBound
        /// Revolve: the axis line's sketch u.
        public var axisU: Double = 0
        public var axisPlane: String?
        /// Finished stages: a blend's base loop; a sweep's path at height `pathZ`; a swept blend's first profile.
        public var base: [FamilyPoint] = []
        public var path: [FamilyPoint] = []
        public var pathZ: FamilyBound = .expr("0")
        public var firstProfile: [FamilyPoint] = []

        public init(form: SketchForm, isVoid: Bool = false, frame: ViewFrame, depth: Double = 0.25, offset: FamilyBound = .expr("0")) {
            self.form = form; self.isVoid = isVoid; self.frame = frame; self.depth = depth; self.offset = offset
        }

        /// True while the current stage is an open path (sweep and swept blend paths) rather than a closed loop.
        public var drawsPath: Bool { (form == .sweep || form == .sweptBlend) && stage == 0 }

        /// The contextual tab's title, as RevitCraft names sketch modes.
        public var title: String {
            switch form {
            case .extrusion: isVoid ? "Create Void Extrusion" : "Create Extrusion"
            case .blend: stage == 0 ? "Create Blend Base Boundary" : "Create Blend Top Boundary"
            case .revolve: isVoid ? "Create Void Revolve" : "Create Revolve"
            case .sweep: stage == 0 ? "Sweep > Sketch Path" : "Sweep > Edit Profile"
            case .sweptBlend: stage == 0 ? "Swept Blend > Sketch Path" : stage == 1 ? "Swept Blend > Edit Profile 1" : "Swept Blend > Edit Profile 2"
            case .filledRegion: "Create Filled Region Boundary"
            case .maskingRegion: "Create Masking Region Boundary"
            case .opening: "Create Opening Boundary"
            }
        }

        public var prompt: String {
            if drawsPath { return form == .sweptBlend ? "Click the start, then the end of the path (one segment). Finish Edit Mode (✓) when done." : "Click the points of the path. Finish Edit Mode (✓) when done." }
            switch form {
            case .revolve: return "Sketch the closed profile on one side of the axis (Axis Line sets it). Finish Edit Mode (✓) when done."
            case .opening: return "Sketch the opening's rectangle. Finish Edit Mode (✓) when done."
            default: return "Sketch a closed loop: click its corners (click the first again to close). Finish Edit Mode (✓) when done."
            }
        }
    }

    /// The outcome of Finish Edit Mode.
    public enum SketchResult: Sendable {
        /// The sketch moves to its next stage (a blend's top, a sweep's profile); the message says what to draw.
        case next(String)
        case solid(FamilySolid)
        case fill(FamilyFill)
        case opening(FamilyOpening)
        /// Nothing is made; the reason.
        case failed(String)
    }

    /// Finishes the current stage. `value` resolves a bound to metres (plane positions in the current type).
    public static func finish(_ s: inout Sketch, in f: FamilyDefinition, value: (FamilyBound) -> Double) -> SketchResult {
        let pts = s.vertices.map(\.familyPoint)
        func name(_ prefix: String) -> String {
            numberedName((s.isVoid ? "Void " : "") + prefix, count: f.solids.count) { n in f.solids.contains { $0.name == n } }
        }
        func loopOK() -> String? {
            guard s.vertices.count >= 3 else { return "Sketch a closed loop of at least three points." }
            let poly = Polygon2(s.vertices.map(\.point))
            guard !poly.isDegenerate else { return "The loop has no area." }
            guard poly.isSimple else { return "The loop crosses itself." }
            return nil
        }
        /// Depth bounds from the work plane: start at the plane, end `depth` into the screen.
        func depthBounds() -> (FamilyBound, FamilyBound) {
            let start = value(s.offset), d = s.depth * s.frame.depthSign
            let end = FamilyBound.expr(numberText(start + d))
            return d >= 0 ? (s.offset, end) : (end, s.offset)
        }
        switch s.form {
        case .extrusion:
            if let e = loopOK() { return .failed(e) }
            guard s.depth > Tolerance.length else { return .failed("Set an extrusion depth greater than zero.") }
            let (z0, z1) = depthBounds()
            var solid = FamilySolid(name: name("Extrusion"), profile: profile(s.vertices), zMin: z0, zMax: z1, isVoid: s.isVoid)
            if s.frame.plane != .xy { solid.workPlane = s.frame.plane }
            return .solid(solid)
        case .blend:
            guard s.frame.plane == .xy else { return .failed("Blends are sketched in the plan view.") }
            if let e = loopOK() { return .failed(e) }
            if s.stage == 0 {
                s.base = pts; s.vertices = []; s.stage = 1
                return .next("Sketch the top boundary of the blend.")
            }
            guard s.depth > Tolerance.length else { return .failed("Set a blend depth greater than zero.") }
            let (z0, z1) = depthBounds()
            return .solid(FamilySolid(name: name("Blend"), profile: .blend(FamilyBlend(bottom: s.base, top: pts)), zMin: z0, zMax: z1, isVoid: s.isVoid))
        case .revolve:
            guard s.frame.isElevation else { return .failed("Sketch a revolve's profile in an elevation view.") }
            if let e = loopOK() { return .failed(e) }
            let rs = s.vertices.map { $0.u - s.axisU }
            guard rs.allSatisfy({ $0 >= -Tolerance.length }) || rs.allSatisfy({ $0 <= Tolerance.length }) else {
                return .failed("The profile crosses the axis. Keep it on one side of the axis line.")
            }
            let axis = s.frame.plane == .xz ? FamilyPoint(s.axisPlane.map { .plane($0) } ?? .expr(numberText(s.axisU)), s.offset)
                                            : FamilyPoint(s.offset, s.axisPlane.map { .plane($0) } ?? .expr(numberText(s.axisU)))
            let profile = s.vertices.map { FamilyPoint(numberText(abs($0.u - s.axisU)), numberText($0.v)) }
            return .solid(FamilySolid(name: name("Revolve"), profile: .revolve(FamilyRevolve(profile: profile, axis: axis)),
                                      zMin: .expr("0"), zMax: .expr("0"), isVoid: s.isVoid))
        case .sweep, .sweptBlend:
            if s.stage == 0 {
                guard s.frame.plane == .xy else { return .failed("Sketch the path in the plan view.") }
                guard s.vertices.count >= 2 else { return .failed("Sketch a path of at least two points.") }
                if s.form == .sweptBlend && s.vertices.count != 2 { return .failed("A swept blend's path is one segment: click its start and end.") }
                s.path = pts; s.pathZ = s.offset; s.vertices = []; s.stage = 1
                return .next(s.form == .sweptBlend ? "Go to a view across the path and sketch profile 1 (at the path's start)." : "Go to a view across the path and sketch the profile.")
            }
            guard s.frame.isElevation else { return .failed("Sketch the profile in an elevation across the path (Go To View).") }
            if let e = loopOK() { return .failed(e) }
            let path = s.path.map { Vec2(value($0.x), value($0.y)) }
            let atEnd = s.form == .sweptBlend && s.stage == 2
            guard let station = profileStation(path, form: s.form, atEnd: atEnd) else { return .failed("The path has no length.") }
            let lateral = station.normal.dot(s.frame.uAxisPlan)
            guard abs(lateral) > 0.2 else { return .failed("This view is along the path. Go to a view across it to sketch the profile.") }
            let z0 = value(s.pathZ)
            let origin = station.point.dot(s.frame.uAxisPlan)
            let profile = s.vertices.map { FamilyPoint(numberText(($0.u - origin) / lateral), numberText($0.v - z0)) }
            if s.form == .sweep {
                return .solid(FamilySolid(name: name("Sweep"), profile: .sweep(FamilySweep(path: s.path, profile: profile)), zMin: s.pathZ, zMax: s.pathZ, isVoid: s.isVoid))
            }
            if s.stage == 1 {
                s.firstProfile = profile; s.vertices = []; s.stage = 2
                return .next("Sketch profile 2 (at the path's end).")
            }
            return .solid(FamilySolid(name: name("Swept Blend"), profile: .sweep(FamilySweep(path: s.path, profile: s.firstProfile, endProfile: profile)),
                                      zMin: s.pathZ, zMax: s.pathZ, isVoid: s.isVoid))
        case .filledRegion, .maskingRegion:
            guard s.frame.plane == .xy else { return .failed("Regions are sketched in the plan view.") }
            if let e = loopOK() { return .failed(e) }
            return .fill(FamilyFill(points: pts, pattern: .solid, isMasking: s.form == .maskingRegion))
        case .opening:
            guard s.frame.plane == .xz else { return .failed("Sketch the opening in the Front or Back elevation.") }
            guard f.template.isHostedInWall else { return .failed("Openings cut the host of wall-hosted families (doors and windows); this family isn't hosted.") }
            guard s.vertices.count >= 2 else { return .failed("Sketch the opening's rectangle.") }
            let us = s.vertices.sorted { $0.u < $1.u }, vs = s.vertices.sorted { $0.v < $1.v }
            guard let u0 = us.first, let u1 = us.last, let v0 = vs.first, let v1 = vs.last, u1.u - u0.u > Tolerance.length, v1.v - v0.v > Tolerance.length else {
                return .failed("The opening has no width or height.")
            }
            func bu(_ x: SketchVertex) -> FamilyBound { x.uPlane.map { .plane($0) } ?? .expr(numberText(x.u)) }
            func bv(_ x: SketchVertex) -> FamilyBound { x.vPlane.map { .plane($0) } ?? .expr(numberText(x.v)) }
            return .opening(FamilyOpening(xMin: bu(u0), xMax: bu(u1), zMin: bv(v0), zMax: bv(v1)))
        }
    }

    /// The profile plane of a sweep (the middle of the path's first segment, RevitCraft `sweep_frame`) or of a swept blend's
    /// start or end, with the path's left normal there.
    public static func profileStation(_ path: [Vec2], form: SketchForm, atEnd: Bool) -> (point: Vec2, normal: Vec2)? {
        var pts: [Vec2] = []
        for p in path where pts.last.map({ !$0.isAlmostEqual(p) }) ?? true { pts.append(p) }
        guard pts.count >= 2 else { return nil }
        if form == .sweptBlend {
            let a = atEnd ? pts[pts.count - 2] : pts[0], b = atEnd ? pts[pts.count - 1] : pts[1]
            return (atEnd ? b : a, (b - a).normalized.perpendicular)
        }
        return ((pts[0] + pts[1]) * 0.5, (pts[1] - pts[0]).normalized.perpendicular)
    }

    /// The elevation frames whose screen is (nearly) parallel to the profile plane at `normal`: Go To View's choices,
    /// best first.
    public static func profileViews(normal: Vec2) -> [ViewFrame] {
        [ViewFrame.front, .back, .right, .left]
            .filter { abs(normal.dot($0.uAxisPlan)) > 0.2 }
            .sorted { abs(normal.dot($0.uAxisPlan)) > abs(normal.dot($1.uAxisPlan)) }
    }

    /// A sketched loop as an extrusion profile: a rectangle when it is one (axis-aligned, four corners), keeping the plane
    /// locks of its sides, else a polygon.
    public static func profile(_ vs: [SketchVertex]) -> FamilySolid.Profile {
        if vs.count == 4 {
            let us = Set(vs.map { ($0.u * 1e6).rounded() }), ws = Set(vs.map { ($0.v * 1e6).rounded() })
            if us.count == 2, ws.count == 2 {
                let byU = vs.sorted { $0.u < $1.u }, byV = vs.sorted { $0.v < $1.v }
                func lockU(_ x: Double) -> FamilyBound { vs.first { abs($0.u - x) < 1e-9 && $0.uPlane != nil }?.uPlane.map { .plane($0) } ?? .expr(numberText(x)) }
                func lockV(_ y: Double) -> FamilyBound { vs.first { abs($0.v - y) < 1e-9 && $0.vPlane != nil }?.vPlane.map { .plane($0) } ?? .expr(numberText(y)) }
                return .rectangle(xMin: lockU(byU[0].u), xMax: lockU(byU[3].u), yMin: lockV(byV[0].v), yMax: lockV(byV[3].v))
            }
        }
        return .polygon(vs.map(\.familyPoint))
    }

    /// The four corners of a rectangle dragged from `a` to `b` (both in sketch coordinates), keeping each corner's locks.
    public static func rectangle(_ a: SketchVertex, _ b: SketchVertex) -> [SketchVertex] {
        [a, SketchVertex(u: b.u, v: a.v, uPlane: b.uPlane, vPlane: a.vPlane), b, SketchVertex(u: a.u, v: b.v, uPlane: a.uPlane, vPlane: b.vPlane)]
    }

    /// The work plane offset for sketches in `frame`: the named plane when it is parallel to the view (Work Plane ▸ Set),
    /// else the view's own plane through the origin.
    public static func workPlaneOffset(_ f: FamilyDefinition, named: String?, frame: ViewFrame) -> FamilyBound {
        guard let n = named, let p = f.referencePlanes.first(where: { $0.name == n }), p.axis == frame.plane.axes.w else { return .expr("0") }
        return .plane(n)
    }

    /// The reference planes Work Plane ▸ Set offers (every named plane), with the sketch plane each sets.
    public static func workPlanes(_ f: FamilyDefinition) -> [(name: String, plane: FamilySketchPlane)] {
        f.referencePlanes.map { ($0.name, FamilySketchPlane.normal($0.axis)) }
    }

    /// Lines drawn by Model Line / Reference Line from a chain of sketch vertices on `frame`'s plane.
    public static func modelLines(_ chain: [SketchVertex], frame: ViewFrame, offset: FamilyBound, reference: Bool) -> [FamilyModelLine] {
        guard chain.count >= 2 else { return [] }
        return (1..<chain.count).compactMap { i in
            guard !chain[i - 1].point.isAlmostEqual(chain[i].point) else { return nil }
            return FamilyModelLine(plane: frame.plane, offset: offset, start: chain[i - 1].familyPoint, end: chain[i].familyPoint, isReference: reference)
        }
    }

    // MARK: Maps and deletes of the F1415 content

    /// Applies `b` to every bound of the model lines, controls and model text (used by renames and plane deletes).
    static func mapF1415(_ f: inout FamilyDefinition, bound b: (FamilyBound) -> FamilyBound) {
        func p(_ x: FamilyPoint) -> FamilyPoint { FamilyPoint(b(x.x), b(x.y)) }
        for i in f.modelLines.indices {
            f.modelLines[i].offset = b(f.modelLines[i].offset); f.modelLines[i].start = p(f.modelLines[i].start); f.modelLines[i].end = p(f.modelLines[i].end)
        }
        for i in f.controls.indices { f.controls[i].position = p(f.controls[i].position) }
        for i in f.modelTexts.indices { f.modelTexts[i].position = p(f.modelTexts[i].position); f.modelTexts[i].offset = b(f.modelTexts[i].offset) }
    }

    static func deleteF1415(_ item: Item, from f: inout FamilyDefinition) -> Bool {
        switch item {
        case .modelLine(let id): let n = f.modelLines.count; f.modelLines.removeAll { $0.id == id }; return f.modelLines.count < n
        case .control(let id): let n = f.controls.count; f.controls.removeAll { $0.id == id }; return f.controls.count < n
        case .modelText(let id): let n = f.modelTexts.count; f.modelTexts.removeAll { $0.id == id }; return f.modelTexts.count < n
        case .fill(let id): let n = f.fills.count; f.fills.removeAll { $0.id == id }; return f.fills.count < n
        default: return false
        }
    }

    /// Purge Unused (Manage): drops loaded families that no nested instance or sweep profile uses. Returns their names.
    @discardableResult
    public static func purgeUnusedNested(_ f: inout FamilyDefinition) -> [String] {
        var used = Set(f.nestedInstances.map(\.familyName))
        for s in f.solids { if case .sweep(let sw) = s.profile, let pf = sw.profileFamily { used.insert(pf) } }
        let gone = f.nestedFamilies.map(\.name).filter { !used.contains($0) }
        f.nestedFamilies.removeAll { !used.contains($0.name) }
        return gone
    }
}
