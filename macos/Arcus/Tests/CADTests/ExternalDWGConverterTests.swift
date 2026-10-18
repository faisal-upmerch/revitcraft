import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

/// External DWG converters (ODA File Converter, LibreDWG dwg2dxf), exercised with fake converter scripts that behave like
/// the real command lines. No real converter and no DWG file are needed (or used). // W2-DWG
@Suite("External DWG converter")
struct ExternalDWGConverterTests {
    /// A scratch folder with a fake converter script and a fake source DWG in a folder whose name has spaces and non-ASCII.
    struct Rig {
        let dir: URL
        let script: URL
        let source: URL
        let argsLog: URL

        /// `body` is the shell script body. `$ARGS_LOG` receives the arguments one per line; `$FIXTURE` is a DXF fixture.
        init(kind: ExternalDWGConverterKind, fixture: String = "r12_plan.dxf", body: String) throws {
            ExternalDWGConversionCache.shared.removeAll()
            let fm = FileManager.default
            dir = fm.temporaryDirectory.appendingPathComponent("arcus-dwgconv-\(UUID().uuidString)")
            let bin = dir.appendingPathComponent(kind == .libreDWG ? "bin" : "Apps/ODAFileConverter.app/Contents/MacOS")
            try fm.createDirectory(at: bin, withIntermediateDirectories: true)
            script = bin.appendingPathComponent(kind == .libreDWG ? "dwg2dxf" : "ODAFileConverter")
            argsLog = dir.appendingPathComponent("args.txt")
            let fixtureCopy = dir.appendingPathComponent("fixture.dxf")
            try fm.copyItem(at: Fx.url(fixture), to: fixtureCopy)
            let text = """
            #!/bin/sh
            ARGS_LOG='\(argsLog.path)'
            FIXTURE='\(fixtureCopy.path)'
            : > "$ARGS_LOG"
            for a in "$@"; do printf '%s\\n' "$a" >> "$ARGS_LOG"; done
            \(body)
            """
            try text.write(to: script, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            let docs = dir.appendingPathComponent("My Drawings ü 図面")
            try fm.createDirectory(at: docs, withIntermediateDirectories: true)
            source = docs.appendingPathComponent("Site plan (rev 2) ü.dwg")
            try Data("AC1032\u{0}\u{0}fake DWG payload for tests".utf8).write(to: source)
        }

        var converter: ExternalDWGConverter {
            ExternalDWGConverter(kind: script.lastPathComponent == "dwg2dxf" ? .libreDWG : .odaFileConverter, executableURL: script)
        }
        var loggedArguments: [String] {
            ((try? String(contentsOf: argsLog, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
        }
        func cleanUp() { try? FileManager.default.removeItem(at: dir) }
    }

    /// Behaves like ODA File Converter: `in out version type recurse audit filter`; writes <out>/<name>.dxf.
    static let odaBody = """
    IN="$1"; OUT="$2"; FILTER="$7"
    [ "$3" = "ACAD2018" ] && [ "$4" = "DXF" ] || { echo "bad version/type" >&2; exit 2; }
    [ -f "$IN/$FILTER" ] || { echo "no input $IN/$FILTER" >&2; exit 3; }
    cp "$FIXTURE" "$OUT/${FILTER%.*}.dxf"
    """
    /// Behaves like LibreDWG: `-y -o out.dxf in.dwg`.
    static let libreBody = """
    [ "$1" = "-y" ] && [ "$2" = "-o" ] || { echo "usage" >&2; exit 1; }
    [ -f "$4" ] || { echo "no input" >&2; exit 1; }
    cp "$FIXTURE" "$3"
    """

    @Test func odaArgumentsFollowTheDocumentedCommandLine() {
        let c = ExternalDWGConverter(kind: .odaFileConverter, executableURL: URL(fileURLWithPath: "/Applications/ODAFileConverter.app/Contents/MacOS/ODAFileConverter"))
        let a = c.arguments(inputDirectory: URL(fileURLWithPath: "/tmp/a b/in"), outputDirectory: URL(fileURLWithPath: "/tmp/a b/out"))
        #expect(a == ["/tmp/a b/in", "/tmp/a b/out", "ACAD2018", "DXF", "0", "1", "drawing.dwg"])
    }

    @Test func libreDWGArguments() {
        let c = ExternalDWGConverter(kind: .libreDWG, executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/dwg2dxf"))
        let a = c.arguments(inputDirectory: URL(fileURLWithPath: "/tmp/x/in"), outputDirectory: URL(fileURLWithPath: "/tmp/x/out"))
        #expect(a == ["-y", "-o", "/tmp/x/out/drawing.dxf", "/tmp/x/in/drawing.dwg"])
    }

    @Test func odaConversionHandsTheDXFToTheReader() throws {
        let rig = try Rig(kind: .odaFileConverter, body: Self.odaBody)
        defer { rig.cleanUp() }
        let p = ExternalConverterDWGProvider(converter: rig.converter, timeout: 20)
        #expect(p.isAvailable && p.unavailableReason == nil)
        let steps = ProgressLog()
        let doc = try p.read(rig.source, options: .init(), progress: { steps.add($0) }, isCancelled: { false })
        #expect(doc.format == "DWG")
        #expect(doc.version == "AC1032")                    // from the DWG header, not the converted DXF
        #expect(!doc.layers.isEmpty && !doc.modelSpace.isEmpty)
        #expect(doc.warnings.contains { $0.contains("ODA File Converter") && $0.contains("third-party") })
        let args = rig.loggedArguments
        #expect(args.count == 7)
        #expect(args[2] == "ACAD2018" && args[3] == "DXF" && args[4] == "0" && args[5] == "1" && args[6] == "drawing.dwg")
        // The converter works on a private staged copy, not in the user's folder.
        #expect(!args[0].contains("My Drawings"))
        #expect(!FileManager.default.fileExists(atPath: args[0]), "the temporary folder is removed afterwards")
        #expect(steps.values.last == 1 && steps.values == steps.values.sorted())
    }

    @Test func libreDWGConversion() throws {
        let rig = try Rig(kind: .libreDWG, fixture: "ac1015_imperial_layouts.dxf", body: Self.libreBody)
        defer { rig.cleanUp() }
        let doc = try ExternalConverterDWGProvider(converter: rig.converter, timeout: 20)
            .read(rig.source, options: .init(), progress: { _ in }, isCancelled: { false })
        #expect(doc.format == "DWG")
        #expect(doc.units == .inches)
        #expect(rig.loggedArguments.first == "-y")
    }

    @Test func stagedCopyMatchesTheSource() throws {
        let rig = try Rig(kind: .odaFileConverter, body: """
        cp "$1/$7" "${ARGS_LOG%.txt}.staged"; cp "$FIXTURE" "$2/drawing.dxf"
        """)
        defer { rig.cleanUp() }
        // The source name has spaces, parentheses and non-ASCII characters; the converter only ever sees drawing.dwg.
        _ = try ExternalDWGConversion.convert(rig.source, with: rig.converter, timeout: 20)
        #expect(rig.loggedArguments.last == "drawing.dwg")
        #expect(try Data(contentsOf: rig.dir.appendingPathComponent("args.staged")) == Data(contentsOf: rig.source))
    }

    @Test func nonZeroExitWithoutOutputReportsTheConverterMessage() throws {
        let rig = try Rig(kind: .odaFileConverter, body: "echo 'File is corrupt' >&2; exit 5")
        defer { rig.cleanUp() }
        let e = try #require(throws: CADError.self) { try ExternalDWGConversion.convert(rig.source, with: rig.converter, timeout: 20) }
        #expect(e.message.contains("did not produce a DXF"))
        #expect(e.message.contains("exit status 5"))
        #expect(e.message.contains("File is corrupt"))
    }

    @Test func errorLogIsReportedWhenNothingIsWritten() throws {
        let rig = try Rig(kind: .odaFileConverter, body: "echo 'Audit failed: bad object' > \"$2/drawing.dwg.err\"; exit 0")
        defer { rig.cleanUp() }
        let e = try #require(throws: CADError.self) { try ExternalDWGConversion.convert(rig.source, with: rig.converter, timeout: 20) }
        #expect(e.message.contains("Audit failed"))
        #expect(!e.message.contains("exit status"))
    }

    @Test func outputDiscoveryIsCaseInsensitiveAndSearchesSubfolders() throws {
        let rig = try Rig(kind: .odaFileConverter, body: "mkdir -p \"$2/sub\"; cp \"$FIXTURE\" \"$2/sub/DRAWING.DXF\"")
        defer { rig.cleanUp() }
        let data = try ExternalDWGConversion.convert(rig.source, with: rig.converter, timeout: 20)
        #expect(DXFReader.looksLikeDXF(data))
    }

    @Test func emptyOrNonDXFOutputIsRejected() throws {
        let empty = try Rig(kind: .libreDWG, body: ": > \"$3\"")
        defer { empty.cleanUp() }
        #expect(throws: CADError.self) { try ExternalDWGConversion.convert(empty.source, with: empty.converter, timeout: 20) }
        let junk = try Rig(kind: .libreDWG, body: "echo 'PK not a drawing' > \"$3\"")
        defer { junk.cleanUp() }
        let e = try #require(throws: CADError.self) { try ExternalDWGConversion.convert(junk.source, with: junk.converter, timeout: 20) }
        #expect(e.message.contains("not a DXF"))
    }

    @Test func timeoutStopsTheConverter() throws {
        let rig = try Rig(kind: .odaFileConverter, body: "sleep 30")
        defer { rig.cleanUp() }
        let start = Date()
        let e = try #require(throws: CADError.self) { try ExternalDWGConversion.convert(rig.source, with: rig.converter, timeout: 0.5) }
        #expect(e.message.contains("did not finish"))
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test func cancellationStopsTheConverter() throws {
        let rig = try Rig(kind: .odaFileConverter, body: "sleep 30")
        defer { rig.cleanUp() }
        let start = Date()
        #expect(throws: CancellationError.self) {
            try ExternalDWGConversion.convert(rig.source, with: rig.converter, timeout: 60, isCancelled: { Date().timeIntervalSince(start) > 0.3 })
        }
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test func missingConverterIsReportedTruthfully() throws {
        let c = ExternalDWGConverter(kind: .libreDWG, executableURL: URL(fileURLWithPath: "/nonexistent/dwg2dxf"))
        let p = ExternalConverterDWGProvider(converter: c)
        #expect(!p.isAvailable)
        #expect(p.unavailableReason?.contains("/nonexistent/dwg2dxf") == true)
        #expect(throws: CADError.self) { try ExternalDWGConversion.convert(URL(fileURLWithPath: "/nonexistent.dwg"), with: c) }
    }

    @Test func detectionFindsBundlesAndHomebrewTools() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("arcus-detect-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        func makeExecutable(_ u: URL) throws {
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\nexit 0\n".write(to: u, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
        }
        let apps = root.appendingPathComponent("Applications")
        let bundle = apps.appendingPathComponent("ODA File Converter 26.4.app")
        try makeExecutable(bundle.appendingPathComponent("Contents/MacOS/ODAFileConverter"))
        let plist: [String: Any] = ["CFBundleExecutable": "ODAFileConverter", "CFBundleShortVersionString": "26.4"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        try fm.createDirectory(at: apps.appendingPathComponent("Other.app/Contents/MacOS"), withIntermediateDirectories: true)
        let brew = root.appendingPathComponent("homebrew/bin/dwg2dxf")
        try makeExecutable(brew)
        let loc = ExternalDWGConverter.SearchLocations(applicationFolders: [apps, root.appendingPathComponent("missing")],
                                                       libreDWGPaths: [brew, root.appendingPathComponent("usr/local/bin/dwg2dxf")])
        let found = ExternalDWGConverter.detect(in: loc)
        #expect(found.map(\.kind) == [.odaFileConverter, .libreDWG])
        #expect(found[0].version == "26.4" && found[0].displayName == "ODA File Converter 26.4")
        #expect(found[0].bundleURL?.lastPathComponent == "ODA File Converter 26.4.app")
        // Nothing installed: nothing found.
        #expect(ExternalDWGConverter.detect(in: .init(applicationFolders: [root.appendingPathComponent("none")], libreDWGPaths: [])).isEmpty)

        // A user-chosen path: the app bundle, the executable inside it, or dwg2dxf.
        #expect(ExternalDWGConverter.at(path: bundle.path)?.kind == .odaFileConverter)
        #expect(ExternalDWGConverter.at(path: bundle.appendingPathComponent("Contents/MacOS/ODAFileConverter").path)?.bundleURL != nil)
        #expect(ExternalDWGConverter.at(path: brew.path)?.kind == .libreDWG)
        #expect(ExternalDWGConverter.at(path: apps.appendingPathComponent("Other.app").path) == nil)
        #expect(ExternalDWGConverter.at(path: "/bin/ls") == nil, "only known converters are run")
        #expect(ExternalDWGConverter.at(path: "  ") == nil)

        // Preferences: a chosen path wins; an invalid choice is reported; detection can be turned off.
        #expect(try DWGConverterPreferences.resolve(chosenPath: brew.path, autoDetect: false, locations: loc)?.get().kind == .libreDWG)
        #expect(try DWGConverterPreferences.resolve(chosenPath: nil, autoDetect: true, locations: loc)?.get().kind == .odaFileConverter)
        #expect(DWGConverterPreferences.resolve(chosenPath: nil, autoDetect: false, locations: loc) == nil)
        let bad = DWGConverterPreferences.resolve(chosenPath: "/nope/ODAFileConverter.app", autoDetect: true, locations: loc)
        guard case .failure(let problem)? = bad else { Issue.record("expected a failure"); return }
        let p = DWGProviders.external(bad)
        #expect(!p.isAvailable)
        #expect(p.unavailableReason?.contains(problem.message) == true)
        #expect(DWGProviders.external(.success(found[1])) is ExternalConverterDWGProvider)
    }

    @Test func unavailableReasonExplainsBothRoutes() throws {
        let r = try #require(UnavailableDWGProvider().unavailableReason)
        #expect(r.contains("ODA File Converter") && r.contains("dwg2dxf") && r.contains("ODA Drawings SDK") && r.contains("DXF"))
    }

    @Test func linkRecordsTheDWGAndReloadConvertsAgain() throws {
        let rig = try Rig(kind: .odaFileConverter, body: Self.odaBody)
        defer { rig.cleanUp() }
        let provider = ExternalConverterDWGProvider(converter: rig.converter, timeout: 20)
        try DWGProviders.$providerOverride.withValue(provider) {
            let (m0, _) = templateModel()
            var o = CADImportOptions()
            o.isLink = true
            let tx = TransactionContext(model: m0, name: "Link DWG")
            let (id, report) = try CADLinkService.place(url: rig.source, bookmark: nil, options: o, projectSurveyOrigin: .zero, in: tx,
                                                        progress: { _ in }, isCancelled: { false })
            let model = try tx.commit().model
            let ld = try #require(model[id]?.link)
            #expect(ld.format == .dwg && ld.isLinked)
            #expect(ld.sourcePath == rig.source.path && ld.sourceName == "Site plan (rev 2) ü.dwg")
            #expect(report.format == "DWG" && report.converted > 0)
            let before = Set(ld.layers.map(\.name))

            // The DWG changes; the next conversion yields a different drawing, and reload converts again.
            try FileManager.default.removeItem(at: rig.dir.appendingPathComponent("fixture.dxf"))
            try FileManager.default.copyItem(at: Fx.url("ac1015_imperial_layouts.dxf"), to: rig.dir.appendingPathComponent("fixture.dxf"))
            try Data("AC1032\u{0}\u{0}edited fake DWG payload, longer".utf8).write(to: rig.source)
            let tx2 = TransactionContext(model: model, name: "Reload")
            let r2 = try CADLinkService.reload(linkElementID: id, from: rig.source, in: tx2, progress: { _ in }, isCancelled: { false })
            let m2 = try tx2.commit().model
            let after = Set(try #require(m2[id]?.link).layers.map(\.name))
            #expect(r2.format == "DWG")
            #expect(after != before)
            #expect(after.contains("A-WALL"))
        }
    }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var v: [Double] = []
    func add(_ x: Double) { lock.lock(); v.append(x); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return v }
}
