import Foundation
import ArcusGeometry

/// A stable reference to a piece of an element's geometry (for dimensions, constraints, alignment, snapping).
public struct GeometryReference: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Wall/beam/grid/line location curve.
        case location
        /// Wall exterior / interior finish faces.
        case exteriorFace, interiorFace
        /// Wall core faces.
        case coreExterior, coreInterior
        /// Start or end point of a curve element.
        case startPoint, endPoint
        /// Center point (column, component, arc center).
        case center
        /// Door/window opening edges (left/right of the opening in plan, along the host).
        case openingLeft, openingRight
        /// Level plane (in elevation/section) — the element is a level.
        case levelPlane
        /// A fixed point in plan (no element); uses `point`.
        case point
    }
    public var elementID: ElementID?
    public var kind: Kind
    public var point: Vec2?

    public init(_ elementID: ElementID?, _ kind: Kind, point: Vec2? = nil) { self.elementID = elementID; self.kind = kind; self.point = point }
    public static func fixed(_ p: Vec2) -> GeometryReference { GeometryReference(nil, .point, point: p) }
}

public enum DimensionKind: String, Codable, Sendable, CaseIterable {
    case linear = "Linear"
    case aligned = "Aligned"
    case angular = "Angular"
    case radial = "Radial"
    case diameter = "Diameter"
    case arcLength = "Arc Length"
}

public struct DimensionData: Hashable, Codable, Sendable {
    public var kind: DimensionKind
    /// References measured, in order along the dimension line. Aligned/linear: two or more.
    public var references: [GeometryReference]
    /// A point the dimension line passes through (view plane coordinates).
    public var linePoint: Vec2
    /// For linear dimensions: direction of measurement (radians). Aligned dims derive it from the references.
    public var direction: Double?
    public var locked: Bool
    public var equality: Bool
    public var textOverride: String?
    public var prefix: String
    public var suffix: String
    public var below: String
    /// Label parameter in family editor dimensions.
    public var labelParameter: String?
    /// Cached measured positions of the references projected on the dimension line (for display when references cannot resolve).
    public var fallbackPoints: [Vec2]
    /// Linear/aligned strings: continuous (nil), baseline or ordinate. Optional: older files decode as continuous.
    public var chainStyle: DimensionChainStyle?
    /// Dragged value texts: offset of segment k's text from its default place (view units). Nil or shorter = default.
    public var textOffsets: [Vec2]?
    /// How an equality-constrained string labels its segments (nil = EQ text).
    public var equalityDisplay: EqualityDisplay?
    public init(kind: DimensionKind, references: [GeometryReference], linePoint: Vec2, direction: Double? = nil, fallbackPoints: [Vec2] = []) {
        self.kind = kind; self.references = references; self.linePoint = linePoint; self.direction = direction
        self.locked = false; self.equality = false; self.textOverride = nil; self.prefix = ""; self.suffix = ""; self.below = ""
        self.labelParameter = nil; self.fallbackPoints = fallbackPoints
    }
}

/// How a multi-reference linear or aligned dimension is laid out.
public enum DimensionChainStyle: String, Codable, Sendable, CaseIterable {
    /// One line, each segment measured from the previous reference.
    case continuous = "Continuous"
    /// Stacked lines, each measured from the first reference.
    case baseline = "Baseline"
    /// One witness per reference, labelled with its distance from the first (the origin, labelled 0).
    case ordinate = "Ordinate"
}

/// Labels of the segments of an equality-constrained dimension string.
public enum EqualityDisplay: String, Codable, Sendable, CaseIterable {
    /// Each segment shows its measured value.
    case value = "Value"
    /// Each segment shows "EQ".
    case text = "Equality Text"
    /// One label for the whole string: "n @ segment = total".
    case formula = "Equality Formula"
}

/// End marks of dimension lines (a dimension type parameter).
public enum DimensionTickMark: String, Codable, Sendable, CaseIterable {
    case diagonal = "Diagonal", heavyDiagonal = "Heavy Diagonal", arrow = "Arrow Filled", openArrow = "Arrow Open", dot = "Dot Filled"
}

public enum TagOrientation: String, Codable, Sendable, CaseIterable { case horizontal = "Horizontal", vertical = "Vertical" }

/// What a tag-like annotation shows. Nil on `TagData.kind` is an ordinary category tag drawn by its tag family.
public enum TagKind: String, Codable, Sendable, CaseIterable {
    /// The material of the tagged element (at the picked layer).
    case material = "Material Tag"
    /// Keynotes: the tagged element's type keynote, its material's keynote, or a key chosen by the user.
    case keynoteElement = "Element Keynote", keynoteMaterial = "Material Keynote", keynoteUser = "User Keynote"
    /// Tread numbers along each run of a stair.
    case treadNumber = "Tread Number"
    /// A reference to another view (its detail and sheet number), placed where the view continues.
    case viewReference = "View Reference"
    /// The span direction symbol of a floor.
    case spanDirection = "Span Direction"
    /// The walk line of a stair with an arrow and UP/DN.
    case stairPath = "Stair Path"
    /// A graphic scale of the owner view.
    case scaleBar = "Scale Bar"

    public var isKeynote: Bool { self == .keynoteElement || self == .keynoteMaterial || self == .keynoteUser }
}

/// What a keynote shows.
public enum KeynoteDisplay: String, Codable, Sendable, CaseIterable { case key = "Key", keyAndText = "Key and Text", text = "Text" }

public struct TagData: Hashable, Codable, Sendable {
    public var taggedID: ElementID
    /// Tag head position in view coordinates.
    public var head: Vec2
    public var hasLeader: Bool
    public var leaderEnd: Vec2?
    public var orientation: TagOrientation
    /// Special tags (material, keynote, tread numbers, view references, symbols). Nil = category tag.
    public var kind: TagKind?
    /// Material tags and material keynotes: the tagged material.
    public var materialID: ElementID?
    /// User keynotes: the chosen key.
    public var keynote: String?
    public var keynoteDisplay: KeynoteDisplay?
    /// Optional bend of the leader (view coordinates).
    public var leaderElbow: Vec2?
    /// Direction for span direction symbols and view references (radians); nil = along the view's x axis.
    public var angle: Double?
    public init(taggedID: ElementID, head: Vec2, hasLeader: Bool = false) {
        self.taggedID = taggedID; self.head = head; self.hasLeader = hasLeader; self.leaderEnd = nil; self.orientation = .horizontal
    }
}

public enum TextAlignment: String, Codable, Sendable, CaseIterable { case left = "Left", center = "Center", right = "Right" }

/// Shape of text note leaders.
public enum LeaderShape: String, Codable, Sendable, CaseIterable { case straight = "Straight", arc = "Arc" }

/// Arrowheads at leader ends (a text type parameter).
public enum LeaderArrowhead: String, Codable, Sendable, CaseIterable { case arrow = "Arrow Filled", openArrow = "Arrow Open", dot = "Dot Filled", none = "None" }

/// Text note backgrounds (a text type parameter): opaque text masks what is behind it.
public enum TextBackground: String, Codable, Sendable, CaseIterable { case opaque = "Opaque", transparent = "Transparent" }

public struct TextNoteData: Hashable, Codable, Sendable {
    public var position: Vec2
    public var text: String
    /// Wrap width on paper (meters); 0 = no wrap.
    public var width: Double
    public var rotation: Double
    public var alignment: TextAlignment
    /// Leader arrow points (view coordinates).
    public var leaders: [Vec2]
    /// Optional elbow of each leader (parallel to `leaders`); a missing or nil entry uses the automatic shoulder.
    public var leaderElbows: [Vec2?]?
    /// Straight (nil) or arc leaders.
    public var leaderShape: LeaderShape?
    /// Instance overrides of the text type's bold, italic and underline (nil = by type).
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public init(position: Vec2, text: String, width: Double = 0) {
        self.position = position; self.text = text; self.width = width; self.rotation = 0; self.alignment = .left; self.leaders = []
    }

    /// The elbow of leader `i`, if one was set.
    public func elbow(_ i: Int) -> Vec2? {
        guard let e = leaderElbows, i < e.count else { return nil }
        return e[i]
    }
}

public enum SpotKind: String, Codable, Sendable, CaseIterable { case elevation = "Spot Elevation", coordinate = "Spot Coordinate", slope = "Spot Slope" }

public struct SpotData: Hashable, Codable, Sendable {
    public var kind: SpotKind
    /// Point on the model in view coordinates.
    public var point: Vec2
    /// Model elevation (for plan views the elevation of the picked surface).
    public var elevation: Double
    public var leaderHead: Vec2
    public var referenceID: ElementID?
    /// Slope value for spot slopes (rise/run) and direction.
    public var slope: Double
    public var slopeDirection: Double
    public init(kind: SpotKind, point: Vec2, elevation: Double, leaderHead: Vec2, referenceID: ElementID? = nil) {
        self.kind = kind; self.point = point; self.elevation = elevation; self.leaderHead = leaderHead; self.referenceID = referenceID
        self.slope = 0; self.slopeDirection = 0
    }
}

public struct FilledRegionData: Hashable, Codable, Sendable {
    public var boundary: Sketch
    public var isMasking: Bool
    public var boundaryStyleID: ElementID?
    public init(boundary: Sketch, isMasking: Bool = false) { self.boundary = boundary; self.isMasking = isMasking; self.boundaryStyleID = nil }
}

public struct DetailComponentData: Hashable, Codable, Sendable {
    public var location: Vec2
    public var rotation: Double
    public var mirrored: Bool
    /// Repeating detail components: the end of the path the component repeats along (from `location`).
    public var repeatEnd: Vec2?
    /// Repeating detail spacing (view units); nil = the component's own length along the path.
    public var repeatSpacing: Double?
    /// Legend components: the model type shown (door, window, wall, furniture… type) instead of a detail family.
    public var legendTypeID: ElementID?
    /// Legend components of wall, floor and roof types: the length drawn (view units).
    public var legendLength: Double?
    public init(location: Vec2, rotation: Double = 0, mirrored: Bool = false) { self.location = location; self.rotation = rotation; self.mirrored = mirrored }
}

public struct RevisionCloudData: Hashable, Codable, Sendable {
    public var outline: Polygon2
    public var revisionID: ElementID?
    public init(outline: Polygon2, revisionID: ElementID?) { self.outline = outline; self.revisionID = revisionID }
}

public struct InsulationData: Hashable, Codable, Sendable {
    public var line: Segment2
    public var width: Double
    public init(line: Segment2, width: Double) { self.line = line; self.width = width }
}

public enum RevisionNumbering: String, Codable, Sendable, CaseIterable { case numeric = "Numeric", alphabetic = "Alphabetic" }
public enum RevisionVisibility: String, Codable, Sendable, CaseIterable {
    case cloudAndTag = "Cloud and Tag Visible", tagOnly = "Tag Visible", hidden = "Hidden"
}

public struct RevisionData: Hashable, Codable, Sendable {
    public var sequence: Int
    public var numbering: RevisionNumbering
    public var date: String
    public var description: String
    public var issuedTo: String
    public var issuedBy: String
    public var issued: Bool
    public var visibility: RevisionVisibility
    public init(sequence: Int, date: String, description: String, numbering: RevisionNumbering = .numeric) {
        self.sequence = sequence; self.numbering = numbering; self.date = date; self.description = description
        self.issuedTo = ""; self.issuedBy = ""; self.issued = false; self.visibility = .cloudAndTag
    }
}
