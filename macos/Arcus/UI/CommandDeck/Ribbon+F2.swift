import SwiftUI
import ArcusDomain
import ArcusApplication

// F2: ribbon captions and contextual panels of Architecture B (RevitCraft ribbon.rs: work_plane_panel, the stair,
// roof and structural column contextual panels, the Grid tool's Draw panel).

extension RibbonItem {
    /// RevitCraft's short ribbon captions for F2 commands.
    static func f2Caption(_ id: CommandID, size: Size, split: Bool) -> String? {
        switch id {
        case .workPlaneSet: return "Set"
        case .workPlaneShow: return "Show"
        case .workPlaneViewer: return "Viewer"
        case .gridMultiSegment: return size == .large ? "Multi-\nSegment" : "Multi-Segment"
        case .connectLevels: return size == .large ? "Connect\nLevels" : "Connect Levels"
        case .alignEaves: return size == .large ? "Align\nEaves" : "Align Eaves"
        case .verticalColumn: return size == .large ? "Vertical\nColumn" : "Vertical Column"
        case .slantedColumn: return size == .large ? "Slanted\nColumn" : "Slanted Column"
        case .columnsAtGrids: return size == .large ? "At\nGrids" : "At Grids"
        case .columnsAtColumns: return size == .large ? "At\nColumns" : "At Columns"
        case .multipleFinish: return "Finish"
        case .multipleCancel: return "Cancel"
        default: return nil
        }
    }
}
