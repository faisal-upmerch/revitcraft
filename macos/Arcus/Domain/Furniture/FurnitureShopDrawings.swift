import Foundation
import ArcusGeometry

// FM7: the shop drawing set of a Furniture document (Docs/FurnitureMode.md §3 "Shop drawings"):
//   F101 Shop Drawing: plan, Front and Right elevations, Section A and {3D}, with the labelled dimensions and Part Tags;
//   F102 Part List: the Part List and the Hardware Schedule;
//   F103 Nesting: one Nesting view per material and thickness;
//   F104 3D and Costs: a 3D view from the back at Fine (joints and machining show), Edge Banding and Cost.
// Every sheet uses the Furniture Title Block (piece, category, material, designer, date, sheet). The template makes
// the sheets, schedules and views (`ensureStandard`); Fabricate ▸ Shop Drawings and Nesting (`update`) tag the parts,
// make the Nesting views and arrange the sheets at a scale that fits.

public enum FurnitureNestingViews {
    /// A Nesting view's group: "<material id>|<thickness in 1/64 in>" (NestingGroup.key).
    public static let groupParam = ParameterID("furniture.nesting.group")
    /// Nesting views are drawn at 1/2" = 1'-0" until the sheet arrangement picks another scale.
    public static let defaultScale = 24

    /// The model's Nesting views, by name.
    public static func views(_ m: BIMModel) -> [Element] {
        m.views.filter { $0.view?.kind == .nesting }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The Nesting view showing `key`, if any.
    public static func view(for key: String, _ m: BIMModel) -> Element? {
        m.views.first { $0.view?.kind == .nesting && $0.params[groupParam]?.textValue == key }
    }

    /// Makes a Nesting view for every material and thickness that has none (named "Plywood 3/4\""); returns the views
    /// of the current groups, in group order.
    @discardableResult
    public static func update(in tx: TransactionContext) -> [ElementID] {
        guard tx.model.isFurniture else { return [] }
        var out: [ElementID] = []
        for g in FurnitureFabrication.nesting(tx.model) {
            if let v = view(for: g.key, tx.model) { out.append(v.id); continue }
            var name = g.title, n = 2
            let taken = Set(tx.model.views.filter { $0.view?.kind == .nesting }.map(\.name))
            while taken.contains(name) { name = "\(g.title) (\(n))"; n += 1 }
            let vd = ViewData(kind: .nesting, scale: defaultScale)
            out.append(tx.create(.views, name: name, data: .view(vd)) { $0.params[groupParam] = .text(g.key) })
        }
        return out
    }
}

public enum FurnitureShopDrawings {
    static let inch = 0.0254
    public static let titleBlockName = "Furniture Title Block"
    /// Sheet numbers of the set.
    public static let shopDrawing = "F101", partList = "F102", nesting = "F103", details = "F104"
    /// The view names the set adds.
    public static let sectionName = "Section A", back3DName = "Back 3D"
    /// Schedule names of the set.
    public static let partListName = "Part List", hardwareName = "Hardware Schedule", takeoffName = "Material Takeoff", bandingName = "Edge Banding",
                      costName = "Cost"
    /// The scales arrangement tries, finest first.
    static let scales = [8, 12, 16, 24, 32, 48, 64, 96]

    // MARK: Template

    /// The Furniture Title Block, Baltic Birch, the cost globals, the fabrication schedules, Section A, Back 3D and
    /// sheets F102–F104 (with F101's title block switched to the Furniture one), where missing; idempotent.
    public static func ensureStandard(in tx: TransactionContext) {
        guard tx.model.isFurniture else { return }
        ensureMaterial(in: tx)
        ensureGlobals(in: tx)
        let tb = ensureTitleBlock(in: tx)
        func schedule(_ name: String, _ kind: ScheduleKind, _ make: () -> ScheduleDefinition) -> ElementID {
            if let e = tx.model.elements(.schedules).first(where: { $0.schedule?.kind == kind && (kind != .materialTakeoff || $0.name == name) }) { return e.id }
            return tx.create(.schedules, name: name, data: .schedule(make()))
        }
        let parts = schedule(partListName, .partList, FabricationSchedules.partList)
        let hardware = schedule(hardwareName, .hardwareSchedule, FabricationSchedules.hardwareSchedule)
        _ = schedule(takeoffName, .materialTakeoff, FabricationSchedules.materialTakeoff)
        let banding = schedule(bandingName, .edgeBanding, FabricationSchedules.edgeBanding)
        let cost = schedule(costName, .costSummary, FabricationSchedules.costSummary)

        // Section A: across the piece at its centre, looking at the right half (shelves, back and joints cut).
        let phase = tx.model.latestPhase?.id
        if !tx.model.views.contains(where: { $0.name == sectionName && $0.view?.kind == .section }) {
            var sv = ViewData(kind: .section, scale: FurnitureTemplates.viewScale)
            sv.viewDirection = Vec2(1, 0)
            sv.planeOrigin = Vec3(0, 0, 0)
            sv.farClip = 1.5
            sv.phaseID = phase
            sv.detailLevel = .fine
            tx.create(.views, name: sectionName, data: .view(sv)) { $0.params[FurnitureViews.autoCrop] = .bool(true) }
        }
        if !tx.model.views.contains(where: { $0.name == back3DName && $0.view?.kind == .threeD }) {
            var v3 = ViewData(kind: .threeD, scale: FurnitureTemplates.viewScale)
            v3.camera = Camera3D(eye: Vec3(1.8, 2.2, 1.4), target: Vec3(0, 0, FurnitureTemplates.defaultHeight / 2), orthoHeight: 1.5)
            v3.phaseID = phase
            v3.detailLevel = .fine
            tx.create(.views, name: back3DName, data: .view(v3))
        }

        // Sheets.
        func sheet(_ number: String, _ name: String) -> ElementID {
            if let s = tx.model.sheets.first(where: { $0.sheet?.number == number }) {
                if let tb, s.sheet?.titleBlockTypeID != tb, tx.model[s.sheet?.titleBlockTypeID]?.typeData?.familyName == "Tabloid Title Block" {
                    tx.update(s.id) { $0.sheet?.titleBlockTypeID = tb }
                }
                return s.id
            }
            return tx.create(.sheets, name: name, data: .sheet(SheetData(number: number, paper: .ansiB, titleBlockTypeID: tb)))
        }
        _ = sheet(shopDrawing, "Shop Drawing")
        let f102 = sheet(partList, "Part List")
        _ = sheet(nesting, "Nesting")
        let f104 = sheet(details, "3D and Costs")
        if let s = tx.model.views.first(where: { $0.name == sectionName && $0.view?.kind == .section }), tx.model.viewports(showing: s.id).isEmpty,
           let f101 = tx.model.sheets.first(where: { $0.sheet?.number == shopDrawing }) {
            // Section A joins F101: the sheet is laid out again in three columns.
            _ = try? SheetPlacement.place(s.id, onSheet: f101.id, at: Vec2(0.17, 0.08), in: tx)
            arrangeShopDrawing(f101.id, in: tx)
        }
        if let b = tx.model.views.first(where: { $0.name == back3DName }), tx.model.viewports(showing: b.id).isEmpty {
            _ = try? SheetPlacement.place(b.id, onSheet: f104, at: Vec2(0.09, 0.17), in: tx)
        }
        for (id, sheetID) in [(parts, f102), (hardware, f102), (banding, f104), (cost, f104)]
        where !tx.model.viewports(showing: id).contains(where: { $0.ownerViewID == sheetID }) {
            _ = try? SheetPlacement.place(id, onSheet: sheetID, at: Vec2(0.17, 0.14), in: tx)
        }
        arrangeSchedules(f102, in: tx)
        arrangeSchedules(f104, in: tx)
    }

    static func ensureMaterial(in tx: TransactionContext) {
        guard !tx.model.elements(.materials).contains(where: { $0.name == FurnitureFabrication.balticBirch }) else { return }
        let patterns = MaterialPatternDefaults.patternIndex(tx.model)
        var m = MaterialData(materialClass: .wood, color: RGBColor(hex: 0xE4CDA2), transparency: 0, description: "Baltic birch plywood, 3/4\", 5'x5' sheet")
        MaterialPatternDefaults.apply(to: &m, name: "Plywood", patterns: patterns)
        m.cost = 110
        m.costUnit = .sheet
        tx.create(.materials, name: FurnitureFabrication.balticBirch, data: .material(m))
    }

    /// Labor Hours, Labor Rate and Markup (Manage ▸ Global Parameters), which the Cost schedule reads.
    static func ensureGlobals(in tx: TransactionContext) {
        var list = GlobalParameters.all(tx.model)
        let want: [(String, ParamType, ParamValue)] = [(FabricationSchedules.laborHours, .number, .double(0)), (FabricationSchedules.laborRate, .currency, .double(45)),
                                                       (FabricationSchedules.markup, .percentage, .double(0))]
        var changed = false
        for (n, t, v) in want where !list.contains(where: { $0.name == n }) {
            list.append(GlobalParameter(name: n, type: t, group: .other, value: v))
            changed = true
        }
        if changed { try? GlobalParameters.set(list, in: tx) }
    }

    /// The Furniture Title Block (Tabloid): the starter title block with the piece's rows (Piece, Category, Material,
    /// Designed By) in place of the project's.
    static func ensureTitleBlock(in tx: TransactionContext) -> ElementID? {
        if let t = tx.model.elements(.elementTypes).first(where: { $0.typeData?.familyName == titleBlockName }) { return t.id }
        let size = PaperSize.ansiB.landscapeSize
        var f = StarterLibrary.titleBlock(titleBlockName, width: size.x, height: size.y)
        let rename: [String: (String, String)] = ["Project Name": ("Piece Name", "PIECE"), "Project Number": ("Piece Material", "MATERIAL"),
                                                  "Client Name": ("Piece Category", "CATEGORY"), "Checked By": ("Designed By", "DESIGNER")]
        let captions: [String: String] = ["PROJECT": "PIECE", "PROJECT NO.": "MATERIAL", "CLIENT": "CATEGORY", "CHECKED": "DESIGNER"]
        for i in f.labels.indices {
            if let p = f.labels[i].parameterName, let (n, sample) = rename[p] { f.labels[i].parameterName = n; f.labels[i].sample = sample }
            if let c = captions[f.labels[i].staticText] { f.labels[i].staticText = c }
        }
        let fid = tx.create(.families, name: f.name, data: .family(f))
        return tx.create(.elementTypes, name: f.name, data: .type(TypeData(instanceCategory: .titleBlocks, familyID: fid, familyName: f.name)))
    }

    /// Values of the Furniture Title Block's piece labels.
    public static func titleBlockValue(_ name: String, _ m: BIMModel) -> String? {
        guard let s = m.furnitureSetup else { return nil }
        switch name {
        case "Piece Name": return s.name
        case "Piece Category": return s.category == .casework ? "Casework" : "Furniture"
        case "Piece Material":
            let values = FamilyEvaluator.parameterValues(s.family, typeName: s.currentType, units: m.units).values
            if case .quantity(let d, _)? = values["Material"] { return m[ElementID(UInt64(max(0, d.rounded())))]?.name ?? "" }
            return ""
        default: return nil
        }
    }

    // MARK: Update

    /// Fabricate ▸ Shop Drawings: the set's sheets and schedules, Part Tags in the Front elevation (and the back in
    /// Section A), the Nesting views, and F101–F104 arranged at scales that fit.
    public static func update(in tx: TransactionContext) {
        guard tx.model.isFurniture else { return }
        ensureStandard(in: tx)
        tagParts(in: tx)
        let nestingViews = FurnitureNestingViews.update(in: tx)
        if let f101 = sheetID(shopDrawing, tx.model) { arrangeShopDrawing(f101, in: tx) }
        if let f103 = sheetID(nesting, tx.model) {
            let n = nestingViews.count
            arrange(nestingViews, onSheet: f103, columns: n <= 1 ? 1 : (n <= 4 ? 2 : 3), in: tx)
        }
        if let f104 = sheetID(details, tx.model), let b = tx.model.views.first(where: { $0.name == back3DName }) {
            arrange([b.id], onSheet: f104, columns: 1, area: Rect2(min: Vec2(0.02, 0.01), max: Vec2(0.17, 0.2694)), in: tx)
        }
        if let f102 = sheetID(partList, tx.model) { arrangeSchedules(f102, in: tx) }
        if let f104 = sheetID(details, tx.model) { arrangeSchedules(f104, in: tx, left: 0.18) }
    }

    /// F101: plan, Section A and {3D} over the Front and Right elevations.
    static func arrangeShopDrawing(_ f101: ElementID, in tx: TransactionContext) {
        let views = ["Ref. Level", sectionName, "{3D}", "Front", "Right"].compactMap { n in tx.model.views.first { $0.name == n && $0.view?.kind != .nesting }?.id }
        arrange(views, onSheet: f101, columns: 3, in: tx)
    }

    static func sheetID(_ number: String, _ m: BIMModel) -> ElementID? { m.sheets.first { $0.sheet?.number == number }?.id }

    /// Part Tags (Mark and size) on every untagged part: in the Front elevation, and the backs in Section A.
    static func tagParts(in tx: TransactionContext) {
        guard let tagType = tx.model.types(for: .tags).first(where: { $0.typeData?.familyName == "Part Tag" })?.id else { return }
        let front = tx.model.views.first { $0.name == "Front" && $0.view?.kind == .elevation }
        let section = tx.model.views.first { $0.name == sectionName && $0.view?.kind == .section }
        let parts = tx.model.elements(Category.furnitureParts.filter { $0 != .furnitureEdgeProfiles && $0 != .furnitureForms }).filter { !$0.isType }
        for (view, wanted) in [(front, { (e: Element) in e.furniturePanel?.role != .back }), (section, { (e: Element) in e.furniturePanel?.role == .back })] {
            guard let view, let vd = view.view, let right = vd.rightVector, let origin = vd.planeOrigin else { continue }
            let tagged = Set(tx.model.owned(byView: view.id).compactMap { $0.tag?.taggedID })
            var heads = tx.model.owned(byView: view.id).compactMap { $0.tag?.head }
            for e in parts.sorted(by: { $0.id < $1.id }) where wanted(e) && !tagged.contains(e.id) {
                guard let box = FurniturePartSolids.partBox(e, tx.model)?.box else { continue }
                let c = (box.min + box.max) * 0.5
                var head = Vec2((Vec2(c.x, c.y) - Vec2(origin.x, origin.y)).dot(right), c.z)
                while heads.contains(where: { $0.distance(to: head) < 1.25 * inch }) { head.y += 1.5 * inch }
                heads.append(head)
                tx.create(.tags, data: .tag(TagData(taggedID: e.id, head: head)), typeID: tagType, ownerViewID: view.id)
            }
        }
    }

    /// The drawing area of a Tabloid sheet left of the title block strip.
    static let drawingArea = Rect2(min: Vec2(0.02, 0.01), max: Vec2(0.3268, 0.2694))

    /// Places `views` on the sheet in a grid of `columns`, every view at the finest common scale that fits its cell
    /// (views already on another sheet are left there).
    static func arrange(_ views: [ElementID], onSheet sheetID: ElementID, columns: Int, area: Rect2 = drawingArea, in tx: TransactionContext) {
        let ids = views.filter { v in tx.model.viewports(showing: v).allSatisfy { $0.ownerViewID == sheetID } }
        guard !ids.isEmpty else { return }
        let cols = max(1, min(columns, ids.count)), rows = (ids.count + cols - 1) / cols
        let cell = Vec2(area.width / Double(cols), area.height / Double(rows))
        // Room for the viewport title under each view.
        let room = Vec2(cell.x - 0.012, cell.y - 0.02)
        func region(_ id: ElementID) -> Rect2 {
            guard let v = tx.model[id] else { return Rect2(center: .zero, halfSize: Vec2(0.5, 0.5)) }
            if let c = v.view?.cropRegion, v.view?.cropActive == true { return c }
            return SheetGraphicsBuilder.viewRegion(ViewGraphicsBuilder(model: tx.model, view: v).build())
        }
        let regions = ids.map(region)
        let scale = scales.first { s in regions.allSatisfy { $0.width / Double(s) <= room.x && $0.height / Double(s) <= room.y } } ?? scales.last!
        for (k, id) in ids.enumerated() {
            let r = k / cols, c = k % cols
            let center = Vec2(area.min.x + cell.x * (Double(c) + 0.5), area.max.y - cell.y * (Double(r) + 0.5) + 0.006)
            if tx.model[id]?.view?.scale != scale { tx.update(id) { $0.view?.scale = scale } }
            if let vp = tx.model.viewports(showing: id).first(where: { $0.ownerViewID == sheetID }) {
                if vp.viewport?.center != center { tx.update(vp.id) { $0.viewport?.center = center } }
            } else {
                _ = try? SheetPlacement.place(id, onSheet: sheetID, at: center, in: tx)
            }
        }
    }

    /// Stacks a sheet's schedules from the top left of the drawing area (starting at `left`), a column at a time.
    static func arrangeSchedules(_ sheetID: ElementID, in tx: TransactionContext, left: Double = drawingArea.min.x) {
        let vps = tx.model.owned(byView: sheetID).filter { $0.viewport != nil && tx.model[$0.viewport?.viewID]?.schedule != nil }
        var x = left + 0.006, y = drawingArea.max.y - 0.006, column = 0.0
        for vp in vps {
            guard let s = tx.model[vp.viewport?.viewID] else { continue }
            let t = ScheduleEngine.compute(s, tx.model)
            let w = t.totalWidth, h = ScheduleLayout.height(t, rows: vp.viewport?.scheduleRows)
            if y - h < drawingArea.min.y + 0.006, column > 0 { x += column + 0.01; y = drawingArea.max.y - 0.006; column = 0 }
            let center = Vec2(x + w / 2, y - h / 2)
            if vp.viewport?.center != center { tx.update(vp.id) { $0.viewport?.center = center } }
            y -= h + 0.01
            column = max(column, w)
        }
    }
}
