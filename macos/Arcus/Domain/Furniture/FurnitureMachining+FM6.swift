import Foundation

// FM6: this batch's machining and derived parts (see FurnitureMachining.swift): every joint's holes, grooves and
// mortises (dowels, cam lock bores and bolt holes, confirmat and pocket screw holes, biscuit slots, dados, rabbets,
// grooves for backs, mortises) and the shelf-pin rows adjustable shelves drill in their sides (JointSolver). Joints
// make no loose pieces: tenons are part of their rails and dowels, cams, screws and biscuits are hardware
// (`FurnitureJoints.hardwareCounts`). Automatic joints have no element: their machining's source is the part that
// butts into the other.

extension FurnitureMachining {
    static func fm6Machining(_ m: BIMModel) -> [MachiningEntry] { JointSolver.solve(m).machining }
    static func fm6DerivedParts(_ m: BIMModel) -> [DerivedPart] { [] }
}
