import AppKit
import ArcusApplication

// Furniture mode's menu (Docs/FurnitureMode.md §3): the Create tab's parts, openings and forms, then fabrication.
// Its commands are greyed out in Architectural projects, with the reason in the tooltip, like other mode-only commands.

extension MainMenuBuilder {
    static func furnitureMenu() -> NSMenuItem {
        let voids = submenu("Void Forms", commands([.furnitureVoidExtrusion, .furnitureVoidBlend, .furnitureVoidRevolve, .furnitureVoidSweep, .furnitureVoidSweptBlend]))
        let forms = submenu("Forms", commands([.furnitureExtrusion, .furnitureBlend, .furnitureRevolve, .furnitureSweep, .furnitureSweptBlend, .furnitureCushion]) + [voids])
        let modify = submenu("Modify Parts", commands([.furnitureEditProfile, .furnitureResetProfile, .furnitureBlendEditTop, .furnitureBlendEditBase, .furniturePanelOpening, .furnitureAttach, .furnitureDetach, .furnitureFlipPanel]))
        return submenu("Furniture", commands([.furniturePanel, .furnitureShelf, .furnitureTop, .furnitureBack, .furnitureDivider, .furnitureLeg, .furnitureLegsAtCorners,
                                              .furnitureRail, .furnitureSlats, .furniturePlinth, .furnitureEdgeProfile, .furnitureGroove]) // FM4
                       + [forms, modify]
                       + furnitureMenuAdditions())
    }

    /// Openings, joints and fabrication items added by later milestones (FM5–FM7).
    static func furnitureMenuAdditions() -> [NSMenuItem] {
        let openings = submenu("Openings", commands([.furnitureBay, .furnitureBaySeparator, .furnitureBayDivide, .furnitureRemoveDivide, .furnitureBayTag, nil,
                                                      .furnitureDoor, .furnitureDrawer, .furnitureFlap, nil, .furnitureFlipHinge, .furniturePickNewHost, .furnitureSelectHardware])) // FM5
        return [openings] + commands([.furnitureHardware]) // FM5
            + [.separator()] + commands([.furnitureJoint, .furnitureJointRules, .furnitureAllowJoin, .furnitureDisallowJoin]) // FM6
            + [.separator()] + commands([.furniturePartList, .furnitureHardwareSchedule, .furnitureMaterialTakeoff, .furnitureEdgeBanding, .furnitureCost, nil,
                                         .furnitureNesting, .furnitureStockSheets, nil, .furnitureCNCExport, .furnitureShopDrawings, .furnitureExplodeParts, .furnitureCheckParts, .furnitureHardwareCatalog]) // FM7
    }
}
