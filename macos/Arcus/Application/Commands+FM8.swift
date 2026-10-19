import Foundation

// FM8: Furniture mode / Home / Family Editor shell batch (Docs/FurnitureMode.md §6).
// Projects load Furniture documents as families (Insert ▸ Load Furniture, and Load Family accepts .arcusfurniture);
// Furniture documents save themselves as templates for Home ▸ Furniture and Load Furniture. Edit Family on a loaded
// piece reopens it in Furniture mode (the existing Edit Family command). No default shortcuts, as in Revit.

extension CommandCatalog {
    static let fm8Commands: [CommandInfo] = [
        CommandInfo(.loadFurniture, "Load Furniture…", .insert, "chair.lounge",
                    help: "Shows the Furniture Library (bundled pieces and your furniture templates) to load a piece as a family and place it.",
                    keywords: ["furniture", "library", "load", "place", "casework", "cabinet", "template"]),
        CommandInfo(.saveAsFurnitureTemplate, "Save as Furniture Template…", .file, "square.and.arrow.down.on.square",
                    help: "Saves this piece with a preview in your Furniture Templates, under a room, so it appears on Home ▸ Furniture and in Load Furniture.",
                    keywords: ["furniture", "template", "library", "save", "room"]),
    ]
}
