import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// MARK: - Doors & windows

@MainActor
public final class InsertTool: BaseTool, InteractiveTool {
    public let category: Category
    public var commandID: CommandID { category == .doors ? .door : .window }
    public var title: String { category.singularName }
    var hostID: ElementID?
    var location: Vec2?
    var facingFlipped = false
    var handFlipped = false
    /// Space pressed an odd number of times: facing is the opposite of the side the pointer is on. // BL-KEYS
    var facingInverted = false
    /// The last pointer input, so Space redraws the preview at once. // BL-KEYS
    var lastInput: ToolInput?
    public var sillHeight: Double
    public var tagOnPlacement = true

    public init(ctx: ToolContext, category: Category) {
        self.category = category
        var sill = 0.0
        if category == .windows, let t = ctx.type(for: .windows), let v = ctx.model[t]?.typeData?.params[Parameters.familyParamID("Default Sill Height")]?.doubleValue { sill = v }
        sillHeight = sill
        super.init(ctx: ctx)
    }

    public var prompt: String {
        guard ctx.isPlan || ctx.isVertical else { return "Open a plan, elevation or section to place \(title.lowercased())s." }
        return hostID == nil ? "Move over a wall to place the \(title.lowercased()). Space flips facing." : "Click to place. Space flips facing; Shift+Space flips hand."
    }
    public var options: [ToolOption] {
        var o = [ToolOption(id: "tag", label: "Tag on Placement", kind: .bool, value: .bool(tagOnPlacement))]
        if category == .windows { o.append(ToolOption(id: "sill", label: "Sill Height", kind: .length, value: .double(sillHeight))) }
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "tag" { tagOnPlacement = value.boolValue ?? true }
        if id == "sill", let d = value.doubleValue { sillHeight = d }
    }

    var probe: Element? {
        guard let t = ctx.type(for: category) else { return nil }
        var e = Element(id: ElementID(UInt64.max), category: category, data: .insert(InsertData(location: location ?? .zero, sillHeight: sillHeight)), typeID: t, hostID: hostID)
        e.insert?.facingFlipped = facingFlipped
        e.insert?.handFlipped = handFlipped
        return e
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        lastInput = i // BL-KEYS
        guard ctx.isPlan else { if ctx.isVertical { verticalPointerMoved(i) }; return } // BL-CANVAS: ARCUS-036
        guard let wall = hit(i, [.walls]) ?? nearestWall(i.rawPoint), let f = WallGeometry.frame(wall, ctx.model) else {
            hostID = nil; preview.cursor = .notAllowed; return
        }
        hostID = wall.id
        let width = probe.flatMap { InsertGeometry.openingSize($0, ctx.model)?.width } ?? 0.9
        guard let p = InsertGeometry.constrainToHost(i.rawPoint, width: width, host: f) else { hostID = nil; preview.cursor = .notAllowed; return }
        location = p
        // Which side of the wall is the cursor on → facing.
        let n = f.location.normal(at: 0.5) * (f.flipped ? -1 : 1)
        let side = (i.rawPoint - p).dot(n)
        facingFlipped = (side < 0) != facingInverted // BL-KEYS: Space flips relative to the pointer side
        // Temporary dimensions along the host to the nearest wall (or the host's end) on each side; typing a value
        // positions the insert from the nearer one and places it.
        // Measured like a placed door: each opening edge to the nearest wall face, opening edge or host end.
        let u = f.location.tangent(at: 0.5)
        func dims(at q: Vec2) -> [SelectionDimension] {
            SelectionDimensions.insertDimensions(id: ElementID(UInt64.max),
                                                 jambs: [(q - u * (width / 2), GeometryReference(nil, .openingLeft)), (q + u * (width / 2), GeometryReference(nil, .openingRight))],
                                                 host: wall, frame: f, model: ctx.model)
        }
        var found = dims(at: p)
        var pulledToMiddle = false
        // Pull to the middle between the two references when the pointer is close to it.
        if found.count == 2 {
            let shift = (found[0].value - found[1].value) / 2
            let dir = found[0].direction // growing found[0] moves away from its reference
            if abs(shift) <= ctx.pixel * 6, let c = InsertGeometry.constrainToHost(p + dir * (-shift), width: width, host: f) {
                location = c
                found = dims(at: c)
                pulledToMiddle = true
            }
        }
        // Otherwise step the insert so the nearer distance is a round value for the zoom.
        if !pulledToMiddle, let d = found.min(by: { $0.value < $1.value }), let loc = location {
            let step = ctx.lengthIncrement
            let rounded = (d.value / step).rounded() * step
            if abs(rounded - d.value) > 1e-9, let c = InsertGeometry.constrainToHost(loc + d.direction * (rounded - d.value), width: width, host: f) {
                location = c
                found = dims(at: c)
            }
        }
        // The opening the insert will cut: the wall is blanked between the jambs and the jambs are drawn.
        if let loc = location {
            let u = f.location.tangent(at: 0.5), nrm = f.location.normal(at: 0.5)
            let lo = f.rightOffset - ctx.pixel, hi = f.leftOffset + ctx.pixel
            let a = loc - u * (width / 2), b = loc + u * (width / 2)
            preview.primitives.append(.fill([Polygon2([a + nrm * lo, b + nrm * lo, b + nrm * hi, a + nrm * hi])], .mask))
            preview.primitives.append(ctx.line(a + nrm * (lo + ctx.pixel), a + nrm * (hi - ctx.pixel)))
            preview.primitives.append(ctx.line(b + nrm * (lo + ctx.pixel), b + nrm * (hi - ctx.pixel)))
        }
        if let e = probe {
            for s in InsertGeometry.planSymbols(e, ctx.model) {
                switch s.curve {
                case .line(let seg): preview.primitives.append(ctx.line(seg.start, seg.end))
                case .arc(let a): preview.primitives.append(.arc(a, ctx.previewStroke))
                }
            }
        }
        spacing = found
        // The preview dimensions stand off the wall face on the cursor's side: measured along that face, and oriented
        // so the canvas's stand-off (to the left of from → to) points away from the wall.
        let nrm = f.location.normal(at: 0.5)
        let outward = (i.rawPoint - p).dot(nrm) >= 0 ? nrm : -nrm
        let face = outward.dot(nrm) > 0 ? f.leftOffset : f.rightOffset
        preview.tempDims = found.map { d in
            let shift = nrm * (face - (d.from - (location ?? p)).dot(nrm))
            var (a, b) = (d.from + shift, d.to + shift)
            if (b - a).perpendicular.dot(outward) < 0 { swap(&a, &b) }
            return TemporaryDimension(from: a, to: b, text: ctx.format(d.value), isAngle: false,
                                      isActive: d == found.min(by: { $0.value < $1.value }))
        }
        preview.highlight = [wall.id]
    }

    /// Current distances to the references on each side (for typed positioning).
    var spacing: [SelectionDimension] = []
    public var numericLabel: String? { spacing.isEmpty ? nil : "Distance" }

    /// Typing a distance places the insert that far from the nearer reference (the highlighted dimension).
    public func numericInput(_ text: String) -> Bool {
        guard let v = ctx.parse(text), v >= 0, let d = spacing.min(by: { $0.value < $1.value }), let loc = location,
              let host = ctx.model[hostID], let f = WallGeometry.frame(host, ctx.model) else { return false }
        let width = probe.flatMap { InsertGeometry.openingSize($0, ctx.model)?.width } ?? 0.9
        guard let q = InsertGeometry.constrainToHost(loc + d.direction * (v - d.value), width: width, host: f) else {
            message("The \(title.lowercased()) doesn't fit there."); return false
        }
        location = q
        pointerDown(ToolInput(point: q, rawPoint: q))
        return true
    }

    func nearestWall(_ p: Vec2) -> Element? {
        let tol = ctx.pixel * 12
        return ctx.model.elements(.walls).filter { $0.levelID == ctx.levelID }.min { a, b in
            (a.wall?.location.distance(to: p) ?? .infinity) < (b.wall?.location.distance(to: p) ?? .infinity)
        }.flatMap { w in (w.wall?.location.distance(to: p) ?? .infinity) <= tol + (WallGeometry.frame(w, ctx.model)?.thickness ?? 0) / 2 ? w : nil }
    }

    public func pointerDown(_ i: ToolInput) {
        guard let host = hostID, let loc = location, let t = ctx.type(for: category), let wall = ctx.model[host] else {
            message("\(title)s must be placed in a wall."); return
        }
        let tagType = tagOnPlacement ? TagTool.defaultTagType(for: category, ctx.model) : nil
        let view = ctx.viewID
        let ff = facingFlipped, hf = handFlipped, sill = sillHeight
        ctx.session.perform("Place \(title)") { tx in
            var d = InsertData(location: loc, sillHeight: sill)
            d.facingFlipped = ff; d.handFlipped = hf
            let id = tx.create(category, data: .insert(d), typeID: t, levelID: wall.levelID, hostID: host)
            if let tt = tagType, ctx.isPlan {
                let head = loc + (wall.wall?.location.normal(at: 0.5) ?? .unitY) * ctx.paper(0.009)
                tx.create(.tags, data: .tag(TagData(taggedID: id, head: head)), typeID: tt, ownerViewID: view)
            }
        }
        if let e = ctx.session.lastError { message(e.message) }
    }

    // BL-KEYS: Space flips facing (and keeps it flipped as the pointer moves); Shift+Space flips hand.
    public func spaceBar() { facingInverted.toggle(); facingFlipped.toggle(); if let i = lastInput { pointerMoved(i) } }
    public func flipHand() { handFlipped.toggle(); if let i = lastInput { pointerMoved(i) } }
    public var isFacingFlipped: Bool { facingFlipped }
    public var isHandFlipped: Bool { handFlipped }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Components, columns, symbols

@MainActor
public final class ComponentTool: BaseTool, InteractiveTool {
    public let category: Category
    public let commandID: CommandID
    public var title: String { category.singularName }
    var location: Vec2?
    public var rotation = 0.0
    public var offset = 0.0
    public var topLevelID: ElementID?
    public var rotateAfterPlacement = false

    public init(ctx: ToolContext, category: Category, commandID: CommandID) {
        self.category = category
        self.commandID = commandID
        super.init(ctx: ctx)
        if category == .columns || category == .structuralColumns { topLevelID = ctx.model.levelAbove(ctx.levelID)?.id }
    }
    var isColumn: Bool { category == .columns || category == .structuralColumns }
    var isViewSpecific: Bool { category == .detailComponents || category == .genericAnnotations }

    public var prompt: String {
        if !isViewSpecific && !ctx.isPlan { return "Open a plan view to place \(title.lowercased())s." }
        return "Click to place the \(title.lowercased()). Space rotates 90°."
    }
    public var options: [ToolOption] {
        var o: [ToolOption] = [ToolOption(id: "rotation", label: "Rotation", kind: .angle, value: .double(rotation))]
        if isColumn {
            o.append(ToolOption(id: "top", label: "Height", kind: .choice(["Unconnected"] + ctx.model.levels.map(\.name)), value: .text(ctx.model[topLevelID]?.name ?? "Unconnected")))
        } else if !isViewSpecific {
            o.append(ToolOption(id: "offset", label: "Elevation", kind: .length, value: .double(offset)))
        }
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "rotation": rotation = value.doubleValue ?? 0
        case "offset": offset = value.doubleValue ?? 0
        case "top": topLevelID = ctx.model.levels.first { $0.name == value.textValue }?.id
        default: break
        }
    }

    func probeElement(at p: Vec2) -> Element? {
        guard let t = ctx.type(for: category) else { return nil }
        let data: ElementData
        switch category {
        case .columns, .structuralColumns: data = .column(ColumnData(location: p, rotation: rotation, topLevelID: topLevelID))
        case .detailComponents, .genericAnnotations: data = .detailComponent(DetailComponentData(location: p, rotation: rotation))
        default: data = .component(ComponentData(location: p, rotation: rotation, offset: offset))
        }
        return Element(id: ElementID(UInt64.max - 1), category: category, data: data, typeID: t, levelID: ctx.levelID)
    }

    public func pointerMoved(_ i: ToolInput) {
        location = i.point
        preview = ToolPreview()
        guard let e = probeElement(at: i.point) else { preview.cursor = .notAllowed; return }
        if isViewSpecific {
            if let item = AnnotationRenderer.previewItem(e, model: ctx.model, scale: ctx.isSheet ? 1 : ctx.scale) { preview.primitives = item }
        } else {
            let outlines = ComponentGeometry.planOutline(e, ctx.model)
            preview.primitives = outlines.map { .polyline($0.points, closed: true, ctx.previewStroke) }
            for s in ComponentGeometry.planSymbols(e, ctx.model) {
                switch s.curve {
                case .line(let seg): preview.primitives.append(ctx.line(seg.start, seg.end))
                case .arc(let a): preview.primitives.append(.arc(a, ctx.previewStroke))
                }
            }
        }
    }

    public func pointerDown(_ i: ToolInput) {
        if !isViewSpecific && !ctx.isPlan { message("Open a plan view to place \(title.lowercased())s."); return }
        guard let e = probeElement(at: i.point), let t = e.typeID else { message("Load a \(title.lowercased()) family first."); return }
        let view = ctx.viewID
        ctx.session.perform("Place \(title)") { tx in
            tx.create(category, data: ctx.sketched(e.data), typeID: t, levelID: isViewSpecific ? nil : ctx.levelID, ownerViewID: isViewSpecific ? view : nil) // S3D2: on the work plane
        }
        if let err = ctx.session.lastError { message(err.message) }
    }
    public func spaceBar() { rotation = Angle.normalize(rotation + .pi / 2); if let l = location { pointerMoved(ToolInput(point: l, rawPoint: l)) } }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Rooms & areas

@MainActor
public final class RoomTool: BaseTool, InteractiveTool {
    public let isArea: Bool
    public var commandID: CommandID { isArea ? .area : .room }
    public var title: String { isArea ? "Area" : "Room" }
    public var tagOnPlacement = true
    var arrangement: PlanarArrangement?
    var arrangementRevision: UInt64 = .max
    var nextNumber: Int

    public init(ctx: ToolContext, isArea: Bool = false) {
        self.isArea = isArea
        nextNumber = RoomPlacement.nextNumber(level: ctx.levelID, ctx.model, areas: isArea)
        super.init(ctx: ctx)
    }
    /// Areas go into the area plan's scheme (else the first scheme).
    var areaScheme: ElementID? {
        guard isArea else { return nil }
        return ctx.viewData?.areaSchemeID ?? AreaPlans.sortedSchemes(ctx.model).first?.id
    }
    public var prompt: String {
        guard ctx.isPlan else { return "\(title)s are placed in plan views." }
        if isArea && ctx.viewData?.kind != .areaPlan { return "Open an area plan to place areas." }
        return "Click inside an enclosed region to place \(title.lowercased()) \(nextNumber)."
    }
    public var options: [ToolOption] { [ToolOption(id: "tag", label: "Tag on Placement", kind: .bool, value: .bool(tagOnPlacement))] }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "tag" { tagOnPlacement = value.boolValue ?? true } }

    func ensureArrangement() {
        guard let level = ctx.levelID, arrangementRevision != ctx.model.revision else { return }
        let z = isArea ? ctx.levelElevation + 1 : ctx.levelElevation + max(0.3, ctx.model[level]?.level?.computationHeight ?? 0)
        arrangement = PlanarArrangement(segments: RoomGeometry.boundingSegments(level: level, atZ: z, ctx.model, areaScheme: areaScheme))
        arrangementRevision = ctx.model.revision
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard ctx.isPlan else { return }
        ensureArrangement()
        if let f = arrangement?.face(containing: i.rawPoint) {
            preview.primitives = [.fill(f.profile.loops, GFill(pattern: .solid, color: RGBColor(0.25, 0.5, 0.8), transparency: 0.8))] + f.profile.loops.map { .polyline($0.points, closed: true, ctx.previewHeavy) }
            preview.cursor = .crosshairPlus
        } else {
            preview.cursor = .crosshair
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan, let level = ctx.levelID else { message("Open a plan view to place \(title.lowercased())s."); return }
        if isArea && ctx.viewData?.kind != .areaPlan { message("Open an area plan to place areas (View ▸ Area Plan)."); return }
        if isArea && areaScheme == nil { message("Create an area plan first; it sets up the area schemes."); return }
        let number = String(nextNumber)
        let cat: Category = isArea ? .areas : .rooms
        let tagType = tagOnPlacement ? TagTool.defaultTagType(for: cat, ctx.model) : nil
        let view = ctx.viewID
        let scheme = areaScheme
        ctx.session.perform("Place \(title)") { tx in
            var rd = RoomData(point: i.rawPoint, number: number)
            rd.areaSchemeID = scheme
            let id = tx.create(cat, name: isArea ? "Area" : "Room", data: .room(rd), levelID: level)
            if let tt = tagType { tx.create(.tags, data: .tag(TagData(taggedID: id, head: i.rawPoint)), typeID: tt, ownerViewID: view) }
        }
        if let e = ctx.session.lastError { message(e.message) } else {
            nextNumber += 1
            let placed = ctx.model.elements(cat).last
            if let r = placed, RoomGeometry.boundary(r, ctx.model).state != .bounded {
                message(isArea ? "Area \(number) is not in a region enclosed by area boundary lines. Add boundary lines, or move it."
                               : "Room \(number) is not in a properly enclosed region. Add walls or room separators, or move it.")
            }
        }
    }

    /// Places a room (or area) in every enclosed region of the level that has none, tagged when Tag on Placement is on.
    /// Returns the number placed.
    @discardableResult
    public func placeAutomatically() -> Int {
        guard ctx.isPlan, let level = ctx.levelID else { message("Open a plan view to place \(title.lowercased())s."); return 0 }
        if isArea && (ctx.viewData?.kind != .areaPlan || areaScheme == nil) { message("Open an area plan to place areas."); return 0 }
        let cat: Category = isArea ? .areas : .rooms
        let tagType = tagOnPlacement ? TagTool.defaultTagType(for: cat, ctx.model) : nil
        let view = ctx.viewID, scheme = areaScheme
        var created: [ElementID] = []
        ctx.session.perform(isArea ? "Place Areas Automatically" : "Place Rooms Automatically") { tx in
            created = RoomPlacement.placeAutomatically(level: level, in: tx, areaScheme: scheme, tagType: tagType, tagView: tagType == nil ? nil : view)
        }
        if let e = ctx.session.lastError { message(e.message); return 0 }
        nextNumber = RoomPlacement.nextNumber(level: level, ctx.model, areas: isArea)
        let noun = isArea ? "area" : "room"
        message(created.isEmpty ? "Every enclosed region on this level already has a \(noun)." : "Placed \(created.count) \(noun)\(created.count == 1 ? "" : "s").")
        return created.count
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Tags

/// Tag by Category (and Room, Area and Multi-Category tags): click an element to tag it with its category's tag. With
/// a leader the tag sits a short way from the element; the preview follows the pointer. W2-ANNOT: works in sections
/// and elevations (tags anchor at the element's station and mid-height) and loads missing area and multi-category tags.
@MainActor
public final class TagTool: BaseTool, InteractiveTool {
    public let commandID: CommandID
    public var title: String {
        switch commandID {
        case .roomTag: "Tag Room"
        case .multiCategoryTag: "Multi-Category Tag"
        case .areaTag: "Tag Area"
        case .spaceTag: "Space Tag" // F5
        default: "Tag by Category"
        }
    }
    public var leader = false
    public var orientation: TagOrientation = .horizontal
    /// Leader length on paper (meters) when tagging with a leader.
    public var leaderLength = 0.012
    let categories: Set<Category>

    public init(ctx: ToolContext, commandID: CommandID = .tagByCategory, categories: Set<Category>? = nil) {
        self.commandID = commandID
        self.categories = categories ?? Set(Category.taggable)
        super.init(ctx: ctx)
    }

    /// The tag type for a category: its own tag family first, the multi-category tag last.
    nonisolated public static func defaultTagType(for c: Category, _ model: BIMModel) -> ElementID? {
        let types = TagAll.tagTypes(for: c, model)
        return (types.first { !AnnotationLibrary.isMultiCategory($0, model) } ?? types.first)?.id
    }

    func tagType(for c: Category) -> ElementID? {
        if commandID == .multiCategoryTag {
            return TagAll.tagTypes(for: c, ctx.model).first { AnnotationLibrary.isMultiCategory($0, ctx.model) }?.id
        }
        return TagTool.defaultTagType(for: c, ctx.model)
    }

    public var prompt: String {
        guard ctx.isPlan || ctx.isVertical || ctx.isDrafting else { return "Tags are placed in plans, sections and elevations." }
        return commandID == .roomTag ? "Click a room to tag it." : commandID == .areaTag ? "Click an area to tag it."
            : commandID == .spaceTag ? "Click to place space tag." : "Click an element to tag it." // F5
    }
    public var options: [ToolOption] {
        [ToolOption(id: "orientation", label: "Orientation", kind: .choice(TagOrientation.allCases.map(\.rawValue)), value: .text(orientation.rawValue)),
         ToolOption(id: "leader", label: "Leader", kind: .bool, value: .bool(leader)),
         ToolOption(id: "length", label: "Length", kind: .length, value: .double(leaderLength * Double(ctx.isSheet ? 1 : ctx.scale)))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "leader" { leader = value.boolValue ?? false }
        if id == "orientation", let o = TagOrientation(rawValue: value.textValue ?? "") { orientation = o }
        if id == "length", let d = value.doubleValue, d > 0 { leaderLength = d / Double(ctx.isSheet ? 1 : ctx.scale) }
    }

    func tagData(for e: Element, at p: Vec2) -> TagData {
        let anchor = AnnotationGeometry.leaderAnchor(e, ctx.model, view: ctx.view) ?? p
        let head = leader ? anchor + Vec2(1, 1).normalized * ctx.paper(leaderLength) : anchor
        var td = TagData(taggedID: e.id, head: head, hasLeader: leader)
        td.orientation = orientation
        return td
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let e = hit(i, categories), let tt = tagType(for: e.category) else { preview.cursor = .notAllowed; return }
        preview.highlight = [e.id]
        preview.cursor = .pick
        let probe = Element(id: ElementID(UInt64.max - 8), category: .tags, data: .tag(tagData(for: e, at: i.point)), typeID: tt, ownerViewID: ctx.viewID)
        if let prims = AnnotationRenderer.previewItem(probe, model: ctx.model, scale: ctx.isSheet ? 1 : ctx.scale) {
            preview.primitives = AnnotationPreview.tinted(prims, ctx.previewStroke.color)
        }
    }

    /// Loads the area or multi-category tag family when the project has none (older projects).
    func ensureFamily() {
        let name: String
        switch commandID {
        case .areaTag: name = AnnotationLibrary.areaTagName
        case .multiCategoryTag: name = AnnotationLibrary.multiCategoryTagName
        case .spaceTag: // F5
            if !ctx.model.elements(.families).contains(where: { $0.name == SpaceTags.familyName }) {
                ctx.session.perform("Load \(SpaceTags.familyName)") { tx in SpaceTags.ensure(in: tx) }
            }
            return
        default: return
        }
        guard !ctx.model.elements(.families).contains(where: { $0.name == name }) else { return }
        ctx.session.perform("Load \(name)") { tx in
            AnnotationLibrary.load(name == AnnotationLibrary.areaTagName ? AnnotationLibrary.areaTag() : AnnotationLibrary.multiCategoryTag(), in: tx)
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard let e = hit(i, categories) else {
            message(commandID == .roomTag ? "Click a room." : commandID == .areaTag ? "Click an area." : commandID == .spaceTag ? "Click a space." : "Click a taggable element.") // F5
            return
        }
        ensureFamily()
        guard let tt = tagType(for: e.category) else { message("No tag family is loaded for \(e.category.displayName). Load one from the library."); return }
        if !ctx.model.tags(of: e.id).filter({ $0.ownerViewID == ctx.viewID && $0.tag?.kind == nil }).isEmpty { message("This element is already tagged in this view.") }
        let view = ctx.viewID
        let td = tagData(for: e, at: i.point)
        ctx.session.perform("Tag \(e.category.singularName)") { tx in tx.create(.tags, data: .tag(td), typeID: tt, ownerViewID: view) }
        if let err = ctx.session.lastError { message(err.message) }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Tag All

/// Settings of a Tag All run.
public struct TagAllOptions: Sendable, Hashable {
    /// Categories to tag, each with the tag type to use.
    public var tagTypes: [Category: ElementID]
    /// Tag only these elements (the selection) instead of everything visible.
    public var onlyElements: Set<ElementID>?
    public var leader: Bool
    /// Leader length on paper (meters).
    public var leaderLength: Double
    public var orientation: TagOrientation
    public init(tagTypes: [Category: ElementID], onlyElements: Set<ElementID>? = nil, leader: Bool = false, leaderLength: Double = 0.012,
                orientation: TagOrientation = .horizontal) {
        self.tagTypes = tagTypes; self.onlyElements = onlyElements; self.leader = leader; self.leaderLength = leaderLength; self.orientation = orientation
    }
}

/// Tags every untagged element of chosen categories in a view.
public enum TagAll {
    /// Tag types whose family tags `c`, in type-selector order.
    public static func tagTypes(for c: Category, _ model: BIMModel) -> [Element] {
        let all = model.types(for: .tags).filter { t in model[t.typeData?.familyID]?.family?.taggedCategories.contains(c) == true }
        // A category's own tags come before the multi-category tag (W2-ANNOT).
        return all.filter { !AnnotationLibrary.isMultiCategory($0, model) } + all.filter { AnnotationLibrary.isMultiCategory($0, model) }
    }

    /// Elements among `visible` that can be tagged and have no tag in `view`, by category.
    public static func untagged(in view: ElementID, visible: Set<ElementID>, _ model: BIMModel) -> [Category: [ElementID]] {
        var out: [Category: [ElementID]] = [:]
        for id in visible.sorted() {
            guard let e = model[id], Category.taggable.contains(e.category), AnnotationGeometry.planAnchor(e, model) != nil else { continue }
            if model.tags(of: id).contains(where: { $0.ownerViewID == view && $0.tag?.kind == nil }) { continue }
            out[e.category, default: []].append(id)
        }
        return out
    }

    /// Creates the tags inside a transaction; returns how many were placed. `scale` converts paper leader lengths.
    @discardableResult
    public static func run(_ o: TagAllOptions, view: ElementID, visible: Set<ElementID>, scale: Int, in tx: TransactionContext) -> Int {
        var count = 0
        let candidates = untagged(in: view, visible: visible, tx.model)
        let offset = Vec2(1, 1).normalized * (o.leaderLength * Double(scale))
        for c in candidates.keys.sorted() {
            guard let tt = o.tagTypes[c], tx.model[tt]?.typeData != nil else { continue }
            for id in candidates[c] ?? [] {
                if let only = o.onlyElements, !only.contains(id) { continue }
                guard let e = tx.model[id], let anchor = AnnotationGeometry.leaderAnchor(e, tx.model, view: tx.model[view]) else { continue }
                var td = TagData(taggedID: id, head: o.leader ? anchor + offset : anchor, hasLeader: o.leader)
                td.orientation = o.orientation
                tx.create(.tags, data: .tag(td), typeID: tt, ownerViewID: view)
                count += 1
            }
        }
        return count
    }
}

// MARK: - Color fill legend

/// Places a colour fill legend for the view's colour scheme.
@MainActor
public final class ColorFillLegendTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.colorFillLegend
    public let title = "Color Fill Legend"
    public var prompt: String {
        guard let v = ctx.view else { return "" }
        return ColorFill.scheme(for: v, ctx.model) == nil ? "Assign a color scheme to this view first (Color Schemes…)." : "Click to place the legend (top-left corner)."
    }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        let probe = Element(id: ElementID(UInt64.max - 5), category: .colorFillLegends, data: .colorFillLegend(ColorFillLegendData(position: i.point)), ownerViewID: ctx.viewID)
        if let prims = AnnotationRenderer.previewItem(probe, model: ctx.model, scale: ctx.scale) { preview.primitives = prims }
    }
    public func pointerDown(_ i: ToolInput) {
        guard let v = ctx.view, v.view?.kind.isPlan == true || v.view?.kind == .section || v.view?.kind == .detail else { message("Color fill legends go in plan and section views."); return }
        guard ColorFill.scheme(for: v, ctx.model) != nil else { message("Assign a color scheme to this view first (Color Schemes…)."); return }
        let view = ctx.viewID, p = i.point
        ctx.session.perform("Place Color Fill Legend") { tx in
            tx.create(.colorFillLegends, data: .colorFillLegend(ColorFillLegendData(position: p)), ownerViewID: view)
        }
        if let e = ctx.session.lastError { message(e.message) } else { ctx.toolFinished?() }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Text notes

// W2-ANNOT: TextTool moved to AnnotateTools.swift (leaders, alignment, wrap width, in-place editing).

// MARK: - Spot annotations

/// Spot elevations, coordinates and slopes: click a point on the model, then where the label goes. The value follows
/// the floor or roof it was placed on (W2-ANNOT); in sections and elevations a spot elevation measures the point's height.
@MainActor
public final class SpotTool: BaseTool, InteractiveTool {
    public let kind: SpotKind
    public var commandID: CommandID { kind == .elevation ? .spotElevation : kind == .coordinate ? .spotCoordinate : .spotSlope }
    public var title: String { kind.rawValue }
    var point: Vec2?
    var elevation = 0.0
    var slope = 0.0
    var slopeDirection = 0.0
    var reference: ElementID?
    /// Place the label with a leader (else on the point).
    public var leader = true

    public init(ctx: ToolContext, kind: SpotKind) { self.kind = kind; super.init(ctx: ctx) }
    public var prompt: String {
        if let reason = unavailableReason { return reason }
        return point == nil ? "Click a point on the model." : "Click to place the annotation."
    }
    var unavailableReason: String? {
        if kind == .coordinate && ctx.isVertical { return "Spot coordinates are placed in plan views." }
        if kind == .slope && ctx.isVertical { return "Spot slopes are placed on floors and roofs in plan views." }
        if ctx.isSheet || ctx.viewData?.kind == .threeD { return "Place spots in a plan, section or elevation." }
        return nil
    }
    public var options: [ToolOption] { [ToolOption(id: "leader", label: "Leader", kind: .bool, value: .bool(leader))] }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "leader" { leader = value.boolValue ?? true } }

    func surface(at p: Vec2, _ i: ToolInput) -> (Double, ElementID?, Double, Double) {
        if ctx.isVertical { return (p.y, i.hit, 0, 0) }
        return SpotGeometry.surface(at: p, levelID: ctx.levelID, ctx.model)
    }

    func data(point p: Vec2, head: Vec2) -> SpotData {
        var sd = SpotData(kind: kind, point: p, elevation: elevation, leaderHead: head, referenceID: reference)
        sd.slope = slope; sd.slopeDirection = slopeDirection
        return sd
    }
    var category: Category { kind == .elevation ? .spotElevations : kind == .coordinate ? .spotCoordinates : .spotSlopes }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard unavailableReason == nil else { preview.cursor = .notAllowed; return }
        let p = point ?? i.point
        if point == nil { (elevation, reference, slope, slopeDirection) = surface(at: i.point, i) }
        let head = point == nil ? i.point + Vec2(ctx.paper(0.006), ctx.paper(0.006)) : i.point
        let probe = Element(id: ElementID(UInt64.max - 7), category: category, data: .spot(data(point: p, head: leader ? head : p)), ownerViewID: ctx.viewID)
        if let prims = AnnotationRenderer.previewItem(probe, model: ctx.model, scale: ctx.isSheet ? 1 : ctx.scale) {
            preview.primitives = AnnotationPreview.tinted(prims, ctx.previewStroke.color)
        }
    }
    public func pointerDown(_ i: ToolInput) {
        if let reason = unavailableReason { message(reason); return }
        guard let p = point else {
            point = i.point
            (elevation, reference, slope, slopeDirection) = surface(at: i.point, i)
            if !leader { place(head: i.point) }
            return
        }
        place(head: i.point)
        _ = p
    }
    func place(head: Vec2) {
        guard let p = point else { return }
        let view = ctx.viewID, cat = category
        let sd = data(point: p, head: leader ? head : p)
        ctx.session.perform("Place \(title)") { tx in tx.create(cat, data: .spot(sd), ownerViewID: view) }
        if let err = ctx.session.lastError { message(err.message) }
        point = nil
        preview = ToolPreview()
    }
    public func escape() -> EscapeResult {
        if point != nil { point = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Elevation marker

@MainActor
public final class ElevationTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.elevation
    public let title = "Elevation"
    public var prompt: String { ctx.isPlan ? "Click to place an elevation marker; it faces the nearest wall." : "Place elevations in a plan view." }

    func direction(at p: Vec2) -> Vec2 {
        var best: (Double, Vec2)?
        for w in ctx.model.elements(.walls) where w.levelID == ctx.levelID {
            guard let c = w.wall?.location else { continue }
            let q = c.closestPoint(to: p)
            let d = q.distance(to: p)
            if d < (best?.0 ?? 40), d > 1e-6 {
                // Face the wall squarely (use the wall's normal pointing away from the marker).
                var n = c.normal(at: 0.5)
                if n.dot(q - p) < 0 { n = -n }
                best = (d, n)
            }
        }
        return best?.1 ?? Vec2(0, 1)
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        let d = direction(at: i.point)
        let r = ctx.paper(0.005)
        preview.primitives = [.arc(Arc2(center: i.point, radius: r, startAngle: 0, sweep: Angle.twoPi), ctx.previewHeavy),
                              .polyline([i.point + d * r * 1.7, i.point + d.perpendicular * r, i.point - d.perpendicular * r], closed: true, ctx.previewHeavy)]
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Place elevations in a plan view."); return }
        let d = direction(at: i.point)
        let levels = ctx.model.levels.compactMap { $0.level?.elevation }
        let zmin = (levels.min() ?? 0) - 1, zmax = (levels.max() ?? 3) + 2
        let n = ctx.model.views.filter { $0.view?.kind == .elevation }.count + 1
        let scale = ctx.scale
        let phase = ctx.model.latestPhase?.id
        var createdID: ElementID?
        ctx.session.perform("Create Elevation") { tx in
            var v = ViewData(kind: .elevation, scale: scale)
            v.planeOrigin = Vec3(i.point, z: 0)
            v.viewDirection = d
            v.markerPosition = i.point
            v.farClip = 40
            v.cropRegion = Rect2(min: Vec2(-12, zmin), max: Vec2(12, zmax))
            v.cropActive = true
            v.phaseID = phase
            createdID = tx.create(.views, name: "Elevation \(n)", data: .view(v))
        }
        if let createdID { message("Created “\(ctx.model[createdID]?.name ?? "")”. Double-click the marker to open it.") }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Toposurface

@MainActor
public final class ToposurfaceTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.toposurface
    public let title = "Toposurface"
    public var isSketchMode: Bool { true }
    public var elevation = 0.0
    var points: [Vec3] = []
    public var prompt: String { "Click to add survey points at the current elevation (\(ctx.format(elevation))). Finish when done (≥ 3 points)." }
    public var numericLabel: String? { "Elevation" }
    public var options: [ToolOption] { [ToolOption(id: "elevation", label: "Elevation", kind: .length, value: .double(elevation))] }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "elevation" { elevation = value.doubleValue ?? 0 } }
    public func numericInput(_ text: String) -> Bool {
        guard let v = ctx.parse(text) else { return false }
        elevation = v
        return true
    }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        for p in points {
            let s = ctx.paper(0.0015)
            preview.primitives.append(.polyline(Rect2(center: p.xy, halfSize: Vec2(s, s)).corners, closed: true, ctx.previewHeavy))
        }
    }
    public func pointerDown(_ i: ToolInput) { points.append(Vec3(i.point, z: elevation)); pointerMoved(i) }
    public func finish() -> Bool {
        guard points.count >= 3 else { message("A toposurface needs at least three points."); return false }
        let pts = points
        ctx.session.perform("Create Toposurface") { tx in tx.create(.topography, name: "Toposurface", data: .topography(TopographyData(points: pts))) }
        points = []
        ctx.toolFinished?()
        return true
    }
    public func cancelSketch() { points = []; ctx.toolFinished?() }
    public func escape() -> EscapeResult {
        if !points.isEmpty { points.removeLast(); return .stayInTool }
        return .exitTool
    }
}

extension AnnotationRenderer {
    /// Primitives for previewing a not-yet-created annotation/detail item.
    public static func previewItem(_ e: Element, model: BIMModel, scale: Int) -> [GPrimitive]? {
        item(e, GraphicOverride(), model: model, scale: scale, builder: nil)?.primitives
    }
}
