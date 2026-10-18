import Foundation
import ArcusGeometry
import ArcusDomain

// F810: View ▸ Presentation ▸ Export OBJ (RevitCraft's `write_obj_files`): the model's 3D geometry as Wavefront OBJ with
// an MTL material library beside it, for visualisation apps.

/// Writes the model as OBJ + MTL: one group per element, one material per Arcus material (or category colour), meters,
/// Y up (OBJ's convention: x, z, −y).
public enum OBJExporter {
    public struct Output: Sendable {
        public var obj: String
        public var mtl: String
        public var elementCount: Int
        public var triangleCount: Int
    }

    /// The elements exported: model elements with 3D geometry that exist (not demolished) and are in no secondary
    /// design option.
    public static func elements(_ model: BIMModel) -> [Element] {
        model.allElements.filter { e in
            guard e.category.isModel, !e.isType, e.ownerViewID == nil, e.phaseDemolished == nil, ElementMeshes.hasModelGeometry(e) else { return false }
            if let o = e.designOptionID, model[o]?.designOption?.isPrimary == false { return false }
            return true
        }.sorted { $0.id < $1.id }
    }

    /// An OBJ/MTL identifier: letters, digits and underscores.
    static func identifier(_ s: String) -> String {
        let t = String(s.map { $0.isLetter || $0.isNumber ? $0 : "_" })
        return t.isEmpty ? "Default" : t
    }

    public static func export(_ model: BIMModel, mtlName: String, detail: DetailLevel = .fine, isCancelled: () -> Bool = { false }) -> Output {
        var obj = "# Arcus OBJ export (meters, Y up)\nmtllib \(mtlName)\n"
        var mtl = "# Arcus materials\n"
        var materials = Set<String>()
        var base = 1, elements = 0, triangles = 0
        func f(_ v: Double) -> String { String(format: "%.4f", v) }
        for e in Self.elements(model) {
            if isCancelled() { break }
            let parts = ElementMeshes.parts(e, model, detail: detail).filter { $0.isVisibleIn3D && $0.mesh.triangleCount > 0 }
            guard !parts.isEmpty else { continue }
            elements += 1
            let label = e.name.isEmpty ? e.category.singularName : e.name
            obj += "g \(identifier(label))_\(e.id.raw)\n"
            for p in parts {
                let matElement = p.materialID.flatMap { model[$0] }
                let name = identifier(matElement?.name ?? "Arcus \(e.category.displayName)")
                if !materials.contains(name) {
                    materials.insert(name)
                    let c = matElement?.material?.color ?? ElementMeshes.defaultColor(e.category)
                    let transparency = matElement?.material?.transparency ?? (1 - c.a)
                    mtl += "newmtl \(name)\nKa 0.000 0.000 0.000\nKd \(f(c.r)) \(f(c.g)) \(f(c.b))\nKs 0.050 0.050 0.050\nNs 10\nd \(f(max(0, min(1, 1 - transparency))))\nillum 2\n\n"
                }
                obj += "usemtl \(name)\n"
                let m = p.mesh
                for q in m.positions { obj += "v \(f(q.x)) \(f(q.z)) \(f(-q.y))\n" }
                let normals = m.normals.count == m.positions.count
                if normals { for n in m.normals { obj += "vn \(f(n.x)) \(f(n.z)) \(f(-n.y))\n" } }
                for k in stride(from: 0, to: m.indices.count - 2, by: 3) {
                    let a = base + Int(m.indices[k]), b = base + Int(m.indices[k + 1]), c = base + Int(m.indices[k + 2])
                    obj += normals ? "f \(a)//\(a) \(b)//\(b) \(c)//\(c)\n" : "f \(a) \(b) \(c)\n"
                }
                triangles += m.triangleCount
                base += m.positions.count
            }
        }
        return Output(obj: obj, mtl: mtl, elementCount: elements, triangleCount: triangles)
    }

    /// Writes `url` (.obj) and the .mtl beside it.
    @discardableResult
    public static func write(_ model: BIMModel, to url: URL) throws -> Output {
        let mtlURL = url.deletingPathExtension().appendingPathExtension("mtl")
        let out = export(model, mtlName: mtlURL.lastPathComponent)
        try Data(out.obj.utf8).write(to: url, options: .atomic)
        try Data(out.mtl.utf8).write(to: mtlURL, options: .atomic)
        return out
    }
}
