import Foundation
import ArcusPersistence

/// Identity of a file or package at a point in time.
public struct FileFingerprint: Sendable, Hashable, Codable {
    /// Total size of the file, or of `manifest.json` + `model.sqlite` for packages.
    public var size: Int64
    /// Latest modification date of the item (for packages: of the directory, manifest and model).
    public var modificationDate: Date?
    /// For Arcus packages: the manifest's documentID and modified date.
    public var documentID: UUID?
    public var manifestModified: Date?

    public init(size: Int64, modificationDate: Date?, documentID: UUID?, manifestModified: Date?) {
        self.size = size; self.modificationDate = modificationDate; self.documentID = documentID; self.manifestModified = manifestModified
    }

    /// True when both fingerprints describe the same saved document state (package manifests match), falling back to
    /// size + modification date for non-package files.
    public func sameDocumentState(as other: FileFingerprint) -> Bool {
        if let a = documentID, let b = other.documentID {
            return a == b && manifestModified == other.manifestModified
        }
        return self == other
    }
}

/// Detects edits made to a document's file by another process (sync clients, another app, another Mac).
public enum ExternalChangeDetector {
    public static func fingerprint(_ url: URL) -> FileFingerprint? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return nil }
        let type = attrs[.type] as? FileAttributeType
        if type == .typeDirectory {
            var size: Int64 = 0
            var latest = attrs[.modificationDate] as? Date
            for rel in [ArcusPackage.manifestPath, ArcusPackage.modelPath, FamilyPackage.familyPath] {
                guard let a = try? fm.attributesOfItem(atPath: url.appending(path: rel).path) else { continue }
                size += (a[.size] as? NSNumber)?.int64Value ?? 0
                if let d = a[.modificationDate] as? Date { latest = max(latest ?? d, d) }
            }
            let manifest = (try? ArcusPackage.readManifest(url)) ?? (try? FamilyPackage.readManifest(url))
            return FileFingerprint(size: size, modificationDate: latest, documentID: manifest?.documentID, manifestModified: manifest?.modified)
        }
        return FileFingerprint(size: (attrs[.size] as? NSNumber)?.int64Value ?? 0, modificationDate: attrs[.modificationDate] as? Date,
                               documentID: nil, manifestModified: nil)
    }

    /// True when the item changed (or disappeared) since `since` was taken.
    public static func hasChanged(_ url: URL, since: FileFingerprint) -> Bool {
        guard let now = fingerprint(url) else { return true }
        return now != since
    }
}
