import Foundation
import ArcusGeometry
import ArcusDomain

// DWG: the DWG engines bundled inside Arcus.app, so DWG files import, link and export with nothing to install.
//
// Two separate helper programs live in Arcus.app/Contents/Helpers and run as their own local processes; Arcus links
// neither and talks to them only through files and command-line arguments (no network, no shared memory):
//
//   arcus-dwg  Arcus's helper around acadrust (MPL-2.0; Tools/DWGHelper). Reads DWG R13–2018 to DXF and writes DWG
//              from Arcus's DXF. The primary reader and the only writer.
//   dwg2dxf    GNU LibreDWG (GPLv3+; Tools/LibreDWG), unmodified. Used only when acadrust cannot read a file.
//
// Reading goes acadrust → LibreDWG → a converter the user installed (ExternalDWGConverter.swift) → the ODA SDK build
// (DWGProvider.swift); `DWGEngineChain` tries each and, when every route fails, says why in plain words and offers DXF.

/// The DWG helper programs bundled with this copy of Arcus.
public struct BundledDWGHelpers: Sendable, Hashable {
    /// `arcus-dwg` (acadrust), or nil when it is missing.
    public var acadrust: URL?
    /// LibreDWG's `dwg2dxf`, or nil when it is missing.
    public var libreDWG: URL?

    public static let acadrustName = "arcus-dwg"
    public static let libreDWGName = "dwg2dxf"
    /// Versions pinned in Tools/DWGHelper/Cargo.lock and Tools/LibreDWG/libredwg.version.
    public static let acadrustVersion = "0.6.5"
    public static let libreDWGVersion = "0.14"
    /// Development override: a folder holding both programs (used by `swift run` builds and the corpus test).
    public static let directoryEnvironmentKey = "ARCUS_DWG_HELPERS_DIR"

    public init(acadrust: URL?, libreDWG: URL?) { self.acadrust = acadrust; self.libreDWG = libreDWG }

    public static let none = BundledDWGHelpers(acadrust: nil, libreDWG: nil)

    /// The helpers in `folder` that exist and are executable.
    public static func `in`(_ folder: URL) -> BundledDWGHelpers {
        func exe(_ name: String) -> URL? {
            let u = folder.appendingPathComponent(name)
            return FileManager.default.isExecutableFile(atPath: u.path) ? u : nil
        }
        return BundledDWGHelpers(acadrust: exe(acadrustName), libreDWG: exe(libreDWGName))
    }

    /// Arcus.app/Contents/Helpers; outside an app bundle, the folder named by `ARCUS_DWG_HELPERS_DIR`.
    public static var standard: BundledDWGHelpers {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" { return .in(bundle.appendingPathComponent("Contents/Helpers", isDirectory: true)) }
        if let dir = ProcessInfo.processInfo.environment[directoryEnvironmentKey], !dir.isEmpty { return .in(URL(fileURLWithPath: dir)) }
        return .none
    }

    /// The helpers as built in a source checkout (`macos/`): Tools/DWGHelper/target/release and Tools/LibreDWG/cache/out.
    public static func development(macosRoot: URL) -> BundledDWGHelpers {
        let a = BundledDWGHelpers.in(macosRoot.appendingPathComponent("Tools/DWGHelper/target/release")).acadrust
        let l = BundledDWGHelpers.in(macosRoot.appendingPathComponent("Tools/LibreDWG/cache/out")).libreDWG
        return BundledDWGHelpers(acadrust: a, libreDWG: l)
    }
}

/// Running `arcus-dwg` and explaining its exit codes (they match Tools/DWGHelper/src/main.rs).
public enum BundledDWGEngine {
    public static let exitUnreadable: Int32 = 2, exitMemory: Int32 = 3, exitTimeout: Int32 = 4, exitWriteFailed: Int32 = 5
    public static let exitInternal: Int32 = 6, exitVerifyFailed: Int32 = 7, exitUsage: Int32 = 64, exitNoInput: Int32 = 66

    /// The helper's memory cap: half of this Mac's memory, between 1 and 8 GB.
    public static var memoryLimitMB: Int {
        let half = Int(ProcessInfo.processInfo.physicalMemory / 2 / (1 << 20))
        return min(8192, max(1024, half))
    }

    /// Plain-language reason for a failed `arcus-dwg` run.
    public static func message(_ outcome: ExternalProcessRunner.Outcome, doing task: String) -> String {
        let said = outcome.standardError.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        switch outcome.exitCode {
        case exitMemory: return "Arcus's DWG engine stopped while \(task): the drawing needs more memory than Arcus allows it (\(memoryLimitMB / 1024) GB)."
        case exitTimeout: return "Arcus's DWG engine stopped while \(task): it did not finish in time."
        case exitInternal: return "Arcus's DWG engine failed while \(task). \(said)"
        case exitNoInput: return "Arcus's DWG engine could not open the file while \(task)."
        case exitUnreadable, exitWriteFailed, exitVerifyFailed: return said.isEmpty ? "Arcus's DWG engine failed while \(task)." : said
        default: return "Arcus's DWG engine stopped unexpectedly while \(task) (status \(outcome.exitCode))." + (said.isEmpty ? "" : " \(said)")
        }
    }

    /// The one-line JSON summary `arcus-dwg` prints on success.
    static func summary(_ stdout: String) -> [String: Any] {
        guard let line = stdout.split(separator: "\n").last(where: { $0.hasPrefix("{") }),
              let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return [:] }
        return obj
    }
}

/// DWG import with Arcus's bundled acadrust helper (the primary route).
public struct BundledAcadrustDWGProvider: DWGImportProvider {
    public var helper: URL
    public var timeout: TimeInterval
    public init(helper: URL, timeout: TimeInterval = 600) { self.helper = helper; self.timeout = timeout }

    public var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: helper.path) }
    public var unavailableReason: String? {
        isAvailable ? nil : "Arcus's DWG engine is missing from this copy of Arcus (\(helper.path))."
    }
    public var sdkName: String { "Arcus DWG engine (acadrust \(BundledDWGHelpers.acadrustVersion), built in)" }
    public var sdkVersion: String? { BundledDWGHelpers.acadrustVersion }
    /// acadrust reads R13 through 2018.
    public var supportedVersions: [String] { ["AC1012", "AC1014", "AC1015", "AC1018", "AC1021", "AC1024", "AC1027", "AC1032"] }

    public func read(_ url: URL, options: CADReadOptions, progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) throws -> CADDocument {
        guard isAvailable else { throw CADError(unavailableReason ?? "Arcus's DWG engine is missing.") }
        let key = "acadrust:" + helper.path
        var info: [String: Any] = [:]
        let data: Data
        if let cached = ExternalDWGConversionCache.shared.data(for: url, engine: key) {
            data = cached
        } else {
            let limit = Int(timeout)
            let r = try ExternalDWGConversion.run(
                url, executable: helper, name: "Arcus's DWG engine", timeout: timeout + 15,
                arguments: { inDir, outDir in
                    ["to-dxf", inDir.appendingPathComponent(ExternalDWGConverter.stagedInputName).path,
                     outDir.appendingPathComponent(ExternalDWGConverter.stagedOutputName).path,
                     "--timeout", "\(limit)", "--max-memory-mb", "\(BundledDWGEngine.memoryLimitMB)"]
                },
                failure: { outcome, _ in CADError(BundledDWGEngine.message(outcome, doing: "reading “\(url.lastPathComponent)”")) },
                progress: { progress(0.6 * $0) }, isCancelled: isCancelled)
            data = r.dxf
            info = BundledDWGEngine.summary(r.standardOutput)
            ExternalDWGConversionCache.shared.store(data, for: url, engine: key)
        }
        if isCancelled() { throw CancellationError() }
        var doc = try DXFReader.read(data, fileName: url.lastPathComponent, options: options,
                                     progress: { progress(0.6 + 0.4 * $0) }, isCancelled: isCancelled)
        doc.format = "DWG"
        if let v = DWGProviders.sniffVersion(url) { doc.version = v; doc.versionName = CADDocument.friendlyVersion(v) }
        if info["recovered"] as? Bool == true {
            doc.warnings.append("The DWG was damaged; Arcus's DWG engine recovered what it could. Check the drawing against the original.")
        }
        return doc
    }
}

/// DWG import with the LibreDWG `dwg2dxf` bundled in Arcus.app (the fallback when acadrust can't read a file).
public struct BundledLibreDWGProvider: DWGImportProvider {
    public var executable: URL
    public var timeout: TimeInterval
    public init(executable: URL, timeout: TimeInterval = 600) { self.executable = executable; self.timeout = timeout }

    public var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }
    public var unavailableReason: String? { isAvailable ? nil : "LibreDWG is missing from this copy of Arcus (\(executable.path))." }
    public var sdkName: String { "GNU LibreDWG \(BundledDWGHelpers.libreDWGVersion) (bundled; runs as its own program)" }
    public var sdkVersion: String? { BundledDWGHelpers.libreDWGVersion }
    public var supportedVersions: [String] { DWGProviders.knownVersions }

    public func read(_ url: URL, options: CADReadOptions, progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) throws -> CADDocument {
        guard isAvailable else { throw CADError(unavailableReason ?? "LibreDWG is missing.") }
        let converter = ExternalDWGConverter(kind: .libreDWG, executableURL: executable)
        let key = "libredwg:" + executable.path
        var warnings: [String] = []
        let data: Data
        if let cached = ExternalDWGConversionCache.shared.data(for: url, engine: key) {
            data = cached
        } else {
            let r = try ExternalDWGConversion.run(url, executable: executable, name: "LibreDWG", timeout: timeout,
                                                  arguments: converter.arguments(inputDirectory:outputDirectory:),
                                                  progress: { progress(0.6 * $0) }, isCancelled: isCancelled)
            data = r.dxf
            if r.exitCode != 0 {
                warnings.append("LibreDWG reported problems reading this drawing (status \(r.exitCode)); some objects may be missing.")
            }
            ExternalDWGConversionCache.shared.store(data, for: url, engine: key)
        }
        if isCancelled() { throw CancellationError() }
        var doc = try DXFReader.read(data, fileName: url.lastPathComponent, options: options,
                                     progress: { progress(0.6 + 0.4 * $0) }, isCancelled: isCancelled)
        doc.format = "DWG"
        if let v = DWGProviders.sniffVersion(url) { doc.version = v; doc.versionName = CADDocument.friendlyVersion(v) }
        doc.warnings += warnings
        return doc
    }
}

/// Reads DWG through every available route in order until one succeeds; records which engine read the file.
public struct DWGEngineChain: DWGImportProvider {
    /// In order of preference.
    public var routes: [any DWGImportProvider]
    /// Explains the situation when no route is available (it also names a chosen converter that is missing).
    public var unavailable: UnavailableDWGProvider

    public init(routes: [any DWGImportProvider], unavailable: UnavailableDWGProvider = UnavailableDWGProvider()) {
        self.routes = routes; self.unavailable = unavailable
    }

    public var available: [any DWGImportProvider] { routes.filter(\.isAvailable) }
    public var isAvailable: Bool { !available.isEmpty }
    public var unavailableReason: String? { isAvailable ? nil : unavailable.unavailableReason }
    public var sdkName: String { available.first?.sdkName ?? unavailable.sdkName }
    public var sdkVersion: String? { available.first?.sdkVersion }
    public var supportedVersions: [String] {
        var seen = Set<String>()
        return available.flatMap(\.supportedVersions).filter { seen.insert($0).inserted }
    }

    public func read(_ url: URL, options: CADReadOptions, progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) throws -> CADDocument {
        let routes = available
        guard !routes.isEmpty else { throw CADError(unavailableReason ?? "DWG import is not available.") }
        var failures: [String] = []
        for (i, r) in routes.enumerated() {
            if isCancelled() { throw CancellationError() }
            do {
                var doc = try r.read(url, options: options, progress: progress, isCancelled: isCancelled)
                if i > 0 {
                    doc.warnings.insert("Read by \(r.sdkName) because the engines before it could not read the drawing: " + failures.joined(separator: " "), at: 0)
                }
                DWGEngineRecord.store(file: url.lastPathComponent, engine: r.sdkName, failures: failures)
                return doc
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append("\(r.sdkName): \(error)")
            }
        }
        DWGEngineRecord.store(file: url.lastPathComponent, engine: nil, failures: failures)
        var msg = "Arcus could not read “\(url.lastPathComponent)”"
        if let v = DWGProviders.sniffVersion(url) { msg += " (\(CADDocument.friendlyVersion(v)) DWG)" }
        msg += ". Tried: " + failures.enumerated().map { "\($0.offset + 1)) \($0.element)" }.joined(separator: " ")
        msg += " Save the drawing as DXF from the application that made it, then import or link the DXF."
        throw CADError(msg)
    }
}

/// Which engine read the last DWG (shown in Settings ▸ DWG).
public enum DWGEngineRecord {
    public static let fileKey = "dwg.last.file"
    public static let engineKey = "dwg.last.engine"
    public static let dateKey = "dwg.last.date"
    public static let failuresKey = "dwg.last.failures"

    public struct Entry: Sendable, Hashable {
        public var file: String
        /// nil when no engine could read it.
        public var engine: String?
        public var date: Date
        public var failures: [String]
    }

    static func store(file: String, engine: String?, failures: [String], defaults: UserDefaults = .standard) {
        defaults.set(file, forKey: fileKey)
        defaults.set(engine ?? "", forKey: engineKey)
        defaults.set(Date(), forKey: dateKey)
        defaults.set(failures, forKey: failuresKey)
    }

    public static func last(_ defaults: UserDefaults = .standard) -> Entry? {
        guard let f = defaults.string(forKey: fileKey), !f.isEmpty else { return nil }
        let e = defaults.string(forKey: engineKey) ?? ""
        return Entry(file: f, engine: e.isEmpty ? nil : e, date: defaults.object(forKey: dateKey) as? Date ?? .distantPast,
                     failures: defaults.stringArray(forKey: failuresKey) ?? [])
    }
}
