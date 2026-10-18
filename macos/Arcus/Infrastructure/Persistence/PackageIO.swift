import Foundation

/// Read access to the files of a package, either a directory on disk or an in-memory `FileWrapper`.
protocol PackageSource {
    /// Location used in user-facing messages (nil for in-memory wrappers).
    var displayURL: URL? { get }
    func exists(_ rel: String) -> Bool
    /// Reads a file, refusing files larger than `maxBytes`. Returns nil when missing.
    func read(_ rel: String, maxBytes: Int) throws -> Data?
    func sha256(_ rel: String) throws -> String?
    /// File names directly inside a sub-directory.
    func list(_ dir: String) -> [String]
    func openDatabase(_ rel: String) throws -> SQLiteDatabase
    var isPackageDirectory: Bool { get }
}

struct TooLarge: Error { var size: Int; var limit: Int }

struct DirectorySource: PackageSource {
    let root: URL
    var displayURL: URL? { root }
    var isPackageDirectory: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) && isDir.boolValue
    }
    private func url(_ rel: String) -> URL { root.appending(path: rel, directoryHint: .notDirectory) }

    func exists(_ rel: String) -> Bool { FileManager.default.fileExists(atPath: url(rel).path) }

    func read(_ rel: String, maxBytes: Int) throws -> Data? {
        let u = url(rel)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: u.path) else { return nil }
        // Refuse symlinks and special files inside packages.
        guard (attrs[.type] as? FileAttributeType) == .typeRegular else { return nil }
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxBytes else { throw TooLarge(size: size, limit: maxBytes) }
        return try Data(contentsOf: u)  // not memory-mapped: a file truncated underneath must not SIGBUS
    }

    func sha256(_ rel: String) throws -> String? {
        let u = url(rel)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: u.path), (attrs[.type] as? FileAttributeType) == .typeRegular else { return nil }
        return try Checksum.hex(fileAt: u)
    }

    func list(_ dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: dir, directoryHint: .isDirectory).path)) ?? []).sorted()
    }

    func openDatabase(_ rel: String) throws -> SQLiteDatabase {
        let u = url(rel)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: u.path), (attrs[.type] as? FileAttributeType) == .typeRegular else {
            throw SQLiteError(code: 14, message: "model.sqlite is missing")
        }
        return try SQLiteDatabase.openReadOnly(path: u.path)
    }
}

struct WrapperSource: PackageSource {
    let wrapper: FileWrapper
    var displayURL: URL? { wrapper.filename.map { URL(fileURLWithPath: $0) } }
    var isPackageDirectory: Bool { wrapper.isDirectory }

    private func node(_ rel: String) -> FileWrapper? {
        var cur: FileWrapper? = wrapper
        for part in rel.split(separator: "/") {
            guard let c = cur, c.isDirectory else { return nil }
            cur = c.fileWrappers?[String(part)]
        }
        return cur
    }
    func exists(_ rel: String) -> Bool { node(rel) != nil }
    func read(_ rel: String, maxBytes: Int) throws -> Data? {
        guard let n = node(rel), n.isRegularFile, let d = n.regularFileContents else { return nil }
        guard d.count <= maxBytes else { throw TooLarge(size: d.count, limit: maxBytes) }
        return d
    }
    func sha256(_ rel: String) throws -> String? {
        guard let n = node(rel), n.isRegularFile, let d = n.regularFileContents else { return nil }
        return Checksum.hex(d)
    }
    func list(_ dir: String) -> [String] {
        guard let n = node(dir), n.isDirectory else { return [] }
        return (n.fileWrappers?.keys.map { $0 } ?? []).sorted()
    }
    func openDatabase(_ rel: String) throws -> SQLiteDatabase {
        guard let d = try read(rel, maxBytes: Int.max) else { throw SQLiteError(code: 14, message: "model.sqlite is missing") }
        return try SQLiteDatabase.deserialize(d)
    }
}

/// Writing package directories safely.
enum PackageWriter {
    /// Files keyed by relative path (directories are implied by `/`).
    typealias Files = [(path: String, data: Data)]

    static func fileWrapper(_ files: Files) -> FileWrapper {
        let root = FileWrapper(directoryWithFileWrappers: [:])
        for f in files {
            var parts = f.path.split(separator: "/").map(String.init)
            let name = parts.removeLast()
            var dir = root
            for p in parts {
                if let existing = dir.fileWrappers?[p], existing.isDirectory { dir = existing; continue }
                let sub = FileWrapper(directoryWithFileWrappers: [:])
                sub.preferredFilename = p
                dir.addFileWrapper(sub)
                dir = sub
            }
            let fw = FileWrapper(regularFileWithContents: f.data)
            fw.preferredFilename = name
            dir.addFileWrapper(fw)
        }
        return root
    }

    /// Writes all files into a staging directory on the destination volume, fsyncs them, then moves the staged
    /// package into place (rename when `url` is new; `replaceItemAt` when it exists). `url` never holds a partial package.
    static func write(_ files: Files, to url: URL) throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: parent.path, isDirectory: &isDir), isDir.boolValue else {
            throw PersistenceError.io(url, "save", CocoaError(.fileNoSuchFile))
        }
        let tempRoot: URL
        if let t = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: parent, create: true) {
            tempRoot = t
        } else {
            tempRoot = parent.appending(path: ".arcus-save-\(UUID().uuidString)", directoryHint: .isDirectory)
            do { try fm.createDirectory(at: tempRoot, withIntermediateDirectories: false) } catch { throw PersistenceError.io(url, "save", error) }
        }
        defer { try? fm.removeItem(at: tempRoot) }
        let staged = tempRoot.appending(path: url.lastPathComponent, directoryHint: .isDirectory)
        do {
            try fm.createDirectory(at: staged, withIntermediateDirectories: true)
            for f in files {
                let dest = staged.appending(path: f.path, directoryHint: .notDirectory)
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard fm.createFile(atPath: dest.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
                let h = try FileHandle(forWritingTo: dest)
                try h.write(contentsOf: f.data)
                try h.synchronize()
                try h.close()
            }
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: staged, backupItemName: nil, options: [])
            } else {
                try fm.moveItem(at: staged, to: url)
            }
        } catch let e as PersistenceError {
            throw e
        } catch {
            throw PersistenceError.io(url, "save", error)
        }
    }
}
