import Foundation
import ArcusGeometry

// F67: 3D representation of linked models, point clouds and decals, and the conversion of another model into
// linked display content.

public enum LinkedGeometry {
    /// Points drawn in 3D per point cloud (the stored points are thinned evenly beyond this).
    public static let maxPoints3D = 60_000
    /// Size of a point marker in 3D (meters).
    public static let pointSize = 0.025
    /// Decals sit this far off their face so they never fight with it in depth.
    public static let decalLift = 0.003

    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        switch e.data {
        case .linkedModel(let l):
            guard l.isLoaded else { return [] }
            let t = l.transform
            return l.parts.map { p in
                var part = MeshPart(mesh: p.mesh.mesh.transformed(t), materialID: nil)
                part.color = p.color
                return part
            }
        case .pointCloud(let pc):
            guard pc.isLoaded else { return [] }
            return pointParts(pc, color: pc.hasColor ? nil : ElementMeshes.defaultColor(.pointClouds))
        case .decal(let d):
            return decalParts(d, type: model[d.decalTypeID]?.decalType)
        default:
            return []
        }
    }

    // MARK: Point clouds

    /// Small tetrahedra at the points, one part per colour bucket (4 levels per channel).
    static func pointParts(_ pc: PointCloudData, color fixed: RGBColor?) -> [MeshPart] {
        let pts = pc.points.points
        guard !pts.isEmpty else { return [] }
        let step = max(1, (pts.count + maxPoints3D - 1) / maxPoints3D)
        let t = pc.transform
        let s = pointSize
        let offsets = [Vec3(0, 0, s), Vec3(-s * 0.94, -s * 0.54, -s / 3), Vec3(s * 0.94, -s * 0.54, -s / 3), Vec3(0, s * 1.09, -s / 3)]
        var buckets: [Int: Mesh] = [:]
        func bucket(_ c: RGBColor) -> Int {
            func q(_ v: Double) -> Int { min(3, max(0, Int(v * 4))) }
            return q(c.r) * 16 + q(c.g) * 4 + q(c.b)
        }
        var i = 0
        while i < pts.count {
            let (p, c) = pts[i]
            i += step
            let w = t.apply(p)
            let k = fixed == nil ? bucket(c) : 0
            var m = buckets[k] ?? Mesh()
            let base = UInt32(m.positions.count)
            for o in offsets { m.positions.append(w + o); m.normals.append(o.normalized) }
            m.indices += [0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3].map { base + $0 }
            buckets[k] = m
        }
        return buckets.keys.sorted().map { k in
            var part = MeshPart(mesh: buckets[k]!, materialID: nil)
            if let fixed { part.color = fixed } else {
                let v = { (x: Int) in (Double(x) + 0.5) / 4 }
                part.color = RGBColor(v(k / 16), v((k / 4) % 4), v(k % 4))
            }
            return part
        }
    }

    // MARK: Decals

    /// A frame with a cross (all styles except Realistic) and the image as a grid of coloured cells (Realistic).
    static func decalParts(_ d: DecalData, type: DecalTypeData?) -> [MeshPart] {
        let c = d.corners(lift: decalLift)
        let n = d.normal.normalized
        var frame = Mesh()
        frame.addConvexFace(c, normal: n, edges: true)
        let base = UInt32(frame.positions.count - 4)
        frame.featureEdges += [base, base + 2, base + 1, base + 3]
        var framePart = MeshPart(mesh: frame, materialID: nil)
        framePart.color = RGBColor(0.55, 0.6, 0.7, 0.35)
        framePart.styles = .exceptRealistic
        var parts = [framePart]
        guard let type, let sw = type.swatch, sw.columns > 0, sw.rows > 0 else {
            var plain = framePart
            plain.styles = .realisticOnly
            return parts + [plain]
        }
        let r = d.right * d.width, u = d.up.normalized * d.height
        let origin = c[0]
        var buckets: [Int: (Mesh, RGBColor)] = [:]
        let opacity = max(0.05, 1 - type.transparency)
        for row in 0..<sw.rows {
            for col in 0..<sw.columns {
                let (rgb, alpha) = sw.color(col, row)
                if type.cutout && alpha < 0.5 { continue }
                let lit = RGBColor(min(1, rgb.r * type.brightness), min(1, rgb.g * type.brightness), min(1, rgb.b * type.brightness))
                func q(_ v: Double) -> Int { min(7, max(0, Int(v * 8))) }
                let k = q(lit.r) * 64 + q(lit.g) * 8 + q(lit.b)
                let x0 = Double(col) / Double(sw.columns), x1 = Double(col + 1) / Double(sw.columns)
                let y0 = Double(row) / Double(sw.rows), y1 = Double(row + 1) / Double(sw.rows)
                let quad = [origin + r * x0 + u * y0, origin + r * x1 + u * y0, origin + r * x1 + u * y1, origin + r * x0 + u * y1]
                var entry = buckets[k] ?? (Mesh(), RGBColor((Double(k / 64) + 0.5) / 8, (Double((k / 8) % 8) + 0.5) / 8, (Double(k % 8) + 0.5) / 8, opacity))
                entry.0.addConvexFace(quad, normal: n, edges: false)
                buckets[k] = entry
            }
        }
        for k in buckets.keys.sorted() {
            var p = MeshPart(mesh: buckets[k]!.0, materialID: nil)
            p.color = buckets[k]!.1
            p.styles = .realisticOnly
            parts.append(p)
        }
        return parts
    }

    // MARK: Linked content from another model

    /// Categories of another model that become linked content (its model elements; datums, rooms and annotation are
    /// left out, as Revit draws only model geometry of links by host view).
    public static func isLinkable(_ e: Element) -> Bool {
        e.category.isModel && !e.isType && e.ownerViewID == nil && ElementMeshes.hasModelGeometry(e)
            && e.category != .linkedModels && e.category != .coordinationModels && e.category != .pointClouds && e.category != .decals
    }

    /// The display geometry of every model element of `model` (one part per element and material colour), in the
    /// model's internal coordinates. Elements of design options other than the primary ones, and demolished elements
    /// of the last phase, are left out.
    public static func content(of model: BIMModel, isCancelled: @Sendable () -> Bool = { false }) -> (parts: [LinkedModelPart], elementCount: Int) {
        var parts: [LinkedModelPart] = []
        var count = 0
        let primaryOptions = Set(model.elements(.designOptions).filter { $0.designOption?.isPrimary ?? false }.map(\.id))
        for e in model.allElements.sorted(by: { $0.id < $1.id }) where isLinkable(e) {
            if isCancelled() { break }
            if let o = e.designOptionID, !primaryOptions.contains(o) { continue }
            if e.phaseDemolished != nil { continue }
            count += 1
            var byColor: [RGBColor: Mesh] = [:]
            var order: [RGBColor] = []
            for p in ElementMeshes.parts(e, model, detail: .medium) where !p.mesh.isEmpty && p.isVisibleIn3D {
                let c = p.color ?? partColor(p.materialID, e.category, model)
                if byColor[c] == nil { order.append(c) }
                byColor[c, default: Mesh()].append(p.mesh)
            }
            let category = linkedCategory(e)
            for c in order { parts.append(LinkedModelPart(category: category, name: e.name, color: c, mesh: byColor[c]!)) }
        }
        return (parts, count)
    }

    static func partColor(_ materialID: ElementID?, _ c: Category, _ model: BIMModel) -> RGBColor {
        if let m = model[materialID]?.material {
            var col = m.color
            col.a = max(0.05, min(1, 1 - m.transparency))
            return col
        }
        return ElementMeshes.defaultColor(c)
    }

    /// IFC reference geometry takes the host category its IFC class corresponds to.
    static func linkedCategory(_ e: Element) -> Category {
        guard e.category == .ifcReference, let t = e.referenceGeometry?.ifcType.lowercased() else { return e.category }
        let map: [(String, Category)] = [("ifcwall", .walls), ("ifccurtainwall", .walls), ("ifcslab", .floors), ("ifcroof", .roofs), ("ifcdoor", .doors),
                                         ("ifcwindow", .windows), ("ifccolumn", .columns), ("ifcbeam", .structuralFraming), ("ifcstair", .stairs),
                                         ("ifcramp", .ramps), ("ifcrailing", .railings), ("ifcfurnishing", .furniture), ("ifcfurniture", .furniture),
                                         ("ifccovering", .ceilings), ("ifcsite", .topography), ("ifcfooting", .structuralFraming), ("ifcmember", .structuralFraming),
                                         ("ifcplate", .walls), ("ifcbuildingelementproxy", .genericModels), ("ifcsanitaryterminal", .plumbingFixtures)]
        return map.first { t.hasPrefix($0.0) }?.1 ?? .genericModels
    }

    /// Display geometry of an OBJ mesh (coordination model): one part per material group.
    public static func content(ofMesh groups: [(name: String, mesh: Mesh)]) -> [LinkedModelPart] {
        groups.filter { !$0.mesh.indices.isEmpty }.map { LinkedModelPart(category: .coordinationModels, name: $0.name, color: ElementMeshes.defaultColor(.coordinationModels), mesh: $0.mesh) }
    }
}
