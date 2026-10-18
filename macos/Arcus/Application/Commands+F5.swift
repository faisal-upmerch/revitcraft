import Foundation

// F5: Analyze and Massing: spaces and zones, masses, model by face, model in-place. Docs/RevitCraftPort.md §5.

extension CommandCatalog {
    /// Titles and help from RevitCraft `Cmd::info` (crates/rc-app/src/commands.rs). The Model by Face tools are titled
    /// "… by Face" so menus and command search tell them from Wall, Roof and Floor; the ribbon captions them as
    /// RevitCraft does (Wall, Roof, Floor, Curtain System).
    static let f5Commands: [CommandInfo] = [
        CommandInfo(.space, "Space", .build, "square.dashed", help: "Places a space in a region bounded by walls or space separators.",
                    keywords: ["spaces", "zones", "analyze", "mep", "energy"]),
        CommandInfo(.spaceSeparator, "Space Separator", .build, "line.diagonal", help: "Draws lines that bound spaces where there are no walls.",
                    keywords: ["spaces", "zones", "analyze", "separation line"]),
        CommandInfo(.spaceTag, "Space Tag", .annotate, "tag", help: "Tags a space with its name and number.", keywords: ["spaces", "tag space"]),
        CommandInfo(.showMass, "Show Mass", .build, "cube.transparent", help: "Shows or hides conceptual masses in every view.",
                    keywords: ["mass", "massing", "conceptual"]),
        CommandInfo(.inPlaceMass, "In-Place Mass", .build, "cube", help: "Sketches the footprint of a conceptual mass and extrudes it to a height.",
                    keywords: ["mass", "massing", "conceptual", "blend"]),
        CommandInfo(.curtainSystemByFace, "Curtain System by Face", .build, "square.grid.3x3", help: "Creates curtain walls on the vertical faces of the selected mass.",
                    keywords: ["model by face", "mass", "curtain"]),
        CommandInfo(.roofByFace, "Roof by Face", .build, "house.lodge", help: "Creates a roof on the top face of the selected mass.",
                    keywords: ["model by face", "mass"]),
        CommandInfo(.wallByFace, "Wall by Face", .build, "rectangle.portrait", help: "Creates walls on the vertical faces of the selected mass.",
                    keywords: ["model by face", "mass"]),
        CommandInfo(.floorByFace, "Floor by Face", .build, "square.stack.3d.up", help: "Creates floors where levels cut the selected mass (mass floors).",
                    keywords: ["model by face", "mass", "mass floors"]),
        CommandInfo(.modelInPlace, "Model In-place", .build, "hammer", help: "Creates an in-place family: unique geometry modelled in the context of the project.",
                    keywords: ["in-place family", "in place", "component"]),
    ]
}
