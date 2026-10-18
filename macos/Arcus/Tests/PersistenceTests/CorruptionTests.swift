import Foundation
import Testing
@testable import ArcusDomain
@testable import ArcusPersistence

@Suite("Damaged and hostile packages")
struct CorruptionTests {
    /// Writes the rich sample model and returns (tempdir, package url, model).
    func fresh(_ name: String = "Doc.arcus") throws -> (TempDir, URL, BIMModel) {
        let tmp = TempDir()
        let model = try Sample.richModel()
        let url = tmp.file(name)
        try ArcusPackage.write(model, to: url, info: Sample.info)
        return (tmp, url, model)
    }

    func expectKind(_ url: URL, limits: PersistenceLimits = .default, sourceLocation: SourceLocation = #_sourceLocation,
                    _ match: (PersistenceError.Kind) -> Bool) {
        do {
            _ = try ArcusPackage.read(from: url, limits: limits)
            Issue.record("expected a PersistenceError", sourceLocation: sourceLocation)
        } catch let e as PersistenceError {
            #expect(match(e.kind), "unexpected kind \(e.kind): \(e.description)", sourceLocation: sourceLocation)
        } catch {
            Issue.record("unexpected error type \(error)", sourceLocation: sourceLocation)
        }
    }

    func mutate(_ url: URL, _ body: (inout Data) -> Void) throws {
        var d = try Data(contentsOf: url)
        body(&d)
        try d.write(to: url)
    }

    @Test func checksumMismatchInModelIsDetected() throws {
        let (tmp, url, _) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        try mutate(url.appending(path: "model.sqlite")) { $0[$0.count / 2] ^= 0xFF }
        expectKind(url) { $0 == .checksumMismatch("model.sqlite") }
        do { _ = try ArcusPackage.read(from: url) } catch let e as PersistenceError {
            #expect(e.description.contains("Save Recovery Copy"))
            #expect(e.description.contains("Doc.arcus"))
        }
    }

    @Test func checksumMismatchInAssetIsDetected() throws {
        let (tmp, url, _) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        let assets = try FileManager.default.contentsOfDirectory(atPath: url.appending(path: "assets").path)
        try mutate(url.appending(path: "assets/\(assets[0])")) { $0[$0.count - 1] ^= 0x01 }
        expectKind(url) { $0 == .checksumMismatch("assets/\(assets[0])") }
    }

    @Test func truncatedSQLiteIsCorruptNotACrash() throws {
        let (tmp, url, _) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        try mutate(url.appending(path: "model.sqlite")) { $0 = $0.prefix($0.count / 2) }
        // Without re-signing: the checksum catches it first.
        expectKind(url) { if case .checksumMismatch = $0 { true } else { false } }
        // With matching checksums the database layer must still reject it cleanly.
        try ArcusPackage.rewriteChecksums(at: url)
        expectKind(url) { if case .corrupt = $0 { true } else { false } }
    }

    @Test func garbageSQLiteIsCorrupt() throws {
        let (tmp, url, _) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        var rng = SystemRandomNumberGenerator()
        try Data((0..<50_000).map { _ in UInt8.random(in: 0...255, using: &rng) }).write(to: url.appending(path: "model.sqlite"))
        try ArcusPackage.rewriteChecksums(at: url)
        expectKind(url) { if case .corrupt = $0 { true } else { false } }
        try Data().write(to: url.appending(path: "model.sqlite"))
        try ArcusPackage.rewriteChecksums(at: url)
        expectKind(url) { if case .corrupt = $0 { true } else { false } }
    }

    @Test func garbageManifestIsCorrupt() throws {
        let (tmp, url, _) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        try Data("{ this is not json".utf8).write(to: url.appending(path: "manifest.json"))
        expectKind(url) { if case .corrupt = $0 { true } else { false } }
        try Data(String(repeating: "[", count: 100_000).utf8).write(to: url.appending(path: "manifest.json"))
        expectKind(url) { if case .corrupt = $0 { true } else { false } }
        try Data(#"{"format":"com.local.arcus.project"}"#.utf8).write(to: url.appending(path: "manifest.json"))
        expectKind(url) { if case .corrupt = $0 { true } else { false } }
    }

    @Test func notAPackage() throws {
        let tmp = TempDir()
        let plain = tmp.file("plain.arcus")
        try Data("hello".utf8).write(to: plain)
        expectKind(plain) { $0 == .notAPackage }
        let emptyDir = tmp.file("empty.arcus")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        expectKind(emptyDir) { $0 == .notAPackage }
        expectKind(tmp.file("missing.arcus")) { $0 == .notAPackage }
        // A family package is not a project.
        let fam = tmp.file("F.arcusfamily")
        try FamilyPackage.write(StarterLibrary.singleDoor(), thumbnailPNG: nil, to: fam, appVersion: "1", build: "1")
        expectKind(fam) { $0 == .notAPackage }
    }

    func editManifest(_ url: URL, _ body: (inout [String: Any]) -> Void) throws {
        let mURL = url.appending(path: "manifest.json")
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: mURL)) as! [String: Any]
        body(&obj)
        try JSONSerialization.data(withJSONObject: obj).write(to: mURL)
    }

    @Test func newerFormatIsRefusedWithActionableMessage() throws {
        let (tmp, url, _) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        try editManifest(url) { $0["minimumReaderVersion"] = 99; $0["schemaVersion"] = 99; $0["writerAppVersion"] = "9.4.1"; $0["writerBuild"] = "9001" }
        expectKind(url) { $0 == .newerFormat(requiredReader: 99, writtenBy: "9.4.1") }
        do { _ = try ArcusPackage.read(from: url) } catch let e as PersistenceError {
            #expect(e.description.contains("Arcus 9.4.1"))
            #expect(e.description.contains("newer file format"))
            #expect(e.description.contains("not been changed"))
        }
        // readManifest still works so the UI can show who wrote it.
        #expect(try ArcusPackage.readManifest(url).writerAppVersion == "9.4.1")
        #expect(!ArcusPackage.verify(url).isHealthy)
    }

    @Test func newerButCompatibleSchemaStillOpens() throws {
        let (tmp, url, model) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        try editManifest(url) { $0["schemaVersion"] = ArcusPackage.currentSchemaVersion + 1; $0["minimumReaderVersion"] = ArcusPackage.readerVersion; $0["futureField"] = ["x": 1] }
        let (read, manifest) = try ArcusPackage.read(from: url)
        Sample.expectEqual(model, read)
        #expect(ArcusPackage.isNewerThanCurrent(manifest))
    }

    @Test func unsupportedOldSchema() throws {
        let (tmp, url, _) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        try editManifest(url) { $0["schemaVersion"] = 0; $0["minimumReaderVersion"] = 0 }
        expectKind(url) { $0 == .unsupportedSchema(0) }
    }

    @Test func assetPathTraversalIsRejected() throws {
        let (tmp, url, _) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        for evil in ["../../../etc/passwd", "a/b.lzfse", "..", ".hidden", "x\\y", "/abs.lzfse", "c:d"] {
            let json = try JSONSerialization.data(withJSONObject: ["ref-x": evil])
            let hex = json.map { String(format: "%02x", $0) }.joined()
            try RawSQLite.exec(url.appending(path: "model.sqlite"), "UPDATE project SET data = X'\(hex)' WHERE key = 'referenceDrawings'")
            try ArcusPackage.rewriteChecksums(at: url)
            expectKind(url) { if case .corrupt(let s) = $0 { s.contains("invalid asset name") } else { false } }
        }
        // Manifest checksum paths are validated too.
        try editManifest(url) { m in
            var sums = m["checksums"] as! [String: String]
            sums["../outside.txt"] = String(repeating: "0", count: 64)
            m["checksums"] = sums
        }
        expectKind(url) { if case .corrupt = $0 { true } else { false } }
    }

    @Test func symlinkedModelIsRefused() throws {
        let (tmp, url, _) = try fresh()
        let outside = tmp.file("outside.sqlite")
        try FileManager.default.moveItem(at: url.appending(path: "model.sqlite"), to: outside)
        try FileManager.default.createSymbolicLink(at: url.appending(path: "model.sqlite"), withDestinationURL: outside)
        expectKind(url) { if case .corrupt = $0 { true } else { false } }
    }

    @Test func decompressionBombIsRejected() throws {
        let (tmp, url, _) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        let assets = try FileManager.default.contentsOfDirectory(atPath: url.appending(path: "assets").path)
        // 200 MB of zeros compresses to a few KB: ratio far above the limit.
        let bomb = try AssetCodec.encode(Data(count: 200 << 20), algorithm: .lzfse)
        #expect(bomb.count < 1 << 20)
        try bomb.write(to: url.appending(path: "assets/\(assets[0])"))
        try ArcusPackage.rewriteChecksums(at: url)
        expectKind(url) { if case .limitExceeded = $0 { true } else { false } }
    }

    @Test func assetCodecBoundsOutput() throws {
        let payload = Data((0..<100_000).map { UInt8($0 % 251) })
        for alg in [AssetCodec.Algorithm.lzfse, .zlib] {
            let packed = try AssetCodec.encode(payload, algorithm: alg)
            #expect(try AssetCodec.decode(packed, limits: .default) == payload)
            // Header lies about the size: decoding stops at the declared size.
            var lying = packed
            lying[8] = 0x10; lying[9] = 0; lying[10] = 0; lying[11] = 0
            #expect(throws: AssetCodec.DecodeError.self) { try AssetCodec.decode(lying, limits: .default) }
            // Truncated stream.
            #expect(throws: AssetCodec.DecodeError.self) { try AssetCodec.decode(packed.prefix(packed.count / 2), limits: .default) }
        }
        var tiny = PersistenceLimits()
        tiny.maxAssetBytes = 1_000
        #expect(throws: AssetCodec.DecodeError.self) { try AssetCodec.decode(try AssetCodec.encode(payload), limits: tiny) }
        #expect(throws: AssetCodec.DecodeError.self) { try AssetCodec.decode(Data("PLZ1".utf8), limits: .default) }
        #expect(throws: AssetCodec.DecodeError.self) { try AssetCodec.decode(Data("NOPE000000000000xxxx".utf8), limits: .default) }
    }

    @Test func elementCountAndDepthLimits() throws {
        let (tmp, url, model) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        var few = PersistenceLimits()
        few.maxElements = 10
        expectKind(url, limits: few) { if case .limitExceeded = $0 { true } else { false } }
        var shallow = PersistenceLimits()
        shallow.maxJSONDepth = 3
        expectKind(url, limits: shallow) { if case .limitExceeded = $0 { true } else { false } }
        var smallBlobs = PersistenceLimits()
        smallBlobs.maxElementBytes = 64
        expectKind(url, limits: smallBlobs) { if case .limitExceeded = $0 { true } else { false } }
        // Defaults read fine.
        #expect(try ArcusPackage.read(from: url).model.count == model.count)
    }

    @Test func deeplyNestedElementJSONIsRejected() throws {
        let (tmp, url, _) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        let deep = String(repeating: "[", count: 5_000) + String(repeating: "]", count: 5_000)
        try RawSQLite.exec(url.appending(path: "model.sqlite"), "UPDATE elements SET data = CAST('\(deep)' AS BLOB) WHERE id = 1")
        try ArcusPackage.rewriteChecksums(at: url)
        expectKind(url) { if case .limitExceeded = $0 { true } else { false } }
    }

    @Test func undecodableElementIsCorruptAndNamed() throws {
        let (tmp, url, _) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        try RawSQLite.exec(url.appending(path: "model.sqlite"), "UPDATE elements SET data = CAST('{\"id\": 5}' AS BLOB) WHERE id = 5")
        try ArcusPackage.rewriteChecksums(at: url)
        expectKind(url) { if case .corrupt(let s) = $0 { s.contains("#5") } else { false } }
        let r = ArcusPackage.verify(url)
        #expect(!r.isHealthy)
        #expect(r.lostElements == 1)
        #expect(r.problems.contains { $0.contains("#5") })
    }

    @Test func mismatchedRowIDIsCorrupt() throws {
        let (tmp, url, model) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        let other = model.allElements[10]
        try RawSQLite.exec(url.appending(path: "model.sqlite"), "UPDATE elements SET data = (SELECT data FROM elements WHERE id = \(other.id.raw)) WHERE id = \(model.allElements[3].id.raw)")
        try ArcusPackage.rewriteChecksums(at: url)
        expectKind(url) { if case .corrupt = $0 { true } else { false } }
    }

    @Test func recoveryCopyFromDamagedElement() throws {
        let (tmp, url, model) = try fresh()
        let victim = model.elements(.walls).first!.id
        try RawSQLite.exec(url.appending(path: "model.sqlite"), "UPDATE elements SET data = X'DEADBEEF' WHERE id = \(victim.raw)")
        // Checksum no longer matches: normal open refuses, recovery copy proceeds.
        expectKind(url) { if case .checksumMismatch = $0 { true } else { false } }
        let dest = tmp.file("Doc (Recovered).arcus")
        var info = Sample.info
        info.documentID = UUID()
        let report = try ArcusPackage.saveRecoveryCopy(from: url, to: dest, info: info)
        #expect(report.recoveredElements == model.count - 1)
        #expect(report.lostElements == 1)
        #expect(!report.isHealthy)
        #expect(report.problems.contains { $0.contains("checksum") })
        let (copy, manifest) = try ArcusPackage.read(from: dest)
        #expect(copy.count == model.count - 1)
        #expect(copy[victim] == nil)
        #expect(copy.referenceDrawings == model.referenceDrawings)
        #expect(copy.projectParameters == model.projectParameters)
        #expect(manifest.documentID == info.documentID)
        // Everything else survived unchanged.
        for e in copy.allElements { #expect(model[e.id] == e) }
        // The damaged original is untouched.
        #expect(FileManager.default.fileExists(atPath: url.appending(path: "model.sqlite").path))
    }

    @Test func recoveryCopyFromTruncatedDatabase() throws {
        let (tmp, url, model) = try fresh()
        try mutate(url.appending(path: "model.sqlite")) { $0 = $0.prefix($0.count * 6 / 10) }
        let dest = tmp.file("Recovered.arcus")
        let report = try ArcusPackage.saveRecoveryCopy(from: url, to: dest, info: Sample.info)
        #expect(!report.isHealthy)
        #expect(report.recoveredElements + report.lostElements == model.count)
        let copy = try ArcusPackage.read(from: dest).model
        #expect(copy.count == report.recoveredElements)
        for e in copy.allElements { #expect(model[e.id] == e) }
    }

    @Test func recoveryCopyFromGarbageStillProducesADocument() throws {
        let (tmp, url, model) = try fresh()
        try Data(repeating: 0x41, count: 4096).write(to: url.appending(path: "model.sqlite"))
        try Data("garbage".utf8).write(to: url.appending(path: "manifest.json"))
        let dest = tmp.file("R.arcus")
        let report = try ArcusPackage.saveRecoveryCopy(from: url, to: dest, info: Sample.info)
        #expect(report.recoveredElements == 0)
        #expect(!report.problems.isEmpty)
        #expect(try ArcusPackage.read(from: dest).model.count == 0)
        _ = model
    }

    @Test func verifyReportsForeignKeyAndRelationProblems() throws {
        let (tmp, url, _) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        try RawSQLite.exec(url.appending(path: "model.sqlite"), "INSERT INTO relations(element_id, related_id, role) VALUES (1, 999999, 'host')")
        try ArcusPackage.rewriteChecksums(at: url)
        let r = ArcusPackage.verify(url)
        #expect(!r.isHealthy)
        #expect(r.problems.contains { $0.contains("Foreign key") })
        #expect(r.problems.contains { $0.contains("relations table") })
    }

    @Test func verifyReportsDanglingReferences() throws {
        let (tmp, _, model) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        // Build a model whose door refers to a host that does not exist.
        var door = model.elements(.doors).first!
        door.hostID = ElementID(987_654)
        var elements = model.allElements.filter { $0.id != door.id }
        elements.append(door)
        let broken = BIMModel(elements: elements, nextID: model.nextID, referenceDrawings: model.referenceDrawings)
        let url = tmp.file("Dangling.arcus")
        try ArcusPackage.write(broken, to: url, info: Sample.info)
        // Reading is lenient (the model layer reports health), verification flags it.
        #expect(try ArcusPackage.read(from: url).model[door.id]?.hostID == ElementID(987_654))
        let r = ArcusPackage.verify(url)
        #expect(r.problems.contains { $0.contains("missing element #987654") })
    }

    @Test func verifyDetectsChecksumAndUnlistedAssets() throws {
        let (tmp, url, _) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        try Data("x".utf8).write(to: url.appending(path: "assets/extra.lzfse"))
        try mutate(url.appending(path: "model.sqlite")) { $0[100] ^= 1 }
        let r = ArcusPackage.verify(url)
        #expect(r.problems.contains { $0.contains("model.sqlite doesn’t match") })
        #expect(r.problems.contains { $0.contains("not listed") })
    }

    @Test func wrapperWithGarbageIsCorrupt() throws {
        let fw = FileWrapper(directoryWithFileWrappers: [:])
        let m = PackageManifest(format: PackageManifest.projectFormat, schemaVersion: 2, minimumReaderVersion: 2, writerAppVersion: "1", writerBuild: "1",
                                documentID: UUID(), created: Date(), modified: Date(), elementCount: 0,
                                checksums: ["model.sqlite": Checksum.hex(Data("nope".utf8))])
        let mf = FileWrapper(regularFileWithContents: try m.encoded()); mf.preferredFilename = "manifest.json"
        let db = FileWrapper(regularFileWithContents: Data("nope".utf8)); db.preferredFilename = "model.sqlite"
        fw.addFileWrapper(mf); fw.addFileWrapper(db)
        #expect(throws: PersistenceError.self) { try ArcusPackage.read(fileWrapper: fw) }
        do { _ = try ArcusPackage.read(fileWrapper: fw) } catch let e as PersistenceError {
            if case .corrupt = e.kind {} else { Issue.record("expected corrupt, got \(e.kind)") }
        }
    }

    @Test func writeIntoMissingDirectoryFailsCleanly() throws {
        let tmp = TempDir()
        let url = tmp.url.appending(path: "no/such/dir/X.arcus")
        #expect(throws: PersistenceError.self) { try ArcusPackage.write(BIMModel(), to: url, info: Sample.info) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func invalidIFCGUIDIsRejectedAndRepairedInRecoveryCopy() throws {
        let (tmp, url, model) = try fresh()
        defer { withExtendedLifetime(tmp) {} }
        let victim = model.elements(.walls).first!
        let json = String(decoding: try StoredJSON.encoder().encode(victim), as: UTF8.self)
            .replacingOccurrences(of: victim.ifcGUID.value, with: "bad")
        let hex = Data(json.utf8).map { String(format: "%02x", $0) }.joined()
        try RawSQLite.exec(url.appending(path: "model.sqlite"), "UPDATE elements SET data = X'\(hex)' WHERE id = \(victim.id.raw)")
        try ArcusPackage.rewriteChecksums(at: url)
        expectKind(url) { if case .corrupt(let s) = $0 { s.contains("IFC GUID") } else { false } }
        #expect(ArcusPackage.verify(url).problems.contains { $0.contains("IFC GUID") })
        let dest = tmp.file("Fixed.arcus")
        let report = try ArcusPackage.saveRecoveryCopy(from: url, to: dest, info: Sample.info)
        #expect(report.recoveredElements == model.count)
        #expect(report.lostElements == 0)
        #expect(report.problems.contains { $0.contains("new one was assigned") })
        let fixed = try ArcusPackage.read(from: dest).model[victim.id]
        #expect(fixed.map { IFCGUID($0.ifcGUID.value) != nil } == true)
    }
}
