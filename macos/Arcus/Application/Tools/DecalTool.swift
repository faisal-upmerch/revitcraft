import Foundation
import ArcusGeometry
import ArcusDomain

/// F67: Place Decal. Click a wall face in a plan, elevation or section (or a floor or roof in a plan) to place a
/// decal of the chosen type there. The decal follows its host when the host moves and is deleted with it.
@MainActor
public final class DecalTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.placeDecal
    public let title = "Place Decal"
    public var typeID: ElementID?
    /// Called with each placed decal (the host selects it).
    public var onPlaced: ((ElementID) -> Void)?

    public init(ctx: ToolContext, typeID: ElementID?) {
        self.typeID = typeID ?? ctx.model.elements(.decalTypes).sorted { $0.name < $1.name }.first?.id
        super.init(ctx: ctx)
    }

    var typeNames: [String] { ctx.model.elements(.decalTypes).map(\.name).sorted() }
    public var prompt: String {
        typeID == nil ? "Create a decal type first (Decal Types)."
            : ctx.isVertical ? "Click a wall face to place the decal." : "Click a wall, floor or roof to place the decal."
    }
    public var options: [ToolOption] {
        [ToolOption(id: "decalType", label: "Decal Type", kind: .choice(typeNames), value: .text(typeID.flatMap { ctx.model[$0]?.name } ?? ""))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "decalType", let n = value.textValue { typeID = ctx.model.elements(.decalTypes).first { $0.name == n }?.id ?? typeID }
    }

    /// The host under the pointer and the face the decal goes on.
    func target(_ i: ToolInput) -> (ElementID, Vec3, Vec3)? {
        var ids = ([i.hit].compactMap { $0 } + i.hitCandidates)
        if ctx.isVertical, let h = InsertTool.verticalHost(at: i.rawPoint, view: ctx.viewData, model: ctx.model, width: 0, prefer: i.hit) { ids.append(h.wallID) }
        for id in ids {
            guard let e = ctx.model[id], Self.canHost(e), let (c, n) = InsertOperations.decalFace(host: e, at: i.rawPoint, view: ctx.viewData, model: ctx.model) else { continue }
            return (id, c, n)
        }
        return nil
    }

    static func canHost(_ e: Element) -> Bool {
        guard e.category.isModel, !e.isType, e.ownerViewID == nil, ElementMeshes.hasModelGeometry(e) else { return false }
        return e.linkedModel == nil && e.pointCloud == nil && e.decal == nil
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard typeID != nil, let (host, c, n) = target(i) else { preview.cursor = .notAllowed; return }
        preview.highlight = [host]
        preview.cursor = .pick
        // The decal's outline where it would go.
        let w = ctx.model.units.system == .imperial ? 0.9144 : 1.0
        let t = typeID.flatMap { ctx.model[$0]?.decalType }
        let h = t.map { $0.pixelWidth > 0 ? w * Double($0.pixelHeight) / Double($0.pixelWidth) : w } ?? w
        var up = Vec3(0, 0, 1) - n * n.z
        if up.length < 1e-6 { up = Vec3(0, 1, 0) - n * n.y }
        let d = DecalData(decalTypeID: ElementID(0), center: c, normal: n, up: up.normalized, width: w, height: h)
        let corners: [Vec2]
        if ctx.isVertical, let v = ctx.viewData, let o = v.planeOrigin, let r = v.rightVector {
            corners = d.corners().map { Vec2(($0.xy - o.xy).dot(r), $0.z) }
        } else if abs(n.z) > 0.7 {
            corners = d.corners().map(\.xy)
        } else {
            corners = [d.corners()[0].xy, d.corners()[1].xy]
        }
        preview.primitives = [.polyline(corners, closed: corners.count > 2, GStroke(weight: 2, color: RGBColor(0.1, 0.45, 0.9)))]
    }

    public func pointerDown(_ i: ToolInput) {
        guard let typeID else { message("Create a decal type first (Decal Types)."); return }
        guard let (host, c, n) = target(i) else {
            message("Decals are placed on planar faces of the model: wall faces in plans, elevations and sections, or floors and roofs in plans.")
            return
        }
        var made: ElementID?
        ctx.session.perform("Place Decal") { tx in made = try InsertOperations.placeDecal(typeID, host: host, center: c, normal: n, in: tx) }
        if let e = ctx.session.lastError { message(e.message); return }
        if let made { onPlaced?(made) }
    }

    public func escape() -> EscapeResult { .exitTool }
}
