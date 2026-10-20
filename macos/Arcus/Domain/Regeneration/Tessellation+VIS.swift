import Foundation
import ArcusGeometry

// VIS: the tessellation quality each view detail level draws curves at (Coarse simple, Medium smooth, Fine very smooth).
extension DetailLevel {
    public var tessellation: TessellationQuality {
        switch self {
        case .coarse: .coarse
        case .medium: .medium
        case .fine: .fine
        }
    }
}
