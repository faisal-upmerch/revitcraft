import Foundation
import ArcusGeometry
import ArcusDomain

// STAIR: stairs export as Revit-style assemblies: an IfcStair (its shape type from the runs) aggregating one
// IfcStairFlight per run (risers, treads, riser height, tread length; IFC4 predefined type STRAIGHT, SPIRAL or WINDER)
// and one IfcSlab LANDING per landing; supports go in the stair's own body. Every storey of a multistory stair is
// included.
extension IFCFileBuilder {
    /// The IfcStairTypeEnum of a stair from its runs and turns.
    func stairShapeType(_ e: Element) -> String {
        guard let s = e.stair else { return "NOTDEFINED" }
        guard s.isComponentStair, let l = StairGeometry.layout(e, model) else {
            switch s.shape {
            case .straight: return "STRAIGHT_RUN_STAIR"
            case .lShaped: return "QUARTER_TURN_STAIR"
            case .uShaped: return "HALF_TURN_STAIR"
            }
        }
        let shapes = l.runs.map(\.shape)
        if shapes.contains(.spiral) { return l.runs.count == 1 ? "SPIRAL_STAIR" : "CURVED_RUN_STAIR" }
        if shapes == [.lWinder] { return "QUARTER_WINDING_STAIR" }
        if shapes == [.uWinder] { return "HALF_WINDING_STAIR" }
        if shapes.contains(.sketch) || shapes.contains(.lWinder) || shapes.contains(.uWinder) { return "NOTDEFINED" }
        if l.runs.count == 1 { return "STRAIGHT_RUN_STAIR" }
        let turn = l.runs.first!.direction.dot(l.runs.last!.direction)
        if l.runs.count == 2 { return turn < -0.5 ? "HALF_TURN_STAIR" : abs(turn) < 0.5 ? "QUARTER_TURN_STAIR" : "TWO_STRAIGHT_RUN_STAIR" }
        if l.runs.count == 3, abs(turn) > 0.5 { return turn < -0.5 ? "TWO_QUARTER_TURN_STAIR" : "THREE_QUARTER_TURN_STAIR" }
        return "NOTDEFINED"
    }

    /// Writes the stair's flights and landings as parts of `stair`, placed in its frame. Returns false when the stair
    /// has no pieces (its own body is then kept).
    @discardableResult
    func exportStairParts(_ e: Element, stair: Int, placement: Int, toLocal: Transform3) -> Bool {
        let pieces = StairMeshes.pieces(e, model).filter { if case .support = $0.kind { return false }; return true }
        guard !pieces.isEmpty else { return false }
        let layouts = (MultistoryStairs.storeys(of: e, model) ?? [e]).map { StairGeometry.layout($0, model) }
        var parts: [Int] = []
        for p in pieces {
            guard let body = meshItems(p.parts, toLocal: toLocal, category: .stairs) else { continue }
            let rep = writer.add("IfcShapeRepresentation", [.r(bodyContext), .s("Body"), .s(body.type), .refs(body.items)])
            let shp = writer.add("IfcProductDefinitionShape", [.null, .null, .refs([rep])])
            let local = localPlacement(relativeTo: placement, .identity)
            let l = layouts.indices.contains(p.storey) ? layouts[p.storey] : nil
            let ent: Int
            switch p.kind {
            case .run(let i):
                let r = l?.runs.first { $0.index == i }
                let seed = "\(e.ifcGUID.value)/storey\(p.storey)/flight\(i)"
                var tail: [STEPValue] = [r.map { .integer($0.risers) } ?? .null, r.map { .integer($0.treads.count) } ?? .null,
                                         l.map { .d($0.riserHeight) } ?? .null, l.map { .d($0.treadDepth) } ?? .null]
                if is4 {
                    let type: String
                    switch r?.shape {
                    case .straight?: type = "STRAIGHT"
                    case .spiral?: type = "SPIRAL"
                    case .lWinder?, .uWinder?: type = "WINDER"
                    case .sketch?: type = "FREEFORM"
                    case nil: type = "NOTDEFINED"
                    }
                    tail.append(.e(type))
                }
                ent = writer.add("IfcStairFlight", [guid(seed), .r(ownerHistory), .s("Run \(i + 1)"), .null, .sOpt(typeLabel(e)), .r(local), .r(shp), .null] + tail)
            case .landing(let k):
                let seed = "\(e.ifcGUID.value)/storey\(p.storey)/landing\(k)"
                ent = writer.add("IfcSlab", [guid(seed), .r(ownerHistory), .s("Landing \(k + 1)"), .null, .sOpt(typeLabel(e)), .r(local), .r(shp), .null, .e("LANDING")])
            case .support:
                continue
            }
            associateMaterials(distinctMaterials(p.parts), object: ent)
            parts.append(ent)
        }
        guard !parts.isEmpty else { return false }
        writer.add("IfcRelAggregates", [guid("\(e.ifcGUID.value)/aggregates/parts"), .r(ownerHistory), .null, .null, .r(stair), .refs(parts)])
        return true
    }
}
