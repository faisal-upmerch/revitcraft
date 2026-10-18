import Foundation
import ArcusGeometry

// BL-VG: Structure ▸ Foundation. Arcus has no Structural Foundations category yet, so footings are structural
// floors (Floors category) of dedicated footing types: a pad under a column, a strip under a wall, or a sketched slab.

public enum StructuralFoundations {
    public static let padTypeName = "Pad Footing 1200 x 1200 x 400"
    public static let stripTypeName = "Wall Footing 300"
    public static let slabTypeName = "Foundation Slab 300"
    /// Pad footing size in plan and depth.
    public static let padSize = 1.2, padDepth = 0.4
    /// Strip footing projection past each wall face and depth.
    public static let stripProjection = 0.15, stripDepth = 0.3

    /// A floor type of one concrete layer with the given thickness, created (from the first floor type) when missing.
    @discardableResult
    public static func footingType(_ name: String, thickness: Double, in tx: TransactionContext) -> ElementID? {
        if let t = tx.model.types(for: .floors).first(where: { $0.name == name }) { return t.id }
        guard let base = tx.model.types(for: .floors).first, var td = base.typeData else { return nil }
        let concrete = tx.model.materials.first { $0.material?.materialClass == .concrete }?.id
            ?? td.assembly?.layers.first(where: { $0.function == .structure })?.materialID
        td.assembly = CompoundAssembly(layers: [AssemblyLayer(function: .structure, materialID: concrete, thickness: thickness)])
        td.params[ParameterID("type.function")] = .text("Foundation")
        return tx.create(.elementTypes, name: name, data: .type(td))
    }

    /// Pad footings under structural (or architectural) columns: square, centred on the column, top at its base.
    @discardableResult
    public static func isolated(under columns: [ElementID], in tx: TransactionContext) -> [ElementID] {
        guard let type = footingType(padTypeName, thickness: padDepth, in: tx) else { return [] }
        var out: [ElementID] = []
        for id in columns {
            guard let c = tx.model[id], c.category == .structuralColumns || c.category == .columns,
                  let pl = ComponentGeometry.placement(c, tx.model) else { continue }
            let p = pl.plan.apply(.zero), h = padSize / 2
            let base = tx.model.baseElevation(of: c) - tx.model.elevation(ofLevel: c.levelID)
            var slab = SlabData(boundary: Sketch(rect: Rect2(min: p - Vec2(h, h), max: p + Vec2(h, h))), offset: base)
            slab.structural = true; slab.roomBounding = false
            out.append(tx.create(.floors, name: "Isolated Foundation", data: .slab(slab), typeID: type, levelID: c.levelID))
        }
        return out
    }

    /// Strip footings under straight walls: the wall's plan footprint widened on both faces, top at the wall base.
    @discardableResult
    public static func wall(under walls: [ElementID], in tx: TransactionContext) -> [ElementID] {
        guard let type = footingType(stripTypeName, thickness: stripDepth, in: tx) else { return [] }
        var out: [ElementID] = []
        for id in walls {
            guard let w = tx.model[id], let wd = w.wall, let f = WallGeometry.frame(w, tx.model),
                  let center = f.location.offset(by: f.centerOffset).asSegment else { continue }
            let half = f.thickness / 2 + stripProjection
            let d = center.direction * stripProjection, n = center.normal * half
            let a = center.start - d, b = center.end + d
            var slab = SlabData(boundary: Sketch(polygon: Polygon2([a - n, b - n, b + n, a + n]).counterClockwise), offset: wd.baseOffset)
            slab.structural = true; slab.roomBounding = false
            out.append(tx.create(.floors, name: "Wall Foundation", data: .slab(slab), typeID: type, levelID: w.levelID))
        }
        return out
    }
}
