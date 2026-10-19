import Foundation
import Testing
@testable import ArcusDomain
import ArcusPersistence

/// FM9C: the part B simple pieces write as the library generator writes them (`<Room>/<Name>.arcusfurniture` in their
/// first room, listed in index.json under every room) and read back as Furniture documents with their types.
@Suite("FM9C library files")
struct FM9CLibraryWriteTests {
    @Test func thePartBPiecesWriteAndReadBack() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "arcus-fm9c-library-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pieces = FurnitureLibrary.simpleB
        let (results, index) = try FurnitureLibraryWriter.write(pieces, to: dir, appVersion: "1.0", build: "1", thumbnail: { _ in nil })
        #expect(results.count == 86)
        #expect(results.allSatisfy { $0.error == nil }, "\(results.filter { $0.error != nil }.prefix(3).map { "\($0.name): \($0.error ?? "")" })")
        #expect(index.pieces.count == 86)
        for p in pieces {
            let url = dir.appending(path: FurnitureLibraryIndex.relativePath(p), directoryHint: .notDirectory)
            #expect(url.pathComponents.dropLast().last == p.rooms[0], "\(p.name) is saved in its first room")
            let m = try ArcusPackage.read(from: url).model
            #expect(m.isFurniture && m.furnitureSetup?.family.types.isEmpty == false, "\(p.name) reads back")
        }
    }
}
