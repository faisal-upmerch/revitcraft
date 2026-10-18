import Foundation
import ArcusGeometry
import ArcusDomain

// DWG through a converter the user installed (W2-DWG).
//
// Arcus contains no DWG reader. When it is built without the licensed ODA Drawings SDK it can still link and import DWG
// files by running a free converter that the user installed themselves, as a separate process, turning the DWG into a
// DXF in a private temporary folder. The DXF then goes through Arcus's own DXF path (layers, units, blocks, text,
// linetypes). Arcus never downloads, bundles or links a converter; it only looks for one in the usual install locations
// or at a path the user chose in Settings. See Docs/DWGSDKSetup.md.

/// The third-party converters Arcus knows how to drive.
public enum ExternalDWGConverterKind: String, Sendable, Codable, CaseIterable, Hashable {
    /// ODA File Converter: a free application from the Open Design Alliance (closed source, ODA license).
    case odaFileConverter = "ODA File Converter"
    /// LibreDWG's `dwg2dxf` command-line tool (GNU GPL v3; run as a separate program, never linked).
    case libreDWG = "LibreDWG dwg2dxf"
}

/// A converter found on this Mac.
public struct ExternalDWGConverter: Sendable, Hashable {
    public var kind: ExternalDWGConverterKind
    /// The executable that is run (inside the app bundle for ODA File Converter).
    public var executableURL: URL
    /// The app bundle for ODA File Converter; nil for command-line tools.
    public var bundleURL: URL?
    /// Version from the app bundle (ODA File Converter only; command-line tools are not run just to ask).
    public var version: String?

    public init(kind: ExternalDWGConverterKind, executableURL: URL, bundleURL: URL? = nil, version: String? = nil) {
        self.kind = kind; self.executableURL = executableURL; self.bundleURL = bundleURL; self.version = version
    }

    /// E.g. "ODA File Converter 26.4" or "LibreDWG dwg2dxf".
    public var displayName: String { version.map { "\(kind.rawValue) \($0)" } ?? kind.rawValue }
    /// The path to show the user (the app bundle when there is one).
    public var displayPath: String { (bundleURL ?? executableURL).path }
    public var isExecutable: Bool { FileManager.default.isExecutableFile(atPath: executableURL.path) }

    /// ODA File Converter's output version argument. AutoCAD 2018 DXF is the newest version Arcus's DXF reader supports.
    public static let odaOutputVersion = "ACAD2018"
    /// File name the source DWG is copied to before conversion. A plain ASCII name keeps paths with spaces, non-Latin
    /// characters or wildcard characters away from the converter's own argument and filter handling.
    public static let stagedInputName = "drawing.dwg"
    public static let stagedOutputName = "drawing.dxf"

    /// Command-line arguments for converting `inputDirectory/stagedInputName` into `outputDirectory`.
    ///
    /// - ODA File Converter (documented command line): `"Input Folder" "Output Folder" version type recurse audit [filter]`,
    ///   here `in out ACAD2018 DXF 0 1 drawing.dwg` (no recursion, audit and repair on, only the staged file).
    /// - LibreDWG: `dwg2dxf [-y] [-o dxffile] dwgfile` (`-y` overwrites, `-o` names the output file).
    public func arguments(inputDirectory: URL, outputDirectory: URL) -> [String] {
        switch kind {
        case .odaFileConverter:
            return [inputDirectory.path, outputDirectory.path, Self.odaOutputVersion, "DXF", "0", "1", Self.stagedInputName]
        case .libreDWG:
            return ["-y", "-o", outputDirectory.appendingPathComponent(Self.stagedOutputName).path,
                    inputDirectory.appendingPathComponent(Self.stagedInputName).path]
        }
    }

    // MARK: Detection

    /// Where Arcus looks for converters (only these places; nothing is searched on the network or elsewhere on disk).
    public struct SearchLocations: Sendable {
        /// Folders searched for ODA File Converter app bundles.
        public var applicationFolders: [URL]
        /// Full paths checked for LibreDWG's `dwg2dxf`.
        public var libreDWGPaths: [URL]
        public init(applicationFolders: [URL], libreDWGPaths: [URL]) {
            self.applicationFolders = applicationFolders; self.libreDWGPaths = libreDWGPaths
        }
        /// /Applications and ~/Applications; Homebrew (Apple silicon and Intel) and MacPorts binary folders.
        public static var standard: SearchLocations {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return SearchLocations(
                applicationFolders: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")],
                libreDWGPaths: ["/opt/homebrew/bin/dwg2dxf", "/usr/local/bin/dwg2dxf", "/opt/local/bin/dwg2dxf"].map { URL(fileURLWithPath: $0) })
        }
    }

    /// Converters installed in the standard (or given) locations, ODA File Converter first.
    public static func detect(in locations: SearchLocations = .standard) -> [ExternalDWGConverter] {
        var found: [ExternalDWGConverter] = []
        let fm = FileManager.default
        for folder in locations.applicationFolders {
            // The usual bundle name first, then other ODA converter bundles (e.g. "ODA File Converter.app", versioned names).
            var bundles = [folder.appendingPathComponent("ODAFileConverter.app")]
            let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            for n in names.sorted() where n.lowercased().hasSuffix(".app") && n.lowercased().hasPrefix("oda") && n.lowercased().contains("converter") {
                let u = folder.appendingPathComponent(n)
                if !bundles.contains(u) { bundles.append(u) }
            }
            for b in bundles {
                if let c = fromAppBundle(b), !found.contains(where: { $0.executableURL == c.executableURL }) { found.append(c) }
            }
        }
        for p in locations.libreDWGPaths where fm.isExecutableFile(atPath: p.path) {
            if !found.contains(where: { $0.executableURL.resolvingSymlinksInPath() == p.resolvingSymlinksInPath() }) {
                found.append(ExternalDWGConverter(kind: .libreDWG, executableURL: p))
            }
        }
        return found
    }

    /// A converter at a path the user chose: an ODA File Converter app bundle or executable, or `dwg2dxf`.
    /// Returns nil if the path is not an executable Arcus knows how to drive.
    public static func at(path: String) -> ExternalDWGConverter? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        if url.pathExtension.lowercased() == "app" { return fromAppBundle(url) }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        let name = url.lastPathComponent.lowercased()
        if name.contains("dwg2dxf") { return ExternalDWGConverter(kind: .libreDWG, executableURL: url) }
        if name.contains("odafileconverter") || name.contains("oda file converter") {
            // An executable inside Contents/MacOS: report the enclosing bundle.
            let bundle = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            if bundle.pathExtension.lowercased() == "app", let c = fromAppBundle(bundle), c.executableURL.standardizedFileURL == url.standardizedFileURL { return c }
            return ExternalDWGConverter(kind: .odaFileConverter, executableURL: url)
        }
        return nil
    }

    static func fromAppBundle(_ bundle: URL) -> ExternalDWGConverter? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: bundle.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        let plist = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        var candidates: [URL] = []
        if let exe = plist?["CFBundleExecutable"] as? String, !exe.isEmpty { candidates.append(macOS.appendingPathComponent(exe)) }
        candidates.append(macOS.appendingPathComponent("ODAFileConverter"))
        let contents = ((try? fm.contentsOfDirectory(atPath: macOS.path)) ?? []).sorted()
        if contents.count == 1 { candidates.append(macOS.appendingPathComponent(contents[0])) }
        guard let exe = candidates.first(where: { fm.isExecutableFile(atPath: $0.path) }) else { return nil }
        let version = (plist?["CFBundleShortVersionString"] as? String) ?? (plist?["CFBundleVersion"] as? String)
        return ExternalDWGConverter(kind: .odaFileConverter, executableURL: exe, bundleURL: bundle, version: version.flatMap { $0.isEmpty ? nil : $0 })
    }
}

// MARK: - Preferences

/// Where the converter choice is stored (the Settings window writes it; `DWGProviders.current` reads it).
public enum DWGConverterPreferences {
    /// Path to a converter the user chose (app bundle or executable). Empty = automatic detection.
    public static let pathKey = "dwg.converterPath"
    /// When false, Arcus does not use a detected converter unless one was chosen explicitly.
    public static let autoDetectKey = "dwg.converterAutoDetect"

    /// The converter to use: the user's choice when set (even if it is no longer valid, so the problem is reported), else
    /// the first detected one when automatic detection is on.
    public static func resolve(chosenPath: String?, autoDetect: Bool, locations: ExternalDWGConverter.SearchLocations = .standard)
        -> Result<ExternalDWGConverter, ConverterProblem>? {
        if let p = chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            if let c = ExternalDWGConverter.at(path: p) { return .success(c) }
            return .failure(.invalidChosenPath(p))
        }
        guard autoDetect, let c = ExternalDWGConverter.detect(in: locations).first else { return nil }
        return .success(c)
    }

    public static func resolveFromDefaults(_ defaults: UserDefaults = .standard) -> Result<ExternalDWGConverter, ConverterProblem>? {
        let auto = defaults.object(forKey: autoDetectKey) as? Bool ?? true
        return resolve(chosenPath: defaults.string(forKey: pathKey), autoDetect: auto)
    }

    public enum ConverterProblem: Error, Sendable, Hashable {
        case invalidChosenPath(String)
        public var message: String {
            switch self {
            case .invalidChosenPath(let p):
                return "The DWG converter chosen in Settings (\(p)) was not found or is not ODA File Converter or LibreDWG dwg2dxf. "
                    + "Choose it again in Arcus ▸ Settings ▸ DWG Converter, or clear the choice to detect an installed converter."
            }
        }
    }
}

// MARK: - Running a converter

/// Runs an external converter as a separate process with a timeout and cancellation.
public enum ExternalProcessRunner {
    public struct Outcome: Sendable {
        public var exitCode: Int32
        public var standardOutput: String
        public var standardError: String
    }

    /// Runs `executable` with `arguments` (no shell: spaces and non-ASCII characters pass through unchanged).
    /// Output goes to files in `logDirectory`, so a chatty converter can never block on a full pipe.
    public static func run(_ executable: URL, arguments: [String], workingDirectory: URL, logDirectory: URL, timeout: TimeInterval,
                           isCancelled: () -> Bool) throws -> Outcome {
        let fm = FileManager.default
        let outURL = logDirectory.appendingPathComponent("stdout.txt"), errURL = logDirectory.appendingPathComponent("stderr.txt")
        fm.createFile(atPath: outURL.path, contents: nil)
        fm.createFile(atPath: errURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: outURL), err = try FileHandle(forWritingTo: errURL)
        defer { try? out.close(); try? err.close() }
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        p.currentDirectoryURL = workingDirectory
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            throw CADError("The DWG converter could not be started (\(executable.path)): \(error.localizedDescription)")
        }
        let deadline = Date().addingTimeInterval(timeout)
        var stopReason: CADError?
        var cancelled = false
        while p.isRunning {
            if isCancelled() { cancelled = true; break }
            if Date() > deadline {
                stopReason = CADError("The DWG converter did not finish within \(Int(timeout)) seconds and was stopped. Large drawings may need more time; try again, or save the drawing as DXF from your CAD application.")
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if p.isRunning {
            p.terminate()
            let grace = Date().addingTimeInterval(2)
            while p.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.02) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            p.waitUntilExit()
            if cancelled { throw CancellationError() }
            if let stopReason { throw stopReason }
        }
        p.waitUntilExit()
        if cancelled { throw CancellationError() }
        func tail(_ u: URL) -> String {
            guard let d = try? Data(contentsOf: u) else { return "" }
            return String(decoding: d.suffix(4000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Outcome(exitCode: p.terminationStatus, standardOutput: tail(outURL), standardError: tail(errURL))
    }
}

/// Converts a DWG into DXF data with an external converter.
public enum ExternalDWGConversion {
    /// Converts `source` and returns the DXF bytes. Everything happens in a private temporary folder that is removed
    /// afterwards; the source file is only read (copied), never written.
    public static func convert(_ source: URL, with converter: ExternalDWGConverter, timeout: TimeInterval = 600,
                               progress: @Sendable (Double) -> Void = { _ in }, isCancelled: @Sendable () -> Bool = { false }) throws -> Data {
        let fm = FileManager.default
        guard converter.isExecutable else {
            throw CADError("\(converter.kind.rawValue) was not found at \(converter.executableURL.path). Install it again, or choose it in Arcus ▸ Settings ▸ DWG Converter.")
        }
        guard fm.isReadableFile(atPath: source.path) else {
            throw CADError("“\(source.lastPathComponent)” could not be read. Check that the file exists and that Arcus may open it.")
        }
        let work = fm.temporaryDirectory.appendingPathComponent("Arcus-DWG-\(UUID().uuidString)", isDirectory: true)
        let input = work.appendingPathComponent("in", isDirectory: true), output = work.appendingPathComponent("out", isDirectory: true)
        let logs = work.appendingPathComponent("logs", isDirectory: true)
        for d in [work, input, output, logs] { try fm.createDirectory(at: d, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        defer { try? fm.removeItem(at: work) }
        do {
            try fm.copyItem(at: source, to: input.appendingPathComponent(ExternalDWGConverter.stagedInputName))
        } catch {
            throw CADError("“\(source.lastPathComponent)” could not be copied for conversion: \(error.localizedDescription)")
        }
        progress(0.05)
        if isCancelled() { throw CancellationError() }
        let outcome = try ExternalProcessRunner.run(converter.executableURL, arguments: converter.arguments(inputDirectory: input, outputDirectory: output),
                                                    workingDirectory: work, logDirectory: logs, timeout: timeout, isCancelled: isCancelled)
        progress(0.9)
        let found = discoverOutput(in: output)
        guard let dxf = found.dxf else {
            var msg = "\(converter.kind.rawValue) did not produce a DXF file"
            msg += outcome.exitCode != 0 ? " (exit status \(outcome.exitCode))." : "."
            let detail = [found.errorLog, outcome.standardError, outcome.standardOutput].compactMap { $0 }.first { !$0.isEmpty }
            if let detail { msg += " It reported: " + String(detail.prefix(600)) }
            msg += " The drawing may be damaged or saved in a version the converter does not read."
            throw CADError(msg)
        }
        let data: Data
        do { data = try Data(contentsOf: dxf) } catch { throw CADError("The converted DXF could not be read: \(error.localizedDescription)") }
        guard DXFReader.looksLikeDXF(data) else {
            throw CADError("\(converter.kind.rawValue) wrote a file that is not a DXF drawing, so it was not imported.")
        }
        progress(1)
        return data
    }

    /// Finds the converter's DXF output (any `.dxf`, case-insensitive, in the output folder or below; the staged name
    /// preferred) and the text of any error log it wrote (ODA File Converter writes `*.err` files for failed audits).
    public static func discoverOutput(in folder: URL) -> (dxf: URL?, errorLog: String?) {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return (nil, nil) }
        var dxfs: [URL] = []
        var log: String?
        for case let u as URL in e {
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let ext = u.pathExtension.lowercased()
            if ext == "dxf" { dxfs.append(u) }
            if ext == "err" || ext == "log", log == nil, let d = try? Data(contentsOf: u) {
                let s = String(decoding: d.prefix(4000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { log = s }
            }
        }
        let stem = (ExternalDWGConverter.stagedOutputName as NSString).deletingPathExtension.lowercased()
        let best = dxfs.first { $0.deletingPathExtension().lastPathComponent.lowercased() == stem }
            ?? dxfs.sorted { $0.path < $1.path }.first
        // A zero-length file is a failed conversion.
        if let b = best, ((try? fm.attributesOfItem(atPath: b.path)[.size] as? Int) ?? 0) == 0 { return (nil, log) }
        return (best, log)
    }
}

/// Caches recent conversions so reading a DWG for the import dialog and then placing it runs the converter once.
/// Keyed by source path, size, modification date and converter; a changed file (a reload after editing) converts again.
final class ExternalDWGConversionCache: @unchecked Sendable {
    static let shared = ExternalDWGConversionCache()
    private struct Key: Hashable { var path: String; var size: Int; var modified: Date; var converter: String }
    private let lock = NSLock()
    private var entries: [(Key, Data)] = []
    private let maxEntries = 2
    private let maxBytes = 256 << 20

    private func key(_ url: URL, _ c: ExternalDWGConverter) -> Key? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path), let size = a[.size] as? Int, let m = a[.modificationDate] as? Date else { return nil }
        return Key(path: url.standardizedFileURL.path, size: size, modified: m, converter: c.executableURL.path)
    }
    func data(for url: URL, converter c: ExternalDWGConverter) -> Data? {
        guard let k = key(url, c) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return entries.first { $0.0 == k }?.1
    }
    func store(_ data: Data, for url: URL, converter c: ExternalDWGConverter) {
        guard data.count <= maxBytes, let k = key(url, c) else { return }
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.0 == k }
        entries.insert((k, data), at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
    }
    func removeAll() { lock.lock(); entries = []; lock.unlock() }
}

/// DWG import through a converter the user installed (see the top of this file).
public struct ExternalConverterDWGProvider: DWGImportProvider {
    public var converter: ExternalDWGConverter
    public var timeout: TimeInterval
    public init(converter: ExternalDWGConverter, timeout: TimeInterval = 600) { self.converter = converter; self.timeout = timeout }

    public var isAvailable: Bool { converter.isExecutable }
    public var unavailableReason: String? {
        isAvailable ? nil : "\(converter.kind.rawValue) was not found at \(converter.executableURL.path). Install it again or choose it in Arcus ▸ Settings ▸ DWG Converter."
    }
    public var sdkName: String { "\(converter.kind.rawValue) (installed separately; runs as its own program)" }
    public var sdkVersion: String? { converter.version }
    /// The converter decides what it reads; these are the versions Arcus names in its report.
    public var supportedVersions: [String] { DWGProviders.knownVersions }

    public func read(_ url: URL, options: CADReadOptions, progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) throws -> CADDocument {
        let data: Data
        if let cached = ExternalDWGConversionCache.shared.data(for: url, converter: converter) {
            data = cached
        } else {
            data = try ExternalDWGConversion.convert(url, with: converter, timeout: timeout, progress: { progress(0.6 * $0) }, isCancelled: isCancelled)
            ExternalDWGConversionCache.shared.store(data, for: url, converter: converter)
        }
        if isCancelled() { throw CancellationError() }
        var doc = try DXFReader.read(data, fileName: url.lastPathComponent, options: options,
                                     progress: { progress(0.6 + 0.4 * $0) }, isCancelled: isCancelled)
        doc.format = "DWG"
        if let v = DWGProviders.sniffVersion(url) { doc.version = v; doc.versionName = CADDocument.friendlyVersion(v) }
        doc.warnings.append("Converted from DWG to DXF on this Mac by \(converter.displayName), a separately installed third-party program. Arcus itself does not read DWG.")
        return doc
    }
}
