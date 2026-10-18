import Foundation

// F34: Structure and reinforcement: truss, brace, beam system, structural settings, rebar, area/path/fabric reinforcement. Docs/RevitCraftPort.md §5.

extension CommandCatalog {
    /// Titles, help and aliases from RevitCraft (crates/rc-app/src/commands.rs `Cmd::info`).
    static let f34Commands: [CommandInfo] = [
        // Structure ▸ Structure
        CommandInfo(.truss, "Truss", .structure, "triangle", help: "Places a flat truss of chords and diagonal members between two points.", keywords: ["warren", "chord", "web", "framing"]),
        CommandInfo(.brace, "Brace", .structure, "line.diagonal", aliases: ["BR"], help: "Adds diagonal braces from the current level up to the level above.", keywords: ["bracing", "framing", "diagonal"]),
        CommandInfo(.beamSystem, "Beam System", .structure, "line.3.horizontal", aliases: ["BS"], help: "Sketches a bay and fills it with parallel beams at a fixed spacing.", keywords: ["joists", "framing", "bay"]),
        // Structure ▸ Reinforcement
        CommandInfo(.rebar, "Rebar", .structure, "line.3.horizontal.decrease", aliases: ["RB"], help: "Places a set of straight bars in a floor or slab at its bottom cover: click the bar's start and end.", keywords: ["reinforcement", "bar", "steel"]),
        CommandInfo(.areaReinforcement, "Area", .structure, "square.grid.3x3", help: "Reinforces a sketched area of a floor or slab with top and bottom bar layers both ways.", keywords: ["area reinforcement", "rebar", "mesh"]),
        CommandInfo(.pathReinforcement, "Path", .structure, "point.topleft.down.to.point.bottomright.curvepath", help: "Places bars along a sketched path in a floor or slab, each running into it at the path's spacing.", keywords: ["path reinforcement", "rebar", "edge"]),
        CommandInfo(.fabricArea, "Fabric Area", .structure, "squareshape.split.3x3", help: "Lays welded wire fabric sheets over a sketched area of a floor or slab, lapped at their edges.", keywords: ["mesh", "welded wire", "reinforcement"]),
        CommandInfo(.fabricSheet, "Fabric Sheet", .structure, "rectangle.split.3x3", help: "Places a single welded wire fabric sheet in a floor or slab.", keywords: ["mesh", "welded wire", "reinforcement"]),
        CommandInfo(.rebarCover, "Cover", .structure, "square.dashed", help: "Rebar Cover Settings: the concrete cover to the bars.", keywords: ["rebar cover", "concrete cover"]),
        CommandInfo(.rebarCoupler, "Rebar Coupler", .structure, "link", help: "Places couplers on the ends of a rebar set's bars, or between two sets that meet end to end.", keywords: ["splice", "mechanical"]),
        CommandInfo(.couplerOnBarEnd, "Place on Bar End", .structure, "link.circle", help: "Places couplers on the end of the bars you pick.", keywords: ["rebar coupler"]),
        CommandInfo(.couplerBetweenBars, "Place between Two Bars", .structure, "link.badge.plus", help: "Places couplers where two rebar sets meet end to end.", keywords: ["rebar coupler"]),
        // Manage ▸ Settings
        CommandInfo(.structuralSettings, "Structural Settings", .manage, "gearshape.2", help: "Symbolic cutbacks, brace symbols, load cases and load combinations.", keywords: ["cutback", "load case", "load combination"]),
        // Annotate ▸ Symbol and Tag
        CommandInfo(.beamSymbol, "Beam", .annotate, "arrow.left.and.right", help: "Places a beam system symbol on a beam: a span arrow with its type.", keywords: ["beam system symbol", "span"]),
        CommandInfo(.areaReinforcementSymbol, "Area", .annotate, "arrow.left.and.right.square", help: "Places an area reinforcement symbol and tag on an area reinforcement.", keywords: ["area reinforcement symbol", "rebar tag"]),
        CommandInfo(.pathReinforcementSymbol, "Path", .annotate, "arrow.up.to.line", help: "Places a path reinforcement symbol and tag on a path reinforcement.", keywords: ["path reinforcement symbol", "rebar tag"]),
        CommandInfo(.rebarSymbol, "Rebar", .annotate, "ruler", help: "Places a rebar symbol across a rebar set with its quantity, size and spacing.", keywords: ["rebar tag", "bar"]),
        CommandInfo(.fabricSymbol, "Fabric", .annotate, "rectangle.split.3x3", help: "Places a fabric reinforcement symbol on a fabric area or sheet.", keywords: ["fabric reinforcement symbol", "mesh"]),
        CommandInfo(.multiRebarAligned, "Aligned Multi-Rebar Annotation", .annotate, "ruler", help: "Dimensions the bars of a rebar set across the set, with its tag.", keywords: ["multi-rebar", "rebar dimension"]),
        CommandInfo(.multiRebarLinear, "Linear Multi-Rebar Annotation", .annotate, "ruler.fill", help: "Dimensions the bars of a rebar set horizontally or vertically, with its tag.", keywords: ["multi-rebar", "rebar dimension"]),
    ]
}
