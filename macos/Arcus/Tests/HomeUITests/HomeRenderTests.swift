import AppKit
import SwiftUI
import Testing
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

// HOME: renders the Home window offscreen, light and dark, to /tmp/arcus-home/ for visual review, and checks its
// model's behaviour (card selection, arrow keys, filters, Create availability).

@MainActor
@Suite("Home window", .serialized)
struct HomeRenderTests {
    static let outDir = URL(fileURLWithPath: "/tmp/arcus-home", isDirectory: true)

    /// Sample recent files on disk (so they "exist" and have dates).
    static func sampleRecents() -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appending(path: "arcus-home-recents", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let names = ["Courtyard House.arcus", "Lakeside Clinic.arcus", "Walnut Sideboard.arcusfurniture", "Kitchen Run.arcusfurniture",
                     "Pivot Door.arcusfamily", "Office Fit-Out.arcus", "Site Survey.dwg"]
        return names.enumerated().map { i, n in
            let u = dir.appending(path: n, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-Double(i) * 86_400 * 1.7 - 3_600)], ofItemAtPath: u.path)
            return u
        }
    }

    static func sampleLibrary() -> [FurnitureLibraryCatalog.Item] {
        let base = URL(fileURLWithPath: "/nonexistent/Furniture Library")
        let rooms: [(String, [String])] = [("Living Room", ["Sofa", "Coffee Table", "TV Stand", "Armchair", "Side Table", "Bookshelf"]),
                                           ("Bedroom", ["Bed", "Bedside Table", "Wardrobe", "Dresser"]), ("Kitchen", ["Kitchen Cabinet", "Pantry Cabinet"])]
        return rooms.flatMap { room, names in names.map { FurnitureLibraryCatalog.Item(url: base.appending(path: "\(room)/\($0).arcusfurniture"), name: $0, room: room, isUser: false) } }
    }

    static func model(_ card: HomeCard?, recents: Bool = true, library: Bool = false) -> HomeModel {
        let m = HomeModel(tab: .recent, readsDisk: false)
        m.selected = card
        m.recents = recents ? sampleRecents() : []
        m.library = library ? sampleLibrary() : []
        return m
    }

    /// Lays the view out in a real (unshown) window with the Home window's chrome and writes a PNG of it.
    static func render(_ model: HomeModel, _ name: String, dark: Bool, size: CGSize = CGSize(width: 1040, height: 660)) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let w = AppDelegate.makeHubWindow(model: model)
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.setContentSize(size)
        w.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        w.contentView?.layoutSubtreeIfNeeded()
        w.displayIfNeeded()
        guard let view = w.contentView?.superview ?? w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: outDir.appending(path: "\(name)-\(dark ? "dark" : "light").png"))
        w.close()
    }

    static func renderOnboarding(_ step: Int, dark: Bool) {
        let view = NSHostingView(rootView: OnboardingView(onFinish: {}, step: step).background(Color(nsColor: .windowBackgroundColor)))
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.frame = NSRect(x: 0, y: 0, width: 720, height: 520)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: outDir.appending(path: "onboarding-\(step)-\(dark ? "dark" : "light").png"))
    }

    @Test func rendersEveryState() {
        for dark in [false, true] {
            Self.render(Self.model(nil), "home-recent", dark: dark)
            Self.render(Self.model(nil, recents: false), "home-recent-empty", dark: dark)
            Self.render(Self.model(.architectural), "home-architectural", dark: dark)
            Self.render(Self.model(.furniture), "home-furniture-empty", dark: dark)
            Self.render(Self.model(.furniture, library: true), "home-furniture", dark: dark)
            Self.render(Self.model(.family), "home-family", dark: dark)
        }
        Self.render(Self.model(nil), "home-recent-min", dark: false, size: CGSize(width: 920, height: 600))
        Self.render(Self.model(.family), "home-family-min", dark: false, size: CGSize(width: 920, height: 600))
        for step in 0..<OnboardingView.steps {
            for dark in [false, true] { Self.renderOnboarding(step, dark: dark) }
        }
        #expect(FileManager.default.fileExists(atPath: Self.outDir.appending(path: "home-recent-light.png").path))
    }
}

@MainActor
@Suite("Home model")
struct HomeModelTests {
    @Test func tabsSelectCards() {
        let m = HomeModel(tab: .new, readsDisk: false)
        #expect(m.selected == .architectural)
        m.selected = .family
        m.apply(.new)
        #expect(m.selected == .family, "New keeps a card already chosen")
        m.apply(.recent)
        #expect(m.selected == nil)
        #expect(HomeModel(tab: .recent, readsDisk: false).selected == nil)
    }

    @Test func arrowKeysMoveBetweenCards() {
        let m = HomeModel(tab: .recent, readsDisk: false)
        m.moveSelection(by: 1)
        #expect(m.selected == .architectural)
        m.moveSelection(by: 1); m.moveSelection(by: 1); m.moveSelection(by: 1)
        #expect(m.selected == .family)
        m.moveSelection(by: -1)
        #expect(m.selected == .furniture)
    }

    @Test func createNeedsANameAndACard() {
        let m = HomeModel(tab: .recent, readsDisk: false)
        #expect(m.createDisabledReason != nil)
        m.selected = .architectural
        #expect(m.createDisabledReason == nil)
        m.projectName = "  "
        #expect(m.createDisabledReason == "Name the project.")
    }

    @Test func familyNameFollowsTheCategoryUntilEdited() {
        let m = HomeModel(tab: .recent, readsDisk: false)
        #expect(m.familyName == "New Door")
        m.familyCategory = .window
        #expect(m.familyName == "New Window")
        m.familyName = "Pivot Window"; m.familyNameEdited = true
        m.familyCategory = .casework
        #expect(m.familyName == "Pivot Window")
    }

    @Test func recentFilterAndLibrarySearch() {
        let m = HomeModel(tab: .recent, readsDisk: false)
        m.recents = ["/a/A.arcus", "/a/B.arcusfurniture", "/a/C.arcusfamily"].map { URL(fileURLWithPath: $0) }
        m.recentFilter = .family
        #expect(m.filteredRecents.map(\.lastPathComponent) == ["C.arcusfamily"])
        m.library = HomeRenderTests.sampleLibrary()
        m.furnitureSearch = "ward"
        #expect(m.libraryRooms.flatMap(\.items).map(\.name) == ["Wardrobe"])
    }
}

@MainActor
@Suite("Home ▸ Family", .serialized)
struct HomeFamilyStartTests {
    /// With no project open, the editor gets a hidden Imperial project; the first Load into Project opens it, and
    /// closing the editor without loading discards it.
    @Test func familyWithoutAProjectGetsAHiddenProject() async throws {
        _ = NSApplication.shared
        let before = FamilyEditorWindowController.open.count
        HomeFamilyStart.open(category: .window, name: "Pivot Window")
        let wc = try #require(FamilyEditorWindowController.open.last)
        #expect(FamilyEditorWindowController.open.count == before + 1)
        #expect(wc.model.family.name == "Pivot Window")
        #expect(wc.model.family.template == .window)
        #expect(wc.model.state.model.units == .imperial)
        #expect(HomeFamilyStart.pendingCount == 1)
        #expect(!NSDocumentController.shared.documents.contains { $0 === wc.model.state.document })
        #expect(wc.model.loadIntoProject())
        try await Task.sleep(for: .milliseconds(200))
        #expect(HomeFamilyStart.pendingCount == 0)
        let doc = try #require(wc.model.state.document)
        #expect(NSDocumentController.shared.documents.contains { $0 === doc })
        #expect(doc.state.model.family(named: "Pivot Window") != nil)
        wc.close()
        doc.updateChangeCount(.changeCleared)
        doc.close()

        HomeFamilyStart.open(category: .door, name: "")
        let second = try #require(FamilyEditorWindowController.open.last)
        #expect(second.model.family.name == "Door")
        #expect(HomeFamilyStart.pendingCount == 1)
        second.close()
        #expect(HomeFamilyStart.pendingCount == 0)
    }
}
