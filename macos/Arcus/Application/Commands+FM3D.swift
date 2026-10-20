import Foundation

// FM3D: Furniture design in 3D views.

extension CommandCatalog {
    static let fm3dCommands: [CommandInfo] = [
        CommandInfo(.furniture3DDesign, "3D Design", .view, "cube.transparent",
                    help: "Opens the piece's 3D design view: an orbit-friendly camera with the work plane shown. Every Furniture tool draws in 3D on the work plane.",
                    keywords: ["furniture", "3d", "design", "work plane", "orbit", "model in 3d"]),
        CommandInfo(.furnitureEditSketch, "Edit Sketch", .modify, "pencil.and.outline",
                    help: "Edits the sketch of the selected extrusion or void extrusion on its own work plane, in a plan, an elevation or 3D.",
                    keywords: ["furniture", "extrusion", "edit extrusion", "profile", "sketch", "form"]),
    ]
}
