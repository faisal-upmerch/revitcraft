import Foundation
import ArcusGeometry
import ArcusDomain

// F5: Massing & Site ▸ Model by Face. With masses selected the command builds on all of their faces at once, as
// RevitCraft does (`ModelByFace.create` from the router); otherwise this tool picks faces one at a time, as Revit
// does: in plans a side face by its edge (walls, curtain systems) or a whole mass (floors, roof), in 3D the face under
// the pointer.

/// Picks mass faces and builds walls, curtain walls, floors or a roof on them.
@MainActor
public final class ModelByFaceTool: BaseTool, InteractiveTool {
    public let kind: ModelByFaceKind
    public var commandID: CommandID {
        switch kind {
        case .wall: .wallByFace
        case .curtainSystem: .curtainSystemByFace
        case .floor: .floorByFace
        case .roof: .roofByFace
        }
    }
    public var title: String { CommandCatalog.info(commandID).title }
    /// The type the new elements take (the type selector's wall, curtain wall, floor or roof type).
    public var typeID: ElementID?

    public init(ctx: ToolContext, kind: ModelByFaceKind, typeID: ElementID?) {
        self.kind = kind
        self.typeID = typeID
        super.init(ctx: ctx)
    }

    /// The type selector's choice when it suits the tool (a curtain wall type only for curtain systems), else `typeID`.
    var currentType: ElementID? {
        let category: Category = kind == .floor ? .floors : kind == .roof ? .roofs : .walls
        guard let t = ctx.currentTypes[category], let td = ctx.model[t]?.typeData, td.instanceCategory == category else { return typeID }
        switch kind {
        case .wall: return td.curtain == nil ? t : typeID
        case .curtainSystem: return td.curtain != nil ? t : typeID
        case .floor, .roof: return t
        }
    }

    public var prompt: String {
        switch kind {
        case .wall: "Click a side face of a mass to put a wall on it."
        case .curtainSystem: "Click a side face of a mass to put a curtain wall on it."
        case .floor: "Click a mass to put floors at its mass floors (where levels cut it)."
        case .roof: "Click the top face of a mass (or the mass in a plan) to put a roof on it."
        }
    }

    /// The mass and face under the pointer.
    func pick(_ i: ToolInput) -> (mass: Element, face: MassFace?)? {
        guard let e = hit(i, [.mass]) else { return nil }
        let m = ctx.model
        if let p = i.surfacePoint { return (e, MassGeometry.face(e, m, at: p)) } // 3D: the face clicked
        switch kind {
        case .wall, .curtainSystem: return (e, MassGeometry.nearestSideFace(e, m, to: i.rawPoint))
        case .roof: return (e, MassGeometry.faces(e, m).first { $0.kind == .top })
        case .floor: return (e, nil)
        }
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let (e, face) = pick(i) else { preview.cursor = .notAllowed; return }
        preview.highlight = [e.id]
        preview.cursor = .pick
        guard let face, ctx.isPlan else { return }
        switch face.kind {
        case .side: preview.primitives = [.polyline([face.bottom.start, face.bottom.end], closed: false, ctx.previewHeavy)]
        case .top: if let top = e.mass.flatMap(MassGeometry.topLoop) { preview.primitives = [.polyline(top.points, closed: true, ctx.previewHeavy)] }
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard let (e, face) = pick(i) else { message("Click a mass. Use In-Place Mass to create one."); return }
        if kind == .roof, face?.kind != .top { message("Roofs by face go on the top face of a mass."); return }
        if kind == .wall || kind == .curtainSystem, face?.kind != .side { message("Walls by face go on the side faces of a mass."); return }
        let faces = face.map { [$0] }
        var made: [ElementID] = []
        let type = currentType
        ctx.session.perform(title) { tx in made = try ModelByFace.create(kind, mass: e.id, faces: faces, typeID: type, in: tx) }
        if let err = ctx.session.lastError { message(err.message); return }
        message("\(title): \(made.count) \(made.count == 1 ? "element" : "elements") created.")
    }
    public func escape() -> EscapeResult { .exitTool }
}
