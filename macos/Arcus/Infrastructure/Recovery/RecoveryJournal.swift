import Foundation
import ArcusDomain
import ArcusPersistence

/// A document with unsaved work left behind by an abnormal termination.
public struct RecoveryItem: Sendable, Identifiable, Hashable {
    /// The document's identifier (also the journal folder name).
    public var id: UUID
    public var displayName: String
    /// Path of the saved file the edits apply to (nil for untitled documents).
    public var savedPath: String?
    public var lastChange: Date
    /// Number of complete journal records.
    public var changeCount: Int
    /// Why recovery may fail or be incomplete (saved file missing or changed since, base snapshot missing…).
    public var problem: String?

    public init(id: UUID, displayName: String, savedPath: String?, lastChange: Date, changeCount: Int, problem: String? = nil) {
        self.id = id; self.displayName = displayName; self.savedPath = savedPath; self.lastChange = lastChange
        self.changeCount = changeCount; self.problem = problem
    }
}

/// Result of replaying a journal.
public struct RecoveryResult: Sendable {
    public var model: BIMModel
    public var savedURL: URL?
    public var displayName: String
    public var replayedRecords: Int
    /// Non-fatal issues (e.g. a truncated final record that was ignored).
    public var warnings: [String]
}

/// Crash-recovery journal. One folder per open document under `baseDirectory`:
///
/// ```
/// <base>/<documentID>/session.json   identity, display name, saved-file identity, counters, cleanShutdown
/// <base>/<documentID>/base.arcus    snapshot package (untitled documents only)
/// <base>/<documentID>/journal.bin    "PLNTJRN1" header + frames [u32 length][u32 crc32][JSON JournalEntry]
/// ```
/// Records are written immediately (they survive an app crash) and fsync'd lazily, coalesced to at most about once
/// per second, or on `flush`. Replay applies records with `BIMModel.apply` on top of the base.
public actor RecoveryJournal {
    public let baseDirectory: URL
    private var open: [UUID: OpenSession] = [:]
    private let log: DiagnosticsLog
    /// Coalescing window for fsync.
    public let syncInterval: Duration

    static let header = Data("PLNTJRN1".utf8)
    static let maxFrameBytes = 1 << 30

    public init(baseDirectory: URL) {
        self.init(baseDirectory: baseDirectory, log: .shared, syncInterval: .seconds(1))
    }

    public init(baseDirectory: URL, log: DiagnosticsLog, syncInterval: Duration = .seconds(1)) {
        self.baseDirectory = baseDirectory
        self.log = log
        self.syncInterval = syncInterval
    }

    // MARK: Session data

    struct SessionInfo: Codable, Sendable {
        var formatVersion = 1
        var documentID: UUID
        var displayName: String
        var savedPath: String?
        var savedBookmark: Data?
        var savedFingerprint: FileFingerprint?
        var hasBase: Bool
        var baseRevision: UInt64
        var created: Date
        var lastChange: Date
        var changeCount: Int
        var cleanShutdown: Bool
        var pid: Int32
        var appVersion: String
    }

    struct JournalEntry: Codable {
        var v = 1
        var record: TransactionRecord
        /// Content of drawings the record added (records carry only keys).
        var drawings: [String: ReferenceDrawing]?
    }

    final class OpenSession {
        var info: SessionInfo
        let handle: FileHandle
        var dirty = false
        var lastSync = ContinuousClock.now
        var syncScheduled = false
        init(info: SessionInfo, handle: FileHandle) { self.info = info; self.handle = handle }
    }

    private func folder(_ id: UUID) -> URL { baseDirectory.appending(path: id.uuidString, directoryHint: .isDirectory) }
    private func sessionURL(_ id: UUID) -> URL { folder(id).appending(path: "session.json") }
    private func baseURL(_ id: UUID) -> URL { folder(id).appending(path: "base.arcus", directoryHint: .isDirectory) }
    private func journalURL(_ id: UUID) -> URL { folder(id).appending(path: "journal.bin") }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return d
    }

    private func writeSession(_ info: SessionInfo) throws {
        let data = try Self.encoder().encode(info)
        try data.write(to: sessionURL(info.documentID), options: .atomic)
    }

    private func readSession(_ id: UUID) throws -> SessionInfo {
        let data = try Data(contentsOf: sessionURL(id))
        guard data.count < 1 << 20 else { throw PersistenceError(.limitExceeded("session.json"), "The recovery session file is too large.") }
        return try Self.decoder().decode(SessionInfo.self, from: data)
    }

    // MARK: Lifecycle

    /// Starts (or restarts) journaling for a document. Untitled documents get a `base.arcus` snapshot of
    /// `baseModel`; saved documents record the saved file's identity (path, bookmark, fingerprint).
    public func begin(documentID: UUID, displayName: String, savedURL: URL?, baseModel: BIMModel, info: ArcusPackage.WriteInfo) throws {
        if let s = open.removeValue(forKey: documentID) { try? s.handle.close() }
        let fm = FileManager.default
        let dir = folder(documentID)
        try? fm.removeItem(at: dir)
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            throw PersistenceError(.io(error.localizedDescription), "Arcus couldn’t create its recovery folder: \(error.localizedDescription)")
        }
        var session = SessionInfo(documentID: documentID, displayName: displayName, hasBase: savedURL == nil, baseRevision: baseModel.revision,
                                  created: Date(), lastChange: Date(), changeCount: 0, cleanShutdown: false,
                                  pid: ProcessInfo.processInfo.processIdentifier, appVersion: info.appVersion)
        if let savedURL {
            setSaved(&session, savedURL)
        } else {
            try Signposts.interval("Recovery base snapshot", log: log) {
                try ArcusPackage.write(baseModel, to: baseURL(documentID), info: info)
            }
        }
        try writeSession(session)
        let handle = try createJournal(documentID)
        open[documentID] = OpenSession(info: session, handle: handle)
        log.log("Recovery", "Journal started for document \(documentID) (\(savedURL == nil ? "untitled, snapshot" : "saved file identity"))")
    }

    private func setSaved(_ session: inout SessionInfo, _ url: URL) {
        session.savedPath = url.path
        session.savedBookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        session.savedFingerprint = ExternalChangeDetector.fingerprint(url)
        session.hasBase = false
    }

    private func createJournal(_ id: UUID) throws -> FileHandle {
        let url = journalURL(id)
        guard FileManager.default.createFile(atPath: url.path, contents: Self.header) else {
            throw PersistenceError(.io("create journal"), "Arcus couldn’t create its recovery journal.")
        }
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        return h
    }

    private func session(_ id: UUID) throws -> OpenSession {
        guard let s = open[id] else {
            throw PersistenceError(.io("no session"), "No recovery journal is open for this document.")
        }
        return s
    }

    /// Appends one committed record. Also append undo (inverse) and redo records so replay reproduces the model.
    public func append(_ record: TransactionRecord, documentID: UUID) throws {
        try append(record, documentID: documentID, drawings: [:])
    }

    /// Appends a record together with the content of the reference drawings it added (`record.addedDrawings`),
    /// which records carry only by key. Pass `model.referenceDrawings` filtered to those keys.
    public func append(_ record: TransactionRecord, documentID: UUID, drawings: [String: ReferenceDrawing]) throws {
        let s = try session(documentID)
        var added: [String: ReferenceDrawing] = [:]
        for k in record.addedDrawings { if let d = drawings[k] { added[k] = d } }
        let payload = try Self.encoder().encode(JournalEntry(record: record, drawings: added.isEmpty ? nil : added))
        guard payload.count <= Self.maxFrameBytes else {
            throw PersistenceError(.limitExceeded("journal record"), "A change was too large to journal for crash recovery.")
        }
        var frame = Data(capacity: payload.count + 8)
        appendLE(&frame, UInt32(payload.count))
        appendLE(&frame, CRC32.checksum(payload))
        frame.append(payload)
        do { try s.handle.write(contentsOf: frame) } catch {
            throw PersistenceError(.io(error.localizedDescription), "Arcus couldn’t write its recovery journal: \(error.localizedDescription)")
        }
        s.info.changeCount += 1
        s.info.lastChange = record.timestamp
        s.dirty = true
        scheduleSync(documentID, s)
    }

    /// Convenience: appends a record, taking added drawing content from the post-commit model.
    public func append(_ record: TransactionRecord, documentID: UUID, model: BIMModel) throws {
        try append(record, documentID: documentID, drawings: model.referenceDrawings.filter { record.addedDrawings.contains($0.key) })
    }

    private func scheduleSync(_ id: UUID, _ s: OpenSession) {
        let elapsed = ContinuousClock.now - s.lastSync
        if elapsed >= syncInterval {
            try? sync(s)
            return
        }
        guard !s.syncScheduled else { return }
        s.syncScheduled = true
        let wait = syncInterval - elapsed
        Task { [weak self] in
            try? await Task.sleep(for: wait)
            await self?.deferredSync(id)
        }
    }

    private func deferredSync(_ id: UUID) {
        guard let s = open[id] else { return }
        s.syncScheduled = false
        if s.dirty { try? sync(s) }
    }

    private func sync(_ s: OpenSession) throws {
        try s.handle.synchronize()
        try writeSession(s.info)
        s.dirty = false
        s.lastSync = .now
    }

    /// Forces pending records to stable storage now.
    public func flush(documentID: UUID) throws {
        let s = try session(documentID)
        do { try sync(s) } catch {
            throw PersistenceError(.io(error.localizedDescription), "Arcus couldn’t flush its recovery journal: \(error.localizedDescription)")
        }
    }

    /// The document was saved to `savedURL` (whose content equals `model`): prunes records, drops the snapshot and
    /// records the saved file's new identity. The session stays open.
    public func markSaved(documentID: UUID, savedURL: URL, model: BIMModel) throws {
        let s = try session(documentID)
        try s.handle.truncate(atOffset: UInt64(Self.header.count))
        try s.handle.seekToEnd()
        setSaved(&s.info, savedURL)
        s.info.baseRevision = model.revision
        s.info.changeCount = 0
        s.info.lastChange = Date()
        s.info.displayName = savedURL.deletingPathExtension().lastPathComponent
        try? FileManager.default.removeItem(at: baseURL(documentID))
        try sync(s)
    }

    /// Clean close: deletes the journal folder.
    public func end(documentID: UUID) throws {
        if let s = open.removeValue(forKey: documentID) {
            s.info.cleanShutdown = true
            try? writeSession(s.info)
            try? s.handle.close()
        }
        let dir = folder(documentID)
        if FileManager.default.fileExists(atPath: dir.path) {
            do { try FileManager.default.removeItem(at: dir) } catch {
                throw PersistenceError(.io(error.localizedDescription), "Arcus couldn’t remove its recovery journal: \(error.localizedDescription)")
            }
        }
    }

    /// Ends every open session (application terminating normally).
    public func endAll() {
        for id in Array(open.keys) { try? end(documentID: id) }
    }

    // MARK: Recovery

    /// Journals left behind by abnormal termination, most recent first. Sessions of this journal instance, of other
    /// running processes and cleanly closed ones are excluded; saved documents without changes are cleaned up.
    public func pendingRecoveries() -> [RecoveryItem] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var items: [RecoveryItem] = []
        for dir in dirs {
            guard let id = UUID(uuidString: dir.lastPathComponent), open[id] == nil else { continue }
            guard let info = try? readSession(id) else {
                log.log("Recovery", "Skipping unreadable recovery session \(id)", level: .warning)
                continue
            }
            if info.cleanShutdown { try? fm.removeItem(at: dir); continue }
            if info.pid != ProcessInfo.processInfo.processIdentifier, Self.processIsAlive(info.pid) { continue }
            let scan = scanJournal(id)
            if scan.entries.isEmpty && info.savedPath != nil { try? fm.removeItem(at: dir); continue }
            var problem: String? = scan.warning
            if info.hasBase {
                if !fm.fileExists(atPath: baseURL(id).path) { problem = "The recovery snapshot is missing." }
            } else if let p = baseProblem(info) {
                problem = p
            }
            let last = scan.entries.last?.record.timestamp ?? info.lastChange
            items.append(RecoveryItem(id: id, displayName: info.displayName, savedPath: info.savedPath, lastChange: last,
                                      changeCount: scan.entries.count, problem: problem))
        }
        return items.sorted { ($0.lastChange, $0.id.uuidString) > ($1.lastChange, $1.id.uuidString) }
    }

    static func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// Locates the saved file (following the bookmark if it moved) and checks it still has the recorded identity.
    private func resolveSaved(_ info: SessionInfo) -> (url: URL?, problem: String?) {
        guard let path = info.savedPath else { return (nil, "No saved file is recorded.") }
        var url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path), let bm = info.savedBookmark {
            var stale = false
            if let r = try? URL(resolvingBookmarkData: bm, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) { url = r }
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (nil, "The saved document “\(url.lastPathComponent)” can’t be found, so the unsaved changes can’t be applied to it.")
        }
        if let expected = info.savedFingerprint, let now = ExternalChangeDetector.fingerprint(url), !now.sameDocumentState(as: expected) {
            return (url, "“\(url.lastPathComponent)” was changed after these edits were made, so they can’t be applied safely.")
        }
        return (url, nil)
    }

    private func baseProblem(_ info: SessionInfo) -> String? { resolveSaved(info).problem }

    struct Scan {
        var entries: [JournalEntry] = []
        var warning: String?
    }

    /// Parses complete frames; a truncated or damaged tail is ignored with a warning.
    func scanJournal(_ id: UUID) -> Scan {
        var scan = Scan()
        guard let data = try? Data(contentsOf: journalURL(id)) else {
            scan.warning = "The recovery journal can’t be read."
            return scan
        }
        guard data.count >= Self.header.count, data.prefix(Self.header.count) == Self.header else {
            scan.warning = "The recovery journal has an unknown format."
            return scan
        }
        let dec = Self.decoder()
        var offset = Self.header.count
        let bytes = [UInt8](data)
        while offset < bytes.count {
            guard offset + 8 <= bytes.count else {
                scan.warning = "The last change was only partly written when Arcus quit and was ignored."
                break
            }
            let len = Int(readLE(bytes, offset)), crc = readLE(bytes, offset + 4)
            guard len <= Self.maxFrameBytes, offset + 8 + len <= bytes.count else {
                scan.warning = "The last change was only partly written when Arcus quit and was ignored."
                break
            }
            let payload = Data(bytes[(offset + 8)..<(offset + 8 + len)])
            guard CRC32.checksum(payload) == crc, let entry = try? dec.decode(JournalEntry.self, from: payload) else {
                scan.warning = "A damaged change record was found; it and any later changes were ignored."
                break
            }
            scan.entries.append(entry)
            offset += 8 + len
        }
        if let w = scan.warning { log.log("Recovery", "Journal \(id): \(w)", level: .warning) }
        return scan
    }

    /// Rebuilds the document: base (snapshot or saved file) + replay of every complete record.
    public func recover(_ item: RecoveryItem) throws -> (model: BIMModel, savedURL: URL?, displayName: String) {
        let r = try recoverWithReport(item)
        return (r.model, r.savedURL, r.displayName)
    }

    public func recoverWithReport(_ item: RecoveryItem) throws -> RecoveryResult {
        let id = item.id
        let info: SessionInfo
        do { info = try readSession(id) } catch {
            throw PersistenceError(.corrupt("session"), "The recovery information for “\(item.displayName)” is damaged and can’t be used.")
        }
        var model: BIMModel
        var savedURL: URL?
        if info.hasBase {
            model = try ArcusPackage.read(from: baseURL(id)).model
        } else {
            let (url, problem) = resolveSaved(info)
            if let problem { throw PersistenceError(.io(problem), problem + " The recovery journal was kept.") }
            guard let url else { throw PersistenceError(.io("missing"), "The saved document can’t be found.") }
            savedURL = url
            model = try ArcusPackage.read(from: url).model
        }
        let scan = scanJournal(id)
        var warnings: [String] = scan.warning.map { [$0] } ?? []
        var mismatched = 0
        var missingDrawings = 0
        Signposts.interval("Recovery replay", log: log) {
            for entry in scan.entries {
                for c in entry.record.changes where model[c.id] != c.before { mismatched += 1 }
                for k in entry.record.addedDrawings {
                    if let d = entry.drawings?[k] { model.referenceDrawings[k] = d } else if model.referenceDrawings[k] == nil { missingDrawings += 1 }
                }
                model.apply(entry.record)
            }
        }
        if mismatched > 0 { warnings.append("\(mismatched) recorded changes didn’t match the base document; the recovered version may differ slightly.") }
        if missingDrawings > 0 { warnings.append("\(missingDrawings) imported reference drawings weren’t journaled and are missing.") }
        for w in warnings { log.log("Recovery", "Recovering \(id): \(w)", level: .warning) }
        log.log("Recovery", "Recovered document \(id): \(scan.entries.count) changes replayed")
        return RecoveryResult(model: model, savedURL: savedURL, displayName: info.displayName, replayedRecords: scan.entries.count, warnings: warnings)
    }

    /// Deletes a recovery journal without recovering it.
    public func discard(_ item: RecoveryItem) throws {
        if let s = open.removeValue(forKey: item.id) { try? s.handle.close() }
        let dir = folder(item.id)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        do { try FileManager.default.removeItem(at: dir) } catch {
            throw PersistenceError(.io(error.localizedDescription), "Arcus couldn’t delete the recovery data: \(error.localizedDescription)")
        }
    }

    /// Documents currently journaled by this instance.
    public var openDocumentIDs: [UUID] { Array(open.keys) }
}

// MARK: - Helpers

private func appendLE(_ d: inout Data, _ v: UInt32) {
    var le = v.littleEndian
    withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
}

private func readLE(_ b: [UInt8], _ o: Int) -> UInt32 {
    UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
}

/// CRC-32 (IEEE 802.3, reflected, polynomial 0xEDB88320).
enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { raw in
            for b in raw { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }
}
