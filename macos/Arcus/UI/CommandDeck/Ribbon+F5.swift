import Foundation
import ArcusApplication

// F5: ribbon captions of the Analyze and Massing & Site tools, as RevitCraft's ribbon.rs labels them.
extension RibbonItem {
    static func f5Caption(_ id: CommandID, size: Size) -> String? {
        let large = size == .large
        switch id {
        case .spaceSeparator: return large ? "Space\nSeparator" : "Space Separator"
        case .spaceTag: return large ? "Tag\nSpace" : "Space Tag"
        case .showMass: return large ? "Show\nMass" : "Show Mass"
        case .inPlaceMass: return large ? "In-Place\nMass" : "In-Place Mass"
        case .curtainSystemByFace: return large ? "Curtain\nSystem" : "Curtain System"
        case .roofByFace: return "Roof"
        case .wallByFace: return "Wall"
        case .floorByFace: return "Floor"
        default: return nil
        }
    }
}
