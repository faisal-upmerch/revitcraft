import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

/// The DWG engines bundled with Arcus (acadrust helper and LibreDWG dwg2dxf), the route chain and DWG export. // DWG
///
/// Tests that run the real engines use the builds in the source tree (Tools/DWGHelper/target/release/arcus-dwg and
/// Tools/LibreDWG/cache/out/dwg2dxf) and are skipped when those have not been built. The corpus test runs only when
/// `ARCUS_DWG_CORPUS` names folders of DWG files (see Docs/DWGSDKSetup.md).
@Suite("Bundled DWG engines")
struct BundledDWGEngineTests {
    static let macosRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let helpers = BundledDWGHelpers.development(macosRoot: macosRoot)
    static var hasAcadrust: Bool { helpers.acadrust != nil }
    static var hasLibreDWG: Bool { helpers.libreDWG != nil }

    static func dwg(_ name: String) -> URL { Fx.url("dwg/\(name)") }
    static func temp(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("arcus-dwgtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    /// A small plan in view coordinates: walls, a door swing, text.
    static func planGraphics() -> ViewGraphics {
        let st = GStroke(weight: 3, color: .black)
        return ViewGraphics(viewID: ElementID(99), scale: 100, items: [
            GItem(elementID: ElementID(1), category: .walls, layer: .cut, primitives: [
                .polyline([Vec2(0, 0), Vec2(10, 0), Vec2(10, 6), Vec2(0, 6)], closed: true, st),
                .polyline([Vec2(5, 0), Vec2(5, 6)], closed: false, st),
            ]),
            GItem(elementID: ElementID(2), category: .doors, layer: .model, primitives: [
                .arc(Arc2(center: Vec2(2, 0), radius: 0.9, startAngle: 0, sweep: .pi / 2), GStroke(weight: 1)),
            ]),
            GItem(elementID: ElementID(3), category: .textNotes, layer: .annotation, primitives: [
                .text(GText(position: Vec2(1, 3), height: 0.0025, string: "Living Größe")),
            ]),
        ], extents: Rect2(min: .zero, max: Vec2(10, 6)), crop: nil, modelRevision: 1)
    }

    // MARK: Reading with the real engines

    @Test(.enabled(if: hasAcadrust)) func acadrustReadsAnAutoCAD2018Drawing() throws {
        ExternalDWGConversionCache.shared.removeAll()
        let p = BundledAcadrustDWGProvider(helper: try #require(Self.helpers.acadrust), timeout: 60)
        #expect(p.isAvailable && p.sdkName.contains("acadrust"))
        let doc = try p.read(Self.dwg("acadsharp_export_sample.dwg"), options: .init(), progress: { _ in }, isCancelled: { false })
        #expect(doc.format == "DWG" && doc.version == "AC1032" && doc.versionName == "AutoCAD 2018")
        #expect(Set(doc.layers.map(\.name)).isSuperset(of: ["0", "out-margin", "control"]))
        #expect(doc.modelSpace.count >= 20)
        let empty = try p.read(Self.dwg("acadsharp_empty.dwg"), options: .init(), progress: { _ in }, isCancelled: { false })
        #expect(empty.modelSpace.isEmpty && empty.layers.map(\.name).contains("0"))
    }

    @Test(.enabled(if: hasLibreDWG)) func libreDWGReadsTheSameDrawing() throws {
        ExternalDWGConversionCache.shared.removeAll()
        let p = BundledLibreDWGProvider(executable: try #require(Self.helpers.libreDWG), timeout: 60)
        #expect(p.sdkName.contains("LibreDWG"))
        let doc = try p.read(Self.dwg("acadsharp_export_sample.dwg"), options: .init(), progress: { _ in }, isCancelled: { false })
        #expect(doc.format == "DWG" && doc.version == "AC1032")
        #expect(Set(doc.layers.map(\.name)).isSuperset(of: ["0", "out-margin", "control"]))
        #expect(!doc.modelSpace.isEmpty)
    }

    @Test(.enabled(if: hasAcadrust)) func dynamicBlocksRead() throws {
        let p = BundledAcadrustDWGProvider(helper: try #require(Self.helpers.acadrust), timeout: 60)
        let doc = try p.read(Self.dwg("acadsharp_block_visibility.dwg"), options: .init(), progress: { _ in }, isCancelled: { false })
        #expect(!doc.blocks.isEmpty)
    }

    @Test(.enabled(if: hasAcadrust)) func hostileInputFailsWithAPlainReason() throws {
        let p = BundledAcadrustDWGProvider(helper: try #require(Self.helpers.acadrust), timeout: 30)
        let junk = try Self.temp("junk.dwg")
        var bytes = Data("AC1032".utf8)
        var g = SystemRandomNumberGenerator()
        bytes.append(contentsOf: (0..<20_000).map { _ in UInt8.random(in: 0...255, using: &g) })
        try bytes.write(to: junk)
        let e = try #require(throws: CADError.self) { try p.read(junk, options: .init(), progress: { _ in }, isCancelled: { false }) }
        #expect(e.message.contains("acadrust could not read this DWG"))
        // A real drawing cut short.
        let full = try Data(contentsOf: Self.dwg("acadsharp_export_sample.dwg"))
        let cut = try Self.temp("cut.dwg")
        try full.prefix(full.count / 3).write(to: cut)
        ExternalDWGConversionCache.shared.removeAll()
        do { _ = try p.read(cut, options: .init(), progress: { _ in }, isCancelled: { false }) } catch let e as CADError { #expect(!e.message.isEmpty) }
    }

    // MARK: The route chain

    /// A stand-in route that always fails or always returns a fixed document.
    struct FakeRoute: DWGImportProvider {
        var name: String
        var fails: Bool
        var isAvailable = true
        var unavailableReason: String? { nil }
        var sdkName: String { name }
        var sdkVersion: String? { nil }
        var supportedVersions: [String] { ["AC1032"] }
        func read(_ url: URL, options: CADReadOptions, progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) throws -> CADDocument {
            if fails { throw CADError("\(name) can't read it.") }
            var d = try Fx.doc("r12_plan.dxf")
            d.format = "DWG"
            return d
        }
    }

    /// Both write the shared "last DWG engine" record, so they run one after the other.
    @Suite(.serialized) struct Record {
    @Test func chainFallsBackInOrderAndRecordsTheEngine() throws {
        let chain = DWGEngineChain(routes: [BundledDWGEngineTests.FakeRoute(name: "First", fails: true), BundledDWGEngineTests.FakeRoute(name: "Second", fails: false), BundledDWGEngineTests.FakeRoute(name: "Third", fails: false)])
        #expect(chain.isAvailable && chain.sdkName == "First")
        let doc = try chain.read(URL(fileURLWithPath: "/tmp/plan.dwg"), options: .init(), progress: { _ in }, isCancelled: { false })
        #expect(doc.warnings.first?.contains("Read by Second") == true)
        #expect(doc.warnings.first?.contains("First can't read it.") == true)
        let last = try #require(DWGEngineRecord.last())
        #expect(last.file == "plan.dwg" && last.engine == "Second" && last.failures.count == 1)
    }

    @Test func chainExplainsEveryFailureAndOffersDXF() throws {
        let chain = DWGEngineChain(routes: [BundledDWGEngineTests.FakeRoute(name: "A", fails: true), BundledDWGEngineTests.FakeRoute(name: "B", fails: true), BundledDWGEngineTests.FakeRoute(name: "C", fails: false, isAvailable: false)])
        let e = try #require(throws: CADError.self) { try chain.read(URL(fileURLWithPath: "/tmp/site.dwg"), options: .init(), progress: { _ in }, isCancelled: { false }) }
        #expect(e.message.contains("1) A: A can't read it.") && e.message.contains("2) B: B can't read it."))
        #expect(!e.message.contains("C:"), "unavailable routes are not tried")
        #expect(e.message.contains("DXF"))
        #expect(DWGEngineRecord.last()?.engine == nil)
    }
    }

    @Test func chainWithNothingAvailableKeepsTheHonestReason() {
        let missing = URL(fileURLWithPath: "/nonexistent/helpers")
        let c = DWGProviders.chain(helpers: .in(missing), converter: nil)
        #expect(!c.isAvailable)
        #expect(c.unavailableReason?.contains("missing from this copy of Arcus") == true)
        #expect(c.unavailableReason?.contains("ODA File Converter") == true && c.unavailableReason?.contains("DXF") == true)
        let bad = DWGProviders.chain(helpers: .none, converter: .failure(.invalidChosenPath("/nope/dwg2dxf")))
        #expect(bad.unavailableReason?.contains("/nope/dwg2dxf") == true)
    }

    @Test func chainOrderIsAcadrustLibreDWGThenInstalledConverter() throws {
        let dir = try Self.temp("helpers").deletingLastPathComponent()
        for n in [BundledDWGHelpers.acadrustName, BundledDWGHelpers.libreDWGName] {
            let u = dir.appendingPathComponent(n)
            try "#!/bin/sh\nexit 1\n".write(to: u, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
        }
        let installed = ExternalDWGConverter(kind: .odaFileConverter, executableURL: URL(fileURLWithPath: "/bin/sh"))
        let c = DWGProviders.chain(helpers: .in(dir), converter: .success(installed))
        #expect(c.routes.count >= 3)
        #expect(c.routes[0] is BundledAcadrustDWGProvider)
        #expect(c.routes[1] is BundledLibreDWGProvider)
        #expect(c.routes[2] is ExternalConverterDWGProvider)
    }

    @Test func helperExitCodesBecomePlainMessages() {
        func o(_ code: Int32, _ err: String = "") -> ExternalProcessRunner.Outcome { .init(exitCode: code, standardOutput: "", standardError: err) }
        #expect(BundledDWGEngine.message(o(3), doing: "reading x").contains("more memory"))
        #expect(BundledDWGEngine.message(o(4), doing: "reading x").contains("did not finish in time"))
        #expect(BundledDWGEngine.message(o(2, "acadrust could not read this DWG (AC1032: Parse error)"), doing: "reading x") == "acadrust could not read this DWG (AC1032: Parse error)")
        #expect(BundledDWGEngine.message(o(9), doing: "reading x").contains("status 9"))
        #expect(BundledDWGEngine.summary("noise\n{\"ok\":true,\"modelSpaceEntities\":4}\n")["modelSpaceEntities"] as? Int == 4)
    }

    // MARK: Export

    @Test(.enabled(if: hasAcadrust)) func exportEveryVersionRoundTrips() throws {
        let helper = try #require(Self.helpers.acadrust)
        var m = BIMModel()
        m = try TransactionContext(model: m, name: "Empty").commit().model
        let dxf = DXFWriter.write(Self.planGraphics(), units: .millimeters, layers: .aia, model: m)
        let reference = try DXFReader.read(dxf, fileName: "plan.dxf")
        for v in DWGExportVersion.allCases {
            let url = try Self.temp("Plan \(v.rawValue) ü.dwg")
            let s = try DWGExporter.write(dxf: dxf, to: url, version: v, helper: helper, timeout: 60)
            #expect(s.entities == reference.modelSpace.count, "\(v)")
            #expect(DWGProviders.sniffVersion(url) == v.rawValue)
            ExternalDWGConversionCache.shared.removeAll()
            let back = try BundledAcadrustDWGProvider(helper: helper, timeout: 60).read(url, options: .init(), progress: { _ in }, isCancelled: { false })
            #expect(back.modelSpace.count == reference.modelSpace.count, "\(v)")
            #expect(Set(back.layers.map(\.name)).isSuperset(of: ["A-WALL", "A-DOOR"]), "\(v)")
            #expect(back.units == .millimeters, "\(v)")
            let texts = back.modelSpace.compactMap { e -> String? in if case .text(let t, _) = e { return t.text }; return nil }
            #expect(texts.contains("Living Größe"), "\(v)")
            if let libre = Self.helpers.libreDWG {
                let l = try BundledLibreDWGProvider(executable: libre, timeout: 60).read(url, options: .init(), progress: { _ in }, isCancelled: { false })
                #expect(l.modelSpace.count == reference.modelSpace.count, "LibreDWG reads Arcus's \(v) DWG")
            }
        }
    }

    /// The sample project's first floor plan and first sheet, as the DWG export writes them, in every version.
    @Test(.enabled(if: hasAcadrust)) func exportRealPlanAndSheetEveryVersion() throws {
        let helper = try #require(Self.helpers.acadrust)
        let m = CourtyardHouse.make()
        let plan = try #require(m.views.first { $0.view?.kind == .floorPlan })
        let sheet = try #require(m.sheets.first)
        let planDXF = DXFWriter.write(ViewGraphicsBuilder(model: m, view: plan).build(), units: .millimeters, layers: .aia, model: m)
        let sheetG = SheetGraphicsBuilder(model: m, sheet: sheet, includeGuides: false, viewGraphics: { ViewGraphicsBuilder(model: m, view: $0).build() }).build()
        let sheetDXF = DXFWriter.write(sheetG, units: .millimeters, layers: .aia, model: m)
        for (name, dxf) in [("plan", planDXF), ("sheet", sheetDXF)] {
            let reference = try DXFReader.read(dxf, fileName: "\(name).dxf")
            #expect(reference.modelSpace.count > 20, "\(name) has content")
            for v in DWGExportVersion.allCases {
                let url = try Self.temp("\(name).dwg")
                try DWGExporter.write(dxf: dxf, to: url, version: v, helper: helper, timeout: 120)
                ExternalDWGConversionCache.shared.removeAll()
                let back = try BundledAcadrustDWGProvider(helper: helper, timeout: 120).read(url, options: .init(), progress: { _ in }, isCancelled: { false })
                #expect(back.modelSpace.count == reference.modelSpace.count, "\(name) \(v)")
                #expect(Set(back.layers.map(\.name)) == Set(reference.layers.map(\.name)), "\(name) \(v) layers")
                #expect(back.entityCounts == reference.entityCounts, "\(name) \(v) entity types")
            }
        }
    }

    @Test func exportReplacesOnlyAfterSuccess() throws {
        let url = try Self.temp("Keep.dwg")
        try Data("previous".utf8).write(to: url)
        // A helper whose read-back check fails (exit 7), as arcus-dwg does when the DWG it wrote doesn't read back.
        let fake = url.deletingLastPathComponent().appendingPathComponent("arcus-dwg")
        try "#!/bin/sh\necho 'The DWG read back with 3 of 5 model-space entities (version AC1032), so it was not saved.' >&2\nexit 7\n"
            .write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let dxf = DXFWriter.write(Self.planGraphics(), units: .millimeters)
        let e = try #require(throws: CADError.self) { try DWGExporter.write(dxf: dxf, to: url, helper: fake, timeout: 30) }
        #expect(e.message.contains("3 of 5"))
        #expect(try Data(contentsOf: url) == Data("previous".utf8), "a failed export leaves the old file alone")
        #expect(throws: CADError.self) { try DWGExporter.write(dxf: Data("not a dxf".utf8), to: url, helper: fake) }
        #expect(throws: CADError.self) { try DWGExporter.write(dxf: dxf, to: url, helper: nil) }
    }

    @Test func exportFileNamesAreSafe() {
        #expect(DWGExporter.fileName("A101 - Ground/First: Floor") == "A101 - Ground-First- Floor.dwg")
        #expect(DWGExporter.fileName("..hidden") == "hidden.dwg")
        #expect(DWGExporter.fileName("  ") == "Drawing.dwg")
        #expect(DWGExportVersion.default == .r2018 && DWGExportVersion.r2018.title == "AutoCAD 2018 DWG")
        #expect(DWGExporter.unavailableReason(helpers: .none)?.contains("DXF") == true)
    }

    // MARK: Corpus

    /// Reads every DWG under the folders in `ARCUS_DWG_CORPUS` (colon-separated) with both engines through Arcus's DXF
    /// reader, then exports what acadrust read to every DWG version and reads it back with both engines. Writes a
    /// Markdown table to `ARCUS_DWG_CORPUS_REPORT` (default: a temporary file, printed at the end).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ARCUS_DWG_CORPUS"] != nil && hasAcadrust))
    func corpus() throws {
        let env = ProcessInfo.processInfo.environment
        let helper = try #require(Self.helpers.acadrust)
        let libre = Self.helpers.libreDWG
        let roots = (env["ARCUS_DWG_CORPUS"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        var files: [(URL, URL)] = []
        for r in roots {
            let e = FileManager.default.enumerator(at: r, includingPropertiesForKeys: [.isRegularFileKey])
            while let u = e?.nextObject() as? URL { if u.pathExtension.lowercased() == "dwg" { files.append((r, u)) } }
        }
        files.sort { $0.1.path < $1.1.path }
        let versions = DWGExportVersion.allCases
        struct Row { var name = "", version = "", acadrust = "", libre = "", trips: [String: String] = [:] }
        var rows: [Row] = []
        var tally: [String: (ok: Int, n: Int)] = [:]
        var readA = 0, readL = 0, readAny = 0
        func describe(_ d: CADDocument) -> String { "\(d.modelSpace.count) ent, \(d.layers.count) lay" }
        func short(_ e: any Error) -> String {
            let s = "\(e)".replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ")
            return "✗ " + String(s.prefix(90))
        }
        for (root, f) in files {
            var row = Row()
            row.name = String(f.path.dropFirst(root.deletingLastPathComponent().path.count + 1))
            row.version = DWGProviders.sniffVersion(f).map { "\($0) (\(CADDocument.friendlyVersion($0)))" } ?? "?"
            ExternalDWGConversionCache.shared.removeAll()
            let a = BundledAcadrustDWGProvider(helper: helper, timeout: 120)
            var aDoc: CADDocument?
            do { aDoc = try a.read(f, options: .init(), progress: { _ in }, isCancelled: { false }); row.acadrust = "✓ " + describe(aDoc!); readA += 1 }
            catch { row.acadrust = short(error) }
            var lDoc: CADDocument?
            if let libre {
                do { lDoc = try BundledLibreDWGProvider(executable: libre, timeout: 120).read(f, options: .init(), progress: { _ in }, isCancelled: { false }); row.libre = "✓ " + describe(lDoc!); readL += 1 }
                catch { row.libre = short(error) }
            } else { row.libre = "not built" }
            if aDoc != nil || lDoc != nil { readAny += 1 }
            let dxf = aDoc == nil ? nil : try? ExternalDWGConversion.run(
                f, executable: helper, name: "acadrust", timeout: 120,
                arguments: { i, o in ["to-dxf", i.appendingPathComponent(ExternalDWGConverter.stagedInputName).path, o.appendingPathComponent(ExternalDWGConverter.stagedOutputName).path] }).dxf
            if let aDoc, let dxf {
                for v in versions {
                    var t = tally[v.rawValue] ?? (0, 0)
                    t.n += 1
                    do {
                        let out = try Self.temp("rt.dwg")
                        defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
                        try DWGExporter.write(dxf: dxf, to: out, version: v, helper: helper, timeout: 120)
                        ExternalDWGConversionCache.shared.removeAll()
                        let back = try BundledAcadrustDWGProvider(helper: helper, timeout: 120).read(out, options: .init(), progress: { _ in }, isCancelled: { false })
                        let ok = back.modelSpace.count >= aDoc.modelSpace.count
                        var note = ok ? "✓" : "✗ \(back.modelSpace.count)/\(aDoc.modelSpace.count)"
                        if let libre {
                            if let l = try? BundledLibreDWGProvider(executable: libre, timeout: 120).read(out, options: .init(), progress: { _ in }, isCancelled: { false }) {
                                if l.modelSpace.count < aDoc.modelSpace.count { note += " L\(l.modelSpace.count)" }
                            } else { note += " L✗" }
                        }
                        row.trips[v.rawValue] = note
                        if ok { t.ok += 1 }
                    } catch {
                        row.trips[v.rawValue] = short(error)
                    }
                    tally[v.rawValue] = t
                }
            }
            rows.append(row)
        }
        var md = "| File | Version | acadrust | LibreDWG | " + versions.map { $0.title.replacingOccurrences(of: "AutoCAD ", with: "") }.joined(separator: " | ") + " |\n"
        md += "|" + String(repeating: " --- |", count: 4 + versions.count) + "\n"
        for r in rows {
            md += "| \(r.name) | \(r.version) | \(r.acadrust) | \(r.libre) | " + versions.map { r.trips[$0.rawValue] ?? "–" }.joined(separator: " | ") + " |\n"
        }
        md += "\n\(files.count) files: acadrust read \(readA), LibreDWG read \(readL), at least one engine read \(readAny).\n\n"
        md += "| Export version | Round trips passed |\n| --- | --- |\n"
        for v in versions { let t = tally[v.rawValue] ?? (0, 0); md += "| \(v.title) | \(t.ok) / \(t.n) |\n" }
        let reportURL = env["ARCUS_DWG_CORPUS_REPORT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("arcus-dwg-corpus.md")
        try md.write(to: reportURL, atomically: true, encoding: .utf8)
        print("DWG corpus report: \(reportURL.path)")
        #expect(readAny > 0)
    }
}
