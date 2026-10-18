import Foundation

// F810: View, sheets and presentation: hidden lines, cut profile, walkthrough, title blocks, windows, render. Docs/RevitCraftPort.md §5.

extension CommandCatalog {
    /// Titles, help and aliases from RevitCraft (crates/rc-app/src/commands.rs `Cmd::info`).
    static let f810Commands: [CommandInfo] = [
        // View ▸ Graphics
        CommandInfo(.showHiddenLines, "Show Hidden Lines", .view, "square.on.square.dashed", help: "Shows the lines of an element hidden by another element as dashed lines.", keywords: ["obscured", "dashed", "hidden lines"]),
        CommandInfo(.removeHiddenLines, "Remove Hidden Lines", .view, "square.on.square", help: "Stops showing the hidden lines of an element.", keywords: ["obscured", "dashed", "hidden lines"]),
        CommandInfo(.cutProfile, "Cut Profile", .view, "square.split.diagonal", help: "Changes the shape of a cut wall in this view only: pick the wall, then sketch the region to add or cut away.", keywords: ["poche", "cut shape", "view specific"]),
        // View ▸ Presentation
        CommandInfo(.render, "Render", .view, "camera.aperture", aliases: ["RR"], help: "Renders the 3D view: quality, resolution, sun lighting and sky; save the image to the project or export it.", keywords: ["rendering", "realistic", "image", "visualisation"]),
        CommandInfo(.renderGallery, "Render Gallery", .view, "photo.on.rectangle", help: "Shows the renderings saved in the project, to export as PNG images or delete.", keywords: ["renderings", "images"]),
        CommandInfo(.exportOBJ, "Export OBJ", .view, "cube.transparent", help: "Exports the model as OBJ with materials, for visualisation apps.", keywords: ["obj", "mtl", "mesh", "visualisation", "export"]),
        // View ▸ Create
        CommandInfo(.framingElevation, "Framing Elevation", .view, "building.columns", help: "Places an elevation beside a grid, looking at it and cropped to it: click near the grid on the side to look from.", keywords: ["grid elevation", "bracing elevation"]),
        CommandInfo(.calloutSketch, "Sketch", .view, "pencil.and.outline", help: "Sketches the boundary of a callout of any shape.", keywords: ["callout", "sketched callout", "detail"]),
        CommandInfo(.walkthrough, "Walkthrough", .view, "figure.walk", help: "Places a walkthrough in a plan: click the camera's path, then Finish Walkthrough.", keywords: ["animation", "path", "camera", "fly through"]),
        CommandInfo(.finishWalkthrough, "Finish Walkthrough", .view, "checkmark.circle", help: "Creates the walkthrough from the clicked path.", keywords: ["walkthrough"]),
        CommandInfo(.walkthroughPreviousFrame, "Previous Frame", .view, "backward.frame", help: "Shows the walkthrough's previous frame.", keywords: ["walkthrough"]),
        CommandInfo(.walkthroughNextFrame, "Next Frame", .view, "forward.frame", help: "Shows the walkthrough's next frame.", keywords: ["walkthrough"]),
        CommandInfo(.walkthroughPlay, "Play", .view, "play", help: "Plays the walkthrough from the current frame (again to stop).", keywords: ["walkthrough", "animation"]),
        CommandInfo(.walkthroughExport, "Export", .view, "film", help: "Exports the walkthrough's frames as PNG images, or as a QuickTime movie.", keywords: ["walkthrough", "frames", "png", "movie", "mov", "video"]),
        // View ▸ Sheet Composition
        CommandInfo(.titleBlock, "Title Block", .view, "doc.richtext", help: "Changes the title block of the sheet.", keywords: ["sheet size", "border"]),
        CommandInfo(.guideGrid, "Guide Grid", .view, "grid", help: "Shows a guide grid on the sheet; viewports snap to it.", keywords: ["sheet grid", "align viewports"]),
        CommandInfo(.matchline, "Matchline", .view, "line.diagonal", help: "Draws a matchline where a plan continues on another sheet.", keywords: ["match line", "continuation"]),
        // View ▸ Windows
        CommandInfo(.switchWindows, "Switch Windows", .view, "macwindow.on.rectangle", help: "Switches to another open view.", keywords: ["open views", "window"]),
        CommandInfo(.tabViews, "Tab Views", .view, "rectangle.stack", aliases: ["TW"], help: "Arranges open views as tabs.", keywords: ["tabs", "windows"]),
        CommandInfo(.tileViews, "Tile Views", .view, "square.grid.2x2", aliases: ["WT"], help: "Tiles open views side by side.", keywords: ["tile", "split", "windows"]),
        CommandInfo(.canvasTheme, "Canvas Theme", .view, "circle.lefthalf.filled", help: "Switches the view canvas between the light, dark and black theme.", keywords: ["dark canvas", "black background", "theme"]),
        // Navigation bar
        CommandInfo(.navigationWheel, "Navigation Wheel", .view, "steeringwheel", help: "The 2D Wheel (Zoom, Pan, Rewind) of plans, sections and sheets, or the Full Navigation Wheel of 3D views: press a wedge and drag. Esc closes it.", keywords: ["steering wheel", "zoom", "pan", "orbit", "rewind", "look", "walk"]),
    ]
}
