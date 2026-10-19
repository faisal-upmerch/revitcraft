import AppKit
import ArcusGeometry
import ArcusDomain

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

    /// The preview of a Furniture document.
    static func image(_ m: BIMModel, width: Int, height: Int) -> CGImage? {
        guard m.isFurniture else { return nil }
        let f = FurnitureCompiler.family(from: m)
        let typeName = m.furnitureSetup.map(\.currentType).flatMap { f.type(named: $0)?.name } ?? f.types.first?.name ?? ""
        var ev = FamilyEvaluator.evaluate(f, typeName: typeName, units: .imperial)
        // Colours by material: a solid's material parameter (this type's value) or the material its nested family set.
        var colors: [String: RGBColor] = [:]
        ev.solids = ev.solids.filter { !$0.isVoid && $0.visibleIn3D && $0.visibleAt.contains(.medium) }.map { s in
            var s = s
            var id = s.resolvedMaterial
            if id == nil, let p = s.materialParameter, case .quantity(let raw, _)? = ev.values[p], raw >= 1 { id = ElementID(UInt64(raw)) }
            if let id, let mat = m[id]?.material {
                let key = "#\(id.raw)"
                colors[key] = mat.color
                s.materialParameter = key
            } else {
                s.materialParameter = nil
            }
            return s
        }
        guard !ev.solids.isEmpty, let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setShouldAntialias(true)
        LibraryThumbnailRenderer.drawShaded(ev, colors: colors, fallback: ElementMeshes.defaultColor(f.template.category), ctx, width: width, height: height)
        return ctx.makeImage()
    }
}
