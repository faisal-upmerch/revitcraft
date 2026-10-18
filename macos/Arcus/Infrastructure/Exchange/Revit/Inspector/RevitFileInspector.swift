import Foundation

/// What a Revit file is, as far as Arcus can tell without reading Revit's model data.
public enum RevitFileKind: String, Codable, Sendable, CaseIterable {
    /// `.rvt` project.
    case project
    /// `.rfa` loadable family.
    case family
    /// `.rte` project template or `.rft` family template.
    case template
    case unknown

    public var displayName: String {
        switch self {
        case .project: "Revit project"
        case .family: "Revit family"
        case .template: "Revit template"
        case .unknown: "Revit file"
        }
    }

    /// Kind implied by a file extension, if it is a Revit extension.
    public static func fromExtension(_ ext: String) -> RevitFileKind? {
        switch ext.lowercased() {
        case "rvt": .project
        case "rfa": .family
        case "rte", "rft": .template
        default: nil
        }
    }
}

/// Container-level facts about a Revit file: kind, the Revit release that saved it, its embedded preview image and the
/// names of its streams. Arcus reads these from the open compound-file container, the PNG preview and plain text only.
public struct RevitFileInfo: Hashable, Sendable {
    public var fileName: String
    public var fileSize: Int
    public var kind: RevitFileKind
    /// How `kind` was decided (for example "file extension .rfa").
    public var kindEvidence: String
    /// Revit release year that saved the file, e.g. "2024", when the file states it in plain text.
    public var revitRelease: String?
    /// Product text found in the file, e.g. "Autodesk Revit 2024".
    public var productName: String?
    /// Build text found in the file, e.g. "20230308_1635(x64)".
    public var buildString: String?
    /// The embedded preview image (a standard PNG), if present and intact.
    public var previewPNG: Data?
    /// Paths of all streams in the container.
    public var streamNames: [String]
    /// Compound file major version (3 or 4).
    public var containerVersion: Int
    /// Readable UTF-16 text runs found in the "BasicFileInfo" stream (capped), for display.
    public var basicFileInfoText: [String]
    /// Non-fatal observations (missing preview, extension mismatch…).
    public var notes: [String]
}

/// Why a file could not be inspected.
public struct RevitInspectionError: Error, Hashable, Sendable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Reads container metadata from Revit files. It never decodes Revit's proprietary element streams: it lists stream
/// names ([MS-CFB]), extracts the PNG stored in "RevitPreview4.0" by locating the PNG signature, and scans
/// "BasicFileInfo" for readable UTF-16LE text such as the release string.
public enum RevitFileInspector {
    public static let previewStreamName = "RevitPreview4.0"
    public static let basicInfoStreamName = "BasicFileInfo"
    /// Largest preview stream read.
    public static let maxPreviewBytes = 32 << 20
    /// Largest BasicFileInfo stream read.
    public static let maxBasicInfoBytes = 1 << 20

    public static func inspect(_ url: URL, limits: CompoundFileLimits = .default) throws(RevitInspectionError) -> RevitFileInfo {
        let cfb: CompoundFile
        do { cfb = try CompoundFile(contentsOf: url, limits: limits) } catch {
            throw RevitInspectionError(message(for: error, fileName: url.lastPathComponent))
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        return inspect(cfb, fileName: url.lastPathComponent, fileSize: size)
    }

    public static func inspect(data: Data, fileName: String, limits: CompoundFileLimits = .default) throws(RevitInspectionError) -> RevitFileInfo {
        let cfb: CompoundFile
        do { cfb = try CompoundFile(data: data, limits: limits) } catch {
            throw RevitInspectionError(message(for: error, fileName: fileName))
        }
        return inspect(cfb, fileName: fileName, fileSize: data.count)
    }

    static func message(for error: CompoundFileError, fileName: String) -> String {
        switch error.kind {
        case .notCompoundFile: "“\(fileName)” is not a Revit file: it does not use the compound file container that Revit files use."
        case .io: "“\(fileName)” could not be read. \(error.message)"
        default: "“\(fileName)” looks damaged and could not be inspected. \(error.message)"
        }
    }

    static func inspect(_ cfb: CompoundFile, fileName: String, fileSize: Int) -> RevitFileInfo {
        var notes: [String] = []
        let names = cfb.streamPaths

        // Preview.
        var preview: Data?
        if let e = cfb.entry(atPath: previewStreamName), e.kind == .stream {
            do {
                let bytes = try cfb.read(e, maxBytes: maxPreviewBytes)
                preview = extractPNG(bytes)
                if preview == nil { notes.append("The preview stream does not contain a complete PNG image.") }
            } catch {
                notes.append("The preview image could not be read: \(error.message)")
            }
        } else {
            notes.append("The file has no preview image.")
        }

        // BasicFileInfo text.
        var text: [String] = []
        if let e = cfb.entry(atPath: basicInfoStreamName), e.kind == .stream {
            do { text = utf16Strings(try cfb.read(e, maxBytes: maxBasicInfoBytes)) } catch {
                notes.append("The file information stream could not be read: \(error.message)")
            }
        } else {
            notes.append("The file has no “\(basicInfoStreamName)” stream; it may not be a Revit file.")
        }
        let facts = parseBasicInfo(text)

        // Kind: extension first, then a saved file name found in the text.
        let ext = (fileName as NSString).pathExtension
        var kind = RevitFileKind.unknown
        var evidence = "not determined"
        if let k = RevitFileKind.fromExtension(ext) {
            kind = k
            evidence = "file extension .\(ext.lowercased())"
            if let hinted = facts.kindHint, hinted.kind != k {
                notes.append("The file has the extension .\(ext.lowercased()) but its file information names “\(hinted.name)”.")
            }
        } else if let hinted = facts.kindHint {
            kind = hinted.kind
            evidence = "saved file name “\(hinted.name)” in the file information"
        }
        return RevitFileInfo(fileName: fileName, fileSize: fileSize, kind: kind, kindEvidence: evidence, revitRelease: facts.release,
                             productName: facts.product, buildString: facts.build, previewPNG: preview, streamNames: names,
                             containerVersion: cfb.majorVersion, basicFileInfoText: text, notes: notes)
    }

    // MARK: PNG

    static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Finds the first PNG signature and returns the bytes through the end of its IEND chunk, after checking that the
    /// chunk sequence starts with IHDR and stays inside the data. Returns nil when no complete PNG is found.
    public static func extractPNG(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return nil }
        var start = -1
        var i = 0
        while i + 8 <= bytes.count {
            if bytes[i] == 0x89, bytes[i + 1] == 0x50, bytes[i + 2] == 0x4E, bytes[i + 3] == 0x47,
               Array(bytes[i..<(i + 8)]) == pngSignature { start = i; break }
            i += 1
        }
        guard start >= 0 else { return nil }
        var pos = start + 8
        var chunks = 0
        while pos + 12 <= bytes.count, chunks < 100_000 {
            let length = Int(bytes[pos]) << 24 | Int(bytes[pos + 1]) << 16 | Int(bytes[pos + 2]) << 8 | Int(bytes[pos + 3])
            let type = String(decoding: bytes[(pos + 4)..<(pos + 8)], as: UTF8.self)
            if chunks == 0 && type != "IHDR" { return nil }
            guard length >= 0, length <= bytes.count, pos + 12 + length <= bytes.count else { return nil }
            pos += 12 + length
            chunks += 1
            if type == "IEND" { return Data(bytes[start..<pos]) }
        }
        return nil
    }

    // MARK: Text

    /// Readable UTF-16LE runs (at least 4 characters) at both byte alignments, deduplicated, at most 200 strings.
    public static func utf16Strings(_ data: Data, minLength: Int = 4) -> [String] {
        let bytes = [UInt8](data)
        var out: [String] = []
        var seen = Set<String>()
        func readable(_ u: UInt16) -> Bool {
            switch u {
            case 0x20...0x7E, 0xA0...0x2FF, 0x370...0x52F, 0x3040...0x30FF, 0x4E00...0x9FFF, 0xAC00...0xD7A3: true
            default: false
            }
        }
        for alignment in 0..<2 {
            var run: [UInt16] = []
            func flush() {
                if run.count >= minLength, out.count < 200 {
                    let s = String(decoding: run.prefix(512), as: UTF16.self).trimmingCharacters(in: .whitespaces)
                    if s.count >= minLength, seen.insert(s).inserted { out.append(s) }
                }
                run.removeAll(keepingCapacity: true)
            }
            var i = alignment
            while i + 1 < bytes.count {
                let u = UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8
                if readable(u) { run.append(u) } else { flush() }
                i += 2
            }
            flush()
        }
        return out
    }

    struct BasicInfoFacts {
        var release: String?
        var product: String?
        var build: String?
        var kindHint: (kind: RevitFileKind, name: String)?
    }

    static func parseBasicInfo(_ strings: [String]) -> BasicInfoFacts {
        var f = BasicInfoFacts()
        var format: String?, productYear: String?
        for s in strings {
            if format == nil, let r = s.firstMatch(of: /Format:\s*(20\d\d)/) { format = String(r.1) }
            if f.product == nil, let r = s.firstMatch(of: /(Autodesk\s+)?Revit(\s+[A-Za-z]+)*\s+(20\d\d)/) {
                f.product = String(r.0)
                productYear = String(r.3)
            }
            if f.build == nil, let r = s.firstMatch(of: /Build:\s*([0-9A-Za-z_.\-]+(\([A-Za-z0-9_]+\))?)/) { f.build = String(r.1) }
            if f.kindHint == nil, let r = s.firstMatch(of: /([^\\\/:*?"<>|]+\.(rvt|rfa|rte|rft))\b/.ignoresCase()),
               let k = RevitFileKind.fromExtension(String(r.2)) {
                f.kindHint = (k, String(r.1).trimmingCharacters(in: .whitespaces))
            }
        }
        // The file format year is authoritative; the product string may name a newer Revit that saved in an older format.
        f.release = format ?? productYear
        return f
    }
}
