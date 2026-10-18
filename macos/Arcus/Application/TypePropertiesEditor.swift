import Foundation
import Observation
import ArcusDomain

/// BL-PROPS: the staged editing session behind the Type Properties dialog.
///
/// Every change — parameter values, the compound structure, Duplicate and Rename — is staged and shown from a preview
/// model; nothing reaches the document until Apply or OK. Apply commits the staged changes as one undo step and keeps
/// the dialog open; OK commits them together with assigning the displayed type to the elements the dialog was opened
/// for (one undo step); Cancel discards whatever is staged. A duplicated type therefore exists only once it is applied.
@MainActor
@Observable
public final class TypePropertiesEditor {
    public let session: DocumentSession
    /// The type shown. For a staged duplicate this is its id in the preview model (the id it gets when committed).
    public private(set) var typeID: ElementID
    /// Elements that take the displayed type on OK (the selection the dialog was opened from).
    public let assignTo: [ElementID]
    /// The document with the staged changes applied (not committed).
    public private(set) var preview: BIMModel

    enum Edit: Hashable { case parameter(ParameterID, ParamValue), assembly(CompoundAssembly), rename(String), stack(StackedWallSpec) } // F2: stack
    enum Op: Hashable { case duplicate(source: ElementID, name: String), edit(ElementID, Edit) }
    /// Staged operations in the order made; replayed in order so a duplicate copies the values staged before it.
    private var log: [Op] = []
    private let initialTypeID: ElementID
    /// Ids the staged duplicates get (in the preview, and when committed to an unchanged document).
    private var duplicateIDs: [ElementID] = []

    public init(session: DocumentSession, typeID: ElementID, assignTo: [ElementID] = []) {
        self.session = session
        self.typeID = typeID
        self.initialTypeID = typeID
        self.assignTo = assignTo
        self.preview = session.model
    }

    public var hasChanges: Bool { !log.isEmpty }
    public var type: Element? { preview[typeID] }
    /// Types offered by the Type drop-down: the family of the displayed type, including staged duplicates.
    public var siblingTypes: [Element] {
        guard let td = type?.typeData else { return [] }
        return preview.types(for: td.instanceCategory).filter { $0.typeData?.familyName == td.familyName }
    }
    public func isStagedDuplicate(_ id: ElementID) -> Bool { session.model[id] == nil && preview[id] != nil }

    /// Switches the displayed type (staged edits of other types are kept).
    public func show(_ id: ElementID) { if preview[id]?.typeData != nil { typeID = id } }

    // MARK: Staging

    /// Stages a parameter value for the displayed type. Throws (staging nothing) when the value is invalid.
    public func stage(_ id: ParameterID, value: ParamValue) throws(ParameterError) {
        try append(.edit(typeID, .parameter(id, value)))
    }

    /// Parses and stages typed text.
    public func stage(_ id: ParameterID, text: String, type: ParamType) throws(ParameterError) {
        try stage(id, value: try Parameters.parse(text, type: type, model: preview))
    }

    /// Stages the compound structure of the displayed type.
    public func stage(assembly: CompoundAssembly) throws(ParameterError) {
        if let e = assembly.validate() { throw ParameterError(e.description) }
        try append(.edit(typeID, .assembly(assembly)))
    }

    /// F2: stages the structure of the displayed stacked wall type.
    public func stage(stack: StackedWallSpec) throws(ParameterError) {
        if let e = stack.validate() { throw ParameterError(e.description) }
        try append(.edit(typeID, .stack(stack)))
    }

    /// Stages a new name for the displayed type.
    public func rename(_ name: String) throws(ParameterError) {
        let n = try validName(name, excluding: typeID)
        try append(.edit(typeID, .rename(n)))
    }

    /// "<Type> 2", or the next free number — the name Duplicate proposes.
    public var suggestedDuplicateName: String {
        let base = type?.name ?? "Type"
        var k = 2
        while nameTaken("\(base) \(k)", excluding: nil) { k += 1 }
        return "\(base) \(k)"
    }

    /// Stages a copy of the displayed type named `name` (with its staged values) and shows it.
    public func duplicate(named name: String) throws(ParameterError) {
        let n = try validName(name, excluding: nil)
        try append(.duplicate(source: typeID, name: n))
        if let id = duplicateIDs.last { typeID = id }
    }

    /// Checks a type name: not empty and not used by another type of the category.
    public func validName(_ name: String, excluding: ElementID?) throws(ParameterError) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw ParameterError("The name can't be empty.") }
        guard !nameTaken(n, excluding: excluding) else { throw ParameterError("A type named “\(n)” already exists.") }
        return n
    }

    func nameTaken(_ n: String, excluding: ElementID?) -> Bool {
        guard let cat = type?.typeData?.instanceCategory else { return false }
        return preview.types(for: cat).contains { $0.id != excluding && $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }

    // MARK: Committing

    /// Commits the staged changes as one undo step and keeps editing. Returns false (keeping them staged) when the
    /// document rejects them; the session's `lastError` says why.
    @discardableResult
    public func apply() -> Bool { commit(assigning: false) }

    /// Commits the staged changes and assigns the displayed type to `assignTo`, as one undo step.
    @discardableResult
    public func ok() -> Bool { commit(assigning: true) }

    /// Discards everything staged.
    public func cancel() {
        if session.model[typeID] == nil { typeID = initialTypeID }
        log = []; duplicateIDs = []
        preview = session.model
    }

    private func commit(assigning: Bool) -> Bool {
        let shownIndex = duplicateIDs.firstIndex(of: typeID)
        let category = preview[typeID]?.typeData?.instanceCategory
        var shown = typeID
        let targets = assigning ? assignTo.filter { id in
            guard let e = session.model[id], e.typeID != nil else { return false }
            return e.category == category && (e.typeID != shown || shownIndex != nil)
        } : []
        guard hasChanges || !targets.isEmpty else { return true }
        let name = log.contains { if case .duplicate = $0 { return true }; return false } ? "Duplicate Type"
            : (targets.isEmpty ? "Type Properties" : "Change Type")
        let record = session.perform(name) { tx in
            let ids = try replay(in: tx)
            if let i = shownIndex, i < ids.count { shown = ids[i] }
            for t in targets { try Parameters.set(ParameterID("familyAndType"), to: .ref(shown), on: t, in: tx) }
        }
        if record == nil && session.lastError != nil { return false }
        typeID = shown
        log = []; duplicateIDs = []
        preview = session.model
        return true
    }

    // MARK: Preview

    private func append(_ op: Op) throws(ParameterError) {
        log.append(op)
        do { try rebuild() } catch {
            log.removeLast()
            try? rebuild()
            throw error
        }
    }

    private func rebuild() throws(ParameterError) {
        let tx = TransactionContext(model: session.model, name: "Type Properties")
        do { duplicateIDs = try replay(in: tx) } catch let e as ParameterError { throw e } catch { throw ParameterError("\(error)") }
        preview = tx.model
    }

    /// Replays the staged operations into `tx` in order. Returns the duplicates' ids (deterministic for a given
    /// document, so preview ids equal committed ids unless the document changed meanwhile).
    private func replay(in tx: TransactionContext) throws -> [ElementID] {
        var ids: [ElementID] = []
        for op in log {
            switch op {
            case .duplicate(let source, let name):
                guard let td = tx.model[source]?.typeData else { throw ParameterError("The type to duplicate no longer exists.") }
                ids.append(tx.create(.elementTypes, name: name, data: .type(td)))
            case .edit(let t, let edit):
                guard tx.model[t] != nil else { throw ParameterError("The type no longer exists.") }
                switch edit {
                case .parameter(let id, let v): try Parameters.set(id, to: v, on: t, in: tx)
                case .assembly(let a): tx.update(t) { $0.typeData?.assembly = a }
                case .rename(let n): tx.update(t) { $0.name = n }
                case .stack(let st): tx.update(t) { $0.typeData?.stack = st } // F2
                }
            }
        }
        return ids
    }
}
