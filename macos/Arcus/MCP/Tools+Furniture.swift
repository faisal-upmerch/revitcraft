import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// MCP: Furniture mode tools: piece size and the part tools on main (Panel, Shelf/Top/Bottom, Back, Divider, Leg,
// Legs At Corners, Rail, Slats, Plinth, Edge Profile, Groove), through FurniturePartOperations like the ribbon tools.

extension ArcusToolbox {
    func requireFurniture(_ c: ToolContext) throws(ToolError) -> BIMModel {
        let m = try c.model()
        guard m.isFurniture else { throw ToolError("This is a building project. Furniture parts go in a Furniture document: create_furniture first.") }
        return m
    }

    func setFurnitureSize(_ c: ToolContext) throws -> ToolOutput {
        let m = try requireFurniture(c)
        var values: [(String, Double)] = []
        for k in ["width", "depth", "height"] {
            guard let v = try c.length(k) else { continue }
            guard v > 0.0127 else { throw ToolError("\(k) must be at least 1/2\".") }
            values.append((k.capitalized, v))
        }
        guard !values.isEmpty else { throw ToolError("Give width, depth and/or height.") }
        try c.edit("Furniture Size") { tx in for (n, v) in values { try FurnitureParameters.setValue(n, .double(v), in: tx) } }
        let nm = try c.model()
        var size: [String: JSONValue] = [:]
        for n in ["Width", "Depth", "Height"] { if let v = FurnitureParameters.value(n, nm)?.quantityValue { size[n.lowercased()] = c.out(v, nm) } }
        _ = m
        return result(c, ["size": .object(size), "planes": .object(FurniturePlanes.positionsByName(nm).mapValues { c.out($0, nm) })], ids: [])
    }

    /// Parses an edge like "front_top" into a part edge: the two named sides fix the cross axes, the edge runs along the third.
    static func edge(_ s: String) throws(ToolError) -> PartEdge {
        let words = Set(s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        var side: [FamilyAxis: Bool] = [:]
        for w in words {
            switch w {
            case "left": side[.x] = false
            case "right": side[.x] = true
            case "front": side[.y] = false
            case "back", "rear": side[.y] = true
            case "bottom": side[.z] = false
            case "top": side[.z] = true
            default: throw ToolError("edge “\(s)”: use two of front/back, left/right, top/bottom, e.g. front_top.")
            }
        }
        guard side.count == 2, let axis = [FamilyAxis.x, .y, .z].first(where: { side[$0] == nil }) else {
            throw ToolError("edge “\(s)” must name two sides on different axes, e.g. front_top or left_back.")
        }
        let e = PartEdge(axis: axis, firstAtMax: false, secondAtMax: false)
        let (a, b) = e.across
        return PartEdge(axis: axis, firstAtMax: side[a] ?? false, secondAtMax: side[b] ?? false)
    }

    func addFurnitureParts(_ c: ToolContext) throws -> ToolOutput {
        var m = try requireFurniture(c)
        if m.types(for: .furniturePanels).isEmpty { try c.edit("Part Types") { tx in FurniturePartTypes.ensureStandard(in: tx) }; m = try c.model() }
        let parts = try c.args.requireArray("parts")
        var refs: [String: ElementID] = [:]
        var made: [JSONValue] = []
        var allIDs: [ElementID] = []
        let inch = 0.0254
        for (k, p) in parts.enumerated() {
            let what = "parts[\(k)]"
            let kind = (p["kind"]?.stringValue ?? "").lowercased()
            m = try c.model()
            let planes = FurniturePlanes.positionsByName(m)
            let L = planes["Left"] ?? -0.45, R = planes["Right"] ?? 0.45, F = planes["Front"] ?? -0.23, B = planes["Back"] ?? 0.23
            let H = (planes["Top"] ?? 0.76) - (planes["Bottom"] ?? 0)
            func len(_ key: String) throws -> Double? { try p[key].map { try c.length($0, "\(what).\(key)") } }
            func pt(_ key: String) throws -> Vec2? { try p[key].map { try c.point($0, "\(what).\(key)") } }
            func host(_ key: String = "host") throws -> ElementID {
                guard let v = p[key] else { throw ToolError("\(what) needs \(key) (a ref from an earlier part or an id).") }
                if let s = v.stringValue, let id = refs[s] { return id }
                return try c.element(v, "\(what).\(key)").id
            }
            func type(_ cat: Category, _ pick: (([Element]) -> Element?)? = nil) throws -> ElementID? {
                if p["type"] == nil, pick == nil { return nil }
                return try c.type(p["type"], category: cat, what: "\(what).type", default: pick).id
            }
            func extent() throws -> PartExtent {
                let base = try len("base") ?? 0
                if let top = try len("top") { return PartExtent(basePlane: "Bottom", baseOffset: base, topPlane: "Bottom", topOffset: top, height: top - base) }
                return PartExtent(basePlane: "Bottom", baseOffset: base, topPlane: "Top", topOffset: 0, height: H - base)
            }
            /// Inside faces of the sides (x), when sides exist.
            func inside() -> (Double, Double) {
                var lo = L, hi = R
                for e in m.elements(.furniturePanels) {
                    guard let b = FurniturePartSolids.partBox(e, m)?.box, b.max.x - b.min.x < 2.1 * inch, b.max.y - b.min.y > 2 * inch else { continue }
                    if abs(b.min.x - L) < 0.003 { lo = max(lo, b.max.x) }
                    if abs(b.max.x - R) < 0.003 { hi = min(hi, b.min.x) }
                }
                return (lo, hi)
            }
            var ids: [ElementID] = []
            let r: TransactionRecord?
            switch kind {
            case "panel", "side", "divider_panel":
                guard let s = try pt("start"), let e = try pt("end") else { throw ToolError("\(what): a panel needs start and end plan points.") }
                let ext = try extent(), t = try type(.furniturePanels)
                r = try c.edit("Panel") { tx in ids = [try FurniturePartOperations.createPanel(start: s, end: e, extent: ext, typeID: t, in: tx)] }
            case "sides":
                let ext = try extent(), t = try type(.furniturePanels)
                r = try c.edit("Sides") { tx in
                    ids = [try FurniturePartOperations.createPanel(start: Vec2(L, F), end: Vec2(L, B), extent: ext, typeID: t, in: tx),
                           try FurniturePartOperations.createPanel(start: Vec2(R, B), end: Vec2(R, F), extent: ext, typeID: t, in: tx)]
                }
            case "shelf", "top", "bottom":
                let role: FurniturePartKind = kind == "top" ? .top : kind == "bottom" ? .bottom : .shelf
                let boundary: [Vec2]
                if let bv = p["boundary"] { boundary = try c.points(bv, what + ".boundary", min: 3) } else {
                    let (lo, hi) = role == .top && p["over_sides"]?.boolValue == true ? (L, R) : inside()
                    boundary = [Vec2(lo, F), Vec2(hi, F), Vec2(hi, B), Vec2(lo, B)]
                }
                let atTop = role == .top && p["z"] == nil || p["at"]?.stringValue == "top"
                let z = try len("z") ?? 0
                let t = try type(.furnitureShelves) { ts in ts.first { $0.typeData?.familyName == (role == .top ? "Top" : "Shelf") } }
                let adjustable = p["adjustable"]?.boolValue ?? false, setback = try len("front_setback") ?? 0
                r = try c.edit(role.rawValue) { tx in
                    ids = [try FurniturePartOperations.createShelf(boundary: boundary, plane: atTop ? "Top" : "Bottom", offset: atTop ? 0 : z, role: role,
                                                                   adjustable: adjustable, frontSetback: setback, typeID: t, in: tx)]
                }
            case "back":
                let at = try pt("at") ?? Vec2((L + R) / 2, H / 2)
                let fit: BackIntent.Fit = p["fit"]?.stringValue?.lowercased().contains("overlay") == true ? .fullOverlay : .inside
                let t = try type(.furniturePanels)
                r = try c.edit("Back") { tx in ids = [try FurniturePartOperations.createBack(atFront: at, fit: fit, typeID: t, in: tx)] }
            case "divider", "dividers":
                let at = try pt("at") ?? Vec2((L + R) / 2, H / 2)
                let vertical = p["vertical"]?.boolValue ?? true, count = p["count"]?.intValue ?? 1, setback = try len("setback") ?? 0
                let t = try type(.furniturePanels)
                r = try c.edit("Divider") { tx in ids = try FurniturePartOperations.createDividers(atFront: at, vertical: vertical, count: count, setback: setback, typeID: t, in: tx) }
            case "leg":
                guard let at = try pt("point") else { throw ToolError("\(what): a leg needs point [x, y].") }
                let ext = try extent(), t = try type(.furnitureLegs)
                r = try c.edit("Leg") { tx in ids = [try FurniturePartOperations.createLeg(at: at, extent: ext, typeID: t, in: tx)] }
            case "legs_at_corners", "legs":
                let h = try host(), inset = try len("inset") ?? 2 * inch, t = try type(.furnitureLegs)
                r = try c.edit("Legs") { tx in ids = try FurniturePartOperations.legsAtCorners(of: h, inset: inset, typeID: t, in: tx) }
            case "rail", "apron", "stretcher":
                guard let s = try pt("start"), let e = try pt("end") else { throw ToolError("\(what): a rail needs start and end plan points.") }
                guard let z = try len("z") else { throw ToolError("\(what): a rail needs z, the height of its top above Bottom.") }
                let t = try type(.furnitureRails)
                r = try c.edit("Rail") { tx in ids = [try FurniturePartOperations.createRail(start: s, end: e, w: z, wPlane: "Bottom", justification: .top, typeID: t, in: tx)] }
            case "slats":
                guard let rv = p["rect"], let corners = Optional(try c.points(rv, what + ".rect")), corners.count == 2 else { throw ToolError("\(what): slats need rect [[x0,y0],[x1,y1]].") }
                guard let z = try len("z") else { throw ToolError("\(what): slats need z (top of the slats above Bottom).") }
                let along = (p["along"]?.stringValue ?? "x").lowercased() != "y"
                let number = p["number"]?.intValue
                let spacing = try len("spacing") ?? 3 * inch
                let t = try type(.furnitureRails)
                r = try c.edit("Slats") { tx in
                    ids = [try FurniturePartOperations.createSlats(in: Rect2(points: corners), alongX: along, rule: number == nil ? .fixedDistance : .fixedNumber,
                                                                   spacing: spacing, number: number ?? 0, z: z, zPlane: "Bottom", typeID: t, in: tx)]
                }
            case "plinth", "kick":
                let h = try host(), setback = try len("setback") ?? 3 * inch, height = try len("height"), t = try type(.furniturePanels)
                r = try c.edit("Plinth") { tx in ids = [try FurniturePartOperations.createPlinth(under: h, setback: setback, height: height, typeID: t, in: tx)] }
            case "edge_profile", "groove":
                let h = try host()
                let edge = try Self.edge(p["edge"]?.stringValue ?? "front_top")
                let offset = try len("offset") ?? 0, t = try type(.furnitureEdgeProfiles)
                r = try c.edit(kind == "groove" ? "Groove" : "Edge Profile") { tx in
                    ids = [try FurniturePartOperations.createEdgeProfile(on: h, edge: edge, groove: kind == "groove", offset: offset, typeID: t, in: tx)]
                }
            default:
                throw ToolError("\(what): unknown kind “\(kind)”. Kinds: panel, sides, shelf, top, bottom, back, divider, leg, legs_at_corners, rail, slats, plinth, edge_profile, groove.")
            }
            _ = r
            if let ref = p["ref"]?.stringValue, let first = ids.first { refs[ref] = first }
            allIDs += ids
            let nm = try c.model()
            made.append(["kind": .string(kind), "ref": p["ref"] ?? .null, "ids": .array(ids.map(\.json)),
                         "type": .string(ids.first.flatMap { nm[$0] }.flatMap { nm.type(of: $0) }.map { ToolContext.typeLabel($0, nm) } ?? "")])
        }
        let nm = try c.model()
        let box = Self.furnitureBox(nm)
        var o: [String: JSONValue] = ["parts": .array(made)]
        if let b = box { o["overall"] = [c.out(b.max.x - b.min.x, nm), c.out(b.max.y - b.min.y, nm), c.out(b.max.z - b.min.z, nm)] }
        return result(c, o, ids: allIDs)
    }
}
