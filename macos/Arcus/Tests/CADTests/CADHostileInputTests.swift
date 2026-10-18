import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

@Suite("Hostile and corrupt input")
struct CADHostileInputTests {
    @Test func truncatedFileYieldsPartialDocumentWithWarning() throws {
        let doc = try Fx.doc("malformed/truncated.dxf")
        #expect(doc.warnings.contains { $0.contains("truncated") })
        #expect(doc.entityCounts["LINE", default: 0] >= 2)
        #expect(doc.layers.contains { $0.name == "WALLS" })
    }

    @Test func invalidGroupCodeStopsWithWarning() throws {
        let doc = try Fx.doc("malformed/bad_group_code.dxf")
        #expect(doc.modelSpace.count == 1)
        #expect(doc.warnings.contains { $0.contains("Invalid group code") && $0.contains("line") })
    }

    @Test func invalidValuesAreSkippedAndReported() throws {
        let doc = try Fx.doc("malformed/bad_values.dxf")
        let handles = Set(doc.modelSpace.map(\.props.handle))
        #expect(handles.contains("1"))   // valid line
        #expect(handles.contains("B"))   // odd/negative group codes are ignored
        #expect(!handles.contains("2"))  // non-numeric coordinate
        #expect(!handles.contains("3") && !handles.contains("4") && !handles.contains("5")) // negative / NaN / inf radius
        #expect(!handles.contains("6"))  // 1e300 coordinate
        #expect(handles.contains("7"))   // gigantic vertex count, two real vertices
        #expect(!handles.contains("C"))  // empty angle
        #expect(!handles.contains("D"))  // negative text height
        #expect(doc.warnings.contains { $0.contains("invalid or out-of-range geometry") })
        guard case .polyline(let p, _)? = doc.entity(handle: "7") else { Issue.record("polyline missing"); return }
        #expect(p.points.count == 2)
        // Conversion copes with the rest (undefined block, zero scale, bogus spline/hatch counts).
        let r = CADConverter.referenceDrawing(doc, options: CADImportOptions())
        #expect(r.drawing.entities.count >= 3)
        #expect(r.report.warnings.contains { $0.contains("not defined") })
    }

    @Test func notADXFFileThrows() {
        #expect(throws: CADError.self) { try DXFReader.read(Data("hello, world\nthis is text".utf8), fileName: "x.dxf") }
        #expect(throws: CADError.self) { try DXFReader.read(Data(), fileName: "empty.dxf") }
        #expect(throws: CADError.self) { try DXFReader.read(Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10]), fileName: "jpeg.dxf") }
        #expect(throws: CADError.self) { try DXFReader.read(Data("0\nSECTION\n".utf8), fileName: "stub.dxf") }
    }

    @Test func blockCyclesAndExpansionBombsAreBounded() throws {
        let doc = try Fx.doc("malformed/block_cycles.dxf")
        let start = Date()
        let r = CADConverter.referenceDrawing(doc, options: CADImportOptions())
        #expect(Date().timeIntervalSince(start) < 10)
        #expect(r.report.warnings.contains { $0.contains("reference themselves") })
        #expect(r.report.warnings.contains { $0.contains("expand to more than") })
        // The stored drawing never flattens into an unbounded amount of geometry.
        let flat = r.drawing.flattened()
        #expect(flat.count < 1000)
        #expect(!r.drawing.entities.contains { if case .insert(let b, _, _, _) = $0 { return b == "BOMB1" }; return false })
        // Exploding is bounded the same way.
        var o = CADImportOptions()
        o.explodeBlocks = true
        let e = CADConverter.referenceDrawing(doc, options: o)
        #expect(e.drawing.entities.count < 1000)
        #expect(e.report.warnings.contains { $0.contains("reference themselves") })
    }

    @Test func deepBlockNestingIsLimited() throws {
        var d = DXFText()
        d.seq([(0, "SECTION"), (2, "HEADER"), (9, "$ACADVER"), (1, "AC1015"), (0, "ENDSEC"), (0, "SECTION"), (2, "BLOCKS")])
        for i in 0..<60 {
            d.seq([(0, "BLOCK"), (2, "N\(i)"), (70, 0), (10, 0), (20, 0), (0, "LINE"), (8, "0"), (10, 0), (20, 0), (11, 1), (21, 0)])
            if i < 59 { d.seq([(0, "INSERT"), (8, "0"), (2, "N\(i + 1)"), (10, 1), (20, 0)]) }
            d.seq([(0, "ENDBLK")])
        }
        d.seq([(0, "ENDSEC"), (0, "SECTION"), (2, "ENTITIES"), (0, "INSERT"), (8, "0"), (2, "N0"), (10, 0), (20, 0), (0, "ENDSEC"), (0, "EOF")])
        let doc = try DXFReader.read(d.data, fileName: "deep.dxf")
        var o = CADImportOptions()
        o.explodeBlocks = true
        let r = CADConverter.referenceDrawing(doc, options: o)
        #expect(r.report.warnings.contains { $0.contains("nested deeper than") })
        #expect(r.drawing.entities.count <= 33)
        let kept = CADConverter.referenceDrawing(doc, options: CADImportOptions())
        #expect(kept.report.warnings.contains { $0.contains("nested deeper than") })
    }

    @Test func hugeSymbolTablesParseInLinearTime() throws {
        var d = DXFText()
        d.seq([(0, "SECTION"), (2, "HEADER"), (9, "$ACADVER"), (1, "AC1015"), (0, "ENDSEC"), (0, "SECTION"), (2, "TABLES")])
        for i in 0..<40_000 { d.seq([(0, "LAYER"), (2, "L\(i)"), (70, 0), (62, i % 255 + 1)]) }
        for i in 0..<40_000 { d.seq([(0, "STYLE"), (2, "S\(i)"), (70, 0), (3, "f\(i).shx")]) }
        d.seq([(0, "ENDSEC"), (0, "SECTION"), (2, "ENTITIES")])
        for i in 0..<40_000 { d.seq([(0, "POINT"), (8, "L\(i)"), (10, i), (20, 0)]) }
        d.seq([(0, "ENDSEC"), (0, "EOF")])
        let data = d.data
        let start = Date()
        let doc = try DXFReader.read(data, fileName: "tables.dxf")
        let mid = Date()
        let r = CADConverter.referenceDrawing(doc, options: CADImportOptions())
        print("CAD tables: read \(mid.timeIntervalSince(start)) convert \(Date().timeIntervalSince(mid))")
        #expect(Date().timeIntervalSince(start) < 10)
        #expect(doc.layers.count == 40_001)
        #expect(doc.fonts.count == 40_000)
        #expect(r.drawing.layers.count == 40_001)
    }

    @Test func entityLimitIsEnforced() throws {
        let d = DXFText.minimal { t in for i in 0..<50 { t.seq([(0, "POINT"), (8, "0"), (10, i), (20, 0)]) } }
        var o = CADReadOptions()
        o.maxEntities = 10
        #expect(throws: CADError.self) { try DXFReader.read(d.data, fileName: "many.dxf", options: o) }
    }

    @Test func readerIsCancellable() throws {
        let d = DXFText.minimal { t in for i in 0..<20_000 { t.seq([(0, "POINT"), (8, "0"), (10, i), (20, 0)]) } }
        #expect(throws: CancellationError.self) { try DXFReader.read(d.data, fileName: "c.dxf", isCancelled: { true }) }
    }

    @Test func progressIsReportedAndReachesOne() throws {
        let d = DXFText.minimal { t in for i in 0..<20_000 { t.seq([(0, "POINT"), (8, "0"), (10, i), (20, 0)]) } }
        final class Box: @unchecked Sendable { var values: [Double] = []; let lock = NSLock() }
        let box = Box()
        _ = try DXFReader.read(d.data, fileName: "p.dxf", progress: { v in box.lock.lock(); box.values.append(v); box.lock.unlock() })
        #expect(box.values.count > 2)
        #expect(box.values.last == 1)
        #expect(zip(box.values, box.values.dropFirst()).allSatisfy { $0 <= $1 })
    }

    /// Deterministic mutation fuzzing: truncations and byte corruptions must never crash or hang.
    @Test func fuzzedFixturesNeverCrash() throws {
        var rng = SplitMix(seed: 0x5EED)
        for name in ["r12_plan.dxf", "ac1015_imperial_layouts.dxf", "ac1027_blocks_annotation.dxf", "ac1032_unicode_survey.dxf"] {
            let original = try Fx.data(name)
            for _ in 0..<60 {
                var bytes = [UInt8](original)
                switch rng.next() % 3 {
                case 0: bytes = Array(bytes.prefix(Int(rng.next() % UInt64(bytes.count))))
                case 1:
                    for _ in 0..<8 { bytes[Int(rng.next() % UInt64(bytes.count))] = UInt8(truncatingIfNeeded: rng.next()) }
                default:
                    let i = Int(rng.next() % UInt64(bytes.count))
                    bytes.insert(contentsOf: Array("\n1e308\n-99999\nnan\n".utf8), at: i)
                }
                if let doc = try? DXFReader.read(Data(bytes), fileName: name) {
                    let r = CADConverter.referenceDrawing(doc, options: CADImportOptions())
                    #expect(CADGeometry.isFinite(r.drawing.extents) || r.drawing.extents == Rect2(min: .zero, max: .zero))
                    // Content must always be encodable (a failed encode would collapse to the hash of empty data).
                    #expect(r.drawing.contentKey != "ref-" + StableHash.hex(Data()))
                }
            }
        }
    }

    /// Generates a large drawing in-test and checks parse + convert stay within a sane time (debug build).
    @Test func largeDrawingPerformance() throws {
        let count = 300_000
        var s = [UInt8]()
        s.reserveCapacity(count * 90)
        func add(_ str: String) { s.append(contentsOf: str.utf8) }
        add("0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1027\n9\n$INSUNITS\n70\n4\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n")
        for i in 0..<count {
            let x = Double(i % 1000) * 100, y = Double(i / 1000) * 100
            switch i % 4 {
            case 0: add("0\nLINE\n5\n\(String(i, radix: 16))\n8\nL\(i % 16)\n10\n\(x)\n20\n\(y)\n11\n\(x + 90)\n21\n\(y)\n")
            case 1: add("0\nLWPOLYLINE\n5\n\(String(i, radix: 16))\n8\nL\(i % 16)\n90\n3\n70\n1\n10\n\(x)\n20\n\(y)\n10\n\(x + 50)\n20\n\(y)\n42\n0.5\n10\n\(x + 50)\n20\n\(y + 50)\n")
            case 2: add("0\nCIRCLE\n5\n\(String(i, radix: 16))\n8\nL\(i % 16)\n10\n\(x)\n20\n\(y)\n40\n25\n")
            default: add("0\nTEXT\n5\n\(String(i, radix: 16))\n8\nL\(i % 16)\n10\n\(x)\n20\n\(y)\n40\n10\n1\nT\(i)\n")
            }
        }
        add("0\nENDSEC\n0\nEOF\n")
        let data = Data(s)
        let start = Date()
        let doc = try DXFReader.read(data, fileName: "big.dxf")
        let parsed = Date()
        let r = CADConverter.referenceDrawing(doc, options: CADImportOptions())
        let end = Date()
        let parseTime = parsed.timeIntervalSince(start), convertTime = end.timeIntervalSince(parsed)
        print("CAD perf: \(count) entities, \(data.count / 1_000_000) MB: parse \(String(format: "%.2f", parseTime)) s, convert \(String(format: "%.2f", convertTime)) s, resident \(CADMemory.residentBytes() / 1_000_000) MB")
        #expect(doc.modelSpace.count == count)
        #expect(r.report.converted == count)
        #expect(r.drawing.layers.count == 17)
        // Debug builds are several times slower than release; the bound catches super-linear regressions.
        #expect(parseTime + convertTime < 90)
        let keyStart = Date()
        _ = r.drawing.contentKey
        print("CAD perf: contentKey of \(r.drawing.entities.count) entities took \(String(format: "%.2f", Date().timeIntervalSince(keyStart))) s")
    }
}

/// Small deterministic PRNG for fuzzing.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
