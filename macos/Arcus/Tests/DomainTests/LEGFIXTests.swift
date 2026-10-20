import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// LEGFIX: a turned leg whose body has beads (VIS: profile heights a share of Height plus a length) still gets its blocks
/// and mortises where stretchers join below the pommel: the body is split round each block (no revolve through a
/// mortise), the beads keep their formulas, and every mortise below the neck lies in a block.
@Suite("LEGFIX turned legs with beads") @MainActor
struct LEGFIXTests {
    /// The Decorative Bench's legs as compiled at Fine.
    static func benchLegs() throws -> [FamilyDefinition] {
        let m = try #require(SimpleB.pieces.first { $0.name == "Decorative Bench" }).make()
        let ctx = PartSolidContext(symbolic: false)
        return try m.elements(.furnitureLegs).map { leg in try #require(FurniturePartSolids.solids(leg, m, ctx).placed.first?.family) }
    }

    /// A bound's value at body height `hb`.
    static func value(_ b: FamilyBound, _ hb: Double) -> Double? {
        guard case .expr(let src) = b else { return nil }
        guard let f = try? Formula(src, knownNames: ["Height"]),
              let v = try? f.evaluate(units: .metric, { $0 == "Height" ? .quantity(hb, .length) : nil }) else { return nil }
        return v.quantityValue
    }

    @Test func theBenchsStretchersAreMortisedInBlocks() throws {
        let legs = try Self.benchLegs()
        #expect(legs.count == 4)
        for fam in legs {
            let h = try #require(fam.types.first?.values["Height"]?.doubleValue)
            let neck = h * FurnitureLegShapes.pommelStart
            let blocks = fam.solids.filter { $0.name.hasPrefix("Block") }.compactMap { s -> (Double, Double)? in
                guard let a = Self.value(s.zMin, h), let b = Self.value(s.zMax, h) else { return nil }
                return (a, b)
            }
            let cuts = fam.solids.filter { $0.isVoid && $0.visibleAt == [.fine] }.compactMap { s -> (Double, Double)? in
                guard let a = Self.value(s.zMin, h), let b = Self.value(s.zMax, h) else { return nil }
                return (a, b)
            }
            #expect(!blocks.isEmpty, "a block where the stretchers join")
            // Aprons in the pommel, stretchers in a block.
            #expect(cuts.contains { $0.0 >= neck - 1e-6 }, "an apron's mortise in the pommel")
            for c in cuts where c.0 < neck - 1e-6 {
                #expect(blocks.contains { $0.0 <= c.0 + 1e-6 && $0.1 >= c.1 - 1e-6 }, "mortise \(c) lies in a block \(blocks)")
            }
            // The body is split round the blocks and its beads keep their formulas.
            let body = try #require(fam.nestedFamilies.first)
            #expect(body.solids.count == blocks.count + 1)
            var lengthTerms = 0
            for s in body.solids {
                guard case .revolve(let rev) = s.profile else { Issue.record("\(s.name) is not a revolve"); continue }
                let ts = rev.profile.compactMap { Self.value($0.y, neck) }
                #expect(ts.count == rev.profile.count)
                lengthTerms += rev.profile.filter { if case .expr(let f) = $0.y { f.contains(" m") } else { false } }.count
                for b in blocks {
                    #expect(!ts.contains { $0 > b.0 + 1e-6 && $0 < b.1 - 1e-6 }, "\(s.name) passes through block \(b)")
                }
            }
            #expect(lengthTerms > 0, "the beads keep their length terms")
        }
    }

    @Test func profilesThatCantBeReadKeepTheMortises() throws {
        // A body whose profile isn't a revolve: the blocks and mortises are still made, the body stays whole.
        let m = try #require(SimpleB.pieces.first { $0.name == "Decorative Bench" }).make()
        let leg = try #require(m.elements(.furnitureLegs).first)
        var raw = try #require(FurniturePartSolids.rawSolids(leg, m, PartSolidContext(symbolic: false)).placed.first)
        raw.family.nestedFamilies[0].solids[0].profile = .rectangle(xMin: .expr("-0.01"), xMax: .expr("0.01"), yMin: .expr("-0.01"), yMax: .expr("0.01"))
        let h = try #require(raw.family.types.first?.values["Height"]?.doubleValue)
        let z = raw.z.value + h * 0.2
        let v = JBox(lo: [PartValue(raw.x.value - 0.005), PartValue(raw.y.value - 0.005), PartValue(z)],
                     hi: [PartValue(raw.x.value + 0.005), PartValue(raw.y.value + 0.005), PartValue(z + 0.02)])
        let out = TurnedLegJoints.cut(raw, voids: [v], width: 0.05)
        #expect(out.family.solids.contains { $0.name == "Block 1" })
        #expect(out.family.solids.contains { $0.name == "Joint Cut 1" && $0.isVoid })
        #expect(out.family.nestedFamilies.first?.solids.count == 1)
    }
}
