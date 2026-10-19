import Foundation

// FM6: Furniture joints (Docs/FurnitureMode.md §3 "Joints"). Joint works as Wall Joins does: markers at every joint,
// pick one, then choose its type or cycle it with Previous/Next. Joint Rules sets the joint each pair kind gets, as
// a settings dialog. Allow and Disallow Join work on part ends as they do on wall ends.

extension CommandCatalog {
    static let fm6Commands: [CommandInfo] = [
        CommandInfo(.furnitureJoint, "Joint", .modify, "rectangle.split.2x2", aliases: ["JT"],
                    help: "Shows a marker at every joint; pick one to set its type (butt, miter, dado, dowel, cam lock…), which part runs through, and its sizes.",
                    keywords: ["furniture", "joint", "wall joins", "butt", "miter", "dado", "rabbet", "dowel", "cam", "pocket", "mortise", "tenon"]),
        CommandInfo(.furnitureJointRules, "Joint Rules", .manage, "tablecells.badge.ellipsis",
                    help: "Sets the joint each kind of pair gets (side–top, shelf–side, rail–leg…) and its sizes.",
                    keywords: ["furniture", "joint", "rules", "settings", "defaults"]),
        CommandInfo(.furnitureAllowJoin, "Allow Join", .modify, "link",
                    help: "Lets the selected parts join at their ends again.", keywords: ["furniture", "joint", "allow"]),
        CommandInfo(.furnitureDisallowJoin, "Disallow Join", .modify, "link.badge.plus",
                    help: "Stops the selected parts joining at their ends: they stay as drawn.", keywords: ["furniture", "joint", "disallow", "unjoin"]),
    ]
}
