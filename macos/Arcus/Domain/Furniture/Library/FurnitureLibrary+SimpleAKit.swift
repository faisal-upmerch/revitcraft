import Foundation
import ArcusGeometry

// FM9B: the kit the simple library pieces are written with (FurnitureLibrary+SimpleA*.swift). A piece is its types
// (standard US sizes), its primary material, any extra reference planes (with formulas of Width, Depth and Height, as
// a Revit user adds them in a family) and a few build steps. Each step is one transaction of the same part, bay and
// front operations the tools call; every part's ends and faces are given on named planes (Left + 3/4", Seat - 4"…) and
// locked there, so the piece flexes with its types and its Width, Depth and Height.

/// The FM9B kit: the framing planes as coordinates, standard type names, and (in extensions) the builders.
enum SA {
    static let inch = 0.0254
    static let L = SA.LP("Left"), R = SA.LP("Right"), F = SA.LP("Front"), B = SA.LP("Back"), Z = SA.LP("Bottom"), T = SA.LP("Top")
    static let CX = SA.LP("Center (Left/Right)"), CY = SA.LP("Center (Front/Back)")
    /// A named plane added by the piece.
    static func p(_ name: String, _ inches: Double = 0) -> SA.LP { SA.LP(name, inches) }

    // Standard part type names.
    static let ply = "3/4\" Plywood", ply12 = "1/2\" Plywood", mdf = "3/4\" MDF", mel = "3/4\" Melamine", oak = "3/4\" Solid Oak"
    static let walnut = "3/4\" Solid Walnut", veneer = "3/4\" Oak Veneer Plywood", hardboard = "1/4\" Back Panel (Hardboard)", ply14 = "1/4\" Plywood"
    static let plyShelf = "3/4\" Plywood Shelf", melShelf = "3/4\" Melamine Shelf", oakShelf = "1\" Solid Oak Shelf", glassShelf = "1/4\" Glass Shelf"
    static let plyTop = "3/4\" Plywood Top", oakTop = "1\" Solid Oak Top", butcher = "1 1/2\" Butcher Block", walnutTop = "1 1/4\" Solid Walnut Top"
    static let laminateTop = "3/4\" Laminate Top"
    static let sq = "Square 1 1/2\"", tapered = "Square Tapered 1 3/4\"", round = "Round 1 1/2\"", roundTapered = "Round Tapered 2\"", turned = "Turned 2 1/2\""
    static let hairpin = "Hairpin 3/8\" Rod", sled = "Sled 1\" Steel", block = "Plinth Block 3\"", caster = "Caster 2\""
    static let apron = "3/4\" x 3\" Apron", stretcher = "3/4\" x 1 1/2\" Stretcher", stretcher15 = "1 1/2\" x 1 1/2\" Stretcher"
    static let cleat = "3/4\" x 3/4\" Cleat", slat = "3/4\" x 2 1/2\" Slat", bedSlat = "1\" x 3\" Bed Slat", roundStretcher = "1\" Round Stretcher"
    // Door, drawer and flap types.
    static let slabDoor = "Slab - Full Overlay", slabPair = "Slab - Full Overlay Pair", shakerDoor = "Shaker - Full Overlay"
    static let shakerPair = "Shaker - Full Overlay Pair", glassDoor = "Glass Panel - Full Overlay", louvered = "Louvered - Full Overlay"
    static let slabDrawer = "Slab - Full Overlay", shakerDrawer = "Shaker - Full Overlay", liftUp = "Slab - Full Overlay Lift-Up", dropDown = "Slab - Full Overlay Drop-Down"
}

extension SA {
    /// A coordinate on a named reference plane: the plane and an offset along its axis (meters).
    struct LP: Sendable {
        var plane: String
        var offset: Double
        init(_ plane: String, _ inches: Double = 0) { self.plane = plane; offset = inches * 0.0254 }
        static func + (a: SA.LP, inches: Double) -> SA.LP { var p = a; p.offset += inches * 0.0254; return p }
        static func - (a: SA.LP, inches: Double) -> SA.LP { a + -inches }
    }
}

extension SA {
    /// A size type: its name and Width, Depth and Height in inches.
    struct Size: Sendable {
        var name: String
        var w: Double, d: Double, h: Double
        /// Named after its size (36" x 18" x 30") unless given a name ("Queen").
        init(_ w: Double, _ d: Double, _ h: Double, _ name: String? = nil) {
            self.w = w; self.d = d; self.h = h
            self.name = name ?? FurnitureTemplates.typeName(w * SA.inch, d * SA.inch, h * SA.inch)
        }
    }
}

extension SA {
    /// A reference plane a piece adds: its name, axis and offset formula.
    struct Plane: Sendable {
        var name: String
        var axis: FamilyAxis
        var formula: String
        init(_ name: String, _ axis: FamilyAxis, _ formula: String) { self.name = name; self.axis = axis; self.formula = formula }
    }
}

extension SA {
    /// One simple library piece: what the library lists and how to build it.
    struct Piece: Sendable {
        typealias Step = @Sendable (SA.Builder) throws -> Void
        var name: String
        var rooms: [String]
        var category: FamilyTemplate
        /// The piece's main material: the Material parameter's value.
        var material: String
        var sizes: [SA.Size]
        var planes: [SA.Plane]
        var steps: [Step]

        init(_ name: String, rooms: [String], _ category: FamilyTemplate = .furniture, material: String, sizes: [SA.Size], planes: [SA.Plane] = [],
             steps: [Step]) {
            self.name = name; self.rooms = rooms; self.category = category; self.material = material; self.sizes = sizes; self.planes = planes
            self.steps = steps
        }

        /// The piece as the library lists it, found by its material and `keywords` too.
        func libraryPiece(keywords: [String] = []) -> FurnitureLibraryPiece {
            let spec = self
            return FurnitureLibraryPiece(name, rooms: rooms, category: category, detail: .simple, keywords: keywords + [material.lowercased()]) { spec.model() }
        }

        /// The piece's document (a blank one of its name when a step fails: `build()` reports why).
        func model() -> BIMModel { (try? build()) ?? FurnitureTemplates.blank(category: category, name: name) }

        /// Builds the piece: its types, material and planes, then each step in its own transaction.
        func build() throws -> BIMModel {
            var m = FurnitureTemplates.blank(category: category, name: name)
            let setup = TransactionContext(model: m, name: "Types and Planes")
            SA.Builder.ensureTypes(in: setup)
            let material = SA.Builder.material(self.material, in: setup)
            let sizes = self.sizes
            try FurnitureParameters.edit(setup) { s in
                let base = s.family.types.first?.values ?? [:]
                s.family.types = sizes.map { z in
                    var v = base
                    v["Width"] = .double(z.w * SA.inch); v["Depth"] = .double(z.d * SA.inch); v["Height"] = .double(z.h * SA.inch)
                    if let material { v["Material"] = .ref(material) }
                    return FamilyTypeDefinition(name: z.name, values: v)
                }
                s.currentType = sizes.first?.name ?? s.currentType
            }
            let extents = FurniturePlanes.extents(setup.model)
            for p in planes {
                let rp = FurniturePlanes.make(axis: p.axis, formula: p.formula, strength: .weak, origin: false, at: 0, extents: extents)
                setup.create(.referencePlanes, name: p.name, data: .referencePlane(rp))
            }
            m = try setup.commit().model
            for (k, step) in steps.enumerated() {
                let tx = TransactionContext(model: m, name: "\(name) \(k + 1)")
                try step(SA.Builder(tx))
                m = try tx.commit().model
            }
            return m
        }
    }
}

extension SA {
    /// What a build step works with: the transaction, the planes' positions and part helpers that take plane coordinates.
    final class Builder {
        let tx: TransactionContext
        let positions: [String: Double]
        var model: BIMModel { tx.model }

        init(_ tx: TransactionContext) { self.tx = tx; positions = FurniturePlanes.positionsByName(tx.model) }

        func v(_ p: SA.LP) -> Double { (positions[p.plane] ?? 0) + p.offset }
        func bound(_ p: SA.LP) -> FurnitureBound { .plane(p.plane, offset: p.offset) }

        // MARK: Types

        /// Part types the simple pieces add to the standard ones (upholstery, mattresses, posts, rods, mirror glass).
        static let extraTypes: [FurniturePartTypes.Spec] = [
            cushion("2\" Seat Pad", 2), cushion("3\" Seat Cushion", 3), cushion("4\" Seat Cushion", 4), cushion("5\" Seat Cushion", 5),
            cushion("6\" Seat Cushion", 6), cushion("8\" Mattress", 8, "Mattress"), cushion("10\" Mattress", 10, "Mattress"), cushion("4\" Leather Cushion", 4, "Leather"),
            cushion("16\" Pouf", 16),
            FurniturePartTypes.sheet(.furniturePanels, "Panel", "3\" Upholstered Panel", t: 3, core: "Fabric", edge: nil, grain: .none),
            FurniturePartTypes.sheet(.furniturePanels, "Panel", "6\" Upholstered Panel", t: 6, core: "Fabric", edge: nil, grain: .none),
            FurniturePartTypes.sheet(.furniturePanels, "Panel", "3\" Leather Panel", t: 3, core: "Leather", edge: nil, grain: .none),
            FurniturePartTypes.sheet(.furniturePanels, "Panel", "6\" Leather Panel", t: 6, core: "Leather", edge: nil, grain: .none),
            FurniturePartTypes.sheet(.furniturePanels, "Panel", "1/4\" Mirror", t: 0.25, core: "Mirror", edge: nil, grain: .none),
            FurniturePartTypes.sheet(.furniturePanels, "Panel", "1/4\" Glass Panel", t: 0.25, core: "Glass", edge: nil, grain: .none),
            FurniturePartTypes.sheet(.furniturePanels, "Panel", "1\" Solid Oak", t: 1, core: "Solid Oak", edge: nil),
            FurniturePartTypes.sheet(.furniturePanels, "Panel", "1/8\" Steel Plate", t: 0.125, core: "Steel", edge: nil, grain: .none),
            FurniturePartTypes.sheet(.furnitureShelves, "Shelf", "3/4\" Solid Walnut Shelf", t: 0.75, core: "Solid Walnut", edge: nil),
            FurniturePartTypes.sheet(.furnitureShelves, "Shelf", "1/8\" Steel Shelf", t: 0.125, core: "Steel", edge: nil, grain: .none),
            FurniturePartTypes.sheet(.furnitureShelves, "Shelf", "1\" Solid Pine Shelf", t: 1, core: "Solid Pine", edge: nil),
            FurniturePartTypes.sheet(.furnitureShelves, "Top", "1\" Solid Ash Top", t: 1, core: "Solid Ash", edge: nil, texts: [FurniturePartTypes.topEdge: TopEdge.roundOver.rawValue]),
            FurniturePartTypes.sheet(.furnitureShelves, "Top", "1\" Solid Maple Top", t: 1, core: "Solid Maple", edge: nil, texts: [FurniturePartTypes.topEdge: TopEdge.roundOver.rawValue]),
            FurniturePartTypes.sheet(.furnitureShelves, "Top", "1/2\" Glass Top", t: 0.5, core: "Glass", edge: nil, grain: .none, texts: [FurniturePartTypes.topEdge: TopEdge.square.rawValue]),
            FurniturePartTypes.sheet(.furnitureShelves, "Top", "1 1/4\" Quartz Top", t: 1.25, core: "Quartz - White", edge: nil, grain: .none,
                                     texts: [FurniturePartTypes.topEdge: TopEdge.square.rawValue]),
            FurniturePartTypes.leg("Square 2 1/2\" Post", .square, w: 2.5, material: "Solid Oak"),
            FurniturePartTypes.leg("Square 3 1/2\" Post", .square, w: 3.5, material: "Solid Pine"),
            FurniturePartTypes.leg("Square 1\" Steel", .square, w: 1, material: "Steel"),
            FurniturePartTypes.leg("Round 1\" Steel", .round, w: 1, material: "Steel"),
            FurniturePartTypes.leg("Round 2\" Steel", .round, w: 2, material: "Steel"),
            FurniturePartTypes.leg("Square 2 1/2\" Steel", .square, w: 2.5, material: "Steel"),
            FurniturePartTypes.leg("Round 1 1/4\"", .round, w: 1.25, material: "Solid Maple"),
            FurniturePartTypes.leg("Square 1 1/4\"", .square, w: 1.25, material: "Solid Oak"),
            FurniturePartTypes.leg("Square 2\" Walnut", .square, w: 2, material: "Solid Walnut"),
            FurniturePartTypes.leg("Square 1 3/4\" x 3/4\"", .square, w: 1.75, d: 0.75, material: "Solid Oak"),
            FurniturePartTypes.rail("1\" Round Steel Rail", w: 1, h: 1, profile: .round, material: "Steel"),
            FurniturePartTypes.rail("1 1/4\" Closet Rod", w: 1.25, h: 1.25, profile: .round, material: "Steel"),
            FurniturePartTypes.rail("1 1/4\" Round Rung", w: 1.25, h: 1.25, profile: .round, material: "Solid Ash"),
            FurniturePartTypes.rail("3/4\" Dowel Rod", w: 0.75, h: 0.75, profile: .round, material: "Solid Maple"),
            FurniturePartTypes.rail("1\" x 1\" Steel Tube", w: 1, h: 1, material: "Steel"),
            FurniturePartTypes.rail("1 1/2\" x 5 1/2\" Bed Rail", w: 1.5, h: 5.5, material: "Solid Pine"),
            FurniturePartTypes.rail("3/4\" x 5\" Rail", w: 0.75, h: 5),
            FurniturePartTypes.rail("3/4\" x 1 1/2\" Steel Bar", w: 0.75, h: 1.5, material: "Steel"),
        ]

        static func cushion(_ name: String, _ t: Double, _ cover: String = "Fabric") -> FurniturePartTypes.Spec {
            FurniturePartTypes.sheet(.furnitureShelves, "Top", name, t: t, core: cover, edge: nil, grain: .none, texts: [FurniturePartTypes.topEdge: TopEdge.bullnose.rawValue])
        }

        /// Creates the extra types where missing (idempotent), and the library palette's materials they use.
        static func ensureTypes(in tx: TransactionContext) {
            FurniturePartTypes.ensureStandard(in: tx)
            for name in Set((extraTypes + SA.Wood.extraTypes).flatMap { $0.materials.values }).sorted() { _ = material(name, in: tx) }
            let materials = Dictionary(tx.model.elements(.materials).map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
            let existing = Set(tx.model.elements(.elementTypes).compactMap { t -> String? in
                guard let td = t.typeData, td.instanceCategory.isFurniturePart else { return nil }
                return "\(td.instanceCategory.rawValue)|\(t.name)"
            })
            for spec in extraTypes + SA.Wood.extraTypes where !existing.contains("\(spec.category.rawValue)|\(spec.name)") {
                var params: [ParameterID: ParamValue] = [:]
                for (k, v) in spec.numbers { params[k] = .double(v) }
                for (k, v) in spec.texts { params[k] = .text(v) }
                for (k, v) in spec.materials { params[k] = .ref(materials[v]) }
                tx.create(.elementTypes, name: spec.name, data: .type(TypeData(instanceCategory: spec.category, familyName: spec.family, params: params)))
            }
        }

        /// A material by name: the document's, else made from the library palette (LibraryKit.palette) the batches share.
        @discardableResult
        static func material(_ name: String, in tx: TransactionContext) -> ElementID? {
            if let id = tx.model.elements(.materials).first(where: { $0.name == name })?.id { return id }
            guard let spec = LibraryKit.palette.first(where: { $0.name == name }) else { return nil }
            var md = MaterialData(materialClass: spec.materialClass, color: RGBColor(hex: spec.color), transparency: spec.transparency, description: spec.description)
            MaterialPatternDefaults.apply(to: &md, name: spec.name, patterns: MaterialPatternDefaults.patternIndex(tx.model))
            md.cost = spec.cost
            md.costUnit = spec.unit
            return tx.create(.materials, name: spec.name, data: .material(md))
        }

        /// A part type in another material: a copy of `name` named "<name> (<material>)", as Duplicate in Edit Type
        /// makes it, once per document (the type itself when it already is that material).
        func type(_ cat: Category, _ name: String, material: String?) throws -> String {
            let base = try type(cat, name)
            guard let material, let mid = Self.material(material, in: tx), model[base]?.typeData?.params[FurniturePartTypes.coreMaterial]?.refValue != mid else { return name }
            let copy = "\(name) (\(material))"
            if model.types(for: cat).contains(where: { $0.name == copy }) { return copy }
            guard var td = model[base]?.typeData else { return name }
            td.params[FurniturePartTypes.coreMaterial] = .ref(mid)
            td.params[FurniturePartTypes.faceMaterial] = nil
            tx.create(.elementTypes, name: copy, data: .type(td))
            return copy
        }

        /// A form (cushion, rocker, bowl, void) that follows the planes as `lock` says.
        @discardableResult
        func form(_ fd: FurnitureFormData, material: String?, lock: FormLock?) throws -> ElementID {
            var fd = fd
            fd.materialID = material.flatMap { Self.material($0, in: tx) }
            fd.lock = lock
            return try FurniturePartOperations.createForm(fd, in: tx)
        }

        func type(_ cat: Category, _ name: String) throws -> ElementID {
            guard let id = model.types(for: cat).first(where: { $0.name == name })?.id else { throw TransactionError("No \(cat.singularName) type named “\(name)”.") }
            return id
        }

        func thickness(_ panelOrShelfType: ElementID) -> Double { FurniturePartTypes.Values(model[panelOrShelfType]?.typeData).thickness }

        func setBounds(_ id: ElementID, _ b: [String: FurnitureBound]) {
            tx.update(id) { e in
                var all = FurniturePartBounds.bounds(of: e)
                for (k, v) in b { all[k] = v }
                FurniturePartBounds.setBounds(all, of: &e)
            }
        }

        func extent(_ z: (SA.LP, SA.LP)) -> PartExtent { PartExtent(basePlane: z.0.plane, baseOffset: z.0.offset, topPlane: z.1.plane, topOffset: z.1.offset) }

        // MARK: Parts

        /// A panel standing across X (a side): one face on `x`, the panel `toward` +X (1) or -X (-1) from it, running from
        /// `y.0` to `y.1` and from `z.0` up to `z.1`.
        @discardableResult
        func sideX(_ x: SA.LP, toward dir: Double, y: (SA.LP, SA.LP), z: (SA.LP, SA.LP), _ typeName: String = SA.ply, role: FurniturePartKind = .panel) throws -> ElementID {
            let t = try type(.furniturePanels, typeName)
            let c = x + dir * thickness(t) / 2 / SA.inch
            // The outside face is on the left of the drawing direction: a +X panel (left side) runs front to back.
            let (y0, y1) = dir > 0 ? (y.0, y.1) : (y.1, y.0)
            let id = try FurniturePartOperations.createPanel(start: Vec2(v(c), v(y0)), end: Vec2(v(c), v(y1)), locationLine: .centerline, extent: extent(z), role: role, typeID: t, in: tx)
            setBounds(id, ["start.u": bound(c), "end.u": bound(c), "start.v": bound(y0), "end.v": bound(y1), "base": bound(z.0), "top": bound(z.1)])
            return id
        }

        /// A panel standing across Y (a back, front rail or apron): one face on `y`, the panel `toward` +Y or -Y from it.
        @discardableResult
        func sideY(_ y: SA.LP, toward dir: Double, x: (SA.LP, SA.LP), z: (SA.LP, SA.LP), _ typeName: String = SA.ply, role: FurniturePartKind = .panel) throws -> ElementID {
            let t = try type(.furniturePanels, typeName)
            let c = y + dir * thickness(t) / 2 / SA.inch
            // A -Y panel (a back) runs left to right so its outside faces the back.
            let (x0, x1) = dir < 0 ? (x.0, x.1) : (x.1, x.0)
            let id = try FurniturePartOperations.createPanel(start: Vec2(v(x0), v(c)), end: Vec2(v(x1), v(c)), locationLine: .centerline, extent: extent(z), role: role, typeID: t, in: tx)
            setBounds(id, ["start.u": bound(x0), "end.u": bound(x1), "start.v": bound(c), "end.v": bound(c), "base": bound(z.0), "top": bound(z.1)])
            return id
        }

        /// A horizontal board (shelf, top, bottom, seat, cushion): the rectangle `x` × `y`, its top face on `top`.
        @discardableResult
        func board(x: (SA.LP, SA.LP), y: (SA.LP, SA.LP), top: SA.LP, _ typeName: String = SA.plyShelf, role: FurniturePartKind = .shelf, adjustable: Bool = false) throws -> ElementID {
            try polygon([(x.0, y.0), (x.1, y.0), (x.1, y.1), (x.0, y.1)], top: top, typeName, role: role, adjustable: adjustable)
        }

        /// An octagonal board (stool seats, round-looking tops): the rectangle `x` × `y` with its corners cut `cut` inches.
        @discardableResult
        func octagon(x: (SA.LP, SA.LP), y: (SA.LP, SA.LP), cut: Double, top: SA.LP, _ typeName: String, role: FurniturePartKind = .top) throws -> ElementID {
            try polygon([(x.0 + cut, y.0), (x.1 - cut, y.0), (x.1, y.0 + cut), (x.1, y.1 - cut), (x.1 - cut, y.1), (x.0 + cut, y.1), (x.0, y.1 - cut), (x.0, y.0 + cut)],
                        top: top, typeName, role: role)
        }

        /// A horizontal board of any outline (corner shelves, L-shaped seats), each point on its planes.
        @discardableResult
        func polygon(_ pts: [(SA.LP, SA.LP)], top: SA.LP, _ typeName: String = SA.plyShelf, role: FurniturePartKind = .shelf, adjustable: Bool = false) throws -> ElementID {
            let t = try type(.furnitureShelves, typeName)
            let id = try FurniturePartOperations.createShelf(boundary: pts.map { Vec2(v($0.0), v($0.1)) }, plane: top.plane, offset: top.offset, role: role,
                                                             adjustable: adjustable, typeID: t, in: tx)
            guard let s = model[id]?.furnitureShelf else { return id }
            // The loop is stored counterclockwise and simplified: each stored point takes the bounds of the point it came from.
            var b: [String: FurnitureBound] = ["z": bound(top)]
            for (i, p) in s.boundary.enumerated() {
                guard let src = pts.min(by: { Vec2(v($0.0), v($0.1)).distance(to: p) < Vec2(v($1.0), v($1.1)).distance(to: p) }) else { continue }
                b["p\(i).x"] = bound(src.0); b["p\(i).y"] = bound(src.1)
            }
            setBounds(id, b)
            return id
        }

        /// A leg (or post) centred on (`x`, `y`) from `z.0` up to `z.1`.
        @discardableResult
        func leg(_ x: SA.LP, _ y: SA.LP, z: (SA.LP, SA.LP), _ typeName: String = SA.sq) throws -> ElementID {
            let t = try type(.furnitureLegs, typeName)
            let id = try FurniturePartOperations.createLeg(at: Vec2(v(x), v(y)), extent: extent(z), typeID: t, in: tx)
            setBounds(id, ["x": bound(x), "y": bound(y), "base": bound(z.0), "top": bound(z.1)])
            return id
        }

        /// Four legs, one in each corner of `x` × `y` (centres `inset` inches in from the corners' faces).
        @discardableResult
        func legs(x: (SA.LP, SA.LP), y: (SA.LP, SA.LP), inset: Double, z: (SA.LP, SA.LP), _ typeName: String = SA.sq) throws -> [ElementID] {
            var ids: [ElementID] = []
            for xx in [x.0 + inset, x.1 - inset] { for yy in [y.0 + inset, y.1 - inset] { ids.append(try leg(xx, yy, z: z, typeName)) } }
            return ids
        }

        /// A rail along X at `y` (its centre line), its top on `top`.
        @discardableResult
        func railX(_ x: (SA.LP, SA.LP), y: SA.LP, top: SA.LP, _ typeName: String = SA.apron) throws -> ElementID {
            let t = try type(.furnitureRails, typeName)
            let id = try FurniturePartOperations.createRail(start: Vec2(v(x.0), v(y)), end: Vec2(v(x.1), v(y)), w: v(top), justification: .top, typeID: t, in: tx)
            setBounds(id, ["start.u": bound(x.0), "end.u": bound(x.1), "start.v": bound(y), "end.v": bound(y), "w": bound(top)])
            return id
        }

        /// A rail along Y at `x` (its centre line), its top on `top`.
        @discardableResult
        func railY(_ y: (SA.LP, SA.LP), x: SA.LP, top: SA.LP, _ typeName: String = SA.apron) throws -> ElementID {
            let t = try type(.furnitureRails, typeName)
            let id = try FurniturePartOperations.createRail(start: Vec2(v(x), v(y.0)), end: Vec2(v(x), v(y.1)), w: v(top), justification: .top, typeID: t, in: tx)
            setBounds(id, ["start.u": bound(x), "end.u": bound(x), "start.v": bound(y.0), "end.v": bound(y.1), "w": bound(top)])
            return id
        }

        /// Aprons round a table: rails between four legs inset `inset` (to the legs' centres), their tops on `top`. The rails
        /// run between the legs' faces, centred on them.
        func aprons(x: (SA.LP, SA.LP), y: (SA.LP, SA.LP), inset: Double, legWidth: Double, top: SA.LP, _ typeName: String = SA.apron, sides: Set<String> = ["F", "B", "L", "R"]) throws {
            let hw = legWidth / 2
            let xs = (x.0 + (inset + hw), x.1 - (inset + hw)), ys = (y.0 + (inset + hw), y.1 - (inset + hw))
            if sides.contains("F") { try railX(xs, y: y.0 + inset, top: top, typeName) }
            if sides.contains("B") { try railX(xs, y: y.1 - inset, top: top, typeName) }
            if sides.contains("L") { try railY(ys, x: x.0 + inset, top: top, typeName) }
            if sides.contains("R") { try railY(ys, x: x.1 - inset, top: top, typeName) }
        }

        // MARK: Carcass picks (after the carcass is committed)

        /// Dividers splitting the bay round (`x`, `z`) into equal spaces (EQ): vertical between bottom and top, or
        /// horizontal (fixed shelves) between the sides.
        @discardableResult
        func dividers(at x: SA.LP, _ z: SA.LP, vertical: Bool, count: Int, _ typeName: String = SA.ply, setback: Double = 0) throws -> [ElementID] {
            try FurniturePartOperations.createDividers(atFront: Vec2(v(x), v(z)), vertical: vertical, count: count, setback: setback * SA.inch,
                                                       typeID: try type(.furniturePanels, typeName), in: tx)
        }

        /// A bay round (`x`, `z`) seen from the front.
        @discardableResult
        func bay(_ x: SA.LP, _ z: SA.LP) throws -> ElementID { try FurnitureBays.createBay(face: .front, at: Vec2(v(x), v(z)), in: tx) }

        /// A bay seen from above round (`x`, `y`) (a lid's opening).
        @discardableResult
        func topBay(_ x: SA.LP, _ y: SA.LP) throws -> ElementID { try FurnitureBays.createBay(face: .top, at: Vec2(v(x), v(y)), in: tx) }

        func frontType(_ kind: FrontKind, _ name: String) throws -> ElementID {
            guard let id = model.types(for: .furnitureFronts).first(where: { $0.typeData?.familyName == kind.rawValue && $0.name == name })?.id else {
                throw TransactionError("No \(kind.rawValue.lowercased()) type named “\(name)”.")
            }
            return id
        }

        /// A front type in the piece's material: a copy of the standard type named "<type> (<material>)", as Duplicate in
        /// Edit Type makes it, once per document (the standard type itself when it already is that material).
        func frontType(_ kind: FrontKind, _ name: String, material: String?) throws -> ElementID {
            let base = try frontType(kind, name)
            guard let material, let mid = Self.material(material, in: tx),
                  model[base]?.typeData?.params[FurniturePartTypes.coreMaterial]?.refValue != mid else { return base }
            let copy = "\(name) (\(material))"
            if let id = model.types(for: .furnitureFronts).first(where: { $0.typeData?.familyName == kind.rawValue && $0.name == copy })?.id { return id }
            guard var td = model[base]?.typeData else { return base }
            td.params[FurniturePartTypes.coreMaterial] = .ref(mid)
            // A shaker or louvered front's panel is the same material; a glass panel stays glass.
            if FurnitureFrontTypes.Values(td).style != .glass { td.params[FurnitureFrontTypes.panelMaterial] = .ref(mid) }
            return tx.create(.elementTypes, name: copy, data: .type(td))
        }

        /// A door in the bay round (`x`, `z`).
        @discardableResult
        func door(_ x: SA.LP, _ z: SA.LP, _ typeName: String = SA.slabDoor, material: String? = nil, hingeRight: Bool = false) throws -> [ElementID] {
            try FurnitureFronts.createFront(.door, in: try bay(x, z), typeID: try frontType(.door, typeName, material: material), hingeFlipped: hingeRight, in: tx)
        }

        /// A stack of `count` equal drawers (EQ) in the bay round (`x`, `z`).
        @discardableResult
        func drawers(_ x: SA.LP, _ z: SA.LP, count: Int, _ typeName: String = SA.slabDrawer, material: String? = nil) throws -> [ElementID] {
            try FurnitureFronts.createDrawers(in: try bay(x, z), count: count, typeID: try frontType(.drawer, typeName, material: material), in: tx)
        }

        /// Drawers side by side: the bay round (`x`, `z`) divided into `count` equal columns (EQ), a drawer in each.
        @discardableResult
        func drawerColumns(_ x: SA.LP, _ z: SA.LP, count: Int, _ typeName: String = SA.slabDrawer, material: String? = nil) throws -> [ElementID] {
            let bay = try bay(x, z)
            try FurnitureBays.divide(bay, BayDivision(direction: .columns, count: count), in: tx)
            return try FurnitureFronts.createFront(.drawer, in: bay, typeID: try frontType(.drawer, typeName, material: material), in: tx)
        }

        /// Doors side by side: the bay round (`x`, `z`) divided into `count` equal columns (EQ), a door in each, the left
        /// half hinged left and the right half hinged right.
        @discardableResult
        func doors(_ x: SA.LP, _ z: SA.LP, count: Int, _ typeName: String = SA.slabDoor, material: String? = nil) throws -> [ElementID] {
            try doors(in: try bay(x, z), count: count, typeName, material: material)
        }

        @discardableResult
        func doors(in bay: ElementID, count: Int, _ typeName: String, material: String?) throws -> [ElementID] {
            if count > 1 { try FurnitureBays.divide(bay, BayDivision(direction: .columns, count: count), in: tx) }
            let cells = count > 1 ? FurnitureBays.cellIDs(of: bay, model) : [bay]
            var ids: [ElementID] = []
            let type = try frontType(.door, typeName, material: material)
            for (k, cell) in cells.enumerated() {
                ids += try FurnitureFronts.createFront(.door, in: cell, typeID: type, hingeFlipped: k >= (count + 1) / 2, in: tx)
            }
            return ids
        }

        /// A flap in the bay round (`x`, `z`) (drop-down desk fronts, lift-up wall cabinets).
        @discardableResult
        func flap(_ x: SA.LP, _ z: SA.LP, _ typeName: String = SA.dropDown, material: String? = nil) throws -> [ElementID] {
            try FurnitureFronts.createFront(.flap, in: try bay(x, z), typeID: try frontType(.flap, typeName, material: material), in: tx)
        }

        /// A lid on the top opening round (`x`, `y`).
        @discardableResult
        func lid(_ x: SA.LP, _ y: SA.LP, _ typeName: String = SA.liftUp, material: String? = nil) throws -> [ElementID] {
            try FurnitureFronts.createFront(.flap, in: try topBay(x, y), typeID: try frontType(.flap, typeName, material: material), in: tx)
        }
    }
}
