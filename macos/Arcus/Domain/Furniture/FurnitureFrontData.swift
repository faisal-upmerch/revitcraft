import Foundation
import ArcusGeometry

// FM5: bays, bay separators, and the doors, drawers and flaps hosted in them (Docs/FurnitureMode.md §2 and §3
// "Furniture elements"). A bay behaves like a Revit-style room: it keeps a point inside it and its opening is found
// again from the parts round that point whenever the parts move (FurnitureBays). Bay Divide splits a bay into rows or
// columns like a curtain grid; each cell is a sub-bay element. Fronts are hosted in a bay like doors and windows in a
// wall: their size comes from the bay and their type (overlay, reveals, style), the hinge side flips like a door's hand,
// and their hardware is placed as component instances they own (FurnitureFronts).

/// Which way a bay is seen: from the front (the opening in a Front/Back elevation, in x, z) or from above (a top-access
/// opening picked in plan, in x, y).
public enum BayFace: String, Codable, Sendable, CaseIterable { case front = "Front", top = "Top" }

/// Bay Divide: rows (stacked, like drawers) or columns (side by side), equal (EQ) or by dimension.
public struct BayDivision: Hashable, Codable, Sendable {
    public enum Direction: String, Codable, Sendable, CaseIterable { case rows = "Rows", columns = "Columns" }
    public enum Layout: String, Codable, Sendable, CaseIterable { case equal = "Equal (EQ)", fixed = "By Dimension" }
    public var direction: Direction
    public var layout: Layout
    public var count: Int
    /// By Dimension: the sizes of the first cells from the bottom (rows) or the left (columns); the last cell takes the rest.
    public var sizes: [Double]
    public init(direction: Direction, layout: Layout = .equal, count: Int, sizes: [Double] = []) {
        self.direction = direction; self.layout = layout; self.count = count; self.sizes = sizes
    }

    /// The cell spans along the divided axis from `lo` to `hi` (bottom to top, or left to right).
    public func cells(_ lo: Double, _ hi: Double) -> [(Double, Double)] {
        let n = max(1, count)
        let total = hi - lo
        guard total > 0 else { return [] }
        var spans: [Double]
        if layout == .fixed, !sizes.isEmpty {
            spans = Array(sizes.prefix(n - 1)).map { max(0, $0) }
            while spans.count < n - 1 { spans.append((total - spans.reduce(0, +)) / Double(n - spans.count)) }
            spans.append(max(0, total - spans.reduce(0, +)))
        } else {
            spans = Array(repeating: total / Double(n), count: n)
        }
        var out: [(Double, Double)] = []
        var a = lo
        for s in spans { out.append((a, min(hi, a + s))); a += s }
        return out
    }
}

/// A bay's resolved opening: the clear space between the parts round it (inside faces), its depth from the carcass front
/// to the back (or the back panel's front face), and the outside faces of the bounding parts (for full overlay fronts).
/// `bounds` keeps the plane (and offset) each face follows, so fronts compile to solids that flex.
public struct BayOpening: Hashable, Codable, Sendable {
    public var x0: Double, x1: Double, y0: Double, y1: Double, z0: Double, z1: Double
    /// Outside faces of the bounding parts across the opening: left/right (x) and, seen from the front, bottom/top (z);
    /// seen from above, front/back (y).
    public var outer0: Double, outer1: Double, outerLow: Double, outerHigh: Double
    /// Plane bindings by face: "x0", "x1", "y0", "y1", "z0", "z1", "outer0", "outer1", "outerLow", "outerHigh".
    public var bounds: [String: FurnitureBound]
    /// The bounding parts: left, right, bottom (front from above), top (back from above), back.
    public var left: ElementID?, right: ElementID?, bottom: ElementID?, top: ElementID?, back: ElementID?
    /// Which edges are shared with a neighbouring bay (a divider, a fixed shelf, a separator or a Bay Divide line): fronts
    /// stop at the middle of a shared part instead of covering it.
    public var sharedLeft: Bool, sharedRight: Bool, sharedLow: Bool, sharedHigh: Bool

    public init(x0: Double, x1: Double, y0: Double, y1: Double, z0: Double, z1: Double) {
        self.x0 = x0; self.x1 = x1; self.y0 = y0; self.y1 = y1; self.z0 = z0; self.z1 = z1
        outer0 = x0; outer1 = x1; outerLow = z0; outerHigh = z1; bounds = [:]
        sharedLeft = false; sharedRight = false; sharedLow = false; sharedHigh = false
    }

    public var width: Double { x1 - x0 }
    public var height: Double { z1 - z0 }
    public var depth: Double { y1 - y0 }
    /// The face value with its plane, for compiling.
    public func value(_ key: String) -> PartValue {
        let v: Double = switch key {
        case "x0": x0
        case "x1": x1
        case "y0": y0
        case "y1": y1
        case "z0": z0
        case "z1": z1
        case "outer0": outer0
        case "outer1": outer1
        case "outerLow": outerLow
        default: outerHigh
        }
        return PartValue(v, bounds[key])
    }
    /// The bounding part ids that exist.
    public var parts: [ElementID] { [left, right, bottom, top, back].compactMap { $0 } }
}

/// A bay: the opening between parts, seen from the front or from above. Recomputed from `seed` whenever the parts
/// move (FurnitureBays.regenerate); sub-bays of a Bay Divide take their cell of the parent's opening.
public struct BayData: Hashable, Codable, Sendable {
    public var face: BayFace
    /// A point inside the bay (front: x, z; top: x, y). It follows the opening's centre as the parts move.
    public var seed: Vec2
    /// Top-access bays: the height the opening is found at.
    public var elevation: Double?
    /// "1", "2"… and "1.2" for the second cell of bay 1.
    public var number: String
    /// Sub-bays: the divided bay and the cell's index (from the bottom or the left).
    public var parentID: ElementID?
    public var cell: Int?
    /// Bay Divide of this bay (its cells are sub-bays).
    public var division: BayDivision?
    /// The opening found at the last regeneration (nil = not enclosed).
    public var opening: BayOpening?

    public init(face: BayFace = .front, seed: Vec2, elevation: Double? = nil, number: String) {
        self.face = face; self.seed = seed; self.elevation = elevation; self.number = number
    }
}

/// A Bay Separator: a line that bounds bays without a part, as a room separator bounds rooms. Seen from the front
/// (x, z) or from above (x, y).
public struct BaySeparatorData: Hashable, Codable, Sendable {
    public var face: BayFace
    public var start: Vec2
    public var end: Vec2
    public init(face: BayFace = .front, start: Vec2, end: Vec2) { self.face = face; self.start = start; self.end = end }
    public var isVertical: Bool { abs(end.x - start.x) <= abs(end.y - start.y) }
}

/// What a front is.
public enum FrontKind: String, Codable, Sendable, CaseIterable {
    case door = "Door", drawer = "Drawer", flap = "Flap"
    public var markPrefix: String { switch self { case .door: "D"; case .drawer: "DW"; case .flap: "FL" } }
}

/// How a front sits on the carcass.
public enum FrontOverlay: String, Codable, Sendable, CaseIterable { case full = "Full Overlay", half = "Half Overlay", inset = "Inset" }

/// The construction of a door, drawer or flap front.
public enum FrontStyle: String, Codable, Sendable, CaseIterable { case slab = "Slab", shaker = "Shaker", glass = "Glass Panel", louvered = "Louvered" }

/// Flaps: hinged at the top (lift-up) or the bottom (drop-down).
public enum FlapAction: String, Codable, Sendable, CaseIterable { case liftUp = "Lift-Up", dropDown = "Drop-Down" }

/// Drawer box corner joints (data for the cut list and the joints milestone).
public enum DrawerBoxJoint: String, Codable, Sendable, CaseIterable { case dovetail = "Dovetail", dowel = "Dowel", boxJoint = "Box Joint", butt = "Butt" }

/// Where a front's handle goes.
public enum HandlePosition: String, Codable, Sendable, CaseIterable {
    case top = "Top", middle = "Middle", bottom = "Bottom", center = "Center", none = "None"
    /// The positions a kind offers (doors along the edge opposite the hinges; drawers and flaps across the front).
    public static func options(_ k: FrontKind) -> [HandlePosition] {
        switch k {
        case .door: [.top, .middle, .bottom, .none]
        case .drawer, .flap: [.center, .top, .none]
        }
    }
    public static func defaultFor(_ k: FrontKind, baseCabinet: Bool = true) -> HandlePosition {
        switch k {
        case .door: baseCabinet ? .top : .bottom
        case .drawer: .center
        case .flap: .center
        }
    }
}

/// A door, drawer or flap hosted in a bay (the element's `hostID`). Its size comes from the bay and its type; what's
/// stored here is what the user sets per instance.
public struct FrontData: Hashable, Codable, Sendable {
    public var kind: FrontKind
    /// Single doors hinge on the left unless flipped (the control arrow or Space, as a door's hand).
    public var hingeFlipped: Bool
    public var handlePosition: HandlePosition
    /// Distance from the front's edge to the handle's centre (nil = the type's default).
    public var handleOffset: Double?
    /// Instance overrides of the type's hardware (nil = the type's).
    public var handleTypeID: ElementID?
    public var hingeTypeID: ElementID?
    public init(kind: FrontKind, hingeFlipped: Bool = false, handlePosition: HandlePosition? = nil) {
        self.kind = kind; self.hingeFlipped = hingeFlipped; self.handlePosition = handlePosition ?? HandlePosition.defaultFor(kind)
    }
}

// MARK: - Element accessors

extension Element {
    public var furnitureBay: BayData? {
        get { if case .furnitureBay(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .furnitureBay(v) } }
    }
    public var furnitureFront: FrontData? {
        get { if case .furnitureFront(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .furnitureFront(v) } }
    }
    public var furnitureBaySeparator: BaySeparatorData? {
        get { if case .furnitureBaySeparator(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .furnitureBaySeparator(v) } }
    }
}

extension Category {
    /// FM5: the categories of bays, fronts, separators and hardware.
    public static let furnitureOpenings: [Category] = [.furnitureBays, .furnitureFronts, .furnitureBaySeparators, .furnitureHardware]
}
