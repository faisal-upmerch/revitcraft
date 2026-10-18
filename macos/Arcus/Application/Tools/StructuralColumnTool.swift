import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

/// F2: Structural Column with RevitCraft's Placement and Multiple panels (`canvas_tools.rs` column placement,
/// `column_multi_tool`, `finish_columns`): Vertical Column (the default) places as the component tool does; Slanted
/// Column takes the base, then the top (the 2nd click's level, or a height); At Grids and At Columns pick grids or
/// architectural columns, preview the columns, and Finish places one at each grid intersection or column.
@MainActor
public final class StructuralColumnTool: BaseTool, InteractiveTool {
    public enum Multiple: Sendable { case atGrids, atColumns }

    /// Vertical placement is the component tool's.
    let vertical: ComponentTool
    public private(set) var slanted = false
    public private(set) var multiple: Multiple?
    /// Slanted Column: the base point once clicked.
    public private(set) var base: Vec2?
    /// Grids or architectural columns picked for At Grids / At Columns.
    public private(set) var picked: [ElementID] = []
    /// Slanted Column: the top's level (2nd click), else `height` above the base.
    public var topLevelID: ElementID?
    public var height = 3.0
    var current: Vec2?

    public override init(ctx: ToolContext) {
        vertical = ComponentTool(ctx: ctx, category: .structuralColumns, commandID: .structuralColumn)
        super.init(ctx: ctx)
        topLevelID = ctx.model.levelAbove(ctx.levelID)?.id
    }

    public var commandID: CommandID { .structuralColumn }
    public var title: String { "Structural Column" }
    public var prompt: String {
        switch multiple {
        case .atGrids?: return "Select grids (each click adds or removes one), then click Finish."
        case .atColumns?: return "Select architectural columns (each click adds or removes one), then click Finish."
        case nil:
            guard slanted else { return vertical.prompt }
            return base == nil ? "Click to enter the column start point." : "Click to enter the column end point."
        }
    }
    public var snapFrom: Vec2? { slanted ? base : nil }
    public var options: [ToolOption] {
        if multiple != nil { return [] }
        guard slanted else { return vertical.options }
        // As RevitCraft: the levels of the 1st (base) and 2nd (top) clicks; Unconnected uses a height.
        var o = [ToolOption(id: "first", label: "1st Click", kind: .choice([ctx.model[ctx.levelID]?.name ?? "Level"]), value: .text(ctx.model[ctx.levelID]?.name ?? "Level")),
                 ToolOption(id: "top", label: "2nd Click", kind: .choice(["Unconnected"] + ctx.model.levels.map(\.name)), value: .text(ctx.model[topLevelID]?.name ?? "Unconnected"))]
        if topLevelID == nil { o.append(ToolOption(id: "height", label: "Height", kind: .length, value: .double(height))) }
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        guard slanted else { vertical.setOption(id, value); return }
        switch id {
        case "top": topLevelID = ctx.model.levels.first { $0.name == value.textValue }?.id
        case "height": if let h = value.doubleValue, h > 0.1 { height = h }
        default: break
        }
    }

    // MARK: Modes

    /// Vertical Column (the default placement).
    public func placeVertical() { slanted = false; multiple = nil; base = nil; picked = []; preview = ToolPreview() }
    /// Slanted Column.
    public func placeSlanted() { slanted = true; multiple = nil; base = nil; picked = []; preview = ToolPreview() }
    /// At Grids / At Columns.
    public func pickMultiple(_ m: Multiple) { multiple = m; base = nil; picked = []; preview = ToolPreview() }
    /// Multiple ▸ Cancel.
    public func cancelMultiple() { multiple = nil; picked = []; preview = ToolPreview() }

    // MARK: Pointer

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        if multiple != nil { rebuildMultiple(hover: pickable(i)); return }
        guard slanted else { vertical.pointerMoved(i); preview = vertical.preview; return }
        preview = ToolPreview()
        preview.cursor = .crosshair
        guard let b = base, let e = probe(base: b, top: i.point) else { return }
        preview.primitives = ComponentGeometry.planOutline(e, ctx.model).map { .polyline($0.points, closed: true, ctx.previewStroke) }
        preview.primitives += ComponentGeometry.planOutline(e, ctx.model).map { o in .polyline(o.points.map { $0 + (i.point - b) }, closed: true, ctx.previewHeavy) }
        preview.primitives.append(ctx.line(b, i.point, heavy: true))
        preview.tempDims = [tempDim(b, i.point)]
    }

    public func pointerDown(_ i: ToolInput) {
        if multiple != nil {
            if let id = pickable(i) { if let k = picked.firstIndex(of: id) { picked.remove(at: k) } else { picked.append(id) } }
            rebuildMultiple(hover: nil)
            return
        }
        guard slanted else { vertical.pointerDown(i); return }
        guard ctx.isPlan else { message("Place columns in a plan view."); return }
        guard let b = base else { base = i.point; return }
        guard i.point.distance(to: b) > Tolerance.shortCurve else { message("Click the top away from the base, or use Vertical Column."); return }
        guard let e = probe(base: b, top: i.point), let t = e.typeID else { message("Load a structural column family first."); return }
        ctx.session.perform("Place Slanted Column") { tx in tx.create(.structuralColumns, data: e.data, typeID: t, levelID: ctx.levelID) }
        if let err = ctx.session.lastError { message(err.message) }
        base = nil
        preview = ToolPreview()
    }

    func probe(base b: Vec2, top: Vec2) -> Element? {
        guard let t = ctx.type(for: .structuralColumns) else { return nil }
        var c = ColumnData(location: b, rotation: vertical.rotation, topLevelID: topLevelID, unconnectedHeight: height)
        c.topLocation = top
        return Element(id: ElementID(UInt64.max - 3), category: .structuralColumns, data: .column(c), typeID: t, levelID: ctx.levelID)
    }

    /// The grid or architectural column under the pointer that At Grids / At Columns can pick.
    func pickable(_ i: ToolInput) -> ElementID? {
        let ids = i.hitCandidates.isEmpty ? (i.hit.map { [$0] } ?? []) : i.hitCandidates
        return ids.first { id in
            guard let e = ctx.model[id] else { return false }
            return multiple == .atGrids ? e.grid != nil : (e.category == .columns && e.column != nil)
        }
    }

    func rebuildMultiple(hover: ElementID?) {
        preview = ToolPreview()
        preview.cursor = hover == nil ? .crosshair : .pick
        preview.highlight = Set(picked + (hover.map { [$0] } ?? []))
        let s = ctx.paper(0.004)
        for q in Self.points(multiple, picked, ctx.model) {
            preview.primitives.append(.polyline(Rect2(center: q, halfSize: Vec2(s, s)).corners, closed: true, ctx.previewHeavy))
        }
    }

    /// Where At Grids / At Columns place columns: the intersections of the picked straight (or multi-segment) grids,
    /// or the picked architectural columns' points.
    public static func points(_ m: Multiple?, _ picked: [ElementID], _ model: BIMModel) -> [Vec2] {
        var out: [Vec2] = []
        func add(_ q: Vec2) { if !out.contains(where: { $0.distance(to: q) < 0.001 }) { out.append(q) } }
        switch m {
        case .atGrids?:
            let segs = picked.map { model[$0]?.grid?.segments ?? [] }
            for i in segs.indices {
                for j in segs.indices where j > i {
                    for a in segs[i] {
                        for b in segs[j] {
                            guard !a.isParallel(to: b), let hit = a.lineIntersection(b) else { continue }
                            if hit.t >= -1e-6, hit.t <= 1 + 1e-6, hit.u >= -1e-6, hit.u <= 1 + 1e-6 { add(hit.point) }
                        }
                    }
                }
            }
        case .atColumns?:
            for id in picked { if let c = model[id]?.column { add(c.location) } }
        case nil: break
        }
        return out
    }

    /// Multiple ▸ Finish (and ↩): one structural column at each point, from this level to the top level (or height).
    public func finish() -> Bool {
        guard let m = multiple else { return false }
        let pts = Self.points(m, picked, ctx.model)
        guard !pts.isEmpty else { message(m == .atGrids ? "Select at least two crossing grids." : "Select at least one architectural column."); return true }
        guard let t = ctx.type(for: .structuralColumns) else { message("Load a structural column family first."); return true }
        let top = vertical.topLevelID, rot = vertical.rotation, level = ctx.levelID
        // At Columns: each column takes the rotation of the architectural column it goes into.
        let rotations: [Vec2: Double] = m == .atColumns ? Dictionary(picked.compactMap { ctx.model[$0]?.column.map { ($0.location, $0.rotation) } }, uniquingKeysWith: { a, _ in a }) : [:]
        ctx.session.perform("Place Structural Columns") { tx in
            for q in pts { tx.create(.structuralColumns, data: .column(ColumnData(location: q, rotation: rotations[q] ?? rot, topLevelID: top)), typeID: t, levelID: level) }
        }
        if let err = ctx.session.lastError { message(err.message); return true }
        message("Placed \(pts.count) structural column\(pts.count == 1 ? "" : "s").")
        cancelMultiple()
        return true
    }

    public func numericInput(_ text: String) -> Bool { slanted || multiple != nil ? false : vertical.numericInput(text) }
    public func spaceBar() { if !slanted, multiple == nil { vertical.spaceBar(); preview = vertical.preview } }
    public func escape() -> EscapeResult {
        if base != nil { base = nil; preview = ToolPreview(); return .stayInTool }
        if multiple != nil { cancelMultiple(); return .stayInTool }
        return .exitTool
    }
}
