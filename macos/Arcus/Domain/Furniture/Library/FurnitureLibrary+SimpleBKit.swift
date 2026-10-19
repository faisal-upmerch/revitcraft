import Foundation
import ArcusGeometry

// FM9C: the helpers the simple library pieces of part B are built with (FurnitureLibrary+SimpleB*.swift). A piece is
// built step by step with the same part operations the tools call (Panel, Shelf, Top, Leg, Rail, Slats, Back, Divider,
// Plinth, Bay, Door, Drawer, Flap, Forms), each step committed as one transaction so regeneration binds the new parts
// to the planes and part faces they were drawn on. The last step locks every coordinate left free to its nearest
// reference plane (Align and lock), so the piece flexes as a whole. Coordinates here are in inches, measured from the
// piece's centre in plan (Left is -Width / 2, Front is -Depth / 2) and from Ref. Level up.

/// One size type of a piece, in inches (named "W x D x H" when no name is given).
struct SBSize: Sendable {
    var w: Double, d: Double, h: Double
    var name: String?
    init(_ w: Double, _ d: Double, _ h: Double, _ name: String? = nil) { self.w = w; self.d = d; self.h = h; self.name = name }
}

/// An extra reference plane of a piece: a name, its axis, its offset formula ("Height * 0.55") and where it is drawn at
/// the first size (inches; regeneration solves it from the formula). Without `at`, "Width/Depth/Height * k" is
/// evaluated for it.
struct SBPlane: Sendable {
    var name: String
    var axis: FamilyAxis
    var formula: String
    var at: Double?
    init(_ name: String, _ axis: FamilyAxis, _ formula: String, at: Double? = nil) { self.name = name; self.axis = axis; self.formula = formula; self.at = at }
}

/// Builds one piece: the blank template, its size types and extra planes, then the caller's steps.
final class SBBuilder {
    static let inch = 0.0254
    private(set) var model: BIMModel

    /// A new piece named `name` in `category`, with `sizes` (the first drives the planes) and `material` as the value
    /// of its Material parameter.
    init(_ name: String, _ category: FamilyTemplate, _ sizes: [SBSize], material: String, planes: [SBPlane] = []) throws {
        model = FurnitureTemplates.blank(category: category, name: name)
        try step("Size and Types") { b in
            SimpleBKit.ensureTypes(in: b.tx)
            try b.setTypes(sizes, material: material)
            for p in planes { b.addPlane(p, size: sizes[0]) }
        }
    }

    /// Runs `body` in one transaction and commits it.
    func step(_ name: String, _ body: (SBStep) throws -> Void) throws {
        let tx = TransactionContext(model: model, name: name)
        try body(SBStep(tx))
        model = try tx.commit().model
    }

    /// Locks the parts' free coordinates to their nearest planes and returns the piece.
    func finish() throws -> BIMModel {
        try step("Lock to Planes") { SimpleBKit.lockAll(in: $0.tx) }
        return model
    }
}

/// One step of a piece: the transaction and the part helpers (inches).
struct SBStep {
    static let inch = 0.0254
    let tx: TransactionContext
    init(_ tx: TransactionContext) { self.tx = tx }

    func m(_ v: Double) -> Double { v * Self.inch }
    func v2(_ x: Double, _ y: Double) -> Vec2 { Vec2(x * Self.inch, y * Self.inch) }

    // MARK: Planes and sizes

    /// A plane's position in inches (0 when it doesn't exist).
    func pos(_ plane: String) -> Double { (FurniturePlanes.positionsByName(tx.model)[plane] ?? 0) / Self.inch }
    var l: Double { pos("Left") }
    var r: Double { pos("Right") }
    var f: Double { pos("Front") }
    var b: Double { pos("Back") }
    var h: Double { pos("Top") }
    var w: Double { r - l }
    var d: Double { b - f }

    func setTypes(_ sizes: [SBSize], material: String) throws {
        let mat = tx.model.elements(.materials).first { $0.name == material }?.id
        guard mat != nil else { throw TransactionError("No material named \(material).") }
        try FurnitureParameters.edit(tx) { s in
            s.family.types = sizes.map { z in
                FamilyTypeDefinition(name: z.name ?? FurnitureTemplates.typeName(z.w * Self.inch, z.d * Self.inch, z.h * Self.inch),
                                     values: ["Width": .double(z.w * Self.inch), "Depth": .double(z.d * Self.inch), "Height": .double(z.h * Self.inch),
                                              "Material": .ref(mat)])
            }
            s.currentType = s.family.types[0].name
        }
    }

    func addPlane(_ p: SBPlane, size z: SBSize) {
        let values = ["Width": z.w, "Depth": z.d, "Height": z.h]
        // The drawn position: the formula of Width/Depth/Height evaluated at the first size (regeneration re-solves it).
        var at = p.at ?? 0
        let parts = p.formula.split(separator: "*").map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-"))) }
        if p.at == nil, parts.count == 2, let v = values[parts[0]], let k = Double(parts[1]) { at = (p.formula.hasPrefix("-") ? -1 : 1) * v * k }
        let rp = FurniturePlanes.make(axis: p.axis, formula: p.formula, strength: .weak, origin: false, at: at * Self.inch, extents: FurniturePlanes.extents(tx.model))
        tx.create(.referencePlanes, name: p.name, data: .referencePlane(rp))
    }

    // MARK: Types

    func type(_ cat: Category, _ name: String) throws -> ElementID {
        guard let t = tx.model.types(for: cat).first(where: { $0.name == name && $0.typeData?.instanceCategory == cat }) else {
            throw TransactionError("No \(cat.singularName) type named \(name).")
        }
        return t.id
    }

    func frontType(_ kind: FrontKind, _ name: String) throws -> ElementID {
        guard let t = tx.model.types(for: .furnitureFronts).first(where: { $0.name == name && $0.typeData?.familyName == kind.rawValue }) else {
            throw TransactionError("No \(kind.rawValue) type named \(name).")
        }
        return t.id
    }

    func material(_ name: String) throws -> ElementID {
        guard let id = tx.model.elements(.materials).first(where: { $0.name == name })?.id else { throw TransactionError("No material named \(name).") }
        return id
    }

    // MARK: Panels

    /// A panel thin along x: its outside face at `x`, its thickness toward +x (`inward` > 0) or -x, running from y0 to y1
    /// and z0 to z1.
    @discardableResult
    func panelX(_ x: Double, inward: Double, y: (Double, Double), z: (Double, Double), _ type: String = "3/4\" Plywood",
                role: FurniturePartKind = .panel) throws -> ElementID {
        let (y0, y1) = (min(y.0, y.1), max(y.0, y.1))
        let s = inward > 0 ? v2(x, y0) : v2(x, y1), e = inward > 0 ? v2(x, y1) : v2(x, y0)
        return try FurniturePartOperations.createPanel(start: s, end: e, extent: extent(z), role: role, typeID: try self.type(.furniturePanels, type), in: tx)
    }

    /// A panel thin along y: its outside face at `y`, its thickness toward +y (`inward` > 0, a front) or -y (a back).
    @discardableResult
    func panelY(_ y: Double, inward: Double, x: (Double, Double), z: (Double, Double), _ type: String = "3/4\" Plywood",
                role: FurniturePartKind = .panel) throws -> ElementID {
        let (x0, x1) = (min(x.0, x.1), max(x.0, x.1))
        let s = inward > 0 ? v2(x1, y) : v2(x0, y), e = inward > 0 ? v2(x0, y) : v2(x1, y)
        return try FurniturePartOperations.createPanel(start: s, end: e, extent: extent(z), role: role, typeID: try self.type(.furniturePanels, type), in: tx)
    }

    /// A panel along a plan line at an angle (its outside face on the line's left), from z0 to z1.
    @discardableResult
    func panelLine(_ a: (Double, Double), _ c: (Double, Double), z: (Double, Double), _ type: String) throws -> ElementID {
        try FurniturePartOperations.createPanel(start: v2(a.0, a.1), end: v2(c.0, c.1), locationLine: .centerline, extent: extent(z),
                                                typeID: try self.type(.furniturePanels, type), in: tx)
    }

    func extent(_ z: (Double, Double)) -> PartExtent {
        PartExtent(basePlane: nil, baseOffset: m(min(z.0, z.1)), topPlane: nil, height: m(abs(z.1 - z.0)))
    }

    // MARK: Boards

    /// A shelf, top or bottom over a plan rectangle, its top face at `top`.
    @discardableResult
    func board(x: (Double, Double), y: (Double, Double), top: Double, _ type: String = "3/4\" Plywood Shelf", role: FurniturePartKind = .shelf,
               adjustable: Bool = false) throws -> ElementID {
        let (x0, x1) = (min(x.0, x.1), max(x.0, x.1)), (y0, y1) = (min(y.0, y.1), max(y.0, y.1))
        let cat: Category = .furnitureShelves
        return try FurniturePartOperations.createShelf(boundary: [v2(x0, y0), v2(x1, y0), v2(x1, y1), v2(x0, y1)], plane: nil, offset: m(top), role: role,
                                                       adjustable: adjustable, typeID: try self.type(cat, type), in: tx)
    }

    /// A shelf over any plan loop.
    @discardableResult
    func board(loop: [(Double, Double)], top: Double, _ type: String, role: FurniturePartKind = .shelf) throws -> ElementID {
        try FurniturePartOperations.createShelf(boundary: loop.map { v2($0.0, $0.1) }, plane: nil, offset: m(top), role: role,
                                                typeID: try self.type(.furnitureShelves, type), in: tx)
    }

    // MARK: Legs and rails

    @discardableResult
    func leg(_ x: Double, _ y: Double, z: (Double, Double), _ type: String = "Square 1 1/2\"", rotation: Double = 0) throws -> ElementID {
        try FurniturePartOperations.createLeg(at: v2(x, y), extent: extent(z), rotation: rotation, typeID: try self.type(.furnitureLegs, type), in: tx)
    }

    /// A rail drawn in plan from `a` to `c`, its top (or centre, or bottom) at `z`.
    @discardableResult
    func rail(_ a: (Double, Double), _ c: (Double, Double), z: Double, _ type: String = "3/4\" x 3\" Apron", just: RailJustification = .top) throws -> ElementID {
        try FurniturePartOperations.createRail(start: v2(a.0, a.1), end: v2(c.0, c.1), w: m(z), justification: just,
                                               typeID: try self.type(.furnitureRails, type), in: tx)
    }

    /// A rail drawn in a front elevation from (x, z) `a` to `c`, its centre at depth `y`.
    @discardableResult
    func railXZ(_ a: (Double, Double), _ c: (Double, Double), y: Double, _ type: String) throws -> ElementID {
        try FurniturePartOperations.createRail(start: v2(a.0, a.1), end: v2(c.0, c.1), plane: .xz, w: m(y), justification: .center,
                                               typeID: try self.type(.furnitureRails, type), in: tx)
    }

    /// A rail drawn in a side elevation from (y, z) `a` to `c`, its centre at `x`.
    @discardableResult
    func railYZ(_ a: (Double, Double), _ c: (Double, Double), x: Double, _ type: String) throws -> ElementID {
        try FurniturePartOperations.createRail(start: v2(a.0, a.1), end: v2(c.0, c.1), plane: .yz, w: m(x), justification: .center,
                                               typeID: try self.type(.furnitureRails, type), in: tx)
    }

    /// A vertical rail (a spindle, bar or post) at plan point (x, y) from z0 to z1.
    @discardableResult
    func spindle(_ x: Double, _ y: Double, z: (Double, Double), _ type: String) throws -> ElementID {
        try railXZ((x, z.0), (x, z.1), y: y, type)
    }

    /// Slats over a plan rectangle, along x or across it, their tops at `top`: one rail per slat (each locked to its
    /// nearest plane, so they stay inside the piece as it flexes), `count` of them or as many as fit at `spacing`.
    @discardableResult
    func slats(x: (Double, Double), y: (Double, Double), alongX: Bool, spacing: Double? = nil, count: Int? = nil, top: Double,
               _ type: String = "3/4\" x 2 1/2\" Slat") throws -> [ElementID] {
        let (x0, x1) = (min(x.0, x.1), max(x.0, x.1)), (y0, y1) = (min(y.0, y.1), max(y.0, y.1))
        let sw = try thickness(.furnitureRails, type)
        let lo = (alongX ? y0 : x0) + sw / 2, hi = (alongX ? y1 : x1) - sw / 2
        let n = max(1, count ?? (Int(((hi - lo) / (spacing ?? 4) + 1e-9).rounded(.down)) + 1))
        var ids: [ElementID] = []
        for k in 0..<n {
            let c = n == 1 ? (lo + hi) / 2 : lo + (hi - lo) * Double(k) / Double(n - 1)
            ids.append(alongX ? try rail((x0, c), (x1, c), z: top, type) : try rail((c, y1), (c, y0), z: top, type))
        }
        return ids
    }

    // MARK: Carcass pieces picked from committed parts

    /// A back inside the carcass round front-view point (x, z).
    @discardableResult
    func back(x: Double, z: Double, _ type: String = "1/4\" Back Panel (Hardboard)") throws -> ElementID {
        try FurniturePartOperations.createBack(atFront: v2(x, z), fit: .inside, typeID: try self.type(.furniturePanels, type), in: tx)
    }

    /// `count` EQ dividers in the opening round front-view point (x, z).
    @discardableResult
    func dividers(x: Double, z: Double, count: Int, vertical: Bool = true, _ type: String = "3/4\" Plywood") throws -> [ElementID] {
        try FurniturePartOperations.createDividers(atFront: v2(x, z), vertical: vertical, count: count, typeID: try self.type(.furniturePanels, type), in: tx)
    }

    /// A toe kick under a bottom, set back from its front.
    @discardableResult
    func plinth(under id: ElementID, setback: Double = 3, _ type: String = "3/4\" Plywood") throws -> ElementID {
        try FurniturePartOperations.createPlinth(under: id, setback: m(setback), typeID: try self.type(.furniturePanels, type), in: tx)
    }

    // MARK: Bays and fronts

    @discardableResult
    func bay(x: Double, z: Double) throws -> ElementID { try FurnitureBays.createBay(face: .front, at: v2(x, z), in: tx) }

    @discardableResult
    func door(x: Double, z: Double, _ type: String = "Slab - Full Overlay", hingeRight: Bool = false) throws -> [ElementID] {
        try FurnitureFronts.createFront(.door, in: try bay(x: x, z: z), typeID: try frontType(.door, type), hingeFlipped: hingeRight, in: tx)
    }

    @discardableResult
    func drawers(x: Double, z: Double, count: Int, _ type: String = "Slab - Full Overlay") throws -> [ElementID] {
        try FurnitureFronts.createDrawers(in: try bay(x: x, z: z), count: count, typeID: try frontType(.drawer, type), in: tx)
    }

    @discardableResult
    func flap(x: Double, z: Double, _ type: String = "Slab - Full Overlay Drop-Down") throws -> [ElementID] {
        try FurnitureFronts.createFront(.flap, in: try bay(x: x, z: z), typeID: try frontType(.flap, type), in: tx)
    }

    /// A lid on the open top of a box round plan point (x, y).
    @discardableResult
    func lid(x: Double, y: Double, _ type: String = "Slab - Full Overlay Lift-Up") throws -> [ElementID] {
        let bay = try FurnitureBays.createBay(face: .top, at: v2(x, y), in: tx)
        return try FurnitureFronts.createFront(.flap, in: bay, typeID: try frontType(.flap, type), in: tx)
    }

    // MARK: Forms

    /// A form in `material`, shown at `detail` levels.
    @discardableResult
    func form(_ f: FurnitureFormData, _ material: String, detail: Set<DetailLevel> = [.coarse, .medium, .fine]) throws -> ElementID {
        var g = f
        g.materialID = try self.material(material)
        g.visibleAt = detail
        return try FurniturePartOperations.createForm(g, in: tx)
    }

    /// An extrusion of a loop (inches) on `plane`, from w0 to w1 along its normal.
    @discardableResult
    func extrusion(_ pts: [(Double, Double)], plane: FamilySketchPlane = .xy, w: (Double, Double), _ material: String) throws -> ElementID {
        try form(FurnitureFormData(kind: .extrusion, plane: plane, profile: pts.map { v2($0.0, $0.1) }, w0: m(w.0), w1: m(w.1)), material)
    }

    /// A revolve of `profile` (distance from the axis, height above z0; inches) about the vertical axis at (x, y).
    @discardableResult
    func revolve(_ profile: [(Double, Double)], at c: (Double, Double) = (0, 0), z0: Double, _ material: String) throws -> ElementID {
        var f = FurnitureFormData(kind: .revolve, profile: profile.map { v2($0.0, $0.1) }, w0: m(z0), w1: m(z0))
        f.axis = v2(c.0, c.1)
        return try form(f, material)
    }

    /// A sweep of `profile` (x left of the path, y up; inches) along a plan `path` at z.
    @discardableResult
    func sweep(_ path: [(Double, Double)], profile: [(Double, Double)], z: Double, _ material: String) throws -> ElementID {
        var f = FurnitureFormData(kind: .sweep, profile: profile.map { v2($0.0, $0.1) }, w0: m(z), w1: m(z))
        f.path = path.map { v2($0.0, $0.1) }
        return try form(f, material)
    }

    /// A cushion standing on z0 (inches).
    @discardableResult
    func cushion(x: Double, y: Double, w: Double, d: Double, h: Double, z0: Double, _ material: String = "Fabric", crown: Double = 0.5,
                 radius: Double = 1.5, piping: Bool = true) throws -> ElementID {
        var f = FurnitureFormData(kind: .cushion, profile: [], w0: m(z0), w1: m(z0 + h))
        f.cushion = CushionSpec(center: v2(x, y), width: m(w), depth: m(d), height: m(h), crown: m(crown), cornerRadius: m(radius),
                                topPiping: piping, bottomPiping: piping)
        return try form(f, material)
    }

    /// A circle (inches) as a loop.
    func circle(_ c: (Double, Double), _ radius: Double, _ n: Int = 24) -> [(Double, Double)] {
        (0..<n).map { k in let a = 2 * Double.pi * Double(k) / Double(n); return (c.0 + radius * cos(a), c.1 + radius * sin(a)) }
    }
}

// MARK: - Types and locking

enum SimpleBKit {
    static let inch = 0.0254

    /// Materials the part B pieces use that the template doesn't have (outdoor woods, aluminium, outdoor fabric…).
    static let materials: [FurnitureTemplates.MaterialSpec] = [
        .init(name: "Solid Teak", materialClass: .wood, color: 0xA27443, transparency: 0, cost: 24, unit: .boardFoot, description: "Plantation teak, kiln dried"),
        .init(name: "Western Red Cedar", materialClass: .wood, color: 0xB7744A, transparency: 0, cost: 6, unit: .boardFoot, description: "Western red cedar, clear"),
        .init(name: "Aluminum", materialClass: .metal, color: 0xBFC4C9, transparency: 0, cost: 5, unit: .linearFoot, description: "Powder-coated aluminum tube"),
        .init(name: "Outdoor Fabric", materialClass: .generic, color: 0xD8D0BF, transparency: 0, cost: 22, unit: .linearFoot, description: "Solution-dyed acrylic, 54\" wide"),
        .init(name: "Mattress", materialClass: .generic, color: 0xF0EDE6, transparency: 0, cost: 4, unit: .squareFoot, description: "Foam mattress with cover"),
        .init(name: "Cotton Rope", materialClass: .generic, color: 0xE6DAC0, transparency: 0, cost: 0.6, unit: .linearFoot, description: "Cotton rope, 1/2\""),
        .init(name: "Canvas", materialClass: .generic, color: 0xE2D7BF, transparency: 0, cost: 12, unit: .linearFoot, description: "Cotton canvas, 60\" wide"),
        .init(name: "Rattan", materialClass: .wood, color: 0xC79C62, transparency: 0, cost: 4, unit: .linearFoot, description: "Natural rattan cane"),
    ]

    typealias Spec = FurniturePartTypes.Spec
    static func sheet(_ cat: Category, _ family: String, _ name: String, t: Double, core: String, grain: GrainDirection = .length) -> Spec {
        FurniturePartTypes.sheet(cat, family, name, t: t, core: core, edge: nil, grain: grain)
    }
    static func leg(_ name: String, _ shape: LegShape, w: Double, d: Double? = nil, taper: Double = 0, material: String) -> Spec {
        FurniturePartTypes.leg(name, shape, w: w, d: d, taper: taper, material: material)
    }
    static func rail(_ name: String, w: Double, h: Double, round: Bool = false, material: String) -> Spec {
        FurniturePartTypes.rail(name, w: w, h: h, profile: round ? .round : .rectangle, material: material)
    }

    /// The part types the part B pieces use beyond the standard ones (Revit-style names: size then material).
    static let types: [Spec] = [
        sheet(.furniturePanels, "Panel", "3/4\" Teak", t: 0.75, core: "Solid Teak"),
        sheet(.furniturePanels, "Panel", "3/4\" Cedar", t: 0.75, core: "Western Red Cedar"),
        sheet(.furniturePanels, "Panel", "3/4\" Solid Pine", t: 0.75, core: "Solid Pine"),
        sheet(.furniturePanels, "Panel", "3/4\" Solid Maple", t: 0.75, core: "Solid Maple"),
        sheet(.furniturePanels, "Panel", "1\" Solid Oak", t: 1, core: "Solid Oak"),
        sheet(.furniturePanels, "Panel", "1/4\" Aluminum", t: 0.25, core: "Aluminum", grain: .none),
        sheet(.furniturePanels, "Panel", "4\" Upholstered Panel", t: 4, core: "Fabric", grain: .none),
        sheet(.furniturePanels, "Panel", "6\" Upholstered Panel", t: 6, core: "Fabric", grain: .none),
        sheet(.furniturePanels, "Panel", "4\" Outdoor Cushion Panel", t: 4, core: "Outdoor Fabric", grain: .none),
        sheet(.furniturePanels, "Panel", "1/8\" Canvas Panel", t: 0.125, core: "Canvas", grain: .none),
        sheet(.furnitureShelves, "Shelf", "3/4\" Teak Shelf", t: 0.75, core: "Solid Teak"),
        sheet(.furnitureShelves, "Shelf", "3/4\" Cedar Shelf", t: 0.75, core: "Western Red Cedar"),
        sheet(.furnitureShelves, "Shelf", "3/4\" Solid Pine Shelf", t: 0.75, core: "Solid Pine"),
        sheet(.furnitureShelves, "Shelf", "3\" Seat Cushion", t: 3, core: "Fabric", grain: .none),
        sheet(.furnitureShelves, "Shelf", "5\" Seat Cushion", t: 5, core: "Fabric", grain: .none),
        sheet(.furnitureShelves, "Shelf", "4\" Outdoor Seat Cushion", t: 4, core: "Outdoor Fabric", grain: .none),
        sheet(.furnitureShelves, "Shelf", "2\" Outdoor Pad", t: 2, core: "Outdoor Fabric", grain: .none),
        sheet(.furnitureShelves, "Shelf", "2\" Leather Pad", t: 2, core: "Leather", grain: .none),
        sheet(.furnitureShelves, "Shelf", "5\" Crib Mattress", t: 5, core: "Mattress", grain: .none),
        sheet(.furnitureShelves, "Shelf", "6\" Mattress", t: 6, core: "Mattress", grain: .none),
        sheet(.furnitureShelves, "Shelf", "8\" Mattress", t: 8, core: "Mattress", grain: .none),
        sheet(.furnitureShelves, "Top", "1\" Teak Top", t: 1, core: "Solid Teak"),
        sheet(.furnitureShelves, "Top", "1 1/2\" Cedar Top", t: 1.5, core: "Western Red Cedar"),
        sheet(.furnitureShelves, "Top", "1/4\" Aluminum Top", t: 0.25, core: "Aluminum", grain: .none),
        sheet(.furnitureShelves, "Top", "1/2\" Glass Top", t: 0.5, core: "Glass", grain: .none),
        sheet(.furnitureShelves, "Top", "3/4\" Solid Maple Top", t: 0.75, core: "Solid Maple"),
        sheet(.furnitureShelves, "Top", "1\" Marble Top", t: 1, core: "Marble", grain: .none),
        leg("Square 1 1/2\" Teak", .square, w: 1.5, material: "Solid Teak"),
        leg("Square 2\" Teak", .square, w: 2, material: "Solid Teak"),
        leg("Square 3 1/2\" Cedar Post", .square, w: 3.5, material: "Western Red Cedar"),
        leg("Square 1 1/2\" Cedar", .square, w: 1.5, material: "Western Red Cedar"),
        leg("Square 1\" Aluminum", .square, w: 1, material: "Aluminum"),
        leg("Round 1\" Aluminum", .round, w: 1, material: "Aluminum"),
        leg("Square 2\" Maple Post", .square, w: 2, material: "Solid Maple"),
        leg("Square 1 1/4\" Maple", .square, w: 1.25, material: "Solid Maple"),
        leg("Square 3\" Oak Post", .square, w: 3, material: "Solid Oak"),
        leg("Round 1 1/4\" Maple", .round, w: 1.25, material: "Solid Maple"),
        leg("Round 1 1/4\" Steel", .round, w: 1.25, material: "Steel"),
        leg("Turned 2\" Walnut", .turned, w: 2, material: "Solid Walnut"),
        leg("Square 1\" Steel", .square, w: 1, material: "Steel"),
        leg("Square 2\" Oak", .square, w: 2, material: "Solid Oak"),
        leg("Round Tapered 1 3/4\" Oak", .round, w: 1.75, taper: 1, material: "Solid Oak"),
        leg("Square 3/4\" Walnut", .square, w: 0.75, material: "Solid Walnut"),
        rail("1\" x 3\" Teak Slat", w: 3, h: 1, material: "Solid Teak"),
        rail("3/4\" x 2\" Teak Slat", w: 2, h: 0.75, material: "Solid Teak"),
        rail("1\" x 3\" Teak Rail", w: 1, h: 3, material: "Solid Teak"),
        rail("3/4\" x 3 1/2\" Cedar Slat", w: 3.5, h: 0.75, material: "Western Red Cedar"),
        rail("1 1/2\" x 5 1/2\" Cedar Plank", w: 5.5, h: 1.5, material: "Western Red Cedar"),
        rail("1 1/2\" x 3 1/2\" Cedar Rail", w: 1.5, h: 3.5, material: "Western Red Cedar"),
        rail("3 1/2\" x 1 1/2\" Cedar Rail", w: 3.5, h: 1.5, material: "Western Red Cedar"),
        rail("1\" x 2\" Aluminum Rail", w: 1, h: 2, material: "Aluminum"),
        rail("1\" Round Aluminum Tube", w: 1, h: 1, round: true, material: "Aluminum"),
        rail("3/4\" Round Steel Rod", w: 0.75, h: 0.75, round: true, material: "Steel"),
        rail("1/2\" Round Steel Rod", w: 0.5, h: 0.5, round: true, material: "Steel"),
        rail("1\" Round Steel Tube", w: 1, h: 1, round: true, material: "Steel"),
        rail("1 1/4\" Round Maple Dowel", w: 1.25, h: 1.25, round: true, material: "Solid Maple"),
        rail("3/4\" Round Maple Peg", w: 0.75, h: 0.75, round: true, material: "Solid Maple"),
        rail("1\" x 1\" Maple Spindle", w: 1, h: 1, material: "Solid Maple"),
        rail("3/4\" x 1 1/2\" Maple Rail", w: 0.75, h: 1.5, material: "Solid Maple"),
        rail("1 1/2\" x 1 1/2\" Maple Rail", w: 1.5, h: 1.5, material: "Solid Maple"),
        rail("3/4\" x 3\" Maple Rail", w: 0.75, h: 3, material: "Solid Maple"),
        rail("1/2\" Cotton Rope", w: 0.5, h: 0.5, round: true, material: "Cotton Rope"),
        rail("1\" Round Rattan", w: 1, h: 1, round: true, material: "Rattan"),
        rail("1 1/2\" Round Oak Rail", w: 1.5, h: 1.5, round: true, material: "Solid Oak"),
        rail("3/4\" x 1 1/2\" Pine Rail", w: 0.75, h: 1.5, material: "Solid Pine"),
        rail("1 1/2\" x 1 1/2\" Oak Rail", w: 1.5, h: 1.5, material: "Solid Oak"),
        rail("1 1/2\" x 3\" Oak Rail", w: 1.5, h: 3, material: "Solid Oak"),
        rail("3/4\" x 1 1/2\" Walnut Rail", w: 0.75, h: 1.5, material: "Solid Walnut"),
        rail("1 1/2\" x 1 1/2\" Steel Tube", w: 1.5, h: 1.5, material: "Steel"),
        rail("1\" x 1\" Steel Tube", w: 1, h: 1, material: "Steel"),
    ]

    /// A marble material for tops (not in the template's set).
    static let marble = FurnitureTemplates.MaterialSpec(name: "Marble", materialClass: .stone, color: 0xE9E6E1, transparency: 0, cost: 45, unit: .squareFoot,
                                                        description: "Carrara marble, 3/4\"")

    /// Creates the materials, part types and front types the part B pieces use (idempotent).
    static func ensureTypes(in tx: TransactionContext) {
        FurniturePartTypes.ensureStandard(in: tx)
        FurnitureFrontTypes.ensureStandard(in: tx)
        var mats: [String: ElementID] = [:]
        for m in tx.model.elements(.materials) { mats[m.name] = m.id }
        let patterns = MaterialPatternDefaults.patternIndex(tx.model)
        for spec in materials + [marble] where mats[spec.name] == nil {
            var m = MaterialData(materialClass: spec.materialClass, color: RGBColor(hex: spec.color), transparency: spec.transparency, description: spec.description)
            MaterialPatternDefaults.apply(to: &m, name: spec.name, patterns: patterns)
            m.cost = spec.cost
            m.costUnit = spec.unit
            mats[spec.name] = tx.create(.materials, name: spec.name, data: .material(m))
        }
        let existing = Set(tx.model.elements(.elementTypes).compactMap { t -> String? in
            guard let td = t.typeData, td.instanceCategory.isFurniturePart else { return nil }
            return "\(td.instanceCategory.rawValue)|\(td.familyName)|\(t.name)"
        })
        for spec in types where !existing.contains("\(spec.category.rawValue)|\(spec.family)|\(spec.name)") {
            var params: [ParameterID: ParamValue] = [:]
            for (k, v) in spec.numbers { params[k] = .double(v) }
            for (k, v) in spec.texts { params[k] = .text(v) }
            for (k, v) in spec.materials { params[k] = .ref(mats[v]) }
            tx.create(.elementTypes, name: spec.name, data: .type(TypeData(instanceCategory: spec.category, familyName: spec.family, params: params)))
        }
        // Front types in other materials: copies of the standard ones.
        let fronts: [(FrontKind, String, String, String)] = [
            (.flap, "Slab - Full Overlay Lift-Up", "Teak Slab - Lift-Up Lid", "Solid Teak"),
            (.flap, "Slab - Full Overlay Lift-Up", "Cedar Slab - Lift-Up Lid", "Western Red Cedar"),
            (.flap, "Slab - Full Overlay Lift-Up", "Upholstered - Lift-Up Lid", "Fabric"),
            (.door, "Slab - Full Overlay", "White Slab - Full Overlay", "Melamine"),
            (.door, "Slab - Full Overlay Pair", "White Slab - Full Overlay Pair", "Melamine"),
            (.drawer, "Slab - Full Overlay", "White Slab - Full Overlay", "Melamine"),
            (.door, "Slab - Full Overlay", "Teak Slab - Full Overlay", "Solid Teak"),
            (.door, "Glass Panel - Full Overlay", "Glass Panel - Full Overlay Pair", "Solid Oak"),
        ]
        let frontTypes = tx.model.types(for: .furnitureFronts)
        for (kind, base, name, core) in fronts where !frontTypes.contains(where: { $0.name == name && $0.typeData?.familyName == kind.rawValue }) {
            guard var td = frontTypes.first(where: { $0.name == base && $0.typeData?.familyName == kind.rawValue })?.typeData else { continue }
            td.params[FurniturePartTypes.coreMaterial] = .ref(mats[core])
            if name.hasSuffix("Pair") { td.params[FurnitureFrontTypes.leaves] = .text("Pair") }
            if core == "Fabric" { td.params[FurniturePartTypes.edgeMaterial] = .ref(nil); td.params[FurniturePartTypes.banding] = .text("None") }
            tx.create(.elementTypes, name: name, data: .type(td))
        }
    }

    /// Align and lock: every part coordinate that follows neither a plane nor a part face locks to a plane at its current
    /// offset (attached ends and EQ dividers keep following their shelf or spacing). A part's coordinates along one axis
    /// lock to their own nearest planes when the part is long enough to stretch between them (it can't turn inside out
    /// at half size), else all to one plane, so the part moves without changing size.
    static func lockAll(in tx: TransactionContext) {
        let resolver = FurnitureBoundResolver(tx.model)
        var planes: [FamilyAxis: [(name: String, position: Double)]] = [:]
        for a in FamilyAxis.allCases { planes[a] = FurniturePartCoordinates.planes(along: a, tx.model) }
        func nearest(_ a: FamilyAxis, _ v: Double) -> (name: String, position: Double)? {
            planes[a]?.min { abs($0.position - v) < abs($1.position - v) }
        }
        for cat in [Category.furniturePanels, .furnitureShelves, .furnitureLegs, .furnitureRails] {
            for e in tx.model.elements(cat) {
                var bounds = FurniturePartBounds.bounds(of: e)
                var skip: Set<String> = []
                if let p = e.furniturePanel {
                    if p.attachedTopID != nil { skip.insert("top") }
                    if p.attachedBaseID != nil { skip.insert("base") }
                    if p.eq != nil, let f = FurniturePartSolids.linearFrame(p.plane, p.start, p.end) {
                        skip.formUnion(f.lineAlongU ? ["start.v", "end.v"] : ["start.u", "end.u"])
                    }
                }
                if e.furnitureLeg?.attachedTopID != nil { skip.insert("top") }
                let coords = FurniturePartCoordinates.coordinates(of: e).filter { !skip.contains($0.key) }
                var changed = false
                for axis in FamilyAxis.allCases {
                    let group = coords.filter { $0.axis == axis }
                    let free = group.filter { bounds[$0.key] == nil }
                    guard !free.isEmpty else { continue }
                    var anchor: (name: String, position: Double)?
                    var used: [Double] = []
                    for c in group {
                        if case .plane(let n, _)? = bounds[c.key], let p = resolver.positions[n] { used.append(p); if anchor == nil { anchor = (n, p) } }
                        else if let n = nearest(axis, c.value) { used.append(n.position) }
                    }
                    let lo = group.map(\.value).min() ?? 0, hi = group.map(\.value).max() ?? 0
                    let spread = (used.max() ?? 0) - (used.min() ?? 0)
                    let rigid = spread > Tolerance.length && hi - lo <= spread / 2 + 0.5 * inch
                    for c in free {
                        guard let target = rigid ? (anchor ?? nearest(axis, (lo + hi) / 2)) : nearest(axis, c.value) else { continue }
                        bounds[c.key] = .plane(target.name, offset: c.value - target.position)
                        changed = true
                    }
                }
                guard changed else { continue }
                var el = e
                FurniturePartBounds.setBounds(bounds, of: &el)
                let data = el.data
                _ = tx.update(e.id) { $0.data = data }
            }
        }
    }
}
