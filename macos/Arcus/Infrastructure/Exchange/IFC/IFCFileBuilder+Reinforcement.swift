import Foundation
import ArcusGeometry
import ArcusDomain

// F34: reinforcement exports as IfcReinforcingBar (rebar sets, area and path reinforcement: one entity per element
// whose body holds every bar) and IfcReinforcingMesh (fabric areas and sheets), with their bar sizes.

extension IFCFileBuilder {
    func reinforcementProduct(_ e: Element, kind: ExportKind, placement: Int, shape: Int?) -> Int {
        let bars = Reinforcement.bars(e, model)
        let steel: STEPValue = .null
        func area(_ d: Double) -> Double { Double.pi * d * d / 4 }
        if kind == .reinforcingMesh {
            let type = e.fabricArea?.fabricTypeID ?? e.typeID
            let s = Reinforcement.sheetSize(model, type)
            var length: STEPValue = .null, width: STEPValue = .null
            if e.fabricSheet != nil { length = .d(s.length); width = .d(s.width) }
            let tail: [STEPValue] = [steel, length, width, .d(s.wire), .d(s.wire), .d(area(s.wire)), .d(area(s.wire)), .d(s.major), .d(s.minor)]
                + (is4 ? [.e("NOTDEFINED")] : [])
            return product(e, "IfcReinforcingMesh", placement: placement, shape: shape, tail: tail)
        }
        let d = bars.first?.diameter ?? Reinforcement.barDiameter(model, e.typeID)
        let length: STEPValue = bars.map(\.length).max().map { .d($0) } ?? .null
        // The bar role (IFC2X3 BarRole, required) or type (IFC4 PredefinedType), then the bar surface.
        let role: STEPValue = e.pathReinforcement != nil ? .e("EDGE") : .e("MAIN")
        let tail: [STEPValue] = [steel, .d(d), .d(area(d)), length, role, .null]
        return product(e, "IfcReinforcingBar", placement: placement, shape: shape, tail: tail)
    }
}
