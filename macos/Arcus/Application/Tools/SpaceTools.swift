import Foundation
import ArcusGeometry
import ArcusDomain

// F5: Analyze ▸ Spaces & Zones ▸ Space (RevitCraft: the Room tool in space mode, "Click to place space").

/// Places spaces in regions enclosed by walls, columns and space separators; the region under the pointer previews.
/// Tag on Placement (on by default) tags each new space with the space tag, loading it when the project has none.
@MainActor
public final class SpaceTool: BaseTool, InteractiveTool {
    public var commandID: CommandID { .space }
    public var title: String { "Space" }
    public var tagOnPlacement = true
    var arrangement: PlanarArrangement?
    var arrangementRevision: UInt64 = .max

    public var prompt: String {
        guard ctx.isPlan else { return "Spaces are placed in plan views." }
        return "Click to place space \(SpacePlacement.nextNumber(ctx.model))."
    }
    public var options: [ToolOption] { [ToolOption(id: "tag", label: "Tag on Placement", kind: .bool, value: .bool(tagOnPlacement))] }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "tag" { tagOnPlacement = value.boolValue ?? true } }

    func ensureArrangement() {
        guard let level = ctx.levelID, arrangementRevision != ctx.model.revision else { return }
        let z = ctx.levelElevation + max(0.3, ctx.model[level]?.level?.computationHeight ?? 0)
        arrangement = PlanarArrangement(segments: RoomGeometry.boundingSegments(level: level, atZ: z, ctx.model, separators: .spaceSeparationLines))
        arrangementRevision = ctx.model.revision
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard ctx.isPlan else { return }
        ensureArrangement()
        if let f = arrangement?.face(containing: i.rawPoint) {
            preview.primitives = [.fill(f.profile.loops, GFill(pattern: .solid, color: RGBColor(0.2, 0.55, 0.5), transparency: 0.8))]
                + f.profile.loops.map { .polyline($0.points, closed: true, ctx.previewHeavy) }
            preview.cursor = .crosshairPlus
        } else {
            preview.cursor = .crosshair
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan, let level = ctx.levelID else { message("Open a plan view to place spaces."); return }
        let tag = tagOnPlacement
        let view = ctx.viewID
        ctx.session.perform("Place Space") { tx in
            let id = try SpacePlacement.place(at: i.rawPoint, level: level, in: tx)
            if tag, let tt = SpaceTags.ensure(in: tx) { tx.create(.tags, data: .tag(TagData(taggedID: id, head: i.rawPoint)), typeID: tt, ownerViewID: view) }
        }
        if let e = ctx.session.lastError { message(e.message) }
    }
    public func escape() -> EscapeResult { .exitTool }
}
