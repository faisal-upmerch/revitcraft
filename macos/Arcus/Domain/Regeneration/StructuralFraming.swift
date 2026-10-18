import Foundation
import ArcusGeometry

// F34: Structure ▸ Truss, Brace and Beam System, and Manage ▸ Structural Settings, as RevitCraft builds them
// (rc-core edit.rs add_brace, add_truss, add_beam_system, regen_beam_system).

public enum StructuralFraming {
    public static let usageParameter = ParameterID("structural.usage")
    /// RevitCraft's truss depth: 1500 mm (5'-0" in imperial projects).
    public static func trussDepth(_ m: BIMModel) -> Double { m.units.system == .imperial ? 1.524 : 1.5 }
    /// RevitCraft's beam system spacing: 1800 mm (6'-0").
    public static func beamSystemSpacing(_ m: BIMModel) -> Double { m.units.system == .imperial ? 1.8288 : 1.8 }

    /// Height from a level to the level above it (3 m when there is none).
    public static func storeyHeight(above level: ElementID?, _ m: BIMModel) -> Double {
        let z = m.elevation(ofLevel: level)
        let above = m.levels.compactMap(\.level?.elevation).filter { $0 > z + Tolerance.length }.min()
        return above.map { $0 - z } ?? 3
    }

    /// A brace: a framing member from `start` at `z0` above the level to `end` at `z1`, its axis through both points.
    @discardableResult
    public static func brace(from start: Vec2, to end: Vec2, z0: Double, z1: Double, type: ElementID?, level: ElementID?, usage: String = "Vertical Bracing",
                             in tx: TransactionContext) -> ElementID {
        var b = BeamData(curve: .line(Segment2(start, end)), startOffset: z0, endOffset: z1, zJustification: .center)
        b.rotation = 0
        return tx.create(.structuralFraming, data: .beam(b), typeID: type, levelID: level) { $0.params[usageParameter] = .text(usage) }
    }

    /// A flat Warren truss from `start` to `end`: the bottom chord at the level, the top chord `depth` above it and
    /// diagonals alternating between them, about one panel per `depth`. Returns its members (chords first).
    public static func truss(from start: Vec2, to end: Vec2, depth: Double, type: ElementID?, level: ElementID?, in tx: TransactionContext) throws(TransactionError) -> [ElementID] {
        let len = start.distance(to: end)
        guard len >= 2 * max(depth, 0.1) else { throw TransactionError("The truss is too short for its height.") }
        let panels = max(2, Int((len / depth).rounded()))
        func at(_ k: Int) -> Vec2 { start + (end - start) * (Double(k) / Double(panels)) }
        var ids = [brace(from: start, to: end, z0: 0, z1: 0, type: type, level: level, usage: "Other", in: tx),
                   brace(from: start, to: end, z0: depth, z1: depth, type: type, level: level, usage: "Other", in: tx)]
        for k in 0..<panels {
            let (z0, z1) = k % 2 == 0 ? (0.0, depth) : (depth, 0.0)
            ids.append(brace(from: at(k), to: at(k + 1), z0: z0, z1: z1, type: type, level: level, usage: "Other", in: tx))
        }
        return ids
    }

    /// The beams' lines of a beam system: along `dir`, `spacing` apart, centred across the boundary and clipped to it.
    public static func beamSystemLines(_ boundary: [Vec2], direction dir: Vec2, spacing: Double) throws(TransactionError) -> [Segment2] {
        guard spacing >= 0.1 else { throw TransactionError("The beam spacing is too small.") }
        guard boundary.count >= 3 else { throw TransactionError("A beam system needs a closed boundary.") }
        let d = dir.lengthSquared > 1e-12 ? dir.normalized : .unitX, n = d.perpendicular
        let across = boundary.map { ($0 - boundary[0]).dot(n) }
        let lo = across.min() ?? 0, hi = across.max() ?? 0
        let count = Int(((hi - lo) / spacing + 1e-9).rounded(.down))
        guard count > 0 else { throw TransactionError("The boundary is narrower than the beam spacing.") }
        let first = lo + (hi - lo - Double(count - 1) * spacing) / 2
        var lines: [Segment2] = []
        for k in 0..<count {
            let o = boundary[0] + n * (first + Double(k) * spacing)
            var ts: [Double] = []
            for i in boundary.indices {
                let a = boundary[i], c = boundary[(i + 1) % boundary.count]
                let da = (a - o).dot(n), dc = (c - o).dot(n)
                if (da > 0) != (dc > 0) { ts.append((a + (c - a) * (da / (da - dc)) - o).dot(d)) }
            }
            ts.sort()
            var i = 0
            while i + 1 < ts.count {
                if ts[i + 1] - ts[i] > 0.1 { lines.append(Segment2(o + d * ts[i], o + d * ts[i + 1])) }
                i += 2
            }
        }
        return lines
    }

    /// Creates a beam system over `boundary` with beams parallel to its first edge; its beams follow in regeneration.
    @discardableResult
    public static func beamSystem(boundary: [Vec2], spacing: Double, beamType: ElementID?, level: ElementID?, in tx: TransactionContext) throws(TransactionError) -> ElementID {
        let b = Polygon2(boundary).simplified().points
        guard b.count >= 3 else { throw TransactionError("A beam system needs a closed boundary.") }
        let dir = (b[1] - b[0]).normalized
        _ = try beamSystemLines(b, direction: dir, spacing: spacing)
        return tx.create(.beamSystems, data: .beamSystem(BeamSystemData(boundary: b, direction: dir, spacing: spacing, beamTypeID: beamType)), levelID: level)
    }

    /// Regeneration: rebuilds the beams of every beam system created or changed in the transaction.
    static func regenerateBeamSystems(_ tx: TransactionContext) throws(TransactionError) {
        for id in tx.touchedIDs {
            guard let sys = tx.model[id], let d = sys.beamSystem else { continue }
            let lines = try beamSystemLines(d.boundary, direction: d.direction, spacing: d.spacing)
            let old = tx.model.hosted(by: id).filter { $0.beam != nil }
            // Unchanged beams (same lines and type) are kept so that editing nothing rebuilds nothing.
            let wanted = lines.map { BeamData(curve: .line($0), startOffset: d.elevation, endOffset: d.elevation) }
            if old.count == wanted.count, zip(old, wanted).allSatisfy({ $0.beam == $1 && $0.typeID == d.beamTypeID && $0.levelID == sys.levelID }) { continue }
            for b in old { tx.delete(b.id) }
            let type = d.beamTypeID ?? tx.model.types(for: .structuralFraming).first?.id
            for w in wanted {
                tx.create(.structuralFraming, data: .beam(w), typeID: type, levelID: sys.levelID, hostID: id) { $0.params[usageParameter] = .text("Beam") }
            }
        }
    }

    /// The project's Structural Settings element, created on first use.
    @discardableResult
    public static func settingsElement(in tx: TransactionContext) -> ElementID {
        if let s = tx.model.elements(.structuralSettings).first { return s.id }
        return tx.create(.structuralSettings, name: "Structural Settings", data: .structuralSettings(StructuralSettingsData()))
    }

    /// Replaces the project's Structural Settings.
    public static func setSettings(_ s: StructuralSettingsData, in tx: TransactionContext) {
        let id = settingsElement(in: tx)
        tx.update(id) { $0.structuralSettings = s }
    }
}
