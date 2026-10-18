import Foundation
import ArcusGeometry

/// Net change to one element within a transaction. `before == nil` is an insertion; `after == nil` a deletion.
public struct ElementChange: Hashable, Codable, Sendable {
    public let id: ElementID
    public let before: Element?
    public let after: Element?
    public init(id: ElementID, before: Element?, after: Element?) { self.id = id; self.before = before; self.after = after }
    public var isInsert: Bool { before == nil && after != nil }
    public var isDelete: Bool { before != nil && after == nil }
    public var inverse: ElementChange { ElementChange(id: id, before: after, after: before) }
}

/// Project-level (non-element) state captured by a transaction when it changes.
public struct ProjectStateChange: Hashable, Codable, Sendable {
    public var projectParametersBefore: [ParameterDefinition]?
    public var projectParametersAfter: [ParameterDefinition]?
    public var sheetSetsBefore: [ViewSheetSet]?
    public var sheetSetsAfter: [ViewSheetSet]?
    public init(projectParametersBefore: [ParameterDefinition]? = nil, projectParametersAfter: [ParameterDefinition]? = nil,
                sheetSetsBefore: [ViewSheetSet]? = nil, sheetSetsAfter: [ViewSheetSet]? = nil) {
        self.projectParametersBefore = projectParametersBefore; self.projectParametersAfter = projectParametersAfter
        self.sheetSetsBefore = sheetSetsBefore; self.sheetSetsAfter = sheetSetsAfter
    }
    public var inverse: ProjectStateChange {
        ProjectStateChange(projectParametersBefore: projectParametersAfter, projectParametersAfter: projectParametersBefore,
                           sheetSetsBefore: sheetSetsAfter, sheetSetsAfter: sheetSetsBefore)
    }
    public var isEmpty: Bool { projectParametersAfter == nil && sheetSetsAfter == nil }
}

/// An immutable, committed transaction. Applying it forward or its inverse reproduces model states exactly.
public struct TransactionRecord: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let timestamp: Date
    /// Changes sorted by element id.
    public let changes: [ElementChange]
    public let project: ProjectStateChange
    /// Keys of reference drawings added by this transaction (content stays in the model; content is immutable).
    public let addedDrawings: [String]
    public let nextIDAfter: UInt64

    public init(id: UUID = UUID(), name: String, timestamp: Date = Date(), changes: [ElementChange], project: ProjectStateChange,
                addedDrawings: [String], nextIDAfter: UInt64) {
        self.id = id; self.name = name; self.timestamp = timestamp; self.changes = changes; self.project = project
        self.addedDrawings = addedDrawings; self.nextIDAfter = nextIDAfter
    }

    public var inverse: TransactionRecord {
        TransactionRecord(id: UUID(), name: name, timestamp: Date(), changes: changes.map(\.inverse), project: project.inverse,
                          addedDrawings: [], nextIDAfter: nextIDAfter)
    }
    public var changedIDs: Set<ElementID> { Set(changes.map(\.id)) }
    public var isEmpty: Bool { changes.isEmpty && project.isEmpty && addedDrawings.isEmpty }
}

/// A validation failure that rolls back a transaction.
public struct TransactionError: Error, Hashable, Sendable, CustomStringConvertible {
    public var message: String
    public var elements: [ElementID]
    /// Suggested resolution shown to the user.
    public var resolution: String?
    public init(_ message: String, elements: [ElementID] = [], resolution: String? = nil) {
        self.message = message; self.elements = elements; self.resolution = resolution
    }
    public var description: String { message }
}

/// A non-fatal issue produced by a commit (shown in the status area and the model health panel).
public struct ModelWarning: Hashable, Codable, Sendable, Identifiable {
    public enum Severity: String, Codable, Sendable, Comparable {
        case info, warning, error
        public static func < (a: Severity, b: Severity) -> Bool {
            let o: [Severity] = [.info, .warning, .error]
            return o.firstIndex(of: a)! < o.firstIndex(of: b)!
        }
    }
    public var id: String
    public var severity: Severity
    public var code: String
    public var message: String
    public var elements: [ElementID]
    public init(_ severity: Severity, code: String, _ message: String, elements: [ElementID]) {
        self.severity = severity; self.code = code; self.message = message; self.elements = elements.sorted()
        id = code + ":" + self.elements.map(\.description).joined(separator: ",")
    }
}

extension BIMModel {
    /// Applies a committed record (forward). Used for undo/redo (with `inverse`) and journal replay.
    public mutating func apply(_ record: TransactionRecord) {
        for c in record.changes {
            if let after = c.after { put(after) } else { remove(c.id) }
        }
        if let p = record.project.projectParametersAfter { projectParameters = p }
        if let s = record.project.sheetSetsAfter { viewSheetSets = s }
        reserveIDs(through: record.nextIDAfter &- 1)
        bumpRevision()
    }
    public func applying(_ record: TransactionRecord) -> BIMModel { var m = self; m.apply(record); return m }
}

/// Mutable scope for building one transaction against a working copy of the model.
///
/// Usage: create, mutate through `create/update/delete`, then `commit()` which regenerates dependent
/// data, solves constraints, validates and returns the new model plus an immutable record — or throws
/// and leaves the original model untouched.
public final class TransactionContext {
    public let name: String
    public private(set) var model: BIMModel
    private let original: BIMModel
    private var touched: [ElementID: Element?] = [:]
    private var projectChange = ProjectStateChange()
    private var addedDrawings: [String] = []
    public private(set) var warnings: [ModelWarning] = []
    /// Elements explicitly edited by the user in this transaction (constraint solver keeps them fixed).
    public private(set) var driven: Set<ElementID> = []

    public init(model: BIMModel, name: String) {
        self.model = model
        self.original = model
        self.name = name
    }

    private func touch(_ id: ElementID) {
        if touched[id] == nil { touched[id] = .some(original[id]) }
    }

    // MARK: Element operations

    /// Creates an element with a fresh id. `configure` can set relationships before insertion.
    @discardableResult
    public func create(_ category: Category, name: String = "", data: ElementData, typeID: ElementID? = nil, levelID: ElementID? = nil,
                       hostID: ElementID? = nil, ownerViewID: ElementID? = nil, ifcGUID: IFCGUID? = nil,
                       configure: ((inout Element) -> Void)? = nil) -> ElementID {
        let id = model.allocateID()
        var e = Element(id: id, category: category, name: name, data: data, typeID: typeID, levelID: levelID, hostID: hostID,
                        ownerViewID: ownerViewID, ifcGUID: ifcGUID)
        if e.phaseCreated == nil, category.isModel { e.phaseCreated = model.latestPhase?.id }
        configure?(&e)
        touch(id)
        model.put(e)
        driven.insert(id)
        return id
    }

    /// Inserts a fully formed element preserving its id (paste, import, journal replay). Reserves the id.
    public func insertPreservingID(_ e: Element) {
        touch(e.id)
        model.put(e)
        driven.insert(e.id)
    }

    /// Mutates an existing element. Returns false if it does not exist.
    @discardableResult
    public func update(_ id: ElementID, _ mutate: (inout Element) -> Void) -> Bool {
        guard var e = model[id] else { return false }
        let before = e
        mutate(&e)
        e.id = id
        guard e != before else { return true }
        touch(id)
        model.put(e)
        driven.insert(id)
        return true
    }

    /// Update performed by propagation (not user-driven).
    @discardableResult
    func propagate(_ id: ElementID, _ mutate: (inout Element) -> Void) -> Bool {
        guard var e = model[id] else { return false }
        let before = e
        mutate(&e)
        guard e != before else { return true }
        touch(id)
        model.put(e)
        return true
    }

    /// Deletes an element and everything that depends on it (hosted inserts, tags, view-owned annotations,
    /// viewports of deleted views, dimensions and constraints referencing it, group membership).
    public func delete(_ id: ElementID) {
        var queue = [id]
        var seen: Set<ElementID> = []
        while let cur = queue.popLast() {
            guard !seen.contains(cur), let e = model[cur] else { continue }
            seen.insert(cur)
            queue.append(contentsOf: dependents(of: e).map(\.id))
        }
        for d in seen.sorted() {
            touch(d)
            model.remove(d)
        }
        // W2-ANNOT: a dimension string loses the witness lines of deleted elements and stays while two remain.
        for d in model.elements(.dimensions) {
            guard let dd = d.dimension, dd.references.contains(where: { $0.elementID.map(seen.contains) ?? false }) else { continue }
            let keep = dd.references.indices.filter { !(dd.references[$0].elementID.map(seen.contains) ?? false) }
            if keep.count >= 2 {
                propagate(d.id) { e in
                    guard var x = e.dimension else { return }
                    x.references = keep.map { dd.references[$0] }
                    x.fallbackPoints = keep.compactMap { $0 < dd.fallbackPoints.count ? dd.fallbackPoints[$0] : nil }
                    if x.fallbackPoints.count != x.references.count { x.fallbackPoints = [] }
                    x.textOffsets = nil
                    e.dimension = x
                }
            } else {
                touch(d.id)
                model.remove(d.id)
                seen.insert(d.id)
            }
        }
        // Remove deleted ids from groups and references that tolerate removal.
        for g in model.elements(.modelGroups) + model.elements(.detailGroups) {
            guard let gd = g.group, gd.members.contains(where: seen.contains) else { continue }
            let remaining = gd.members.filter { !seen.contains($0) }
            if remaining.isEmpty { touch(g.id); model.remove(g.id) } else {
                propagate(g.id) { $0.group?.members = remaining }
            }
        }
        for w in model.elements(.walls) {
            guard let wd = w.wall else { continue }
            if wd.attachedTopIDs.contains(where: seen.contains) || wd.attachedBaseIDs.contains(where: seen.contains) {
                propagate(w.id) {
                    $0.wall?.attachedTopIDs.removeAll(where: seen.contains)
                    $0.wall?.attachedBaseIDs.removeAll(where: seen.contains)
                }
            }
        }
    }

    /// Direct dependents that must be deleted with `e`.
    private func dependents(of e: Element) -> [Element] {
        var out = model.hosted(by: e.id) + model.owned(byView: e.id) + model.tags(of: e.id) + model.viewports(showing: e.id)
        switch e.data {
        case .level:
            out += model.onLevel(e.id)
        case .view:
            out += model.views.filter { $0.view?.parentViewID == e.id }
        case .type:
            out += model.instances(ofType: e.id)
        case .family:
            out += model.elements(.elementTypes).filter { $0.typeData?.familyID == e.id }
        case .revision:
            out += model.elements(.revisionClouds).filter { $0.revisionCloud?.revisionID == e.id }
        default: break
        }
        // Dimensions and constraints referencing the element.
        // Strings of three or more references are trimmed after the deletion instead (see `delete`).
        for d in model.elements(.dimensions) where d.dimension?.references.contains(where: { $0.elementID == e.id }) == true && (d.dimension?.references.count ?? 0) <= 2 {
            out.append(d)
        }
        for c in model.elements(.constraints) where c.constraint?.references.contains(where: { $0.elementID == e.id }) == true {
            out.append(c)
        }
        return out
    }

    public func setProjectParameters(_ params: [ParameterDefinition]) {
        if projectChange.projectParametersBefore == nil { projectChange.projectParametersBefore = original.projectParameters }
        model.projectParameters = params
        projectChange.projectParametersAfter = params
    }
    public func setViewSheetSets(_ sets: [ViewSheetSet]) {
        if projectChange.sheetSetsBefore == nil { projectChange.sheetSetsBefore = original.viewSheetSets }
        model.viewSheetSets = sets
        projectChange.sheetSetsAfter = sets
    }
    /// Adds an immutable reference drawing; returns its content key.
    @discardableResult
    public func addReferenceDrawing(_ d: ReferenceDrawing) -> String {
        let key = d.contentKey
        if model.referenceDrawings[key] == nil {
            model.referenceDrawings[key] = d
            addedDrawings.append(key)
        }
        return key
    }

    public func warn(_ w: ModelWarning) { warnings.append(w) }

    public var hasChanges: Bool {
        touched.contains { id, before in before != model[id] } || !projectChange.isEmpty || !addedDrawings.isEmpty
    }

    // MARK: Commit

    /// Regenerates, solves constraints and validates. On success returns the new model and the record.
    public func commit(regenerator: Regenerator = Regenerator()) throws(TransactionError) -> (model: BIMModel, record: TransactionRecord, warnings: [ModelWarning]) {
        try regenerator.regenerate(self)
        let changes: [ElementChange] = touched.keys.sorted().compactMap { id in
            let before = touched[id] ?? nil
            var after = model[id]
            guard before != after else { return nil }
            if var a = after {
                a.revision = Element.nextRevision()
                after = a
                model.put(a)
            }
            return ElementChange(id: id, before: before, after: after)
        }
        model.bumpRevision()
        let record = TransactionRecord(name: name, changes: changes, project: projectChange, addedDrawings: addedDrawings, nextIDAfter: model.nextID)
        return (model, record, warnings)
    }

    /// Elements touched so far (for regeneration).
    public var touchedIDs: [ElementID] { touched.keys.sorted() }
    public func originalElement(_ id: ElementID) -> Element? { original[id] }
    public var originalModel: BIMModel { original }
}
