import Foundation
import ArcusGeometry
import ArcusDomain

// F1: Room ▸ Highlight Boundaries (RevitCraft `Cmd::HighlightBoundaries` in crates/rc-app/src/actions.rs): highlights the
// room-bounding elements of the plan's level until the next click or Esc.

/// Shows the level's room-bounding walls, columns and room separation lines highlighted.
@MainActor
public final class HighlightBoundariesTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.highlightBoundaries
    public let title = "Highlight Boundaries"
    /// The highlighted elements.
    public let boundaries: [ElementID]

    public override init(ctx: ToolContext) {
        boundaries = ctx.levelID.map { RoomGeometry.boundingElements(level: $0, ctx.model) } ?? []
        super.init(ctx: ctx)
        preview.highlight = Set(boundaries)
        message(boundaries.isEmpty ? "The level has no room-bounding elements." : "Room Bounding elements are highlighted.")
    }

    public var prompt: String { "Room Bounding elements are highlighted. Click or press Esc to finish." }

    public func pointerMoved(_ i: ToolInput) {}
    public func pointerDown(_ i: ToolInput) { ctx.toolFinished?() }
    public func escape() -> EscapeResult { .exitTool }
}
