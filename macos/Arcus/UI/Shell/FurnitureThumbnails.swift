import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusOutput

// FM8: previews of Furniture documents: a shaded three-quarter view from the front left (the Component Library's
// renderer) of the piece as it loads into a project, at Medium detail (fronts and hardware, no machining), in its
// materials' colours on a transparent background. `.arcusfurniture` packages save it as their thumbnail, so Home's
// Recent grid, Home ▸ Furniture and Load Furniture show it.

nonisolated enum FurnitureThumbnail {
    /// The preview of a Furniture document as PNG data, or nil when it has nothing to show.
    static func png(_ m: BIMModel, width: Int = 512, height: Int = 384) -> Data? {
        guard let image = image(m, width: width, height: height) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// The preview of a Furniture document (FM9: of a type, from a view direction, at a detail level; drawn by
    /// ArcusOutput's FurniturePreview, as arcus-bench draws the library's thumbnails).
    static func image(_ m: BIMModel, width: Int, height: Int, type: String? = nil, yaw: Double = ShadedFamilyRenderer.yaw,
                      pitch: Double = ShadedFamilyRenderer.pitch, detail: DetailLevel = .medium) -> CGImage? {
        FurniturePreview.image(m, width: width, height: height, type: type, yaw: yaw, pitch: pitch, detail: detail)
    }
}
