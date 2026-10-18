import Foundation

// F11: project-wide Manage data (RevitCraft keeps these on its Project): global parameters, saved selections, the
// starting view, the keynote table and Keynoting Settings, and Print Setup. Stored in `ProjectInfoData.f11`, so it
// saves with the project, undoes with the Project Information element and older files open unchanged.

/// Project-wide values made in the Manage tab and Print Setup.
public struct ManageProjectData: Hashable, Codable, Sendable {
    /// Manage ▸ Global Parameters, in the order the dialog lists them.
    public var globalParameters: [GlobalParameter] = []
    /// Manage ▸ Selection: saved selections.
    public var selectionSets: [SelectionSet] = []
    /// Manage Project ▸ Starting View: the view opened with the project (nil = the default first plan).
    public var startingViewID: ElementID?
    /// Keynoting Settings: a loaded keynote table (nil = the built-in table) and the name of the file it came from.
    public var keynoteTable: [KeynoteRecord]?
    public var keynoteFile: String?
    /// Keynoting Settings: what keynote tags show unless a tag chooses for itself.
    public var keynoteDisplay: KeynoteDisplay?
    /// File ▸ Print ▸ Print Setup (also the defaults of PDF export).
    public var printSetup: PrintSetup?
    public init() {}
}

extension ProjectInfoData {
    /// The Manage data of the project (empty when the file has none).
    public var manage: ManageProjectData {
        get { f11 ?? ManageProjectData() }
        set { f11 = newValue == ManageProjectData() ? nil : newValue }
    }
}

extension BIMModel {
    /// The Manage data of the project.
    public var manageData: ManageProjectData { projectInfo.manage }
}

extension TransactionContext {
    /// Edits the project's Manage data (one element update of Project Information, so it undoes in the same step).
    public func updateManageData(_ change: (inout ManageProjectData) -> Void) {
        guard let pid = model.projectInfoElement?.id else { return }
        update(pid) { e in
            guard var info = e.projectInfo else { return }
            change(&info.manage)
            e.projectInfo = info
        }
    }
}

/// A named saved selection (Manage ▸ Selection ▸ Save).
public struct SelectionSet: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var elementIDs: [ElementID]
    public init(name: String, elementIDs: [ElementID]) { id = UUID().uuidString; self.name = name; self.elementIDs = elementIDs }
}

/// Saved selections: save, load (dropping elements deleted since), rename and delete.
public enum SavedSelections {
    /// The next default name ("Selection 3").
    public static func nextName(_ model: BIMModel) -> String {
        let used = Set(model.manageData.selectionSets.map(\.name))
        var n = model.manageData.selectionSets.count + 1
        while used.contains("Selection \(n)") { n += 1 }
        return "Selection \(n)"
    }

    /// Saves `ids` under `name` (replacing a set of the same name, as RevitCraft does). Throws for an empty name or selection.
    public static func save(_ ids: [ElementID], name: String, in tx: TransactionContext) throws(TransactionError) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw TransactionError("Enter a name for the selection.") }
        let kept = ids.filter { tx.model[$0] != nil }
        guard !kept.isEmpty else { throw TransactionError("Select elements to save first.") }
        tx.updateManageData { d in
            if let i = d.selectionSets.firstIndex(where: { $0.name == n }) { d.selectionSets[i].elementIDs = kept }
            else { d.selectionSets.append(SelectionSet(name: n, elementIDs: kept)) }
        }
    }

    /// The elements of a saved selection that still exist.
    public static func elements(of setID: String, _ model: BIMModel) -> [ElementID] {
        model.manageData.selectionSets.first { $0.id == setID }?.elementIDs.filter { model[$0] != nil } ?? []
    }

    public static func rename(_ setID: String, to name: String, in tx: TransactionContext) throws(TransactionError) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw TransactionError("Enter a name for the selection.") }
        if tx.model.manageData.selectionSets.contains(where: { $0.name == n && $0.id != setID }) { throw TransactionError("A saved selection named “\(n)” already exists.") }
        tx.updateManageData { d in if let i = d.selectionSets.firstIndex(where: { $0.id == setID }) { d.selectionSets[i].name = n } }
    }

    public static func delete(_ setID: String, in tx: TransactionContext) {
        tx.updateManageData { d in d.selectionSets.removeAll { $0.id == setID } }
    }
}

/// Manage Project ▸ Starting View.
public enum StartingView {
    /// The starting view if it still exists and can be opened.
    public static func view(_ model: BIMModel) -> Element? {
        guard let id = model.manageData.startingViewID, let e = model[id], e.view != nil || e.sheet != nil || e.schedule != nil else { return nil }
        return e
    }
    public static func set(_ id: ElementID?, in tx: TransactionContext) {
        tx.updateManageData { $0.startingViewID = id }
    }
}

/// File ▸ Print Setup: paper, orientation, zoom, colours and the hide options shared with PDF export.
public struct PrintSetup: Hashable, Codable, Sendable {
    public enum Colors: String, Codable, Sendable, CaseIterable { case color = "Color", blackLines = "Black Lines", grayscale = "Grayscale" }
    public enum Zoom: String, Codable, Sendable, CaseIterable { case fitToPage = "Fit to page", actual = "Zoom 100%" }
    /// Paper for views (sheets always print at their own size).
    public var paper: PaperSize = .a3
    public var landscape = true
    public var zoom: Zoom = .fitToPage
    public var colors: Colors = .color
    public var hideReferencePlanes = true
    public var hideScopeBoxes = true
    public var hideCropBoundaries = true
    public var hideUnreferencedViewTags = false
    public init() {}
}
