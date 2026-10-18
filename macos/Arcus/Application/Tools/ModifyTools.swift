import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

/// Move / Copy with base point → target point; typed distance along the current direction.
@MainActor
public final class MoveCopyTool: BaseTool, InteractiveTool {
    public let isCopy: Bool
    public var commandID: CommandID { isCopy ? .copy : .move }
    public var title: String { isCopy ? "Copy" : "Move" }
    let ids: [ElementID]
    var base: Vec2?
    var current: Vec2?
    public var multiple = false
    public var constrain = false
    /// Move only: the moved elements come apart from elements that stay (walls don't drag their neighbours; moved
    /// doors and windows take the wall at their new location as host).
    public var disjoin = false

    public init(ctx: ToolContext, ids: [ElementID], copy: Bool) {
        self.ids = ids
        self.isCopy = copy
        super.init(ctx: ctx)
    }
    public var prompt: String { ids.isEmpty ? "Select elements first, then choose \(title)." : (base == nil ? "Click the start (base) point." : "Click the end point or type a distance.") }
    public var numericLabel: String? { base != nil ? "Distance" : nil }
    public var snapFrom: Vec2? { base }
    public var options: [ToolOption] {
        var o = [ToolOption(id: "constrain", label: "Constrain", kind: .bool, value: .bool(constrain))]
        if isCopy { o.append(ToolOption(id: "multiple", label: "Multiple", kind: .bool, value: .bool(multiple))) }
        else { o.append(ToolOption(id: "disjoin", label: "Disjoin", kind: .bool, value: .bool(disjoin))) }
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "constrain" { constrain = value.boolValue ?? false }
        if id == "multiple" { multiple = value.boolValue ?? false }
        if id == "disjoin" { disjoin = value.boolValue ?? false }
    }

    func target(_ p: Vec2) -> Vec2 {
        guard constrain, let b = base else { return p }
        let v = p - b
        return abs(v.x) > abs(v.y) ? Vec2(p.x, b.y) : Vec2(b.x, p.y)
    }

    public func pointerMoved(_ i: ToolInput) {
        current = target(i.point)
        preview = ToolPreview()
        preview.cursor = isCopy ? .copy : .move
        preview.highlight = Set(ids)
        guard let b = base, let c = current else { return }
        let t = Transform2.translation(c - b)
        preview.primitives = ghost(ids, t)
        // I3: as in RevitCraft: a dashed box around what moves, a thin blue rubber band, its length and angle.
        preview.movedBox = movedBounds(preview.primitives)
        preview.rubberBand = Segment2(b, c)
        preview.tempDims = [tempDim(b, c), angleDim(b, c)]
    }

    /// Bounds of the ghost outlines (view units).
    func movedBounds(_ prims: [GPrimitive]) -> Rect2? {
        var pts: [Vec2] = []
        for p in prims { if case .polyline(let q, _, _) = p { pts += q } }
        return pts.isEmpty ? nil : Rect2(points: pts)
    }

    /// Outline ghosts of the moved elements.
    func ghost(_ ids: [ElementID], _ t: Transform2) -> [GPrimitive] {
        var out: [GPrimitive] = []
        for id in ids.prefix(200) {
            guard let e = ctx.model[id] else { continue }
            switch e.data {
            case .wall:
                if let fp = WallGeometry.footprint(e, ctx.model) { out.append(.polyline(fp.transformed(t).points, closed: true, ctx.previewStroke)) }
            default:
                if let c = ElementOperations.curveOf(e) {
                    let pts = c.tessellate(chordTolerance: 0.01).map(t.apply)
                    out.append(.polyline(pts, closed: false, ctx.previewStroke))
                } else {
                    let b = ElementMeshes.bounds(e, ctx.model).xy
                    if !b.isEmpty { out.append(.polyline(b.corners.map(t.apply), closed: true, ctx.previewStroke)) }
                }
            }
        }
        return out
    }

    public func pointerDown(_ i: ToolInput) {
        guard !ids.isEmpty else { return }
        guard let b = base else {
            base = i.point
            // Moving: the moved elements must not snap to their own original geometry.
            if !isCopy { ctx.snapExclusions = ElementOperations.dependentsToCarry(Set(ids), ctx.model, viewID: ctx.viewID) }
            return
        }
        ctx.snapExclusions = []
        apply(target(i.point) - b)
        if isCopy && multiple { base = target(i.point) } else { ctx.toolFinished?() }
    }

    func apply(_ v: Vec2) {
        guard v.lengthSquared > Tolerance.lengthSquared else { return }
        let t = Transform2.translation(v)
        let view = ctx.viewID
        if isCopy {
            var newIDs: [ElementID] = []
            ctx.session.perform("Copy") { tx in
                let map = ElementOperations.copy(ids, by: t, in: tx, viewID: view)
                newIDs = ids.compactMap { map[$0] }
            }
            if !newIDs.isEmpty { ctx.session.selection.select(newIDs) }
        } else {
            let dj = disjoin
            ctx.session.perform("Move") { tx in try ElementOperations.transform(ids, by: t, in: tx, viewID: view, disjoin: dj) }
        }
        if let e = ctx.session.lastError { message(e.message) }
    }

    public func numericInput(_ text: String) -> Bool {
        guard let b = base, let c = current, let d = ctx.parse(text) else { return false }
        let dir = (c - b).lengthSquared > 0 ? (c - b).normalized : .unitX
        apply(dir * d)
        if isCopy && multiple { base = b + dir * d } else { ctx.toolFinished?() }
        return true
    }
    public func escape() -> EscapeResult {
        if base != nil { base = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

@MainActor
public final class RotateTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.rotate
    public let title = "Rotate"
    let ids: [ElementID]
    var center: Vec2
    var startRay: Vec2?
    var placingCenter = false
    public var copy = false
    public var disjoin = false

    public init(ctx: ToolContext, ids: [ElementID]) {
        self.ids = ids
        center = ElementOperations.center(of: ids, ctx.model)
        super.init(ctx: ctx)
    }
    public var prompt: String {
        if placingCenter { return "Click the new center of rotation." }
        return startRay == nil ? "Click to set the start ray (or hold Option and click to move the center)." : "Click the end ray or type an angle in degrees."
    }
    public var numericLabel: String? { "Angle" }
    public var snapFrom: Vec2? { center }
    public var options: [ToolOption] {
        [ToolOption(id: "disjoin", label: "Disjoin", kind: .bool, value: .bool(disjoin)), ToolOption(id: "copy", label: "Copy", kind: .bool, value: .bool(copy))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "copy" { copy = value.boolValue ?? false }
        if id == "disjoin" { disjoin = value.boolValue ?? false }
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        preview.cursor = .rotate
        let r = ctx.paper(0.004)
        preview.primitives = [.arc(Arc2(center: center, radius: r, startAngle: 0, sweep: Angle.twoPi), ctx.previewHeavy)]
        if let s = startRay {
            preview.primitives.append(ctx.line(center, s))
            preview.primitives.append(ctx.line(center, i.point))
            let a = Angle.normalizeSigned((i.point - center).angle - (s - center).angle)
            preview.tempDims = [TemporaryDimension(from: s, to: i.point, text: String(format: "%.2f°", Angle.degrees(a)), isAngle: true, isActive: true)]
            preview.primitives += MoveCopyTool(ctx: ctx, ids: ids, copy: false).ghost(ids, .rotation(a, around: center))
        }
    }
    public func pointerDown(_ i: ToolInput) {
        if placingCenter || (i.option && startRay == nil) { center = i.point; placingCenter = false; return }
        guard let s = startRay else { startRay = i.point; return }
        apply(Angle.normalizeSigned((i.point - center).angle - (s - center).angle))
    }
    func apply(_ a: Double) {
        let t = Transform2.rotation(a, around: center)
        let view = ctx.viewID
        let dj = disjoin
        ctx.session.perform(copy ? "Rotate Copy" : "Rotate") { tx in
            if copy { ElementOperations.copy(ids, by: t, in: tx, viewID: view) } else { try ElementOperations.transform(ids, by: t, in: tx, viewID: view, disjoin: dj) }
        }
        if let e = ctx.session.lastError { message(e.message) }
        ctx.toolFinished?()
    }
    public func numericInput(_ text: String) -> Bool {
        guard let deg = Double(text.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)) else { return false }
        apply(Angle.radians(deg))
        return true
    }
    public func escape() -> EscapeResult {
        if startRay != nil { startRay = nil; return .stayInTool }
        return .exitTool
    }
}

@MainActor
public final class MirrorTool: BaseTool, InteractiveTool {
    public let pickAxis: Bool
    public var commandID: CommandID { pickAxis ? .mirrorPickAxis : .mirrorDrawAxis }
    public var title: String { pickAxis ? "Mirror - Pick Axis" : "Mirror - Draw Axis" }
    let ids: [ElementID]
    var start: Vec2?
    public var copy = true

    public init(ctx: ToolContext, ids: [ElementID], pickAxis: Bool) { self.ids = ids; self.pickAxis = pickAxis; super.init(ctx: ctx) }
    public var prompt: String { pickAxis ? "Click a line or wall to use as the mirror axis." : (start == nil ? "Click the start of the mirror axis." : "Click the end of the mirror axis.") }
    public var snapFrom: Vec2? { start }
    public var options: [ToolOption] { [ToolOption(id: "copy", label: "Copy", kind: .bool, value: .bool(copy))] }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "copy" { copy = value.boolValue ?? true } }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if pickAxis, let (seg, _) = ctx.snapIndex.nearestSegment(i.point, radius: ctx.pixel * 8) {
            preview.primitives = [ctx.line(seg.start, seg.end, heavy: true)] + MoveCopyTool(ctx: ctx, ids: ids, copy: false).ghost(ids, .mirror(through: seg.start, direction: seg.direction))
            preview.cursor = .pick
        } else if let s = start, s.distance(to: i.point) > 1e-6 {
            preview.primitives = [ctx.line(s, i.point, heavy: true)] + MoveCopyTool(ctx: ctx, ids: ids, copy: false).ghost(ids, .mirror(through: s, direction: (i.point - s).normalized))
        }
    }
    public func pointerDown(_ i: ToolInput) {
        if pickAxis {
            guard let (seg, _) = ctx.snapIndex.nearestSegment(i.point, radius: ctx.pixel * 8) else { message("Click a line to mirror about."); return }
            apply(.mirror(through: seg.start, direction: seg.direction))
        } else if let s = start {
            guard s.distance(to: i.point) > Tolerance.shortCurve else { return }
            apply(.mirror(through: s, direction: (i.point - s).normalized))
        } else { start = i.point }
    }
    func apply(_ t: Transform2) {
        let view = ctx.viewID
        ctx.session.perform(copy ? "Mirror Copy" : "Mirror") { tx in
            if copy { ElementOperations.copy(ids, by: t, in: tx, viewID: view) } else { try ElementOperations.transform(ids, by: t, in: tx, viewID: view) }
        }
        if let e = ctx.session.lastError { message(e.message) }
        ctx.toolFinished?()
    }
    public func escape() -> EscapeResult { if start != nil { start = nil; return .stayInTool }; return .exitTool }
}

/// Array: linear (base point → second or last member) or radial (about a center, start ray → end ray or a typed
/// angle). With Group and Associate the members form an array group whose number can be changed afterwards.
@MainActor
public final class ArrayTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.array
    public let title = "Array"
    let ids: [ElementID]
    public var radial = false
    public var count = 3
    public var moveToLast = false
    public var associate = true
    public var constrain = false
    /// Radial arrays: the center of rotation (the selection's center until moved with Option-click).
    public var center: Vec2
    /// Linear: the start point of the spacing. Radial: a point on the start ray.
    var base: Vec2?
    var current: Vec2?

    public init(ctx: ToolContext, ids: [ElementID]) {
        self.ids = ids
        center = ElementOperations.center(of: ids, ctx.model)
        super.init(ctx: ctx)
    }
    public var prompt: String {
        if ids.isEmpty { return "Select elements first, then choose Array." }
        if radial {
            return base == nil ? "Click to set the start ray, or type the angle. Option-click moves the center of rotation." : "Click the end ray or type an angle in degrees."
        }
        return base == nil ? "Click the start point of the array spacing." : "Click the \(moveToLast ? "last" : "second") member position or type a spacing."
    }
    public var numericLabel: String? { radial ? "Angle" : (base != nil ? "Spacing" : nil) }
    public var snapFrom: Vec2? { radial ? center : base }
    public var options: [ToolOption] {
        var o = [ToolOption(id: "arrayMode", label: "Array", kind: .choice(ArraySpec.Kind.allCases.map(\.rawValue)), value: .text(radial ? ArraySpec.Kind.radial.rawValue : ArraySpec.Kind.linear.rawValue)),
                 ToolOption(id: "associate", label: "Group and Associate", kind: .bool, value: .bool(associate)),
                 ToolOption(id: "count", label: "Number", kind: .integer, value: .int(count)),
                 ToolOption(id: "last", label: "Move To Last", kind: .bool, value: .bool(moveToLast))]
        if !radial { o.append(ToolOption(id: "constrain", label: "Constrain", kind: .bool, value: .bool(constrain))) }
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "arrayMode":
            let r = value.textValue == ArraySpec.Kind.radial.rawValue
            if r != radial { radial = r; base = nil; preview = ToolPreview() }
        case "count": if let n = value.intValue, n >= 2, n <= ArraySpec.maximumCount { count = n }
        case "last": moveToLast = value.boolValue ?? false
        case "associate": associate = value.boolValue ?? true
        case "constrain": constrain = value.boolValue ?? false
        default: break
        }
    }

    func target(_ p: Vec2) -> Vec2 {
        guard constrain, !radial, let b = base else { return p }
        let v = p - b
        return abs(v.x) > abs(v.y) ? Vec2(p.x, b.y) : Vec2(b.x, p.y)
    }
    /// Linear: spacing between members for a picked point.
    func step(to p: Vec2, from b: Vec2) -> Vec2 { moveToLast ? (p - b) / Double(max(count - 1, 1)) : (p - b) }
    /// Radial: angle between members for a swept angle. A full turn with Move To Last spaces the members evenly
    /// around the circle (the last one does not land on the first).
    func stepAngle(forSweep a: Double) -> Double {
        guard moveToLast else { return a }
        if abs(abs(a) - Angle.twoPi) < 1e-9 { return a / Double(count) }
        return a / Double(max(count - 1, 1))
    }

    public func pointerMoved(_ i: ToolInput) {
        current = target(i.point)
        preview = ToolPreview()
        let mover = MoveCopyTool(ctx: ctx, ids: ids, copy: false)
        if radial {
            preview.cursor = .rotate
            preview.primitives = [.arc(Arc2(center: center, radius: ctx.paper(0.004), startAngle: 0, sweep: Angle.twoPi), ctx.previewHeavy)]
            guard let s = base else { return }
            let a = Angle.normalizeSigned((i.point - center).angle - (s - center).angle)
            preview.primitives.append(ctx.line(center, s))
            preview.primitives.append(ctx.line(center, i.point))
            preview.tempDims = [TemporaryDimension(from: s, to: i.point, text: String(format: "%.2f°", Angle.degrees(a)), isAngle: true, isActive: true)]
            let st = stepAngle(forSweep: a)
            for k in 1..<count { preview.primitives += mover.ghost(ids, .rotation(st * Double(k), around: center)) }
        } else {
            guard let b = base, let c = current else { return }
            let st = step(to: c, from: b)
            for k in 1..<count { preview.primitives += mover.ghost(ids, .translation(st * Double(k))) }
            preview.tempDims = [tempDim(b, b + st)]
        }
    }
    public func pointerDown(_ i: ToolInput) {
        guard !ids.isEmpty else { return }
        if radial {
            if i.option && base == nil { center = i.point; return }
            guard let s = base else { base = i.point; return }
            let a = Angle.normalizeSigned((i.point - center).angle - (s - center).angle)
            commit(.radial(count: count, center: center, stepAngle: stepAngle(forSweep: a), sourceMembers: ids, fixedExtent: moveToLast))
        } else {
            guard let b = base else { base = i.point; return }
            commit(.linear(count: count, step: step(to: target(i.point), from: b), sourceMembers: ids, fixedExtent: moveToLast))
        }
    }
    func commit(_ spec: ArraySpec) {
        if spec.kind == .linear { guard spec.step.lengthSquared > Tolerance.lengthSquared else { return } }
        else {
            // Members would coincide when the step is a whole number of turns.
            let r = spec.stepAngle.truncatingRemainder(dividingBy: Angle.twoPi)
            guard abs(r) > 1e-9, abs(abs(r) - Angle.twoPi) > 1e-9 else { message("Enter an angle that separates the members."); return }
        }
        let view = ctx.viewID
        let grouped = ids.contains { ctx.model[$0]?.groupID != nil }
        let assoc = associate && !grouped
        var group: ElementID?
        ctx.session.perform("Array") { tx in group = try ArrayOperations.create(spec, associate: assoc, in: tx, viewID: view) }
        if let e = ctx.session.lastError { message(e.message) }
        else if associate && grouped { message("The selection already belongs to a group, so the array was made without Group and Associate.") }
        else if group != nil { message("Array group created. Select a member and choose Array Number to change the number of members.") }
        ctx.toolFinished?()
    }
    public func numericInput(_ text: String) -> Bool {
        guard !ids.isEmpty else { return false }
        if radial {
            guard let deg = Double(text.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)), deg != 0 else { return false }
            commit(.radial(count: count, center: center, stepAngle: stepAngle(forSweep: Angle.radians(deg)), sourceMembers: ids, fixedExtent: moveToLast))
            return true
        }
        guard let b = base, let c = current, let d = ctx.parse(text), d > 0 else { return false }
        let dir = (c - b).lengthSquared > 0 ? (c - b).normalized : .unitX
        // A typed value is the distance to the member the pick would set (second, or last with Move To Last).
        commit(.linear(count: count, step: moveToLast ? dir * d / Double(max(count - 1, 1)) : dir * d, sourceMembers: ids, fixedExtent: moveToLast))
        return true
    }
    public func escape() -> EscapeResult {
        if base != nil { base = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

/// Scale: resize lines, walls, regions and links about an origin. Graphical: pick the origin, a reference point
/// and the new position of that point. Numerical: type a factor and pick the origin.
@MainActor
public final class ScaleTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.scale
    public let title = "Scale"
    let ids: [ElementID]
    public var numerical = false
    public var factor = 2.0
    var origin: Vec2?
    var reference: Vec2?

    public init(ctx: ToolContext, ids: [ElementID]) {
        self.ids = ids.filter { ctx.model[$0].map(ElementOperations.isScalable) ?? false }
        super.init(ctx: ctx)
    }
    public var prompt: String {
        if ids.isEmpty { return "Select walls, lines, reference planes, regions or links first, then choose Scale." }
        if numerical { return "Type a scale factor (now \(Self.format(factor))), then click the origin." }
        if origin == nil { return "Click the origin (the point that stays fixed)." }
        return reference == nil ? "Click a reference point." : "Click the new position of the reference point."
    }
    public var options: [ToolOption] {
        var o = [ToolOption(id: "scaleMethod", label: "Method", kind: .choice(["Graphical", "Numerical"]), value: .text(numerical ? "Numerical" : "Graphical"))]
        if numerical { o.append(ToolOption(id: "scaleFactor", label: "Scale", kind: .choice(Self.factorChoices(factor)), value: .text(Self.format(factor)))) } // BL-CANVAS: ARCUS-054
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "scaleMethod" { numerical = value.textValue == "Numerical"; origin = nil; reference = nil; preview = ToolPreview() }
        if id == "scaleFactor" { if let f = value.doubleValue ?? value.textValue.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }), f.isFinite, f > 1e-6 { factor = f } else { message("The scale factor must be a number greater than zero.") } } // BL-CANVAS
    }
    /// Common factors offered in the Options Bar (the current one first when it is not among them).
    static func factorChoices(_ current: Double) -> [String] {
        let common = ["0.25", "0.5", "2", "3", "4", "10"]
        return common.contains(format(current)) ? common : [format(current)] + common
    }
    public var numericLabel: String? { numerical ? "Scale" : nil }
    public var snapFrom: Vec2? { origin }
    static func format(_ f: Double) -> String { String(format: "%g", f) }

    func currentFactor(_ p: Vec2) -> Double? {
        guard let o = origin, let r = reference else { return nil }
        let d = r.distance(to: o)
        return d > Tolerance.length ? p.distance(to: o) / d : nil
    }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        preview.highlight = Set(ids)
        let mover = MoveCopyTool(ctx: ctx, ids: ids, copy: false)
        if numerical {
            preview.primitives = mover.ghost(ids, .scale(factor, factor, around: i.point))
            return
        }
        guard let o = origin else { return }
        preview.primitives.append(ctx.line(o, i.point))
        if let r = reference, let f = currentFactor(i.point) {
            preview.primitives.append(ctx.line(o, r, heavy: true))
            preview.primitives += mover.ghost(ids, .scale(f, f, around: o))
            preview.tempDims = [TemporaryDimension(from: o, to: i.point, text: "× " + Self.format((f * 1000).rounded() / 1000), isAngle: false, isActive: false)]
        }
    }
    public func pointerDown(_ i: ToolInput) {
        guard !ids.isEmpty else { return }
        if numerical { apply(factor, about: i.point); return }
        guard let o = origin else { origin = i.point; return }
        guard reference != nil else {
            guard i.point.distance(to: o) > Tolerance.shortCurve else { message("Pick a reference point away from the origin."); return }
            reference = i.point; return
        }
        guard let f = currentFactor(i.point), f > 1e-6 else { message("Pick a point away from the origin."); return }
        apply(f, about: o)
    }
    func apply(_ f: Double, about o: Vec2) {
        let view = ctx.viewID
        ctx.session.perform("Scale") { tx in try ElementOperations.scale(ids, by: f, about: o, in: tx, viewID: view) }
        if let e = ctx.session.lastError { message(e.message) }
        ctx.toolFinished?()
    }
    public func numericInput(_ text: String) -> Bool {
        guard numerical, let f = Double(text.trimmingCharacters(in: .whitespaces)), f.isFinite, f > 1e-6 else { return false }
        factor = f
        return true
    }
    public func escape() -> EscapeResult {
        if reference != nil { reference = nil; return .stayInTool }
        if origin != nil { origin = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

/// Align: pick a reference line, then an element edge to align to it. Option to lock (creates an alignment constraint).
/// I3: as in RevitCraft, Multiple Alignment keeps the reference for further picks (otherwise each alignment starts
/// over), and Prefer chooses which line of a wall a pick takes: centerline, faces, core centre or core faces.
@MainActor
public final class AlignTool: BaseTool, InteractiveTool {
    public enum Prefer: String, CaseIterable, Sendable {
        case centers = "Wall centerlines", faces = "Wall faces", coreCenter = "Center of core", coreFaces = "Faces of core"
    }
    public let commandID = CommandID.align
    public let title = "Align"
    var reference: (Segment2, ElementID?)?
    public var lock = false
    public var multiple = false
    public var prefer = Prefer.centers
    public var prompt: String { reference == nil ? "Click the reference line to align to." : "Click the line or edge to move into alignment." }
    public var options: [ToolOption] {
        [ToolOption(id: "multiple", label: "Multiple Alignment", kind: .bool, value: .bool(multiple)),
         ToolOption(id: "prefer", label: "Prefer", kind: .choice(Prefer.allCases.map(\.rawValue)), value: .text(prefer.rawValue)),
         ToolOption(id: "lock", label: "Lock", kind: .bool, value: .bool(lock))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "lock" { lock = value.boolValue ?? false }
        if id == "multiple" { multiple = value.boolValue ?? false }
        if id == "prefer", let p = value.textValue.flatMap(Prefer.init(rawValue:)) { prefer = p }
    }
    /// The line a pick takes: on a straight wall, the preferred one of its lines (the nearer face for faces).
    func pick(_ p: Vec2) -> (Segment2, ElementID?)? {
        guard let (seg, id) = ctx.snapIndex.nearestSegment(p, radius: ctx.pixel * 8) else { return nil }
        guard let id, let e = ctx.model[id], e.wall != nil, let f = WallGeometry.frame(e, ctx.model), f.isStraight else { return (seg, id) }
        let a = f.assembly
        let offsets: [Double]
        switch prefer {
        case .centers: offsets = [f.centerOffset]
        case .faces: offsets = [f.exteriorOffset, f.interiorOffset]
        case .coreCenter: offsets = [f.offset(fromExterior: a.exteriorToCore + a.coreThickness / 2)]
        case .coreFaces: offsets = [f.offset(fromExterior: a.exteriorToCore), f.offset(fromExterior: a.exteriorToCore + a.coreThickness)]
        }
        let lines = offsets.compactMap { f.location.offset(by: $0).asSegment }
        return lines.min { $0.distance(to: p) < $1.distance(to: p) }.map { ($0, id) } ?? (seg, id)
    }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let r = reference { preview.primitives.append(ctx.line(r.0.start, r.0.end, heavy: true)) }
        if let (s, _) = pick(i.point) { preview.primitives.append(ctx.line(s.start, s.end)); preview.cursor = .pick }
    }
    public func pointerDown(_ i: ToolInput) {
        guard let (seg, id) = pick(i.point) else { message("Click a line or edge."); return }
        guard let (ref, refID) = reference else { reference = (seg, id); return }
        guard let moveID = id, moveID != refID else { message("Pick an element's edge to move."); return }
        guard ref.isParallel(to: seg) else { message("The lines must be parallel to align them."); return }
        let n = ref.normal
        let d = ref.signedDistance(to: seg.midpoint)
        let v = n * -d
        let view = ctx.viewID
        let doLock = lock
        ctx.session.perform("Align") { tx in
            try ElementOperations.transform([moveID], by: .translation(v), in: tx, viewID: view)
            if doLock, let refID {
                tx.create(.constraints, data: .constraint(ConstraintData(kind: .alignment, references: [GeometryReference(refID, .location), GeometryReference(moveID, .location)])))
            }
        }
        if let e = ctx.session.lastError { message(e.message) }
        if !multiple { reference = nil }
    }
    public func escape() -> EscapeResult { if reference != nil { reference = nil; return .stayInTool }; return .exitTool }
}

/// Offset: copies (or moves) a wall/line parallel to itself. Numerical: by the typed distance toward the cursor side.
/// I3: Graphical, as in RevitCraft: pick the element, then two points; their distance across it is the offset.
@MainActor
public final class OffsetTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.offset
    public let title = "Offset"
    public var distance = 1.0
    public var copy = true
    public var graphical = false
    var picked: (Element, Curve2)?
    var firstPoint: Vec2?
    public var prompt: String {
        guard graphical else { return "Click a wall or line to offset it \(ctx.format(distance)) toward the cursor side." }
        if picked == nil { return "Click the wall or line to offset." }
        return firstPoint == nil ? "Click the first point of the offset distance." : "Click the second point: its distance across the element is the offset."
    }
    public var numericLabel: String? { graphical ? nil : "Offset" }
    public var snapFrom: Vec2? { firstPoint }
    public var options: [ToolOption] {
        var o = [ToolOption(id: "mode", label: "Offset", kind: .choice(["Graphical", "Numerical"]), value: .text(graphical ? "Graphical" : "Numerical"))]
        if !graphical { o.append(ToolOption(id: "distance", label: "Distance", kind: .length, value: .double(distance))) }
        o.append(ToolOption(id: "copy", label: "Copy", kind: .bool, value: .bool(copy)))
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "distance", let d = value.doubleValue, d > 0 { distance = d }
        if id == "copy" { copy = value.boolValue ?? true }
        if id == "mode" { graphical = value.textValue == "Graphical"; picked = nil; firstPoint = nil; preview = ToolPreview() }
    }
    func target(_ i: ToolInput) -> (Element, Curve2, Double)? {
        for id in [i.hit].compactMap({ $0 }) + i.hitCandidates {
            guard let e = ctx.model[id], let c = ElementOperations.curveOf(e) else { continue }
            let side = c.normal(at: 0.5).dot(i.rawPoint - c.closestPoint(to: i.rawPoint)) >= 0 ? 1.0 : -1.0
            return (e, c, side)
        }
        return nil
    }
    /// Graphical: the signed offset from the first point to `p`, across the picked element.
    func graphicalDistance(_ c: Curve2, _ p: Vec2) -> Double? {
        guard let f = firstPoint else { return nil }
        return c.normal(at: 0.5).dot(p - f)
    }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if graphical, let (e, c) = picked {
            preview.highlight = [e.id]
            guard let f = firstPoint, let d = graphicalDistance(c, i.point), abs(d) > Tolerance.length else { return }
            preview.primitives = [.polyline(c.offset(by: d).tessellate(chordTolerance: 0.01), closed: false, ctx.previewHeavy)]
            preview.tempDims = [tempDim(f, f + c.normal(at: 0.5) * d)]
            return
        }
        guard let (e, c, side) = target(i) else { preview.cursor = .notAllowed; return }
        if graphical { preview.highlight = [e.id]; preview.cursor = .pick; return }
        let o = c.offset(by: distance * side)
        preview.primitives = [.polyline(o.tessellate(chordTolerance: 0.01), closed: false, ctx.previewHeavy)]
        preview.cursor = .pick
    }
    public func pointerDown(_ i: ToolInput) {
        if graphical {
            guard let (e, c) = picked else {
                if let (e, c, _) = target(i) { picked = (e, c) } else { message("Click a wall or line.") }
                return
            }
            guard firstPoint != nil else { firstPoint = i.point; return }
            guard let d = graphicalDistance(c, i.point), abs(d) > Tolerance.length else { return }
            apply(e.id, d)
            picked = nil; firstPoint = nil; preview = ToolPreview()
            return
        }
        guard let (e, _, side) = target(i) else { return }
        apply(e.id, distance * side)
    }
    func apply(_ id: ElementID, _ d: Double) {
        let view = ctx.viewID
        let isCopy = copy
        // Doors and windows in an offset wall go with it (copied onto the new wall, or moved with the wall).
        ctx.session.perform("Offset") { tx in try ElementOperations.offset(id, by: d, copy: isCopy, in: tx, viewID: view) }
        if let err = ctx.session.lastError { message(err.message) }
    }
    public func numericInput(_ text: String) -> Bool {
        guard !graphical, let d = ctx.parse(text), d > 0 else { return false }
        distance = d
        return true
    }
    public func escape() -> EscapeResult {
        if firstPoint != nil { firstPoint = nil; return .stayInTool }
        if picked != nil { picked = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

/// Trim/Extend: corner (two picks), single (boundary then element), multiple (boundary then elements).
@MainActor
public final class TrimExtendTool: BaseTool, InteractiveTool {
    public enum Mode { case corner, single, multiple }
    public let mode: Mode
    public var commandID: CommandID { mode == .corner ? .trimExtendCorner : mode == .single ? .trimExtendSingle : .trimExtendMultiple }
    public var title: String { mode == .corner ? "Trim/Extend to Corner" : mode == .single ? "Trim/Extend Single" : "Trim/Extend Multiple" }
    var first: (ElementID, Vec2)?
    var boundary: Curve2?

    public init(ctx: ToolContext, mode: Mode) { self.mode = mode; super.init(ctx: ctx) }
    public var prompt: String {
        switch mode {
        case .corner: first == nil ? "Click the first wall or line on the side to keep." : "Click the second wall or line on the side to keep."
        case .single, .multiple: boundary == nil ? "Click the boundary line." : "Click the element to trim or extend (on the side to keep)."
        }
    }
    func pick(_ i: ToolInput) -> Element? {
        for id in [i.hit].compactMap({ $0 }) + i.hitCandidates { if let e = ctx.model[id], ElementOperations.curveOf(e) != nil { return e } }
        return nil
    }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let e = pick(i) { preview.highlight = [e.id]; preview.cursor = .pick } else { preview.cursor = .notAllowed }
        if let b = boundary { preview.primitives = [.polyline(b.tessellate(chordTolerance: 0.01), closed: false, ctx.previewHeavy)] }
    }
    public func pointerDown(_ i: ToolInput) {
        guard let e = pick(i), let c = ElementOperations.curveOf(e) else { message("Click a wall or line."); return }
        switch mode {
        case .corner:
            guard let (fid, fp) = first else { first = (e.id, i.rawPoint); return }
            guard fid != e.id, let fc = ctx.model[fid].flatMap(ElementOperations.curveOf) else { return }
            ctx.session.perform("Trim/Extend to Corner") { tx in
                try ElementOperations.trimExtend(fid, keepNear: fp, to: c, in: tx)
                try ElementOperations.trimExtend(e.id, keepNear: i.rawPoint, to: fc, in: tx)
            }
            first = nil
        case .single, .multiple:
            guard let b = boundary else { boundary = c; return }
            ctx.session.perform("Trim/Extend") { tx in try ElementOperations.trimExtend(e.id, keepNear: i.rawPoint, to: b, in: tx) }
            if mode == .single { boundary = nil }
        }
        if let err = ctx.session.lastError { message(err.message) }
    }
    public func escape() -> EscapeResult {
        if first != nil || boundary != nil { first = nil; boundary = nil; return .stayInTool }
        return .exitTool
    }
}

/// Split Element: split at a point, remove the segment between two picked points (Delete Inner Segment), or split
/// leaving a gap of a set width (Split with Gap).
@MainActor
public final class SplitTool: BaseTool, InteractiveTool {
    public enum Mode: String, CaseIterable, Sendable {
        case split = "Split"
        case deleteInnerSegment = "Delete Inner Segment"
        case gap = "Split with Gap"
    }
    public let commandID = CommandID.split
    public let title = "Split Element"
    public var mode = Mode.split
    /// Split with Gap: the width of the gap left between the pieces.
    public var gap = 0.025
    /// Delete Inner Segment: the element and point of the first pick.
    var first: (ElementID, Vec2)?

    public var prompt: String {
        switch mode {
        case .split: "Click a wall, line or beam where it should be split."
        case .deleteInnerSegment: first == nil ? "Click the first point of the segment to remove." : "Click the second point on the same element."
        case .gap: "Click a wall, line or beam where the gap should be (gap \(ctx.format(gap)))."
        }
    }
    public var options: [ToolOption] {
        var o = [ToolOption(id: "splitMode", label: "Split", kind: .choice(Mode.allCases.map(\.rawValue)), value: .text(mode.rawValue))]
        if mode == .gap { o.append(ToolOption(id: "gap", label: "Joint Gap", kind: .length, value: .double(gap))) }
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "splitMode", let m = value.textValue.flatMap(Mode.init(rawValue:)) { mode = m; first = nil; preview = ToolPreview() }
        if id == "gap", let g = value.doubleValue, g > Tolerance.shortCurve { gap = g }
    }
    public var numericLabel: String? { mode == .gap ? "Joint Gap" : nil }
    public func numericInput(_ text: String) -> Bool {
        guard mode == .gap, let g = ctx.parse(text), g > Tolerance.shortCurve else { return false }
        gap = g
        return true
    }

    func pick(_ i: ToolInput) -> (Element, Curve2)? {
        for id in [i.hit].compactMap({ $0 }) + i.hitCandidates {
            guard let e = ctx.model[id], e.wall != nil || e.modelLine != nil || e.beam != nil, let c = ElementOperations.curveOf(e) else { continue }
            if let f = first, f.0 != id { continue }
            return (e, c)
        }
        return nil
    }
    /// The two cut points of a gap centred on `p`.
    func gapEnds(_ c: Curve2, at p: Vec2) -> (Vec2, Vec2) {
        let t = c.parameter(of: c.closestPoint(to: p))
        let dt = gap / 2 / max(c.length, Tolerance.length)
        return (c.point(at: max(t - dt, 0)), c.point(at: min(t + dt, 1)))
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let (e, c) = pick(i) else { preview.cursor = .notAllowed; return }
        let p = c.closestPoint(to: i.rawPoint)
        let n = c.normal(at: c.parameter(of: p)) * ctx.paper(0.004)
        preview.cursor = .pick
        switch mode {
        case .split:
            preview.primitives = [ctx.line(p - n, p + n, heavy: true)]
        case .gap:
            let (a, b) = gapEnds(c, at: p)
            preview.primitives = [ctx.line(a - n, a + n, heavy: true), ctx.line(b - n, b + n, heavy: true)]
        case .deleteInnerSegment:
            preview.highlight = [e.id]
            preview.primitives = [ctx.line(p - n, p + n, heavy: true)]
            if let (_, q) = first {
                let t0 = c.parameter(of: c.closestPoint(to: q)), t1 = c.parameter(of: p)
                let piece = c.subcurve(from: min(max(t0, 0), 1), to: min(max(t1, 0), 1))
                preview.primitives.append(.polyline(piece.tessellate(chordTolerance: 0.01), closed: false, ctx.previewHeavy))
                preview.tempDims = [TemporaryDimension(from: piece.start, to: piece.end, text: ctx.format(piece.length), isAngle: false, isActive: false)]
            }
        }
    }
    public func pointerDown(_ i: ToolInput) {
        guard let (e, c) = pick(i) else {
            message(first == nil ? "Click a wall, line or beam." : "Click the same element again.")
            return
        }
        switch mode {
        case .split:
            ctx.session.perform("Split") { tx in try ElementOperations.split(e.id, at: i.rawPoint, in: tx) }
        case .gap:
            let (a, b) = gapEnds(c, at: i.rawPoint)
            ctx.session.perform("Split with Gap") { tx in try ElementOperations.deleteSegment(e.id, between: a, and: b, in: tx) }
        case .deleteInnerSegment:
            guard let (_, q) = first else { first = (e.id, c.closestPoint(to: i.rawPoint)); return }
            first = nil
            ctx.session.perform("Delete Inner Segment") { tx in try ElementOperations.deleteSegment(e.id, between: q, and: i.rawPoint, in: tx) }
        }
        if let err = ctx.session.lastError { message(err.message) }
    }
    public func escape() -> EscapeResult {
        if first != nil { first = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

@MainActor
public final class MatchTypeTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.matchType
    public let title = "Match Type Properties"
    var source: Element?
    public var prompt: String { source == nil ? "Click the source element." : "Click elements to receive the type “\(ctx.model.type(of: source!)?.name ?? "")”. Esc to pick a new source." }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let id = i.hit { preview.highlight = [id]; preview.cursor = .pick }
    }
    public func pointerDown(_ i: ToolInput) {
        guard let id = i.hit, let e = ctx.model[id] else { return }
        guard let s = source else {
            guard e.typeID != nil else { message("That element has no type."); return }
            source = e; return
        }
        guard e.category == s.category || (Set([e.category, s.category]) == Set([.columns, .structuralColumns])) else {
            message("Types can only be matched within a category (\(s.category.displayName))."); return
        }
        let t = s.typeID
        ctx.session.perform("Match Type") { tx in tx.update(e.id) { $0.typeID = t } }
        if let err = ctx.session.lastError { message(err.message) }
    }
    public func escape() -> EscapeResult { if source != nil { source = nil; return .stayInTool }; return .exitTool }
}
