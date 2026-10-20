import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// MCP: documentation tools: views, sheets, schedules, dimensions and tags.

extension ArcusToolbox {
    /// Plan extents of the building: walls, floors, roofs and components (meters).
    static func modelExtents(_ m: BIMModel) -> Rect2? {
        var pts: [Vec2] = []
        for w in m.elements(.walls) { if let l = w.wall?.location { pts += [l.start, l.end] } }
        for f in m.elements([.floors, .ceilings]) { pts += f.slab?.boundary.loops.first?.map(\.start) ?? [] }
        for r in m.elements(.roofs) { pts += r.roof?.footprint.loops.first?.map(\.start) ?? [] }
        for c in m.elements(Category.allCases.filter { $0.isModel }) { if let p = c.component?.location { pts.append(p) } }
        if let b = furnitureBox(m) { pts += [b.min.xy, b.max.xy] }
        return pts.isEmpty ? nil : Rect2(points: pts)
    }

    /// The bounding box of a Furniture document's parts.
    static func furnitureBox(_ m: BIMModel) -> Box3? {
        guard m.isFurniture else { return nil }
        var b: Box3?
        for e in m.elements([.furniturePanels, .furnitureShelves, .furnitureLegs, .furnitureRails]) {
            guard let pb = FurniturePartSolids.partBox(e, m)?.box else { continue }
            b = b.map { Box3(min: Vec3(Swift.min($0.min.x, pb.min.x), Swift.min($0.min.y, pb.min.y), Swift.min($0.min.z, pb.min.z)),
                             max: Vec3(Swift.max($0.max.x, pb.max.x), Swift.max($0.max.y, pb.max.y), Swift.max($0.max.z, pb.max.z))) } ?? pb
        }
        return b
    }

    /// Crops the plans to the building and re-aims the template's four exterior elevations at the building (markers just outside it, cropped to it) while
    /// none of them is on a sheet, so plans stay tight around the model and elevations frame it.
    static func fitTemplateElevations(in tx: TransactionContext) {
        let m = tx.model
        guard let ext = modelExtents(m), ext.width > 0.5 || ext.height > 0.5 else { return }
        let margin = m.units.system == .imperial ? 12 * 0.3048 : 4.0
        // Plans not yet on a sheet: cropped to the building plus its dimension strings and elevation markers (a sheet
        // viewport otherwise clips to the model's extents and cuts the dimensions off).
        for v in m.views where (v.view?.kind == .floorPlan || v.view?.kind == .ceilingPlan) && m.viewports(showing: v.id).isEmpty {
            tx.update(v.id) { e in
                e.view?.cropRegion = Rect2(min: ext.min - Vec2(margin, margin) * 1.25, max: ext.max + Vec2(margin, margin) * 1.25)
                e.view?.cropActive = true
                e.view?.cropVisible = false
            }
        }
        let names = ["North", "South", "East", "West"]
        let elevations = m.views.filter { $0.view?.kind == .elevation && names.contains($0.name) }
        guard !elevations.isEmpty, elevations.allSatisfy({ m.viewports(showing: $0.id).isEmpty }) else { return }
        let (z0, z1) = levelRange(m)
        let center = ext.center
        for e in elevations {
            tx.update(e.id) { v in
                guard var vd = v.view, let d = vd.viewDirection else { return }
                let along = abs(d.x) > abs(d.y) ? ext.width : ext.height    // depth seen through
                let across = abs(d.x) > abs(d.y) ? ext.height : ext.width   // width of the picture
                // Markers clear of the auto dimension strings (4' and 6'-6" out).
                vd.planeOrigin = Vec3(center - d * (along / 2 + margin * 1.1), z: 0)
                vd.markerPosition = center - d * (along / 2 + margin)
                vd.farClip = along + 2 * margin
                vd.cropRegion = Rect2(min: Vec2(-across / 2 - margin / 2, z0 - margin / 4), max: Vec2(across / 2 + margin / 2, z1 + margin))
                vd.cropActive = true
                v.view = vd
            }
        }
    }

    static func levelRange(_ m: BIMModel) -> (Double, Double) {
        let zs = m.levels.compactMap { $0.level?.elevation }
        return ((zs.min() ?? 0), (zs.max() ?? 3))
    }

    /// An isometric camera framing the building from the south-west (or `box`).
    static func fitCamera(_ m: BIMModel, box: Box3? = nil) -> Camera3D {
        let r = modelExtents(m) ?? Rect2(min: .zero, max: Vec2(10, 10))
        let (z0, z1) = levelRange(m)
        let b = box ?? furnitureBox(m) ?? Box3(min: Vec3(r.min, z: z0), max: Vec3(r.max, z: z1 + 1))
        let center = Vec3((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2, (b.min.z + b.max.z) / 2)
        let size = max(b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z, 1)
        let eye = center + Vec3(-1, -1.2, 0.9).normalized * (size * 2.5)
        return Camera3D(eye: eye, target: center, orthoHeight: size * 1.1)
    }

    func uniqueViewName(_ base: String, kind: ViewKind, _ m: BIMModel) -> String {
        let taken = Set(m.views.filter { $0.view?.kind == kind }.map(\.name))
        guard taken.contains(base) else { return base }
        var k = 2
        while taken.contains("\(base) (\(k))") { k += 1 }
        return "\(base) (\(k))"
    }

    func createViews(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let phase = m.latestPhase?.id
        let imperial = m.units.system == .imperial
        let defaultScale = m.isFurniture ? 12 : imperial ? 48 : 100
        let (z0, z1) = Self.levelRange(m)
        let ext = Self.modelExtents(m) ?? Rect2(min: .zero, max: Vec2(10, 10))
        var specs: [(name: String, data: ViewData, level: ElementID?)] = []
        var counts: [ViewKind: Int] = [:]
        for (k, v) in try c.args.requireArray("views").enumerated() {
            let what = "views[\(k)]"
            let scale = v["scale"]?.intValue ?? defaultScale
            guard scale >= 1, scale <= 20_000 else { throw ToolError("\(what).scale must be 1…20000 (e.g. 48 for 1/4\" = 1'-0\").") }
            switch v["kind"]?.stringValue?.lowercased() {
            case "floor_plan", "ceiling_plan", "plan":
                let kind: ViewKind = v["kind"]?.stringValue == "ceiling_plan" ? .ceilingPlan : .floorPlan
                let level = try c.level(v["level"], what + ".level")
                var vd = ViewData(kind: kind, scale: scale); vd.phaseID = phase
                specs.append((uniqueViewName(v["name"]?.stringValue ?? level.name, kind: kind, m), vd, level.id))
            case "three_d", "3d":
                var vd = ViewData(kind: .threeD, scale: scale); vd.phaseID = phase
                var box: Box3?
                if let cut = v["cut_to_level"] {
                    let l = try c.level(cut, what + ".cut_to_level")
                    let top = (l.level?.elevation ?? 0) + (imperial ? 4 * 0.3048 : 1.2)
                    let b = Box3(min: Vec3(ext.min - Vec2(1, 1), z: z0 - 1), max: Vec3(ext.max + Vec2(1, 1), z: top))
                    vd.sectionBox = b; vd.sectionBoxActive = true; box = b
                }
                vd.camera = Self.fitCamera(m, box: box)
                specs.append((uniqueViewName(v["name"]?.stringValue ?? "3D View", kind: .threeD, m), vd, nil))
            case "section":
                guard let sv = v["start"], let ev = v["end"] else { throw ToolError("\(what): a section needs start and end points.") }
                let s = try c.point(sv, what + ".start"), e = try c.point(ev, what + ".end")
                guard s.distance(to: e) > 0.1 else { throw ToolError("\(what): start and end are too close.") }
                let dir = (e - s).normalized
                let look = (v["flip"]?.boolValue ?? false) ? -dir.perpendicular : dir.perpendicular
                var vd = ViewData(kind: .section, scale: scale)
                vd.viewDirection = look
                let right = vd.rightVector ?? dir
                let origin = right.dot(dir) > 0 ? s : e
                vd.planeOrigin = Vec3(origin, z: 0)
                vd.cropRegion = Rect2(min: Vec2(0, z0 - 1.5), max: Vec2(s.distance(to: e), z1 + 3))
                vd.cropActive = true
                vd.farClip = try v["depth"].map { try c.length($0, what + ".depth") } ?? (imperial ? 40 * 0.3048 : 12)
                vd.phaseID = phase
                counts[.section, default: m.views.filter { $0.view?.kind == .section }.count] += 1
                specs.append((v["name"]?.stringValue ?? "Section \(counts[.section]!)", vd, nil))
            case "elevation":
                guard let pv = v["point"], let fv = v["facing"] else { throw ToolError("\(what): an elevation needs point (where it stands) and facing (the direction it looks).") }
                let p = try c.point(pv, what + ".point")
                let a = try c.angle(fv, what + ".facing")
                let d = Vec2(cos(a), sin(a))
                var vd = ViewData(kind: .elevation, scale: scale)
                vd.planeOrigin = Vec3(p, z: 0)
                vd.viewDirection = d
                vd.markerPosition = p
                vd.farClip = try v["depth"].map { try c.length($0, what + ".depth") } ?? (ext.width + ext.height + 10)
                let half = max(ext.width, ext.height) / 2 + 2
                vd.cropRegion = Rect2(min: Vec2(-half, z0 - 1), max: Vec2(half, z1 + 2))
                vd.cropActive = true
                vd.phaseID = phase
                counts[.elevation, default: m.views.filter { $0.view?.kind == .elevation }.count] += 1
                specs.append((v["name"]?.stringValue ?? "Elevation \(counts[.elevation]!)", vd, nil))
            case "drafting", "drafting_view", "legend":
                // AITOOLS: drafting views and legends (2D views with no model).
                let legend = v["kind"]?.stringValue?.lowercased() == "legend"
                var vd = ViewData(kind: legend ? .legend : .drafting, scale: v["scale"]?.intValue ?? (legend ? 50 : 20)); vd.phaseID = phase
                specs.append((v["name"]?.stringValue ?? (legend ? "Legend" : "Drafting View") + " \(m.views.filter { $0.view?.kind == vd.kind }.count + 1)", vd, nil))
            case "callout":
                // AITOOLS: a callout of a parent view: the parent's settings at twice the scale, cropped to a rectangle.
                guard let pv = v["parent"], let rv = v["rect"] else { throw ToolError("\(what): a callout needs parent (view) and rect [[x0,y0],[x1,y1]].") }
                let parent = try c.view(pv, what: what + ".parent")
                guard var vd = parent.view else { throw ToolError("\(what).parent must be a view.") }
                let r = try c.points(rv, what + ".rect")
                vd.scale = v["scale"]?.intValue ?? max(1, vd.scale / 2)
                vd.cropRegion = Rect2(points: r); vd.cropActive = true; vd.cropVisible = true
                vd.parentViewID = parent.id
                vd.templateID = nil
                specs.append((uniqueViewName(v["name"]?.stringValue ?? "Callout of \(parent.name)", kind: vd.kind, m), vd, parent.levelID))
            default:
                throw ToolError("\(what).kind must be floor_plan, ceiling_plan, three_d, section, elevation, callout, drafting or legend.")
            }
        }
        let r = try c.edit("Create Views") { tx in
            for s in specs { tx.create(.views, name: s.name, data: .view(s.data), levelID: s.level) }
        }
        let ids = ToolContext.created(r)
        let nm = try c.model()
        return result(c, ["views": .array(ids.compactMap { nm[$0] }.filter { $0.view != nil }.map {
            ["id": $0.id.json, "name": .string($0.name), "kind": .string($0.view?.kind.rawValue ?? ""), "scale": .int($0.view?.scale ?? 0)]
        })], ids: ids)
    }

    // MARK: Sheets

    static func paper(_ s: String?, imperial: Bool) throws(ToolError) -> PaperSize {
        guard let s else { return imperial ? .archD : .a1 }
        let k = s.uppercased().replacingOccurrences(of: "_", with: " ")
        if let p = PaperSize.allCases.first(where: { $0.rawValue.uppercased() == k || $0.rawValue.uppercased().hasPrefix(k) }) { return p }
        if k.contains("TABLOID") || k == "ANSIB" || k == "ANSI B" { return .ansiB }
        throw ToolError("paper must be one of \(PaperSize.allCases.map(\.rawValue).joined(separator: ", ")).")
    }

    /// A view's (or schedule's) size on paper, meters.
    static func paperSize(of e: Element, _ m: BIMModel) -> Vec2 {
        if e.schedule != nil { return Vec2(0.25, 0.2) }
        guard let vd = e.view else { return Vec2(0.2, 0.2) }
        let g = ViewGraphicsBuilder(model: m, view: e).build()
        let r = g.crop ?? g.extents
        let s = Double(max(1, vd.scale))
        return Vec2(r.width / s, r.height / s)
    }

    func createSheet(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let number = try c.args.requireString("number"), name = try c.args.requireString("name")
        if m.sheets.contains(where: { $0.sheet?.number == number }) { throw ToolError("Sheet \(number) already exists. Choose another number.") }
        let paper = try Self.paper(c.args.string("paper"), imperial: m.isFurniture || m.units.system == .imperial)
        let tbs = m.types(for: .titleBlocks)
        let tb: Element? = try c.args["title_block"].map { try c.type($0, category: .titleBlocks, what: "title_block") }
            ?? tbs.first { ToolContext.typeLabel($0, m).uppercased().contains(paper.rawValue.uppercased()) }
            ?? tbs.first { ToolContext.typeLabel($0, m).uppercased().contains(paper.rawValue.split(separator: " ").first.map(String.init)?.uppercased() ?? "") } ?? tbs.first
        // Views and schedules to place.
        var items: [(Element, Vec2?)] = []
        for (k, v) in (c.args.array("views") ?? []).enumerated() {
            guard let vv = v["view"] else { throw ToolError("views[\(k)] needs a view.") }
            let e: Element
            if let s = vv.stringValue, let sc = m.schedules.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) { e = sc } else { e = try c.view(vv, what: "views[\(k)].view") }
            var pos: Vec2?
            if let p = v["position"]?.arrayValue, p.count == 2, let u = p[0].doubleValue, let w = p[1].doubleValue {
                guard (0...1).contains(u), (0...1).contains(w) else { throw ToolError("views[\(k)].position must be fractions of the paper, 0–1.") }
                pos = Vec2(u, w)
            }
            items.append((e, pos))
        }
        for (k, s) in (c.args.array("schedules") ?? []).enumerated() {
            guard let n = s.stringValue, let sc = m.schedules.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) ?? s.intValue.flatMap({ m[ElementID(UInt64($0))] }) else {
                throw ToolError("schedules[\(k)]: no schedule “\(s.stringValue ?? s.jsonText)”. Schedules: \(m.schedules.map(\.name).joined(separator: ", ")).")
            }
            items.append((sc, nil))
        }
        for (e, _) in items {
            if e.schedule == nil, let vp = m.viewports(showing: e.id).first, let owner = m[vp.ownerViewID] {
                throw ToolError("“\(e.name)” is already on sheet \(owner.sheet?.number ?? "") \(owner.name). A view goes on one sheet; create another view (create_views).")
            }
        }
        // Grid layout in the drawing area (left 80 %, clear of the title block strip on the right).
        let size = paper.landscapeSize
        // One grid cell per item, in order; positioned items keep their place and auto items take their own cells.
        let cols = max(1, Int(Double(items.count).squareRoot().rounded(.up))), rows = max(1, Int((Double(items.count) / Double(cols)).rounded(.up)))
        let area = Rect2(min: Vec2(size.x * 0.03, size.y * 0.06), max: Vec2(size.x * 0.80, size.y * 0.95))
        var placements: [(Element, Vec2)] = []
        var overflow: [String] = []
        var rescale: [ElementID: Int] = [:]
        for (k, (e, pos)) in items.enumerated() {
            let center: Vec2
            if let pos { center = Vec2(pos.x * size.x, pos.y * size.y) } else {
                let col = k % cols, row = k / cols
                center = Vec2(area.min.x + area.width * (Double(col) + 0.5) / Double(cols), area.max.y - area.height * (Double(row) + 0.5) / Double(rows))
                // Schedules size themselves to their rows; only views are checked.
                let ps = Self.paperSize(of: e, m)
                let cell = Vec2(area.width / Double(cols), area.height / Double(rows))
                if let vd = e.view, ps.x > cell.x * 1.02 || ps.y > cell.y * 1.02 {
                    // AITOOLS: fit (default): the next standard scale that fits the cell, as a drafter would pick.
                    let scales = m.units.system == .imperial || m.isFurniture ? [4, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 480] : [5, 10, 20, 25, 50, 100, 200, 250, 500, 1000]
                    if c.args.bool("fit", default: true), let s = scales.first(where: { $0 > vd.scale && ps.x * Double(vd.scale) / Double($0) <= cell.x * 1.02 && ps.y * Double(vd.scale) / Double($0) <= cell.y * 1.02 }) {
                        rescale[e.id] = s
                    } else {
                        overflow.append("\(e.name) is \(Int(ps.x * 1000))×\(Int(ps.y * 1000)) mm on paper at 1:\(vd.scale), more than its \(Int(cell.x * 1000))×\(Int(cell.y * 1000)) mm cell")
                    }
                }
            }
            placements.append((e, center))
        }
        let imperial = m.units.system == .imperial || m.isFurniture
        let r = try c.edit("Create Sheet") { tx in
            var sd = SheetData(number: number, paper: paper, titleBlockTypeID: tb?.id)
            sd.drawnBy = "Arcus"; sd.designedBy = "Arcus"
            let sid = tx.create(.sheets, name: name, data: .sheet(sd))
            for (id, s) in rescale { tx.update(id) { $0.view?.scale = s } }
            for (e, center) in placements { try SheetPlacement.place(e.id, onSheet: sid, at: center, in: tx) }
        }
        let ids = ToolContext.created(r)
        let nm = try c.model()
        let sheet = ids.compactMap { nm[$0] }.first { $0.sheet != nil }
        var o: [String: JSONValue] = ["sheet": sheet?.id.json ?? .null, "number": .string(number), "paper": .string(paper.rawValue),
                                      "title_block": .string(tb.map { ToolContext.typeLabel($0, nm) } ?? "none"),
                                      "placed": .array(placements.map { .string($0.0.name) })]
        if !rescale.isEmpty { o["rescaled"] = .object(rescale.reduce(into: [:]) { $0[nm[$1.key]?.name ?? ""] = .string("1:\($1.value)") }) }
        if !overflow.isEmpty {
            o["fit"] = .string(overflow.joined(separator: "; ") + ". Use a smaller scale (set_parameters {\"View Scale\": \(imperial ? "96" : "200")}), a bigger paper, or fewer views per sheet.")
        }
        return result(c, o, ids: ids)
    }

    func createSchedule(_ c: ToolContext) throws -> ToolOutput {
        let kind = try c.args.requireString("kind").lowercased()
        var def: ScheduleDefinition, base: String
        switch kind {
        case "doors", "door": def = ScheduleTemplates.doorSchedule(); base = "Door Schedule"
        case "windows", "window": def = ScheduleTemplates.windowSchedule(); base = "Window Schedule"
        case "rooms", "room": def = ScheduleTemplates.roomSchedule(); base = "Room Schedule"
        case "walls", "wall": def = ScheduleTemplates.wallQuantities(); base = "Wall Quantities"
        case "sheets", "sheet": def = ScheduleTemplates.sheetList(); base = "Sheet List"
        // AITOOLS: Furniture fabrication and component schedules, and any category with its fields.
        case "part_list": def = FabricationSchedules.partList(); base = "Part List"
        case "hardware": def = FabricationSchedules.hardwareSchedule(); base = "Hardware Schedule"
        case "edge_banding": def = FabricationSchedules.edgeBanding(); base = "Edge Banding"
        case "cost": def = FabricationSchedules.costSummary(); base = "Cost"
        case "material_takeoff": def = FabricationSchedules.materialTakeoff(); base = "Material Takeoff"
        case "component_bom": def = ComponentSchedules.bom(); base = "Component BOM"
        case "category":
            let cat = try Self.category(try c.args.requireString("category"))
            def = ScheduleDefinition(kind: .category, categories: [cat])
            for n in c.args.array("fields")?.compactMap(\.stringValue) ?? ["Type", "Count"] { def.fields.append(try scheduleField(n, def, try c.model())) }
            if let f = def.fields.first { def.sorting = [ScheduleSort(fieldID: f.id)] }
            def.grandTotals = true
            base = "\(cat.displayName) Schedule"
        default: throw ToolError("kind must be doors, windows, rooms, walls, sheets, part_list, hardware, edge_banding, cost, material_takeoff, component_bom or category (with category and fields).")
        }
        let m = try c.model()
        var name = c.args.string("name") ?? base
        if m.schedules.contains(where: { $0.name == name }) {
            if c.args.string("name") == nil { return result(c, ["schedule": m.schedules.first { $0.name == name }!.id.json, "name": .string(name), "note": "Already in the document."], ids: []) }
            throw ToolError("A schedule named “\(name)” exists.")
        }
        name = name.isEmpty ? base : name
        let r = try c.edit("Create Schedule") { tx in tx.create(.schedules, name: name, data: .schedule(def)) }
        let ids = ToolContext.created(r)
        let nm = try c.model()
        let rows = ids.first.flatMap { nm[$0] }.map { ScheduleEngine.compute($0, nm).rows.count } ?? 0
        return result(c, ["schedule": ids.first.map(\.json) ?? .null, "name": .string(name), "rows": .int(rows)], ids: ids)
    }

    // MARK: Dimensions and tags

    func addDimensions(_ c: ToolContext) throws -> ToolOutput {
        // AITOOLS: any view: plans (walls), sections and elevations (level heights, overall width), Furniture views (W, D, H).
        let view = try c.viewOrActive(kinds: [.floorPlan, .ceilingPlan, .structuralPlan, .areaPlan, .section, .elevation, .detail])
        let m = try c.model()
        let dimType = m.types(for: .dimensions).first { $0.name.lowercased().contains("linear") || $0.name == "Dimension" } ?? m.types(for: .dimensions).first
        var dims: [DimensionData] = []
        if let wv = c.args["walls"], let list = wv.arrayValue, !list.isEmpty, !c.args.bool("auto", default: false) {
            let walls = try c.elementIDs("walls").compactMap { m[$0] }
            guard walls.count >= 2, walls.allSatisfy({ $0.wall != nil }) else { throw ToolError("walls must be two or more wall ids.") }
            guard let at = c.args["at"] else { throw ToolError("Give “at”, a point the dimension line passes through.") }
            let kind: GeometryReference.Kind = switch c.args.string("reference") {
            case "exterior_face": .exteriorFace
            case "interior_face": .interiorFace
            default: .location
            }
            dims.append(DimensionData(kind: .aligned, references: walls.map { GeometryReference($0.id, kind) }, linePoint: try c.point(at, "at")))
        } else if c.args["elements"] != nil {
            let refs = try c.elementIDs("elements").map { GeometryReference($0, .location) }
            guard refs.count >= 2, let at = c.args["at"] else { throw ToolError("Give two or more elements and “at”, a point the dimension line passes through.") }
            dims.append(DimensionData(kind: .aligned, references: refs, linePoint: try c.point(at, "at")))
        } else if m.isFurniture {
            dims = try furnitureDimensions(c, view: view, m)
        } else if view.view?.kind.isVerticalCut == true {
            dims = try verticalDimensions(c, view: view, m)
        } else {
            guard let level = view.levelID else { throw ToolError("“\(view.name)” has no level.") }
            dims = try autoDimensions(c, level: level, m)
        }
        guard !dims.isEmpty else { throw ToolError("Nothing to dimension in “\(view.name)”.") }
        let r = try c.edit("Dimension") { tx in
            for d in dims { tx.create(.dimensions, data: .dimension(d), typeID: dimType?.id, ownerViewID: view.id) }
        }
        let ids = ToolContext.created(r)
        let nm = try c.model()
        let texts: [JSONValue] = ids.compactMap { nm[$0] }.map { e in
            guard let d = e.dimension, let l = DimensionLayout.make(e, d, nm, scale: Double(view.view?.scale ?? 100), view: view) else { return .null }
            return .string(l.values.map { c.formatLength($0, nm) }.joined(separator: " | "))
        }
        let fresh = Set(ids)
        let problems = DrawingCheck.dimensionProblems(nm[view.id] ?? view, nm).filter { !fresh.isDisjoint(with: $0.elements) }.map(\.message)
        return result(c, ["dimensions": .array(ids.map(\.json)), "view": .string(view.name), "strings": .array(texts)], ids: ids,
                      problems: problems + (problems.isEmpty ? [] : ["Fix with arrange_dimensions."]))
    }

    /// Sections and elevations: a chain through the levels at the left of the view, and the overall level-to-level height.
    func verticalDimensions(_ c: ToolContext, view: Element, _ m: BIMModel) throws(ToolError) -> [DimensionData] {
        let levels = m.levels.sorted { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) }
        guard levels.count >= 2 else { throw ToolError("A section or elevation needs two levels to dimension.") }
        let crop = view.view?.cropRegion ?? Rect2(min: Vec2(-10, levels.first!.level!.elevation), max: Vec2(10, levels.last!.level!.elevation))
        let scale = Double(view.view?.scale ?? 100)
        let x = crop.min.x + 0.012 * scale
        var out = [DimensionData(kind: .linear, references: levels.map { GeometryReference($0.id, .levelPlane) }, linePoint: Vec2(x, crop.center.y), direction: .pi / 2)]
        if levels.count > 2 {
            out.append(DimensionData(kind: .linear, references: [GeometryReference(levels.first!.id, .levelPlane), GeometryReference(levels.last!.id, .levelPlane)],
                                     linePoint: Vec2(x - 0.008 * scale, crop.center.y), direction: .pi / 2))
        }
        return out
    }

    /// Furniture views: overall width, depth or height between the piece's reference planes, outside the parts.
    func furnitureDimensions(_ c: ToolContext, view: Element, _ m: BIMModel) throws(ToolError) -> [DimensionData] {
        let planes = Dictionary(m.elements(.referencePlanes).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        guard let box = Self.furnitureBox(m) else { throw ToolError("The piece has no parts yet.") }
        let scale = Double(view.view?.scale ?? 12)
        let off = 0.012 * scale
        func pair(_ a: String, _ b: String) -> [GeometryReference]? {
            guard let pa = planes[a], let pb = planes[b] else { return nil }
            return [GeometryReference(pa.id, .location), GeometryReference(pb.id, .location)]
        }
        var out: [DimensionData] = []
        switch view.view?.kind {
        case .floorPlan?, .ceilingPlan?:
            if let r = pair("Left", "Right") { out.append(DimensionData(kind: .linear, references: r, linePoint: Vec2(0, box.min.y - off), direction: 0)) }
            if let r = pair("Front", "Back") { out.append(DimensionData(kind: .linear, references: r, linePoint: Vec2(box.max.x + off, 0), direction: .pi / 2)) }
        default:
            let d = view.view?.viewDirection ?? Vec2(0, 1)
            let widthPair = abs(d.y) >= abs(d.x) ? pair("Left", "Right") : pair("Front", "Back")
            let crop = view.view?.cropRegion ?? Rect2(min: Vec2(-1, box.min.z), max: Vec2(1, box.max.z))
            if let r = widthPair { out.append(DimensionData(kind: .linear, references: r, linePoint: Vec2(crop.center.x, box.min.z - off), direction: 0)) }
            if let r = pair("Bottom", "Top") { out.append(DimensionData(kind: .linear, references: r, linePoint: Vec2(crop.max.x - off / 2, (box.min.z + box.max.z) / 2), direction: .pi / 2)) }
        }
        guard !out.isEmpty else { throw ToolError("The piece's reference planes (Left, Right, Front, Back, Bottom, Top) are missing.") }
        return out
    }

    /// Overall and wall-by-wall strings on each side of the level's walls.
    func autoDimensions(_ c: ToolContext, level: ElementID, _ m: BIMModel) throws(ToolError) -> [DimensionData] {
        let frames = m.elements(.walls).filter { $0.levelID == level }.compactMap { WallGeometry.frame($0, m) }.filter { $0.isStraight }
        guard !frames.isEmpty else { throw ToolError("The view's level has no straight walls to dimension.") }
        let outline = try wallOutline(c, level: level, exterior: true)
        let box = Rect2(points: outline.points)
        let center = box.center
        let unit = m.units.system == .imperial ? 0.3048 : 1.0 / 3.28084
        let gap = try c.length("offset") ?? 4 * unit
        let step = 2.5 * unit
        func isVertical(_ f: WallFrame) -> Bool { let v = f.location.end - f.location.start; return abs(v.x) < abs(v.y) * 0.02 }
        func isHorizontal(_ f: WallFrame) -> Bool { let v = f.location.end - f.location.start; return abs(v.y) < abs(v.x) * 0.02 }
        /// The face of `f` farther from the building's centre (the outside face of an exterior wall).
        func outsideFace(_ f: WallFrame) -> GeometryReference.Kind {
            let e = f.exteriorFace.point(at: 0.5).distance(to: center), i = f.interiorFace.point(at: 0.5).distance(to: center)
            return e >= i ? .exteriorFace : .interiorFace
        }
        func faceCoord(_ f: WallFrame, _ k: GeometryReference.Kind, x: Bool) -> Double {
            let p = (k == .exteriorFace ? f.exteriorFace : f.interiorFace).point(at: 0.5)
            return x ? p.x : p.y
        }
        var out: [DimensionData] = []
        // Vertical walls give x stations (south and north strings); horizontal walls give y stations (west and east).
        for (walls, x) in [(frames.filter(isVertical), true), (frames.filter(isHorizontal), false)] {
            guard walls.count >= 2 else { continue }
            let pos = { (f: WallFrame) in x ? f.location.start.x : f.location.start.y }
            let lo = walls.min { pos($0) < pos($1) }!, hi = walls.max { pos($0) < pos($1) }!
            let loK = outsideFace(lo), hiK = outsideFace(hi)
            for side in [false, true] {
                // Side: south/west (false) or north/east (true). Chain: walls reaching that half, centre lines, outer faces at the ends.
                let mid = x ? center.y : center.x
                let reach = walls.filter { f in
                    let a = x ? min(f.location.start.y, f.location.end.y) : min(f.location.start.x, f.location.end.x)
                    let b = x ? max(f.location.start.y, f.location.end.y) : max(f.location.start.x, f.location.end.x)
                    return side ? b > mid : a < mid
                }
                var refs: [(Double, GeometryReference)] = [(faceCoord(lo, loK, x: x), GeometryReference(lo.id, loK))]
                for f in reach.sorted(by: { pos($0) < pos($1) }) where f.id != lo.id && f.id != hi.id {
                    let p = pos(f)
                    if refs.contains(where: { abs($0.0 - p) < 0.05 }) { continue }
                    refs.append((p, GeometryReference(f.id, .location)))
                }
                refs.append((faceCoord(hi, hiK, x: x), GeometryReference(hi.id, hiK)))
                refs.sort { $0.0 < $1.0 }
                let base = x ? (side ? box.max.y + gap : box.min.y - gap) : (side ? box.max.x + gap : box.min.x - gap)
                let sign = side ? 1.0 : -1.0
                let along = (x ? center.x : center.y)
                func pt(_ d: Double) -> Vec2 { x ? Vec2(along, d) : Vec2(d, along) }
                if refs.count > 2 { out.append(DimensionData(kind: .aligned, references: refs.map(\.1), linePoint: pt(base))) }
                out.append(DimensionData(kind: .aligned, references: [GeometryReference(lo.id, loK), GeometryReference(hi.id, hiK)],
                                         linePoint: pt(base + sign * (refs.count > 2 ? step : 0))))
            }
        }
        return out
    }

    func addTags(_ c: ToolContext) throws -> ToolOutput {
        let view = try c.viewOrActive()
        let m = try c.model()
        var cats: [Category] = []
        for s in c.args.array("categories")?.compactMap(\.stringValue) ?? ["doors", "windows", "rooms"] {
            guard let cat = Category(rawValue: s) ?? Category.allCases.first(where: { $0.displayName.lowercased() == s.lowercased() }) else {
                throw ToolError("Unknown category “\(s)”. Use e.g. doors, windows, rooms, walls, furniture.")
            }
            cats.append(cat)
        }
        var types: [Category: ElementID] = [:]
        var missing: [String] = []
        for cat in cats { if let t = TagTool.defaultTagType(for: cat, m) { types[cat] = t } else { missing.append(cat.rawValue) } }
        let visible = Set(ViewGraphicsBuilder(model: m, view: view).build().items.compactMap(\.elementID))
        var count = 0
        let only = c.args["elements"] != nil ? Set(try c.elementIDs("elements")) : nil
        let opts = TagAllOptions(tagTypes: types, onlyElements: only, leader: c.args.bool("leader", default: false))
        let r = try c.edit("Tag All") { tx in
            count = TagAll.run(opts, view: view.id, visible: visible, scale: view.view?.scale ?? 100, in: tx)
        }
        let ids = ToolContext.created(r)
        var o: [String: JSONValue] = ["tagged": .int(count), "view": .string(view.name)]
        if !missing.isEmpty { o["no_tag_family"] = .array(missing.map { .string($0) }) }
        let nm = try c.model()
        let left = TagAll.untagged(in: view.id, visible: visible, nm).filter { cats.contains($0.key) && types[$0.key] != nil }
            .map { k, v in v.filter { only?.contains($0) ?? true }.count > 0 ? "\(v.filter { only?.contains($0) ?? true }.count) \(k.displayName.lowercased()) still untagged" : nil }.compactMap { $0 }
        return result(c, o, ids: ids, problems: left + missing.map { "No tag family loads for \($0)." })
    }
}
