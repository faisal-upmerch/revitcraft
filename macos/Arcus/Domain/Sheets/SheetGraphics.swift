import Foundation
import ArcusGeometry

/// Placement of a viewport on a sheet with its computed paper box.
public struct ViewportLayout: Sendable {
    public var viewportID: ElementID
    public var viewID: ElementID
    /// Box on paper (meters).
    public var box: Rect2
    /// view coordinates → paper.
    public var transform: Transform2
    public var scale: Int
}

/// Builds sheet display lists in paper meters (origin at the sheet's lower-left corner).
public struct SheetGraphicsBuilder: Sendable {
    public let model: BIMModel
    public let sheet: Element
    /// Supplies view graphics (so callers can reuse cached builds). Defaults to building on demand.
    public var viewGraphics: @Sendable (Element) -> ViewGraphics?
    public var includeGuides: Bool

    public init(model: BIMModel, sheet: Element, includeGuides: Bool = true, viewGraphics: (@Sendable (Element) -> ViewGraphics?)? = nil) {
        self.model = model
        self.sheet = sheet
        self.includeGuides = includeGuides
        let m = model
        self.viewGraphics = viewGraphics ?? { v in ViewGraphicsBuilder(model: m, view: v).build() }
    }

    public var paperSize: Vec2 { (sheet.sheet?.paper ?? .a1).landscapeSize }

    /// The content region of a view used to place it (crop if active, else model extents).
    public static func viewRegion(_ g: ViewGraphics) -> Rect2 {
        if let c = g.crop { return c }
        var r = Rect2.empty
        for i in g.items where i.layer != .overlay && i.layer != .annotation { r.include(i.bounds) }
        if r.isEmpty { r = g.extents }
        return r.isEmpty ? Rect2(center: .zero, halfSize: Vec2(1, 1)) : r
    }

    /// Paper box and view→paper transform of a view region drawn at `scale` and centred on `center` (paper meters).
    public static func placement(center: Vec2, region: Rect2, scale: Int) -> (box: Rect2, transform: Transform2) {
        let s = 1.0 / Double(max(scale, 1))
        let t = Transform2.translation(center) * Transform2.scale(s, s) * Transform2.translation(-region.center)
        return (Rect2(points: region.corners.map(t.apply)), t)
    }

    /// Margin around a viewport's region within which view annotations still show on the sheet (paper meters).
    public static let annotationMargin = 0.012

        public func layouts() -> [(ViewportLayout, ViewGraphics?)] {
        model.owned(byView: sheet.id).compactMap { vpEl -> (ViewportLayout, ViewGraphics?)? in
            guard let vp = vpEl.viewport, let v = model[vp.viewID] else { return nil }
            if v.schedule != nil {
                let table = ScheduleEngine.compute(v, model)
                let h = ScheduleLayout.height(table, rows: vp.scheduleRows) // BL-SCHED: title, header group row, headers, rows; F12: header rows, Split & Place segment
                let box = Rect2(min: vp.center - Vec2(table.totalWidth / 2, h / 2), max: vp.center + Vec2(table.totalWidth / 2, h / 2))
                return (ViewportLayout(viewportID: vpEl.id, viewID: v.id, box: box, transform: .identity, scale: 1), nil)
            }
            guard let vd = v.view else { return nil }
            let g = viewGraphics(v)
            let region = g.map(SheetGraphicsBuilder.viewRegion) ?? Rect2(center: .zero, halfSize: Vec2(1, 1))
            let (box, t) = SheetGraphicsBuilder.placement(center: vp.center, region: region, scale: vd.scale)
            return (ViewportLayout(viewportID: vpEl.id, viewID: v.id, box: box, transform: t, scale: vd.scale), g)
        }
    }

    public func build() -> ViewGraphics {
        var items: [GItem] = []
        let size = paperSize
        items += titleBlock(size)
        for (layout, graphics) in layouts() {
            guard let v = model[layout.viewID] else { continue }
            if v.schedule != nil {
                items.append(scheduleItem(layout, v))
                continue
            }
            guard let g = graphics else { continue }
            // Clip view content to the viewport region (crop or model extents plus an annotation margin).
            let region = SheetGraphicsBuilder.viewRegion(g).expanded(by: Double(layout.scale) * SheetGraphicsBuilder.annotationMargin)
            var first = true
            for item in g.items where item.layer != .overlay {
                guard region.intersects(item.bounds) || item.bounds.isEmpty else { continue }
                let clipped = region.contains(item.bounds) ? item.primitives : item.primitives.flatMap { ViewGraphicsBuilder.clipPrimitive($0, to: region) }
                guard !clipped.isEmpty else { continue }
                var vpItem = GItem(elementID: layout.viewportID, category: .viewports, layer: item.layer,
                                   primitives: clipped.map { transform($0, layout.transform) },
                                   targetViewID: item.targetViewID ?? layout.viewID,
                                   hitPolygons: first ? [.rectangle(layout.box)] : [])
                vpItem.lineScale = layout.scale
                items.append(vpItem)
                first = false
            }
            if first {
                items.append(GItem(elementID: layout.viewportID, category: .viewports, layer: .model, primitives: [], targetViewID: layout.viewID, hitPolygons: [.rectangle(layout.box)]))
            }
            if let vp = model[layout.viewportID]?.viewport, vp.showTitle {
                items.append(viewTitle(layout, v, vp))
            }
        }
        for e in model.owned(byView: sheet.id) where e.category != .viewports {
            if let item = AnnotationRenderer.item(e, GraphicOverride(), model: model, scale: 1, builder: nil) { items.append(item) }
        }
        if includeGuides, let spacing = sheet.sheet?.guideGridSpacing, spacing > 0.005 - 1e-9 { // F810: 5 mm grids draw too
            var prims: [GPrimitive] = []
            let st = GStroke(weight: 1, color: RGBColor(0.35, 0.55, 0.85), pattern: .dot)
            var x = spacing
            while x < size.x { prims.append(.polyline([Vec2(x, 0), Vec2(x, size.y)], closed: false, st)); x += spacing }
            var y = spacing
            while y < size.y { prims.append(.polyline([Vec2(0, y), Vec2(size.x, y)], closed: false, st)); y += spacing }
            items.append(GItem(elementID: nil, category: .sheets, layer: .overlay, primitives: prims, selectable: false))
        }
        items.sort { $0.layer < $1.layer }
        return ViewGraphics(viewID: sheet.id, scale: 1, items: items, extents: Rect2(min: .zero, max: size), crop: nil, modelRevision: model.revision)
    }

    func transform(_ p: GPrimitive, _ t: Transform2) -> GPrimitive {
        switch p {
        case .polyline(let pts, let c, let s): return .polyline(pts.map(t.apply), closed: c, s)
        case .arc(let a, let s): return .arc(a.transformed(t), s)
        case .fill(let polys, let f): return .fill(polys.map { $0.transformed(t) }, f)
        case .text(var tx): tx.position = t.apply(tx.position); tx.rotation += t.rotationAngle; return .text(tx)
        }
    }

    // MARK: Title block

    /// Values available to title block labels.
    public func titleBlockValue(_ name: String) -> String {
        let info = model.projectInfo
        let sd = sheet.sheet
        switch name {
        case "Sheet Number": return sd?.number ?? ""
        case "Sheet Name": return sheet.name
        case "Project Name": return info.projectName
        case "Project Number": return info.projectNumber
        case "Client Name": return info.clientName
        case "Project Address": return info.address
        case "Project Status": return info.status
        case "Organization": return info.organization
        case "Drawn By": return sd?.drawnBy ?? ""
        case "Checked By": return sd?.checkedBy ?? ""
        case "Designed By": return sd?.designedBy ?? ""
        case "Approved By": return sd?.approvedBy ?? ""
        case "Sheet Issue Date": return sd?.issueDate ?? ""
        case "Current Revision": return RevisionQueries.current(onSheet: sheet, model).map { RevisionQueries.label($0, model) } ?? ""
        case "Current Revision Date": return RevisionQueries.current(onSheet: sheet, model)?.revisionData?.date ?? ""
        case "Scale":
            let scales = Set(model.owned(byView: sheet.id).compactMap { model[$0.viewport?.viewID]?.view?.scale })
            if scales.count == 1, let s = scales.first { return ViewScales.label(s, imperial: model.units.system == .imperial) }
            return scales.isEmpty ? "" : "As indicated"
        default:
            if let pid = Parameters.id(named: name, for: sheet, model), let v = Parameters.value(pid, of: sheet, model) { return v.description }
            return ""
        }
    }

    func titleBlock(_ size: Vec2) -> [GItem] {
        let border = GStroke(weight: 4)
        guard let tbType = model[sheet.sheet?.titleBlockTypeID], let famID = tbType.typeData?.familyID, let fam = model[famID]?.family else {
            let m = 0.01
            return [GItem(elementID: nil, category: .titleBlocks, layer: .annotation,
                          primitives: [.polyline(Rect2(min: Vec2(m, m), max: size - Vec2(m, m)).corners, closed: true, border),
                                       .text(GText(position: size - Vec2(0.02, 0.02), height: 0.005, string: "\(sheet.sheet?.number ?? "") – \(sheet.name)", alignment: .right, verticalAnchor: 1, bold: true))],
                          selectable: false)]
        }
        var instanceValues: [String: ParamValue] = [:]
        instanceValues["Sheet Width"] = .double(size.x)
        instanceValues["Sheet Height"] = .double(size.y)
        let ev = FamilyEvaluator.evaluate(Parameters.effectiveFamily(fam, for: tbType, model), typeName: "project", instance: instanceValues, units: model.units)
        var prims: [GPrimitive] = []
        for f in ev.fills { prims.append(.fill([f.polygon], f.isMasking ? .mask : GFill(pattern: f.pattern, color: .black))) }
        for l in ev.annotationLines {
            let st = GStroke(weight: l.weight)
            switch l.curve {
            case .line(let s): prims.append(.polyline([s.start, s.end], closed: false, st))
            case .arc(let a): prims.append(.arc(a, st))
            }
        }
        var revisionAnchor: (Vec2, Double)?
        for lb in ev.labels {
            if lb.parameterName == "Revision Schedule" { revisionAnchor = (lb.position, lb.height); continue }
            let text = lb.parameterName.map(titleBlockValue) ?? lb.staticText
            prims.append(.text(GText(position: lb.position, height: lb.height, string: text, alignment: lb.alignment, verticalAnchor: 0.5, bold: lb.bold)))
        }
        if let (anchor, h) = revisionAnchor { prims += revisionSchedule(at: anchor, textHeight: h) }
        return [GItem(elementID: nil, category: .titleBlocks, layer: .annotation, primitives: prims, selectable: false)]
    }

    /// Revision schedule table growing upward from `anchor` (top-left of the header row).
    func revisionSchedule(at anchor: Vec2, textHeight h: Double) -> [GPrimitive] {
        let revs = RevisionQueries.revisions(onSheet: sheet, model)
        let widths: [Double] = [0.012, 0.022, 0.06]
        let rowH = h * 2.2
        var prims: [GPrimitive] = []
        let headers = ["Rev", "Date", "Description"]
        func row(_ cells: [String], y: Double, bold: Bool) {
            var x = anchor.x
            for (i, c) in cells.enumerated() {
                prims.append(.text(GText(position: Vec2(x + 0.0012, y - rowH / 2), height: h, string: c, verticalAnchor: 0.5, bold: bold)))
                x += widths[i]
            }
            prims.append(.polyline([Vec2(anchor.x, y - rowH), Vec2(anchor.x + widths.reduce(0, +), y - rowH)], closed: false, GStroke(weight: 1)))
        }
        row(headers, y: anchor.y, bold: true)
        for (i, r) in revs.enumerated() {
            let d = r.revisionData!
            row([RevisionQueries.label(r, model), d.date, d.description], y: anchor.y - rowH * Double(i + 1), bold: false)
        }
        return prims
    }

    // MARK: Viewport titles & schedules

    func viewTitle(_ l: ViewportLayout, _ v: Element, _ vp: ViewportData) -> GItem {
        let p = Vec2(l.box.min.x, l.box.min.y) + vp.titleOffset
        let r = 0.0045
        let title = (v.view?.titleOnSheet.isEmpty == false ? v.view!.titleOnSheet : v.name).uppercased()
        let len = vp.titleLineLength ?? max(0.04, Double(title.count) * 0.0024 + 0.02)
        var prims: [GPrimitive] = [
            .arc(Arc2(center: p + Vec2(r, 0), radius: r, startAngle: 0, sweep: Angle.twoPi), GStroke(weight: 2)),
            .text(GText(position: p + Vec2(r, 0), height: 0.003, string: vp.detailNumber, alignment: .center, verticalAnchor: 0.5, bold: true)),
            .polyline([p + Vec2(2 * r + 0.001, -0.0004), p + Vec2(2 * r + 0.001 + len, -0.0004)], closed: false, GStroke(weight: 4)),
            .text(GText(position: p + Vec2(2 * r + 0.002, 0.0008), height: 0.0032, string: title, bold: true)),
        ]
        if let s = v.view?.scale {
            prims.append(.text(GText(position: p + Vec2(2 * r + 0.002, -0.0012), height: 0.0022, string: ViewScales.label(s, imperial: model.units.system == .imperial), verticalAnchor: 1)))
        }
        return GItem(elementID: l.viewportID, category: .viewports, layer: .annotation, primitives: prims, targetViewID: l.viewID)
    }

    func scheduleItem(_ l: ViewportLayout, _ schedule: Element) -> GItem {
        let table = ScheduleEngine.compute(schedule, model)
        let rows = model[l.viewportID]?.viewport?.scheduleRows // F12: Split & Place segment
        let prims = ScheduleLayout.primitives(table, topLeft: Vec2(l.box.min.x, l.box.max.y), rows: rows)
        return GItem(elementID: l.viewportID, category: .viewports, layer: .annotation, primitives: prims, targetViewID: l.viewID,
                     hitPolygons: [.rectangle(l.box)])
    }
}

// BL-SCHED: ScheduleLayout moved to Schedules/ScheduleLayout.swift (F12: a grid of styled cells, header rows, segments).

/// Placing views and schedules on sheets (Place View dialog and dragging from the Project Browser).
public enum SheetPlacement {
    /// Why an element can't be placed on a sheet, or nil when it can.
    public static func refusal(_ id: ElementID, onSheet sheetID: ElementID, _ model: BIMModel) -> String? {
        guard let sheet = model[sheetID], sheet.sheet != nil else { return "Open a sheet to place views." }
        guard let e = model[id] else { return "That view no longer exists." }
        if e.sheet != nil { return "A sheet can't be placed on another sheet." }
        if e.schedule != nil { return nil }
        guard let vd = e.view else { return "Only views and schedules can be placed on sheets." }
        if vd.kind == .legend { return nil }
        if let other = model.viewports(showing: id).first, let owner = model[other.ownerViewID] {
            let where_ = owner.id == sheetID ? "this sheet" : "sheet \(owner.sheet?.number ?? "") – \(owner.name)"
            return "“\(e.name)” is already placed on \(where_). A view can be placed on one sheet only; duplicate it first."
        }
        return nil
    }

    /// The next free detail number on a sheet.
    public static func nextDetailNumber(onSheet sheetID: ElementID, _ model: BIMModel) -> String {
        String((model.owned(byView: sheetID).compactMap { Int($0.viewport?.detailNumber ?? "") }.max() ?? 0) + 1)
    }

    /// Where a view goes when no point is given: a little left of and below the sheet centre (clear of a title block
    /// along the right or bottom edge).
    public static func defaultCenter(onSheet sheetID: ElementID, _ model: BIMModel) -> Vec2 {
        (model[sheetID]?.sheet?.paper ?? .a1).landscapeSize * 0.42
    }

    /// Places a view or schedule on a sheet with its centre at `center` (paper meters). Throws with a readable message
    /// when the view is already on a sheet (legends and schedules may appear on many sheets).
    @discardableResult
    public static func place(_ viewID: ElementID, onSheet sheetID: ElementID, at center: Vec2? = nil, in tx: TransactionContext) throws -> ElementID {
        if let reason = refusal(viewID, onSheet: sheetID, tx.model) { throw TransactionError(reason, elements: [viewID]) }
        let c = center ?? defaultCenter(onSheet: sheetID, tx.model)
        let n = nextDetailNumber(onSheet: sheetID, tx.model)
        return tx.create(.viewports, data: .viewport(ViewportData(viewID: viewID, center: c, detailNumber: n)), ownerViewID: sheetID)
    }
}
