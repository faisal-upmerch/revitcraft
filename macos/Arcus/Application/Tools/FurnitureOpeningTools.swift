import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// FM5: the Openings tools, each as its Revit-style counterpart. Bay (BY) places like Room: hover a region bounded by
// parts in a Front/Back elevation (or a box in plan, for top-access bays) and click, with Tag on Placement. Bay
// Separator draws like Room Separator. Bay Divide lays out rows or columns like a curtain grid. Door (DF), Drawer (DW)
// and Flap (FP) place like Door: hover a bay, Space flips the hinge side, Tag on Placement; Drawer's Number stacks that
// many drawers (EQ). Hardware (HW) places a hardware type like Component. Pick New Host moves a front to another bay.

/// Picking bays in a view: Front/Back elevations see bays from the front (x, z), plans from above (x, y).
@MainActor
enum FurnitureOpeningPick {
    static func face(_ map: FurnitureSketchMap?) -> BayFace? {
        switch map?.plane {
        case .xz?: .front
        case .xy?: .top
        default: nil
        }
    }

    /// A view point in the face's coordinates.
    static func point(_ p: Vec2, _ map: FurnitureSketchMap) -> Vec2 { map.toSketch(p) }

    /// The innermost bay at a face point: the smallest undivided bay whose opening holds it.
    static func bay(at p: Vec2, face: BayFace, _ m: BIMModel, undividedOnly: Bool = true) -> Element? {
        m.elements(.furnitureBays).filter { b in
            guard let d = b.furnitureBay, d.face == face, let o = d.opening else { return false }
            if undividedOnly, d.division != nil { return false }
            return FurnitureBays.outline(o, face).contains(p)
        }.min { a, b in
            let ra = FurnitureBays.outline(a.furnitureBay!.opening!, face), rb = FurnitureBays.outline(b.furnitureBay!.opening!, face)
            return ra.width * ra.height < rb.width * rb.height
        }
    }

    /// A face rectangle as view corners.
    static func corners(_ r: Rect2, _ map: FurnitureSketchMap) -> [Vec2] { Rect2(points: [map.toView(r.min), map.toView(r.max)]).corners }

    /// Where a tag goes on a bay or front: centred, a third of the way up (clear of drawer handles).
    static func tagHead(_ r: Rect2, _ map: FurnitureSketchMap) -> Vec2 { map.toView(Vec2(r.center.x, r.min.y + r.height * 0.32)) }

    static func highlightFill() -> GFill { GFill(pattern: .solid, color: RGBColor(0.25, 0.5, 0.8), transparency: 0.82) }
}

// MARK: - Bay

@MainActor
public final class FurnitureBayTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .furnitureBay
    public var title: String { "Bay" }
    public var tagOnPlacement = true
    let map: FurnitureSketchMap?

    public override init(ctx: ToolContext) { map = FurnitureSketchMap.of(ctx.viewData); super.init(ctx: ctx) }

    var face: BayFace? { FurnitureOpeningPick.face(map) }
    public var prompt: String {
        switch face {
        case .front?: "Click inside a region bounded by parts or bay separators to place a bay."
        case .top?: "Click inside a box (sides, front and back) to place a top-access bay."
        default: "Bays are placed in the Front or Back elevation, or in plan for top-access bays."
        }
    }
    public var options: [ToolOption] { [ToolOption(id: "tag", label: "Tag on Placement", kind: .bool, value: .bool(tagOnPlacement))] }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "tag" { tagOnPlacement = value.boolValue ?? true } }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let map, let face else { return }
        let p = FurnitureOpeningPick.point(i.point, map)
        guard let o = FurnitureBays.opening(face: face, at: p, ctx.model) else { preview.cursor = .crosshair; return }
        let pts = FurnitureOpeningPick.corners(FurnitureBays.outline(o, face), map)
        preview.primitives = [.fill([Polygon2(pts)], FurnitureOpeningPick.highlightFill()), .polyline(pts, closed: true, ctx.previewHeavy)]
        preview.highlight = Set(o.parts)
        preview.cursor = .crosshairPlus
    }

    public func pointerDown(_ i: ToolInput) {
        guard let map, let face else { message(prompt); return }
        let p = FurnitureOpeningPick.point(i.point, map)
        let tagType = tagOnPlacement ? TagTool.defaultTagType(for: .furnitureBays, ctx.model) : nil
        let view = ctx.viewID
        var created: ElementID?
        ctx.session.perform("Place Bay") { tx in
            let id = try FurnitureBays.createBay(face: face, at: p, in: tx)
            if let tt = tagType, let o = tx.model[id]?.furnitureBay?.opening {
                tx.create(.tags, data: .tag(TagData(taggedID: id, head: FurnitureOpeningPick.tagHead(FurnitureBays.outline(o, face), map))), typeID: tt, ownerViewID: view)
            }
            created = id
        }
        if let e = ctx.session.lastError { message(e.message) } else if let created { message("\(ctx.model[created]?.name ?? "Bay") placed.") }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Bay Separator

@MainActor
public final class FurnitureBaySeparatorTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .furnitureBaySeparator
    public var title: String { "Bay Separator" }
    public var chain = true
    let map: FurnitureSketchMap?
    var start: Vec2?
    var current: Vec2?

    public override init(ctx: ToolContext) { map = FurnitureSketchMap.of(ctx.viewData); super.init(ctx: ctx) }

    var face: BayFace? { FurnitureOpeningPick.face(map) }
    public var prompt: String {
        guard face != nil else { return "Draw bay separators in the Front or Back elevation, or in plan." }
        return start == nil ? "Click to start the separator." : "Click to end it (square to the piece), or type a length."
    }
    public var numericLabel: String? { start != nil ? "Length" : nil }
    public var snapFrom: Vec2? { start }
    public var options: [ToolOption] { [ToolOption(id: "chain", label: "Chain", kind: .bool, value: .bool(chain))] }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "chain" { chain = value.boolValue ?? true } }

    /// The end square to the piece from the start.
    func squared(_ s: Vec2, _ p: Vec2) -> Vec2 { abs(p.x - s.x) >= abs(p.y - s.y) ? Vec2(p.x, s.y) : Vec2(s.x, p.y) }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        guard let s = start else { return }
        let e = squared(s, i.point)
        preview.primitives = [ctx.line(s, e, heavy: true)]
        preview.tempDims = [tempDim(s, e)]
    }

    public func pointerDown(_ i: ToolInput) {
        guard face != nil else { message(prompt); return }
        if let s = start { if create(s, squared(s, i.point)) { start = chain ? squared(s, i.point) : nil } } else { start = i.point }
    }

    @discardableResult
    func create(_ a: Vec2, _ b: Vec2) -> Bool {
        guard let map, let face else { return false }
        ctx.session.perform("Create Bay Separator") { tx in try FurnitureBays.createSeparator(face: face, from: map.toSketch(a), to: map.toSketch(b), in: tx) }
        if let e = ctx.session.lastError { message(e.message); return false }
        return true
    }

    public func numericInput(_ text: String) -> Bool {
        guard let s = start, let c = current, let v = ctx.parse(text), v > Tolerance.shortCurve else { return false }
        let e0 = squared(s, c)
        let d = (e0 - s).lengthSquared > 0 ? (e0 - s).normalized : .unitX
        let e = s + d * v
        if create(s, e) { start = chain ? e : nil }
        return true
    }

    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Bay Divide

@MainActor
public final class FurnitureBayDivideTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .furnitureBayDivide
    public var title: String { "Bay Divide" }
    public var division = BayDivision(direction: .rows, count: 3)
    let map: FurnitureSketchMap?

    public init(ctx: ToolContext, bay: ElementID? = nil) {
        map = FurnitureSketchMap.of(ctx.viewData)
        super.init(ctx: ctx)
        if let d = ctx.model[bay]?.furnitureBay?.division { division = d }
    }

    var face: BayFace? { FurnitureOpeningPick.face(map) }
    public var prompt: String { face == nil ? "Divide bays in the Front or Back elevation, or in plan." : "Click a bay to divide it into \(division.count) \(division.direction.rawValue.lowercased())." }
    public var options: [ToolOption] {
        var o = [ToolOption(id: "direction", label: "Divide Into", kind: .choice(BayDivision.Direction.allCases.map(\.rawValue)), value: .text(division.direction.rawValue)),
                 ToolOption(id: "layout", label: "Layout", kind: .choice(BayDivision.Layout.allCases.map(\.rawValue)), value: .text(division.layout.rawValue)),
                 ToolOption(id: "count", label: "Number", kind: .integer, value: .int(division.count))]
        if division.layout == .fixed {
            o.append(ToolOption(id: "size", label: "First Cell", kind: .length, value: .double(division.sizes.first ?? 6 * 0.0254)))
        }
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "direction": if let d = BayDivision.Direction(rawValue: value.textValue ?? "") { division.direction = d }
        case "layout":
            if let l = BayDivision.Layout(rawValue: value.textValue ?? "") { division.layout = l; if l == .fixed, division.sizes.isEmpty { division.sizes = [6 * 0.0254] } }
        case "count": if let n = value.intValue, (1...24).contains(n) { division.count = n } else { message("Use 1 to 24 cells.") }
        case "size": if let d = value.doubleValue, d > 0.01 { division.sizes = [d] }
        default: break
        }
    }

    func target(_ p: Vec2) -> Element? {
        guard let map, let face else { return nil }
        return FurnitureOpeningPick.bay(at: FurnitureOpeningPick.point(p, map), face: face, ctx.model)
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let map, let face, let b = target(i.point), let d = b.furnitureBay, let o = d.opening else { return }
        preview.primitives = [.polyline(FurnitureOpeningPick.corners(FurnitureBays.outline(o, face), map), closed: true, ctx.previewHeavy)]
        for (k, c) in FurnitureBays.cells(o, face, division, number: d.number).enumerated() where k > 0 {
            let r = FurnitureBays.outline(c, face)
            let (a, e) = division.direction == .rows ? (Vec2(r.min.x, r.min.y), Vec2(r.max.x, r.min.y)) : (Vec2(r.min.x, r.min.y), Vec2(r.min.x, r.max.y))
            preview.primitives.append(ctx.line(map.toView(a), map.toView(e), heavy: true))
        }
        preview.highlight = [b.id]
        preview.cursor = .pick
    }

    public func pointerDown(_ i: ToolInput) {
        guard let b = target(i.point) else { message(face == nil ? prompt : "Click inside an enclosed bay."); return }
        let d = division
        ctx.session.perform("Bay Divide") { tx in try FurnitureBays.divide(b.id, d, in: tx) }
        if let e = ctx.session.lastError { message(e.message) } else { ctx.session.selection.select([b.id]) }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Door, Drawer, Flap

@MainActor
public final class FurnitureFrontTool: BaseTool, InteractiveTool {
    public let kind: FrontKind
    public var commandID: CommandID { switch kind { case .door: .furnitureDoor; case .drawer: .furnitureDrawer; case .flap: .furnitureFlap } }
    public var title: String { kind.rawValue }
    public var tagOnPlacement = false
    public var hingeRight = false
    public var count = 1
    let map: FurnitureSketchMap?
    var current: Vec2?

    public init(ctx: ToolContext, kind: FrontKind) { self.kind = kind; map = FurnitureSketchMap.of(ctx.viewData); super.init(ctx: ctx) }

    var face: BayFace? { FurnitureOpeningPick.face(map) }
    var typeID: ElementID? {
        if let t = ctx.currentTypes[.furnitureFronts], ctx.model[t]?.typeData?.familyName == kind.rawValue { return t }
        return FurnitureFrontTypes.firstType(kind, ctx.model)
    }
    public var prompt: String {
        guard face != nil else { return "Place \(kind.rawValue.lowercased())s in the Front or Back elevation (lids: in plan)." }
        return kind == .door ? "Click a bay to place the door. Space flips the hinge side." : "Click a bay to place the \(kind.rawValue.lowercased())."
    }
    public var options: [ToolOption] {
        var o: [ToolOption] = []
        if kind == .door, !FurnitureFrontTypes.Values(ctx.model[typeID]?.typeData).isPair {
            o.append(ToolOption(id: "hinge", label: "Hinge", kind: .choice(["Left", "Right"]), value: .text(hingeRight ? "Right" : "Left")))
        }
        if kind == .drawer { o.append(ToolOption(id: "count", label: "Number", kind: .integer, value: .int(count))) }
        o.append(ToolOption(id: "tag", label: "Tag on Placement", kind: .bool, value: .bool(tagOnPlacement)))
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "hinge": hingeRight = value.textValue == "Right"
        case "count": if let n = value.intValue, (1...12).contains(n) { count = n } else { message("Stack 1 to 12 drawers.") }
        case "tag": tagOnPlacement = value.boolValue ?? false
        default: break
        }
        if let c = current { pointerMoved(ToolInput(point: c, rawPoint: c)) }
    }

    func bay(at p: Vec2) -> Element? {
        guard let map, let face else { return nil }
        let q = FurnitureOpeningPick.point(p, map)
        // A divided bay takes the drawer stack (or a front per cell) when Number asks for its cells.
        if kind == .drawer, count > 1, let b = FurnitureOpeningPick.bay(at: q, face: face, ctx.model, undividedOnly: false),
           b.furnitureBay?.parentID == nil, FurnitureBays.cellIDs(of: b.id, ctx.model).isEmpty { return b }
        return FurnitureOpeningPick.bay(at: q, face: face, ctx.model)
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        guard let map, let b = bay(at: i.point), let bd = b.furnitureBay, let o = bd.opening else { preview.cursor = face == nil ? .notAllowed : .crosshair; return }
        let tv = FurnitureFrontTypes.Values(ctx.model[typeID]?.typeData)
        let cells: [BayOpening] = kind == .drawer && count > 1 ? FurnitureBays.cells(o, bd.face, BayDivision(direction: .rows, count: count), number: bd.number) : [o]
        let taken = ctx.model.hosted(by: b.id).contains { $0.furnitureFront != nil }
        for c in cells {
            guard let g = FurnitureFronts.geometry(FrontData(kind: kind, hingeFlipped: hingeRight), type: tv, bay: bd, opening: c) else { continue }
            for leaf in g.leaves {
                let pts = FurnitureOpeningPick.corners(leaf.rect, map)
                preview.primitives.append(.polyline(pts, closed: true, ctx.previewHeavy))
                // The swing triangle, pointing at the hinges.
                let r = leaf.rect
                let tri: [Vec2]? = switch leaf.hinge {
                case .left?: [Vec2(r.max.x, r.max.y), Vec2(r.min.x, r.center.y), Vec2(r.max.x, r.min.y)]
                case .right?: [Vec2(r.min.x, r.max.y), Vec2(r.max.x, r.center.y), Vec2(r.min.x, r.min.y)]
                case .top?: [Vec2(r.min.x, r.min.y), Vec2(r.center.x, r.max.y), Vec2(r.max.x, r.min.y)]
                case .bottom?: [Vec2(r.min.x, r.max.y), Vec2(r.center.x, r.min.y), Vec2(r.max.x, r.max.y)]
                default: nil
                }
                if let tri, bd.face == .front { preview.primitives.append(.polyline(tri.map(map.toView), closed: false, ctx.previewStroke)) }
            }
        }
        preview.highlight = [b.id]
        preview.cursor = taken ? .notAllowed : .crosshairPlus
    }

    public func pointerDown(_ i: ToolInput) {
        guard let map, let b = bay(at: i.point) else { message(face == nil ? prompt : "Click inside a bay (place one with Bay first)."); return }
        let kind = kind, type = typeID, flipped = hingeRight, n = count, view = ctx.viewID
        let tagType = tagOnPlacement ? TagTool.defaultTagType(for: .furnitureFronts, ctx.model) : nil
        var ids: [ElementID] = []
        ctx.session.perform("Place \(kind.rawValue)") { tx in
            ids = kind == .drawer && n > 1 ? try FurnitureFronts.createDrawers(in: b.id, count: n, typeID: type, in: tx)
                                           : try FurnitureFronts.createFront(kind, in: b.id, typeID: type, hingeFlipped: flipped, in: tx)
            if let tt = tagType {
                for id in ids {
                    guard let e = tx.model[id], let bay = tx.model[e.hostID]?.furnitureBay, let o = bay.opening else { continue }
                    let head = map.toView(FurnitureBays.center(o, bay.face))
                    tx.create(.tags, data: .tag(TagData(taggedID: id, head: head)), typeID: tt, ownerViewID: view)
                }
            }
        }
        if let e = ctx.session.lastError { message(e.message) } else { ctx.session.selection.select(ids) }
    }

    public func spaceBar() {
        guard kind == .door else { return }
        hingeRight.toggle()
        message(hingeRight ? "Hinged on the right." : "Hinged on the left.")
        if let c = current { pointerMoved(ToolInput(point: c, rawPoint: c)) }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Hardware

@MainActor
public final class FurnitureHardwareTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .furnitureHardware
    public var title: String { "Hardware" }
    public var elevation = 0.0
    public var mirrored = false
    let map: FurnitureSketchMap?
    var current: Vec2?

    public override init(ctx: ToolContext) { map = FurnitureSketchMap.of(ctx.viewData); super.init(ctx: ctx) }

    var typeID: ElementID? {
        if let t = ctx.currentTypes[.furnitureHardware], ctx.model[t]?.typeData?.instanceCategory == .furnitureHardware { return t }
        return FurnitureHardware.types(.handle, ctx.model).first?.id ?? ctx.model.types(for: .furnitureHardware).first?.id
    }
    public var prompt: String {
        guard let map, map.plane != .yz else { return "Place hardware in a plan or the Front/Back elevation." }
        return "Click to place the hardware. Space mirrors it."
    }
    public var options: [ToolOption] {
        map?.plane == .xy ? [ToolOption(id: "elevation", label: "Elevation", kind: .length, value: .double(elevation))] : []
    }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "elevation" { elevation = value.doubleValue ?? 0 } }

    /// The world point a click puts the hardware at: in plan at the Elevation; in a Front/Back elevation on the
    /// carcass's front face.
    func world(_ p: Vec2) -> Vec3? {
        guard let map else { return nil }
        if map.plane == .xy { return Vec3(p.x, p.y, elevation) }
        guard map.plane == .xz else { return nil }
        let s = map.toSketch(p)
        let front = ctx.model.elements(.furnitureFronts).compactMap { FurnitureFronts.geometry($0, ctx.model) }.filter { g in
            g.face == .front && g.leaves.contains { $0.rect.contains(s) }
        }.first?.outerFace
        let carcass = FurniturePlanes.positionsByName(ctx.model)["Front"] ?? 0
        return Vec3(s.x, front ?? carcass, s.y)
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        guard let w = world(i.point), let t = typeID else { preview.cursor = .notAllowed; return }
        let probe = Element(id: ElementID(UInt64.max - 1), category: .furnitureHardware, data: .component(ComponentData(location: w.xy, offset: w.z, mirrored: mirrored)),
                            typeID: t, levelID: ctx.model.levels.first?.id)
        let mesh = ElementMeshes.parts(probe, ctx.model, detail: .fine).reduce(into: Mesh()) { $0.append($1.mesh) }
        guard !mesh.isEmpty, let map else { return }
        // `project` gives view coordinates (plans: x, y; elevations: u, z).
        let r = Rect2(points: mesh.bounds.corners.map(map.project))
        preview.primitives = [.polyline(r.corners, closed: true, ctx.previewHeavy)]
        preview.cursor = .crosshairPlus
    }

    public func pointerDown(_ i: ToolInput) {
        guard let w = world(i.point), let t = typeID else { message(prompt); return }
        let m = mirrored
        var id: ElementID?
        ctx.session.perform("Place Hardware") { tx in
            let levelZ = tx.model.elevation(ofLevel: tx.model.levels.first?.id)
            id = tx.create(.furnitureHardware, data: .component(ComponentData(location: w.xy, offset: w.z - levelZ, mirrored: m)), typeID: t, levelID: tx.model.levels.first?.id)
        }
        if let e = ctx.session.lastError { message(e.message) } else if let id { ctx.session.selection.select([id]) }
    }

    public func spaceBar() {
        mirrored.toggle()
        if let c = current { pointerMoved(ToolInput(point: c, rawPoint: c)) }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Pick New Host and Bay Tag

@MainActor
public final class FurniturePickBayTool: BaseTool, InteractiveTool {
    public enum Purpose { case newHost([ElementID]), tag }
    public let purpose: Purpose
    public var commandID: CommandID { if case .tag = purpose { return .furnitureBayTag }; return .furniturePickNewHost }
    public var title: String { if case .tag = purpose { return "Bay Tag" }; return "Pick New Host" }
    let map: FurnitureSketchMap?

    public init(ctx: ToolContext, purpose: Purpose) { self.purpose = purpose; map = FurnitureSketchMap.of(ctx.viewData); super.init(ctx: ctx) }

    var face: BayFace? { FurnitureOpeningPick.face(map) }
    public var prompt: String {
        if case .tag = purpose { return "Click a bay to tag it." }
        return "Click the bay to move the front to."
    }

    func bay(_ p: Vec2) -> Element? {
        guard let map, let face else { return nil }
        if case .tag = purpose { return FurnitureOpeningPick.bay(at: FurnitureOpeningPick.point(p, map), face: face, ctx.model, undividedOnly: false) }
        return FurnitureOpeningPick.bay(at: FurnitureOpeningPick.point(p, map), face: face, ctx.model)
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let map, let b = bay(i.point), let d = b.furnitureBay, let o = d.opening else { return }
        let pts = FurnitureOpeningPick.corners(FurnitureBays.outline(o, d.face), map)
        preview.primitives = [.fill([Polygon2(pts)], FurnitureOpeningPick.highlightFill()), .polyline(pts, closed: true, ctx.previewHeavy)]
        preview.cursor = .pick
    }

    public func pointerDown(_ i: ToolInput) {
        guard let map, let b = bay(i.point), let d = b.furnitureBay, let o = d.opening else { message("Click inside a bay."); return }
        switch purpose {
        case .tag:
            guard let tt = TagTool.defaultTagType(for: .furnitureBays, ctx.model) else { message("Load a Bay Tag first."); return }
            let view = ctx.viewID, head = FurnitureOpeningPick.tagHead(FurnitureBays.outline(o, d.face), map)
            ctx.session.perform("Tag Bay") { tx in tx.create(.tags, data: .tag(TagData(taggedID: b.id, head: head)), typeID: tt, ownerViewID: view) }
        case .newHost(let ids):
            ctx.session.perform("Pick New Host") { tx in try FurnitureFronts.rehost(ids, to: b.id, in: tx) }
        }
        if let e = ctx.session.lastError { message(e.message) }
    }
    public func escape() -> EscapeResult { .exitTool }
}
