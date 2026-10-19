import Foundation
import ArcusGeometry

// FMG3: the library kit's helpers for bays on faces other than the front (a corner cabinet's canted door, a storage
// bed's drawers along its sides), built with the same operations the Bay and Door tools call in the views looking at
// those faces.

extension SA.Builder {
    /// A plan point (inches → meters) halfway between plane coordinates, for the current size.
    func point(_ x: (SA.LP, SA.LP), _ y: (SA.LP, SA.LP)) -> Vec2 { Vec2((v(x.0) + v(x.1)) / 2, (v(y.0) + v(y.1)) / 2) }

    /// A bay on the face seen from `facing` (radians: the face's frame, π/4 for a front canted to the front right), round
    /// the plan point `at` and the height `z`.
    @discardableResult
    func bay(at p: Vec2, z: SA.LP, facing: Double) throws -> ElementID {
        let frame = BayFrame(angle: facing)
        let local = frame.local(p)
        return try FurnitureBays.createBay(face: .front, at: Vec2(local.x, v(z)), frame: frame, in: tx)
    }

    /// A door in the bay on a canted (or any) face round the plan point halfway along `x` and `y`.
    @discardableResult
    func faceDoor(x: (SA.LP, SA.LP), y: (SA.LP, SA.LP), z: SA.LP, facing: Double, _ typeName: String, material: String? = nil, hingeRight: Bool = false) throws -> [ElementID] {
        let bay = try bay(at: point(x, y), z: z, facing: facing)
        return try FurnitureFronts.createFront(.door, in: bay, typeID: try frontType(.door, typeName, material: material), hingeFlipped: hingeRight, in: tx)
    }

    /// Drawers side by side in the bay on the face seen from `facing`, round the plan point halfway along `x` and `y`
    /// and height `z` (divided into `count` equal columns, EQ).
    @discardableResult
    func faceDrawers(x: (SA.LP, SA.LP), y: (SA.LP, SA.LP), z: SA.LP, facing: Double, count: Int, _ typeName: String = SA.slabDrawer, material: String? = nil) throws -> [ElementID] {
        let bay = try bay(at: point(x, y), z: z, facing: facing)
        if count > 1 { try FurnitureBays.divide(bay, BayDivision(direction: .columns, count: count), in: tx) }
        return try FurnitureFronts.createFront(.drawer, in: bay, typeID: try frontType(.drawer, typeName, material: material), in: tx)
    }
}
