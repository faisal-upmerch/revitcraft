import Foundation

// F1415: Family Editor: main-window editor, views, reference/model lines, controls, swept blend, voids, openings. Docs/RevitCraftPort.md §5.
// Titles and help follow RevitCraft's `Cmd::info` (crates/rc-app/src/commands.rs, Fe* commands); RevitCraft gives them no
// aliases. They run in the Family Editor window; from the project window they act on the Family Editor open on this project.

extension CommandCatalog {
    static let f1415Commands: [CommandInfo] = [
        CommandInfo(.feExtrusion, "Extrusion", .manage, "cube", help: "Creates a solid by extruding a closed sketch perpendicular to the work plane.", keywords: ["family", "form", "solid"]),
        CommandInfo(.feBlend, "Blend", .manage, "trapezoid.and.line.vertical", help: "Creates a solid that blends a base sketch into a top sketch.", keywords: ["family", "form", "loft"]),
        CommandInfo(.feRevolve, "Revolve", .manage, "rotate.3d", help: "Creates a solid by revolving a sketch about an axis.", keywords: ["family", "form", "lathe"]),
        CommandInfo(.feSweep, "Sweep", .manage, "point.topleft.down.to.point.bottomright.curvepath", help: "Creates a solid by sweeping a profile along a path.", keywords: ["family", "form", "path", "profile"]),
        CommandInfo(.feSweptBlend, "Swept Blend", .manage, "point.topleft.down.to.point.bottomright.curvepath.fill", help: "Creates a solid swept along a path between two profiles.", keywords: ["family", "form", "path", "profile", "blend"]),
        CommandInfo(.feVoidExtrusion, "Void Extrusion", .manage, "cube.transparent", help: "Creates a void that cuts solids by extruding a closed sketch.", keywords: ["family", "void", "cut"]),
        CommandInfo(.feVoidBlend, "Void Blend", .manage, "trapezoid.and.line.vertical.fill", help: "Creates a void blending a base sketch into a top sketch.", keywords: ["family", "void", "cut"]),
        CommandInfo(.feVoidRevolve, "Void Revolve", .manage, "rotate.3d.fill", help: "Creates a void by revolving a sketch.", keywords: ["family", "void", "cut"]),
        CommandInfo(.feVoidSweep, "Void Sweep", .manage, "scribble.variable", help: "Creates a void by sweeping a profile along a path.", keywords: ["family", "void", "cut"]),
        CommandInfo(.feModelLine, "Model Line", .manage, "line.diagonal", help: "Draws lines that exist in 3D in the family.", keywords: ["family", "line"]),
        CommandInfo(.feComponent, "Component", .manage, "square.on.square", help: "Places a nested family in the family.", keywords: ["family", "nested", "place"]),
        CommandInfo(.feModelText, "Model Text", .manage, "textformat.size", help: "Places 3D text in the family.", keywords: ["family", "text", "3d"]),
        CommandInfo(.feOpening, "Opening", .manage, "rectangle.dashed", help: "Cuts an opening in the host of a hosted family.", keywords: ["family", "door", "window", "host", "cut"]),
        CommandInfo(.feControl, "Control", .manage, "arrow.left.arrow.right", help: "Adds flip arrows to the family.", keywords: ["family", "flip", "arrow"]),
        CommandInfo(.feReferenceLine, "Reference Line", .manage, "line.diagonal.arrow", help: "Draws a reference line to drive angles and rigs.", keywords: ["family", "datum"]),
        CommandInfo(.feReferencePlane, "Reference Plane", .manage, "squareshape.split.2x2.dotted", help: "Draws reference planes that the family's geometry locks to.", keywords: ["family", "datum"]),
        CommandInfo(.feDimension, "Aligned", .manage, "ruler", help: "Dimensions between parallel reference planes; label it with a parameter to make it flex.", keywords: ["family", "dimension", "label"]),
        CommandInfo(.feSymbolicLine, "Symbolic Line", .manage, "pencil.line", help: "Draws lines shown in plan instead of the family's geometry.", keywords: ["family", "plan", "symbol"]),
        CommandInfo(.feFamilyTypes, "Family Types", .manage, "tablecells", help: "Creates types, adds parameters and sets their values and formulas.", keywords: ["family", "parameters", "types"]),
        CommandInfo(.feFamilyCategory, "Family Category and Parameters", .manage, "list.bullet.rectangle", help: "Sets the family's category and its family parameters.", keywords: ["family", "category"]),
        CommandInfo(.feLoadIntoProject, "Load into Project", .manage, "square.and.arrow.up.on.square", help: "Loads the family into the project.", keywords: ["family", "load", "reload"]),
        CommandInfo(.feLoadAndClose, "Load into Project and Close", .manage, "square.and.arrow.up.on.square.fill", help: "Loads the family into the project and closes the family.", keywords: ["family", "load", "close"]),
        CommandInfo(.feFinishSketch, "Finish Edit Mode", .manage, "checkmark", help: "Finishes the sketch.", keywords: ["family", "sketch", "finish"]),
        CommandInfo(.feCancelSketch, "Cancel Edit Mode", .manage, "xmark", help: "Abandons the sketch.", keywords: ["family", "sketch", "cancel"]),
        CommandInfo(.feDefault3D, "Default 3D View", .manage, "cube.fill", help: "Opens the family's default 3D view, with orbit.", keywords: ["family", "3d", "orbit"]),
        CommandInfo(.feControlSingleVertical, "Single Vertical", .manage, "arrow.up", help: "Places a vertical flip control (flips the facing).", keywords: ["family", "control", "flip"]),
        CommandInfo(.feControlDoubleVertical, "Double Vertical", .manage, "arrow.up.arrow.down", help: "Places a double vertical flip control (flips the facing).", keywords: ["family", "control", "flip"]),
        CommandInfo(.feControlSingleHorizontal, "Single Horizontal", .manage, "arrow.right", help: "Places a horizontal flip control (flips the hand).", keywords: ["family", "control", "flip"]),
        CommandInfo(.feControlDoubleHorizontal, "Double Horizontal", .manage, "arrow.left.arrow.right", help: "Places a double horizontal flip control (flips the hand).", keywords: ["family", "control", "flip"]),
        CommandInfo(.feFilledRegion, "Filled Region", .manage, "square.fill.on.square", help: "Sketches a filled region shown with the family in plan.", keywords: ["family", "region", "fill"]),
        CommandInfo(.feMaskingRegion, "Masking Region", .manage, "square.on.square.dashed", help: "Sketches a masking region shown with the family in plan.", keywords: ["family", "region", "mask"]),
        CommandInfo(.feText, "Text", .manage, "textformat", help: "Places static text in the family's plan (labels show a parameter instead).", keywords: ["family", "text", "note"]),
        CommandInfo(.feWorkPlaneSet, "Set Work Plane", .manage, "square.grid.3x3.square", help: "Specifies the work plane of the current view: a named reference plane new forms, lines and text start from.", keywords: ["family", "work plane"]),
        CommandInfo(.feWorkPlaneShow, "Show Work Plane", .manage, "square.grid.3x3", help: "Shows or hides the work plane grid in the current view.", keywords: ["family", "work plane"]),
        CommandInfo(.feLoadNestedFamily, "Load Family into Family…", .manage, "square.and.arrow.down", help: "Loads a family file into this family, to place as a nested component or use as a sweep profile.", keywords: ["family", "nested", "load"]),
        CommandInfo(.fePurgeUnused, "Purge Unused Families", .manage, "trash.slash", help: "Removes families loaded into this family that no component or sweep uses.", keywords: ["family", "purge"]),
        CommandInfo(.feFlexTest, "Flex Test", .manage, "checkmark.seal", help: "Evaluates every type, and each length parameter at 50% and 150%, reporting geometry and constraint failures.", keywords: ["family", "flex", "check"]),
        CommandInfo(.feSaveFamilyAs, "Save Family As…", .manage, "square.and.arrow.down.on.square", help: "Saves the family as a .arcusfamily file.", keywords: ["family", "save", "file"]),
    ]
}
