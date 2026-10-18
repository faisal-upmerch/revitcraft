import Foundation
import ArcusDomain

/// The `.arcusfamily` package: `manifest.json`, `family.json` (the `FamilyDefinition`, sorted-key JSON) and an
/// optional `thumbnails/preview.png`. See Docs/FileFormat.md.
public enum FamilyPackage {
    /// 2: sweeps, blends, revolves, nested families, EQ/locked dimensions and per-view visibility (additive JSON).
    public static let currentSchemaVersion = 2
    public static let readerVersion = 2
    public static let fileExtension = "arcusfamily"
    public static let familyPath = "family.json"

    /// Writes a family package. When a family package already exists at `url`, its `documentID` and creation date are kept.
    public static func write(_ family: FamilyDefinition, thumbnailPNG: Data?, to url: URL, appVersion: String, build: String) throws {
        let existing = try? ArcusPackage.loadManifest(DirectorySource(root: url), limits: .default, format: PackageManifest.familyFormat)
        let json: Data
        do { json = try StoredJSON.encoder().encode(family) } catch {
            throw PersistenceError(.corrupt("family"), "The family “\(family.name)” couldn’t be encoded: \(error)")
        }
        let now = Date()
        let manifest = PackageManifest(format: PackageManifest.familyFormat, schemaVersion: currentSchemaVersion,
                                       // Families that only use format-1 features stay readable by older Arcus builds.
                                       minimumReaderVersion: family.minimumReaderVersion,
                                       writerAppVersion: appVersion, writerBuild: build, documentID: existing?.documentID ?? UUID(),
                                       created: existing?.created ?? now, modified: now, elementCount: family.types.count,
                                       checksums: [familyPath: Checksum.hex(json)])
        var files: PackageWriter.Files = [(familyPath, json)]
        if let thumbnailPNG { files.append((ArcusPackage.thumbnailPath, thumbnailPNG)) }
        files.append((ArcusPackage.manifestPath, try manifest.encoded()))
        try PackageWriter.write(files, to: url)
    }

    public static func read(from url: URL) throws -> (FamilyDefinition, thumbnailPNG: Data?, manifest: PackageManifest) {
        try read(from: url, limits: .default)
    }

    /// Reads and validates only the manifest of a family package.
    public static func readManifest(_ url: URL) throws -> PackageManifest {
        try ArcusPackage.loadManifest(DirectorySource(root: url), limits: .default, format: PackageManifest.familyFormat)
    }

    public static func read(from url: URL, limits: PersistenceLimits) throws -> (FamilyDefinition, thumbnailPNG: Data?, manifest: PackageManifest) {
        let src = DirectorySource(root: url)
        let manifest = try ArcusPackage.loadManifest(src, limits: limits, format: PackageManifest.familyFormat)
        try ArcusPackage.gate(manifest, url: url, reader: readerVersion, oldest: 1)
        try ArcusPackage.verifyChecksums(src, manifest: manifest, required: [familyPath])
        let data: Data
        do {
            guard let d = try src.read(familyPath, maxBytes: limits.maxFamilyBytes) else { throw PersistenceError.corrupt(url, "family.json is missing") }
            data = d
        } catch let e as TooLarge {
            throw PersistenceError.limit(url, "family.json is \(e.size) bytes")
        }
        let family: FamilyDefinition
        do { family = try StoredJSON.decode(FamilyDefinition.self, from: data, limits: limits, maxBytes: limits.maxFamilyBytes, what: "family.json") } catch let e as LimitError {
            throw PersistenceError.limit(url, e.description)
        } catch {
            throw PersistenceError.corrupt(url, "family.json can’t be decoded: \(ElementCodec.describe(error))")
        }
        let thumb = try? src.read(ArcusPackage.thumbnailPath, maxBytes: limits.maxThumbnailBytes)
        return (family, thumb ?? nil, manifest)
    }
}
