import Foundation

// FMG2: polish and Furniture mode gap batch.

extension CommandCatalog {
    static let fmg2Commands: [CommandInfo] = [
        CommandInfo(.furnitureExplodeParts, "Explode Parts", .view, "square.3.layers.3d.down.right",
                    help: "Draws the active 3D view with the parts moved apart along their joints, tagged, at a distance you set (shop drawing F104 uses it).",
                    keywords: ["furniture", "explode", "exploded view", "assembly", "displace", "3d", "parts"]),
    ]
}
