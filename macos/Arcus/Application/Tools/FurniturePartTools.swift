import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// FM4: the other part tools. Back and Divider pick the carcass or bay round a click in a Front/Back elevation; Leg places
// like Column (points, or At Corners of a top, as Column's At Grids); Rail draws like Beam (chained, Z Justification);
// Slats fill a region like a beam system; Plinth picks a bottom; Edge Profile and Groove pick part edges like Wall Sweep
// and Reveal; Attach Top/Base picks the shelf; Opening picks two corners on a panel's face; Cushion takes two corners.

/// The bay round a front-view point, for the Back and Divider tools, in view coordinates.
@MainActor
enum FurnitureBayPick {
    /// The world (x, z) of a Front/Back elevation point.
    static func frontPoint(_ p: Vec2, _ map: FurnitureSketchMap?) -> Vec2? {
        guard let map, map.plane == .xz else { return nil }
        return map.toSketch(p)
    }

    static func rect(_ x: (PartValue, PartValue), _ z: (PartValue, PartValue), _ map: FurnitureSketchMap) -> [Vec2] {
        Rect2(points: [map.toView(Vec2(x.0.value, z.0.value)), map.toView(Vec2(x.1.value, z.1.value))]).corners
    }
}

// MARK: - Back

@MainActor
public final class FurnitureBackTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .furnitureBack
    public var title: String { "Back" }
    public var fit: BackIntent.Fit = .inside
    public var joint: BackIntent.Joint = .butt
    let map: FurnitureSketchMap?

    public override init(ctx: ToolContext) { map = FurnitureSketchMap.of(ctx.viewData); super.init(ctx: ctx) }

    public var prompt: String { map?.plane == .xz ? "Click inside a carcass: the back fits between its sides, bottom and top." : "Open a Front or Back elevation to place a back." }
    public var options: [ToolOption] {
        [ToolOption(id: "fit", label: "Fit", kind: .choice(BackIntent.Fit.allCases.map(\.rawValue)), value: .text(fit.rawValue)),
         ToolOption(id: "joint", label: "Joint", kind: .choice(BackIntent.Joint.allCases.map(\.rawValue)), value: .text(joint.rawValue))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "fit", let f = BackIntent.Fit(rawValue: value.textValue ?? "") { fit = f }
        if id == "joint", let j = BackIntent.Joint(rawValue: value.textValue ?? "") { joint = j }
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let map, let p = FurnitureBayPick.frontPoint(i.point, map), let bay = FurniturePartOperations.bay(atFront: p, carcass: true, ctx.model) else { return }
        let (x, z) = fit == .inside ? (bay.x, bay.z) : (bay.outer.x, bay.outer.z)
        preview.primitives = [.polyline(FurnitureBayPick.rect(x, z, map), closed: true, ctx.previewHeavy)]
        preview.highlight = Set([bay.left, bay.right, bay.bottom, bay.top].compactMap { $0 })
        preview.cursor = .pick
    }

    public func pointerDown(_ i: ToolInput) {
        guard let p = FurnitureBayPick.frontPoint(i.point, map) else { message(prompt); return }
        let fit = fit, joint = joint, type = ctx.currentTypes[.furniturePanels]
        var created: ElementID?
        ctx.session.perform("Create Back") { tx in
            let id = try FurniturePartOperations.createBack(atFront: p, fit: fit, typeID: type.flatMap { tx.model[$0]?.name.contains("Back") == true ? $0 : nil }, in: tx)
            tx.update(id) { $0.furniturePanel?.back?.joint = joint }
            created = id
        }
        if let e = ctx.session.lastError { message(e.message) } else if let created { ctx.session.selection.select([created]) }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Divider

@MainActor
public final class FurnitureDividerTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .furnitureDivider
    public var title: String { "Divider" }
    public var vertical = true
    public var count = 1
    public var setback = 0.0
    let map: FurnitureSketchMap?

    public override init(ctx: ToolContext) { map = FurnitureSketchMap.of(ctx.viewData); super.init(ctx: ctx) }

    public var prompt: String { map?.plane == .xz ? "Click inside a bay: dividers split it into equal spaces (EQ)." : "Open a Front or Back elevation to place dividers." }
    public var options: [ToolOption] {
        [ToolOption(id: "orientation", label: "Orientation", kind: .choice(["Vertical", "Horizontal"]), value: .text(vertical ? "Vertical" : "Horizontal")),
         ToolOption(id: "count", label: "Number", kind: .integer, value: .int(count)),
         ToolOption(id: "setback", label: "Front Setback", kind: .length, value: .double(setback))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "orientation": vertical = value.textValue != "Horizontal"
        case "count": if let n = value.intValue, (1...20).contains(n) { count = n } else { message("Use 1 to 20 dividers.") }
        case "setback": setback = max(0, value.doubleValue ?? 0)
        default: break
        }
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let map, let p = FurnitureBayPick.frontPoint(i.point, map), let bay = FurniturePartOperations.bay(atFront: p, ctx.model) else { return }
        preview.primitives = [.polyline(FurnitureBayPick.rect(bay.x, bay.z, map), closed: true, ctx.previewStroke)]
        for k in 1...count {
            let f = Double(k) / Double(count + 1)
            if vertical {
                let x = bay.x.0.value + (bay.x.1.value - bay.x.0.value) * f
                preview.primitives.append(ctx.line(map.toView(Vec2(x, bay.z.0.value)), map.toView(Vec2(x, bay.z.1.value)), heavy: true))
            } else {
                let z = bay.z.0.value + (bay.z.1.value - bay.z.0.value) * f
                preview.primitives.append(ctx.line(map.toView(Vec2(bay.x.0.value, z)), map.toView(Vec2(bay.x.1.value, z)), heavy: true))
            }
        }
        preview.cursor = .pick
    }

    public func pointerDown(_ i: ToolInput) {
        guard let p = FurnitureBayPick.frontPoint(i.point, map) else { message(prompt); return }
        let v = vertical, n = count, sb = setback, type = FurnitureToolOptions.type(.furniturePanels, family: "Panel", ctx)
        var ids: [ElementID] = []
        ctx.session.perform(n == 1 ? "Create Divider" : "Create Dividers") { tx in ids = try FurniturePartOperations.createDividers(atFront: p, vertical: v, count: n, setback: sb, typeID: type, in: tx) }
        if let e = ctx.session.lastError { message(e.message) } else { ctx.session.selection.select(ids) }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Leg

@MainActor
public final class FurnitureLegTool: BaseTool, InteractiveTool {
    public enum Mode: String, CaseIterable { case point = "At Point", corners = "At Corners" }
    public let commandID: CommandID
    public var title: String { "Leg" }
    public var mode: Mode
    public var extent = PartExtent(basePlane: "Bottom", topPlane: "Top")
    public var rotation = 0.0
    public var inset = 1 * 0.0254
    var current: Vec2?

    public init(ctx: ToolContext, atCorners: Bool = false) {
        mode = atCorners ? .corners : .point
        commandID = atCorners ? .furnitureLegsAtCorners : .furnitureLeg
        super.init(ctx: ctx)
    }

    public var prompt: String {
        guard ctx.isPlan else { return "Place legs in a plan." }
        return mode == .point ? "Click to place a leg. Space rotates it." : "Click a top or shelf: a leg goes in each corner, up to its underside."
    }
    public var options: [ToolOption] {
        var o = [ToolOption(id: "mode", label: "Place", kind: .choice(Mode.allCases.map(\.rawValue)), value: .text(mode.rawValue))]
        if mode == .point {
            o += FurnitureToolOptions.extentOptions(extent, axis: .z, ctx.model)
            o.append(ToolOption(id: "rotation", label: "Rotation", kind: .angle, value: .double(rotation)))
        } else {
            o.append(ToolOption(id: "basePlane", label: "Base", kind: .choice(FurnitureToolOptions.planeNames(.z, ctx.model)), value: .text(extent.basePlane ?? "Bottom")))
            o.append(ToolOption(id: "inset", label: "Inset", kind: .length, value: .double(inset)))
        }
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if FurnitureToolOptions.setExtent(&extent, id, value) { return }
        switch id {
        case "mode": if let m = Mode(rawValue: value.textValue ?? "") { mode = m }
        case "rotation": rotation = value.doubleValue ?? 0
        case "inset": inset = max(0, value.doubleValue ?? 0)
        default: break
        }
    }

    var typeID: ElementID? { FurnitureToolOptions.type(.furnitureLegs, ctx) }

    func top(at p: Vec2) -> Element? {
        guard let map = FurnitureSketchMap.of(ctx.viewData) else { return nil }
        return FurnitureToolOptions.parts(at: p, [.furnitureShelves], map: map, tolerance: ctx.pixel * 4, ctx.model)
            .max { (FurniturePartSolids.partBox($0, ctx.model)?.box.max.z ?? 0) < (FurniturePartSolids.partBox($1, ctx.model)?.box.max.z ?? 0) }
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        let tv = FurniturePartTypes.Values(ctx.model[typeID]?.typeData)
        switch mode {
        case .point:
            let t = Transform2.translation(i.point) * Transform2.rotation(rotation)
            let r = Rect2(center: .zero, halfSize: Vec2(tv.width / 2, tv.depth / 2))
            preview.primitives = [.polyline(r.corners.map(t.apply), closed: true, ctx.previewHeavy)]
        case .corners:
            if let s = top(at: i.point), let b = FurniturePartSolids.partBox(s, ctx.model)?.box {
                preview.highlight = [s.id]
                preview.cursor = .pick
                for (sx, x) in [(1.0, b.min.x), (-1.0, b.max.x)] {
                    for (sy, y) in [(1.0, b.min.y), (-1.0, b.max.y)] {
                        let c = Vec2(x + sx * (tv.width / 2 + inset), y + sy * (tv.depth / 2 + inset))
                        preview.primitives.append(.polyline(Rect2(center: c, halfSize: Vec2(tv.width / 2, tv.depth / 2)).corners, closed: true, ctx.previewHeavy))
                    }
                }
            }
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message(prompt); return }
        let type = typeID
        switch mode {
        case .point:
            let ext = extent, rot = rotation, p = i.point
            ctx.session.perform("Create Leg") { tx in try FurniturePartOperations.createLeg(at: p, extent: ext, rotation: rot, typeID: type, in: tx) }
        case .corners:
            guard let s = top(at: i.point) else { message("Click a top or shelf."); return }
            let base = extent.basePlane, inset = inset
            var ids: [ElementID] = []
            ctx.session.perform("Create Legs") { tx in ids = try FurniturePartOperations.legsAtCorners(of: s.id, inset: inset, basePlane: base, typeID: type, in: tx) }
            if ctx.session.lastError == nil { ctx.session.selection.select(ids) }
        }
        if let e = ctx.session.lastError { message(e.message) }
    }

    public func spaceBar() {
        rotation = Angle.normalize(rotation + .pi / 2)
        if let c = current { var i = ToolInput(point: c, rawPoint: c); i.hit = nil; pointerMoved(i) }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Rail

@MainActor
public final class FurnitureRailTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .furnitureRail
    public var title: String { "Rail" }
    public var chain = true
    public var justification: RailJustification = .top
    public var plane: String?
    public var offset = 0.0
    let map: FurnitureSketchMap?
    var start: Vec2?
    var current: Vec2?

    public override init(ctx: ToolContext) {
        map = FurnitureSketchMap.of(ctx.viewData)
        plane = map?.plane == .xy || map == nil ? "Top" : map?.defaultExtent.base
        super.init(ctx: ctx)
        if map?.plane != .xy { offset = FurniturePartTypes.Values(ctx.model[typeID]?.typeData).width / 2 }
    }

    public var prompt: String {
        guard map != nil else { return "Draw rails in a plan, or in an elevation square to the piece." }
        return start == nil ? "Click the rail's start point." : "Click its end point, or type a length. Esc ends the chain."
    }
    public var numericLabel: String? { start != nil ? "Length" : nil }
    public var snapFrom: Vec2? { start }
    var axis: FamilyAxis { (map?.plane ?? .xy).axes.w }
    var typeID: ElementID? { FurnitureToolOptions.type(.furnitureRails, ctx) }

    public var options: [ToolOption] {
        [ToolOption(id: "plane", label: map?.plane == .xy ? "Height from" : "Depth from", kind: .choice(["None"] + FurnitureToolOptions.planeNames(axis, ctx.model)), value: .text(plane ?? "None")),
         ToolOption(id: "offset", label: "Offset", kind: .length, value: .double(offset)),
         ToolOption(id: "just", label: "Z Justification", kind: .choice(RailJustification.allCases.map(\.rawValue)), value: .text(justification.rawValue)),
         ToolOption(id: "chain", label: "Chain", kind: .bool, value: .bool(chain))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "plane": plane = value.textValue == "None" ? nil : value.textValue
        case "offset": offset = value.doubleValue ?? 0
        case "just": if let j = RailJustification(rawValue: value.textValue ?? "") { justification = j }
        case "chain": chain = value.boolValue ?? true
        default: break
        }
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        guard let s = start else { return }
        preview.primitives = [ctx.line(s, i.point, heavy: true)]
        preview.tempDims = [tempDim(s, i.point), angleDim(s, i.point)]
    }

    public func pointerDown(_ i: ToolInput) {
        guard map != nil else { message(prompt); return }
        if let s = start { if create(s, i.point) { start = chain ? i.point : nil } } else { start = i.point }
    }

    @discardableResult
    func create(_ a: Vec2, _ b: Vec2) -> Bool {
        guard let map else { return false }
        let p = plane, o = offset, j = justification, type = typeID
        ctx.session.perform("Create Rail") { tx in
            try FurniturePartOperations.createRail(start: map.toSketch(a), end: map.toSketch(b), plane: map.plane, w: o, wPlane: p, justification: j, typeID: type, in: tx)
        }
        if let e = ctx.session.lastError { message(e.message); return false }
        return true
    }

    public func numericInput(_ text: String) -> Bool {
        guard let s = start, let c = current, let v = ctx.parse(text), v > Tolerance.shortCurve else { return false }
        let e = s + ((c - s).lengthSquared > 0 ? (c - s).normalized : .unitX) * v
        if create(s, e) { start = chain ? e : nil }
        return true
    }
    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Slats

@MainActor
public final class FurnitureSlatsTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .furnitureSlats
    public var title: String { "Slats" }
    public var alongX = true
    public var rule: SlatLayout.Rule = .fixedDistance
    public var spacing = 4 * 0.0254
    public var number = 8
    public var plane: String? = "Top"
    public var offset = 0.0
    var start: Vec2?

    public var prompt: String {
        guard ctx.isPlan else { return "Lay out slats in a plan." }
        return start == nil ? "Click the first corner of the region to fill." : "Click the opposite corner."
    }
    public var options: [ToolOption] {
        var o = [ToolOption(id: "direction", label: "Slats Run", kind: .choice(["Along X", "Along Y"]), value: .text(alongX ? "Along X" : "Along Y")),
                 ToolOption(id: "rule", label: "Layout Rule", kind: .choice(SlatLayout.Rule.allCases.map(\.rawValue)), value: .text(rule.rawValue))]
        o.append(rule == .fixedDistance ? ToolOption(id: "spacing", label: "Spacing", kind: .length, value: .double(spacing))
                                        : ToolOption(id: "number", label: "Number", kind: .integer, value: .int(number)))
        o.append(ToolOption(id: "plane", label: "Height from", kind: .choice(["None"] + FurnitureToolOptions.planeNames(.z, ctx.model)), value: .text(plane ?? "None")))
        o.append(ToolOption(id: "offset", label: "Offset", kind: .length, value: .double(offset)))
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "direction": alongX = value.textValue != "Along Y"
        case "rule": if let r = SlatLayout.Rule(rawValue: value.textValue ?? "") { rule = r }
        case "spacing": if let d = value.doubleValue, d > 0.005 { spacing = d }
        case "number": if let n = value.intValue, (1...200).contains(n) { number = n }
        case "plane": plane = value.textValue == "None" ? nil : value.textValue
        case "offset": offset = value.doubleValue ?? 0
        default: break
        }
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let s = start else { return }
        let r = Rect2(points: [s, i.point])
        preview.primitives = [.polyline(r.corners, closed: true, ctx.previewStroke)]
        let w = FurniturePartTypes.Values(ctx.model[FurnitureToolOptions.type(.furnitureRails, ctx)]?.typeData).width
        let extent = (alongX ? r.height : r.width) - w
        guard extent >= 0 else { return }
        for off in SlatLayout(rule: rule, spacing: spacing, number: number, extent: extent).offsets {
            if alongX { let y = r.min.y + w / 2 + off; preview.primitives.append(ctx.line(Vec2(r.min.x, y), Vec2(r.max.x, y), heavy: true)) }
            else { let x = r.min.x + w / 2 + off; preview.primitives.append(ctx.line(Vec2(x, r.min.y), Vec2(x, r.max.y), heavy: true)) }
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message(prompt); return }
        guard let s = start else { start = i.point; return }
        let r = Rect2(points: [s, i.point])
        let ax = alongX, ru = rule, sp = spacing, n = number, p = plane, o = offset
        let type = ctx.currentTypes[.furnitureRails]
        var created: ElementID?
        ctx.session.perform("Create Slats") { tx in created = try FurniturePartOperations.createSlats(in: r, alongX: ax, rule: ru, spacing: sp, number: n, z: o, zPlane: p, typeID: type, in: tx) }
        if let e = ctx.session.lastError { message(e.message) } else if let created { ctx.session.selection.select([created]) }
        start = nil
        preview = ToolPreview()
    }
    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Plinth

@MainActor
public final class FurniturePlinthTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .furniturePlinth
    public var title: String { "Plinth" }
    public var setback = 3 * 0.0254
    /// nil: up to the bottom's underside.
    public var height: Double?

    public var prompt: String { "Click a bottom (or shelf) to run a plinth under its front." }
    public var options: [ToolOption] {
        var o = [ToolOption(id: "setback", label: "Setback", kind: .length, value: .double(setback)),
                 ToolOption(id: "top", label: "Height", kind: .choice(["To Bottom", "Unconnected"]), value: .text(height == nil ? "To Bottom" : "Unconnected"))]
        if let h = height { o.append(ToolOption(id: "height", label: "", kind: .length, value: .double(h))) }
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "setback": setback = max(0, value.doubleValue ?? 0)
        case "top": height = value.textValue == "Unconnected" ? (height ?? 4 * 0.0254) : nil
        case "height": if let d = value.doubleValue, d > Tolerance.length { height = d }
        default: break
        }
    }

    func bottom(at p: Vec2) -> Element? {
        guard let map = FurnitureSketchMap.of(ctx.viewData) else { return nil }
        return FurnitureToolOptions.parts(at: p, [.furnitureShelves, .furniturePanels], map: map, tolerance: ctx.pixel * 4, ctx.model)
            .filter { e in e.furnitureShelf != nil || (FurniturePartSolids.partBox(e, ctx.model)?.box).map { $0.max.z - $0.min.z < 0.05 } == true }
            .min { (FurniturePartSolids.partBox($0, ctx.model)?.box.min.z ?? 0) < (FurniturePartSolids.partBox($1, ctx.model)?.box.min.z ?? 0) }
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let b = bottom(at: i.point) { preview.highlight = [b.id]; preview.cursor = .pick }
    }
    public func pointerDown(_ i: ToolInput) {
        guard let b = bottom(at: i.point) else { message(prompt); return }
        let sb = setback, h = height, type = FurnitureToolOptions.type(.furniturePanels, family: "Panel", ctx)
        var created: ElementID?
        ctx.session.perform("Create Plinth") { tx in created = try FurniturePartOperations.createPlinth(under: b.id, setback: sb, height: h, typeID: type, in: tx) }
        if let e = ctx.session.lastError { message(e.message) } else if let created { ctx.session.selection.select([created]) }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Edge Profile and Groove

@MainActor
public final class FurnitureEdgeProfileTool: BaseTool, InteractiveTool {
    public let commandID: CommandID
    public let groove: Bool
    public var title: String { groove ? "Groove" : "Edge Profile" }
    public var offset = 0.25 * 0.0254
    let map: FurnitureSketchMap?

    public init(ctx: ToolContext, groove: Bool) {
        self.groove = groove
        commandID = groove ? .furnitureGroove : .furnitureEdgeProfile
        map = FurnitureSketchMap.of(ctx.viewData)
        super.init(ctx: ctx)
    }

    public var prompt: String { "Click an edge of a panel, shelf, rail or square leg." }
    public var options: [ToolOption] { groove ? [ToolOption(id: "offset", label: "Offset from Edge", kind: .length, value: .double(offset))] : [] }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "offset" { offset = max(0, value.doubleValue ?? 0) } }

    func depth(_ p: Vec3) -> Double {
        guard let map else { return 0 }
        return map.plane == .xy ? -p.z : (p.xy - map.origin).dot(map.forward)
    }

    func pick(_ p: Vec2) -> (Element, PartEdge)? {
        guard let map else { return nil }
        let tol = ctx.pixel * 6
        for e in FurnitureToolOptions.parts(at: p, [.furniturePanels, .furnitureShelves, .furnitureRails, .furnitureLegs], map: map, tolerance: tol, ctx.model) {
            if let edge = FurniturePartOperations.nearestEdge(of: e, ctx.model, pick: p, tolerance: tol, toView: { (map.project($0), self.depth($0)) }) { return (e, edge) }
        }
        return nil
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let map, let (e, edge) = pick(i.point), let b = FurniturePartSolids.partBox(e, ctx.model)?.box else { return }
        let (a, c) = FurniturePartOperations.segment(b, edge)
        preview.primitives = [.polyline([map.project(a), map.project(c)], closed: false, ctx.previewHeavy)]
        preview.highlight = [e.id]
        preview.cursor = .pick
    }

    public func pointerDown(_ i: ToolInput) {
        guard let (e, edge) = pick(i.point) else { message(prompt); return }
        let g = groove, o = offset
        let type = FurnitureToolOptions.type(.furnitureEdgeProfiles, family: g ? FurniturePartTypes.grooveFamily : "Edge Profile", ctx)
        ctx.session.perform(g ? "Create Groove" : "Create Edge Profile") { tx in
            try FurniturePartOperations.createEdgeProfile(on: e.id, edge: edge, groove: g, offset: g ? o : 0, typeID: type, in: tx)
        }
        if let err = ctx.session.lastError { message(err.message) }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Attach Top/Base

@MainActor
public final class FurnitureAttachTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .furnitureAttach
    public var title: String { "Attach Top/Base" }
    let ids: [ElementID]
    public init(ctx: ToolContext, ids: [ElementID]) { self.ids = ids; super.init(ctx: ctx) }
    public var prompt: String { "Click the shelf or top to attach the \(ids.count) selected part\(ids.count == 1 ? "" : "s") to." }

    func shelf(at p: Vec2) -> Element? {
        guard let map = FurnitureSketchMap.of(ctx.viewData) else { return nil }
        return FurnitureToolOptions.parts(at: p, [.furnitureShelves], map: map, tolerance: ctx.pixel * 4, ctx.model).first
    }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        preview.highlight = Set(ids)
        if let s = shelf(at: i.point) { preview.highlight.insert(s.id); preview.cursor = .pick }
    }
    public func pointerDown(_ i: ToolInput) {
        guard let s = shelf(at: i.point) else { message(prompt); return }
        let ids = ids
        ctx.session.perform("Attach Top/Base") { tx in try FurniturePartOperations.attach(ids, to: s.id, in: tx) }
        if let e = ctx.session.lastError { message(e.message) } else { ctx.toolFinished?() }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Opening

@MainActor
public final class FurniturePanelOpeningTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .furniturePanelOpening
    public var title: String { "Opening" }
    var panelID: ElementID?
    var start: Vec2?

    public init(ctx: ToolContext, panel: ElementID?) { panelID = panel; super.init(ctx: ctx) }
    public var prompt: String {
        if panelID == nil { return "Click the panel to cut, in an elevation that sees its face." }
        return start == nil ? "Click the first corner of the opening." : "Click the opposite corner."
    }

    /// A view point in the panel's face coordinates (s along its line, t up from its base).
    func face(_ p: Vec2) -> Vec2? {
        guard let id = panelID, let pd = ctx.model[id]?.furniturePanel, pd.plane == .xy, let map = FurnitureSketchMap.of(ctx.viewData), map.plane != .xy,
              let f = FurniturePartSolids.linearFrame(pd.plane, pd.start, pd.end), FamilySketchPlane.normal(f.crossAxis) == map.plane else { return nil }
        let s = map.toSketch(p), u0 = f.lineAlongU ? pd.start.x : pd.start.y
        return Vec2((s.x - u0) * f.along, s.y - pd.base)
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let s = start { preview.primitives = [.polyline(Rect2(points: [s, i.point]).corners, closed: true, ctx.previewHeavy)] }
    }
    public func pointerDown(_ i: ToolInput) {
        if panelID == nil {
            if let map = FurnitureSketchMap.of(ctx.viewData), let e = FurnitureToolOptions.parts(at: i.point, [.furniturePanels], map: map, tolerance: ctx.pixel * 4, ctx.model).first {
                panelID = e.id
            } else { message(prompt) }
            return
        }
        guard face(i.point) != nil else { message("Open an elevation that sees the panel's face."); return }
        guard let s = start else { start = i.point; return }
        guard let a = face(s), let b = face(i.point), let id = panelID else { return }
        ctx.session.perform("Create Opening") { tx in try FurniturePartOperations.addOpening(id, PanelOpening(s0: a.x, s1: b.x, t0: a.y, t1: b.y), in: tx) }
        if let e = ctx.session.lastError { message(e.message) }
        start = nil
        preview = ToolPreview()
    }
    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Cushion

@MainActor
public final class FurnitureCushionTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .furnitureCushion
    public var title: String { "Cushion" }
    public var spec = CushionSpec(center: .zero, width: 0, depth: 0, height: 4 * 0.0254, crown: 0.75 * 0.0254, cornerRadius: 1.5 * 0.0254)
    public var plane: String? = "Bottom"
    public var offset = 16 * 0.0254
    var start: Vec2?

    public var prompt: String {
        guard ctx.isPlan else { return "Place cushions in a plan." }
        return start == nil ? "Click a corner of the cushion." : "Click the opposite corner. Space turns it a quarter turn."
    }
    public var options: [ToolOption] {
        let piping = spec.topPiping && spec.bottomPiping ? "Both" : spec.topPiping ? "Top" : spec.bottomPiping ? "Bottom" : "None"
        return [ToolOption(id: "height", label: "Height", kind: .length, value: .double(spec.height)),
                ToolOption(id: "crown", label: "Crown", kind: .length, value: .double(spec.crown)),
                ToolOption(id: "radius", label: "Corner Radius", kind: .length, value: .double(spec.cornerRadius)),
                ToolOption(id: "piping", label: "Piping", kind: .choice(["Both", "Top", "Bottom", "None"]), value: .text(piping)),
                ToolOption(id: "plane", label: "Base", kind: .choice(FurnitureToolOptions.planeNames(.z, ctx.model)), value: .text(plane ?? "")),
                ToolOption(id: "offset", label: "Offset", kind: .length, value: .double(offset))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "height": if let d = value.doubleValue, d > 0.005 { spec.height = d }
        case "crown": spec.crown = max(0, value.doubleValue ?? 0)
        case "radius": spec.cornerRadius = max(0, value.doubleValue ?? 0)
        case "piping": let p = value.textValue ?? "Both"; spec.topPiping = p == "Both" || p == "Top"; spec.bottomPiping = p == "Both" || p == "Bottom"
        case "plane": plane = value.textValue
        case "offset": offset = value.doubleValue ?? 0
        default: break
        }
    }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let s = start else { return }
        let r = Rect2(points: [s, i.point])
        preview.primitives = [.polyline(FurnitureForms.roundedRect(r.center, r.width, r.height, spec.cornerRadius), closed: true, ctx.previewHeavy)]
        preview.tempDims = [tempDim(Vec2(r.min.x, r.min.y), Vec2(r.max.x, r.min.y)), tempDim(Vec2(r.max.x, r.min.y), Vec2(r.max.x, r.max.y), active: false)]
    }
    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message(prompt); return }
        guard let s = start else { start = i.point; return }
        let r = Rect2(points: [s, i.point])
        guard r.width > 0.02, r.height > 0.02 else { return }
        var c = spec
        c.center = r.center; c.width = r.width; c.depth = r.height
        let z = (plane.flatMap { FurniturePlanes.positionsByName(ctx.model)[$0] } ?? 0) + offset
        var f = FurnitureFormData(kind: .cushion, profile: [], w0: z, w1: z + c.height)
        f.cushion = c
        var created: ElementID?
        ctx.session.perform("Create Cushion") { tx in created = try FurniturePartOperations.createForm(f, in: tx) }
        if let e = ctx.session.lastError { message(e.message) } else if let created { ctx.session.selection.select([created]) }
        start = nil
        preview = ToolPreview()
    }
    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}
