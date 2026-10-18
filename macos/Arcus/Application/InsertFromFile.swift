import Foundation
import ArcusGeometry
import ArcusDomain

// F67: Insert ▸ Load as Group and Insert from File (views and 2D elements), copying from another project with the
// same matching rules as pasting between projects (types, families, materials and styles by name).

public enum InsertFromFile {
    // MARK: Load as Group

    /// The model elements of `src` that Load as Group brings across.
    static func groupableIDs(_ src: BIMModel) -> [ElementID] {
        src.allElements.filter { e in
            e.category.isModel && e.ownerViewID == nil && !e.isType && ProjectTransfer.isTransferable(e)
        }.map(\.id).sorted()
    }

    /// Load as Group: the model of another project as one model group, internal origin to internal origin. Elements
    /// on levels the project lacks go to `fallbackLevel` (else the lowest level).
    public static func loadAsGroup(_ src: BIMModel, name: String, fallbackLevel: ElementID? = nil, in tx: TransactionContext) throws -> (group: ElementID, report: PasteReport) {
        let ids = groupableIDs(src)
        guard !ids.isEmpty, let payload = ClipboardPayload.capture(ids, from: src, viewID: nil, levelID: src.levels.first?.id) else {
            throw InsertError("The file has no model elements to load as a group.")
        }
        let report = ProjectTransfer.paste(payload, into: tx, targetView: nil, fallbackLevel: fallbackLevel ?? tx.model.levels.first?.id)
        let top = report.pasted.filter { tx.model[$0]?.groupID == nil }
        guard !top.isEmpty else { throw InsertError("None of the file's model elements could be loaded.") }
        let names = Set(tx.model.elements(.modelGroups).compactMap { $0.group?.groupTypeName })
        var n = name.isEmpty ? "Group" : name, k = 2
        while names.contains(n) { n = "\(name) \(k)"; k += 1 }
        let gid = tx.create(.modelGroups, name: n, data: .group(GroupData(members: top, origin: .zero, groupTypeName: n)))
        for m in top { tx.update(m) { $0.groupID = gid } }
        return (gid, report)
    }

    // MARK: Insert Views from File

    /// Views of another project Insert Views can copy: drafting views, legends and schedules.
    public static func insertableViews(_ src: BIMModel) -> [Element] {
        let views = src.views.filter { $0.view?.kind == .drafting || $0.view?.kind == .legend }
        let schedules = src.schedules.filter { $0.schedule?.kind != nil }
        return (views + schedules).sorted { ($0.category.rawValue, $0.name) < ($1.category.rawValue, $1.name) }
    }

    /// Insert Views from File: copies the chosen drafting views, legends and schedules with their 2D content.
    /// A name already used in this project gets a number. Returns the new views.
    public static func insertViews(_ ids: [ElementID], from src: BIMModel, in tx: TransactionContext) throws -> (views: [ElementID], report: PasteReport) {
        var created: [ElementID] = []
        var total = PasteReport()
        for id in ids {
            guard let v = src[id] else { continue }
            let name = uniqueName(v.name, among: Set((tx.model.views + tx.model.schedules).map(\.name)))
            if var sd = v.schedule {
                sd.phaseID = sd.phaseID.flatMap { p in src[p].flatMap { s in tx.model.phases.first { $0.name == s.name }?.id } }
                let nid = tx.create(.schedules, name: name, data: .schedule(sd))
                created.append(nid)
                continue
            }
            guard var vd = v.view, vd.kind == .drafting || vd.kind == .legend else { continue }
            vd.templateID = nil; vd.parentViewID = nil; vd.underlayLevelID = nil; vd.scopeBoxID = nil; vd.colorSchemeID = nil; vd.areaSchemeID = nil
            vd.phaseID = vd.phaseID.flatMap { p in src[p].flatMap { s in tx.model.phases.first { $0.name == s.name }?.id } }
            vd.designOptions = [:]
            vd.visibility.hiddenElements = []; vd.visibility.elementOverrides = [:]; vd.visibility.hiddenLinkLayers = [:]
            vd.visibility.filters = []
            let nid = tx.create(.views, name: name, data: .view(vd))
            created.append(nid)
            let r = try copy2D(from: id, of: src, into: nid, in: tx, allowEmpty: true)
            total.pasted += r.pasted; total.addedTypes += r.addedTypes; total.duplicateTypes += r.duplicateTypes; total.skipped += r.skipped
        }
        guard !created.isEmpty else { throw InsertError("None of the chosen views could be inserted.") }
        return (created, total)
    }

    // MARK: Insert 2D Elements from File

    /// The views of another project whose 2D elements can be inserted: drafting views and legends with content.
    public static func viewsWith2DElements(_ src: BIMModel) -> [Element] {
        src.views.filter { ($0.view?.kind == .drafting || $0.view?.kind == .legend) && !src.owned(byView: $0.id).isEmpty }.sorted { $0.name < $1.name }
    }

    /// Insert 2D Elements: the detail lines, text, regions, detail components, dimensions and clouds of a drafting view
    /// or legend in another project, copied into `targetView` at the same coordinates.
    @discardableResult
    public static func insert2DElements(from viewID: ElementID, of src: BIMModel, into targetView: ElementID, in tx: TransactionContext) throws -> PasteReport {
        guard tx.model[targetView]?.view != nil || tx.model[targetView]?.sheet != nil else { throw InsertError("Open a 2D view to insert 2D elements into.") }
        return try copy2D(from: viewID, of: src, into: targetView, in: tx, allowEmpty: false)
    }

    static func copy2D(from viewID: ElementID, of src: BIMModel, into target: ElementID, in tx: TransactionContext, allowEmpty: Bool) throws -> PasteReport {
        let owned = src.owned(byView: viewID).filter { ProjectTransfer.isTransferable($0) }.map(\.id)
        guard !owned.isEmpty, var payload = ClipboardPayload.capture(owned, from: src, viewID: viewID, levelID: nil) else {
            if allowEmpty { return PasteReport() }
            throw InsertError("The view has no 2D elements to insert.")
        }
        // Legend components refer to the type they show: carry it (and what it refers to) along.
        var queue = payload.elements.compactMap { $0.detailComponent?.legendTypeID }
        while let id = queue.popLast() {
            guard payload.context[id] == nil, let e = src[id], ProjectTransfer.isSupporting(e) else { continue }
            payload.context[id] = e
            queue += ProjectTransfer.references(of: e)
        }
        let before = Set(tx.model.allElements.map(\.id))
        let report = ProjectTransfer.paste(payload, into: tx, targetView: target, fallbackLevel: nil)
        // Remap legend types with a resolver over the same context (types were matched or added by the paste).
        var r = ProjectTransfer.Resolver(payload: payload, tx: tx)
        for id in report.pasted where !before.contains(id) {
            guard var d = tx.model[id]?.detailComponent, let lt = d.legendTypeID else { continue }
            d.legendTypeID = r.resolve(lt)
            tx.update(id) { $0.data = .detailComponent(d) }
        }
        return report
    }

    static func uniqueName(_ base: String, among names: Set<String>) -> String {
        var n = base, k = 2
        while names.contains(n) { n = "\(base) (\(k))"; k += 1 }
        return n
    }
}
