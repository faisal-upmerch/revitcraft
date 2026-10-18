import Foundation
import ArcusGeometry
import ArcusDomain

// F5: sketch-mode finish of Massing & Site ▸ In-Place Mass, as RevitCraft's finish_sketch does it (`SketchKind::Mass`
// → `add_mass(level, outline, mass_height)`).

/// What an F5 sketch creates.
public enum F5SketchTarget: Sendable, Equatable {
    case mass

    public var title: String {
        switch self {
        case .mass: "Mass Footprint"
        }
    }
}

/// Options of the In-Place Mass sketch. The last values are kept for the next mass, as RevitCraft keeps `mass_height`.
public struct MassSketchOptions: Sendable, Equatable {
    /// nil = the default (10 m, 30'-0" in imperial projects).
    public var height: Double?
    /// Blend top inset; 0 = an extrusion.
    public var topInset: Double = 0
    public init(height: Double? = nil, topInset: Double = 0) { self.height = height; self.topInset = topInset }

    /// The options of the last In-Place Mass sketch.
    @MainActor public static var last = MassSketchOptions()
}

extension SketchTool {
    func f5Options(_ t: F5SketchTarget) -> [ToolOption] {
        guard editingID == nil else { return [] } // Edit Boundary keeps the mass's height and form (Properties edits them)
        switch t {
        case .mass:
            return [ToolOption(id: "massHeight", label: "Height", kind: .length, value: .double(massOptions.height ?? MassGeometry.defaultHeight(ctx.units))),
                    ToolOption(id: "massForm", label: "Form", kind: .choice(["Extrusion", "Blend"]), value: .text(massOptions.topInset > 0 ? "Blend" : "Extrusion")),
                    ToolOption(id: "massTopInset", label: "Top Inset", kind: .length, value: .double(massOptions.topInset))]
        }
    }

    func f5SetOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "massHeight":
            guard let h = value.doubleValue, h > Tolerance.length else { message("The mass height must be positive."); return }
            massOptions.height = h
        case "massForm":
            // Blend starts with a top inset of a tenth of the height; Extrusion clears it.
            let blend = value.textValue == "Blend"
            massOptions.topInset = blend ? (massOptions.topInset > 0 ? massOptions.topInset : (massOptions.height ?? MassGeometry.defaultHeight(ctx.units)) / 10) : 0
        case "massTopInset":
            guard let d = value.doubleValue, d >= 0 else { message("The top inset can't be negative."); return }
            massOptions.topInset = d
        default: return
        }
        MassSketchOptions.last = massOptions
    }

    /// Creates the mass from the sketch's outer loop and keeps it selected.
    func f5Commit(_ t: F5SketchTarget, _ sketch: Sketch, level: ElementID?) {
        switch t {
        case .mass:
            guard case .success(let polys) = sketch.polygons(), let outline = polys.max(by: { $0.area < $1.area }) else { message("Sketch a closed loop."); return }
            if let id = editingID { // Edit Boundary: the new footprint, keeping height and form
                ctx.session.perform("Edit Mass Footprint") { tx in
                    guard var m = tx.model[id]?.mass else { return }
                    m.boundary = outline.counterClockwise.points
                    if m.isBlend, MassGeometry.topLoop(m) == nil { throw TransactionError("The top inset leaves no top face on this footprint.") }
                    tx.update(id) { $0.mass = m }
                }
                if ctx.session.lastError == nil { ctx.session.selection.select([id]) }
                return
            }
            let height = massOptions.height ?? MassGeometry.defaultHeight(ctx.units)
            let inset = massOptions.topInset
            var created: ElementID?
            ctx.session.perform("Create Mass") { tx in
                created = try MassGeometry.create(boundary: outline.points, height: height, topInset: inset, level: level, in: tx)
            }
            if ctx.session.lastError == nil, let created { ctx.session.selection.select([created]) }
        }
    }
}
