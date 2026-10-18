import Foundation

// F1: Architecture A: Model Text, Wall: Reveal, openings, Place Model Group, spline and ellipse modes. Docs/RevitCraftPort.md §5.

extension CommandCatalog {
    /// Titles and help follow RevitCraft (`crates/rc-app/src/commands.rs` `Cmd::info`); none of these has an alias there.
    static let f1Commands: [CommandInfo] = [
        CommandInfo(.modelText, "Model Text", .build, "textformat", help: "Places three-dimensional text in the model.", keywords: ["3d text", "sign", "lettering"]),
        CommandInfo(.wallReveal, "Wall: Reveal", .build, "rectangle.compress.vertical",
                    help: "Cuts a reveal into a wall face: click the face in a 3D, elevation or section view.", keywords: ["groove", "reveal", "recess", "joint"]),
        CommandInfo(.faceOpening, "By Face", .build, "square.dashed",
                    help: "Cuts an opening perpendicular to the selected face of a roof, floor or ceiling.", keywords: ["opening", "hole", "skylight", "face opening"]),
        CommandInfo(.verticalOpening, "Vertical Opening", .build, "square.dashed.inset.filled",
                    help: "Cuts a vertical opening through a roof, floor or ceiling.", keywords: ["opening", "hole", "vertical"]),
        CommandInfo(.dormerOpening, "Dormer Opening", .build, "house.lodge",
                    help: "Cuts a roof where a dormer meets it: pick the roof, then the dormer's walls and edges.", keywords: ["dormer", "opening", "roof"]),
        CommandInfo(.placeModelGroup, "Place Model Group", .build, "square.on.square",
                    help: "Places an instance of a model group.", keywords: ["group", "model group", "repeat"]),
        CommandInfo(.highlightBoundaries, "Highlight Boundaries", .build, "highlighter",
                    help: "Highlights the room-bounding elements of the level.", keywords: ["room bounding", "boundary", "rooms"]),
    ]
}
