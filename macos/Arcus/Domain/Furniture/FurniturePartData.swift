import Foundation
import ArcusGeometry

// FM4: Furniture mode parts (Docs/FurnitureMode.md §2 mapping table and §3 "Furniture elements"). Each part behaves
// like its Revit-style Architecture counterpart: Panels like walls, Shelves/Tops/Bottoms like floors, Legs like columns,
// Rails like beams (and Slats like a beam system), Edge Profiles/Grooves like wall sweeps/reveals, and Forms like the
// Family Editor's forms. Parts store their resolved geometry plus optional plane bindings (`bounds`), so they follow
// the reference planes when Family Types values change (FurniturePartRegeneration) and compile to family solids bound
// to the same planes (FurnitureCompiler+Parts).

/// What a part is: its role in the piece, Mark prefix and the tool that makes it.
public enum FurniturePartKind: String, Codable, Sendable, CaseIterable {
    case panel = "Panel", back = "Back", divider = "Divider", plinth = "Plinth"
    case shelf = "Shelf", top = "Top", bottom = "Bottom"
    case leg = "Leg", rail = "Rail", slats = "Slats"
    case edgeProfile = "Edge Profile", groove = "Groove", form = "Form"

    /// Mark prefix: P1, P2… per kind, as Revit numbers Marks per category.
    public var markPrefix: String {
        switch self {
        case .panel: "P"
        case .back: "BK"
        case .divider: "DV"
        case .plinth: "KK"
        case .shelf: "S"
        case .top: "T"
        case .bottom: "BT"
        case .leg: "L"
        case .rail: "R"
        case .slats: "SL"
        case .edgeProfile: "EP"
        case .groove: "G"
        case .form: "F"
        }
    }
}

/// Where a panel's location line lies across its thickness (as a wall's Location Line).
public enum PanelLocationLine: String, Codable, Sendable, CaseIterable {
    case centerline = "Panel Centerline", faceInside = "Face: Inside", faceOutside = "Face: Outside"
}

/// The grain of a sheet or board part.
public enum GrainDirection: String, Codable, Sendable, CaseIterable {
    case length = "Along Length", width = "Along Width", none = "None"
}

/// Edge banding per edge: L1/L2 run along the part's length, W1/W2 along its width (cut-list notation).
public struct EdgeBanding: Hashable, Codable, Sendable {
    public var l1: Bool, l2: Bool, w1: Bool, w2: Bool
    public init(l1: Bool = false, l2: Bool = false, w1: Bool = false, w2: Bool = false) { self.l1 = l1; self.l2 = l2; self.w1 = w1; self.w2 = w2 }
    public static let none = EdgeBanding()
    /// "L1 L2 W1" (or "None").
    public var code: String {
        let s = [(l1, "L1"), (l2, "L2"), (w1, "W1"), (w2, "W2")].filter(\.0).map(\.1)
        return s.isEmpty ? "None" : s.joined(separator: " ")
    }
    /// Parses "L1 L2", "L1,W2", "none"…
    public init(code: String) {
        let t = code.uppercased()
        self.init(l1: t.contains("L1"), l2: t.contains("L2"), w1: t.contains("W1"), w2: t.contains("W2"))
    }
}

/// A rectangular cut-out in a panel, in the panel's face coordinates (s along the location line from its start, t from
/// its base), as Wall ▸ Opening.
public struct PanelOpening: Hashable, Codable, Sendable {
    public var s0: Double, s1: Double, t0: Double, t1: Double
    public init(s0: Double, s1: Double, t0: Double, t1: Double) {
        self.s0 = Swift.min(s0, s1); self.s1 = Swift.max(s0, s1); self.t0 = Swift.min(t0, t1); self.t1 = Swift.max(t0, t1)
    }
}

/// How a back fits the carcass (the joint itself is made by FM6 joints; this stores the intent).
public struct BackIntent: Hashable, Codable, Sendable {
    public enum Fit: String, Codable, Sendable, CaseIterable { case inside = "Inside", fullOverlay = "Full Overlay" }
    public enum Joint: String, Codable, Sendable, CaseIterable { case butt = "Butt", inset = "Inset", rabbet = "Rabbet", dado = "Dado" }
    public var fit: Fit
    public var joint: Joint
    /// The panels the back was fitted to.
    public var carcass: [ElementID]
    public init(fit: Fit, joint: Joint = .butt, carcass: [ElementID] = []) { self.fit = fit; self.joint = joint; self.carcass = carcass }
}

/// Equal spacing of dividers (EQ): this divider's centre is `index`/`count` of the way from `low` to `high`.
public struct EqualSpacing: Hashable, Codable, Sendable {
    public var low: FurnitureBound
    public var high: FurnitureBound
    public var index: Int
    public var count: Int
    public init(low: FurnitureBound, high: FurnitureBound, index: Int, count: Int) { self.low = low; self.high = high; self.index = index; self.count = count }
}

/// A sheet part: side, divider, back, apron or plinth. Drawn like a wall: a location line on a sketch plane and a
/// thickness from the type, running from `base` to `top` across the plane.
///
/// - `.xy` (drawn in plan): the line is in plan (x, y); the panel stands from z = `base` to z = `top`.
/// - `.xz` (drawn in a Front/Back elevation): the line is in (x, z); the panel runs from y = `base` to y = `top`.
/// - `.yz` (drawn in a Left/Right elevation): the line is in (y, z); the panel runs from x = `base` to x = `top`.
public struct PanelData: Hashable, Codable, Sendable {
    public var role: FurniturePartKind
    public var plane: FamilySketchPlane
    public var start: Vec2
    public var end: Vec2
    public var locationLine: PanelLocationLine
    /// The outside face is on the left of the drawing direction (in sketch coordinates) unless flipped.
    public var flipped: Bool
    public var base: Double
    public var top: Double
    /// Edit Profile: the panel's outline in face coordinates (s along the line from its start, t from its base).
    public var profile: [Vec2]?
    public var openings: [PanelOpening]?
    /// Attach Top/Base: the shelf or top whose underside (top) or top face (base) the panel runs to.
    public var attachedTopID: ElementID?
    public var attachedBaseID: ElementID?
    /// Edge banding of this panel (nil = the type's default).
    public var banding: EdgeBanding?
    public var back: BackIntent?
    public var eq: EqualSpacing?
    /// Plane bindings by coordinate: "start.u", "start.v", "end.u", "end.v", "base", "top".
    public var bounds: [String: FurnitureBound]

    public init(role: FurniturePartKind = .panel, plane: FamilySketchPlane = .xy, start: Vec2, end: Vec2, locationLine: PanelLocationLine = .faceOutside,
                flipped: Bool = false, base: Double, top: Double, bounds: [String: FurnitureBound] = [:]) {
        self.role = role; self.plane = plane; self.start = start; self.end = end; self.locationLine = locationLine; self.flipped = flipped
        self.base = base; self.top = top; self.bounds = bounds
    }

    public var length: Double { start.distance(to: end) }
    public var height: Double { top - base }
}

/// Shelf pins of an adjustable shelf: rows of holes in the side panels (drilled by FM6; data only here).
public struct ShelfPins: Hashable, Codable, Sendable {
    /// Hole spacing (32 mm system by default).
    public var spacing: Double
    /// Holes above and below the shelf's position.
    public var above: Int
    public var below: Int
    /// Rows from the front and back edges of the sides.
    public var inset: Double
    public var diameter: Double
    public init(spacing: Double = 0.032, above: Int = 4, below: Int = 4, inset: Double = 0.0375, diameter: Double = 0.005) {
        self.spacing = spacing; self.above = above; self.below = below; self.inset = inset; self.diameter = diameter
    }
}

/// A horizontal board: shelf, top or bottom. Sketched like a floor (boundary lines or Pick Panels); `elevation` is its
/// top face, the type's thickness hangs below it.
public struct ShelfData: Hashable, Codable, Sendable {
    public var role: FurniturePartKind
    /// Counterclockwise plan loop.
    public var boundary: [Vec2]
    public var elevation: Double
    public var adjustable: Bool
    public var pins: ShelfPins?
    /// How far the front edge is set back from where it was sketched (applied to the boundary when sketched).
    public var frontSetback: Double
    /// Grain / span direction in plan (radians); nil = along the longest edge.
    public var spanAngle: Double?
    /// Plane bindings: "p<i>.x", "p<i>.y" per boundary point and "z" for the elevation.
    public var bounds: [String: FurnitureBound]

    public init(role: FurniturePartKind = .shelf, boundary: [Vec2], elevation: Double, adjustable: Bool = false, frontSetback: Double = 0,
                bounds: [String: FurnitureBound] = [:]) {
        self.role = role; self.boundary = boundary; self.elevation = elevation; self.adjustable = adjustable; self.frontSetback = frontSetback
        self.bounds = bounds
    }
}

/// A leg, placed like a column at a point, from `base` to `top`.
public struct LegData: Hashable, Codable, Sendable {
    public var location: Vec2
    public var base: Double
    public var top: Double
    public var rotation: Double
    /// The top (or shelf) the leg runs up to (At Corners).
    public var attachedTopID: ElementID?
    /// Plane bindings: "x", "y", "base", "top".
    public var bounds: [String: FurnitureBound]
    public init(location: Vec2, base: Double, top: Double, rotation: Double = 0, bounds: [String: FurnitureBound] = [:]) {
        self.location = location; self.base = base; self.top = top; self.rotation = rotation; self.bounds = bounds
    }
    public var height: Double { top - base }
}

/// Where a rail's cross-section sits on its line (as a beam's Z Justification).
public enum RailJustification: String, Codable, Sendable, CaseIterable { case top = "Top", center = "Center", bottom = "Bottom" }

/// Slats: rails repeated across a width at a spacing, as a beam system lays out its beams.
public struct SlatLayout: Hashable, Codable, Sendable {
    public enum Rule: String, Codable, Sendable, CaseIterable { case fixedDistance = "Fixed Distance", fixedNumber = "Fixed Number" }
    public var rule: Rule
    /// Centre-to-centre spacing (Fixed Distance).
    public var spacing: Double
    /// Number of slats (Fixed Number).
    public var number: Int
    /// The distance from the first slat's centre to the last's, across the line (to its left in sketch coordinates).
    public var extent: Double
    public init(rule: Rule = .fixedDistance, spacing: Double = 0.1, number: Int = 5, extent: Double) {
        self.rule = rule; self.spacing = spacing; self.number = number; self.extent = extent
    }

    /// The slats' offsets from the first one, across the line.
    public var offsets: [Double] {
        let e = max(0, extent)
        switch rule {
        case .fixedNumber:
            let n = max(1, number)
            return n == 1 ? [e / 2] : (0..<n).map { e * Double($0) / Double(n - 1) }
        case .fixedDistance:
            guard spacing > 1e-6 else { return [0] }
            let n = Int((e / spacing + 1e-9).rounded(.down)) + 1
            // Centred in the extent, as a beam system's Justification: Center.
            let used = spacing * Double(n - 1)
            let start = (e - used) / 2
            return (0..<n).map { start + spacing * Double($0) }
        }
    }
}

/// A rail: stretcher, apron, cleat or slat, drawn like a beam between two points.
///
/// Drawn in plan (`.xy`): the line is in plan and `w` is the elevation its Z Justification refers to. Drawn in an
/// elevation (`.xz`, `.yz`): the line is in that plane and `w` is the rail's centre across it.
public struct RailData: Hashable, Codable, Sendable {
    public var plane: FamilySketchPlane
    public var start: Vec2
    public var end: Vec2
    public var w: Double
    public var justification: RailJustification
    public var startExtension: Double
    public var endExtension: Double
    public var slats: SlatLayout?
    /// Plane bindings: "start.u", "start.v", "end.u", "end.v", "w", and "far" (the last slat's line, across).
    public var bounds: [String: FurnitureBound]
    public init(plane: FamilySketchPlane = .xy, start: Vec2, end: Vec2, w: Double, justification: RailJustification = .top,
                bounds: [String: FurnitureBound] = [:]) {
        self.plane = plane; self.start = start; self.end = end; self.w = w; self.justification = justification
        startExtension = 0; endExtension = 0; self.bounds = bounds
    }
    public var length: Double { start.distance(to: end) + startExtension + endExtension }
}

/// One edge of a box-shaped part: the edge runs along `axis`, at the min or max side of each of the other two axes
/// (in x, y, z order).
public struct PartEdge: Hashable, Codable, Sendable {
    public var axis: FamilyAxis
    public var firstAtMax: Bool
    public var secondAtMax: Bool
    public init(axis: FamilyAxis, firstAtMax: Bool, secondAtMax: Bool) { self.axis = axis; self.firstAtMax = firstAtMax; self.secondAtMax = secondAtMax }

    /// The two axes across the edge, in x, y, z order.
    public var across: (FamilyAxis, FamilyAxis) {
        switch axis {
        case .x: (.y, .z)
        case .y: (.x, .z)
        case .z: (.x, .y)
        }
    }
}

/// The profile cut along a part edge (as a wall sweep or reveal).
public enum EdgeProfileShape: String, Codable, Sendable, CaseIterable {
    case roundOver = "Round-Over", chamfer = "Chamfer", bullnose = "Bullnose", ogee = "Ogee", cove = "Cove", fingerPull = "Finger Pull", groove = "Groove"
}

/// An edge profile or groove on a part's edge. The host is the element's `hostID`.
public struct EdgeProfileData: Hashable, Codable, Sendable {
    public var edge: PartEdge
    /// Grooves: distance from the edge across the face they're cut in.
    public var offset: Double
    /// Grooves: cut into the face across the first (false) or the second (true) of the edge's cross axes.
    public var inSecondFace: Bool
    /// Setbacks from the ends of the edge.
    public var startSetback: Double
    public var endSetback: Double
    /// Made with the Groove tool (a reveal) rather than Edge Profile (a sweep).
    public var isGroove: Bool
    public init(edge: PartEdge, offset: Double = 0, inSecondFace: Bool = false, isGroove: Bool = false) {
        self.edge = edge; self.offset = offset; self.inSecondFace = inSecondFace; startSetback = 0; endSetback = 0; self.isGroove = isGroove
    }
}

/// Free forms in Furniture documents: Extrusion, Blend, Revolve, Sweep, Swept Blend (solid or void) and Cushion.
public enum FurnitureFormKind: String, Codable, Sendable, CaseIterable {
    case extrusion = "Extrusion", blend = "Blend", revolve = "Revolve", sweep = "Sweep", sweptBlend = "Swept Blend", cushion = "Cushion"
}

/// A cushion: a box with a crowned top, rounded corners and optional piping round the top and bottom edges.
public struct CushionSpec: Hashable, Codable, Sendable {
    public var center: Vec2
    public var width: Double
    public var depth: Double
    public var height: Double
    /// How much higher the middle of the top is than its edges.
    public var crown: Double
    public var cornerRadius: Double
    public var topPiping: Bool
    public var bottomPiping: Bool
    public var pipingDiameter: Double
    public var rotation: Double
    public init(center: Vec2, width: Double, depth: Double, height: Double, crown: Double = 0.0127, cornerRadius: Double = 0.0254,
                topPiping: Bool = true, bottomPiping: Bool = true, pipingDiameter: Double = 0.00635, rotation: Double = 0) {
        self.center = center; self.width = width; self.depth = depth; self.height = height; self.crown = crown; self.cornerRadius = cornerRadius
        self.topPiping = topPiping; self.bottomPiping = bottomPiping; self.pipingDiameter = pipingDiameter; self.rotation = rotation
    }
}

/// A form in a Furniture document, kept in its sketch's numbers and compiled to a `FamilySolid` (FurnitureForms).
///
/// - Extrusion: `profile` loops on `plane`, from `w0` to `w1` along its normal.
/// - Blend: `profile` (bottom loop, at z `w0`) to `topProfile` (at z `w1`), in plan.
/// - Revolve: `profile` in (distance from the axis, height above `w0`), about the vertical axis at `axis`.
/// - Sweep: `profile` (x left of the path, y up) along the plan `path` at z `w0`; Swept Blend adds `endProfile`.
/// - Cushion: `cushion`, standing on z `w0`.
public struct FurnitureFormData: Hashable, Codable, Sendable {
    public var kind: FurnitureFormKind
    public var isVoid: Bool
    public var plane: FamilySketchPlane
    public var profile: [Vec2]
    public var holes: [[Vec2]]
    public var topProfile: [Vec2]?
    public var endProfile: [Vec2]?
    public var path: [Vec2]?
    public var axis: Vec2?
    public var startAngle: Double
    public var endAngle: Double
    public var w0: Double
    public var w1: Double
    public var cushion: CushionSpec?
    public var materialID: ElementID?
    public var visibleAt: Set<DetailLevel>
    /// FM9: the planes the form follows (nil = it stays where it was drawn).
    public var lock: FormLock? = nil
    public init(kind: FurnitureFormKind, isVoid: Bool = false, plane: FamilySketchPlane = .xy, profile: [Vec2], w0: Double, w1: Double) {
        self.kind = kind; self.isVoid = isVoid; self.plane = plane; self.profile = profile; holes = []; topProfile = nil; endProfile = nil
        path = nil; axis = nil; startAngle = 0; endAngle = 2 * .pi; self.w0 = w0; self.w1 = w1; cushion = nil; materialID = nil
        visibleAt = [.coarse, .medium, .fine]
    }
}

// MARK: - Element accessors

extension Element {
    public var furniturePanel: PanelData? {
        get { if case .furniturePanel(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .furniturePanel(v) } }
    }
    public var furnitureShelf: ShelfData? {
        get { if case .furnitureShelf(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .furnitureShelf(v) } }
    }
    public var furnitureLeg: LegData? {
        get { if case .furnitureLeg(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .furnitureLeg(v) } }
    }
    public var furnitureRail: RailData? {
        get { if case .furnitureRail(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .furnitureRail(v) } }
    }
    public var furnitureEdgeProfile: EdgeProfileData? {
        get { if case .furnitureEdgeProfile(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .furnitureEdgeProfile(v) } }
    }
    public var furnitureForm: FurnitureFormData? {
        get { if case .furnitureForm(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .furnitureForm(v) } }
    }

    /// The part's kind (nil for elements that aren't furniture parts).
    public var furniturePartKind: FurniturePartKind? {
        switch data {
        case .furniturePanel(let p): p.role
        case .furnitureShelf(let s): s.role
        case .furnitureLeg: .leg
        case .furnitureRail(let r): r.slats == nil ? .rail : .slats
        case .furnitureEdgeProfile(let e): e.isGroove ? .groove : .edgeProfile
        case .furnitureForm: .form
        default: nil
        }
    }
}

extension Category {
    /// FM4: the furniture part categories, in Object Styles order.
    public static let furnitureParts: [Category] = [.furniturePanels, .furnitureShelves, .furnitureLegs, .furnitureRails, .furnitureEdgeProfiles, .furnitureForms]
    public var isFurniturePart: Bool { Category.furnitureParts.contains(self) }
}
