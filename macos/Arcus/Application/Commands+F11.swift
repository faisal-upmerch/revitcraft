import Foundation

// F11: Manage, schedules and export: global parameters, coordinates, design options, selections, schedule tools, export formats. Docs/RevitCraftPort.md §5.

extension CommandCatalog {
    /// Titles and help follow RevitCraft (`crates/rc-app/src/commands.rs` `Cmd::info`); RevitCraft gives none of these an alias.
    static let f11Commands: [CommandInfo] = [
        // F11 Manage
        CommandInfo(.globalParameters, "Global Parameters", .manage, "globe", help: "Creates project-wide values that drive dimensions and element parameters.", keywords: ["global", "parameter", "formula"]),
        CommandInfo(.specifyCoordinates, "Specify Coordinates at Point", .manage, "scope", help: "Click a point and enter its shared coordinates (North/South, East/West, Elevation) and the angle to true north.", keywords: ["shared coordinates", "survey"]),
        CommandInfo(.reportCoordinates, "Report Shared Coordinates", .manage, "location.viewfinder", help: "Click points to read their shared coordinates.", keywords: ["shared coordinates", "survey"]),
        CommandInfo(.relocateProject, "Relocate Project", .manage, "arrow.up.and.down.and.arrow.left.and.right", help: "Moves the project against the shared coordinates: click a start and an end point.", keywords: ["shared coordinates", "position"]),
        CommandInfo(.rotateTrueNorth, "Rotate True North", .manage, "location.north.line", help: "Sets the angle between project north and true north.", keywords: ["north", "position"]),
        CommandInfo(.rotateProjectNorth, "Rotate Project North", .manage, "rotate.right", help: "Turns the whole project (model and views) 90° or 180° about its origin; true north stays where it is.", keywords: ["north", "position"]),
        CommandInfo(.mirrorProject, "Mirror Project", .manage, "arrow.left.and.right.righttriangle.left.righttriangle.right", help: "Mirrors the whole project about its north-south or east-west axis.", keywords: ["position", "flip"]),
        CommandInfo(.addToSet, "Add to Set", .manage, "plus.square.on.square", help: "Moves the selected main model elements into design options of a set.", keywords: ["design option"]),
        CommandInfo(.pickToEdit, "Pick to Edit", .manage, "hand.point.up.left", help: "Click an element to edit the design option it belongs to.", keywords: ["design option"]),
        CommandInfo(.startingView, "Starting View", .manage, "flag", help: "Specifies the view that opens when the project opens."),
        CommandInfo(.saveSelection, "Save Selection", .manage, "square.and.arrow.down.on.square", help: "Saves the current selection so it can be loaded later.", keywords: ["selection set"]),
        CommandInfo(.loadSelection, "Load Selection", .manage, "square.and.arrow.up.on.square", help: "Loads a saved selection.", keywords: ["selection set"]),
        CommandInfo(.editSelection, "Edit Selection", .manage, "pencil.and.list.clipboard", help: "Renames or deletes saved selections.", keywords: ["selection set"]),
        CommandInfo(.selectJoinedElements, "Select Joined Elements", .modify, "link", help: "Adds the elements joined to the selection.", keywords: ["wall joins"]),
        // F12 schedule tools (the Modify Schedule/Quantities tab) and keynotes
        CommandInfo(.scheduleCombineParameters, "Combine Parameters", .view, "rectangle.2.swap", help: "Combines several parameters into one column.", keywords: ["schedule"]),
        CommandInfo(.scheduleInsertHeaderRow, "Insert Row", .view, "text.insert", help: "Inserts a row in the header.", keywords: ["schedule", "title"]),
        CommandInfo(.scheduleInsertRowAbove, "Insert Row Above Selected", .view, "arrow.up.to.line", help: "Inserts a header row above the selected row.", keywords: ["schedule", "above selected"]),
        CommandInfo(.scheduleInsertRowBelow, "Insert Row Below Selected", .view, "arrow.down.to.line", help: "Inserts a header row below the selected row.", keywords: ["schedule", "below selected"]),
        CommandInfo(.scheduleResizeRow, "Resize Row", .view, "arrow.up.and.down.square", help: "Sets the height of the selected row.", keywords: ["schedule"]),
        CommandInfo(.scheduleInsertImage, "Insert Image", .view, "photo.badge.plus", help: "Inserts an image in a header cell.", keywords: ["schedule", "logo"]),
        CommandInfo(.scheduleClearCell, "Clear Cell", .view, "eraser", help: "Clears the text of a header cell.", keywords: ["schedule"]),
        CommandInfo(.scheduleFreezeHeader, "Freeze Header", .view, "pin.square", help: "Keeps the title and headers in view while scrolling.", keywords: ["schedule"]),
        CommandInfo(.scheduleShading, "Shading", .view, "paintbrush.fill", help: "Sets the background colour of cells.", keywords: ["schedule", "fill"]),
        CommandInfo(.scheduleBorders, "Borders", .view, "square.dashed", help: "Sets the borders of cells.", keywords: ["schedule", "lines"]),
        CommandInfo(.scheduleResetAppearance, "Reset", .view, "arrow.counterclockwise.square", help: "Resets the appearance of cells.", keywords: ["schedule"]),
        CommandInfo(.scheduleFont, "Font", .view, "textformat", help: "Sets the font of cells.", keywords: ["schedule", "text"]),
        CommandInfo(.scheduleAlignLeft, "Align Left", .view, "text.alignleft", help: "Aligns the selected column: left.", keywords: ["schedule", "align horizontal"]),
        CommandInfo(.scheduleAlignCenter, "Align Center", .view, "text.aligncenter", help: "Aligns the selected column: center.", keywords: ["schedule", "align horizontal"]),
        CommandInfo(.scheduleAlignRight, "Align Right", .view, "text.alignright", help: "Aligns the selected column: right.", keywords: ["schedule", "align horizontal"]),
        CommandInfo(.scheduleAlignTop, "Align Top", .view, "arrow.up.to.line.compact", help: "Aligns the selected cells' text to the top.", keywords: ["schedule", "align vertical"]),
        CommandInfo(.scheduleAlignMiddle, "Align Middle", .view, "arrow.up.and.down.text.horizontal", help: "Aligns the selected cells' text to the middle.", keywords: ["schedule", "align vertical"]),
        CommandInfo(.scheduleAlignBottom, "Align Bottom", .view, "arrow.down.to.line.compact", help: "Aligns the selected cells' text to the bottom.", keywords: ["schedule", "align vertical"]),
        CommandInfo(.scheduleSplitAndPlace, "Split & Place", .view, "rectangle.split.3x1", help: "Splits the schedule and places the parts on a sheet.", keywords: ["schedule", "sheet", "segments"]),
        CommandInfo(.keynoteLegend, "Keynote Legend", .view, "list.number", help: "Creates a legend listing the keynotes used in the project.", keywords: ["keynote", "legend"]),
        CommandInfo(.keynotingSettings, "Keynoting Settings", .annotate, "key.viewfinder", help: "Chooses the keynote table and how keynote tags read.", keywords: ["keynote"]),
        // F13 export and print (File menu)
        CommandInfo(.exportDWFx, "Export DWF/DWFx…", .file, "doc.richtext", help: "Exports views and sheets to a DWFx file (for markup and review).", keywords: ["dwf", "dwfx", "xps"]),
        CommandInfo(.exportSTL, "Export STL…", .file, "cube", help: "Exports the model as an STL file (millimetres).", keywords: ["stl", "3d print", "mesh"]),
        CommandInfo(.exportGbXML, "Export gbXML…", .file, "leaf", help: "Saves the rooms and spaces as a gbXML file.", keywords: ["gbxml", "energy", "spaces"]),
        CommandInfo(.exportRoomAreaReport, "Export Room/Area Report…", .file, "doc.text.magnifyingglass", help: "Saves an HTML report of the rooms with their areas and shapes.", keywords: ["report", "rooms", "areas", "html", "csv"]),
        CommandInfo(.exportFamilyTypes, "Export Family Types…", .file, "list.bullet.rectangle.portrait", help: "Exports the family's types to a type catalog (.txt).", keywords: ["type catalog", "family"]),
        CommandInfo(.printPreview, "Print Preview", .file, "doc.viewfinder", help: "Shows how the current view or sheet will print."),
        CommandInfo(.printSetup, "Print Setup…", .file, "printer.dotmatrix", help: "Specifies the paper, zoom, colors and options used to print.", keywords: ["page setup"]),
    ]
}
