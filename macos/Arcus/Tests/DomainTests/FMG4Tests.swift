import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

/// FMG4: the gap batches' open items. Slats keep their spread through their joints in compiled families: the slats
/// stay between their first plane and far side (not at fixed offsets from the first), the slats past the count stay
/// hidden, the legs at the slats' ends aren't run on across the layout, and tenons and mortises follow the slats.
@Suite("FMG4 slats through joints") @MainActor
struct FMG4SlatTests {
    static let inch = 0.0254

    static func compiled(_ name: String) throws -> FamilyDefinition {
        let p = try #require(SimpleB.pieces.first { $0.name == name })
        return FurnitureCompiler.family(from: try p.make())
    }

    static func evaluate(_ f: FamilyDefinition, _ param: String, _ k: Double) -> EvaluatedFamily {
        var g = f
        if let base = g.types[0].values[param]?.doubleValue { g.types[0].values[param] = .double(base * k) }
        return FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
    }

    @Test(arguments: ["Outdoor Side Table", "Garden Bench", "Shoe Bench"])
    func slatsSpreadWithDepthInTheCompiledFamily(_ name: String) throws {
        let f = try Self.compiled(name)
        let base = Self.evaluate(f, "Depth", 1), deep = Self.evaluate(f, "Depth", 1.25), shallow = Self.evaluate(f, "Depth", 0.85)
        for ev in [base, deep, shallow] { #expect(ev.errors.isEmpty, "\(name): \(ev.errors.prefix(2))") }
        let b0 = FMG1Tests.bounds(base)
        for (ev, k) in [(deep, 1.25), (shallow, 0.85)] {
            let b = FMG1Tests.bounds(ev)
            let depth0 = b0.max.y - b0.min.y, depth = b.max.y - b.min.y
            let d = try #require(f.types[0].values["Depth"]?.doubleValue)
            #expect(abs((depth - depth0) - d * (k - 1)) < 1e-3, "\(name) x\(k): \(depth0 / Self.inch) → \(depth / Self.inch)")
            // The last visible slat of the top layout sits at the far side: within a slat of the back.
            let slats = ev.solids.filter { $0.name.hasPrefix("SL1 Slat") && !$0.name.contains("Tenon") && !$0.isVoid }
            let back = slats.map(\.bounds.max.y).max() ?? 0
            #expect(abs(back - b.max.y) < 3.5 * Self.inch, "\(name) x\(k): last slat at \(back / Self.inch), piece back \(b.max.y / Self.inch)")
        }
    }

    @Test func aLegUnderSlatsIsntRunOnAcrossTheLayout() throws {
        let p = try #require(SimpleB.pieces.first { $0.name == "Outdoor Side Table" })
        let m = try p.make()
        let sol = JointSolver.solve(m)
        for leg in m.elements(.furnitureLegs) {
            guard let part = sol.parts[leg.id], let box = sol.finalBoxes[leg.id] else { continue }
            #expect(abs(box.ext(.y) - part.box.size.y) < 1e-6, "\(leg.mark): \(part.box.size.y / Self.inch) → \(box.ext(.y) / Self.inch)")
        }
    }
}

/// FMG4: the template views' scale follows the piece (a standard furniture scale), the template dimensions sit at
/// paper distances outside it, row by row, the elevation markers just outside the plan, and a View Scale the user
/// sets turns the automatic scale off for that view.
@Suite("FMG4 automatic view scale") @MainActor
struct FMG4AutoScaleTests {
    static let inch = 0.0254

    static func set(_ name: String, _ inches: Double, _ m: BIMModel) throws -> BIMModel {
        let tx = TransactionContext(model: m, name: "Size")
        try FurnitureParameters.setValue(name, .double(inches * Self.inch), in: tx)
        return try tx.commit().model
    }

    static func plan(_ m: BIMModel) -> Element { m.views.first { $0.name == "Ref. Level" && $0.view?.kind.isPlan == true }! }

    @Test func theScaleFollowsThePieceSize() throws {
        #expect(FurnitureAutoScale.scale(width: 12 * Self.inch, depth: 4 * Self.inch, height: 8 * Self.inch) == 4)
        #expect(FurnitureAutoScale.scale(width: 36 * Self.inch, depth: 15 * Self.inch, height: 18 * Self.inch) == 8)
        #expect(FurnitureAutoScale.scale(width: 84 * Self.inch, depth: 36 * Self.inch, height: 34 * Self.inch) == 24)
        var m = try Self.set("Width", 36, FurnitureTemplates.blank())
        m = try Self.set("Depth", 15, m)
        m = try Self.set("Height", 18, m)
        #expect(Self.plan(m).view?.scale == 8)
        #expect(m.views.filter { FurnitureAutoScale.isOn($0) }.allSatisfy { $0.view?.scale == 8 })
        // 84" wide: 1/2" = 1'-0" would fit, but at 15" deep 3/4" keeps the text a sixth of the depth.
        m = try Self.set("Width", 84, m)
        #expect(Self.plan(m).view?.scale == 16, "\(Self.plan(m).view?.scale ?? 0)")
        m = try Self.set("Depth", 36, m)
        #expect(Self.plan(m).view?.scale == 24, "\(Self.plan(m).view?.scale ?? 0)")
    }

    @Test func aViewScaleTheUserSetsStays() throws {
        var m = try Self.set("Width", 36, FurnitureTemplates.blank())
        let id = Self.plan(m).id
        let tx = TransactionContext(model: m, name: "View Scale")
        let auto = try #require(m[id]?.view?.scale)
        tx.update(id) { $0.view?.scale = auto == 4 ? 8 : 4 }
        m = try tx.commit().model
        let mine = auto == 4 ? 8 : 4
        #expect(m[id]?.view?.scale == mine)
        #expect(m[id]?.params[FurnitureAutoScale.onParam]?.boolValue == false)
        m = try Self.set("Width", 84, m)
        m = try Self.set("Depth", 36, m)
        #expect(m[id]?.view?.scale == mine)
        #expect(m.views.first { $0.name == "Front" }?.view?.scale == 24)
    }

    @Test func dimensionsSitInRowsAtPaperDistancesAndMarkersOutsideThePlan() throws {
        var m = try Self.set("Width", 84, FurnitureTemplates.blank())
        m = try Self.set("Depth", 36, m)
        let plan = Self.plan(m), s = Double(plan.view!.scale)
        let e = FurniturePlanes.extents(m), mg = FurniturePlanes.margin
        let front = e.y.lowerBound + mg
        let below = m.elements(.dimensions).filter { $0.ownerViewID == plan.id && $0.dimension!.linePoint.y < front }
        let rows = below.map { (front - $0.dimension!.linePoint.y) / s }.sorted()
        #expect(rows.count == 2)
        #expect(abs(rows[0] - FurnitureAutoScale.firstRow) < 1e-6 && abs(rows[1] - (FurnitureAutoScale.firstRow + FurnitureAutoScale.rowGap)) < 1e-6, "\(rows)")
        // The Front elevation's marker: in front of the piece, past the plan's crop and dimensions, inside its annotation crop.
        let fe = try #require(m.views.first { $0.name == "Front" }?.view)
        let marker = try #require(fe.markerPosition)
        #expect(marker.y < front - rows[1] * s)
        let crop = try #require(plan.view?.cropRegion)
        #expect(marker.y > crop.min.y - plan.view!.annotationCropOffset * s)
        #expect(abs((fe.planeOrigin?.y ?? 0) - marker.y) < 1e-9 && abs(fe.planeOrigin?.x ?? 1) < 1e-9) // moved along the view direction only
        // A dimension the user moves is theirs.
        let dim = below[0]
        let tx = TransactionContext(model: m, name: "Move")
        tx.update(dim.id) { $0.dimension?.linePoint.y -= 0.1 }
        m = try tx.commit().model
        let moved = try #require(m[dim.id]?.dimension?.linePoint)
        m = try Self.set("Width", 60, m)
        #expect(m[dim.id]?.dimension?.linePoint.y == moved.y)
        #expect(m[dim.id]?.params[FurnitureAutoScale.rowParam] == nil)
    }
}
