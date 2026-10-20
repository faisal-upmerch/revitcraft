import AppKit
import UniformTypeIdentifiers
import ArcusDomain
import ArcusApplication
import ArcusPersistence
import ArcusServices

nonisolated extension UTType {
    static let arcusProject = UTType(exportedAs: "com.local.arcus.project", conformingTo: .package)
    static let arcusFamily = UTType(exportedAs: "com.local.arcus.family", conformingTo: .package)
    /// FM3: a Furniture document (`.arcusfurniture`), the project package opened in Furniture mode.
    static let arcusFurniture = UTType(exportedAs: "com.local.arcus.furniture", conformingTo: .package)
}

/// An Arcus project document (`.arcus` package). Saving is atomic via NSDocument safe-save; autosave in place,
/// versions, duplicate, revert and window restoration come from NSDocument. A recovery journal records every
/// transaction so unsaved work survives a crash.
final class ArcusDocument: NSDocument, TransactionObserver {
    private(set) var session: DocumentSession
    private(set) var state: DocumentState!
    private var documentID = UUID()
    private var created: Date?
    private var fingerprint: FileFingerprint?
    private var journalStarted = false
    /// Serializes journal operations in submission order (begin → appends → markSaved → end).
    private let journalQueue = JournalQueue()
    /// Snapshot used by (possibly asynchronous, background-thread) saves.
    private let snapshot = SaveSnapshot()
    /// AICORE: the AI assistant's chats as read from the package (the open sidebar's chats replace them on save).
    var assistantHistory: Data?

    override init() {
        session = DocumentSession(model: BIMModel())
        super.init()
        hasUndoManager = true
        undoManager = session.undoManager
    }

    /// Creates an untitled document with a model (template, sample or recovered).
    convenience init(model: BIMModel, displayName: String? = nil) {
        self.init()
        session.replaceModel(model)
        fileType = Self.documentType(model).identifier // FM3: Furniture documents save as .arcusfurniture
        if let displayName { self.displayName = displayName }
        state = DocumentState(session: session)
        state.document = self
        session.observer = self
    }

    nonisolated override class var autosavesInPlace: Bool { true }
    nonisolated override class var readableTypes: [String] { [UTType.arcusProject.identifier, UTType.arcusFurniture.identifier] } // FM3
    nonisolated override class var writableTypes: [String] { [UTType.arcusProject.identifier, UTType.arcusFurniture.identifier] }
    nonisolated override class func isNativeType(_ type: String) -> Bool { readableTypes.contains(type) }
    /// FM3: a project saves as `.arcus`, a Furniture document as `.arcusfurniture` (Save As offers only its own type).
    nonisolated override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        let furniture = MainActor.assumeIsolated { session.model.isFurniture }
        return [(furniture ? UTType.arcusFurniture : UTType.arcusProject).identifier]
    }
    nonisolated static func documentType(_ model: BIMModel) -> UTType { model.isFurniture ? .arcusFurniture : .arcusProject }
    nonisolated override class var preservesVersions: Bool { true }

    /// Mirrors the edited state and file name into the observable state (the sidebar header shows them).
    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        state?.refreshDocumentInfo()
    }
    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        state?.refreshDocumentInfo()
    }
    nonisolated override var fileURL: URL? {
        didSet { DispatchQueue.main.async { [weak self] in self?.state?.refreshDocumentInfo() } }
    }

    override func makeWindowControllers() {
        if state == nil {
            state = DocumentState(session: session)
            state.document = self
            session.observer = self
        }
        addWindowController(DocumentWindowController(document: self))
        startJournal()
        F67Links(state: state).reloadOnOpen() // F67: linked models, point clouds, topography and markups follow their files
    }

    // MARK: Reading

    nonisolated override func read(from url: URL, ofType typeName: String) throws {
        let t0 = CFAbsoluteTimeGetCurrent()
        let result = try ArcusPackage.read(from: url)
        let fp = ExternalChangeDetector.fingerprint(url)
        // Documents are read on the main thread (concurrent reading is not enabled).
        MainActor.assumeIsolated {
            if ArcusPackage.isNewerThanCurrent(result.manifest) {
                DiagnosticsLog.shared.log("document", "Opened a newer schema (\(result.manifest.schemaVersion)) with \(AppVersionInfo.current.marketingVersion)", level: .warning)
            }
            documentID = result.manifest.documentID
            created = result.manifest.created
            assistantHistory = ArcusPackage.readAssistantHistory(url) // AICORE
            session.replaceModel(result.model)
            fingerprint = fp
            if state != nil { state.openInitialView() }
        }
        DiagnosticsLog.shared.recordTiming("open", seconds: CFAbsoluteTimeGetCurrent() - t0)
    }

    // MARK: Writing

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping ((any Error)?) -> Void) {
        snapshot.set(session.model, documentID: documentID, created: created)
        if let s = state, let h = AIAssistantPanel.historyData(s) { assistantHistory = h.isEmpty ? nil : h } // AICORE
        snapshot.assistantHistory = assistantHistory
        // Warn before overwriting a file changed by another process.
        if saveOperation == .saveOperation, let fp = fingerprint, let fileURL, ExternalChangeDetector.hasChanged(fileURL, since: fp) {
            let alert = NSAlert()
            alert.messageText = "“\(displayName ?? "This project")” was changed by another application."
            alert.informativeText = "Saving will replace the other changes. You can save your version under a new name instead."
            alert.addButton(withTitle: "Save Anyway")
            alert.addButton(withTitle: "Save As…")
            alert.addButton(withTitle: "Cancel")
            let r = alert.runModal()
            if r == .alertSecondButtonReturn { saveAs(nil); completionHandler(CocoaError(.userCancelled)); return }
            if r != .alertFirstButtonReturn { completionHandler(CocoaError(.userCancelled)); return }
        }
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            MainActor.assumeIsolated {
                guard let self else { completionHandler(error); return }
                if error == nil, let saved = self.fileURL, saveOperation != .autosaveElsewhereOperation {
                    self.fingerprint = ExternalChangeDetector.fingerprint(saved)
                    let model = self.snapshot.model ?? self.session.model
                    let id = self.documentID
                    let j = AppServices.shared.journal
                    self.journalQueue.submit { try? await j.markSaved(documentID: id, savedURL: saved, model: model) }
                }
                completionHandler(error)
            }
        }
    }

    nonisolated override func write(to url: URL, ofType typeName: String) throws {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let model = snapshot.model else { throw CocoaError(.fileWriteUnknown) }
        let thumbnail = Thumbnailer.png(model: model)
        var info = AppVersionInfo.current.writeInfo(documentID: snapshot.documentID, created: snapshot.created ?? Date(), thumbnailPNG: thumbnail)
        info.assistantHistory = snapshot.assistantHistory // AICORE
        try ArcusPackage.write(model, to: url, info: info)
        DiagnosticsLog.shared.recordTiming("save", seconds: CFAbsoluteTimeGetCurrent() - t0)
    }

    nonisolated override func canAsynchronouslyWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) -> Bool { true }

    // MARK: Journal

    func startJournal() {
        guard !journalStarted else { return }
        journalStarted = true
        let id = documentID
        let name = displayName ?? "Untitled"
        let url = fileURL
        let model = session.model
        let info = AppVersionInfo.current.writeInfo(documentID: id, created: created)
        let j = AppServices.shared.journal
        journalQueue.submit { try? await j.begin(documentID: id, displayName: name, savedURL: url, baseModel: model, info: info) }
    }

    func session(_ session: DocumentSession, didApply record: TransactionRecord, kind: DocumentSession.ChangeKind) {
        guard kind != .replace else { return }
        let id = documentID
        let drawings = Dictionary(uniqueKeysWithValues: record.addedDrawings.compactMap { k in session.model.referenceDrawings[k].map { (k, $0) } })
        let j = AppServices.shared.journal
        journalQueue.submit { try? await j.append(record, documentID: id, drawings: drawings) }
    }

    override func close() {
        let id = documentID
        let j = AppServices.shared.journal
        journalQueue.submit { try? await j.end(documentID: id) }
        for (_, v) in state?.canvases ?? [:] { v.removeFromSuperview() }
        if let s = state { AIAssistantPanel.existing(s)?.agent.stop(); AIAssistantPanel.forget(s) } // AICORE
        super.close()
        state?.tearDown()
        if !NSDocumentController.shared.documents.contains(where: { $0 is ArcusDocument }) { DerivedCaches.purgeAll() }
    }

    // MARK: Restoration

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        guard let state else { return }
        coder.encode(state.openViews.map { Int64($0.raw) }, forKey: "openViews")
        if let a = state.activeViewID { coder.encode(Int64(a.raw), forKey: "activeView") }
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        guard let state, let open = coder.decodeObject(of: [NSArray.self, NSNumber.self], forKey: "openViews") as? [Int64] else { return }
        for raw in open { state.open(ElementID(UInt64(raw))) }
        let active = coder.decodeInt64(forKey: "activeView")
        if active > 0 { state.open(ElementID(UInt64(active))) }
    }

    // MARK: Recovery copy

    func saveRecoveryCopy() {
        guard let src = fileURL else {
            state?.show("Save the project first; a recovery copy is made from the saved file.", error: true)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.documentType(session.model)] // FM3
        panel.nameFieldStringValue = (displayName ?? "Project") + " (Recovered)." + (session.model.isFurniture ? ArcusPackage.furnitureFileExtension : ArcusPackage.fileExtension)
        guard let w = windowForSheet else { return }
        panel.beginSheetModal(for: w) { r in
            guard r == .OK, let dest = panel.url else { return }
            do {
                let report = try ArcusPackage.saveRecoveryCopy(from: src, to: dest, info: AppVersionInfo.current.writeInfo(documentID: UUID()))
                self.state?.show(report.isHealthy ? "Recovery copy saved; the project was healthy." : "Recovery copy saved with \(report.recoveredElements) elements; \(report.lostElements) could not be read.")
            } catch {
                self.state?.show("Couldn't write a recovery copy: \(error.localizedDescription)", error: true)
            }
        }
    }
}

/// App-wide services (recovery journal).
@MainActor
final class AppServices {
    static let shared = AppServices()
    let journal: RecoveryJournal
    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Arcus/Recovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        journal = RecoveryJournal(baseDirectory: base, log: DiagnosticsLog.shared)
    }
}

/// Thread-safe holder for the model snapshot written by background saves.
nonisolated final class SaveSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var _model: BIMModel?
    private var _documentID = UUID()
    private var _created: Date?
    func set(_ m: BIMModel, documentID: UUID, created: Date?) { lock.lock(); _model = m; _documentID = documentID; _created = created; lock.unlock() }
    var model: BIMModel? { lock.lock(); defer { lock.unlock() }; return _model }
    var documentID: UUID { lock.lock(); defer { lock.unlock() }; return _documentID }
    var created: Date? { lock.lock(); defer { lock.unlock() }; return _created }
    /// AICORE: the assistant's chats to write with the package.
    private var _assistantHistory: Data?
    var assistantHistory: Data? {
        get { lock.lock(); defer { lock.unlock() }; return _assistantHistory }
        set { lock.lock(); _assistantHistory = newValue; lock.unlock() }
    }
}

/// A FIFO of async operations executed one at a time, in order.
nonisolated final class JournalQueue: Sendable {
    private let continuation: AsyncStream<@Sendable () async -> Void>.Continuation
    init() {
        let (stream, cont) = AsyncStream<@Sendable () async -> Void>.makeStream()
        continuation = cont
        Task.detached(priority: .utility) { for await op in stream { await op() } }
    }
    func submit(_ op: @escaping @Sendable () async -> Void) { continuation.yield(op) }
}
