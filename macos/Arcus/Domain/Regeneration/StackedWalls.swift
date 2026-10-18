import Foundation
import ArcusGeometry

/// F2: a stacked wall draws and builds as its parts. Each part is a wall of a basic type over its height band, derived
/// on the fly (never stored): the same element with the part's type, base offset, height and location line, so the
/// basic wall geometry (joins, openings, layers, plan cuts, sections) applies to it unchanged.
public enum StackedWalls {
    /// The stacked structure of a wall's type, or nil for every other wall.
    public static func spec(_ e: Element, _ model: BIMModel) -> StackedWallSpec? {
        guard e.wall != nil, let s = model.typeData(of: e)?.stack, !s.parts.isEmpty else { return nil }
        return s
    }
    public static func isStacked(_ e: Element, _ model: BIMModel) -> Bool { spec(e, model) != nil }

    /// The basic wall type ids a stacked type uses.
    public static func partTypes(_ td: TypeData?) -> [ElementID] { td?.stack?.parts.compactMap(\.typeID) ?? [] }

    /// The assembly a stacked wall reports as a whole (joins, rooms, hosted inserts): its thickest part's.
    public static func nominalAssembly(_ s: StackedWallSpec, _ model: BIMModel) -> CompoundAssembly {
        let assemblies = s.parts.map { partAssembly($0, model) }
        return assemblies.max { $0.totalThickness < $1.totalThickness } ?? WallGeometry.assembly(ofType: nil)
    }

    static func partAssembly(_ p: StackedWallPart, _ model: BIMModel) -> CompoundAssembly {
        let td = model[p.typeID]?.typeData
        // Only basic wall types stack; anything else builds as the generic wall.
        return WallGeometry.assembly(ofType: td?.stack == nil && td?.curtain == nil ? td : nil)
    }

    /// The parts of a stacked wall as walls of their own types over their height bands, bottom up (nil when `e` isn't
    /// a stacked wall). Each keeps `e`'s id, level and hosted elements. Only the top part keeps the top constraint and
    /// the roof or floor attachments above; only the bottom part keeps the base attachments. Edited profiles and wall
    /// sweeps stay with the stacked wall itself.
    public static func parts(of e: Element, _ model: BIMModel) -> [Element]? {
        guard let s = spec(e, model), let w = e.wall else { return nil }
        let base = model.baseElevation(of: e)
        let top = max(base + Tolerance.shortCurve, model.topElevation(base: base, topLevelID: w.topLevelID, topOffset: w.topOffset, unconnectedHeight: w.unconnectedHeight))
        let bands = s.bands(base: base, top: top)
        var out: [Element] = []
        for (k, b) in bands.enumerated() {
            let p = s.parts[b.index]
            var part = e
            let td = model[p.typeID]?.typeData
            part.typeID = td?.stack == nil && td?.curtain == nil ? p.typeID : nil
            var pw = w
            pw.baseOffset = w.baseOffset + (b.z0 - base)
            if k < bands.count - 1 {
                pw.topLevelID = nil; pw.topOffset = 0; pw.unconnectedHeight = b.z1 - b.z0
                pw.attachedTopIDs = []
            } else if pw.topLevelID == nil {
                pw.unconnectedHeight = top - b.z0 // the raised base keeps the wall's own top
            }
            if k > 0 { pw.attachedBaseIDs = [] }
            let flip = p.flipped ?? false
            pw.flipped = w.flipped != flip
            if abs(p.offset) > Tolerance.length { pw.location = w.location.offset(by: w.flipped ? -p.offset : p.offset) }
            pw.profile = nil; pw.sweeps = nil; pw.curtain = nil
            part.data = .wall(pw)
            out.append(part)
        }
        return out
    }

    /// The part a horizontal cut at `z` passes through (the wall itself when it isn't stacked; the nearest part when
    /// `z` is outside the wall).
    public static func part(of e: Element, atZ z: Double, _ model: BIMModel) -> Element {
        guard let ps = parts(of: e, model), !ps.isEmpty else { return e }
        return ps.first { p in
            let b = model.baseElevation(of: p)
            guard let pw = p.wall else { return false }
            let t = model.topElevation(base: b, topLevelID: pw.topLevelID, topOffset: pw.topOffset, unconnectedHeight: pw.unconnectedHeight)
            return z >= b - Tolerance.length && z < t - Tolerance.length
        } ?? (z < model.baseElevation(of: ps[0]) ? ps[0] : ps[ps.count - 1])
    }
}
