import Foundation
import ArcusGeometry

// FM9: the helpers every library batch builds its pieces with (FurnitureLibrary+Essentials/+SimpleA/+SimpleB). They
// call the same Furniture mode operations the tools call (FurniturePartOperations, FurnitureBays, FurnitureFronts,
// forms with FormLock), so a library piece is an ordinary Furniture document: parametric Width/Depth/Height planes,
// part types with materials, joints by rule, hardware placed by the fronts, and types for its standard sizes.
//
// Conventions: every size and position is in inches; x runs left to right, y front to back, z up from the floor;
// the piece's centre is at x = 0, y = 0. `b.l, b.r, b.f, b.b` are the Left/Right/Front/Back planes and `b.h` the
// Top plane for the first size. Parts are locked to the nearest plane when the piece is finished, so they flex.
//
//     LibraryKit.piece("Nightstand", category: .casework, sizes: [.init("24\"", w: 24, d: 18, h: 26)]) { b in
//         b.carcass(.init(base: .plinth(height: 3), columns: [.init(rows: [.init(.drawers(2))])]))
//     }

/// The Furniture Library builder's entry points (see the file comment).
public enum LibraryKit {
    public static let inch = 0.0254

    /// One size type: its name and Width/Depth/Height in inches, plus values of the piece's own length parameters
    /// (inches) by name.
    public struct Size: Sendable, Hashable {
        public var name: String
        public var width: Double
        public var depth: Double
        public var height: Double
        public var values: [String: Double]
        public init(_ name: String, w: Double, d: Double, h: Double, _ values: [String: Double] = [:]) {
            self.name = name; width = w; depth = d; height = h; self.values = values
        }
    }

    /// Where a build failure is recorded (on the Project Information element), so tests and the generator report it.
    public static let buildErrorKey = ParameterID("furniture.library.buildError")

    /// Builds a library piece: a blank Furniture (or Casework) document named `name`, with one type per size (the first
    /// drives the planes while building), extra length `parameters` (their values come from the sizes), and the parts
    /// `build` makes. Everything is locked to the planes at the end. A failure is recorded (`buildError`) and the
    /// pieces built so far are kept.
    public static func piece(_ name: String, category: FamilyTemplate = .furniture, sizes: [Size], parameters: [String] = [],
                             description: String = "", build: (LibraryBuilder) throws -> Void) -> BIMModel {
        var m = FurnitureTemplates.blank(category: category, name: name)
        let sizes = sizes.isEmpty ? [Size(FurnitureTemplates.typeName(FurnitureTemplates.defaultWidth, FurnitureTemplates.defaultDepth, FurnitureTemplates.defaultHeight),
                                          w: 36, d: 18, h: 30)] : sizes
        do {
            let tx = TransactionContext(model: m, name: "Types")
            try FurnitureParameters.edit(tx) { s in
                for p in parameters where s.family.parameter(named: p) == nil {
                    s.family.parameters.append(FamilyParameter(name: p, type: .length, group: .dimensions))
                }
                let material = s.family.types.first?.values["Material"]
                s.family.types = sizes.map { z in
                    var v: [String: ParamValue] = ["Width": .double(z.width * inch), "Depth": .double(z.depth * inch), "Height": .double(z.height * inch)]
                    if let material { v["Material"] = material }
                    for p in parameters { v[p] = .double((z.values[p] ?? 0) * inch) }
                    return FamilyTypeDefinition(name: z.name, values: v)
                }
                s.currentType = sizes[0].name
                if !description.isEmpty { s.family.description = description }
            }
            m = try tx.commit().model
        } catch {
            return failed(m, error)
        }
        let b = LibraryBuilder(m)
        do {
            b.ensureKitTypes()
            try build(b)
            try b.finish()
            return b.model
        } catch {
            try? b.commit()
            return failed(b.model, error)
        }
    }

    /// The build failure recorded on a piece, or nil.
    public static func buildError(_ m: BIMModel) -> String? { m.projectInfoElement?.params[buildErrorKey]?.textValue }

    static func failed(_ m: BIMModel, _ error: any Error) -> BIMModel {
        var m = m
        guard var info = m.projectInfoElement else { return m }
        info.params[buildErrorKey] = .text((error as? TransactionError)?.message ?? "\(error)")
        m.put(info)
        return m
    }
}

// MARK: - Builder

/// Builds one piece (see `LibraryKit.piece`). Parts are made in an open transaction; the operations that pick from
/// parts already made (backs, plinths, dividers, legs At Corners, bays, fronts) commit first, as the tools work on a
/// committed model.
public final class LibraryBuilder {
    public static let inch = 0.0254
    public private(set) var model: BIMModel
    private var open: TransactionContext?
    /// The forms made so far (locks are set when they're made).
    public private(set) var forms: [ElementID] = []

    init(_ m: BIMModel) { model = m }

    // MARK: Frame (inches)

    /// Plane positions of the first size (inches).
    public var l: Double { plane("Left") }
    public var r: Double { plane("Right") }
    public var f: Double { plane("Front") }
    public var b: Double { plane("Back") }
    public var h: Double { plane("Top") }
    public var w: Double { r - l }
    public var d: Double { b - f }
    /// A plane's position (inches), 0 when missing.
    public func plane(_ name: String) -> Double { (FurniturePlanes.positionsByName(tx.model)[name] ?? 0) / Self.inch }
    /// A length parameter's value in the current type (inches).
    public func value(_ name: String) -> Double {
        if case .quantity(let v, _)? = FurnitureParameters.value(name, tx.model) { return v / Self.inch }
        return 0
    }

    static func m(_ v: Double) -> Double { v * inch }
    static func mv(_ p: Vec2) -> Vec2 { Vec2(p.x * inch, p.y * inch) }

    // MARK: Transactions

    /// The open transaction (one is started when needed).
    public var tx: TransactionContext {
        if let t = open { return t }
        let t = TransactionContext(model: model, name: "Library")
        open = t
        return t
    }

    /// Commits the open transaction (regeneration binds the new parts to the planes and faces they lie on).
    public func commit() throws {
        guard let t = open else { return }
        open = nil
        model = try t.commit().model
    }

    /// Runs `body` in its own transaction and commits it.
    @discardableResult
    public func step<T>(_ body: (TransactionContext) throws -> T) throws -> T {
        try commit()
        let out = try body(tx)
        try commit()
        return out
    }

    /// Commits, then locks every part coordinate not yet bound to the nearest plane along its axis (Align and lock).
    func finish() throws {
        try commit()
        try LibraryKit.lockAll(in: tx)
        try commit()
    }

    /// Adds a reference plane driven by `formula` ("Height - Seat Thickness"), as a named plane parts can lock to.
    @discardableResult
    public func addPlane(_ name: String, axis: FamilyAxis, formula: String) throws -> ElementID {
        try commit()
        let ext = FurniturePlanes.extents(tx.model)
        let rp = FurniturePlanes.make(axis: axis, formula: formula, strength: .weak, origin: false, at: 0, extents: ext)
        let id = tx.create(.referencePlanes, name: name, data: .referencePlane(rp))
        try commit()
        return id
    }

    // MARK: Materials and types

    /// A material by name, created from the library palette (`LibraryKit.palette`) when the document doesn't have it.
    @discardableResult
    public func material(_ name: String) -> ElementID? {
        if let id = tx.model.elements(.materials).first(where: { $0.name == name })?.id { return id }
        guard let spec = LibraryKit.palette.first(where: { $0.name == name }) else { return nil }
        var md = MaterialData(materialClass: spec.materialClass, color: RGBColor(hex: spec.color), transparency: spec.transparency, description: spec.description)
        MaterialPatternDefaults.apply(to: &md, name: spec.name, patterns: MaterialPatternDefaults.patternIndex(tx.model))
        md.cost = spec.cost
        md.costUnit = spec.unit
        return tx.create(.materials, name: spec.name, data: .material(md))
    }

    /// A type of `category` by name (any family).
    public func type(_ category: Category, _ name: String) -> ElementID? { tx.model.types(for: category).first { $0.name == name }?.id }

    private func partType(_ category: Category, family: String, name: String, numbers: [ParameterID: Double], texts: [ParameterID: String],
                          materials: [ParameterID: String]) -> ElementID {
        if let id = tx.model.types(for: category).first(where: { $0.name == name && $0.typeData?.familyName == family })?.id { return id }
        var params: [ParameterID: ParamValue] = [:]
        for (k, v) in numbers { params[k] = .double(v) }
        for (k, v) in texts { params[k] = .text(v) }
        for (k, v) in materials { params[k] = .ref(material(v)) }
        return tx.create(.elementTypes, name: name, data: .type(TypeData(instanceCategory: category, familyName: family, params: params)))
    }

    /// A panel type (sides, dividers, aprons, backs): thickness in inches, core material, optional face material.
    @discardableResult
    public func panelType(_ name: String, thickness: Double, material core: String, face: String? = nil, edge: String? = "Edge Banding",
                          banding: String = "L1", grain: GrainDirection = .length) -> ElementID {
        var mats: [ParameterID: String] = [FurniturePartTypes.coreMaterial: core]
        if let face { mats[FurniturePartTypes.faceMaterial] = face }
        if let edge { mats[FurniturePartTypes.edgeMaterial] = edge }
        return partType(.furniturePanels, family: "Panel", name: name,
                        numbers: [FurniturePartTypes.thickness: Self.m(thickness), FurniturePartTypes.edgeThickness: edge == nil ? 0 : Self.m(0.02)],
                        texts: [FurniturePartTypes.banding: edge == nil ? "None" : banding, FurniturePartTypes.grain: grain.rawValue], materials: mats)
    }

    /// A shelf or top type (`top` puts it in the Top family with an edge shape).
    @discardableResult
    public func shelfType(_ name: String, thickness: Double, material core: String, face: String? = nil, top: Bool = false, edgeShape: TopEdge = .square,
                          edge: String? = nil, banding: String = "L1", grain: GrainDirection = .length) -> ElementID {
        var mats: [ParameterID: String] = [FurniturePartTypes.coreMaterial: core]
        if let face { mats[FurniturePartTypes.faceMaterial] = face }
        if let edge { mats[FurniturePartTypes.edgeMaterial] = edge }
        var texts: [ParameterID: String] = [FurniturePartTypes.banding: edge == nil ? "None" : banding, FurniturePartTypes.grain: grain.rawValue]
        if top { texts[FurniturePartTypes.topEdge] = edgeShape.rawValue }
        return partType(.furnitureShelves, family: top ? "Top" : "Shelf", name: name,
                        numbers: [FurniturePartTypes.thickness: Self.m(thickness), FurniturePartTypes.edgeThickness: edge == nil ? 0 : Self.m(0.02)],
                        texts: texts, materials: mats)
    }

    /// A leg type: shape, size at the top (`width` x `depth`), size at the foot (`taper`, 0 = straight), rod size
    /// (hairpin, sled), material.
    @discardableResult
    public func legType(_ name: String, shape: LegShape, width: Double, depth: Double? = nil, taper: Double = 0, rod: Double = 0.375, material: String) -> ElementID {
        partType(.furnitureLegs, family: "Leg", name: name,
                 numbers: [FurniturePartTypes.width: Self.m(width), FurniturePartTypes.depth: Self.m(depth ?? width), FurniturePartTypes.taper: Self.m(taper),
                           FurniturePartTypes.rod: Self.m(rod)],
                 texts: [FurniturePartTypes.legShape: shape.rawValue], materials: [FurniturePartTypes.coreMaterial: material])
    }

    /// A rail type: `width` across, `height` deep (inches), rectangular or round.
    @discardableResult
    public func railType(_ name: String, width: Double, height: Double, profile: RailProfile = .rectangle, material: String) -> ElementID {
        partType(.furnitureRails, family: "Rail", name: name, numbers: [FurniturePartTypes.width: Self.m(width), FurniturePartTypes.depth: Self.m(height)],
                 texts: [FurniturePartTypes.railProfile: profile.rawValue, FurniturePartTypes.grain: GrainDirection.length.rawValue],
                 materials: [FurniturePartTypes.coreMaterial: material])
    }

    /// A door, drawer or flap type copied from a standard one (`from`, e.g. "Shaker - Full Overlay"), with its own
    /// material, style and handle (family and type, e.g. (FurnitureHardware.knob, "1 1/4\"")).
    @discardableResult
    public func frontType(_ kind: FrontKind, _ name: String, from base: String, material: String? = nil, panel: String? = nil, style: FrontStyle? = nil,
                          handle: (String, String)? = nil, edgeProfile: EdgeProfileShape? = nil) -> ElementID? {
        if let id = tx.model.types(for: .furnitureFronts).first(where: { $0.name == name && $0.typeData?.familyName == kind.rawValue })?.id { return id }
        if FurnitureFrontTypes.firstType(kind, tx.model) == nil { FurnitureFrontTypes.ensureStandard(in: tx) }
        guard var td = tx.model.types(for: .furnitureFronts).first(where: { $0.name == base && $0.typeData?.familyName == kind.rawValue })?.typeData else { return nil }
        if let material { td.params[FurniturePartTypes.coreMaterial] = .ref(self.material(material)) }
        if let panel { td.params[FurnitureFrontTypes.panelMaterial] = .ref(self.material(panel)) }
        if let style { td.params[FurnitureFrontTypes.style] = .text(style.rawValue) }
        if let handle { td.params[FurnitureFrontTypes.handleType] = .ref(FurnitureHardware.type(handle.0, handle.1, tx.model)) }
        if let edgeProfile { td.params[FurnitureFrontTypes.edgeProfile] = .text(edgeProfile.rawValue) }
        return tx.create(.elementTypes, name: name, data: .type(td))
    }

    /// Part types the recipes use beyond the standard set.
    func ensureKitTypes() {
        shelfType("1/2\" Plywood Shelf", thickness: 0.5, material: "Plywood", edge: "Edge Banding")
    }

    func typeID(_ category: Category, _ name: String?) -> ElementID? { name.flatMap { type(category, $0) } }
    func thickness(_ typeID: ElementID?) -> Double { FurniturePartTypes.Values(tx.model[typeID]?.typeData).thickness / Self.inch }

    // MARK: Parts (inches)

    /// A board: a panel when it is thin across x or y (a side, an apron, a back), a shelf when it is thin in z. The
    /// type's thickness wins over the range's; the board's low face is at the range's start.
    @discardableResult
    public func board(x: ClosedRange<Double>, y: ClosedRange<Double>, z: ClosedRange<Double>, type: String, role: FurniturePartKind? = nil) throws -> ElementID {
        let sx = x.upperBound - x.lowerBound, sy = y.upperBound - y.lowerBound, sz = z.upperBound - z.lowerBound
        if sz <= sx, sz <= sy {
            let t = typeID(.furnitureShelves, type) ?? typeID(.furniturePanels, type)
            let th = thickness(t)
            return try shelf(x: x, y: y, top: z.lowerBound + th, typeID: t, role: role ?? .shelf)
        }
        let t = typeID(.furniturePanels, type)
        let ext = PartExtent(basePlane: nil, baseOffset: Self.m(z.lowerBound), topPlane: nil, height: Self.m(sz))
        if sx <= sy {
            // Drawn front to back: the outside face (left of the line) at x.lowerBound, the board toward +x.
            return try FurniturePartOperations.createPanel(start: Self.mv(Vec2(x.lowerBound, y.lowerBound)), end: Self.mv(Vec2(x.lowerBound, y.upperBound)),
                                                           locationLine: .faceOutside, extent: ext, role: role ?? .panel, typeID: t, in: tx)
        }
        // Drawn right to left: the outside face toward the front at y.lowerBound, the board toward +y.
        return try FurniturePartOperations.createPanel(start: Self.mv(Vec2(x.upperBound, y.lowerBound)), end: Self.mv(Vec2(x.lowerBound, y.lowerBound)),
                                                       locationLine: .faceOutside, extent: ext, role: role ?? .panel, typeID: t, in: tx)
    }

    /// A panel drawn in plan from `a` to `b`, standing from `z0` to `z1` (as the Panel tool draws it).
    @discardableResult
    public func panel(from a: Vec2, to b: Vec2, z: ClosedRange<Double>, type: String? = nil, line: PanelLocationLine = .faceOutside, role: FurniturePartKind = .panel) throws -> ElementID {
        let ext = PartExtent(basePlane: nil, baseOffset: Self.m(z.lowerBound), topPlane: nil, height: Self.m(z.upperBound - z.lowerBound))
        return try FurniturePartOperations.createPanel(start: Self.mv(a), end: Self.mv(b), locationLine: line, extent: ext, role: role, typeID: typeID(.furniturePanels, type), in: tx)
    }

    /// A panel drawn in the front elevation (x, z) from `a` to `b`, running from y = `y0` to `y1` (a horizontal panel
    /// drawn in elevation, like a bed's deck seen from the front).
    @discardableResult
    public func panelXZ(from a: Vec2, to b: Vec2, y: ClosedRange<Double>, type: String? = nil, line: PanelLocationLine = .faceOutside, role: FurniturePartKind = .panel) throws -> ElementID {
        let ext = PartExtent(basePlane: nil, baseOffset: Self.m(y.lowerBound), topPlane: nil, height: Self.m(y.upperBound - y.lowerBound))
        return try FurniturePartOperations.createPanel(start: Self.mv(a), end: Self.mv(b), plane: .xz, locationLine: line, extent: ext, role: role,
                                                       typeID: typeID(.furniturePanels, type), in: tx)
    }

    /// A shelf, top or bottom: a plan rectangle with its top face at `top`.
    @discardableResult
    public func shelf(x: ClosedRange<Double>, y: ClosedRange<Double>, top: Double, type: String? = nil, role: FurniturePartKind = .shelf, adjustable: Bool = false,
                      setback: Double = 0) throws -> ElementID {
        try shelf(x: x, y: y, top: top, typeID: typeID(.furnitureShelves, type), role: role, adjustable: adjustable, setback: setback)
    }

    func shelf(x: ClosedRange<Double>, y: ClosedRange<Double>, top: Double, typeID t: ElementID?, role: FurniturePartKind = .shelf, adjustable: Bool = false,
               setback: Double = 0) throws -> ElementID {
        let loop = [Vec2(x.lowerBound, y.lowerBound), Vec2(x.upperBound, y.lowerBound), Vec2(x.upperBound, y.upperBound), Vec2(x.lowerBound, y.upperBound)].map(Self.mv)
        return try FurniturePartOperations.createShelf(boundary: loop, plane: nil, offset: Self.m(top), role: role, adjustable: adjustable, frontSetback: Self.m(setback),
                                                       typeID: t, in: tx)
    }

    /// A shelf or top with any plan outline (a round or shaped top).
    @discardableResult
    public func shelf(outline: [Vec2], top: Double, type: String? = nil, role: FurniturePartKind = .top) throws -> ElementID {
        try FurniturePartOperations.createShelf(boundary: outline.map(Self.mv), plane: nil, offset: Self.m(top), role: role, typeID: typeID(.furnitureShelves, type), in: tx)
    }

    /// A leg at a plan point from `z0` to `z1`.
    @discardableResult
    public func leg(at p: Vec2, z: ClosedRange<Double>, type: String? = nil, rotation: Double = 0) throws -> ElementID {
        let ext = PartExtent(basePlane: nil, baseOffset: Self.m(z.lowerBound), topPlane: nil, height: Self.m(z.upperBound - z.lowerBound))
        return try FurniturePartOperations.createLeg(at: Self.mv(p), extent: ext, rotation: rotation, typeID: typeID(.furnitureLegs, type), in: tx)
    }

    /// Four legs, one in each corner of the plan rectangle (centres `inset` in from its edges plus half the leg).
    @discardableResult
    public func legs(x: ClosedRange<Double>, y: ClosedRange<Double>, inset: Double = 0, z: ClosedRange<Double>, type: String) throws -> [ElementID] {
        let t = typeID(.furnitureLegs, type)
        let tv = FurniturePartTypes.Values(tx.model[t]?.typeData)
        let hx = tv.width / Self.inch / 2 + inset, hy = tv.depth / Self.inch / 2 + inset
        var out: [ElementID] = []
        for px in [x.lowerBound + hx, x.upperBound - hx] {
            for py in [y.lowerBound + hy, y.upperBound - hy] { out.append(try leg(at: Vec2(px, py), z: z, type: type)) }
        }
        return out
    }

    /// The width and depth of a leg type (inches).
    public func legSize(_ type: String) -> (width: Double, depth: Double) {
        let tv = FurniturePartTypes.Values(tx.model[typeID(.furnitureLegs, type)]?.typeData)
        return (tv.width / Self.inch, tv.depth / Self.inch)
    }

    /// A rail drawn in plan from `a` to `b`, its top (or `justification`) at `z`.
    @discardableResult
    public func rail(from a: Vec2, to b: Vec2, z: Double, type: String? = nil, justification: RailJustification = .top) throws -> ElementID {
        try FurniturePartOperations.createRail(start: Self.mv(a), end: Self.mv(b), w: Self.m(z), justification: justification, typeID: typeID(.furnitureRails, type), in: tx)
    }

    /// A rail drawn in the front elevation (x, z) from `a` to `b`, centred at depth `y` (a back post, a slanted stile).
    @discardableResult
    public func railXZ(from a: Vec2, to b: Vec2, y: Double, type: String? = nil) throws -> ElementID {
        try FurniturePartOperations.createRail(start: Self.mv(a), end: Self.mv(b), plane: .xz, w: Self.m(y), justification: .center, typeID: typeID(.furnitureRails, type), in: tx)
    }

    /// A rail drawn in the side elevation (y, z) from `a` to `b`, centred at `x` (a chair's back leg seen from the side).
    @discardableResult
    public func railYZ(from a: Vec2, to b: Vec2, x: Double, type: String? = nil) throws -> ElementID {
        try FurniturePartOperations.createRail(start: Self.mv(a), end: Self.mv(b), plane: .yz, w: Self.m(x), justification: .center, typeID: typeID(.furnitureRails, type), in: tx)
    }

    /// Slats filling a plan rectangle, their tops at `z`, `alongX` or front to back, at a spacing or a number.
    @discardableResult
    public func slats(x: ClosedRange<Double>, y: ClosedRange<Double>, z: Double, alongX: Bool, spacing: Double? = nil, number: Int? = nil, type: String? = nil) throws -> ElementID {
        let rect = Rect2(min: Self.mv(Vec2(x.lowerBound, y.lowerBound)), max: Self.mv(Vec2(x.upperBound, y.upperBound)))
        return try FurniturePartOperations.createSlats(in: rect, alongX: alongX, rule: number == nil ? .fixedDistance : .fixedNumber, spacing: Self.m(spacing ?? 4),
                                                       number: number ?? 5, z: Self.m(z), typeID: typeID(.furnitureRails, type), in: tx)
    }

    /// An edge profile or groove on a part's edge (type by name, e.g. "1/4\" Round-Over").
    @discardableResult
    public func edgeProfile(on part: ElementID, edge: PartEdge, type: String) throws -> ElementID {
        try commit()
        return try FurniturePartOperations.createEdgeProfile(on: part, edge: edge, typeID: typeID(.furnitureEdgeProfiles, type), in: tx)
    }

    // MARK: Picked parts (commit first)

    /// A back inside the carcass round the front point (x, z), between its sides, bottom and top.
    @discardableResult
    public func back(at p: Vec2, type: String = "1/4\" Back Panel (Hardboard)", overlay: Bool = false) throws -> ElementID {
        try commit()
        return try FurniturePartOperations.createBack(atFront: Self.mv(p), fit: overlay ? .fullOverlay : .inside, typeID: typeID(.furniturePanels, type), in: tx)
    }

    /// A plinth (toe kick) under a bottom, `setback` in from its front.
    @discardableResult
    public func plinth(under bottom: ElementID, setback: Double = 3, type: String? = nil) throws -> ElementID {
        try commit()
        return try FurniturePartOperations.createPlinth(under: bottom, setback: Self.m(setback), typeID: typeID(.furniturePanels, type), in: tx)
    }

    /// `count` dividers splitting the bay round the front point (x, z) equally (EQ).
    @discardableResult
    public func dividers(at p: Vec2, vertical: Bool = true, count: Int, type: String? = nil, setback: Double = 0) throws -> [ElementID] {
        try commit()
        return try FurniturePartOperations.createDividers(atFront: Self.mv(p), vertical: vertical, count: count, setback: Self.m(setback), typeID: typeID(.furniturePanels, type), in: tx)
    }

    /// Legs At Corners of a committed top or shelf, `inset` in from its edges.
    @discardableResult
    public func legsAtCorners(of top: ElementID, inset: Double, type: String, baseOffset: Double = 0) throws -> [ElementID] {
        try commit()
        return try FurniturePartOperations.legsAtCorners(of: top, inset: Self.m(inset), baseOffset: Self.m(baseOffset), typeID: typeID(.furnitureLegs, type), in: tx)
    }

    // MARK: Bays and fronts (commit first)

    /// A bay round the front point (x, z).
    @discardableResult
    public func bay(at p: Vec2) throws -> ElementID {
        try commit()
        return try FurnitureBays.createBay(face: .front, at: Self.mv(p), in: tx)
    }

    /// Bay Divide into rows (from the bottom): equal when `heights` is empty, else the first cells' heights (inches).
    @discardableResult
    public func divide(_ bay: ElementID, rows count: Int, heights: [Double] = []) throws -> [ElementID] {
        try commit()
        let d = BayDivision(direction: .rows, layout: heights.isEmpty ? .equal : .fixed, count: count, sizes: heights.map(Self.m))
        try FurnitureBays.divide(bay, d, in: tx)
        try commit()
        return FurnitureBays.cellIDs(of: bay, model)
    }

    /// A door (hinged left unless `hingeRight`), drawer or flap in a bay, of the front type named `type` (nil = the
    /// standard one).
    @discardableResult
    public func front(_ kind: FrontKind, in bay: ElementID, type: String? = nil, hingeRight: Bool = false) throws -> [ElementID] {
        try commit()
        let t = type.flatMap { n in tx.model.types(for: .furnitureFronts).first { $0.name == n && $0.typeData?.familyName == kind.rawValue }?.id }
        return try FurnitureFronts.createFront(kind, in: bay, typeID: t, hingeFlipped: hingeRight, in: tx)
    }

    /// A stack of `count` equal drawers in a bay.
    @discardableResult
    public func drawers(in bay: ElementID, count: Int, type: String? = nil) throws -> [ElementID] {
        try commit()
        let t = type.flatMap { n in tx.model.types(for: .furnitureFronts).first { $0.name == n && $0.typeData?.familyName == FrontKind.drawer.rawValue }?.id }
        return try FurnitureFronts.createDrawers(in: bay, count: count, typeID: t, in: tx)
    }

    // MARK: Forms (inches)

    /// How a form follows the planes: by its position (`auto`: a form against a side follows that side, one across the
    /// middle stretches), not at all, or as given per axis.
    public enum Lock: Sendable {
        case auto
        case none
        case axes(x: FormAxisLock.Mode?, y: FormAxisLock.Mode?, z: FormAxisLock.Mode?)
    }

    /// A cushion: plan rectangle, standing on `z`, `height` tall with a crowned top, rounded corners and piping.
    @discardableResult
    public func cushion(x: ClosedRange<Double>, y: ClosedRange<Double>, z: Double, height: Double, crown: Double = 0.75, radius: Double = 1.5,
                        piping: Bool = true, material: String = "Fabric", lock: Lock = .auto) throws -> ElementID {
        var c = CushionSpec(center: Self.mv(Vec2((x.lowerBound + x.upperBound) / 2, (y.lowerBound + y.upperBound) / 2)), width: Self.m(x.upperBound - x.lowerBound),
                            depth: Self.m(y.upperBound - y.lowerBound), height: Self.m(height), crown: Self.m(crown), cornerRadius: Self.m(radius),
                            topPiping: piping, bottomPiping: piping, pipingDiameter: Self.m(0.25))
        c.rotation = 0
        var fd = FurnitureFormData(kind: .cushion, profile: [], w0: Self.m(z), w1: Self.m(z + height))
        fd.cushion = c
        return try form(fd, material: material, lock: lock, extent: (x, y, z...(z + height)))
    }

    /// An extrusion: `profile` (inches) on `plane` (plan: x, y; front: x, z; side: y, z), from `w0` to `w1` along its
    /// normal (z, y or x).
    @discardableResult
    public func extrusion(_ profile: [Vec2], plane: FamilySketchPlane = .xy, w: ClosedRange<Double>, material: String, lock: Lock = .auto,
                          visibleAt: Set<DetailLevel> = [.coarse, .medium, .fine]) throws -> ElementID {
        var fd = FurnitureFormData(kind: .extrusion, plane: plane, profile: profile.map(Self.mv), w0: Self.m(w.lowerBound), w1: Self.m(w.upperBound))
        fd.visibleAt = visibleAt
        let us = profile.map(\.x), vs = profile.map(\.y)
        let ur = (us.min() ?? 0)...(us.max() ?? 0), vr = (vs.min() ?? 0)...(vs.max() ?? 0)
        let ext: (ClosedRange<Double>, ClosedRange<Double>, ClosedRange<Double>) = switch plane {
        case .xy: (ur, vr, w)
        case .xz: (ur, w, vr)
        case .yz: (w, ur, vr)
        }
        return try form(fd, material: material, lock: lock, extent: ext)
    }

    /// A blend from a bottom plan loop at `z0` to a top loop at `z1`.
    @discardableResult
    public func blend(bottom: [Vec2], top: [Vec2], z: ClosedRange<Double>, material: String, lock: Lock = .auto) throws -> ElementID {
        var fd = FurnitureFormData(kind: .blend, profile: bottom.map(Self.mv), w0: Self.m(z.lowerBound), w1: Self.m(z.upperBound))
        fd.topProfile = top.map(Self.mv)
        let all = bottom + top
        return try form(fd, material: material, lock: lock, extent: ((all.map(\.x).min() ?? 0)...(all.map(\.x).max() ?? 0), (all.map(\.y).min() ?? 0)...(all.map(\.y).max() ?? 0), z))
    }

    /// A revolve about the vertical axis at `axis`: `profile` in (distance from the axis, height above `z`).
    @discardableResult
    public func revolve(axis: Vec2, profile: [Vec2], z: Double, material: String, lock: Lock = .auto) throws -> ElementID {
        var fd = FurnitureFormData(kind: .revolve, profile: profile.map(Self.mv), w0: Self.m(z), w1: Self.m(z))
        fd.axis = Self.mv(axis)
        let rad = profile.map(\.x).max() ?? 0, top = profile.map(\.y).max() ?? 0
        return try form(fd, material: material, lock: lock, extent: ((axis.x - rad)...(axis.x + rad), (axis.y - rad)...(axis.y + rad), z...(z + top)))
    }

    /// A sweep: `profile` (x to the left of the path, y up, inches) along the plan `path` at height `z`.
    @discardableResult
    public func sweep(path: [Vec2], profile: [Vec2], z: Double, material: String, lock: Lock = .auto) throws -> ElementID {
        var fd = FurnitureFormData(kind: .sweep, profile: profile.map(Self.mv), w0: Self.m(z), w1: Self.m(z))
        fd.path = path.map(Self.mv)
        let ys = profile.map(\.y), xs = profile.map(\.x)
        let reach = xs.map(abs).max() ?? 0
        return try form(fd, material: material, lock: lock,
                        extent: (((path.map(\.x).min() ?? 0) - reach)...((path.map(\.x).max() ?? 0) + reach), ((path.map(\.y).min() ?? 0) - reach)...((path.map(\.y).max() ?? 0) + reach),
                                 (z + (ys.min() ?? 0))...(z + (ys.max() ?? 0))))
    }

    func form(_ fd: FurnitureFormData, material: String, lock: Lock, extent: (ClosedRange<Double>, ClosedRange<Double>, ClosedRange<Double>)) throws -> ElementID {
        var fd = fd
        fd.materialID = self.material(material) ?? tx.model.elements(.materials).first { $0.name == "Fabric" }?.id
        switch lock {
        case .none: fd.lock = nil
        case .axes(let x, let y, let z): fd.lock = FormLock.framing(tx.model, x: x, y: y, z: z)
        case .auto: fd.lock = FormLock.framing(tx.model, x: autoMode(extent.0, l, r, vertical: false), y: autoMode(extent.1, f, b, vertical: false),
                                               z: autoMode(extent.2, 0, h, vertical: true))
        }
        let id = try FurniturePartOperations.createForm(fd, in: tx)
        forms.append(id)
        return id
    }

    /// `auto` lock along one axis: against the low plane (within 1/2") and narrow → follows it; against the high plane →
    /// follows that; across the middle → stretches. Heights follow the Bottom unless the form reaches the Top.
    func autoMode(_ e: ClosedRange<Double>, _ lo: Double, _ hi: Double, vertical: Bool) -> FormAxisLock.Mode {
        let span = hi - lo, tol = 0.5
        guard span > 0 else { return .low }
        if vertical {
            guard e.upperBound >= hi - 1.5 else { return .low }
            return e.lowerBound <= lo + span * 0.5 ? .stretch : .high
        }
        let size = e.upperBound - e.lowerBound
        let atLow = e.lowerBound <= lo + tol, atHigh = e.upperBound >= hi - tol
        if atLow && !atHigh && size < span * 0.4 { return .low }
        if atHigh && !atLow && size < span * 0.4 { return .high }
        return .stretch
    }
}

// MARK: - Palette

extension LibraryKit {
    /// Materials library pieces use beyond the Furniture template's set (created on first use by `material(_:)`).
    public static let palette: [FurnitureTemplates.MaterialSpec] = [
        .init(name: "Solid White Oak", materialClass: .wood, color: 0xC9A777, transparency: 0, cost: 11, unit: .boardFoot, description: "White oak, quartersawn, kiln dried"),
        .init(name: "Solid Cherry", materialClass: .wood, color: 0x9C5B3B, transparency: 0, cost: 10, unit: .boardFoot, description: "Black cherry, kiln dried"),
        .init(name: "Walnut Veneer", materialClass: .wood, color: 0x6E4B33, transparency: 0, cost: 5, unit: .squareFoot, description: "Walnut veneer, paper backed"),
        .init(name: "Oak Veneer", materialClass: .wood, color: 0xC49A68, transparency: 0, cost: 4, unit: .squareFoot, description: "White oak veneer, paper backed"),
        .init(name: "Painted MDF - White", materialClass: .paint, color: 0xF1EFEA, transparency: 0, cost: 70, unit: .sheet, description: "MDF, primed and painted white, 3/4\", 4'x8' sheet"),
        .init(name: "Painted MDF - Sage", materialClass: .paint, color: 0x9AA58E, transparency: 0, cost: 70, unit: .sheet, description: "MDF, painted sage green, 3/4\", 4'x8' sheet"),
        .init(name: "Painted MDF - Navy", materialClass: .paint, color: 0x2F3D57, transparency: 0, cost: 70, unit: .sheet, description: "MDF, painted navy, 3/4\", 4'x8' sheet"),
        .init(name: "Fabric - Oatmeal Linen", materialClass: .generic, color: 0xCDC2AE, transparency: 0, cost: 9, unit: .linearFoot, description: "Linen-blend upholstery fabric, 54\" wide"),
        .init(name: "Fabric - Charcoal Weave", materialClass: .generic, color: 0x4B4E54, transparency: 0, cost: 9, unit: .linearFoot, description: "Woven polyester upholstery fabric, 54\" wide"),
        .init(name: "Fabric - Navy Velvet", materialClass: .generic, color: 0x2C3954, transparency: 0, cost: 14, unit: .linearFoot, description: "Cotton velvet, 54\" wide"),
        .init(name: "Fabric - Sage Boucle", materialClass: .generic, color: 0xA3AC93, transparency: 0, cost: 15, unit: .linearFoot, description: "Boucle upholstery fabric, 54\" wide"),
        .init(name: "Fabric - White Cotton", materialClass: .generic, color: 0xF3F1EC, transparency: 0, cost: 6, unit: .linearFoot, description: "Cotton sateen bedding fabric"),
        .init(name: "Leather - Cognac", materialClass: .generic, color: 0x9A5B32, transparency: 0, cost: 11, unit: .squareFoot, description: "Aniline upholstery leather"),
        .init(name: "Leather - Black", materialClass: .generic, color: 0x2B2826, transparency: 0, cost: 10, unit: .squareFoot, description: "Pigmented upholstery leather"),
        .init(name: "Mesh - Black", materialClass: .plastic, color: 0x2A2B2D, transparency: 0, cost: 6, unit: .squareFoot, description: "Elastomeric chair mesh"),
        .init(name: "Black Steel", materialClass: .metal, color: 0x2E3033, transparency: 0, cost: 7, unit: .linearFoot, description: "Powder-coated steel tube, matte black"),
        .init(name: "Chrome", materialClass: .metal, color: 0xC9CED3, transparency: 0, cost: 9, unit: .linearFoot, description: "Chrome-plated steel"),
        .init(name: "Aluminum", materialClass: .metal, color: 0xB4B8BC, transparency: 0, cost: 8, unit: .linearFoot, description: "Polished cast aluminum"),
        .init(name: "Plastic - Black", materialClass: .plastic, color: 0x252527, transparency: 0, cost: 4, unit: .each, description: "Glass-filled nylon"),
        .init(name: "Marble - Carrara", materialClass: .stone, color: 0xE8E5E0, transparency: 0, cost: 45, unit: .squareFoot, description: "Carrara marble, honed, 3/4\""),
        .init(name: "Quartz - White", materialClass: .stone, color: 0xF2F0EC, transparency: 0, cost: 60, unit: .squareFoot, description: "Engineered quartz, 1 1/4\""),
        .init(name: "Ceramic - White", materialClass: .ceramic, color: 0xF7F7F5, transparency: 0, cost: 180, unit: .each, description: "Vitreous china undermount sink"),
        .init(name: "Mirror", materialClass: .glass, color: 0xCFDCE2, transparency: 0.15, cost: 14, unit: .squareFoot, description: "Silvered float glass mirror, 1/4\""),
        .init(name: "Rattan", materialClass: .wood, color: 0xC9A16B, transparency: 0, cost: 12, unit: .squareFoot, description: "Woven rattan cane webbing"),
        .init(name: "Mattress", materialClass: .generic, color: 0xF4F2EE, transparency: 0, cost: 30, unit: .squareFoot, description: "Hybrid mattress, quilted cover"),
    ]
}

// MARK: - Locking

extension LibraryKit {
    /// Binds every part coordinate that isn't bound yet to the nearest plane along its axis, at its current offset (Align
    /// and lock), so the piece flexes as a whole. EQ dividers keep their spacing.
    public static func lockAll(in tx: TransactionContext) throws {
        let m = tx.model
        let byAxis = Dictionary(grouping: FamilyAxis.allCases.flatMap { a in FurniturePartCoordinates.planes(along: a, m).map { (a, $0) } }, by: \.0).mapValues { $0.map(\.1) }
        func nearest(_ v: Double, _ a: FamilyAxis) -> FurnitureBound? {
            guard let p = byAxis[a]?.min(by: { abs($0.position - v) < abs($1.position - v) }) else { return nil }
            return .plane(p.name, offset: v - p.position)
        }
        for c in Category.furnitureParts {
            for e in m.elements(c) {
                var bounds = FurniturePartBounds.bounds(of: e)
                let skip: Set<String> = e.furniturePanel?.eq != nil ? (FurniturePartSolids.linearFrame(e.furniturePanel!.plane, e.furniturePanel!.start, e.furniturePanel!.end)?.lineAlongU == true
                                                                       ? ["start.v", "end.v"] : ["start.u", "end.u"]) : []
                var changed = false
                for k in FurniturePartCoordinates.coordinates(of: e) where bounds[k.key] == nil && !skip.contains(k.key) {
                    // Attached tops and bases follow their shelf.
                    if k.key == "top", e.furniturePanel?.attachedTopID != nil || e.furnitureLeg?.attachedTopID != nil { continue }
                    if k.key == "base", e.furniturePanel?.attachedBaseID != nil { continue }
                    if let bd = nearest(k.value, k.axis) { bounds[k.key] = bd; changed = true }
                }
                guard changed else { continue }
                var x = e
                FurniturePartBounds.setBounds(bounds, of: &x)
                let data = x.data
                _ = tx.update(e.id) { $0.data = data }
            }
        }
    }
}
