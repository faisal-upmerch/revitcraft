import Foundation
import ArcusGeometry
import ArcusDomain

extension CADConverter {
    /// Destination of a conversion of link/import content into native Arcus elements.
    public enum Target: Sendable {
        /// Lines, polylines, arcs and circles → view-specific detail lines.
        case detailLines(viewID: ElementID)
        /// Lines, polylines, arcs and circles → model lines on a level (room separation, property or area boundary lines).
        case modelLines(levelID: ElementID, category: ArcusDomain.Category)
        /// TEXT/MTEXT (and attribute/dimension text) → text notes.
        case textNotes(viewID: ElementID)
        /// Closed polylines, closed line/arc chains and hatches → filled regions.
        case filledRegions(viewID: ElementID)
    }

    /// Categories accepted by `.modelLines`.
    public static let modelLineCategories: [ArcusDomain.Category] = [.roomSeparationLines, .propertyLines, .areaBoundaryLines]

    /// Converts supported 2D entities of a placed link/import into native Arcus drafting or model-reference geometry in a transaction.
    /// Entities are taken from the model's stored reference drawing (the source file is never touched), transformed by the link
    /// placement and filtered by layer name (case-insensitive; nil = all layers). Returns the number of elements created.
    public static func convert(linkElement: ElementID, layers: Set<String>?, target: Target, in tx: TransactionContext) throws -> Int {
        let model = tx.model
        guard let el = model[linkElement], let link = el.link else { throw CADError("The selected element is not a CAD link or import.") }
        guard link.format == .dxf || link.format == .dwg else { throw CADError("Only DWG and DXF content can be converted to Arcus elements.") }
        guard let drawing = model.referenceDrawings[link.contentKey] else {
            throw CADError("The CAD content of “\(link.sourceName)” is not available in this project. Reload the link first.")
        }
        switch target {
        case .detailLines(let v), .textNotes(let v), .filledRegions(let v):
            guard model[v]?.view != nil else { throw CADError("The target view does not exist.") }
        case .modelLines(let l, let cat):
            guard model[l]?.level != nil else { throw CADError("The target level does not exist.") }
            guard modelLineCategories.contains(cat) else {
                throw CADError("\(cat.displayName) can't be created from CAD lines. Use room separation, property or area boundary lines.")
            }
        }
        let filter = layers.map { Set($0.map { $0.uppercased() }) }
        let placement = link.placement
        var items: [(ReferenceDrawing.Entity, String)] = []
        for e in drawing.flattened() {
            let li = e.style.layer
            let lname = li >= 0 && li < drawing.layers.count ? drawing.layers[li].name : "0"
            if let f = filter, !f.contains(lname.uppercased()) { continue }
            items.append((e.transformed(placement), lname))
        }
        let format = link.format.rawValue
        func source(_ handle: String, _ type: String, _ layer: String) -> SourceMetadata {
            SourceMetadata(format: format, fileName: link.sourceName, originalID: handle, originalType: type, layer: layer)
        }
        var created = 0
        switch target {
        case .detailLines(let viewID):
            for (c, h, t, l) in curves(items) {
                tx.create(.detailLines, data: .modelLine(ModelLineData(curve: c)), ownerViewID: viewID) { $0.source = source(h, t, l) }
                created += 1
            }
        case .modelLines(let levelID, let cat):
            for (c, h, t, l) in curves(items) {
                tx.create(cat, data: .modelLine(ModelLineData(curve: c)), levelID: levelID) { $0.source = source(h, t, l) }
                created += 1
            }
        case .textNotes(let viewID):
            let scale = Double(max(1, model[viewID]?.view?.scale ?? 100))
            let types = model.types(for: .textNotes)
            for (e, l) in items {
                guard case .text(let p, let h, let r, let s, let al, let st) = e, !s.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                var d = TextNoteData(position: p, text: s)
                d.rotation = r
                d.alignment = al
                let paper = h / scale
                let type = types.min { abs(($0.typeData?.params[ParameterID("text.size")]?.doubleValue ?? 0) - paper) < abs(($1.typeData?.params[ParameterID("text.size")]?.doubleValue ?? 0) - paper) }
                tx.create(.textNotes, data: .textNote(d), typeID: type?.id, ownerViewID: viewID) { $0.source = source(st.handle, "TEXT", l) }
                created += 1
            }
        case .filledRegions(let viewID):
            let types = model.types(for: .filledRegions)
            let solidType = types.first { $0.typeData?.params[ParameterID("region.pattern")]?.textValue == FillPatternKind.solid.rawValue }
            let hatchType = types.first { $0.typeData?.params[ParameterID("region.pattern")]?.textValue != FillPatternKind.solid.rawValue } ?? types.first
            for r in regions(items) {
                guard case .success = r.sketch.profile() else { continue }
                tx.create(.filledRegions, data: .filledRegion(FilledRegionData(boundary: r.sketch)), typeID: (r.solid ? solidType : hatchType)?.id,
                          ownerViewID: viewID) { $0.source = source(r.handle, r.type, r.layer) }
                created += 1
            }
        }
        return created
    }

    /// Curves for line conversion: polylines explode into segments; full circles split into two arcs.
    static func curves(_ items: [(ReferenceDrawing.Entity, String)]) -> [(Curve2, String, String, String)] {
        var out: [(Curve2, String, String, String)] = []
        func add(_ c: Curve2, _ h: String, _ t: String, _ l: String) {
            guard c.length >= Tolerance.shortCurve else { return }
            out.append((c, h, t, l))
        }
        for (e, l) in items {
            switch e {
            case .line(let s, let st): add(.line(s), st.handle, "LINE", l)
            case .arc(let a, let st):
                if a.isFullCircle {
                    let half = a.sweep / 2
                    add(.arc(Arc2(center: a.center, radius: a.radius, startAngle: a.startAngle, sweep: half)), st.handle, "CIRCLE", l)
                    add(.arc(Arc2(center: a.center, radius: a.radius, startAngle: a.startAngle + half, sweep: half)), st.handle, "CIRCLE", l)
                } else {
                    add(.arc(a), st.handle, "ARC", l)
                }
            case .polyline(let pts, let closed, let st):
                guard pts.count >= 2 else { continue }
                let n = closed ? pts.count : pts.count - 1
                for i in 0..<n { add(.line(Segment2(pts[i], pts[(i + 1) % pts.count])), st.handle, "POLYLINE", l) }
            default: continue
            }
        }
        return out
    }

    struct Region { var sketch: Sketch; var solid: Bool; var handle: String; var type: String; var layer: String }

    /// Closed boundaries: closed polylines, hatches, and consecutive line/arc chains sharing a handle (bulged polylines) that close.
    static func regions(_ items: [(ReferenceDrawing.Entity, String)]) -> [Region] {
        var out: [Region] = []
        var chain: [Curve2] = []
        var chainHandle = ""
        var chainLayer = ""
        func flushChain() {
            defer { chain = []; chainHandle = "" }
            guard chain.count >= 2, !chainHandle.isEmpty, let ordered = Sketch.orderLoop(chain) else { return }
            out.append(Region(sketch: Sketch(loops: [ordered]), solid: false, handle: chainHandle, type: "POLYLINE", layer: chainLayer))
        }
        func polyLoop(_ pts: [Vec2]) -> [Curve2] {
            var p = pts
            if p.count > 1, p[0].isAlmostEqual(p[p.count - 1]) { p.removeLast() }
            guard p.count >= 3 else { return [] }
            return (0..<p.count).compactMap { i in
                let s = Segment2(p[i], p[(i + 1) % p.count])
                return s.length > Tolerance.length ? Curve2.line(s) : nil
            }
        }
        for (e, l) in items {
            var chainable: Curve2?
            var h = ""
            switch e {
            case .line(let s, let st): chainable = .line(s); h = st.handle
            case .arc(let a, let st) where !a.isFullCircle: chainable = .arc(a); h = st.handle
            default: break
            }
            if let c = chainable, !h.isEmpty {
                if h != chainHandle { flushChain(); chainHandle = h; chainLayer = l }
                chain.append(c)
                continue
            }
            flushChain()
            switch e {
            case .polyline(let pts, let closed, let st) where closed:
                let loop = polyLoop(pts)
                if !loop.isEmpty { out.append(Region(sketch: Sketch(loops: [loop]), solid: false, handle: st.handle, type: "POLYLINE", layer: l)) }
            case .arc(let a, let st) where a.isFullCircle:
                let half = a.sweep / 2
                let loop: [Curve2] = [.arc(Arc2(center: a.center, radius: a.radius, startAngle: a.startAngle, sweep: half)),
                                      .arc(Arc2(center: a.center, radius: a.radius, startAngle: a.startAngle + half, sweep: half))]
                out.append(Region(sketch: Sketch(loops: [loop]), solid: false, handle: st.handle, type: "CIRCLE", layer: l))
            case .hatch(let loops, let solid, let st):
                let ls = loops.map(polyLoop).filter { !$0.isEmpty }
                if !ls.isEmpty { out.append(Region(sketch: Sketch(loops: ls), solid: solid, handle: st.handle, type: "HATCH", layer: l)) }
            default: break
            }
        }
        flushChain()
        return out
    }
}
