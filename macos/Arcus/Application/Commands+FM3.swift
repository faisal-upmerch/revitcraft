import Foundation

// FM3: Furniture mode / Home / Family Editor shell batch (Docs/FurnitureMode.md §6).
// Furniture documents: Family Types, Family Category and Parameters, Flex and Load into Project, as in the Family
// Editor (no default shortcuts, as in Revit-style tools), and File ▸ New ▸ Furniture.

extension CommandCatalog {
    static let fm3Commands: [CommandInfo] = [
        CommandInfo(.furnitureFamilyTypes, "Family Types", .manage, "tablecells",
                    help: "Creates types, adds parameters and sets their values and formulas for this piece.", keywords: ["furniture", "parameters", "types", "width", "depth", "height"]),
        CommandInfo(.furnitureCategory, "Family Category and Parameters", .manage, "list.bullet.rectangle",
                    help: "Sets the piece's category (Furniture or Casework) and its identity data.", keywords: ["furniture", "casework", "category"]),
        CommandInfo(.furnitureFlex, "Flex", .manage, "checkmark.seal",
                    help: "Tries every type, and each length parameter at 50% and 150%, and reports what breaks.", keywords: ["furniture", "flex", "test", "check"]),
        CommandInfo(.furnitureLoadIntoProject, "Load into Project", .manage, "square.and.arrow.up.on.square",
                    help: "Loads this piece into an open project as a family (reloads it when it is already there).", keywords: ["furniture", "family", "load", "reload"]),
        CommandInfo(.furnitureLoadAndClose, "Load into Project and Close", .manage, "square.and.arrow.up.on.square.fill",
                    help: "Loads this piece into an open project, then closes it.", keywords: ["furniture", "family", "load", "close"]),
        CommandInfo(.newFurniture, "New Furniture…", .file, "chair.lounge",
                    help: "Creates a Furniture document: a custom piece with parameters, cut lists and shop drawings.", keywords: ["new", "furniture", "casework", "millwork", "cabinet"]),
    ]
}
