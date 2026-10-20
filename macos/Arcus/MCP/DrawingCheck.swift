import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// AITOOLS: checks a view or sheet the way a reviewer marks up a drawing: dimension strings on top of each other or with
// colliding texts, duplicate dimensions, untagged doors/windows/rooms, empty title block fields, viewports off the paper
// or on top of each other, annotations outside the crop. verify_drawing reports them; arrange_dimensions fixes spacing.

/// One dimension string as laid out in its view (view coordinates, meters).
struct DimInfo {
    var id: ElementID
    var direction: Vec2
    /// Position across the dimension line (along its normal).
    var across: Double
    /// Extent along the dimension line.
    var along: ClosedRange<Double>
    var texts: [Rect2]
    var references: [GeometryReference]
    var linePoint: Vec2
    var normal: Vec2
}

/// A drawing problem with the elements involved.
struct DrawingProblem {
    var code: String
    var message: String
    var elements: [ElementID]
    var json: JSONValue { ["code": .string(code), "message": .string(message), "elements": .array(elements.prefix(10).map(\.json))] }
}

@MainActor
enum DrawingCheck {
    /// Paper distance (m) below which two parallel strings read as one.
    static let minSpacing = 0.004

    static func dimensions(in view: Element, _ m: BIMModel) -> [DimInfo] {
        let scale = Double(view.view?.scale ?? 100)
        var out: [DimInfo] = []
        for e in m.owned(byView: view.id) where e.category == .dimensions {
            guard let d = e.dimension, [.linear, .aligned].contains(d.kind), let l = DimensionLayout.make(e, d, m, scale: scale, view: view) else { continue }
            let n = l.direction.perpendicular
            let alongs = l.projected.map { $0.dot(l.direction) }
            guard let lo = alongs.min(), let hi = alongs.max(), hi - lo > 1e-6 else { continue }
            let style = DimensionStyle.resolve(e, m)
            let h = style.textSize * scale
            let horizontal = abs(l.direction.x) >= abs(l.direction.y)
            let texts = zip(l.values, l.textPositions).map { v, p -> Rect2 in
                let w = Double(Parameters.format(.double(v), type: .length, model: m).count) * h * 0.62
                let half = horizontal ? Vec2(w / 2, h / 2) : Vec2(h / 2, w / 2)
                return Rect2(min: p - half, max: p + half)
            }
            out.append(DimInfo(id: e.id, direction: l.direction, across: d.linePoint.dot(n), along: lo...hi, texts: texts,
                               references: d.references, linePoint: d.linePoint, normal: n))
        }
        return out
    }

    static func parallel(_ a: Vec2, _ b: Vec2) -> Bool { abs(a.cross(b)) < 0.02 }

    /// Overlapping strings, colliding texts and duplicates among a view's dimensions.
    static func dimensionProblems(_ view: Element, _ m: BIMModel) -> [DrawingProblem] {
        let dims = dimensions(in: view, m)
        let scale = Double(view.view?.scale ?? 100)
        var out: [DrawingProblem] = []
        var reported = Set<String>()
        for i in dims.indices {
            for j in dims.indices where j > i {
                let a = dims[i], b = dims[j]
                let key = "\(a.id.raw)-\(b.id.raw)"
                if parallel(a.direction, b.direction) {
                    let sameRefs = Set(a.references.map { "\($0.elementID?.raw ?? 0)-\($0.kind)" }) == Set(b.references.map { "\($0.elementID?.raw ?? 0)-\($0.kind)" })
                    let acrossGap = abs(a.linePoint.dot(a.normal) - b.linePoint.dot(a.normal))
                    let overlapAlong = min(a.along.upperBound, b.along.upperBound) - max(a.along.lowerBound, b.along.lowerBound)
                    if sameRefs && acrossGap < minSpacing * scale * 4 {
                        out.append(DrawingProblem(code: "dimension.duplicate", message: "Dimensions \(a.id.raw) and \(b.id.raw) measure the same references.", elements: [a.id, b.id]))
                        reported.insert(key); continue
                    }
                    if overlapAlong > 1e-3 && acrossGap < minSpacing * scale {
                        out.append(DrawingProblem(code: "dimension.overlap", message: "Dimension strings \(a.id.raw) and \(b.id.raw) lie on top of each other (\(Int((acrossGap / scale * 1000).rounded())) mm apart on paper).", elements: [a.id, b.id]))
                        reported.insert(key); continue
                    }
                }
                if !reported.contains(key), a.texts.contains(where: { ta in b.texts.contains { tb in ta.intersects(tb) } }) {
                    out.append(DrawingProblem(code: "dimension.text_overlap", message: "Texts of dimensions \(a.id.raw) and \(b.id.raw) overlap.", elements: [a.id, b.id]))
                }
            }
            // Texts within one string that collide (segments too short for their values).
            let t = dims[i].texts
            if t.count > 1, zip(t.dropLast(), t.dropFirst()).contains(where: { $0.intersects($1) }) {
                out.append(DrawingProblem(code: "dimension.crowded", message: "Dimension \(dims[i].id.raw) has segment texts that overlap; move texts or drop short segments.", elements: [dims[i].id]))
            }
        }
        return out
    }

    /// Respaces parallel strings that overlap so consecutive lines are `spacing` apart on paper, moving outward from
    /// the drawing's centre, and deletes duplicates. Returns (moved, deleted).
    static func arrange(_ view: Element, spacing paper: Double, removeDuplicates: Bool, in tx: TransactionContext) -> (Int, Int) {
        let m = tx.model
        let scale = Double(view.view?.scale ?? 100)
        let gap = paper * scale
        var dims = dimensions(in: view, m)
        var deleted = 0
        if removeDuplicates {
            var seen: [String: DimInfo] = [:]
            var keep: [DimInfo] = []
            for d in dims {
                let k = d.references.map { "\($0.elementID?.raw ?? 0)-\($0.kind)" }.sorted().joined(separator: ",")
                if let o = seen[k], parallel(o.direction, d.direction), abs(o.linePoint.dot(o.normal) - d.linePoint.dot(o.normal)) < gap * 4 {
                    tx.delete(d.id); deleted += 1; continue
                }
                seen[k] = d; keep.append(d)
            }
            dims = keep
        }
        let centre = ArcusToolbox.modelExtents(m)?.center ?? .zero
        var moved = 0
        var groups: [[DimInfo]] = []
        for d in dims {
            if let g = groups.firstIndex(where: { parallel($0[0].direction, d.direction) }) { groups[g].append(d) } else { groups.append([d]) }
        }
        for g in groups {
            let n = g[0].normal
            let c = centre.dot(n)
            for outward in [true, false] {
                let side = g.filter { outward ? $0.linePoint.dot(n) >= c : $0.linePoint.dot(n) < c }
                    .sorted { outward ? $0.linePoint.dot(n) < $1.linePoint.dot(n) : $0.linePoint.dot(n) > $1.linePoint.dot(n) }
                var placed: [(Double, ClosedRange<Double>)] = []
                for d in side {
                    var pos = d.linePoint.dot(n)
                    let overlapping = placed.filter { min($0.1.upperBound, d.along.upperBound) - max($0.1.lowerBound, d.along.lowerBound) > 1e-3 }
                    if let last = overlapping.map(\.0).max(by: { outward ? $0 < $1 : $0 > $1 }) {
                        let need = outward ? last + gap : last - gap
                        if outward ? pos < need - 1e-6 : pos > need + 1e-6 {
                            let shift = need - pos
                            tx.update(d.id) { $0.dimension?.linePoint = d.linePoint + n * shift }
                            pos = need
                            moved += 1
                        }
                    }
                    placed.append((pos, d.along))
                }
            }
        }
        return (moved, deleted)
    }

    /// Every problem a reviewer would mark on a view or sheet.
    static func problems(_ e: Element, _ m: BIMModel, tagCategories: [Category] = [.doors, .windows, .rooms]) -> (problems: [DrawingProblem], stats: [String: JSONValue]) {
        var out: [DrawingProblem] = []
        var stats: [String: JSONValue] = [:]
        if let sheet = e.sheet {
            let info = m.projectInfo
            let fields: [(String, String)] = [("Sheet Number", sheet.number), ("Sheet Name", e.name), ("Project Name", info.projectName),
                                              ("Project Number", info.projectNumber), ("Drawn By", sheet.drawnBy), ("Sheet Issue Date", sheet.issueDate.isEmpty ? info.issueDate : sheet.issueDate)]
            let empty = fields.filter { $0.1.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.0)
            if sheet.titleBlockTypeID == nil { out.append(DrawingProblem(code: "sheet.no_title_block", message: "Sheet \(sheet.number) has no title block.", elements: [e.id])) }
            if !empty.isEmpty { out.append(DrawingProblem(code: "sheet.empty_fields", message: "Title block fields are empty: \(empty.joined(separator: ", ")). Fill them with set_sheet_info / set_project_info.", elements: [e.id])) }
            let paper = sheet.paper.landscapeSize
            var boxes: [(Element, Rect2)] = []
            for vp in m.owned(byView: e.id) where vp.viewport != nil {
                guard let v = vp.viewport, let shown = m[v.viewID] else { continue }
                let size = ArcusToolbox.paperSize(of: shown, m)
                let r = Rect2(min: v.center - size * 0.5, max: v.center + size * 0.5)
                boxes.append((shown, r))
                if r.min.x < -1e-4 || r.min.y < -1e-4 || r.max.x > paper.x + 1e-4 || r.max.y > paper.y + 1e-4 {
                    out.append(DrawingProblem(code: "sheet.off_paper", message: "“\(shown.name)” runs off the \(sheet.paper.rawValue) paper. Use a smaller scale or a bigger paper.", elements: [vp.id]))
                }
                if shown.view != nil { out += problems(shown, m, tagCategories: tagCategories).problems.map { var p = $0; p.message = "\(shown.name): " + p.message; return p } }
            }
            for i in boxes.indices { for j in boxes.indices where j > i {
                let a = boxes[i].1, b = boxes[j].1
                let ix = min(a.max.x, b.max.x) - max(a.min.x, b.min.x), iy = min(a.max.y, b.max.y) - max(a.min.y, b.min.y)
                if ix > 0.005 && iy > 0.005 { out.append(DrawingProblem(code: "sheet.viewports_overlap", message: "“\(boxes[i].0.name)” and “\(boxes[j].0.name)” overlap on the sheet. Move one (place_on_sheet with position).", elements: [boxes[i].0.id, boxes[j].0.id])) }
            } }
            stats["viewports"] = .int(boxes.count)
            if boxes.isEmpty { out.append(DrawingProblem(code: "sheet.empty", message: "Sheet \(sheet.number) has no views.", elements: [e.id])) }
            return (out, stats)
        }
        guard let vd = e.view else { return (out, stats) }
        let g = ViewGraphicsBuilder(model: m, view: e).build()
        if g.items.isEmpty { out.append(DrawingProblem(code: "view.empty", message: "The view shows nothing.", elements: [e.id])) }
        let dims = dimensions(in: e, m)
        stats["dimensions"] = .int(dims.count)
        out += dimensionProblems(e, m)
        if vd.kind.isPlan || vd.kind.isVerticalCut {
            let visible = Set(g.items.compactMap(\.elementID))
            let untagged = TagAll.untagged(in: e.id, visible: visible, m)
            var coverage: [String: JSONValue] = [:]
            for cat in tagCategories {
                let total = visible.compactMap { m[$0] }.filter { $0.category == cat }.count
                guard total > 0 else { continue }
                let missing = untagged[cat]?.count ?? 0
                coverage[cat.rawValue] = .string("\(total - missing)/\(total)")
                if missing > 0 { out.append(DrawingProblem(code: "tags.missing", message: "\(missing) of \(total) \(cat.displayName.lowercased()) have no tag. add_tags tags them.", elements: untagged[cat] ?? [])) }
            }
            stats["tag_coverage"] = .object(coverage)
            if vd.kind.isPlan && dims.isEmpty && !m.elements(.walls).filter({ $0.levelID == e.levelID }).isEmpty {
                out.append(DrawingProblem(code: "dimensions.missing", message: "The plan has walls but no dimensions. add_dimensions {auto: true} dimensions it.", elements: [e.id]))
            }
        }
        if vd.cropActive, let crop = vd.cropRegion {
            let outside = dims.filter { d in d.texts.contains { !crop.contains($0.center) } }
            if !outside.isEmpty && !vd.annotationCropActive {
                // Annotations show past the model crop unless Annotation Crop is on; flag only when it is.
            } else if !outside.isEmpty {
                out.append(DrawingProblem(code: "view.clipped", message: "\(outside.count) dimension(s) fall outside the annotation crop and are clipped. Enlarge the crop (set_view_properties).", elements: outside.map(\.id)))
            }
        }
        return (out, stats)
    }
}
