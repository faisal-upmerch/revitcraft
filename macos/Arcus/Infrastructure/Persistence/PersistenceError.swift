import Foundation

/// A failure reading or writing an Arcus package. `description` is user-facing and actionable.
public struct PersistenceError: Error, Sendable, CustomStringConvertible, LocalizedError {
    public enum Kind: Sendable, Hashable {
        /// The item is not an Arcus package (wrong layout, missing manifest, wrong format identifier).
        case notAPackage
        /// The package requires a newer reader than this build provides.
        case newerFormat(requiredReader: Int, writtenBy: String)
        /// The package is damaged (unreadable manifest, malformed database, undecodable data…).
        case corrupt(String)
        /// A critical file's SHA-256 does not match the manifest. Associated value: the relative path.
        case checksumMismatch(String)
        /// The schema version is not one this build knows how to read (e.g. 0 or negative).
        case unsupportedSchema(Int)
        /// A file-system error.
        case io(String)
        /// Hostile or absurd input tripped a safety limit (element count, blob size, decompression ratio…).
        case limitExceeded(String)
    }

    public var kind: Kind
    public var description: String

    public init(_ kind: Kind, _ description: String) {
        self.kind = kind
        self.description = description
    }

    public var errorDescription: String? { description }

    // MARK: Factories with consistent wording

    static func notAPackage(_ url: URL?) -> PersistenceError {
        PersistenceError(.notAPackage, "\(quoted(url)) isn’t an Arcus document. Choose a file with the .arcus extension that was saved by Arcus.")
    }

    static func notAFamily(_ url: URL?) -> PersistenceError {
        PersistenceError(.notAPackage, "\(quoted(url)) isn’t an Arcus family. Choose a file with the .arcusfamily extension.")
    }

    static func newer(_ url: URL?, manifest: PackageManifest, reader: Int) -> PersistenceError {
        let by = manifest.writerAppVersion.isEmpty ? "a newer version of Arcus" : "Arcus \(manifest.writerAppVersion) (build \(manifest.writerBuild))"
        return PersistenceError(
            .newerFormat(requiredReader: manifest.minimumReaderVersion, writtenBy: manifest.writerAppVersion),
            "\(quoted(url)) was saved by \(by) in a newer file format (reader version \(manifest.minimumReaderVersion) required; this version of Arcus reads up to version \(reader)). "
                + "To open it, install Arcus \(manifest.writerAppVersion.isEmpty ? "" : manifest.writerAppVersion + " ")or later. The file has not been changed.")
    }

    static func corrupt(_ url: URL?, _ detail: String) -> PersistenceError {
        PersistenceError(.corrupt(detail), "\(quoted(url)) is damaged and can’t be opened (\(detail)). "
            + "Use “Save Recovery Copy…” to extract every readable element into a new document, or restore the file from a backup.")
    }

    static func checksum(_ url: URL?, path: String) -> PersistenceError {
        PersistenceError(.checksumMismatch(path), "Part of \(quoted(url)) (“\(path)”) doesn’t match the checksum recorded when it was saved, so the document may be damaged. "
            + "Arcus didn’t open it to avoid showing incomplete data. Use “Save Recovery Copy…” to extract every readable element into a new document, or restore the file from a backup.")
    }

    static func unsupported(_ url: URL?, _ v: Int) -> PersistenceError {
        PersistenceError(.unsupportedSchema(v), "\(quoted(url)) uses an unknown document schema (version \(v)). It may have been created by a pre-release build of Arcus.")
    }

    static func io(_ url: URL?, _ action: String, _ error: (any Error)?) -> PersistenceError {
        let why = error.map { ($0 as NSError).localizedDescription } ?? "unknown error"
        return PersistenceError(.io(why), "Arcus couldn’t \(action) \(quoted(url)): \(why)")
    }

    static func limit(_ url: URL?, _ detail: String) -> PersistenceError {
        PersistenceError(.limitExceeded(detail), "\(quoted(url)) exceeds a safety limit (\(detail)) and wasn’t opened. It may be damaged or not a genuine Arcus document.")
    }

    static func quoted(_ url: URL?) -> String {
        guard let url else { return "The document" }
        return "“\(url.lastPathComponent)”"
    }
}

/// Result of an integrity check or recovery-copy extraction.
public struct IntegrityReport: Sendable, Hashable {
    public var isHealthy: Bool
    public var problems: [String]
    public var recoveredElements: Int
    public var lostElements: Int
    public init(isHealthy: Bool, problems: [String], recoveredElements: Int, lostElements: Int) {
        self.isHealthy = isHealthy; self.problems = problems; self.recoveredElements = recoveredElements; self.lostElements = lostElements
    }
}

/// Safety limits applied when reading untrusted packages.
public struct PersistenceLimits: Sendable, Hashable {
    /// Maximum number of elements in one document.
    public var maxElements: Int = 5_000_000
    /// Maximum size of one element's encoded data.
    public var maxElementBytes: Int = 64 << 20
    /// Maximum size of one project-table value (parameters, sheet sets, drawing index).
    public var maxProjectValueBytes: Int = 256 << 20
    /// Maximum decompressed size of one asset.
    public var maxAssetBytes: Int = 1 << 30
    /// Maximum decompressed / compressed ratio accepted for assets (zip-bomb protection).
    public var maxCompressionRatio: Int = 1_000
    /// Maximum number of assets.
    public var maxAssets: Int = 100_000
    /// Maximum manifest size.
    public var maxManifestBytes: Int = 4 << 20
    /// Maximum nesting depth of any stored JSON value.
    public var maxJSONDepth: Int = 256
    /// Maximum thumbnail size.
    public var maxThumbnailBytes: Int = 32 << 20
    /// Maximum size of a family definition file.
    public var maxFamilyBytes: Int = 256 << 20
    /// Maximum number of rows in a type catalog.
    public var maxCatalogRows: Int = 100_000

    public init() {}
    public static let `default` = PersistenceLimits()
}
