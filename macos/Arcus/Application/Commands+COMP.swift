import Foundation
import ArcusDomain

// COMP: the Furniture Component Library (Domain/Furniture/Components): the Components panel and browser, placing and
// replacing components, one-click hardware on fronts and bays, assembly presets, hardware rules, custom components and
// the component schedules.

extension CommandCatalog {
    static let compCommands: [CommandInfo] = [
        CommandInfo(.components, "Components", .insert, "square.grid.3x3.square",
                    help: "Shows or hides the Components panel: search the hardware and component library, preview, place and replace.",
                    keywords: ["component", "library", "hardware", "handle", "hinge", "slide", "browser", "panel", "search"]),
        CommandInfo(.componentBrowser, "Component Browser", .insert, "square.grid.3x3.topleft.filled",
                    help: "Opens the Component Library in its own window, at full size.",
                    keywords: ["component", "library", "browser", "window", "hardware"]),
        CommandInfo(.componentPlace, "Place Component", .build, "plus.square.on.square",
                    help: "Places the component selected in the Components panel on a door, drawer, panel, shelf or bay; it follows its host.",
                    keywords: ["component", "place", "insert", "hardware", "host"]),
        CommandInfo(.componentReplace, "Replace Component", .modify, "arrow.triangle.2.circlepath",
                    help: "Replaces the selected components with the one selected in the Components panel, keeping host, position and alignment.",
                    keywords: ["component", "replace", "swap", "hardware"]),
        CommandInfo(.componentAssembly, "Insert Assembly", .build, "square.stack.3d.up",
                    help: "Inserts a ready module into the selected bay: drawer stack, desk pedestal, wardrobe interior, pantry pull-out…",
                    keywords: ["assembly", "module", "preset", "drawer stack", "wardrobe", "pantry", "pedestal"]),
        CommandInfo(.componentHardwareRules, "Hardware Rules", .manage, "ruler",
                    help: "Sets how many hinges doors get by their height.",
                    keywords: ["hardware", "rules", "hinges", "count", "door height"]),
        CommandInfo(.componentSaveSelection, "Save Selection as Component", .file, "square.and.arrow.down.on.square",
                    help: "Saves the selected parts, fronts and hardware as a component in your library.",
                    keywords: ["component", "save", "selection", "custom", "library"]),
        CommandInfo(.componentBOM, "Component BOM", .view, "list.bullet.clipboard",
                    help: "Opens the Component BOM: every hardware line grouped by component category, with counts and cost.",
                    keywords: ["bom", "bill of materials", "hardware", "components", "cost", "quantity"]),
        CommandInfo(.componentPowerSummary, "Power Summary", .view, "bolt",
                    help: "Opens the Power Summary: the electronics by supply with their watts.",
                    keywords: ["power", "electrical", "led", "watts", "driver", "summary"]),
        CommandInfo(.componentUpdate, "Update Components", .manage, "arrow.down.circle",
                    help: "Reloads components whose library definition is newer, keeping the document's values.",
                    keywords: ["update", "upgrade", "reload", "components", "version"]),
        CommandInfo(.componentNewFamily, "New Component", .file, "plus.rectangle.on.folder",
                    help: "Starts a component of your own from the Furniture Hardware / Component template.",
                    keywords: ["component", "new", "template", "family", "custom", "hardware"]),
        CommandInfo(.componentAddHandle, "Add Handle", .build, "hand.point.up.left", help: "Adds a handle sized to each selected front.", keywords: ["handle", "pull", "knob", "one click"]),
        CommandInfo(.componentAddHinges, "Add Hinges", .build, "door.left.hand.open", help: "Adds hinges to the selected doors and flaps by their height and overlay.",
                    keywords: ["hinge", "hinges", "one click"]),
        CommandInfo(.componentAddLock, "Add Lock", .build, "lock", help: "Adds a lock to the selected fronts.", keywords: ["lock", "security", "one click"]),
        CommandInfo(.componentAddSoftClose, "Add Soft-Close", .build, "arrow.down.right.and.arrow.up.left", help: "Adds a soft-close damper to the selected fronts.",
                    keywords: ["soft close", "damper", "one click"]),
        CommandInfo(.componentAddPushToOpen, "Add Push-to-Open", .build, "hand.tap", help: "Adds a push-to-open latch to the selected fronts and takes their handles off.",
                    keywords: ["push to open", "touch latch", "handleless", "one click"]),
        CommandInfo(.componentAddSlides, "Add Slides", .build, "archivebox", help: "Adds drawer slides sized to the bay's depth.", keywords: ["slide", "runner", "drawer", "one click"]),
        CommandInfo(.componentAddOrganizer, "Add Organizer", .build, "square.grid.3x2", help: "Adds an organizer to the selected drawer or bay.",
                    keywords: ["organizer", "insert", "cutlery", "one click"]),
        CommandInfo(.componentAddHangingRod, "Add Hanging Rod", .build, "tshirt", help: "Adds a hanging rod across the selected bay.", keywords: ["rod", "wardrobe", "closet", "one click"]),
        CommandInfo(.componentAddShoeRack, "Add Shoe Rack", .build, "shoeprints.fill", help: "Adds a shoe rack to the selected bay.", keywords: ["shoe", "rack", "wardrobe", "one click"]),
        CommandInfo(.componentAddLighting, "Add Lighting", .build, "lightbulb", help: "Adds LED lighting to the selected bay, shelf or top.", keywords: ["led", "light", "lighting", "one click"]),
        CommandInfo(.componentAddSlidingSystem, "Add Sliding System", .build, "rectangle.split.2x1", help: "Adds a sliding door system to the selected bay.",
                    keywords: ["sliding", "door", "track", "wardrobe", "one click"]),
    ]

    /// COMP: the one-click hardware command of an action.
    public static func compCommand(_ a: ComponentAction) -> CommandID {
        switch a {
        case .handle: .componentAddHandle
        case .hinges: .componentAddHinges
        case .lock: .componentAddLock
        case .softClose: .componentAddSoftClose
        case .pushToOpen: .componentAddPushToOpen
        case .slides: .componentAddSlides
        case .organizer: .componentAddOrganizer
        case .hangingRod: .componentAddHangingRod
        case .shoeRack: .componentAddShoeRack
        case .lighting: .componentAddLighting
        case .slidingSystem: .componentAddSlidingSystem
        }
    }

    /// COMP: the action of a one-click hardware command.
    public static func compAction(_ id: CommandID) -> ComponentAction? { ComponentAction.allCases.first { compCommand($0) == id } }
}
