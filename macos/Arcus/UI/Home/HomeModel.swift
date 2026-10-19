import AppKit
import SwiftUI
import ArcusDomain
import ArcusApplication
import ArcusPersistence

// HOME: state and actions of the Home window (Docs/FurnitureMode.md §4). The view reads it; QA drives it.

/// What Home starts: the three Start cards.
enum HomeCard: String, CaseIterable, Identifiable {
    case architectural, furniture, family
    var id: String { rawValue }

    var title: String {
        switch self {
        case .architectural: "Architectural Project"
        case .furniture: "Furniture"
        case .family: "Family"
        }
    }
    var line: String {
        switch self {
        case .architectural: "Buildings, sheets and schedules. Imperial."
        case .furniture: "Custom pieces, cut lists and CNC."
        case .family: "Doors, windows and components."
        }
    }
    var createTitle: String {
        switch self {
        case .architectural: "Create Project"
        case .furniture: "Create Furniture"
        case .family: "Create Family"
        }
    }
    /// The card's accent, used by its illustration, its selection and the matching Recent badge.
    var tint: Color { HomeStyle.tint(self) }
}

/// The Home window's state: the selected card, each card's choices, and the Recent grid.
@MainActor
@Observable
final class HomeModel {
    /// The selected card; nil shows Recent.
    var selected: HomeCard?
    /// True while the sample project is being built.
    var openingSample = false

    // Architectural
    var projectName = "Untitled Project"
    var template: ProjectTemplateChoice = .builtIn(.architectural)
    var userTemplates: [UserTemplates.Entry] = []
    var browsedTemplates: [URL] = []

    // Furniture
    var furnitureName = "Untitled Furniture"
    var furnitureCategory: FamilyTemplate = .furniture
    var furnitureSearch = ""
    /// The library piece to start from; nil is Blank.
    var furnitureTemplate: URL?
    var library: [FurnitureLibraryCatalog.Item] = []
    /// FMG4: the name the last picked piece filled in (so picking another piece renames it, but a typed name stays).
    var furnitureAutoName: String?

    // Family
    var familyCategory: FamilyTemplate = .door { didSet { if !familyNameEdited { familyName = Self.defaultFamilyName(familyCategory) } } }
    var familyName = HomeModel.defaultFamilyName(.door)
    /// True once the user typed a family name (changing the category then keeps it).
    var familyNameEdited = false

    // Recent
    var recentFilter: HomeDocumentKind?
    var recents: [URL] = []

    init(tab: AppDelegate.HubTab, readsDisk: Bool = true) {
        self.readsDisk = readsDisk
        apply(tab)
        reload()
    }

    /// `.new` selects Architectural (unless a card is already selected); `.furniture` selects Furniture; `.recent` shows
    /// Recent.
    func apply(_ tab: AppDelegate.HubTab) {
        switch tab {
        case .new: if selected == nil { selected = .architectural }
        case .recent: selected = nil
        case .furniture: selected = .furniture
        }
    }

    /// False for offscreen renders and tests that set the lists themselves.
    @ObservationIgnored var readsDisk = true

    /// Re-reads the recent documents, user templates and the furniture library.
    func reload() {
        guard readsDisk else { return }
        recents = RecentDocuments.urls()
        userTemplates = UserTemplates.list()
        library = FurnitureLibraryCatalog.all()
    }

    static func defaultFamilyName(_ c: FamilyTemplate) -> String { "New \(c.rawValue)" }

    var filteredRecents: [URL] { HomeDocumentKind.filter(recents, recentFilter) }
    var libraryRooms: [FurnitureLibraryCatalog.Room] { FurnitureLibraryCatalog.rooms(library, matching: furnitureSearch) }

    /// Moves the selection to the previous or next card (arrow keys); from Recent, any arrow selects the first card.
    func moveSelection(by delta: Int) {
        let all = HomeCard.allCases
        guard let s = selected, let i = all.firstIndex(of: s) else { selected = all.first; return }
        selected = all[max(0, min(all.count - 1, i + delta))]
    }

    // MARK: Actions

    /// FMG4: picks the piece to start from (nil: Blank). The name and category follow the piece unless the user typed
    /// a name of their own, so picking Entryway Bench and then Kitchen Cart starts a Kitchen Cart.
    func pickFurnitureTemplate(_ item: FurnitureLibraryCatalog.Item?) {
        furnitureTemplate = item?.url
        let typed = furnitureName != "Untitled Furniture" && furnitureName != furnitureAutoName
        if !typed {
            furnitureName = item?.name ?? "Untitled Furniture"
            furnitureAutoName = item?.name
        }
        if let c = item?.category { furnitureCategory = c == "Casework" ? .casework : .furniture }
    }

    /// Return / Create: starts the selected card's document.
    func create() {
        switch selected {
        case .architectural:
            switch template {
            case .builtIn(let kind): AppDelegate.shared?.newProject(template: kind, units: .imperial, name: projectName)
            case .user(let url): UserTemplates.newProject(from: url, name: projectName)
            }
        case .furniture:
            AppDelegate.shared?.newFurniture(name: furnitureName, category: furnitureCategory, template: furnitureTemplate)
        case .family:
            HomeFamilyStart.open(category: familyCategory, name: familyName)
        case nil: break
        }
    }

    /// Why Create can't run now, or nil.
    var createDisabledReason: String? {
        switch selected {
        case .architectural: projectName.trimmingCharacters(in: .whitespaces).isEmpty ? "Name the project." : nil
        case .furniture: furnitureName.trimmingCharacters(in: .whitespaces).isEmpty ? "Name the piece." : nil
        case .family: familyName.trimmingCharacters(in: .whitespaces).isEmpty ? "Name the family." : nil
        case nil: "Choose what to start."
        }
    }

    func openPanel() { NSDocumentController.shared.openDocument(nil) }

    func openSample() {
        openingSample = true
        AppDelegate.shared?.openSample()
    }

    func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            MainActor.assumeIsolated {
                if let error { NSAlert(error: error).runModal() } else { AppDelegate.shared?.closeHub() }
            }
        }
    }

    // MARK: Templates (Architectural)

    var isUserTemplate: Bool { if case .user = template { return true }; return false }

    var templateTitle: String {
        switch template {
        case .builtIn(let k): k.rawValue
        case .user(let url): url.deletingPathExtension().lastPathComponent
        }
    }

    func browseTemplate() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.arcusProject]
        panel.message = "Choose an Arcus template or project to start from. Model elements are left out of the new project."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !browsedTemplates.contains(url) && !userTemplates.contains(where: { $0.url == url }) { browsedTemplates.append(url) }
        template = .user(url)
    }

    func trashTemplate(_ url: URL) {
        NSWorkspace.shared.recycle([url]) { _, error in
            let message = error?.localizedDescription
            Task { @MainActor in
                if let message {
                    let a = NSAlert()
                    a.messageText = "Couldn't move the template to the Trash."
                    a.informativeText = message
                    a.runModal()
                    return
                }
                self.userTemplates = UserTemplates.list()
                self.template = .builtIn(.architectural)
            }
        }
    }

    func openTemplatesFolder() {
        guard let dir = UserTemplates.directory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    /// Furniture ▸ the user's furniture templates folder (created on demand).
    func openFurnitureTemplatesFolder() {
        guard let dir = FurnitureLibraryCatalog.userRoot else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}
