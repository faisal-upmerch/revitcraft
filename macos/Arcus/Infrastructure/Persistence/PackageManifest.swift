import Foundation
import CryptoKit

/// `manifest.json` at the root of every Arcus package (`.arcus` and `.arcusfamily`).
///
/// The manifest is small, human-readable JSON (sorted keys, ISO-8601 dates with milliseconds). It is the first
/// file read, gates version compatibility and lists SHA-256 checksums of the critical files.
public struct PackageManifest: Codable, Sendable, Hashable {
    public static let projectFormat = "com.local.arcus.project"
    public static let familyFormat = "com.local.arcus.family"
    /// FM3: a Furniture document (`.arcusfurniture`): the project layout, opened in Furniture mode.
    public static let furnitureFormat = "com.local.arcus.furniture"
    /// Formats read as projects (the package layout is the same).
    public static let projectFormats: Set<String> = [projectFormat, furnitureFormat]

    /// `com.local.arcus.project` or `com.local.arcus.family`.
    public var format: String
    /// Layout version the writer used.
    public var schemaVersion: Int
    /// Oldest reader version able to read this package correctly.
    public var minimumReaderVersion: Int
    /// Marketing version of the writing app (e.g. "1.0.0").
    public var writerAppVersion: String
    public var writerBuild: String
    public var documentID: UUID
    public var created: Date
    public var modified: Date
    public var elementCount: Int
    /// Relative path → lowercase SHA-256 hex for critical files.
    public var checksums: [String: String]
    /// True for a project saved as a template (new projects start from a copy). Absent in ordinary projects.
    public var isTemplate: Bool?
    /// FM3: the document kind ("furniture"); absent in projects.
    public var kind: String?

    public init(format: String, schemaVersion: Int, minimumReaderVersion: Int, writerAppVersion: String, writerBuild: String,
                documentID: UUID, created: Date, modified: Date, elementCount: Int, checksums: [String: String], isTemplate: Bool? = nil) {
        self.format = format; self.schemaVersion = schemaVersion; self.minimumReaderVersion = minimumReaderVersion
        self.writerAppVersion = writerAppVersion; self.writerBuild = writerBuild; self.documentID = documentID
        self.created = created; self.modified = modified; self.elementCount = elementCount; self.checksums = checksums
        self.isTemplate = isTemplate
        self.kind = nil
    }

    // Tolerant decoding: unknown keys are ignored (newer writers may add fields); required keys must exist.
    enum CodingKeys: String, CodingKey {
        case format, schemaVersion, minimumReaderVersion, writerAppVersion, writerBuild, documentID, created, modified, elementCount, checksums
        case isTemplate
        case kind // FM3
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        minimumReaderVersion = try c.decodeIfPresent(Int.self, forKey: .minimumReaderVersion) ?? schemaVersion
        writerAppVersion = try c.decodeIfPresent(String.self, forKey: .writerAppVersion) ?? ""
        writerBuild = try c.decodeIfPresent(String.self, forKey: .writerBuild) ?? ""
        documentID = try c.decode(UUID.self, forKey: .documentID)
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date(timeIntervalSince1970: 0)
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? created
        elementCount = try c.decodeIfPresent(Int.self, forKey: .elementCount) ?? 0
        checksums = try c.decodeIfPresent([String: String].self, forKey: .checksums) ?? [:]
        isTemplate = try c.decodeIfPresent(Bool.self, forKey: .isTemplate)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) // FM3
    }

    // MARK: Coding

    func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(ManifestDates.format(date))
        }
        return try enc.encode(self)
    }

    static func decode(_ data: Data) throws -> PackageManifest {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            guard let d = ManifestDates.parse(s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date \(s)")
            }
            return d
        }
        return try dec.decode(PackageManifest.self, from: data)
    }
}

enum ManifestDates {
    /// ISO-8601 UTC with milliseconds, rounded (not truncated) so parse → format is stable across re-saves.
    static func format(_ d: Date) -> String {
        let ms = (d.timeIntervalSince1970 * 1000).rounded()
        let secs = (ms / 1000).rounded(.down)
        let frac = Int(ms - secs * 1000)
        let base = Date(timeIntervalSince1970: secs).formatted(Date.ISO8601FormatStyle(timeZone: .gmt))
        return String(base.dropLast()) + String(format: ".%03dZ", frac)
    }
    static func parse(_ s: String) -> Date? {
        if let d = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt).parse(s) { return d }
        return try? Date.ISO8601FormatStyle(timeZone: .gmt).parse(s)
    }
}

/// SHA-256 helpers.
enum Checksum {
    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    /// Streams a file through SHA-256 (1 MiB chunks).
    static func hex(fileAt url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Validation of names and relative paths that come from untrusted package content.
enum SafeName {
    /// A single path component: non-empty, ≤ 255 bytes, no separators, no `..`/`.`, no control characters, not hidden.
    static func isValidComponent(_ s: String) -> Bool {
        guard !s.isEmpty, s.utf8.count <= 255, s != ".", s != "..", !s.hasPrefix(".") else { return false }
        for u in s.unicodeScalars {
            if u == "/" || u == "\\" || u == ":" || u.value < 0x20 || u.value == 0x7f { return false }
        }
        return !s.contains("..")
    }
    /// A relative path made of valid components separated by `/` (at most 4 levels).
    static func isValidRelativePath(_ p: String) -> Bool {
        let parts = p.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return !parts.isEmpty && parts.count <= 4 && parts.allSatisfy(isValidComponent)
    }
}
