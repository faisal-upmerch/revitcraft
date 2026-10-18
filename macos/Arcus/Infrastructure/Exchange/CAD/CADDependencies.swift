import Foundation

/// An external file a drawing refers to (xref, raster image or font).
public struct CADDependency: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable { case xref, image, font }
    public enum Status: String, Sendable, Hashable {
        case found
        case missing
        /// The declared path is absolute or escapes the drawing's folder; it is never read automatically.
        case outsideParentFolder
    }
    public var name: String
    public var kind: Kind
    public var declaredPath: String
    public var resolvedURL: URL?
    public var status: Status
    public init(name: String, kind: Kind, declaredPath: String, resolvedURL: URL?, status: Status) {
        self.name = name; self.kind = kind; self.declaredPath = declaredPath; self.resolvedURL = resolvedURL; self.status = status
    }
}

public enum CADDependencies {
    /// Lists xrefs/images/fonts relative to the parent file (never searches unrelated directories).
    ///
    /// Relative paths are resolved against the folder containing `parentURL`. Absolute paths and paths that escape that
    /// folder (`../..`, symlinks pointing elsewhere) are reported as `.outsideParentFolder` and are never read automatically;
    /// the user can choose the file explicitly, which is passed back in `userResolved` (keyed by name or declared path).
    public static func scan(_ doc: CADDocument, parentURL: URL, userResolved: [String: URL] = [:]) -> [CADDependency] {
        let folder = parentURL.hasDirectoryPath ? parentURL : parentURL.deletingLastPathComponent()
        var out: [CADDependency] = []
        func user(_ name: String, _ declared: String) -> URL? { userResolved[name] ?? userResolved[declared] }
        func make(_ name: String, _ kind: CADDependency.Kind, _ declared: String) -> CADDependency {
            if let u = user(name, declared) {
                let exists = FileManager.default.fileExists(atPath: u.path)
                return CADDependency(name: name, kind: kind, declaredPath: declared, resolvedURL: exists ? u : nil, status: exists ? .found : .missing)
            }
            let r = resolve(declared, in: folder)
            return CADDependency(name: name, kind: kind, declaredPath: declared, resolvedURL: r.url, status: r.status)
        }
        for x in doc.xrefs {
            out.append(make(x.blockName, .xref, x.path))
        }
        for img in doc.images {
            out.append(make(fileName(of: img), .image, img))
        }
        for f in doc.fonts {
            var declared = f
            if (f as NSString).pathExtension.isEmpty { declared = f + ".shx" }
            out.append(make(fileName(of: f), .font, declared))
        }
        return out
    }

    static func fileName(of path: String) -> String {
        let p = path.replacingOccurrences(of: "\\", with: "/")
        return p.split(separator: "/").last.map(String.init) ?? p
    }

    static func isAbsolute(_ p: String) -> Bool {
        if p.hasPrefix("/") || p.hasPrefix("~") { return true }
        let u = Array(p.utf8)
        // Windows drive letter ("C:/…", "C:…").
        if u.count >= 2, ((u[0] >= 65 && u[0] <= 90) || (u[0] >= 97 && u[0] <= 122)), u[1] == 58 { return true }
        // URL schemes.
        if p.contains("://") { return true }
        return false
    }

    /// Resolves a declared path strictly inside `folder`.
    static func resolve(_ declared: String, in folder: URL) -> (url: URL?, status: CADDependency.Status) {
        let p = declared.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !p.contains("\0") else { return (nil, .missing) }
        let root = folder.standardizedFileURL.resolvingSymlinksInPath()
        if isAbsolute(p) {
            // An absolute POSIX path is accepted only when it already lies inside the drawing's folder.
            if p.hasPrefix("/") {
                let u = URL(fileURLWithPath: p).standardizedFileURL.resolvingSymlinksInPath()
                if isInside(u, root) {
                    return FileManager.default.fileExists(atPath: u.path) ? (u, .found) : (nil, .missing)
                }
            }
            return (nil, .outsideParentFolder)
        }
        let candidate = root.appendingPathComponent(p).standardizedFileURL
        guard isInside(candidate, root) else { return (nil, .outsideParentFolder) }
        let resolved = candidate.resolvingSymlinksInPath()
        guard isInside(resolved, root) else { return (nil, .outsideParentFolder) }
        return FileManager.default.fileExists(atPath: resolved.path) ? (resolved, .found) : (nil, .missing)
    }

    static func isInside(_ u: URL, _ root: URL) -> Bool {
        let a = u.standardizedFileURL.pathComponents, r = root.standardizedFileURL.pathComponents
        guard a.count > r.count else { return false }
        return Array(a.prefix(r.count)) == r
    }
}
