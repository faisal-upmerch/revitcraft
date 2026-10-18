import Foundation
import ArcusGeometry
import ArcusDomain

/// How imported CAD content is positioned in the model.
public enum CADPositioning: Sendable, Hashable {
    /// Drawing origin (0,0) lands on the model's internal origin.
    case originToOrigin
    /// Center of the drawing extents lands on the model's internal origin.
    case centerToCenter
    /// Drawing coordinates are shared (survey) coordinates: the drawing point (easting, northing) lands on the project
    /// survey point, and the drawing is rotated counter-clockwise by `rotation` radians about it (e.g. the angle from
    /// grid north to project north).
    case sharedCoordinates(easting: Double, northing: Double, rotation: Double)
}

public struct CADImportOptions: Sendable {
    /// Layout to import; nil = model space.
    public var layout: String? = nil
    /// Overrides the drawing's $INSUNITS.
    public var unitsOverride: CADUnits? = nil
    /// Layers to import (case-insensitive); nil = all layers.
    public var includedLayers: Set<String>? = nil
    public var positioning: CADPositioning = .originToOrigin
    /// Additional uniform scale applied about the insertion point.
    public var scale = 1.0
    /// Additional rotation (radians, counter-clockwise) about the insertion point.
    public var rotation = 0.0
    /// Flattens block references into plain geometry instead of keeping reusable blocks.
    public var explodeBlocks = false
    /// Level the import is placed on.
    public var levelID: ElementID? = nil
    /// View that owns a view-specific import ("current view only").
    public var currentViewOnly: ElementID? = nil
    /// Link (reloadable, source-tracked) instead of an import snapshot.
    public var isLink = false
    public init() {}
}

/// Summary of a CAD import, shown to the user after placing a link or import.
public struct CADImportReport: Sendable {
    public var fileName: String = ""
    /// "DXF" or "DWG".
    public var format: String = ""
    /// Friendly version, e.g. "AutoCAD 2018 (AC1032)".
    public var version: String = ""
    /// Units used for the import (after any override).
    public var units: CADUnits = .unitless
    /// Meters per drawing unit.
    public var unitScale: Double = 1
    /// Extents of the imported content in meters, in drawing (world) coordinates.
    public var extents: Rect2 = Rect2(min: .zero, max: .zero)
    public var layouts: [String] = []
    public var layerCount: Int = 0
    public var entityCountsByType: [String: Int] = [:]
    /// Source entities converted to reference geometry.
    public var converted: Int = 0
    /// Entities retained as reference-only geometry (proxy boxes, 3D faces and meshes, image frames).
    public var retainedAsReference: Int = 0
    /// Entity types that could not be converted (including those retained only as a bounding box).
    public var unsupported: [String: Int] = [:]
    public var missingFonts: [String] = []
    public var missingXrefs: [String] = []
    public var missingImages: [String] = []
    public var warnings: [String] = []
    public var elapsed: TimeInterval = 0
    public var peakMemoryBytes: UInt64 = 0
    public init() {}

    /// Short multi-line summary for display.
    public var summary: String {
        var lines = ["\(fileName) — \(format) \(version)",
                     "Units: \(units.displayName) (1 unit = \(unitScale) m)",
                     "Converted \(converted) entities; \(retainedAsReference) kept as reference geometry."]
        if !unsupported.isEmpty {
            lines.append("Not converted: " + unsupported.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", "))
        }
        if !missingXrefs.isEmpty { lines.append("Missing references: " + missingXrefs.joined(separator: ", ")) }
        if !missingImages.isEmpty { lines.append("Missing images: " + missingImages.joined(separator: ", ")) }
        if !missingFonts.isEmpty { lines.append("Substituted fonts: " + missingFonts.joined(separator: ", ")) }
        lines.append(contentsOf: warnings)
        return lines.joined(separator: "\n")
    }
}

/// Resident memory sampling (Mach task info) used for the import report's peak memory.
public enum CADMemory {
    /// Current resident size of this process in bytes (0 if unavailable).
    public static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let port = task_self_trap()
        defer { _ = mach_port_deallocate(port, port) }
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(port, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
}

/// Thread-safe peak sampler.
final class CADPeakSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64 = 0
    private var lastSample = Date.distantPast
    func sample(force: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        guard force || now.timeIntervalSince(lastSample) > 0.05 else { return }
        lastSample = now
        peak = max(peak, CADMemory.residentBytes())
    }
    var value: UInt64 { lock.lock(); defer { lock.unlock() }; return peak }
}
