import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusPersistence
@testable import ArcusServices

@Suite("Recovery journal")
struct RecoveryJournalTests {
    /// Live editing session: a model mutated by transactions whose records are journaled.
    final class Session {
        var model: BIMModel
        var records: [TransactionRecord] = []
        let ids: ProjectTemplates.Ids
        init() {
            let (m, ids) = ProjectTemplates.make(.architectural, units: .metric)
            model = m; self.ids = ids
        }
        @discardableResult
        func edit(_ name: String, _ body: (TransactionContext) -> Void) throws -> TransactionRecord {
            let tx = TransactionContext(model: model, name: name)
            body(tx)
            let r = try tx.commit()
            model = r.model
            records.append(r.record)
            return r.record
        }
        /// A representative mix: creates, updates, deletes, drawings, project parameters, sheet sets.
        func typicalEdits(journal: RecoveryJournal, id: UUID) async throws {
            let l1 = ids.levels[0], l2 = ids.levels[1]
            let wt = ids.wallTypes["Generic - 200mm"]!
            var walls: [ElementID] = []
            let r1 = try edit("Walls") { tx in
                for i in 0..<5 {
                    walls.append(tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(Double(i) * 4, 0), Vec2(Double(i) * 4 + 3, 0))), topLevelID: l2)),
                                           typeID: wt, levelID: l1))
                }
            }
            try await journal.append(r1, documentID: id, model: model)
            let r2 = try edit("Mark") { tx in tx.update(walls[1]) { $0.mark = "W-2"; $0.comments = "∆ changed" } }
            try await journal.append(r2, documentID: id, model: model)
            let r3 = try edit("Delete") { tx in tx.delete(walls[4]) }
            try await journal.append(r3, documentID: id, model: model)
            let r4 = try edit("Import") { tx in tx.addReferenceDrawing(Sample.drawing(3)) }
            try await journal.append(r4, documentID: id, model: model)
            let r5 = try edit("Params") { tx in
                tx.setProjectParameters([ParameterDefinition(name: "Zone", type: .text, categories: [.walls])])
                tx.setViewSheetSets([ViewSheetSet(name: "Set", members: [])])
            }
            try await journal.append(r5, documentID: id, model: model)
            // Undo of the mark change is journaled as the inverse record.
            model.apply(r2.inverse)
            try await journal.append(r2.inverse, documentID: id)
        }
    }

    func journal(_ tmp: TempDir) -> RecoveryJournal {
        RecoveryJournal(baseDirectory: tmp.url.appending(path: "Recovery", directoryHint: .isDirectory),
                        log: DiagnosticsLog(capacity: 200), syncInterval: .milliseconds(50))
    }

    @Test func untitledDocumentReplaysExactlyAfterCrash() async throws {
        let tmp = TempDir()
        let s = Session()
        let id = UUID()
        let j1 = journal(tmp)
        try await j1.begin(documentID: id, displayName: "Untitled 3", savedURL: nil, baseModel: s.model, info: Sample.info)
        try await s.typicalEdits(journal: j1, id: id)
        try await j1.flush(documentID: id)
        // Simulated crash: a new process (journal instance) finds the leftover session.
        let j2 = journal(tmp)
        let pending = await j2.pendingRecoveries()
        #expect(pending.count == 1)
        let item = try #require(pending.first)
        #expect(item.id == id)
        #expect(item.displayName == "Untitled 3")
        #expect(item.savedPath == nil)
        #expect(item.changeCount == 6)
        #expect(item.problem == nil)
        let result = try await j2.recoverWithReport(item)
        #expect(result.warnings.isEmpty, "\(result.warnings)")
        #expect(result.savedURL == nil)
        #expect(result.replayedRecords == 6)
        Sample.expectEqual(s.model, result.model)
        #expect(result.model.referenceDrawings.count == 1)
        // Recovery doesn't delete the journal until the app discards or ends it.
        #expect(await j2.pendingRecoveries().count == 1)
        try await j2.discard(item)
        #expect(await j2.pendingRecoveries().isEmpty)
    }

    @Test func savedDocumentReplaysOnTopOfSavedFileWithoutTouchingIt() async throws {
        let tmp = TempDir()
        let s = Session()
        let url = tmp.file("Tower.arcus")
        try ArcusPackage.write(s.model, to: url, info: Sample.info)
        let before = try Data(contentsOf: url.appending(path: "model.sqlite"))
        let fp = try #require(ExternalChangeDetector.fingerprint(url))
        let id = Sample.info.documentID
        let j1 = journal(tmp)
        try await j1.begin(documentID: id, displayName: "Tower", savedURL: url, baseModel: s.model, info: Sample.info)
        #expect(!FileManager.default.fileExists(atPath: tmp.url.appending(path: "Recovery/\(id.uuidString)/base.arcus").path))
        try await s.typicalEdits(journal: j1, id: id)
        try await j1.flush(documentID: id)
        let j2 = journal(tmp)
        let item = try #require(await j2.pendingRecoveries().first)
        #expect(item.savedPath == url.path)
        let (model, savedURL, name) = try await j2.recover(item)
        Sample.expectEqual(s.model, model)
        #expect(savedURL?.standardizedFileURL == url.standardizedFileURL)
        #expect(name == "Tower")
        #expect(try Data(contentsOf: url.appending(path: "model.sqlite")) == before)
        #expect(!ExternalChangeDetector.hasChanged(url, since: fp))
    }

    @Test func markSavedPrunesRecords() async throws {
        let tmp = TempDir()
        let s = Session()
        let id = UUID()
        let j = journal(tmp)
        try await j.begin(documentID: id, displayName: "Untitled", savedURL: nil, baseModel: s.model, info: Sample.info)
        try await s.typicalEdits(journal: j, id: id)
        let url = tmp.file("Saved.arcus")
        try ArcusPackage.write(s.model, to: url, info: Sample.info)
        try await j.markSaved(documentID: id, savedURL: url, model: s.model)
        let folder = tmp.url.appending(path: "Recovery/\(id.uuidString)")
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "base.arcus").path))
        let size = try FileManager.default.attributesOfItem(atPath: folder.appending(path: "journal.bin").path)[.size] as? Int
        #expect(size == 8)
        // Crash right after saving: nothing to recover, and the stale session is cleaned up.
        #expect(await journal(tmp).pendingRecoveries().isEmpty)
    }

    @Test func editsAfterSaveReplayOnSavedFile() async throws {
        let tmp = TempDir()
        let s = Session()
        let id = UUID()
        let j = journal(tmp)
        try await j.begin(documentID: id, displayName: "Untitled", savedURL: nil, baseModel: s.model, info: Sample.info)
        try await s.typicalEdits(journal: j, id: id)
        let url = tmp.file("Saved.arcus")
        try ArcusPackage.write(s.model, to: url, info: Sample.info)
        try await j.markSaved(documentID: id, savedURL: url, model: s.model)
        let r = try s.edit("After save") { tx in
            let w = tx.model.elements(.walls).first!.id
            tx.update(w) { $0.mark = "after" }
        }
        try await j.append(r, documentID: id)
        try await j.flush(documentID: id)
        let item = try #require(await journal(tmp).pendingRecoveries().first)
        #expect(item.changeCount == 1)
        #expect(item.displayName == "Saved")
        let rec = try await journal(tmp).recover(item)
        Sample.expectEqual(s.model, rec.model)
        #expect(rec.savedURL?.lastPathComponent == "Saved.arcus")
    }

    @Test func endDeletesJournal() async throws {
        let tmp = TempDir()
        let s = Session()
        let id = UUID()
        let j = journal(tmp)
        try await j.begin(documentID: id, displayName: "Doc", savedURL: nil, baseModel: s.model, info: Sample.info)
        try await s.typicalEdits(journal: j, id: id)
        try await j.end(documentID: id)
        #expect(!FileManager.default.fileExists(atPath: tmp.url.appending(path: "Recovery/\(id.uuidString)").path))
        #expect(await journal(tmp).pendingRecoveries().isEmpty)
        await #expect(throws: PersistenceError.self) { try await j.append(s.records[0], documentID: id) }
    }

    @Test func truncatedLastRecordIsIgnoredWithWarning() async throws {
        let tmp = TempDir()
        let s = Session()
        let id = UUID()
        let j = journal(tmp)
        try await j.begin(documentID: id, displayName: "Crashy", savedURL: nil, baseModel: s.model, info: Sample.info)
        try await s.typicalEdits(journal: j, id: id)
        try await j.flush(documentID: id)
        let expected = s.model
        // One more change whose frame is cut off mid-write (the process died during append).
        try s.edit("Lost") { tx in tx.update(tx.model.elements(.walls).first!.id) { $0.mark = "lost" } }
        let journalURL = tmp.url.appending(path: "Recovery/\(id.uuidString)/journal.bin")
        let full = try Data(contentsOf: journalURL)
        try await j.append(s.records.last!, documentID: id)
        try await j.flush(documentID: id)
        let withLast = try Data(contentsOf: journalURL)
        let partial = withLast.prefix(full.count + (withLast.count - full.count) / 2)
        try partial.write(to: journalURL)
        let item = try #require(await journal(tmp).pendingRecoveries().first)
        #expect(item.changeCount == 6)
        #expect(item.problem?.contains("partly written") == true)
        let result = try await journal(tmp).recoverWithReport(item)
        #expect(result.replayedRecords == 6)
        #expect(result.warnings.contains { $0.contains("partly written") })
        Sample.expectEqual(expected, result.model)
        // Only the header of the next frame made it to disk.
        try withLast.prefix(full.count + 5).write(to: journalURL)
        Sample.expectEqual(expected, try await journal(tmp).recover(item).model)
    }

    @Test func damagedRecordStopsReplayAtLastGoodRecord() async throws {
        let tmp = TempDir()
        let s = Session()
        let id = UUID()
        let j = journal(tmp)
        try await j.begin(documentID: id, displayName: "Bitrot", savedURL: nil, baseModel: s.model, info: Sample.info)
        let base = s.model
        let r1 = try s.edit("One") { tx in tx.update(tx.model.elements(.levels).first!.id) { $0.name = "Ground" } }
        try await j.append(r1, documentID: id)
        let afterOne = s.model
        let r2 = try s.edit("Two") { tx in tx.update(tx.model.elements(.levels).first!.id) { $0.name = "Ground 2" } }
        try await j.append(r2, documentID: id)
        try await j.flush(documentID: id)
        let url = tmp.url.appending(path: "Recovery/\(id.uuidString)/journal.bin")
        var d = try Data(contentsOf: url)
        d[d.count - 3] ^= 0xFF
        try d.write(to: url)
        let item = try #require(await journal(tmp).pendingRecoveries().first)
        let result = try await journal(tmp).recoverWithReport(item)
        #expect(result.replayedRecords == 1)
        #expect(result.warnings.contains { $0.contains("damaged") })
        Sample.expectEqual(afterOne, result.model)
        _ = base
    }

    @Test func pendingRecoveriesAreSortedAndExcludeOwnOpenSessions() async throws {
        let tmp = TempDir()
        let s = Session()
        let j = journal(tmp)
        let a = UUID(), b = UUID(), c = UUID()
        for (id, name) in [(a, "A"), (b, "B"), (c, "C")] {
            try await j.begin(documentID: id, displayName: name, savedURL: nil, baseModel: s.model, info: Sample.info)
        }
        let rec = try s.edit("x") { tx in tx.update(tx.model.elements(.levels).first!.id) { $0.name = "L" } }
        func stamped(_ r: TransactionRecord, _ t: TimeInterval) -> TransactionRecord {
            TransactionRecord(id: r.id, name: r.name, timestamp: Date(timeIntervalSince1970: t), changes: r.changes, project: r.project,
                              addedDrawings: r.addedDrawings, nextIDAfter: r.nextIDAfter)
        }
        try await j.append(stamped(rec, 1_000), documentID: a)
        try await j.append(stamped(rec, 3_000), documentID: b)
        try await j.append(stamped(rec, 2_000), documentID: c)
        for id in [a, b, c] { try await j.flush(documentID: id) }
        // The instance that owns the sessions doesn't offer them for recovery.
        #expect(await j.pendingRecoveries().isEmpty)
        try await j.end(documentID: c)
        let other = journal(tmp)
        let items = await other.pendingRecoveries()
        #expect(items.map(\.displayName) == ["B", "A"])
        #expect(items.first?.lastChange == Date(timeIntervalSince1970: 3_000))
    }

    @Test func externallyChangedSavedFileIsNotReplayed() async throws {
        let tmp = TempDir()
        let s = Session()
        let url = tmp.file("Shared.arcus")
        try ArcusPackage.write(s.model, to: url, info: Sample.info)
        let id = UUID()
        let j = journal(tmp)
        try await j.begin(documentID: id, displayName: "Shared", savedURL: url, baseModel: s.model, info: Sample.info)
        try await s.typicalEdits(journal: j, id: id)
        try await j.flush(documentID: id)
        // Someone else saves over the file (new manifest modified date).
        try await Task.sleep(for: .milliseconds(5))
        try ArcusPackage.write(BIMModel(), to: url, info: Sample.info)
        let other = journal(tmp)
        let item = try #require(await other.pendingRecoveries().first)
        #expect(item.problem?.contains("was changed") == true)
        await #expect(throws: PersistenceError.self) { try await other.recover(item) }
        // Journal kept; saved file untouched by the failed recovery.
        #expect(await other.pendingRecoveries().count == 1)
        #expect(try ArcusPackage.read(from: url).model.count == 0)
    }

    @Test func missingSavedFileIsFoundThroughBookmark() async throws {
        let tmp = TempDir()
        let s = Session()
        let url = tmp.file("Moving.arcus")
        try ArcusPackage.write(s.model, to: url, info: Sample.info)
        let id = UUID()
        let j = journal(tmp)
        try await j.begin(documentID: id, displayName: "Moving", savedURL: url, baseModel: s.model, info: Sample.info)
        try await s.typicalEdits(journal: j, id: id)
        try await j.flush(documentID: id)
        let moved = tmp.file("Moved Elsewhere.arcus")
        try FileManager.default.moveItem(at: url, to: moved)
        let other = journal(tmp)
        let item = try #require(await other.pendingRecoveries().first)
        #expect(item.problem == nil, "\(item.problem ?? "")")
        let rec = try await other.recover(item)
        Sample.expectEqual(s.model, rec.model)
        #expect(rec.savedURL?.lastPathComponent == "Moved Elsewhere.arcus")
    }

    @Test func manyAppendsAreFastAndCoalesced() async throws {
        let tmp = TempDir()
        let s = Session()
        let id = UUID()
        let j = journal(tmp)
        try await j.begin(documentID: id, displayName: "Busy", savedURL: nil, baseModel: s.model, info: Sample.info)
        let level = s.model.elements(.levels).first!.id
        var recs: [TransactionRecord] = []
        for i in 0..<300 { recs.append(try s.edit("n\(i)") { tx in tx.update(level) { $0.name = "L\(i)" } }) }
        let clock = ContinuousClock()
        let t = try await clock.measure {
            for r in recs { try await j.append(r, documentID: id) }
        }
        #expect(t < .seconds(5))
        try await j.flush(documentID: id)
        let session = try JSONSerialization.jsonObject(with: Data(contentsOf: tmp.url.appending(path: "Recovery/\(id.uuidString)/session.json"))) as! [String: Any]
        #expect(session["changeCount"] as? Int == 300)
        #expect(session["cleanShutdown"] as? Bool == false)
        let item = try #require(await journal(tmp).pendingRecoveries().first)
        Sample.expectEqual(s.model, try await journal(tmp).recover(item).model)
    }

    @Test func crc32KnownVector() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data()) == 0)
    }
}
