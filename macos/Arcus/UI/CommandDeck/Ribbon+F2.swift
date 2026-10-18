import SwiftUI
import ArcusDomain
import ArcusApplication

// F2: ribbon captions and contextual panels of Architecture B (RevitCraft ribbon.rs: work_plane_panel, the stair,
// roof and structural column contextual panels, the Grid tool's Draw panel).

extension RibbonItem {
    /// RevitCraft's short ribbon captions for F2 commands.
    static func f2Caption(_ id: CommandID, size: Size, split: Bool) -> String? {
        switch id {
        case .workPlaneSet: return "Set"
        case .workPlaneShow: return "Show"
        case .workPlaneViewer: return "Viewer"
        case .gridMultiSegment: return size == .large ? "Multi-\nSegment" : "Multi-Segment"
        case .connectLevels: return size == .large ? "Connect\nLevels" : "Connect Levels"
        case .alignEaves: return size == .large ? "Align\nEaves" : "Align Eaves"
        case .verticalColumn: return size == .large ? "Vertical\nColumn" : "Vertical Column"
        case .slantedColumn: return size == .large ? "Slanted\nColumn" : "Slanted Column"
        case .columnsAtGrids: return size == .large ? "At\nGrids" : "At Grids"
        case .columnsAtColumns: return size == .large ? "At\nColumns" : "At Columns"
        case .multipleFinish: return "Finish"
        case .multipleCancel: return "Cancel"
        default: return nil
        }
    }
}

extension RibbonContent {
    /// RevitCraft's Work Plane panel (`work_plane_panel`, Architecture and Structure): Set, Show, Ref Plane, Viewer.
    static let workPlaneItems: [RibbonItem] = [.large(.workPlaneSet), .small(.workPlaneShow), .small(.referencePlane), .small(.workPlaneViewer)]

    /// Draw panel commands before the shapes: what a floor, ceiling or roof sketch draws (RevitCraft: Boundary Line,
    /// Slope Arrow).
    @MainActor static func f2DrawLeading(_ tool: any InteractiveTool) -> [CommandID] {
        guard let t = tool as? SketchTool, [.floor, .ceiling, .roof].contains(t.target), !t.isAligningEaves else { return [] }
        return [.sketchBoundaryLine, .slopeArrow]
    }

    /// Draw panel commands after the shapes: the Grid tool's Multi-Segment.
    @MainActor static func f2DrawTrailing(_ tool: any InteractiveTool) -> [CommandID] {
        if let l = tool as? LineTool, l.kind == .grid { return [.gridMultiSegment] }
        return []
    }

    /// Contextual panels of running tools: Multistory Stairs (stairs), Tools (roof footprint sketches), Placement and
    /// Multiple (structural columns), and the Work Plane panel in sketches, as RevitCraft's `contextual`.
    @MainActor static func f2ToolPanels(_ tool: any InteractiveTool, _ state: DocumentState) -> [RibbonPanel] {
        var out: [RibbonPanel] = []
        if tool is StairTool {
            out.append(RibbonPanel(title: "Multistory Stairs", items: [.large(.connectLevels)], tint: circulation))
        }
        if let t = tool as? SketchTool, t.target == .roof {
            out.append(RibbonPanel(title: "Tools", items: [.large(.alignEaves), .small(.adjustHeight), .small(.adjustOverhang)], tint: build))
        }
        if tool.isSketchMode { out.append(RibbonPanel(title: "Work Plane", items: [.large(.workPlaneSet), .small(.workPlaneShow), .small(.workPlaneViewer)], tint: datum)) }
        if let c = tool as? StructuralColumnTool {
            out.append(RibbonPanel(title: "Placement", items: [.large(.verticalColumn), .large(.slantedColumn)], tint: build))
            out.append(c.multiple == nil ? RibbonPanel(title: "Multiple", items: [.large(.columnsAtGrids), .large(.columnsAtColumns)], tint: build)
                       : RibbonPanel(title: "Multiple", items: [.large(.multipleFinish), .large(.multipleCancel)], tint: build))
        }
        return out
    }

    /// Selection panel items: a selected stair repeats over levels with Connect Levels.
    static func f2SelectionItems(_ sel: [Element], _ m: BIMModel) -> (title: String?, items: [RibbonItem]) {
        guard sel.count == 1, sel[0].stair != nil else { return (nil, []) }
        return ("Multistory Stairs", [.large(.connectLevels)])
    }

    /// The on state of F2 mode buttons (nil: the default, the running tool's command).
    @MainActor static func f2IsActive(_ id: CommandID, _ state: DocumentState) -> Bool? {
        switch id {
        case .slopeArrow: return (state.activeTool as? SketchTool)?.isDrawingSlopeArrow ?? false
        case .sketchBoundaryLine: return (state.activeTool as? SketchTool).map { !$0.isDrawingSlopeArrow && !$0.isAligningEaves } ?? false
        case .alignEaves: return (state.activeTool as? SketchTool)?.isAligningEaves ?? false
        case .adjustHeight: return (state.activeTool as? SketchTool).map { $0.isAligningEaves && $0.eaveAdjustment == .height } ?? false
        case .adjustOverhang: return (state.activeTool as? SketchTool).map { $0.isAligningEaves && $0.eaveAdjustment == .overhang } ?? false
        case .verticalColumn: return (state.activeTool as? StructuralColumnTool).map { !$0.slanted && $0.multiple == nil } ?? false
        case .slantedColumn: return (state.activeTool as? StructuralColumnTool).map { $0.slanted && $0.multiple == nil } ?? false
        case .columnsAtGrids: return (state.activeTool as? StructuralColumnTool)?.multiple == .atGrids
        case .columnsAtColumns: return (state.activeTool as? StructuralColumnTool)?.multiple == .atColumns
        case .workPlaneShow: return state.f2ShowsWorkPlane
        default: return nil
        }
    }
}
