import Foundation
import ArcusGeometry
import simd

// F1415: Family Editor content from RevitCraft (`crates/rc-core/src/family_def.rs`): work planes for sketches, model and
// reference lines, flip controls and model text. Every field is optional or defaults to empty in JSON, so families written
// before these existed decode unchanged.

/// The plane a family sketch lies on (RevitCraft `SketchPlane`). Sketch coordinates (u, v) and the extrusion direction w map
/// to family XYZ: XY sketches (x, y) extrude along z; XZ sketches (x, z) along y; YZ sketches (y, z) along x.
public enum FamilySketchPlane: String, Codable, Sendable, CaseIterable {
    case xy = "XY", xz = "XZ", yz = "YZ"

    /// The family point at sketch coordinates (u, v) and depth w.
    public func point(_ u: Double, _ v: Double, _ w: Double = 0) -> Vec3 {
        switch self {
        case .xy: Vec3(u, v, w)
        case .xz: Vec3(u, w, v)
        case .yz: Vec3(w, u, v)
        }
    }

    /// Sketch to family coordinates as a transform (the XZ mapping swaps two axes, so it mirrors).
    public var transform: Transform3 {
        switch self {
        case .xy: .identity
        case .xz: Transform3(simd_double4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 0, 1))))
        case .yz: Transform3(simd_double4x4(columns: (SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(1, 0, 0, 0), SIMD4(0, 0, 0, 1))))
        }
    }

    /// Axes of the sketch's u, v and normal (w) directions.
    public var axes: (u: FamilyAxis, v: FamilyAxis, w: FamilyAxis) {
        switch self {
        case .xy: (.x, .y, .z)
        case .xz: (.x, .z, .y)
        case .yz: (.y, .z, .x)
        }
    }

    /// The sketch plane whose normal is `axis` (the plane a named reference plane of that axis sets).
    public static func normal(_ axis: FamilyAxis) -> FamilySketchPlane {
        switch axis {
        case .z: .xy
        case .y: .xz
        case .x: .yz
        }
    }

    public var label: String {
        switch self {
        case .xy: "Ref. Level (plan)"
        case .xz: "Front (elevation)"
        case .yz: "Right (elevation)"
        }
    }
}

/// Create ▸ Model Line or Reference Line: a straight line on a work plane, shown in every family view. Model lines are part
/// of the family's geometry in projects; reference lines are datums (green) and never show in projects.
public struct FamilyModelLine: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var plane: FamilySketchPlane
    /// Position of the work plane along its normal (a reference plane name locks the line to it).
    public var offset: FamilyBound
    /// Ends in sketch coordinates (u, v).
    public var start: FamilyPoint
    public var end: FamilyPoint
    public var isReference: Bool
    public var subcategory: FamilySubcategory
    public var visibleAt: Set<DetailLevel>
    public init(plane: FamilySketchPlane, offset: FamilyBound = .expr("0"), start: FamilyPoint, end: FamilyPoint, isReference: Bool = false) {
        id = UUID().uuidString; self.plane = plane; self.offset = offset; self.start = start; self.end = end; self.isReference = isReference
        subcategory = .general; visibleAt = [.coarse, .medium, .fine]
    }

    enum CodingKeys: String, CodingKey { case id, plane, offset, start, end, isReference, subcategory, visibleAt }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        plane = try c.decodeIfPresent(FamilySketchPlane.self, forKey: .plane) ?? .xy
        offset = try c.decodeIfPresent(FamilyBound.self, forKey: .offset) ?? .expr("0")
        start = try c.decode(FamilyPoint.self, forKey: .start)
        end = try c.decode(FamilyPoint.self, forKey: .end)
        isReference = try c.decodeIfPresent(Bool.self, forKey: .isReference) ?? false
        subcategory = try c.decodeIfPresent(FamilySubcategory.self, forKey: .subcategory) ?? .general
        visibleAt = try c.decodeIfPresent(Set<DetailLevel>.self, forKey: .visibleAt) ?? [.coarse, .medium, .fine]
    }
}

/// Create ▸ Control: a flip arrow shown on placed instances in plan (RevitCraft `ControlKind`). Horizontal controls flip the
/// hand (mirror across the family's Y axis); vertical ones flip the facing (mirror across its X axis).
public enum FamilyControlKind: String, Codable, Sendable, CaseIterable {
    case singleVertical = "Single Vertical", doubleVertical = "Double Vertical"
    case singleHorizontal = "Single Horizontal", doubleHorizontal = "Double Horizontal"
    public var isHorizontal: Bool { self == .singleHorizontal || self == .doubleHorizontal }
    public var isDouble: Bool { self == .doubleVertical || self == .doubleHorizontal }
}

public struct FamilyControl: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    /// Plan position in family coordinates.
    public var position: FamilyPoint
    public var kind: FamilyControlKind
    public init(position: FamilyPoint, kind: FamilyControlKind) { id = UUID().uuidString; self.position = position; self.kind = kind }
}

/// Create ▸ Model Text: glyphs on a sketch plane, extruded `depth` from the work plane (RevitCraft `ModelTextDef`).
public struct FamilyModelText: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var plane: FamilySketchPlane
    /// Insertion point (the first baseline's left end) in sketch coordinates.
    public var position: FamilyPoint
    /// Position of the work plane along its normal; the glyphs extrude from it by `depth`.
    public var offset: FamilyBound
    /// Text Size: the capital height (metres).
    public var size: Double
    public var depth: Double
    public var fontName: String
    public var materialParameter: String?
    public var visibilityParameter: String?
    public init(text: String, plane: FamilySketchPlane, position: FamilyPoint, offset: FamilyBound = .expr("0"), size: Double = 0.3, depth: Double = 0.05) {
        id = UUID().uuidString; self.text = text; self.plane = plane; self.position = position; self.offset = offset
        self.size = size; self.depth = depth; fontName = ModelTextData.defaultFont; materialParameter = nil; visibilityParameter = nil
    }

    enum CodingKeys: String, CodingKey { case id, text, plane, position, offset, size, depth, fontName, materialParameter, visibilityParameter }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try c.decode(String.self, forKey: .text)
        plane = try c.decodeIfPresent(FamilySketchPlane.self, forKey: .plane) ?? .xy
        position = try c.decode(FamilyPoint.self, forKey: .position)
        offset = try c.decodeIfPresent(FamilyBound.self, forKey: .offset) ?? .expr("0")
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 0.3
        depth = try c.decodeIfPresent(Double.self, forKey: .depth) ?? 0.05
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? ModelTextData.defaultFont
        materialParameter = try c.decodeIfPresent(String.self, forKey: .materialParameter)
        visibilityParameter = try c.decodeIfPresent(String.self, forKey: .visibilityParameter)
    }

    /// The text as project model text data, for the shared glyph geometry.
    var glyphData: ModelTextData { ModelTextData(text: text, position: .zero, size: size, depth: depth, fontName: fontName) }
}

extension FamilySweep {
    /// F1415: a swept blend is a sweep whose profile changes along the path to `endProfile`.
    public var isSweptBlend: Bool { (endProfile?.count ?? 0) >= 3 }
}

extension FamilySolid.Profile {
    /// F1415: the form's name, telling swept blends from sweeps.
    public var kindName: String {
        if case .sweep(let sw) = self, sw.isSweptBlend { return "Swept Blend" }
        return formName
    }
}

extension FamilyDefinition {
    /// F1415: whether a placed instance shows flip controls in plan.
    public var hasControls: Bool { !controls.isEmpty }

    /// F1415: true when the family uses content a format-2 reader would drop or misread (elevation sketches, swept blends,
    /// model and reference lines, controls, model text).
    var usesF1415Content: Bool {
        !modelLines.isEmpty || !controls.isEmpty || !modelTexts.isEmpty
            || solids.contains { s in
                if let w = s.workPlane, w != .xy { return true }
                if case .sweep(let sw) = s.profile, sw.isSweptBlend { return true }
                return false
            }
    }
}
