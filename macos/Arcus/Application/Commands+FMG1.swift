import Foundation

// FMG1: polish and Furniture mode gap batch.

extension CommandCatalog {
    static let fmg1Commands: [CommandInfo] = [
        CommandInfo(.furnitureBlendEditTop, "Edit Top", .modify, "square.stack.3d.up",
                    help: "Sketches the blend's top loop (its base is kept), or edits the selected blend's top.", keywords: ["furniture", "blend", "top", "form"]),
        CommandInfo(.furnitureBlendEditBase, "Edit Base", .modify, "square.stack.3d.down.forward",
                    help: "Sketches the blend's base loop (its top is kept), or edits the selected blend's base.", keywords: ["furniture", "blend", "base", "form"]),
    ]
}
