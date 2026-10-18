import Foundation

// BL-VG: Manage ▸ Additional Settings ▸ Temporary Dimensions.

/// What temporary dimensions of walls measure from (a per-user preference, like the other drawing settings).
public enum TemporaryDimensionSettings {
    public enum WallReference: String, CaseIterable, Sendable { case centerlines = "Centerlines", faces = "Faces" }
    static let key = "temporaryDimensions.walls"

    public static var walls: WallReference {
        get { UserDefaults.standard.string(forKey: key).flatMap(WallReference.init(rawValue:)) ?? .faces }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
