import Foundation
import Testing
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

// HOME: Home's data: the template kinds it offers, the furniture library scan and the Recent kinds and filter.

@Suite("Home")
struct HomeTests {
    @Test func residentialIsGoneAndEmptyStaysForTests() {
        #expect(ProjectTemplateKind.allCases == [.architectural, .empty])
        #expect(ProjectTemplateKind(rawValue: "Residential") == nil)
    }

    @Test func architecturalImperialProjectsAreImperial() {
        let (m, _) = ProjectTemplates.make(.architectural, units: .imperial, projectName: "House")
        #expect(m.units == .imperial)
        #expect(m.projectInfo.projectName == "House")
        #expect(m.types(for: .stairs).contains { $0.name == "Monolithic - 7\" max riser" })
        #expect(!m.allElements.contains { $0.name.hasPrefix("Residential") })
    }

    /// A temporary folder tree; removed when the test ends.
    final class Tree {
        let root = FileManager.default.temporaryDirectory.appending(path: "arcus-home-\(UUID().uuidString)", directoryHint: .isDirectory)
        func add(_ path: String) {
            let u = root.appending(path: path, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }
    }

    @Test func libraryScansRoomsAndUserTemplates() {
        let bundle = Tree(), user = Tree()
        bundle.add("Living Room/Sofa.arcusfurniture")
        bundle.add("Living Room/Coffee Table.arcusfurniture")
        bundle.add("Kitchen/Kitchen Cabinet.arcusfurniture")
        bundle.add("Kitchen/notes.txt")
        bundle.add("Loose.arcusfurniture") // bundled pieces live in room folders only
        user.add("My Bench.arcusfurniture")
        user.add("Workshop/Tool Chest.arcusfurniture")
        let items = FurnitureLibraryCatalog.scan(bundled: bundle.root, user: user.root)
        #expect(items.map(\.name).sorted() == ["Coffee Table", "Kitchen Cabinet", "My Bench", "Sofa", "Tool Chest"])
        #expect(items.first { $0.name == "My Bench" }?.room == FurnitureLibraryCatalog.myTemplatesRoom)
        #expect(items.first { $0.name == "Tool Chest" }?.isUser == true)
        #expect(items.first { $0.name == "Sofa" }?.isUser == false)
        let rooms = FurnitureLibraryCatalog.rooms(items)
        #expect(rooms.map(\.name) == ["Kitchen", "Living Room", "Workshop", "My Templates"])
        #expect(rooms[1].items.map(\.name) == ["Coffee Table", "Sofa"])
        #expect(FurnitureLibraryCatalog.rooms(items, matching: "sofa").map(\.name) == ["Living Room"])
        #expect(FurnitureLibraryCatalog.rooms(items, matching: "kitchen").flatMap(\.items).map(\.name) == ["Kitchen Cabinet"])
        #expect(FurnitureLibraryCatalog.rooms(items, matching: "zebra").isEmpty)
    }

    @Test func missingLibraryFoldersGiveNoPieces() {
        let nowhere = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(FurnitureLibraryCatalog.scan(bundled: nowhere, user: nil).isEmpty)
        #expect(FurnitureLibraryCatalog.rooms([]).isEmpty)
    }

    @Test func recentKindsComeFromTheExtension() {
        let urls = ["/a/House.arcus", "/a/Sideboard.arcusfurniture", "/a/Door.ARCUSFAMILY", "/a/Plan.dwg"].map { URL(fileURLWithPath: $0) }
        #expect(urls.map { HomeDocumentKind(url: $0) } == [.project, .furniture, .family, nil])
        #expect(HomeDocumentKind.filter(urls, nil) == urls)
        #expect(HomeDocumentKind.filter(urls, .furniture).map(\.lastPathComponent) == ["Sideboard.arcusfurniture"])
        #expect(HomeDocumentKind.filter(urls, .project).count == 1)
        #expect(HomeDocumentKind.allCases.map(\.filterTitle) == ["Projects", "Furniture", "Families"])
    }
}
