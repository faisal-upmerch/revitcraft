import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain

/// Wall solids must stay closed when openings touch the outline (doors at the base) or overlap each other.
@Suite("Wall solids")
struct WallSolidTests {
    /// Every directed edge (by welded position) is matched by its reverse.
    func isClosed(_ m: Mesh) -> Bool {
        var keys: [SIMD3<Int64>: Int] = [:]
        func id(_ p: Vec3) -> Int {
            let k = SIMD3<Int64>(Int64((p.x * 1e4).rounded()), Int64((p.y * 1e4).rounded()), Int64((p.z * 1e4).rounded()))
            if let i = keys[k] { return i }
            keys[k] = keys.count
            return keys.count - 1
        }
        let ids = m.positions.map(id)
        var directed: [SIMD2<Int>: Int] = [:]
        for t in stride(from: 0, to: m.indices.count, by: 3) {
            let a = ids[Int(m.indices[t])], b = ids[Int(m.indices[t + 1])], c = ids[Int(m.indices[t + 2])]
            if a == b || b == c || a == c { continue }
            for (u, v) in [(a, b), (b, c), (c, a)] { directed[SIMD2(u, v), default: 0] += 1 }
        }
        return directed.allSatisfy { directed[SIMD2($0.key.y, $0.key.x), default: 0] == $0.value }
    }

    func model(doorsAt xs: [Double], corner: Bool) throws -> (BIMModel, ElementID, Double) {
        let (m0, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m0, name: "Walls")
        let l1 = ids.levels[0], l2 = ids.levels[1]
        let wt = ids.wallTypes["Exterior - Brick on CMU"]!
        let w0 = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(0, 0), Vec2(8, 0))), topLevelID: l2)), typeID: wt, levelID: l1)
        if corner {
            tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(8, 0), Vec2(8, 6))), topLevelID: l2)), typeID: wt, levelID: l1)
        }
        let door = ids.familyTypes["Door - Single Flush: 900 x 2100"]!
        for x in xs { tx.create(.doors, data: .insert(InsertData(location: Vec2(x, 0))), typeID: door, levelID: l1, hostID: w0) }
        let m = try tx.commit().model
        return (m, w0, WallGeometry.frame(m[w0]!, m)!.thickness)
    }

    @Test(arguments: [false, true])
    func doorAtBaseKeepsSolidClosed(corner: Bool) throws {
        let (m, w, _) = try model(doorsAt: [3], corner: corner)
        #expect(WallGeometry.openings(m[w]!, m).count == 1)
        let solid = WallGeometry.solid(m[w]!, m)
        #expect(isClosed(solid))
    }

    @Test func freeWallVolumeSubtractsDoor() throws {
        let (m, w, t) = try model(doorsAt: [3], corner: false)
        let solid = WallGeometry.solid(m[w]!, m)
        let o = WallGeometry.openings(m[w]!, m)[0]
        let h = WallGeometry.frame(m[w]!, m)!.height
        let expected = 8 * h * t - (o.s1 - o.s0) * (o.z1 - o.z0) * t
        #expect(abs(abs(solid.signedVolume) - expected) < 1e-4)
    }

    @Test func overlappingOpeningsStayClosed() throws {
        let (m, w, _) = try model(doorsAt: [3, 3.5], corner: false)
        let solid = WallGeometry.solid(m[w]!, m)
        #expect(isClosed(solid))
    }
}
