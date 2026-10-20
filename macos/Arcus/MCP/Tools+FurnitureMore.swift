import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication

// AITOOLS: Furniture mode beyond parts: bays and Bay Divide, doors/drawers/flaps, one-click hardware, joints and Joint
// Rules, the Component Library (search, place, replace, assemblies), stock sheets, fabrication reports, shop drawings,
// parameters/types/formulas, flex, and the Furniture Library. Each furniture edit is flexed and part-checked in its
// verification block.

extension ArcusToolCatalog {
    static let inchNote = "Furniture lengths are inches (numbers) or text like 1'-6\". Front points are [x, z]: x across (Left −W/2 … Right +W/2), z up from Bottom."
    static let furnitureTools: [ToolSpec] = [
        ToolSpec("add_bays", "Bay", "Place bays (front openings bounded by parts, like rooms) at front points [x, z], or auto: one in every opening of the front; optionally divide each into rows (drawer stack) or columns. " + inchNote,
                 risk: .edit, group: .furniture, modes: .furniture,
                 properties: ["points": S.points("[[x, z], …] inside openings"), "auto": S.bool(), "face": S.oneOf(["front", "top"], "Default front"),
                              "divide": S.oneOf(["rows", "columns"]), "count": S.int("Cells for divide")]),
        ToolSpec("add_fronts", "Door/Drawer/Flap", "Put doors, drawers (count: a drawer stack) or flaps in bays (ids, or all bays without a front). hinge: left or right for doors; type: front type name (Slab, Shaker…).",
                 risk: .edit, group: .furniture, modes: .furniture,
                 properties: ["kind": S.oneOf(["door", "drawer", "flap"]), "bays": S.ids("Default all empty bays"), "count": S.int("Drawers per bay"), "hinge": S.oneOf(["left", "right"]), "type": S.ref()],
                 required: ["kind"]),
        ToolSpec("add_hardware", "One-Click Hardware", "Add hardware to fronts or bays in one step: handle, hinges, lock, soft_close, push_to_open, slides, organizer, hanging_rod, shoe_rack, lighting, sliding_system. Picks the component that fits each host; returns what it placed and its notes. " + selNote,
                 risk: .edit, group: .furniture, modes: .furniture,
                 properties: ["elements": S.ids("Fronts or bays (default every front)"), "action": S.oneOf(["handle", "hinges", "lock", "soft_close", "push_to_open", "slides", "organizer", "hanging_rod", "shoe_rack", "lighting", "sliding_system"])],
                 required: ["action"]),
        ToolSpec("set_joint", "Joint", "Set the joint between two touching parts (butt, miter, dado, rabbet, groove, dowel, cam_lock, pocket_screw, mortise_tenon, confirmat, biscuit), which part runs through, or reset to the rule. list: show every joint.",
                 risk: .edit, group: .furniture, modes: .furniture,
                 properties: ["parts": S.ids("Two part ids"), "type": S.str(), "through": S.int("The part that runs through"), "reset": S.bool(), "list": S.bool()]),
        ToolSpec("set_joint_rules", "Joint Rules", "Change Joint Rules (which joint each pair kind gets): pairs side_top, side_bottom, side_side, side_back, shelf_side, shelf_back, divider_shelf, plinth_carcass, rail_leg, rail_panel, rail_top, top_leg, slat_frame, other.",
                 risk: .projectWide, group: .furniture, modes: .furniture,
                 properties: ["rules": S.array(S.object(["pair": S.str(), "type": S.str(), "through": S.oneOf(["first", "second"])], required: ["pair", "type"]))], required: ["rules"]),
        ToolSpec("search_components", "Search Components", "Search the Component Library (435 hardware, legs, kitchen, lighting, mechanism… families) by words, sizes or synonyms; filter by host kind.",
                 risk: .read, group: .furniture, modes: .model,
                 properties: ["query": S.str(), "host": S.str("door, drawer_front, bay, top, shelf, side_panel…"), "limit": S.int("Default 12")], required: ["query"]),
        ToolSpec("place_library_component", "Place Component", "Place a Component Library component (name or id) with a type on a host part/front (placed where it belongs) or at a point. " + inchNote,
                 risk: .edit, group: .furniture, modes: .model,
                 properties: ["component": S.str(), "type": S.str(), "host": S.int("Front, bay or part id"), "point": S.point("[x, y] plan point when no host"), "z": S.len()],
                 required: ["component"]),
        ToolSpec("replace_components", "Replace Component", "Replace placed components with another component (keeps placement and host). " + selNote,
                 risk: .edit, group: .furniture, modes: .model, properties: ["elements": S.ids(), "component": S.str(), "type": S.str()], required: ["component"]),
        ToolSpec("insert_assembly", "Assembly", "Insert an assembly preset into a bay: e.g. Drawer Stack (3), Wardrobe Interior, Kitchen Base… (list with list: true).",
                 risk: .edit, group: .furniture, modes: .furniture, properties: ["assembly": S.str(), "bay": S.int(), "list": S.bool()]),
        ToolSpec("set_stock_sheets", "Stock Sheets", "Stock sheet sizes for nesting (default 4'×8'), kerf and edge trim, rotation. " + inchNote,
                 risk: .projectWide, group: .furniture, modes: .furniture,
                 properties: ["sizes": S.array(S.object(["name": S.str(), "length": S.len(), "width": S.len(), "thickness": S.len(), "cost": S.num()], required: ["length", "width"])),
                              "kerf": S.len(), "edge_trim": S.len(), "allow_rotation": S.bool()]),
        ToolSpec("fabrication_report", "Fabrication Report", "Read the piece's fabrication data: parts (cut list with sizes, material, grain, banding), hardware (with counts), banding, nesting (sheets and yield), cost (total and by line).",
                 risk: .read, group: .furniture, modes: .furniture,
                 properties: ["what": S.oneOf(["parts", "hardware", "banding", "nesting", "cost", "all"], "Default all"), "limit": S.int("Default 60")]),
        ToolSpec("create_shop_drawings", "Shop Drawings", "Set up the shop drawings: fabrication schedules and sheets F101–F104 (plan, elevations, section, 3D, part list, exploded view) and the nesting sheets. Rerun after changes to update them.",
                 risk: .edit, group: .furniture, modes: .furniture, properties: ["nesting": S.bool("Also the nesting sheets, default true")]),
        ToolSpec("set_furniture_parameter", "Furniture Parameter", "Add or change a parameter of the piece (Family Types in Furniture mode): value in the current type, a formula, a new type copied from the current, or switch type. " + inchNote,
                 risk: .edit, group: .furniture, modes: .furniture,
                 properties: ["name": S.str(), "value": S.anyValue, "formula": S.str(), "type": S.oneOf(["length", "number", "integer", "yes_no", "text"], "New parameter type (default length)"),
                              "instance": S.bool(), "new_type": S.str(), "current_type": S.str()]),
        ToolSpec("flex_furniture", "Flex", "Flex the piece: every type, and lengths at 50%/150%; reports planes that cross, formula errors and parts that don't follow.",
                 risk: .read, group: .furniture, modes: .furniture),
        ToolSpec("list_furniture_library", "Furniture Library", "Browse the Furniture Library (Sofa, Wardrobe, Kitchen Cabinet… 190+ pieces) by words or room.",
                 risk: .read, group: .furniture, modes: [], properties: ["search": S.str(), "room": S.str(), "limit": S.int("Default 30")]),
        ToolSpec("load_furniture_piece", "Load Furniture", "Load a Furniture Library piece: into: project places it in the open project at a point (as a family); into: new opens it as a new Furniture document to edit.",
                 risk: .file, group: .furniture, modes: [],
                 properties: ["piece": S.str("Library name, e.g. 'Kitchen Cabinet'"), "into": S.oneOf(["project", "new"], "Default project when one is open"), "type": S.str(), "point": S.point(),
                              "level": S.ref(), "facing": S.ref("north/south/east/west or degrees")], required: ["piece"]),
    ]
}

extension ArcusToolbox {
    static let furnitureHandlers: [String: ToolHandler] = [
        "add_bays": { b, c in try b.addBays(c) },
        "add_fronts": { b, c in try b.addFronts(c) },
        "add_hardware": { b, c in try b.addHardware(c) },
        "set_joint": { b, c in try b.setJoint(c) },
        "set_joint_rules": { b, c in try b.setJointRules(c) },
        "search_components": { b, c in try b.searchComponents(c) },
        "place_library_component": { b, c in try b.placeLibraryComponent(c) },
        "replace_components": { b, c in try b.replaceComponents(c) },
        "insert_assembly": { b, c in try b.insertAssembly(c) },
        "set_stock_sheets": { b, c in try b.setStockSheets(c) },
        "fabrication_report": { b, c in try b.fabricationReport(c) },
        "create_shop_drawings": { b, c in try b.createShopDrawings(c) },
        "set_furniture_parameter": { b, c in try b.setFurnitureParameter(c) },
        "flex_furniture": { b, c in try b.flexFurniture(c) },
        "list_furniture_library": { b, c in try b.listFurnitureLibrary(c) },
        "load_furniture_piece": { b, c in try await b.loadFurniturePiece(c) },
    ]

    /// A furniture edit's result: flex problems and new Check Parts findings in the verification.
    func furnitureResult(_ c: ToolContext, _ fields: [String: JSONValue], ids: [ElementID], extra: [String] = []) throws(ToolError) -> ToolOutput {
        let m = try c.model()
        let flex = FurnitureParameters.flex(m)
        let parts = FurnitureCheckParts.check(m).filter { $0.severity >= .warning && (ids.isEmpty || !Set(ids).isDisjoint(with: $0.elements)) }.prefix(6).map(\.message)
        var o = fields
        if let b = Self.furnitureBox(m) { o["overall"] = [c.out(b.max.x - b.min.x, m), c.out(b.max.y - b.min.y, m), c.out(b.max.z - b.min.z, m)] }
        return result(c, o, ids: ids, problems: extra + flex.prefix(6) + parts)
    }

    // MARK: Bays and fronts

    func addBays(_ c: ToolContext) throws -> ToolOutput {
        let m = try requireFurniture(c)
        let face: BayFace = c.args.string("face")?.lowercased() == "top" ? .top : .front
        var pts: [Vec2] = []
        if let pv = c.args["points"] { pts = try c.points(pv, "points", min: 1) }
        if c.args.bool("auto", default: pts.isEmpty) {
            let planes = FurniturePlanes.positionsByName(m)
            let l = planes["Left"] ?? -0.45, r = planes["Right"] ?? 0.45, b = planes["Bottom"] ?? 0, t = planes["Top"] ?? 0.76
            let f = planes["Front"] ?? -0.23, k = planes["Back"] ?? 0.23
            let (u0, u1, v0, v1) = face == .front ? (l, r, b, t) : (l, r, f, k)
            // Sample the face; one bay per opening (by its bounds), skipping toe kicks and slots under 5".
            var seen: [[Int]] = []
            let minSize = 5 * 0.0254
            for i in 1..<24 { for j in 1..<24 {
                let p = Vec2(u0 + (u1 - u0) * Double(i) / 24, v0 + (v1 - v0) * Double(j) / 24)
                guard let o = FurnitureBays.opening(face: face, at: p, frame: .front, m) else { continue }
                let (w, h) = face == .front ? (o.x1 - o.x0, o.z1 - o.z0) : (o.x1 - o.x0, o.y1 - o.y0)
                guard w >= minSize, h >= minSize else { continue }
                let key = [o.x0, o.x1, o.y0, o.y1, o.z0, o.z1].map { Int(($0 / 0.002).rounded()) }
                guard !seen.contains(key) else { continue }
                seen.append(key)
                // The opening's centre, so the bay seed sits well inside it.
                pts.append(face == .front ? Vec2((o.x0 + o.x1) / 2, (o.z0 + o.z1) / 2) : Vec2((o.x0 + o.x1) / 2, (o.y0 + o.y1) / 2))
            } }
            // Openings already holding a bay are skipped below.
        }
        guard !pts.isEmpty else { throw ToolError("No openings found: add sides, top, bottom and shelves first, or give points [x, z] inside an opening.") }
        var made: [ElementID] = []
        var skipped: [String] = []
        let division: BayDivision? = try c.args.string("divide").map { d throws(ToolError) in
            guard let n = c.args.int("count"), n >= 1 else { throw ToolError("divide needs count.") }
            return BayDivision(direction: d.lowercased() == "columns" ? .columns : .rows, count: n)
        }
        try c.edit("Bay") { tx in
            for p in pts {
                do { made.append(try FurnitureBays.createBay(face: face, at: p, in: tx)) } catch { skipped.append((error as? TransactionError)?.message ?? "\(error)") }
            }
            if let division { for b in made { try FurnitureBays.divide(b, division, in: tx) } }
        }
        let nm = try c.model()
        if made.isEmpty { throw ToolError("No bay placed: \(skipped.first ?? "no opening at those points").") }
        return try furnitureResult(c, ["bays": .array(made.compactMap { nm[$0] }.map { b in
            var o: [String: JSONValue] = ["id": b.id.json, "name": .string(b.name)]
            if let op = b.furnitureBay?.opening { o["size"] = [c.out(op.x1 - op.x0, nm), c.out(op.z1 - op.z0, nm)] }
            if let d = b.furnitureBay, d.division != nil { o["cells"] = .array(FurnitureBays.cellIDs(of: b.id, nm).map(\.json)) }
            return .object(o)
        }), "skipped": .int(skipped.count)], ids: made)
    }

    func addFronts(_ c: ToolContext) throws -> ToolOutput {
        let m = try requireFurniture(c)
        let kindName = try c.args.requireString("kind").lowercased()
        guard let kind = FrontKind.allCases.first(where: { $0.rawValue.lowercased() == kindName }) else { throw ToolError("kind must be door, drawer or flap.") }
        var bays: [ElementID]
        if c.args["bays"] != nil { bays = try c.elementIDs("bays") } else {
            let fronted = Set(m.elements(.furnitureFronts).compactMap(\.hostID))
            bays = m.elements(.furnitureBays).filter { $0.furnitureBay?.parentID == nil && !fronted.contains($0.id) && FurnitureBays.cellIDs(of: $0.id, m).allSatisfy { !fronted.contains($0) } }.map(\.id)
        }
        guard !bays.isEmpty else { throw ToolError("No empty bays. add_bays first (or give bays ids).") }
        for b in bays where m[b]?.furnitureBay == nil { throw ToolError("Element \(b.raw) is not a bay.") }
        let type = try c.args["type"].map { try c.type($0, category: .furnitureFronts) }
        let hinge = c.args.string("hinge")?.lowercased() == "right"
        let count = c.args.int("count")
        var made: [ElementID] = []
        try c.edit(kind.rawValue) { tx in
            for b in bays {
                if kind == .drawer, let n = count, n > 1 { made += try FurnitureFronts.createDrawers(in: b, count: n, typeID: type?.id, in: tx) }
                else { made += try FurnitureFronts.createFront(kind, in: b, typeID: type?.id, hingeFlipped: hinge, in: tx) }
            }
        }
        let nm = try c.model()
        return try furnitureResult(c, ["fronts": .array(made.compactMap { nm[$0] }.map { ["id": $0.id.json, "mark": .string($0.mark), "kind": .string(kind.rawValue)] })], ids: made)
    }

    static func componentAction(_ s: String) throws(ToolError) -> ComponentAction {
        let k = s.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
        if let a = ComponentAction.allCases.first(where: { $0.rawValue.lowercased().replacingOccurrences(of: "add ", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "") == k }) { return a }
        throw ToolError("action must be one of \(ComponentAction.allCases.map { $0.rawValue.replacingOccurrences(of: "Add ", with: "").lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_") }.joined(separator: ", ")).")
    }

    func addHardware(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let action = try Self.componentAction(try c.args.requireString("action"))
        let ids: [ElementID] = c.args["elements"] != nil ? try c.elementIDs("elements")
            : (!(try c.session().selection.isEmpty) ? try c.session().selection.ids : m.elements([.furnitureFronts]).map(\.id) + (action.isBayAction ? m.elements(.furnitureBays).map(\.id) : []))
        let available = ComponentActions.available(for: ids, m)
        guard available.contains(action) else {
            throw ToolError("\(action.rawValue) doesn't apply to these elements. Available: \(available.map(\.rawValue).joined(separator: ", ")). Fronts take handles/hinges/locks; drawers take slides; bays take rods, racks, lighting.")
        }
        let plan = ComponentActions.plan(action, for: ids, m)
        guard !plan.isEmpty else { throw ToolError("Nothing to add: \(plan.notes.joined(separator: " "))") }
        var made: [ElementID] = []
        try c.edit(action.rawValue) { tx in made = try ComponentActions.apply(plan, in: tx) }
        return try furnitureResult(c, ["placed": .array(plan.lines.map { .string($0) }), "notes": .array(plan.notes.map { .string($0) }), "elements": .int(made.count)], ids: made)
    }

    // MARK: Joints

    func setJoint(_ c: ToolContext) throws -> ToolOutput {
        let m = try requireFurniture(c)
        if c.args.bool("list", default: false) || c.args["parts"] == nil {
            let joints = FurnitureJoints.joints(m)
            return ToolOutput(["joints": .array(joints.prefix(80).map { j in
                ["parts": [j.throughID.json, j.otherID.json], "pair": .string(j.pair.rawValue), "type": .string(j.type.rawValue), "through": j.throughID.json, "by_rule": .bool(j.type == j.ruleType)]
            }), "count": .int(joints.count)])
        }
        let parts = try c.elementIDs("parts")
        guard parts.count == 2 else { throw ToolError("parts must be two part ids.") }
        let key = JointKey(parts[0], parts[1])
        guard FurnitureJoints.joint(parts[0], parts[1], m) != nil else { throw ToolError("Parts \(parts[0].raw) and \(parts[1].raw) don't touch, so they have no joint. set_joint {list: true} lists the joints.") }
        try c.edit("Joint") { tx in
            if c.args.bool("reset", default: false) { FurnitureJointOperations.reset(key, in: tx); return }
            if let t = c.args.string("type") {
                let k = t.lowercased().replacingOccurrences(of: "_", with: " ")
                guard let jt = JointType.allCases.first(where: { $0.rawValue.lowercased() == k || $0.rawValue.lowercased().replacingOccurrences(of: " and ", with: " ") == k }) else {
                    throw TransactionError("type must be one of \(JointType.allCases.map(\.rawValue).joined(separator: ", ")).")
                }
                try FurnitureJointOperations.set(key, type: jt, in: tx)
            }
            if let th = c.args.int("through") { try FurnitureJointOperations.set(key, through: ElementID(UInt64(max(0, th))), in: tx) }
        }
        let nm = try c.model()
        let j = FurnitureJoints.joint(parts[0], parts[1], nm)
        return try furnitureResult(c, ["type": .string(j?.type.rawValue ?? ""), "through": j?.throughID.json ?? .null,
                                       "cut_sizes": .array(parts.compactMap { FurnitureJoints.cutSize(of: $0, in: nm) }.map { [c.out($0.length, nm), c.out($0.width, nm), c.out($0.thickness, nm)] })], ids: parts)
    }

    func setJointRules(_ c: ToolContext) throws -> ToolOutput {
        let m = try requireFurniture(c)
        var rules = m.furnitureSetup?.jointRules ?? FurnitureJointRules.defaults(m.furnitureSetup?.category ?? .furniture)
        for (k, r) in try c.args.requireArray("rules").enumerated() {
            let pk = (r["pair"]?.stringValue ?? "").lowercased().replacingOccurrences(of: "_", with: "")
            guard let pair = JointPairKind.allCases.first(where: { $0.rawValue.lowercased().replacingOccurrences(of: " – ", with: "").replacingOccurrences(of: " ", with: "") == pk }) else {
                throw ToolError("rules[\(k)].pair: one of \(JointPairKind.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
            let tk = (r["type"]?.stringValue ?? "").lowercased().replacingOccurrences(of: "_", with: " ")
            guard let type = JointType.allCases.first(where: { $0.rawValue.lowercased() == tk || $0.rawValue.lowercased().replacingOccurrences(of: " and ", with: " ") == tk }) else {
                throw ToolError("rules[\(k)].type: one of \(JointType.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
            let through: JointThrough = r["through"]?.stringValue?.lowercased() == "second" ? .second : .first
            if let i = rules.rules.firstIndex(where: { $0.pair == pair }) { rules.rules[i].type = type; rules.rules[i].through = through; rules.rules[i].parameters = JointParameters.defaults(type) }
            else { rules.rules.append(JointRule(pair, type, through: through, parameters: JointParameters.defaults(type))) }
        }
        let final = rules
        try c.edit("Joint Rules") { tx in try FurnitureJointOperations.setRules(final, in: tx) }
        return try furnitureResult(c, ["rules": .array(final.rules.map { ["pair": .string($0.pair.rawValue), "type": .string($0.type.rawValue)] }), "joints": .int(FurnitureJoints.joints(try c.model()).count)], ids: [])
    }

    // MARK: Component Library

    func component(_ name: String) throws(ToolError) -> ComponentDefinition {
        let cat = ComponentCatalog.current
        if let d = cat.definition(id: name) ?? cat.definition(named: name) { return d }
        let hits = ComponentSearchIndex(cat.all).search(name, limit: 6)
        if let first = hits.first, hits.count == 1 || first.definition.name.localizedCaseInsensitiveContains(name) { return first.definition }
        throw ToolError("No component “\(name)”.\(hits.isEmpty ? "" : " Close: \(hits.map(\.definition.name).joined(separator: "; ")).") search_components finds them.")
    }

    func searchComponents(_ c: ToolContext) throws -> ToolOutput {
        let q = try c.args.requireString("query")
        var filter = ComponentSearchFilter()
        if let h = c.args.string("host") {
            let k = h.lowercased().replacingOccurrences(of: "_", with: "")
            guard let hk = ComponentHostKind.allCases.first(where: { "\($0)".lowercased() == k }) else { throw ToolError("host: \(ComponentHostKind.allCases.map { "\($0)" }.joined(separator: ", ")).") }
            filter.host = hk
        }
        let hits = ComponentSearchIndex(ComponentCatalog.current.all).search(q, filter: filter, limit: max(1, c.args.int("limit") ?? 12))
        return ToolOutput(["components": .array(hits.map { h in
            ["id": .string(h.definition.id), "name": .string(h.definition.name), "category": .string("\(h.definition.category)"),
             "types": .array(h.definition.types.prefix(8).map { .string($0.name) }), "best_type": h.typeName.map { .string($0) } ?? .null]
        }), "count": .int(hits.count)])
    }

    func placeLibraryComponent(_ c: ToolContext) throws -> ToolOutput {
        let d = try component(try c.args.requireString("component"))
        let typeName = c.args.string("type")
        if let t = typeName, !d.types.contains(where: { $0.name == t }) { throw ToolError("“\(d.name)” has no type “\(t)”. Types: \(d.types.map(\.name).joined(separator: "; ")).") }
        let hostID = try c.args["host"].map { try c.element($0, "host").id }
        let p = try c.args["point"].map { try c.point($0, "point") }
        guard hostID != nil || p != nil else { throw ToolError("Give host (a front, bay or part id) or point.") }
        var lp: Vec3?
        if let p, let z = try c.length("z") { lp = Vec3(p, z: z) }
        var made: [ElementID] = []
        try c.edit("Place Component") { tx in made = try ComponentPlacement.place(d, typeName: typeName, hostID: hostID, at: lp == nil ? p : nil, levelPoint: lp, in: tx) }
        let m = try c.model()
        let collisions = ComponentChecks.check(m).filter { !Set(made).isDisjoint(with: $0.elements) }.map(\.message)
        return result(c, ["placed": .array(made.map(\.json)), "component": .string(d.name)], ids: made, problems: collisions)
    }

    func replaceComponents(_ c: ToolContext) throws -> ToolOutput {
        let ids = try c.idsOrSelection()
        let d = try component(try c.args.requireString("component"))
        var notes: [ModelWarning] = []
        try c.edit("Replace Component") { tx in notes = try ComponentPlacement.replace(ids, with: d, typeName: c.args.string("type"), in: tx) }
        return result(c, ["replaced": .int(ids.count), "component": .string(d.name)], ids: ids, problems: notes.map(\.message))
    }

    func insertAssembly(_ c: ToolContext) throws -> ToolOutput {
        let all = ComponentAssembly.builtIn
        if c.args.bool("list", default: false) || c.args["assembly"] == nil {
            return ToolOutput(["assemblies": .array(all.map { ["name": .string($0.name), "summary": .string($0.summary)] })])
        }
        let n = try c.args.requireString("assembly")
        guard let a = all.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame || $0.id == n }) ?? all.first(where: { $0.name.localizedCaseInsensitiveContains(n) }) else {
            throw ToolError("No assembly “\(n)”. Assemblies: \(all.map(\.name).joined(separator: ", ")).")
        }
        guard let bv = c.args["bay"] else { throw ToolError("Give bay (a bay id; add_bays makes one).") }
        let bay = try c.element(bv, "bay")
        guard bay.furnitureBay != nil else { throw ToolError("Element \(bay.id.raw) is not a bay.") }
        var made: [ElementID] = []
        try c.edit(a.name) { tx in made = try ComponentAssemblies.insert(a, bay: bay.id, in: tx) }
        return try furnitureResult(c, ["assembly": .string(a.name), "elements": .int(made.count)], ids: made)
    }

    // MARK: Fabrication

    func setStockSheets(_ c: ToolContext) throws -> ToolOutput {
        let m = try requireFurniture(c)
        var s = m.furnitureSetup?.stockSheets ?? FurnitureStockSheets.defaults(m)
        if let sizes = c.args.array("sizes") {
            var out: [StockSheetSize] = []
            for (k, v) in sizes.enumerated() {
                guard let l = v["length"], let w = v["width"] else { throw ToolError("sizes[\(k)] needs length and width.") }
                let t = try v["thickness"].map { try c.length($0, "thickness") }
                out.append(StockSheetSize(name: v["name"]?.stringValue ?? "Sheet \(k + 1)", thickness: t, length: try c.length(l, "length"), width: try c.length(w, "width"), cost: v["cost"]?.doubleValue))
            }
            s.sizes = out
        }
        if let k = try c.length("kerf") { s.kerf = k }
        if let t = try c.length("edge_trim") { s.edgeTrim = t }
        if let r = c.args["allow_rotation"]?.boolValue { s.allowRotation = r }
        if let p = s.problem() { throw ToolError(p) }
        let final = s
        try c.edit("Stock Sheets") { tx in try FurnitureStockSheets.set(final, in: tx) }
        let nm = try c.model()
        let groups = FurnitureFabrication.nesting(nm)
        return try furnitureResult(c, ["sizes": .array(final.sizes.map { .string("\($0.name) \(c.formatLength($0.length, nm)) × \(c.formatLength($0.width, nm))") }),
                                       "sheets_needed": .int(groups.reduce(0) { $0 + $1.result.sheets.count })], ids: [])
    }

    func fabricationReport(_ c: ToolContext) throws -> ToolOutput {
        let m = try requireFurniture(c)
        let what = c.args.string("what")?.lowercased() ?? "all"
        let limit = max(1, c.args.int("limit") ?? 60)
        var o: [String: JSONValue] = ["unit": "in"]
        if what == "parts" || what == "all" {
            let parts = FurnitureFabrication.parts(m)
            o["parts"] = .array(parts.prefix(limit).map { p in
                ["mark": .string(p.mark), "part": .string(p.name), "type": .string(p.typeName), "material": .string(m[p.materialID]?.name ?? "none"),
                 "size": [c.out(p.length, m), c.out(p.width, m), c.out(p.thickness, m)], "grain": .string(p.grain.rawValue)]
            })
            o["part_count"] = .int(parts.count)
        }
        if what == "hardware" || what == "all" {
            o["hardware"] = .array(FurnitureFabrication.hardware(m).prefix(limit).map { h in ["name": .string("\(h.family): \(h.typeName)"), "kind": .string(h.kind), "count": .int(h.count)] })
        }
        if what == "banding" || what == "all" {
            o["banding"] = .array(FurnitureFabrication.banding(m).prefix(limit).map { b in ["material": .string(m[b.materialID]?.name ?? "none"), "part": .string(b.part.mark), "length": c.out(b.length, m)] })
        }
        if what == "nesting" || what == "all" {
            o["nesting"] = .array(FurnitureFabrication.nesting(m).map { g in
                ["material": .string("\(m[g.materialID]?.name ?? "Any") \(c.formatLength(g.thickness, m))"), "sheets": .int(g.result.sheets.count), "yield": .double((g.result.yield * 1000).rounded() / 10)]
            })
        }
        if what == "cost" || what == "all" {
            o["cost"] = .double((FurnitureCostEstimate.cost(of: m) * 100).rounded() / 100)
            o["cost_lines"] = .array(FabricationSchedules.costLines(m).prefix(limit).map { .string("\($0.category) – \($0.item): \(String(format: "%.2f", $0.cost))") })
        }
        let checks = FurnitureCheckParts.check(m)
        if !checks.isEmpty { o["check_parts"] = .array(checks.prefix(10).map(ToolContext.warningJSON)) }
        return ToolOutput(.object(o))
    }

    func createShopDrawings(_ c: ToolContext) throws -> ToolOutput {
        _ = try requireFurniture(c)
        guard !FurnitureFabrication.parts(try c.model()).isEmpty else { throw ToolError("The piece has no parts yet.") }
        var nest: [ElementID] = []
        try c.edit("Shop Drawings") { tx in
            FurnitureShopDrawings.ensureStandard(in: tx)
            FurnitureShopDrawings.update(in: tx)
            if c.args.bool("nesting", default: true) { nest = FurnitureShopDrawings.updateNesting(in: tx) }
        }
        let m = try c.model()
        let sheets = m.sheets.sorted { ($0.sheet?.number ?? "") < ($1.sheet?.number ?? "") }
        let problems = sheets.flatMap { DrawingCheck.problems($0, m).problems.filter { $0.code.hasPrefix("sheet.") && $0.code != "sheet.empty_fields" } }.map(\.message)
        return try furnitureResult(c, ["sheets": .array(sheets.map { .string("\($0.sheet?.number ?? "") \($0.name)") }), "nesting_sheets": .int(nest.count)], ids: [], extra: problems)
    }

    func setFurnitureParameter(_ c: ToolContext) throws -> ToolOutput {
        let m = try requireFurniture(c)
        let a = c.args
        guard a["name"] != nil || a["new_type"] != nil || a["current_type"] != nil else { throw ToolError("Give name (with value or formula), new_type or current_type.") }
        try c.edit("Family Types") { tx in
            if let nt = a.string("new_type") {
                var ok = true
                try FurnitureParameters.edit(tx) { s in ok = FamilyEditing.addType(&s.family, named: nt, copying: s.currentType); if ok { s.currentType = nt } }
                if !ok { throw TransactionError("A type named “\(nt)” exists.") }
            }
            if let ct = a.string("current_type") { try FurnitureParameters.setCurrentType(ct, in: tx) }
            guard let name = a.string("name") else { return }
            let type = try Self.familyParamType(a.string("type"))
            var exists = false
            try FurnitureParameters.edit(tx) { s in
                if let i = s.family.parameters.firstIndex(where: { $0.name == name }) {
                    exists = true
                    if let f = a["formula"] { s.family.parameters[i].formula = f.stringValue.flatMap { $0.isEmpty ? nil : $0 } }
                } else {
                    s.family.parameters.append(FamilyParameter(name: name, type: type, isInstance: a.bool("instance", default: false), formula: a.string("formula")))
                }
            }
            if let v = a["value"] {
                let pt = tx.model.furnitureSetup?.family.parameter(named: name)?.type ?? type
                // Furniture numbers are inches.
                let value: ParamValue = pt == .length ? .double(try c.length(v, name)) : try Self.familyValue(v, pt, name, .imperial)
                try FurnitureParameters.setValue(name, value, in: tx)
            }
            _ = exists
        }
        let nm = try c.model()
        var o: [String: JSONValue] = ["current_type": .string(nm.furnitureSetup?.currentType ?? ""), "types": .array((nm.furnitureSetup?.family.types ?? []).map { .string($0.name) })]
        if let n = a.string("name"), let v = FurnitureParameters.value(n, nm) {
            o["value"] = v.quantityValue.map { c.out($0, nm) } ?? .string("\(v)")
        }
        o["planes"] = .object(FurniturePlanes.positionsByName(nm).mapValues { c.out($0, nm) })
        _ = m
        return try furnitureResult(c, o, ids: [])
    }

    func flexFurniture(_ c: ToolContext) throws -> ToolOutput {
        let m = try requireFurniture(c)
        let p = FurnitureParameters.flex(m)
        let parts = FurnitureCheckParts.check(m).filter { $0.severity >= .warning }.map(\.message)
        return ToolOutput(["ok": .bool(p.isEmpty), "problems": .array(p.map { .string($0) }), "check_parts": .array(parts.prefix(10).map { .string($0) }),
                           "types": .array((m.furnitureSetup?.family.types ?? []).map { .string($0.name) })])
    }

    // MARK: Library

    func listFurnitureLibrary(_ c: ToolContext) throws -> ToolOutput {
        var pieces = FurnitureLibrary.all
        if let r = c.args.string("room") { pieces = pieces.filter { $0.rooms.contains { $0.localizedCaseInsensitiveContains(r) } } }
        if let s = c.args.string("search") {
            let q = ToolContext.tokens(s)
            pieces = pieces.filter { p in let hay = ToolContext.tokens(p.name + " " + p.rooms.joined(separator: " ") + " " + p.keywords.joined(separator: " ")); return q.allSatisfy { w in hay.contains { $0.hasPrefix(w) } } }
        }
        let limit = max(1, c.args.int("limit") ?? 30)
        return ToolOutput(["pieces": .array(pieces.prefix(limit).map { ["name": .string($0.name), "rooms": .array($0.rooms.map { .string($0) }), "category": .string($0.category.rawValue), "detail": .string($0.detail.rawValue)] }),
                           "count": .int(pieces.count)])
    }

    func loadFurniturePiece(_ c: ToolContext) async throws -> ToolOutput {
        let n = try c.args.requireString("piece")
        let all = FurnitureLibrary.all
        guard let piece = all.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) ?? all.first(where: { $0.name.localizedCaseInsensitiveContains(n) }) else {
            let near = all.filter { p in ToolContext.tokens(n).contains { w in ToolContext.tokens(p.name).contains { $0.hasPrefix(w) } } }.prefix(8).map(\.name)
            throw ToolError("No library piece “\(n)”.\(near.isEmpty ? "" : " Close: \(near.joined(separator: "; ")).") list_furniture_library browses them.")
        }
        let source = piece.build()
        let intoProject = (c.args.string("into")?.lowercased() ?? (host.session.map { $0.model.isFurniture ? "new" : "project" } ?? "new")) == "project"
        if !intoProject {
            try host.adopt(source, name: piece.name)
            return ToolOutput(["document": .string(piece.name), "kind": "furniture", "types": .array((source.furnitureSetup?.family.types ?? []).map { .string($0.name) }),
                               "next": "Edit it with the furniture tools; load_furniture_piece {into:'project'} or Load into Project places it in a project."])
        }
        let m = try c.model()
        guard !m.isFurniture else { throw ToolError("The front document is a Furniture document. Use into: 'new', or open a project.") }
        let level = try c.levelOrViewLevel()
        let family = FurnitureCompiler.family(from: source)
        let existing = m.family(named: family.name)?.id
        let point = try c.args["point"].map { try c.point($0, "point") }
        let rot = try c.args["facing"].map { try c.angle($0, "facing") + .pi / 2 } ?? 0
        var placed: ElementID?
        let r = try c.edit("Load Furniture") { tx in
            let fid = FurnitureLoading.load(family, from: source, replacing: existing, in: tx)
            let types = tx.model.elements(.elementTypes).filter { $0.typeData?.familyID == fid }
            let t = c.args.string("type").flatMap { n in types.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } } ?? types.first
            if let point, let t, let cat = t.typeData?.instanceCategory {
                placed = tx.create(cat, data: .component(ComponentData(location: point, rotation: rot)), typeID: t.id, levelID: level.id)
            }
        }
        let nm = try c.model()
        return result(c, ["family": .string(family.name), "placed": placed?.json ?? .null, "types": .array(nm.elements(.elementTypes).filter { nm[$0.typeData?.familyID]?.name == family.name }.map { .string($0.name) })],
                      ids: ToolContext.created(r), problems: point == nil ? [] : (placed == nil ? ["Loaded, but no type could be placed."] : []))
    }
}

extension ComponentAction {
    /// Actions that go in bays rather than on fronts.
    var isBayAction: Bool { [.hangingRod, .shoeRack, .lighting, .organizer, .slidingSystem].contains(self) }
}
