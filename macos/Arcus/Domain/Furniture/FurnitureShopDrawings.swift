import Foundation
import ArcusGeometry

// FM7: the shop drawing set of a Furniture document (Docs/FurnitureMode.md §3 "Shop drawings"):
//   F101 Shop Drawing: plan, Front and Right elevations, Section A and {3D}, with the labelled dimensions and Part Tags;
//   F102 Part List: the Part List and the Hardware Schedule;
//   F103 Nesting: one Nesting view per material and thickness;
//   F104 3D and Costs: a 3D view from the back at Fine (joints and machining show), exploded with its parts tagged
//   (FMG2: Explode Parts), Edge Banding and Cost.
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
    static let scales = [4, 8, 12, 16, 24, 32, 48, 64, 96] // POLISH: 3" = 1'-0" for small pieces

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
            v3.titleOnSheet = "Exploded View" // FMG2
            tx.create(.views, name: back3DName, data: .view(v3)) { $0.params[FurnitureExplode.onParam] = .bool(true) } // FMG2: Explode Parts
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
        where tx.model.viewports(showing: id).isEmpty { // POLISH: a schedule moved to F104 (no room on F102) stays there
            _ = try? SheetPlacement.place(id, onSheet: sheetID, at: Vec2(0.17, 0.14), in: tx)
        }
        arrangeSchedules(f102, in: tx)
        arrangeSchedules(f104, in: tx, left: 0.17)
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

    /// The Furniture Title Block (Tabloid): border, a strip on the right with the organization, revisions and the
    /// piece's rows (Piece, Category, Material, Designed By, Drawn By, Date, Scale, Sheet Name, Sheet Number).
    static func ensureTitleBlock(in tx: TransactionContext) -> ElementID? {
        if let t = tx.model.elements(.elementTypes).first(where: { $0.typeData?.familyName == titleBlockName }) { return t.id }
        let f = titleBlockFamily()
        let fid = tx.create(.families, name: f.name, data: .family(f))
        return tx.create(.elementTypes, name: f.name, data: .type(TypeData(instanceCategory: .titleBlocks, familyID: fid, familyName: f.name)))
    }

    static func titleBlockFamily() -> FamilyDefinition {
        let size = PaperSize.ansiB.landscapeSize, w = size.x, h = size.y
        var f = FamilyDefinition(name: titleBlockName, template: .titleBlock)
        f.types = [FamilyTypeDefinition(name: titleBlockName, values: [:])]
        func n(_ v: Double) -> String { String(format: "%.4f", v) }
        func line(_ a: (Double, Double), _ b: (Double, Double), _ weight: Int) -> FamilyLine {
            FamilyLine(shape: .line(FamilyPoint(n(a.0), n(a.1)), FamilyPoint(n(b.0), n(b.1))), weight: weight)
        }
        let left = 0.02, m = 0.01, stripW = min(0.19, w * 0.22), sx = w - m - stripW
        var lines = [line((left, m), (w - m, m), 5), line((w - m, m), (w - m, h - m), 5), line((w - m, h - m), (left, h - m), 5), line((left, h - m), (left, m), 5),
                     line((sx, m), (sx, h - m), 3)]
        // Rows from the bottom up: height, label parameter, caption, text height, bold.
        let rows: [(Double, String, String, Double, Bool)] = [
            (0.03, "Sheet Number", "SHEET", 0.009, true), (0.024, "Sheet Name", "TITLE", 0.0038, true), (0.016, "Scale", "SCALE", 0.0024, false),
            (0.016, "Sheet Issue Date", "DATE", 0.0024, false), (0.016, "Drawn By", "DRAWN", 0.0024, false), (0.016, "Designed By", "DESIGNER", 0.0024, false),
            (0.02, "Piece Material", "MATERIAL", 0.003, false), (0.018, "Piece Category", "CATEGORY", 0.003, false), (0.03, "Piece Name", "PIECE", 0.0045, true),
        ]
        var y = m
        var labels: [FamilyLabel] = []
        for (rh, param, caption, textH, bold) in rows {
            let top = y + rh
            lines.append(line((sx, top), (w - m, top), 2))
            labels.append(FamilyLabel(position: FamilyPoint(n(sx + 0.003), n(top - 0.0032)), parameterName: nil, staticText: caption, height: 0.0013, alignment: .left))
            labels.append(FamilyLabel(position: FamilyPoint(n(sx + 0.005), n(y + rh * 0.3)), parameterName: param, height: textH, alignment: .left, bold: bold, sample: caption))
            y = top
        }
        labels.append(FamilyLabel(position: FamilyPoint(n(sx + 0.003), n(y + 0.004)), parameterName: "Revision Schedule", height: 0.0016))
        labels.append(FamilyLabel(position: FamilyPoint(n(sx + stripW / 2), n(h - m - 0.009)), parameterName: "Organization", height: 0.0038, alignment: .center, bold: true))
        f.annotationLines = lines
        f.labels = labels
        f.parameters = [FamilyParameter(name: "Sheet Width", type: .length, isInstance: true), FamilyParameter(name: "Sheet Height", type: .length, isInstance: true)]
        return f
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
        updateNesting(in: tx)
        // POLISH: tags are laid out at the views' scale and take room on the sheet, so arrange, tag, and arrange again
        // until the scale holds (the tags this run made follow a new scale; tags placed before are left alone).
        var made: Set<ElementID> = []
        for _ in 0..<3 {
            let before = shopDrawingScales(tx.model)
            if let f101 = sheetID(shopDrawing, tx.model) { arrangeShopDrawing(f101, in: tx) }
            let scales = shopDrawingScales(tx.model)
            if !made.isEmpty && scales == before { break }
            made = tagParts(in: tx, relayout: made)
        }
        if let f101 = sheetID(shopDrawing, tx.model) { arrangeShopDrawing(f101, in: tx) }
        if let f104 = sheetID(details, tx.model), let b = tx.model.views.first(where: { $0.name == back3DName }) {
            // FMG2: Back 3D of older documents explodes too (unless the user turned it off).
            if b.params[FurnitureExplode.onParam] == nil { tx.update(b.id) { $0.params[FurnitureExplode.onParam] = .bool(true) } }
            arrange([b.id], onSheet: f104, columns: 1, area: Rect2(min: Vec2(0.02, 0.01), max: Vec2(0.165, 0.2694)), in: tx)
        }
        if let f102 = sheetID(partList, tx.model) {
            // POLISH: schedules that don't fit on F102 below the Part List go on to F104, under Edge Banding and Cost.
            let over = arrangeSchedules(f102, in: tx).filter { tx.model[tx.model[$0]?.viewport?.viewID]?.schedule?.kind != .partList }
            if let f104 = sheetID(details, tx.model), !over.isEmpty {
                for vp in over { tx.update(vp) { $0.ownerViewID = f104 } }
                arrangeSchedules(f102, in: tx)
            }
        }
        if let f104 = sheetID(details, tx.model) { arrangeSchedules(f104, in: tx, left: 0.17) }
    }

    /// F101: plan, Section A and {3D} over the Front and Right elevations. POLISH: in three columns, or two when that
    /// gives a larger scale (small pieces).
    static func arrangeShopDrawing(_ f101: ElementID, in tx: TransactionContext) {
        let views = ["Ref. Level", sectionName, "{3D}", "Front", "Right"].compactMap { n in tx.model.views.first { $0.name == n && $0.view?.kind != .nesting }?.id }
        let three = fittingScale(views, onSheet: f101, columns: 3, in: tx), two = fittingScale(views, onSheet: f101, columns: 2, in: tx)
        arrange(views, onSheet: f101, columns: two < three ? 2 : 3, in: tx)
    }

    /// The scales of F101's views, to tell when an arrangement has settled.
    static func shopDrawingScales(_ m: BIMModel) -> [Int] {
        guard let f101 = sheetID(shopDrawing, m) else { return [] }
        return m.owned(byView: f101).compactMap { m[$0.viewport?.viewID]?.view?.scale }
    }

    /// Fabricate ▸ Nesting: a Nesting view per material and thickness, arranged on F103. Returns the current groups' views.
    @discardableResult
    public static func updateNesting(in tx: TransactionContext) -> [ElementID] {
        guard tx.model.isFurniture else { return [] }
        if sheetID(nesting, tx.model) == nil { ensureStandard(in: tx) }
        let views = FurnitureNestingViews.update(in: tx)
        if let f103 = sheetID(nesting, tx.model) {
            let n = views.count
            // Groups stack in one column (each is a row of up to three sheets); more than four groups take two columns.
            arrange(views, onSheet: f103, columns: n <= 4 ? 1 : 2, in: tx)
        }
        return views
    }

    static func sheetID(_ number: String, _ m: BIMModel) -> ElementID? { m.sheets.first { $0.sheet?.number == number }?.id }

    /// Part Tags (Mark and size) on every untagged part: in the Front elevation, and the backs in Section A. POLISH:
    /// laid out with `FurnitureTagLayout` (columns beside the piece, clear of dimensions, labels and each other); the
    /// tags in `relayout` (made by an earlier pass at another scale) are laid out again. Returns the tags made or moved.
    @discardableResult
    static func tagParts(in tx: TransactionContext, relayout: Set<ElementID> = []) -> Set<ElementID> {
        guard let tagType = tx.model.types(for: .tags).first(where: { $0.typeData?.familyName == "Part Tag" })?.id else { return [] }
        let front = tx.model.views.first { $0.name == "Front" && $0.view?.kind == .elevation }
        let section = tx.model.views.first { $0.name == sectionName && $0.view?.kind == .section }
        let parts = tx.model.elements(Category.furnitureParts.filter { $0 != .furnitureEdgeProfiles && $0 != .furnitureForms }).filter { !$0.isType }
        var out: Set<ElementID> = []
        for (view, wanted) in [(front, { (e: Element) in e.furniturePanel?.role != .back }), (section, { (e: Element) in e.furniturePanel?.role == .back })] {
            guard let view, let vd = view.view, let right = vd.rightVector, let origin = vd.planeOrigin else { continue }
            let tags = tx.model.owned(byView: view.id).filter { $0.tag != nil }
            let mine = Dictionary(tags.filter { relayout.contains($0.id) }.compactMap { t in t.tag.map { ($0.taggedID, t.id) } }, uniquingKeysWith: { a, _ in a })
            let tagged = Set(tags.compactMap { $0.tag?.taggedID })
            var anchors: [(id: ElementID, anchor: Vec2)] = []
            for e in parts.sorted(by: { $0.id < $1.id }) where wanted(e) && (!tagged.contains(e.id) || mine[e.id] != nil) {
                guard let box = FurniturePartSolids.partBox(e, tx.model)?.box else { continue }
                let c = (box.min + box.max) * 0.5
                anchors.append((e.id, Vec2((Vec2(c.x, c.y) - Vec2(origin.x, origin.y)).dot(right), c.z)))
            }
            guard !anchors.isEmpty else { continue }
            // Everything the view will show once its annotation crop takes in the tags (level heads beside the piece too).
            var wide = view
            wide.view?.annotationCropOffset = max(vd.annotationCropOffset, 0.06)
            let g = ViewGraphicsBuilder(model: tx.model, view: wide).build()
            let scene = FurnitureTagLayout.scene(g, skipping: Set(mine.values))
            let placements = FurnitureTagLayout.layout(anchors, outline: scene.outline, obstacles: scene.obstacles, scale: vd.scale)
            var reach = 0.0
            for p in placements {
                var t = TagData(taggedID: p.part, head: p.head, hasLeader: true)
                t.leaderEnd = p.anchor
                t.leaderElbow = p.elbow
                if let id = mine[p.part] {
                    if tx.model[id]?.tag != t { tx.update(id) { $0.data = .tag(t) } }
                    out.insert(id)
                } else {
                    out.insert(tx.create(.tags, data: .tag(t), typeID: tagType, ownerViewID: view.id))
                }
                if let crop = vd.cropRegion {
                    let b = FurnitureTagLayout.box(p.head, scale: vd.scale)
                    reach = max(reach, crop.min.x - b.min.x, b.max.x - crop.max.x, crop.min.y - b.min.y, b.max.y - crop.max.y)
                }
            }
            // The annotation crop takes in the tags (paper), so neither the view nor its viewport cuts them off.
            let need = reach / Double(max(vd.scale, 1)) + 0.003
            if vd.cropActive, need > vd.annotationCropOffset { tx.update(view.id) { $0.view?.annotationCropOffset = need } }
        }
        return out
    }

    /// The drawing area of a Tabloid sheet left of the title block strip.
    static let drawingArea = Rect2(min: Vec2(0.02, 0.01), max: Vec2(0.3268, 0.2694))

    /// Places `views` on the sheet in a grid of `columns`, every view at the finest common scale that fits its cell
    /// (views already on another sheet are left there).
    static func arrange(_ views: [ElementID], onSheet sheetID: ElementID, columns: Int, area: Rect2 = drawingArea, in tx: TransactionContext) {
        guard let plan = gridPlan(views, onSheet: sheetID, columns: columns, area: area, in: tx) else { return }
        for (id, center) in plan.centers {
            if tx.model[id]?.view?.scale != plan.scale { tx.update(id) { $0.view?.scale = plan.scale } }
            if let vp = tx.model.viewports(showing: id).first(where: { $0.ownerViewID == sheetID }) {
                if vp.viewport?.center != center { tx.update(vp.id) { $0.viewport?.center = center } }
            } else {
                _ = try? SheetPlacement.place(id, onSheet: sheetID, at: center, in: tx)
            }
        }
    }

    /// The scale `arrange` would choose for `columns` (POLISH: to compare layouts).
    static func fittingScale(_ views: [ElementID], onSheet sheetID: ElementID, columns: Int, area: Rect2 = drawingArea, in tx: TransactionContext) -> Int {
        gridPlan(views, onSheet: sheetID, columns: columns, area: area, in: tx)?.scale ?? scales.last!
    }

    /// The grid arrangement: the finest scale at which every view fits its cell, and each viewport's centre.
    static func gridPlan(_ views: [ElementID], onSheet sheetID: ElementID, columns: Int, area: Rect2, in tx: TransactionContext) -> (scale: Int, centers: [(ElementID, Vec2)])? {
        let ids = views.filter { v in tx.model.viewports(showing: v).allSatisfy { $0.ownerViewID == sheetID } }
        guard !ids.isEmpty else { return nil }
        let cols = max(1, min(columns, ids.count)), rows = (ids.count + cols - 1) / cols
        let groups = FurnitureFabrication.nesting(tx.model)
        // Cropped views: the crop, and how far their annotations (dimensions, datum labels, Part Tags) reach past it
        // on paper, each side (POLISH: so tags and dimensions don't run into the next view).
        var fixed: [ElementID: (base: Rect2, reach: (l: Double, r: Double, b: Double, t: Double))] = [:]
        func measured(_ id: ElementID, _ v: Element) -> (base: Rect2, reach: (l: Double, r: Double, b: Double, t: Double)) {
            if let f = fixed[id] { return f }
            let g = ViewGraphicsBuilder(model: tx.model, view: v).build()
            let base = SheetGraphicsBuilder.viewRegion(g)
            var all = base
            if v.view?.cropActive == true, v.view?.cropRegion != nil {
                let ac = base.expanded(by: Double(max(g.scale, 1)) * max(SheetGraphicsBuilder.annotationMargin, v.view?.annotationCropOffset ?? 0))
                for o in FurnitureTagLayout.scene(g).obstacles { all.include(o.intersection(ac)) }
            }
            let k = 1 / Double(max(g.scale, 1))
            let f = (base, (l: (base.min.x - all.min.x) * k, r: (all.max.x - base.max.x) * k, b: (base.min.y - all.min.y) * k, t: (all.max.y - base.max.y) * k))
            fixed[id] = f
            return f
        }
        // A view's region on the sheet at scale `s` (Nesting views leave room for their titles at their scale), and the
        // offset on paper of its centre from the centre of what the viewport draws.
        func region(_ id: ElementID, _ s: Int) -> (rect: Rect2, offset: Vec2) {
            guard let v = tx.model[id] else { return (Rect2(center: .zero, halfSize: Vec2(0.5, 0.5)), .zero) }
            if v.view?.kind == .nesting {
                let key = v.params[FurnitureNestingViews.groupParam]?.textValue
                return (NestingLayout(groups.first { $0.key == key }, scale: s).sheetBounds, .zero)
            }
            let m = measured(id, v), d = Double(s)
            var r = Rect2(min: m.base.min - Vec2(m.reach.l, m.reach.b) * d, max: m.base.max + Vec2(m.reach.r, m.reach.t) * d)
            // The view title starts under the view's left edge and runs on past a narrow view (SheetGraphicsBuilder.viewTitle).
            let title = (v.view?.titleOnSheet.isEmpty == false ? v.view!.titleOnSheet : v.name).uppercased()
            let titleWidth = 0.0101 + max(0.04, Double(title.count) * 0.0024 + 0.02) + 0.003
            r.max.x = max(r.max.x, m.base.min.x + titleWidth * d)
            return (r, (r.center - m.base.center) / d)
        }
        func layout(_ s: Int) -> (regions: [(rect: Rect2, offset: Vec2)], colW: [Double], rowH: [Double]) {
            let regions = ids.map { region($0, s) }
            let colW = (0..<cols).map { c in stride(from: c, to: ids.count, by: cols).map { regions[$0].rect.width }.max() ?? 0 }
            let rowH = (0..<rows).map { r in (r * cols..<min(ids.count, (r + 1) * cols)).map { regions[$0].rect.height }.max() ?? 0 }
            return (regions, colW, rowH)
        }
        // Columns as wide as their widest view, rows as tall as their tallest, with room between them and for titles.
        let padX = 0.012, padY = 0.022
        let scale = scales.first { s in
            let l = layout(s)
            return l.colW.reduce(0, +) / Double(s) + padX * Double(cols) <= area.width && l.rowH.reduce(0, +) / Double(s) + padY * Double(rows) <= area.height
        } ?? scales.last!
        let (regions, colW, rowH) = layout(scale)
        // Spread what's left evenly.
        let spareX = max(0, area.width - colW.reduce(0, +) / Double(scale)) / Double(cols)
        let spareY = max(0, area.height - rowH.reduce(0, +) / Double(scale)) / Double(rows)
        var centers: [(ElementID, Vec2)] = []
        for (k, id) in ids.enumerated() {
            let r = k / cols, c = k % cols
            let x0 = area.min.x + colW[..<c].reduce(0, +) / Double(scale) + spareX * Double(c)
            let y0 = area.max.y - rowH[..<r].reduce(0, +) / Double(scale) - spareY * Double(r)
            let cell = Vec2(x0 + (colW[c] / Double(scale) + spareX) / 2, y0 - (rowH[r] / Double(scale) + spareY) / 2 + 0.006)
            centers.append((id, cell - regions[k].offset))
        }
        return (scale, centers)
    }

    /// Stacks a sheet's schedules from the top left of the drawing area (starting at `left`), a column at a time.
    /// Returns the viewports that run out of the drawing area (POLISH).
    @discardableResult
    static func arrangeSchedules(_ sheetID: ElementID, in tx: TransactionContext, left: Double = drawingArea.min.x) -> [ElementID] {
        let vps = tx.model.owned(byView: sheetID).filter { $0.viewport != nil && tx.model[$0.viewport?.viewID]?.schedule != nil }
        var x = left + 0.006, y = drawingArea.max.y - 0.006, column = 0.0
        var over: [ElementID] = []
        for vp in vps {
            guard let s = tx.model[vp.viewport?.viewID] else { continue }
            let t = ScheduleEngine.compute(s, tx.model)
            let w = t.totalWidth, h = ScheduleLayout.height(t, rows: vp.viewport?.scheduleRows)
            if y - h < drawingArea.min.y + 0.006, column > 0 { x += column + 0.01; y = drawingArea.max.y - 0.006; column = 0 }
            if y - h < drawingArea.min.y - 1e-9 || x + w > drawingArea.max.x + 1e-9 { over.append(vp.id) }
            let center = Vec2(x + w / 2, y - h / 2)
            if vp.viewport?.center != center { tx.update(vp.id) { $0.viewport?.center = center } }
            y -= h + 0.01
            column = max(column, w)
        }
        return over
    }
}
