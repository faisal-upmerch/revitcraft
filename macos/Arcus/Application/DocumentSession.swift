import Foundation
import Observation
import OSLog
import ArcusGeometry
import ArcusDomain

/// Observes committed transactions (recovery journal, autosave scheduling, caches).
@MainActor
public protocol TransactionObserver: AnyObject {
    func session(_ session: DocumentSession, didApply record: TransactionRecord, kind: DocumentSession.ChangeKind)
}

/// Describes what changed after a commit/undo/redo, for localized regeneration of views and panels.
public struct ModelChange: Sendable {
    public var record: TransactionRecord
    public var changed: Set<ElementID>
    /// Changed plus dependents whose derived graphics are affected.
    public var affected: Set<ElementID>
    public var categories: Set<Category>
    public var kind: DocumentSession.ChangeKind
}

/// The live editing session of one document: authoritative model, transactions, undo/redo, selection and views.
@MainActor
@Observable
public final class DocumentSession {
    public enum ChangeKind: Sendable { case commit, undo, redo, replace }

    public private(set) var model: BIMModel
    public let undoManager: UndoManager
    public let selection = SelectionModel()
    /// Last non-fatal warnings from a commit (shown in the status bar).
    public private(set) var lastWarnings: [ModelWarning] = []
    /// Last error from a rejected transaction.
    public private(set) var lastError: TransactionError?
    /// Monotonic counter of changes, for SwiftUI invalidation.
    public private(set) var changeCounter: Int = 0
    public private(set) var lastChange: ModelChange?
    /// Temporary hide/isolate per view (session only; not undoable, not saved).
    public var temporaryVisibility: [ElementID: TemporaryVisibility] = [:]
    /// F5: Massing & Site ▸ Show Mass. Session only, for every view (RevitCraft `show_mass`); views get it as
    /// `TemporaryVisibility.hideMass` through `temporaryVisibility(for:)`.
    public var showMass = true
    /// Group being edited (Edit Group mode), if any.
    public var editingGroupID: ElementID?
    /// Instance values set in the Properties palette before placement ("New Doors"); applied to matching new elements. BL-PROPS
    @ObservationIgnored public var creationDefaults: CreationDefaults?
    /// The design option being edited (Manage ▸ Design Options combo, Pick to Edit): new model elements join it. nil = main model. // F11
    public var activeDesignOptionID: ElementID?

    @ObservationIgnored public weak var observer: (any TransactionObserver)?
    /// Runs inside every `perform` just before commit (e.g. Structural Wall marks the walls its tool creates). // BL-VG
    @ObservationIgnored public var beforeCommit: ((TransactionContext) -> Void)?
    @ObservationIgnored private var changeHandlers: [UUID: (ModelChange) -> Void] = [:]

    public init(model: BIMModel, undoManager: UndoManager = UndoManager()) {
        self.model = model
        self.undoManager = undoManager
        undoManager.levelsOfUndo = 200
    }

    // MARK: Change notifications

    @discardableResult
    public func onChange(_ handler: @escaping (ModelChange) -> Void) -> UUID {
        let id = UUID()
        changeHandlers[id] = handler
        return id
    }
    public func removeChangeHandler(_ id: UUID) { changeHandlers.removeValue(forKey: id) }

    // MARK: Transactions

    /// Runs `build` in a new transaction and commits it. Returns the record, or nil if nothing changed or the
    /// transaction was rejected (see `lastError`). The model is untouched on failure.
    @discardableResult
    public func perform(_ name: String, _ build: (TransactionContext) throws -> Void) -> TransactionRecord? {
        let tx = TransactionContext(model: model, name: name)
        do {
            try build(tx)
            creationDefaults?.apply(in: tx, createdSince: model) // BL-PROPS
            MarkNumbering.apply(tx) // BL-CANVAS: ARCUS-045
            DesignOptionEditing.assignNewElements(to: activeDesignOptionID, in: tx, createdSince: model) // F11
        } catch let e as TransactionError {
            lastError = e
            return nil
        } catch let e as ParameterError {
            lastError = TransactionError(e.message)
            return nil
        } catch {
            lastError = TransactionError("\(error)")
            return nil
        }
        beforeCommit?(tx) // BL-VG
        guard tx.hasChanges else { return nil }
        let interval = Signpost.begin("transaction")
        let result: (model: BIMModel, record: TransactionRecord, warnings: [ModelWarning])
        do {
            result = try tx.commit()
        } catch {
            Signpost.end(interval, completed: false)
            lastError = error
            return nil
        }
        Signpost.end(interval)
        lastError = nil
        lastWarnings = result.warnings
        install(result.model, record: result.record, kind: .commit)
        registerUndo(result.record)
        return result.record
    }

    /// Like `perform` but throws the rejection (for callers that present errors inline).
    @discardableResult
    public func performThrowing(_ name: String, _ build: (TransactionContext) throws -> Void) throws -> TransactionRecord? {
        let r = perform(name, build)
        if r == nil, let e = lastError { throw e }
        return r
    }

    private func registerUndo(_ record: TransactionRecord) {
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.applyInverse(record) }
        }
        undoManager.setActionName(record.name)
    }


    private func applyInverse(_ record: TransactionRecord) {
        let inverse = record.inverse
        install(model.applying(inverse), record: inverse, kind: undoManager.isUndoing ? .undo : .redo)
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.applyInverse(inverse) }
        }
        undoManager.setActionName(record.name)
    }

    private func install(_ newModel: BIMModel, record: TransactionRecord, kind: ChangeKind) {
        let old = model
        model = newModel
        let changed = record.changedIDs
        let affected = DependencyGraph.affected(by: changed, before: old, after: newModel)
        var cats = Set<Category>()
        for c in record.changes { if let e = c.after ?? c.before { cats.insert(e.category) } }
        let change = ModelChange(record: record, changed: changed, affected: affected, categories: cats, kind: kind)
        // Drop selection of deleted elements.
        selection.retainExisting(in: newModel)
        lastChange = change
        changeCounter += 1
        observer?.session(self, didApply: record, kind: kind)
        for h in changeHandlers.values { h(change) }
    }

    /// Replaces the model wholesale (open, revert, recovery). Clears undo history.
    public func replaceModel(_ newModel: BIMModel) {
        undoManager.removeAllActions()
        let record = TransactionRecord(name: "Open", changes: [], project: ProjectStateChange(), addedDrawings: [], nextIDAfter: newModel.nextID)
        model = newModel
        selection.clear()
        let change = ModelChange(record: record, changed: [], affected: Set(newModel.allElements.map(\.id)), categories: Set(Category.allCases), kind: .replace)
        lastChange = change
        changeCounter += 1
        for h in changeHandlers.values { h(change) }
    }

    public func clearError() { lastError = nil }

    /// Releases the model, undo history and listeners when the document closes. The session is unusable afterwards.
    public func discard() {
        changeHandlers.removeAll()
        observer = nil
        undoManager.removeAllActions()
        selection.clear()
        model = BIMModel()
    }

    // MARK: Convenience

    public func setParameter(_ id: ParameterID, text: String, on elements: [ElementID], type: ParamType, name: String) {
        let value: ParamValue
        do { value = try Parameters.parse(text, type: type, model: model) } catch { lastError = TransactionError(error.message); return }
        setParameter(id, value: value, on: elements, name: name)
    }

    public func setParameter(_ id: ParameterID, value: ParamValue, on elements: [ElementID], name: String) {
        perform("Change \(name)") { tx in
            for e in elements { try Parameters.set(id, to: value, on: e, in: tx) }
        }
    }

    public func delete(_ ids: [ElementID]) {
        let deletable = ids.filter { id in model[id].map { !$0.pinned } ?? false }
        let pinned = ids.count - deletable.count
        if deletable.isEmpty {
            if pinned > 0 { lastError = TransactionError("Pinned elements can't be deleted. Unpin them first.", elements: ids) }
            return
        }
        perform(deletable.count == 1 ? "Delete \(model[deletable[0]]?.category.singularName ?? "Element")" : "Delete \(deletable.count) Elements") { tx in
            for id in deletable { tx.delete(id) }
        }
        if pinned > 0 { lastWarnings.append(ModelWarning(.info, code: "delete.pinned", "\(pinned) pinned element(s) were not deleted.", elements: [])) }
    }

    public var canUndo: Bool { undoManager.canUndo }
    public var canRedo: Bool { undoManager.canRedo }
}

/// Lightweight signpost timing hook (Application layer has no OSLog dependency requirement; UI installs a sink).
/// Performance intervals for hot paths: emitted as os_signpost intervals (Instruments → Points of Interest,
/// subsystem `com.local.arcus`) and forwarded to `sink` (the app records them in the diagnostics log).
public enum Signpost {
    nonisolated(unsafe) public static var sink: (@Sendable (String, Double) -> Void)?
    public static let signposter = OSSignposter(subsystem: "com.local.arcus", category: .pointsOfInterest)

    public struct Interval: @unchecked Sendable {
        let name: StaticString
        let state: OSSignpostIntervalState
        let start: CFAbsoluteTime
    }
    public static func begin(_ name: StaticString) -> Interval {
        Interval(name: name, state: signposter.beginInterval(name, id: signposter.makeSignpostID()), start: CFAbsoluteTimeGetCurrent())
    }
    /// Ends the interval and reports its duration. Pass `completed: false` for cancelled or superseded work
    /// (the interval still ends in Instruments but is not recorded as a timing).
    public static func end(_ i: Interval, completed: Bool = true) {
        signposter.endInterval(i.name, i.state)
        if completed { sink?(String(describing: i.name), CFAbsoluteTimeGetCurrent() - i.start) }
    }
    public static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let i = begin(name)
        defer { end(i) }
        return try body()
    }
}
