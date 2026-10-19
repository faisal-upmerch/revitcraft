import Foundation

// FM5: Furniture mode openings and hardware (Docs/FurnitureMode.md §2): Bay ~ Room (BY), Bay Separator ~ Room Separator,
// Bay Divide ~ Curtain Grid, Door/Drawer/Flap ~ Door (DF, DW, FP: FL is Floor), Hardware ~ Component (HW), and the
// Modify | Doors tools (Flip Hinge ~ Flip Hand, Pick New Host as for doors).

extension CommandCatalog {
    static let fm5Commands: [CommandInfo] = [
        CommandInfo(.furnitureBay, "Bay", .build, "rectangle.dashed", aliases: ["BY"],
                    help: "Places a bay like a room: click inside a region bounded by parts in the Front elevation (or a box in plan, for a top-access bay). It follows the parts as they move.",
                    keywords: ["furniture", "bay", "opening", "room", "carcass"]),
        CommandInfo(.furnitureBaySeparator, "Bay Separator", .build, "line.diagonal", aliases: ["BYS"],
                    help: "Draws lines that bound bays without a part, as Room Separator.", keywords: ["furniture", "bay", "separator", "boundary"]),
        CommandInfo(.furnitureBayDivide, "Bay Divide", .build, "rectangle.split.1x2", aliases: ["BD"],
                    help: "Splits a bay into equal (EQ) or sized rows or columns, as a curtain grid: each cell takes its own door or drawer.",
                    keywords: ["furniture", "bay", "divide", "grid", "drawers", "split"]),
        CommandInfo(.furnitureRemoveDivide, "Remove Bay Divide", .modify, "rectangle",
                    help: "Removes the selected bays' divisions (and the fronts of their cells).", keywords: ["furniture", "bay", "divide"]),
        CommandInfo(.furnitureBayTag, "Bay Tag", .annotate, "tag.square",
                    help: "Tags a bay with its name and clear opening, as Room Tag.", keywords: ["furniture", "bay", "tag", "opening"]),
        CommandInfo(.furnitureDoor, "Door", .build, "door.left.hand.closed", aliases: ["DF"],
                    help: "Places a cabinet front that hinges in a bay: full or half overlay, or inset; single or pair. Space flips the hinge side.",
                    keywords: ["furniture", "front", "cabinet", "hinge", "leaf"]),
        CommandInfo(.furnitureDrawer, "Drawer", .build, "archivebox", aliases: ["DW"],
                    help: "Places drawers in a bay: the front, its box and slides sized from the bay. Number stacks that many drawers (EQ).",
                    keywords: ["furniture", "drawer", "front", "slide", "box"]),
        CommandInfo(.furnitureFlap, "Flap", .build, "rectangle.portrait.topthird.inset.filled", aliases: ["FP"],
                    help: "Places a lift-up or drop-down flap in a bay (in plan: a lid on a top-access bay), with its hinges and stays.",
                    keywords: ["furniture", "flap", "lid", "lift-up", "drop-down", "fall front"]),
        CommandInfo(.furnitureHardware, "Hardware", .build, "gearshape.2", aliases: ["HW"],
                    help: "Places a hardware type (hinge, slide, handle, glide, caster, pin, connector) as a component. Doors and drawers place their own.",
                    keywords: ["furniture", "hardware", "handle", "knob", "hinge", "glide", "caster", "component"]),
        CommandInfo(.furnitureFlipHinge, "Flip Hinge", .modify, "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    help: "Flips the selected doors to hinge on the other side (Space does the same).", keywords: ["furniture", "door", "hinge", "flip", "hand"]),
        CommandInfo(.furniturePickNewHost, "Pick New Host", .modify, "arrow.right.square",
                    help: "Moves the selected front to another bay: click the bay.", keywords: ["furniture", "door", "drawer", "host", "bay"]),
        CommandInfo(.furnitureSelectHardware, "Select Hardware", .modify, "gearshape",
                    help: "Selects the hardware of the selected fronts.", keywords: ["furniture", "hardware", "select"]),
    ]
}
