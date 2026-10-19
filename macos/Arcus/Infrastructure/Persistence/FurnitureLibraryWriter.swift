import Foundation
import ArcusDomain

// FM9: writes the Furniture Library (`arcus-bench --furniture-library <dir>`): every registered piece as
// `<dir>/<Room>/<Name>.arcusfurniture` (in its first room) with its 3D preview, and `<dir>/index.json` listing each
// piece's rooms, category, detail, keywords and type sizes. Pieces build in parallel; identifiers, dates and the
// document ids are derived from the piece, so a rebuild writes the same bytes.

public enum FurnitureLibraryWriter {
    /// What one piece came to.
    public struct Result: Sendable {
        public var name: String
        public var file: String
        public var error: String?
        public var seconds: Double
    }

    /// A fixed date for the packages' created and modified stamps (stable files).
    public static let libraryDate = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01

    /// Builds and writes `pieces` under `dir` (replacing the folder's room folders and index), with `thumbnail` drawing
    /// each preview. Returns one result per piece, in order, and the index written.
    @discardableResult
    public static func write(_ pieces: [FurnitureLibraryPiece], to dir: URL, appVersion: String, build: String,
                             thumbnail: @escaping @Sendable (BIMModel) -> Data?) throws -> (results: [Result], index: FurnitureLibraryIndex) {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // Room folders from an earlier build go, so renamed or removed pieces don't linger.
        for entry in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [] {
            if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { try fm.removeItem(at: entry) }
        }
        let names = pieces.map(\.name)
        let duplicates = Set(names.filter { n in names.filter { $0 == n }.count > 1 })
        let box = ResultsBox(count: pieces.count)
        DispatchQueue.concurrentPerform(iterations: pieces.count) { i in
            let p = pieces[i]
            let t0 = Date()
            let rel = FurnitureLibraryIndex.relativePath(p)
            var error: String? = duplicates.contains(p.name) ? "Two pieces are named “\(p.name)”." : nil
            let built = p.build()
            if let e = LibraryKit.buildError(built) { error = e }
            let m = FurnitureLibrary.stabilized(built, seed: p.name)
            let entry = FurnitureLibraryIndex.entry(p, m)
            if error == nil {
                do {
                    let url = dir.appending(path: rel, directoryHint: .notDirectory)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    var info = ArcusPackage.WriteInfo(documentID: UUID(uuidString: FurnitureLibrary.deterministicUUID("document/" + p.name)) ?? UUID(),
                                                      appVersion: appVersion, build: build, created: libraryDate, thumbnailPNG: thumbnail(m))
                    info.modified = libraryDate
                    try ArcusPackage.write(m, to: url, info: info)
                } catch let e {
                    error = "\(e)"
                }
            }
            box.set(i, Result(name: p.name, file: rel, error: error, seconds: Date().timeIntervalSince(t0)), error == nil ? entry : nil)
        }
        let index = FurnitureLibraryIndex(pieces: box.entries.compactMap { $0 })
        try index.encoded().write(to: dir.appending(path: FurnitureLibraryIndex.fileName, directoryHint: .notDirectory), options: .atomic)
        return (box.results.compactMap { $0 }, index)
    }

    /// Results gathered from the parallel builds.
    final class ResultsBox: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var results: [Result?]
        private(set) var entries: [FurnitureLibraryIndex.Piece?]
        init(count: Int) { results = Array(repeating: nil, count: count); entries = Array(repeating: nil, count: count) }
        func set(_ i: Int, _ r: Result, _ e: FurnitureLibraryIndex.Piece?) {
            lock.lock(); results[i] = r; entries[i] = e; lock.unlock()
        }
    }
}
