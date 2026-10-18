import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// BL-BROWSER: interactive viewport placement (Place View dialog, and views dragged from the Project Browser).

/// Places one or more views or schedules on the open sheet: their viewport outlines follow the cursor (several are
/// tiled in a row) and a click places them. Escape cancels without placing anything.
@MainActor
public final class PlaceViewportTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.placeView
    public var title: String { "View" }
    public let viewIDs: [ElementID]
    /// Paper size of each viewport, measured once when the tool starts.
    let sizes: [Vec2]
    var cursor: Vec2?
    /// Called with the created viewports after a click places them.
    public var onPlaced: (([ElementID]) -> Void)?

    public init(ctx: ToolContext, viewIDs: [ElementID]) {
        self.viewIDs = viewIDs
        sizes = viewIDs.map { SheetPlacement.paperSize(of: $0, ctx.model) }
        super.init(ctx: ctx)
    }

    public var prompt: String {
        guard ctx.isSheet else { return "Open a sheet to place views." }
        let names = viewIDs.compactMap { ctx.model[$0]?.name }
        let what = names.count == 1 ? "“\(names[0])”" : "\(names.count) views"
        return "Click to place \(what) on the sheet. Esc cancels."
    }

    public func pointerMoved(_ i: ToolInput) {
        cursor = i.point
        preview = ToolPreview()
        guard ctx.isSheet else { preview.cursor = .notAllowed; return }
        let centers = SheetPlacement.tiledCenters(sizes: sizes, at: i.point)
        for (c, s) in zip(centers, sizes) {
            let r = Rect2(center: c, halfSize: s * 0.5)
            let k = r.corners
            preview.primitives += (0..<4).map { ctx.line(k[$0], k[($0 + 1) % 4], heavy: true) }
            preview.primitives += [ctx.line(k[0], k[2]), ctx.line(k[1], k[3])]
        }
        preview.cursor = .copy
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isSheet else { message("Open a sheet to place views."); return }
        let sheet = ctx.viewID, ids = viewIDs, sz = sizes
        var result: (placed: [ElementID], refused: [String])?
        ctx.session.perform(ids.count == 1 ? "Place View" : "Place Views") { tx in
            result = try SheetPlacement.place(ids, sizes: sz, onSheet: sheet, at: i.point, in: tx)
        }
        preview = ToolPreview()
        if let result {
            if let r = result.refused.first { message(r) }
            onPlaced?(result.placed)
            ctx.toolFinished?()
        } else if let e = ctx.session.lastError {
            message(e.message)
            ctx.session.clearError()
            ctx.toolFinished?()
        }
    }

    public func escape() -> EscapeResult { .exitTool }
}
