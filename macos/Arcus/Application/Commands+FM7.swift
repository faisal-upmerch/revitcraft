import Foundation

// FM7: Furniture fabrication outputs (Docs/FurnitureMode.md §3 "Fabrication outputs"). The schedules are ordinary
// schedule views opened from the Fabricate tab (made when missing); Stock Sheets and Hardware Catalog are settings
// dialogs; Nesting makes the Nesting views; CNC Export writes DXF/DWG programs; Check Parts lists what would go wrong
// in the shop; Shop Drawings tags the parts and arranges sheets F101–F104.

extension CommandCatalog {
    static let fm7Commands: [CommandInfo] = [
        CommandInfo(.furniturePartList, "Part List", .view, "list.bullet.rectangle.portrait",
                    help: "Opens the Part List: every part and drawer box piece at its cut size, grouped by material and thickness, with edge banding and cost.",
                    keywords: ["furniture", "cut list", "part list", "panel schedule", "cutting list", "schedule"]),
        CommandInfo(.furnitureHardwareSchedule, "Hardware Schedule", .view, "wrench.and.screwdriver",
                    help: "Opens the Hardware Schedule: hinges, slides, handles and the joints' dowels, cams and screws, with count and cost.",
                    keywords: ["furniture", "hardware", "schedule", "hinges", "slides", "cost"]),
        CommandInfo(.furnitureMaterialTakeoff, "Material Takeoff", .view, "square.stack.3d.down.right",
                    help: "Opens the Material Takeoff with cost: area, volume, cost and sheets needed by material.",
                    keywords: ["furniture", "material", "takeoff", "cost", "sheets"]),
        CommandInfo(.furnitureEdgeBanding, "Edge Banding", .view, "rectangle.dashed",
                    help: "Opens the Edge Banding takeoff: linear feet and cost by banding material.",
                    keywords: ["furniture", "edge banding", "takeoff", "linear feet"]),
        CommandInfo(.furnitureCost, "Cost", .view, "dollarsign.circle",
                    help: "Opens the Cost schedule: materials, banding, hardware, labor and markup, totalled as the piece cost.",
                    keywords: ["furniture", "cost", "price", "estimate", "labor", "markup"]),
        CommandInfo(.furnitureStockSheets, "Stock Sheets", .manage, "rectangle.split.3x3",
                    help: "Sets the sheet sizes parts are nested on (per material and thickness), the kerf, edge trim, grain and rotation.",
                    keywords: ["furniture", "stock", "sheet", "4x8", "kerf", "trim", "nesting"]),
        CommandInfo(.furnitureHardwareCatalog, "Hardware Catalog", .manage, "books.vertical",
                    help: "Lists every hardware type with its cost, manufacturer and model for editing.",
                    keywords: ["furniture", "hardware", "catalog", "cost", "manufacturer"]),
        CommandInfo(.furnitureNesting, "Nesting", .view, "square.grid.3x3.square",
                    help: "Lays the sheet parts out on stock sheets, one Nesting view per material and thickness, with grain and yield.",
                    keywords: ["furniture", "nesting", "nest", "sheet", "yield", "optimize", "layout"]),
        CommandInfo(.furnitureCNCExport, "CNC Export", .file, "cpu",
                    help: "Writes DXF or DWG programs per part or per nested sheet (outline, drilling, grooves, pockets, grain, labels) and a CSV part list.",
                    keywords: ["furniture", "cnc", "dxf", "dwg", "router", "export", "cam"]),
        CommandInfo(.furnitureCheckParts, "Check Parts", .manage, "checkmark.seal",
                    help: "Checks the parts before cutting: too thin for their hardware, larger than the stock, missing materials, overlapping without a joint, edges that show unbanded.",
                    keywords: ["furniture", "check", "warnings", "validate", "parts"]),
        CommandInfo(.furnitureShopDrawings, "Shop Drawings", .view, "doc.richtext",
                    help: "Tags the parts, makes the Nesting views and arranges sheets F101–F104 at scales that fit.",
                    keywords: ["furniture", "shop drawings", "sheets", "tags", "set"]),
    ]
}
