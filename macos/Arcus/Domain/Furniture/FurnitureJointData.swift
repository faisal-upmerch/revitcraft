import Foundation
import ArcusGeometry

// FM6: joints between furniture parts (Docs/FurnitureMode.md §3 "Joints"). They behave like Revit-style wall joins:
// every pair of parts that touch or overlap gets a joint at regeneration from the document's Joint Rules (pair kind →
// joint type and parameters), computed and never stored. Only joints the user sets with the Joint tool, and ends where
// the user disallowed a join, are stored, as `furnitureJoint(JointData)` elements. All lengths are in model units
// (meters); the UI shows them in feet and inches.

/// How two parts are joined.
public enum JointType: String, Codable, Sendable, CaseIterable {
    case butt = "Butt", miter = "Miter", dado = "Dado", rabbet = "Rabbet", groove = "Groove", dowel = "Dowel", camLock = "Cam Lock"
    case pocketScrew = "Pocket Screw", mortiseTenon = "Mortise and Tenon", confirmat = "Confirmat Screw", biscuit = "Biscuit"

    /// Housed joints: the butting part runs into a groove in the other (its cut size grows by the depth).
    public var isHoused: Bool { self == .dado || self == .rabbet || self == .groove }
    /// Joints with fasteners or holes along the joint.
    public var hasFasteners: Bool { [.dowel, .camLock, .pocketScrew, .confirmat, .biscuit].contains(self) }
    /// The parameters the Joint tool and Joint Rules show for this type.
    public var parameterKeys: [JointParameterKey] {
        switch self {
        case .butt, .miter: []
        case .dado, .groove: [.depth, .clearance]
        case .rabbet: [.depth]
        case .dowel: [.diameter, .length, .spacing, .edgeDistance, .count]
        case .camLock, .confirmat, .biscuit: [.spacing, .edgeDistance, .count]
        case .pocketScrew: [.spacing, .edgeDistance, .count, .angle]
        case .mortiseTenon: [.depth, .shoulder, .tenonThickness]
        }
    }
}

/// One joint parameter (Options Bar, Properties and Joint Rules use the same names).
public enum JointParameterKey: String, Codable, Sendable, CaseIterable {
    case depth = "Depth", clearance = "Clearance", diameter = "Diameter", length = "Length", spacing = "Spacing"
    case edgeDistance = "Edge Distance", count = "Count", angle = "Angle", shoulder = "Shoulder", tenonThickness = "Tenon Thickness"

    /// The label for a joint type (Mortise and Tenon calls its depth the tenon length).
    public func label(for type: JointType) -> String {
        if type == .mortiseTenon && self == .depth { return "Tenon Length" }
        if type == .dowel && self == .length { return "Dowel Length" }
        return rawValue
    }
    public var isAngle: Bool { self == .angle }
    public var isCount: Bool { self == .count }
}

/// A joint's parameters. Every value is optional: nil takes the type's default (`JointParameters.defaults`).
public struct JointParameters: Hashable, Codable, Sendable {
    /// Housed joints: how deep the groove is. Mortise and tenon: the tenon length.
    public var depth: Double?
    /// Housed joints: the groove is the mating part's thickness plus this.
    public var clearance: Double?
    /// Dowels.
    public var diameter: Double?
    public var length: Double?
    /// The largest distance between fasteners along the joint, and their distance from its ends.
    public var spacing: Double?
    public var edgeDistance: Double?
    /// A fixed number of fasteners (nil or 0: as many as the spacing needs).
    public var count: Int?
    /// Pocket screws: the pocket's angle to the face (radians).
    public var angle: Double?
    /// Mortise and tenon: the shoulders and the tenon's thickness (nil: a third of the rail).
    public var shoulder: Double?
    public var tenonThickness: Double?

    public init(depth: Double? = nil, clearance: Double? = nil, diameter: Double? = nil, length: Double? = nil, spacing: Double? = nil,
                edgeDistance: Double? = nil, count: Int? = nil, angle: Double? = nil, shoulder: Double? = nil, tenonThickness: Double? = nil) {
        self.depth = depth; self.clearance = clearance; self.diameter = diameter; self.length = length; self.spacing = spacing
        self.edgeDistance = edgeDistance; self.count = count; self.angle = angle; self.shoulder = shoulder; self.tenonThickness = tenonThickness
    }

    static let inch = 0.0254

    /// The type's defaults (Imperial where shops work in inches; 32 mm-system hardware keeps its metric sizes).
    public static func defaults(_ type: JointType) -> JointParameters {
        let i = inch
        switch type {
        case .butt, .miter: return JointParameters()
        case .dado: return JointParameters(depth: 0.25 * i, clearance: 1.0 / 32 * i)
        case .groove: return JointParameters(depth: 0.25 * i, clearance: 1.0 / 16 * i)
        case .rabbet: return JointParameters(depth: 0.375 * i)
        case .dowel: return JointParameters(diameter: 0.008, length: 0.030, spacing: 6 * i, edgeDistance: 1.5 * i)
        case .camLock: return JointParameters(diameter: 0.015, spacing: 12 * i, edgeDistance: 0.037)
        case .confirmat: return JointParameters(diameter: 0.007, spacing: 8 * i, edgeDistance: 2 * i)
        case .pocketScrew: return JointParameters(diameter: 0.375 * i, spacing: 8 * i, edgeDistance: 2 * i, angle: 15 * .pi / 180)
        case .biscuit: return JointParameters(spacing: 8 * i, edgeDistance: 2 * i)
        case .mortiseTenon: return JointParameters(depth: 1 * i, shoulder: 0.25 * i)
        }
    }

    /// These values over `base` (nil keeps the base's).
    public func over(_ base: JointParameters) -> JointParameters {
        JointParameters(depth: depth ?? base.depth, clearance: clearance ?? base.clearance, diameter: diameter ?? base.diameter, length: length ?? base.length,
                        spacing: spacing ?? base.spacing, edgeDistance: edgeDistance ?? base.edgeDistance, count: count ?? base.count, angle: angle ?? base.angle,
                        shoulder: shoulder ?? base.shoulder, tenonThickness: tenonThickness ?? base.tenonThickness)
    }

    public func value(_ k: JointParameterKey) -> Double? {
        switch k {
        case .depth: depth
        case .clearance: clearance
        case .diameter: diameter
        case .length: length
        case .spacing: spacing
        case .edgeDistance: edgeDistance
        case .count: count.map(Double.init)
        case .angle: angle
        case .shoulder: shoulder
        case .tenonThickness: tenonThickness
        }
    }

    public mutating func set(_ k: JointParameterKey, _ v: Double?) {
        switch k {
        case .depth: depth = v
        case .clearance: clearance = v
        case .diameter: diameter = v
        case .length: length = v
        case .spacing: spacing = v
        case .edgeDistance: edgeDistance = v
        case .count: count = v.map { Int($0.rounded()) }
        case .angle: angle = v
        case .shoulder: shoulder = v
        case .tenonThickness: tenonThickness = v
        }
    }

    /// True when no value is set.
    public var isEmpty: Bool { self == JointParameters() }
}

/// One end of a part: the min or max side of its box along an axis.
public struct PartEnd: Hashable, Codable, Sendable {
    public var axis: FamilyAxis
    public var atMax: Bool
    public init(axis: FamilyAxis, atMax: Bool) { self.axis = axis; self.atMax = atMax }
}

/// A joint the user set with the Joint tool (type, which part runs through, parameters), or a part end where the user
/// disallowed joins. Automatic joints are not stored.
public struct JointData: Hashable, Codable, Sendable {
    /// The two parts (sorted); one part for a Disallow Join.
    public var parts: [ElementID]
    /// nil = By Rule.
    public var type: JointType?
    /// The part that runs through (nil = by rule, or as drawn).
    public var throughPartID: ElementID?
    /// Values over the rule's (nil = the rule's).
    public var parameters: JointParameters?
    /// Disallow Join: the end of `parts[0]` that joins nothing.
    public var disallowedEnd: PartEnd?

    public init(parts: [ElementID], type: JointType? = nil, throughPartID: ElementID? = nil, parameters: JointParameters? = nil, disallowedEnd: PartEnd? = nil) {
        self.parts = parts.sorted(); self.type = type; self.throughPartID = throughPartID; self.parameters = parameters; self.disallowedEnd = disallowedEnd
    }

    /// A joint between two parts (not a Disallow Join).
    public var isPair: Bool { parts.count == 2 && disallowedEnd == nil }
    /// Nothing is overridden (the element can go).
    public var isByRule: Bool { type == nil && throughPartID == nil && (parameters?.isEmpty ?? true) }
}

/// The two parts of a joint, smaller id first.
public struct JointKey: Hashable, Codable, Sendable, Comparable {
    public var a: ElementID
    public var b: ElementID
    public init(_ p: ElementID, _ q: ElementID) { a = min(p, q); b = max(p, q) }
    public static func < (l: JointKey, r: JointKey) -> Bool { l.a != r.a ? l.a < r.a : l.b < r.b }
}

// MARK: - Joint Rules

/// What a part is to the joint solver.
public enum JointRole: String, Sendable, CaseIterable {
    case side = "Side", top = "Top", bottom = "Bottom", shelf = "Shelf", adjustableShelf = "Adjustable Shelf", back = "Back", divider = "Divider"
    case plinth = "Plinth", leg = "Leg", rail = "Rail"
    case slat = "Slat" // FMG2
}

/// The kinds of part pairs Joint Rules sets a joint for.
public enum JointPairKind: String, Codable, Sendable, CaseIterable {
    case sideTop = "Side – Top", sideBottom = "Side – Bottom", sideSide = "Side – Side", sideBack = "Side – Back", shelfSide = "Shelf – Side"
    case shelfBack = "Shelf – Back", dividerShelf = "Divider – Shelf", plinthCarcass = "Plinth – Carcass", railLeg = "Rail – Leg", railPanel = "Rail – Panel"
    case railTop = "Rail – Top", topLeg = "Top – Leg"
    case slatFrame = "Slat – Frame" // FMG2
    case other = "Other"

    /// The names of the pair's two parts, as the rule's Runs Through choices show them.
    public var roles: (first: String, second: String) {
        let parts = rawValue.components(separatedBy: " – ")
        return (parts.first ?? "First", parts.count > 1 ? parts[1] : "Second")
    }

    /// One line on what the rule covers (Joint Rules dialog).
    public var help: String {
        switch self {
        case .sideTop: "Sides and the top."
        case .sideBottom: "Sides and the bottom."
        case .sideSide: "Panels meeting at a corner (a box drawn as a rectangle)."
        case .sideBack: "The back and the sides, top, bottom and dividers round it."
        case .shelfSide: "Fixed shelves and horizontal dividers into sides and dividers."
        case .shelfBack: "Shelves against the back."
        case .dividerShelf: "Vertical dividers and the shelves, top or bottom they meet."
        case .plinthCarcass: "The plinth under the bottom and between the sides."
        case .railLeg: "Aprons and stretchers into legs."
        case .railPanel: "Rails into sides and other panels."
        case .railTop: "Aprons under a top or shelf."
        case .topLeg: "Legs under a top or shelf."
        case .slatFrame: "Slats into the rails, legs or panels they span between." // FMG2
        case .other: "Any other parts that touch."
        }
    }
}

/// Which part of a pair runs through (the other is trimmed to it).
public enum JointThrough: String, Codable, Sendable, CaseIterable {
    /// The pair kind's first part (Side in Side – Top); for two parts of the same kind, the first drawn.
    case first = "First"
    case second = "Second"
    /// The longer part.
    case longer = "Longer"
}

/// The joint a pair kind gets.
public struct JointRule: Hashable, Codable, Sendable {
    public var pair: JointPairKind
    public var type: JointType
    public var through: JointThrough
    public var parameters: JointParameters
    public init(_ pair: JointPairKind, _ type: JointType, through: JointThrough = .first, parameters: JointParameters = JointParameters()) {
        self.pair = pair; self.type = type; self.through = through; self.parameters = parameters
    }
}

/// Manage ▸ Joint Rules: the joint each pair kind gets, stored with the document's furniture setup.
public struct FurnitureJointRules: Hashable, Codable, Sendable {
    public var rules: [JointRule]
    public init(rules: [JointRule]) { self.rules = rules }

    /// The rule of a pair kind (the category's default when the table has none).
    public func rule(_ pair: JointPairKind, category: FamilyTemplate) -> JointRule {
        rules.first { $0.pair == pair } ?? Self.defaults(category).rules.first { $0.pair == pair } ?? JointRule(pair, .butt)
    }

    /// Sensible defaults: Casework is dowelled, with dadoed fixed shelves and a grooved back; Furniture has mortise and
    /// tenon rails and dowels elsewhere. Aprons are pocket-screwed to tops in both.
    public static func defaults(_ category: FamilyTemplate) -> FurnitureJointRules {
        let casework = category != .furniture
        let rules: [JointRule] = [
            JointRule(.sideTop, .dowel), JointRule(.sideBottom, .dowel), JointRule(.sideSide, .dowel, through: .longer),
            JointRule(.sideBack, casework ? .groove : .rabbet),
            JointRule(.shelfSide, casework ? .dado : .dowel, through: .second), JointRule(.shelfBack, .butt, through: .second),
            JointRule(.dividerShelf, casework ? .dado : .dowel, through: .second), JointRule(.plinthCarcass, casework ? .pocketScrew : .dowel, through: .second),
            JointRule(.railLeg, .mortiseTenon, through: .second), JointRule(.railPanel, .dowel, through: .second), JointRule(.railTop, .pocketScrew, through: .second),
            JointRule(.topLeg, .dowel),
            JointRule(.slatFrame, casework ? .dowel : .mortiseTenon, through: .second), // FMG2
            JointRule(.other, .butt, through: .longer),
        ]
        return FurnitureJointRules(rules: rules)
    }
}

extension BIMModel {
    /// The document's Joint Rules (its category's defaults until edited).
    public var furnitureJointRules: FurnitureJointRules {
        guard let s = furnitureSetup else { return FurnitureJointRules.defaults(.casework) }
        return s.jointRules ?? FurnitureJointRules.defaults(s.category)
    }
}

// MARK: - Element accessor

extension Element {
    public var furnitureJoint: JointData? {
        get { if case .furnitureJoint(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .furnitureJoint(v) } }
    }
}
