import Foundation

// F2: Architecture B: stacked walls, multi-segment grids, work planes, multistory stairs, roof tools, slanted columns. Docs/RevitCraftPort.md §5.

extension CommandCatalog {
    /// Help follows RevitCraft (`crates/rc-app/src/commands.rs` `Cmd::info`); none of these has an alias there. Titles
    /// RevitCraft keeps short for the ribbon ("Set", "Multi-Segment", "At Grids") name their subject here, so menus and
    /// command search read on their own; the ribbon shows RevitCraft's captions (`RibbonItem.f2Caption`).
    static let f2Commands: [CommandInfo] = [
        CommandInfo(.stackedWall, "Wall: Stacked", .build, "square.stack.3d.down.forward",
                    help: "Draws walls of a stacked wall type: basic wall types stacked by height. Edit the stack in Type Properties.",
                    keywords: ["stacked wall", "base course", "plinth", "stack"]),
        CommandInfo(.gridMultiSegment, "Grid: Multi-Segment", .build, "point.topleft.down.to.point.bottomright.curvepath",
                    help: "Sketches a grid of several connected segments.", keywords: ["grid", "bent grid", "polyline grid"]),
        CommandInfo(.workPlaneSet, "Set Work Plane", .build, "square.grid.3x3.topleft.filled",
                    help: "Specifies the work plane of the current view: a level, a named reference plane, or a plane you pick.",
                    keywords: ["work plane", "sketch plane", "plane"]),
        CommandInfo(.workPlaneShow, "Show Work Plane", .build, "square.grid.3x3",
                    help: "Shows or hides the work plane grid in the current view.", keywords: ["work plane", "grid", "plane"]),
        CommandInfo(.workPlaneViewer, "Work Plane Viewer", .build, "macwindow.on.rectangle",
                    help: "Opens a viewer of the current work plane.", keywords: ["work plane", "viewer", "plane"]),
        CommandInfo(.connectLevels, "Connect Levels", .build, "stairs",
                    help: "Repeats the stair through the selected levels (multistory stair).", keywords: ["multistory", "multi-storey", "stair", "repeat"]),
        CommandInfo(.sketchBoundaryLine, "Boundary Line", .build, "skew",
                    help: "Draws the boundary lines of the sketch.", keywords: ["sketch", "boundary"]),
        CommandInfo(.slopeArrow, "Slope Arrow", .build, "arrow.up.right",
                    help: "Draws a slope arrow: the floor or roof rises from its tail to its head.", keywords: ["slope", "shed", "fall", "pitch"]),
        CommandInfo(.alignEaves, "Align Eaves", .build, "align.vertical.bottom",
                    help: "Aligns the eaves of the roof being sketched: pick the eave to match, then the eaves to align.", keywords: ["eave", "roof", "plate"]),
        CommandInfo(.adjustHeight, "Adjust Height", .build, "arrow.up.and.down",
                    help: "Aligns the picked eaves by adjusting the roof height. Available in Align Eaves mode.", keywords: ["eave", "roof", "slope"]),
        CommandInfo(.adjustOverhang, "Adjust Overhang", .build, "arrow.left.and.right",
                    help: "Aligns the picked eaves by adjusting the overhang. Available in Align Eaves mode.", keywords: ["eave", "roof", "overhang"]),
        CommandInfo(.verticalColumn, "Vertical Column", .structure, "rectangle.portrait",
                    help: "Places vertical columns.", keywords: ["column"]),
        CommandInfo(.slantedColumn, "Slanted Column", .structure, "line.diagonal",
                    help: "Places slanted columns: click the base, then the top.", keywords: ["column", "inclined", "raked", "slanted"]),
        CommandInfo(.columnsAtGrids, "Columns at Grids", .structure, "number.square",
                    help: "Places structural columns at the intersections of the grids you select; click Finish when done.", keywords: ["column", "grid", "intersection"]),
        CommandInfo(.columnsAtColumns, "Columns at Columns", .structure, "square.on.square",
                    help: "Places structural columns inside the architectural columns you select; click Finish when done.", keywords: ["column", "architectural column"]),
        CommandInfo(.multipleFinish, "Finish Placing Columns", .structure, "checkmark",
                    help: "Places the columns.", keywords: ["finish", "multiple"]),
        CommandInfo(.multipleCancel, "Cancel Placing Columns", .structure, "xmark",
                    help: "Cancels placing multiple columns.", keywords: ["cancel", "multiple"]),
    ]
}
