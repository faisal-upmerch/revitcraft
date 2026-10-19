import Foundation
import ArcusGeometry
import ArcusDomain

// DWG: File ▸ Export ▸ CAD Formats ▸ DWG. Views and sheets are written as 2D DXF by Arcus's own DXFWriter (same AIA or
// category layers as the DXF export), then turned into DWG by the bundled acadrust helper, which reads every DWG back
// before it is saved (BundledDWGEngine.swift). Saving goes through acadrust only.

/// The DWG versions Arcus writes. All six passed the DXF→DWG→read-back corpus test (Docs/VerificationReport.md).
public enum DWGExportVersion: String, CaseIterable, Sendable, Identifiable {
    case r2018 = "AC1032", r2013 = "AC1027", r2010 = "AC1024", r2007 = "AC1021", r2004 = "AC1018", r2000 = "AC1015"
    public var id: String { rawValue }
    /// E.g. "AutoCAD 2018 DWG".
    public var title: String { "\(CADDocument.friendlyVersion(rawValue)) DWG" }
    public static let `default` = DWGExportVersion.r2018
}

public enum DWGExporter {
    /// What one export wrote.
    public struct Summary: Sendable {
        public var url: URL
        public var version: DWGExportVersion
        public var entities: Int
    }

    /// Why DWG export can't run, or nil when the bundled engine is present.
    public static func unavailableReason(helpers: BundledDWGHelpers = .standard) -> String? {
        helpers.acadrust == nil
            ? "DWG export needs Arcus's DWG engine, which is missing from this copy of Arcus. Export DXF instead (File ▸ Export ▸ CAD Formats ▸ DXF), or reinstall Arcus."
            : nil
    }

    /// Converts Arcus DXF bytes to a DWG at `url`, replacing an existing file only once the new one has been written
    /// and read back. Throws a plain-language `CADError`.
    @discardableResult
    public static func write(dxf: Data, to url: URL, version: DWGExportVersion = .default, helper: URL?, timeout: TimeInterval = 600,
                             isCancelled: @Sendable () -> Bool = { false }) throws -> Summary {
        guard let helper, FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw CADError(unavailableReason(helpers: .none) ?? "DWG export is not available.")
        }
        guard DXFReader.looksLikeDXF(dxf) else { throw CADError("There was no drawing to export to DWG.") }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("Arcus-DWGExport-\(UUID().uuidString)", isDirectory: true)
        let logs = work.appendingPathComponent("logs", isDirectory: true)
        try fm.createDirectory(at: logs, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: work) }
        let src = work.appendingPathComponent("drawing.dxf"), out = work.appendingPathComponent("drawing.dwg")
        try dxf.write(to: src)
        let outcome = try ExternalProcessRunner.run(
            helper, arguments: ["from-dxf", src.path, out.path, "--version", version.rawValue, "--timeout", "\(Int(timeout))",
                                "--max-memory-mb", "\(BundledDWGEngine.memoryLimitMB)"],
            workingDirectory: work, logDirectory: logs, timeout: timeout + 15, isCancelled: isCancelled)
        guard outcome.exitCode == 0, fm.fileExists(atPath: out.path) else {
            throw CADError(BundledDWGEngine.message(outcome, doing: "writing “\(url.lastPathComponent)”"))
        }
        let info = BundledDWGEngine.summary(outcome.standardOutput)
        do {
            if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: out) } else { try fm.moveItem(at: out, to: url) }
        } catch {
            throw CADError("“\(url.lastPathComponent)” could not be saved: \(error.localizedDescription)")
        }
        return Summary(url: url, version: version, entities: info["modelSpaceEntities"] as? Int ?? 0)
    }

    /// A file name for a view or sheet export ("A101 - Ground Floor.dwg"), without characters Finder or CAD tools reject.
    public static func fileName(_ title: String) -> String {
        let bad = Set("/\\:*?\"<>|")
        var s = String(title.map { bad.contains($0) || $0.isNewline ? "-" : $0 }).trimmingCharacters(in: .whitespaces)
        while s.hasPrefix(".") { s.removeFirst() }
        if s.isEmpty { s = "Drawing" }
        return String(s.prefix(200)) + ".dwg"
    }
}
