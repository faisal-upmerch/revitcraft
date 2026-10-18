import Foundation
import ArcusGeometry
import ArcusDomain

/// W2-DWG: survey points from CAD contour drawings, for Toposurface ▸ from Import.
///
/// Contour polylines (LWPOLYLINE elevation or 3D POLYLINE vertices), lines, points and 3D faces on the chosen layers of
/// model space give (x, y, z) points. The link's placement puts them where the drawing sits in the model.
public enum CADSitePoints {
    public struct LayerSummary: Sendable, Hashable {
        public var name: String
        /// Vertices on the layer.
        public var points: Int
        /// Distinct non-zero elevations found (a quick "does this layer carry heights" hint).
        public var elevations: Int
    }

    /// Vertices with their elevation, in drawing units, from model-space entities on `layers` (nil = all layers).
    public static func points(in doc: CADDocument, layers: Set<String>? = nil) -> [Vec3] {
        let wanted = layers.map { Set($0.map { $0.uppercased() }) }
        var out: [Vec3] = []
        for e in doc.modelSpace {
            if let w = wanted, !w.contains(e.props.layer.uppercased()) { continue }
            switch e {
            case .polyline(let p, _): out += p.points
            case .line(let a, let b, _): out += [a, b]
            case .point(let p, _): out.append(p)
            case .face3D(let pts, _): out += pts
            default: break
            }
        }
        return out.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
    }

    /// Layers with point-bearing geometry, those carrying elevations first.
    public static func layers(in doc: CADDocument) -> [LayerSummary] {
        var byLayer: [String: (Int, Set<Double>)] = [:]
        var names: [String: String] = [:]
        for e in doc.modelSpace {
            let pts = points(in: CADDocument(modelSpace: [e]))
            guard !pts.isEmpty else { continue }
            let k = e.props.layer.uppercased()
            names[k] = names[k] ?? e.props.layer
            var v = byLayer[k] ?? (0, [])
            v.0 += pts.count
            for p in pts where p.z != 0 && v.1.count < 1000 { v.1.insert(p.z) }
            byLayer[k] = v
        }
        return byLayer.map { LayerSummary(name: names[$0.key] ?? $0.key, points: $0.value.0, elevations: $0.value.1.count) }
            .sorted { ($0.elevations > 0 ? 0 : 1, $0.name) < ($1.elevations > 0 ? 0 : 1, $1.name) }
    }

    /// Maps drawing-unit points into model coordinates (meters) the way the link's content was placed.
    /// `metersPerUnit` is the drawing's unit scale; the local origin and placement come from the linked content.
    public static func modelPoints(_ pts: [Vec3], metersPerUnit s: Double, localOrigin: Vec2, placement: Transform2) -> [Vec3] {
        pts.map { p in Vec3(placement.apply(p.xy * s - localOrigin), z: p.z * s) }
    }

    /// Model points for a placed CAD link or import element, re-reading its source through `document`.
    public static func modelPoints(for link: LinkData, drawing: ReferenceDrawing?, document doc: CADDocument, layers: Set<String>?) -> [Vec3] {
        let meta = { (k: String) in drawing?.metadata[k].flatMap(Double.init) }
        let s = meta("cad.metersPerUnit") ?? (doc.units == .unitless ? CADUnits.millimeters.metersPerUnit : doc.units.metersPerUnit)
        let local = Vec2(meta("cad.localOriginX") ?? 0, meta("cad.localOriginY") ?? 0)
        return modelPoints(points(in: doc, layers: layers), metersPerUnit: s, localOrigin: local, placement: link.placement)
    }

    /// Reads a link's source (DXF, or DWG through the current DWG provider).
    public static func readSource(_ url: URL, isCancelled: @Sendable () -> Bool = { false }) throws -> CADDocument {
        try CADLinkService.readDocument(url: url, options: CADReadOptions(), progress: { _ in }, isCancelled: isCancelled).0
    }
}
