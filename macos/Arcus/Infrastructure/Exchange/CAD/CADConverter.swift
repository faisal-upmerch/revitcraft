import Foundation
import ArcusGeometry
import ArcusDomain

public enum CADConverter {
    /// Converts a parsed document to a Domain ReferenceDrawing (meters, positioned relative to the insertion), honoring options; never modifies the source.
    public static func referenceDrawing(_ doc: CADDocument, options: CADImportOptions, surveyOrigin: Vec2 = .zero) -> (drawing: ReferenceDrawing, report: CADImportReport) {
        do {
            let r = try convertDocument(doc, options: options, localOrigin: nil, isCancelled: { false })
            return (r.drawing, r.report)
        } catch {
            // Only cancellation can throw, and this entry point never cancels.
            var report = CADImportReport()
            report.warnings = ["Conversion failed: \(error)"]
            return (ReferenceDrawing(layers: [ReferenceDrawing.Layer(name: "0")], entities: [], extents: Rect2(min: .zero, max: .zero)), report)
        }
    }

    /// Placement transform (drawing local meters → model) for a drawing produced by `referenceDrawing`.
    ///
    /// The drawing's content is stored relative to a local origin near its extents so that large survey coordinates keep
    /// full precision; the placement carries the positioning, user scale/rotation and that local origin.
    public static func placement(for drawing: ReferenceDrawing, options: CADImportOptions, surveyOrigin: Vec2 = .zero) -> Transform2 {
        let local = Vec2(meta(drawing, "cad.localOriginX"), meta(drawing, "cad.localOriginY"))
        let center = Vec2(meta(drawing, "cad.worldCenterX"), meta(drawing, "cad.worldCenterY"))
        let user = Transform2.rotation(options.rotation) * Transform2.scale(options.scale, options.scale)
        switch options.positioning {
        case .originToOrigin:
            return user * .translation(local)
        case .centerToCenter:
            return user * .translation(local - center)
        case .sharedCoordinates(let e, let n, let rot):
            return .translation(surveyOrigin) * .rotation(rot) * user * .translation(local - Vec2(e, n))
        }
    }

    static func meta(_ d: ReferenceDrawing, _ key: String) -> Double {
        d.metadata[key].flatMap(Double.init) ?? 0
    }

    struct Result {
        var drawing: ReferenceDrawing
        var report: CADImportReport
    }

    /// Full conversion. `localOrigin` (meters, world) forces the local origin (used by reload to keep the placement).
    static func convertDocument(_ doc: CADDocument, options: CADImportOptions, localOrigin: Vec2?, maxEntities: Int = CADReadOptions().maxEntities,
                                maxBlockDepth: Int = CADReadOptions().maxBlockDepth, isCancelled: () -> Bool) throws -> Result {
        let start = Date()
        var conv = Conversion(doc: doc, options: options, maxEntities: maxEntities, maxBlockDepth: maxBlockDepth)
        let r = try conv.run(localOrigin: localOrigin, isCancelled: isCancelled)
        var report = r.report
        report.elapsed = Date().timeIntervalSince(start)
        return Result(drawing: r.drawing, report: report)
    }
}

/// One conversion run.
private struct Conversion {
    typealias Entity = ReferenceDrawing.Entity
    typealias Style = ReferenceDrawing.Style

    let doc: CADDocument
    let options: CADImportOptions
    let maxEntities: Int
    let maxBlockDepth: Int
    let units: CADUnits
    let s: Double
    var base = Vec2.zero
    var layers: [ReferenceDrawing.Layer] = []
    var layerIndex: [String: Int] = [:]
    var layerFilter: Set<String>?
    var blockOut: [String: [Entity]] = [:]
    var neededBlocks: [String] = []
    var queued: Set<String> = []
    var blockKey: [String: String] = [:]
    var sourceLayers: [String: CADLayer] = [:]
    var expandedMemo: [String: Int] = [:]
    var expandedVisiting: Set<String> = []
    var budgetUsed = 0
    var skippedForBudget = 0
    var cycleRefs: Set<String> = []
    var depthLimited = 0
    var report = CADImportReport()
    var warnings: [String] = []
    var converted = 0
    var retained = 0
    var unsupported: [String: Int] = [:]
    var invalid = 0
    var arrowSize: Double
    var dimTextHeight: Double
    var counter = 0

    init(doc: CADDocument, options: CADImportOptions, maxEntities: Int, maxBlockDepth: Int) {
        self.doc = doc; self.options = options; self.maxEntities = maxEntities; self.maxBlockDepth = max(1, maxBlockDepth)
        units = options.unitsOverride ?? doc.units
        s = units.metersPerUnit
        for k in doc.blocks.keys { blockKey[k.uppercased()] = k }
        for l in doc.layers where sourceLayers[l.name.uppercased()] == nil { sourceLayers[l.name.uppercased()] = l }
        let metric = (doc.header["$MEASUREMENT"].flatMap { Int($0) } ?? (units == .inches || units == .feet ? 0 : 1)) == 1
        let dimScale = doc.header["$DIMSCALE"].flatMap(Double.init).flatMap { $0 > 0 && $0 < 1e6 ? $0 : nil } ?? 1
        arrowSize = (doc.header["$DIMASZ"].flatMap(Double.init).flatMap { $0 > 0 && $0 < 1e6 ? $0 : nil } ?? (metric ? 2.5 : 0.18)) * dimScale
        dimTextHeight = (doc.header["$DIMTXT"].flatMap(Double.init).flatMap { $0 > 0 && $0 < 1e6 ? $0 : nil } ?? (metric ? 2.5 : 0.18)) * dimScale
        if let inc = options.includedLayers { layerFilter = Set(inc.map { $0.uppercased() }) }
    }

    // MARK: Driver

    mutating func run(localOrigin: Vec2?, isCancelled: () -> Bool) throws -> CADImportReport.ResultBox {
        if options.unitsOverride == nil && doc.units == .unitless {
            warnings.append("The drawing has no units ($INSUNITS is unitless); millimeters were assumed. Choose explicit units if the size is wrong.")
        }
        // Source entities: model space or a layout.
        var source = doc.modelSpace
        if let want = options.layout, !want.isEmpty {
            if let lo = doc.layout(named: want) {
                source = lo.entities
            } else {
                warnings.append("Layout “\(want)” was not found; model space was imported instead.")
            }
        }
        if let f = layerFilter { source = source.filter { f.contains($0.props.layer.uppercased()) } }

        // Extents in drawing units (for the local origin and center positioning).
        var calc = CADBoundsCalculator(doc: doc, maxDepth: maxBlockDepth)
        var ext = calc.bounds(of: source)
        if !CADGeometry.isFinite(ext) { ext = Rect2(min: .zero, max: .zero) }
        if let lo = localOrigin, s > 0 { base = lo / s } else { base = ext.center }

        // Layers (filtered).
        for l in doc.layers where layerFilter == nil || layerFilter!.contains(l.name.uppercased()) || l.name == "0" {
            _ = layer(l.name)
        }

        // Top-level conversion.
        let top = Transform2(a: s, b: 0, c: 0, d: s, tx: -base.x * s, ty: -base.y * s)
        var out: [Entity] = []
        out.reserveCapacity(min(source.count, 1 << 20))
        for e in source {
            counter += 1
            if counter & 0x3FFF == 0, isCancelled() { throw CancellationError() }
            convertTree(e, top, into: &out, depth: 0, inBlock: false, inherited: nil, stack: [])
        }
        // Blocks referenced by the output (breadth-first; each converted once).
        var qi = 0
        while qi < neededBlocks.count {
            if isCancelled() { throw CancellationError() }
            let key = neededBlocks[qi]
            qi += 1
            guard let b = doc.blocks[key] else { continue }
            var ents: [Entity] = []
            for e in b.entities { convertTree(e, .scale(s, s), into: &ents, depth: 1, inBlock: true, inherited: nil, stack: [key]) }
            blockOut[key] = ents
        }
        pruneBlockGraph()

        if skippedForBudget > 0 {
            warnings.append("\(skippedForBudget) block references were not imported because the drawing would expand to more than \(maxEntities) entities.")
        }
        if !cycleRefs.isEmpty {
            warnings.append("Blocks reference themselves (" + cycleRefs.sorted().joined(separator: ", ") + "); the recursive references were ignored.")
        }
        if depthLimited > 0 {
            warnings.append("\(depthLimited) block references nested deeper than \(maxBlockDepth) levels were ignored.")
        }
        if invalid > 0 { warnings.append("\(invalid) entities could not be converted because of invalid geometry.") }
        let totalUnsupported = unsupported.values.reduce(0, +)
        if totalUnsupported > 0 {
            warnings.append("\(totalUnsupported) objects of unsupported types were not converted (" +
                            unsupported.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ") + ").")
        }
        warnings.append(contentsOf: doc.warnings)

        // Extents in local meters.
        let localExt = Rect2(points: ext.corners.map(top.apply))
        let worldExt = Rect2(min: ext.min * s, max: ext.max * s)
        let center = worldExt.center
        var meta: [String: String] = [
            "source.format": doc.format,
            "source.version": doc.version,
            "source.versionName": doc.versionName,
            "source.units": String(units.rawValue),
            "cad.metersPerUnit": String(format: "%.17g", s),
            "cad.localOriginX": String(format: "%.17g", base.x * s),
            "cad.localOriginY": String(format: "%.17g", base.y * s),
            "cad.worldCenterX": String(format: "%.17g", center.x),
            "cad.worldCenterY": String(format: "%.17g", center.y),
            "cad.layout": options.layout ?? "",
            "cad.explodeBlocks": options.explodeBlocks ? "1" : "0",
            "cad.unitsOverride": options.unitsOverride.map { String($0.rawValue) } ?? "",
        ]
        if let inc = options.includedLayers { meta["cad.includedLayers"] = inc.sorted().joined(separator: "\n") }
        let drawing = ReferenceDrawing(layers: layers, blocks: blockOut, entities: out,
                                       extents: CADGeometry.isFinite(localExt) ? localExt : Rect2(min: .zero, max: .zero), metadata: meta)

        report.format = doc.format.hasPrefix("DXF") ? "DXF" : doc.format
        report.version = "\(doc.versionName) (\(doc.version))"
        report.units = units
        report.unitScale = s
        report.extents = CADGeometry.isFinite(worldExt) ? worldExt : Rect2(min: .zero, max: .zero)
        report.layouts = doc.layouts.map(\.name)
        report.layerCount = layers.count
        report.entityCountsByType = doc.entityCounts
        report.converted = converted
        report.retainedAsReference = retained
        report.unsupported = unsupported
        var seenFonts: Set<String> = []
        report.missingFonts = doc.textStyles.filter(\.isSHX).map(\.fontFile).filter { !$0.isEmpty && seenFonts.insert($0.uppercased()).inserted }
        report.warnings = warnings
        return CADImportReport.ResultBox(drawing: drawing, report: report)
    }

    // MARK: Layers and styles

    mutating func layer(_ name: String) -> Int {
        let key = name.uppercased()
        if let i = layerIndex[key] { return i }
        let src = sourceLayers[key] ?? CADLayer(name: name)
        let l = ReferenceDrawing.Layer(name: src.name, color: src.color, lineWeight: src.lineWeight, lineType: src.lineType,
                                       isOn: src.isOn, isFrozen: src.isFrozen, isLocked: src.isLocked, plots: src.plots)
        layers.append(l)
        layerIndex[key] = layers.count - 1
        return layers.count - 1
    }

    /// Effective props with block inheritance (layer 0 and BYBLOCK take the insert's values) when exploding.
    func effective(_ p: CADEntityProps, _ inherited: CADEntityProps?) -> CADEntityProps {
        guard let inh = inherited else { return p }
        var q = p
        if q.layer == "0" { q.layer = inh.layer }
        if case .byBlock = q.color { q.color = inh.color }
        if q.lineWeightByBlock { q.lineWeight = inh.lineWeight; q.lineWeightByBlock = false }
        if q.lineType?.uppercased() == "BYBLOCK" { q.lineType = inh.lineType }
        return q
    }

    mutating func style(_ p: CADEntityProps) -> Style {
        var lt = p.lineType
        if let l = lt, l.uppercased() == "BYBLOCK" || l.uppercased() == "BYLAYER" { lt = nil }
        return Style(layer: layer(p.layer), color: p.color.resolved, lineWeight: p.lineWeight, lineType: lt, handle: p.handle)
    }

    // MARK: Entities

    func finite(_ v: Vec2) -> Bool { v.x.isFinite && v.y.isFinite && abs(v.x) < 1e13 && abs(v.y) < 1e13 }

    mutating func emit(_ e: Entity, into out: inout [Entity]) -> Bool {
        let b = e.bounds
        if case .insert(_, let t, _, _) = e {
            guard [t.a, t.b, t.c, t.d, t.tx, t.ty].allSatisfy({ $0.isFinite }) else { invalid += 1; return false }
        } else {
            guard b.isEmpty || (finite(b.min) && finite(b.max)) else { invalid += 1; return false }
        }
        out.append(e)
        return true
    }

    struct WorkItem {
        var entity: CADEntity
        var m: Transform2
        var depth: Int
        var inherited: CADEntityProps?
        var stack: [String]
    }
    /// Entities produced by exploding inserts, waiting to be converted (keeps block expansion off the call stack).
    var spawned: [WorkItem] = []

    /// Converts an entity and, iteratively, everything its exploded inserts expand to. Recursion depth stays constant, so
    /// deeply nested blocks cannot overflow the (small) stacks of background threads.
    mutating func convertTree(_ e: CADEntity, _ m: Transform2, into out: inout [Entity], depth: Int, inBlock: Bool, inherited: CADEntityProps?, stack: [String]) {
        convert(e, m, into: &out, depth: depth, inBlock: inBlock, inherited: inherited, stack: stack)
        var work: [WorkItem] = []
        work.append(contentsOf: spawned)
        spawned.removeAll()
        while let w = work.popLast() {
            convert(w.entity, w.m, into: &out, depth: w.depth, inBlock: true, inherited: w.inherited, stack: w.stack)
            if !spawned.isEmpty { work.append(contentsOf: spawned); spawned.removeAll() }
        }
    }

    mutating func convert(_ e: CADEntity, _ m: Transform2, into out: inout [Entity], depth: Int, inBlock: Bool, inherited: CADEntityProps?, stack: [String]) {
        let p = effective(e.props, inherited)
        if inherited != nil, let f = layerFilter, !f.contains(p.layer.uppercased()) { return }
        let st = style(p)
        let sim = CADGeometry.isSimilarity(m)
        let scale = m.uniformScale
        switch e {
        case .line(let a, let b, _):
            if emit(.line(Segment2(m.apply(a.xy), m.apply(b.xy)), st), into: &out) { converted += 1 }

        case .polyline(let poly, _):
            if poly.isMesh {
                var n = 0
                for f in poly.meshFaces {
                    let pts = f.map { i -> Vec3 in let q = m.apply(poly.points[i].xy); return Vec3(q.x, q.y, poly.points[i].z * scale) }
                    if emit(.face3D(pts, st), into: &out) { n += 1 }
                }
                if n > 0 { retained += 1 }
                return
            }
            let pts2 = poly.points2D
            if poly.hasBulges && !poly.is3D {
                if sim {
                    // Keep true arcs: one line/arc per segment, sharing the source handle.
                    let count = poly.closed ? pts2.count : pts2.count - 1
                    guard count > 0 else { invalid += 1; return }
                    var ok = false
                    for i in 0..<count {
                        let a = pts2[i], b = pts2[(i + 1) % pts2.count]
                        if let arc = CADGeometry.bulgeArc(a, b, poly.bulge(at: i)) {
                            ok = emit(.arc(arc.transformed(m), st), into: &out) || ok
                        } else if !a.isAlmostEqual(b, tolerance: 0) {
                            ok = emit(.line(Segment2(m.apply(a), m.apply(b)), st), into: &out) || ok
                        }
                    }
                    if ok { converted += 1 }
                } else {
                    let t = CADGeometry.tessellate(points: pts2, bulges: poly.bulges, closed: poly.closed)
                    if emit(.polyline(t.map(m.apply), closed: poly.closed, st), into: &out) { converted += 1 }
                }
            } else {
                guard !pts2.isEmpty else { invalid += 1; return }
                if pts2.count == 1 {
                    if emit(.point(m.apply(pts2[0]), st), into: &out) { converted += 1 }
                } else if emit(.polyline(pts2.map(m.apply), closed: poly.closed, st), into: &out) { converted += 1 }
            }

        case .arc(let c, let r, let sa, let ea, _):
            let arc = Arc2(center: c, radius: r, startAngle: sa, sweep: CADGeometry.ccwSweep(sa, ea))
            if sim {
                if emit(.arc(arc.transformed(m), st), into: &out) { converted += 1 }
            } else {
                let el = Ellipse2(center: c, majorAxis: Vec2(r, 0), ratio: 1, startParam: sa, endParam: sa + arc.sweep).transformed(m)
                if emit(.polyline(el.tessellate(chordTolerance: CADGeometry.chordTolerance(forSize: r * scale)), closed: false, st), into: &out) { converted += 1 }
            }

        case .circle(let c, let r, _):
            if sim {
                if emit(.arc(Arc2(center: c, radius: r, startAngle: 0, sweep: Angle.twoPi).transformed(m), st), into: &out) { converted += 1 }
            } else {
                let el = Ellipse2(center: c, majorAxis: Vec2(r, 0), ratio: 1).transformed(m)
                var pts = el.tessellate(chordTolerance: CADGeometry.chordTolerance(forSize: r * scale))
                if pts.count > 2 { pts.removeLast() }
                if emit(.polyline(pts, closed: true, st), into: &out) { converted += 1 }
            }

        case .ellipse(let el, _):
            let t = el.transformed(m)
            var pts = t.tessellate(chordTolerance: CADGeometry.chordTolerance(forSize: t.majorAxis.length))
            if t.isFull && pts.count > 2 { pts.removeLast() }
            if emit(.polyline(pts, closed: t.isFull, st), into: &out) { converted += 1 }

        case .spline(let sp, let fit, let closed, _):
            var pts: [Vec2]
            if let sp, sp.isValid {
                let t = sp.transformed(m)
                let size = max(t.controlBounds.width, t.controlBounds.height)
                pts = t.tessellate(chordTolerance: CADGeometry.chordTolerance(forSize: size))
            } else {
                pts = CADConversionMath.smooth(fit).map(m.apply)
            }
            guard pts.count >= 2 else { invalid += 1; return }
            if closed, pts.count > 2, pts[0].isAlmostEqual(pts[pts.count - 1], tolerance: 1e-9) { pts.removeLast() }
            if emit(.polyline(pts, closed: closed, st), into: &out) { converted += 1 }

        case .point(let pt, _):
            if emit(.point(m.apply(pt.xy), st), into: &out) { converted += 1 }

        case .text(let t, _):
            if emitText(t, m, st, into: &out) { converted += 1 }

        case .attributeDefinition(let a, _):
            // Templates are not drawn inside blocks; constant attributes are. Loose ATTDEFs show their tag.
            if inBlock {
                if a.isConstant && !a.isInvisible, emitText(a.text, m, st, into: &out) { converted += 1 }
            } else {
                var t = a.text
                t.text = a.tag
                if emitText(t, m, st, into: &out) { converted += 1 }
            }

        case .mtext(let mt, _):
            if emitMText(mt, m, st, into: &out) { converted += 1 }

        case .hatch(let h, _):
            var loops: [[Vec2]] = []
            for l in h.loops {
                let pts = CADGeometry.loopPoints(l).map(m.apply)
                if pts.count >= 3 { loops.append(pts) }
            }
            guard !loops.isEmpty else { invalid += 1; return }
            if emit(.hatch(loops: loops, solid: h.isSolid, st), into: &out) { converted += 1 }

        case .solid(let pts, _):
            if emit(.hatch(loops: [pts.map(m.apply)], solid: true, st), into: &out) { converted += 1 }

        case .insert(let ins, _):
            convertInsert(ins, p, st, m, into: &out, depth: depth, inBlock: inBlock, stack: stack)

        case .dimension(let dim, _):
            if let key = resolve(dim.blockName) {
                let ins = CADInsert(blockName: key, position: .zero)
                convertInsert(ins, p, st, m, into: &out, depth: depth, inBlock: inBlock, stack: stack, countAs: "DIMENSION")
            } else {
                // No graphics block: show the measurement text at the text position.
                let t = CADText(text: dim.text, position: dim.textMidpoint, height: dimTextHeight, horizontal: .center, vertical: .middle)
                if emitText(t, m, st, into: &out) { converted += 1 }
            }

        case .leader(let pts, let arrow, _):
            let mp = pts.map(m.apply)
            if emit(.polyline(mp, closed: false, st), into: &out) {
                converted += 1
                if arrow, pts.count >= 2 { _ = emit(arrowHead(tip: pts[0], from: pts[1], m, st), into: &out) }
            }

        case .multileader(let ml, _):
            var ok = false
            for line in ml.leaderLines where line.count >= 2 {
                // Leader lines run from the arrow point to the landing.
                ok = emit(.polyline(line.map(m.apply), closed: false, st), into: &out) || ok
                if ml.hasArrowhead { _ = emit(arrowHead(tip: line[0], from: line[1], m, st), into: &out) }
            }
            if !ml.text.isEmpty, let pos = ml.textPosition {
                let h = ml.textHeight > 0 ? ml.textHeight : dimTextHeight
                let mt = CADMText(rawText: ml.text, plainText: ml.text, position: pos, height: h, attachment: 1)
                ok = emitMText(mt, m, st, into: &out) || ok
            }
            if ok { converted += 1 }

        case .image(let path, let corners, _):
            let name = path.isEmpty ? "(unresolved image)" : path
            if emit(.imageRef(name: name, corners: corners.map(m.apply), st), into: &out) { retained += 1 }

        case .face3D(let pts, _):
            let q = pts.map { v -> Vec3 in let a = m.apply(v.xy); return Vec3(a.x, a.y, v.z * scale) }
            if emit(.face3D(q, st), into: &out) { retained += 1 }

        case .proxy(let name, let bounds, _):
            unsupported[name, default: 0] += 1
            if let b = bounds, CADGeometry.isFinite(b) {
                if emit(.proxy(bounds: Rect2(points: b.corners.map(m.apply)), typeName: name, st), into: &out) { retained += 1 }
            }

        case .unsupported(let name, _):
            unsupported[name, default: 0] += 1
        }
    }

    // MARK: Text

    mutating func emitText(_ t: CADText, _ m: Transform2, _ st: Style, into out: inout [Entity]) -> Bool {
        guard !t.text.isEmpty, t.height > 0 else { return false }
        let up = Vec2.fromAngle(t.rotation).perpendicular
        var anchor = t.position
        var rotation = t.rotation
        var align: TextAlignment = .left
        var vShift = 0.0
        switch t.horizontal {
        case .left: break
        case .center: align = .center; anchor = t.alignmentPoint ?? t.position
        case .right: align = .right; anchor = t.alignmentPoint ?? t.position
        case .middle: align = .center; anchor = t.alignmentPoint ?? t.position; vShift = t.height / 2
        case .aligned, .fit:
            if let ap = t.alignmentPoint, ap.distance(to: t.position) > 0 { rotation = (ap - t.position).angle }
        }
        if t.horizontal == .left && t.vertical != .baseline, let ap = t.alignmentPoint { anchor = ap }
        switch t.vertical {
        case .baseline, .bottom: break
        case .middle: vShift = t.height / 2
        case .top: vShift = t.height
        }
        let baseline = anchor - up * vShift
        let pos = m.apply(baseline)
        let dir = m.applyVector(Vec2.fromAngle(rotation))
        let h = t.height * m.uniformScale
        return emit(.text(position: pos, height: h, rotation: dir.angle, text: t.text, alignment: align, st), into: &out)
    }

    mutating func emitMText(_ mt: CADMText, _ m: Transform2, _ st: Style, into out: inout [Entity]) -> Bool {
        guard mt.height > 0 else { return false }
        var lines = mt.plainText.components(separatedBy: "\n")
        if mt.width > 0 { lines = CADConversionMath.wrap(lines, width: mt.width, height: mt.height) }
        while let l = lines.last, l.trimmingCharacters(in: .whitespaces).isEmpty, lines.count > 1 { lines.removeLast() }
        guard lines.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return false }
        let a = max(1, min(9, mt.attachment)) - 1
        let col = a % 3, row = a / 3
        let align: TextAlignment = col == 0 ? .left : (col == 1 ? .center : .right)
        let step = mt.height * 1.6667 * max(0.25, mt.lineSpacingFactor)
        let total = mt.height + Double(lines.count - 1) * step
        let up = Vec2.fromAngle(mt.rotation).perpendicular
        let firstBaseline: Double = row == 0 ? -mt.height : (row == 1 ? total / 2 - mt.height : Double(lines.count - 1) * step)
        var any = false
        let dir = m.applyVector(Vec2.fromAngle(mt.rotation))
        let h = mt.height * m.uniformScale
        for (i, l) in lines.enumerated() where !l.trimmingCharacters(in: .whitespaces).isEmpty {
            let p = mt.position + up * (firstBaseline - Double(i) * step)
            any = emit(.text(position: m.apply(p), height: h, rotation: dir.angle, text: l, alignment: align, st), into: &out) || any
        }
        return any
    }

    func arrowHead(tip: Vec2, from: Vec2, _ m: Transform2, _ st: Style) -> Entity {
        let d = (tip - from).normalized
        let base = tip - d * arrowSize
        let w = d.perpendicular * (arrowSize / 6)
        return .hatch(loops: [[m.apply(tip), m.apply(base + w), m.apply(base - w)]], solid: true, st)
    }

    // MARK: Blocks

    func resolve(_ name: String) -> String? {
        if doc.blocks[name] != nil { return name }
        return blockKey[name.uppercased()]
    }

    /// Number of entities a block expands to when flattened (saturating; cycles contribute 0).
    mutating func expandedCount(_ key: String, depth: Int = 0) -> Int {
        if let c = expandedMemo[key] { return c }
        guard depth < maxBlockDepth, let b = doc.blocks[key], !expandedVisiting.contains(key) else { return 0 }
        expandedVisiting.insert(key)
        var total = 0
        for e in b.entities {
            switch e {
            case .insert(let ins, _):
                if let k = resolve(ins.blockName) {
                    let cells = max(1, ins.columns).multipliedReportingOverflow(by: max(1, ins.rows))
                    let per = expandedCount(k, depth: depth + 1)
                    let (x, o) = per.multipliedReportingOverflow(by: cells.overflow ? Int.max : cells.partialValue)
                    total = o ? Int.max : total.addingReportingOverflow(x).overflow ? Int.max : total + x
                }
                total = total == Int.max ? total : total + 1
            case .dimension(let d, _):
                if let k = resolve(d.blockName) { let x = expandedCount(k, depth: depth + 1); total = total.addingReportingOverflow(x).overflow ? Int.max : total + x }
            default:
                if total < Int.max { total += 1 }
            }
            if total >= Int.max / 4 { total = Int.max; break }
        }
        expandedVisiting.remove(key)
        expandedMemo[key] = total
        return total
    }

    mutating func convertInsert(_ ins: CADInsert, _ p: CADEntityProps, _ st: Style, _ m: Transform2, into out: inout [Entity], depth: Int, inBlock: Bool,
                                stack: [String], countAs: String = "INSERT") {
        // Attributes are placed in the parent's coordinates.
        for a in ins.attributes where !a.isInvisible && !a.text.text.isEmpty {
            _ = emitText(a.text, m, st, into: &out)
        }
        guard let key = resolve(ins.blockName), let block = doc.blocks[key] else {
            if !ins.blockName.isEmpty { warningOnce("Some block references point to blocks that are not defined; they were skipped.") }
            invalid += 1
            return
        }
        if stack.contains(key) {
            cycleRefs.insert(key)
            return
        }
        if depth >= maxBlockDepth {
            depthLimited += 1
            return
        }
        let cols = max(1, ins.columns), rows = max(1, ins.rows)
        let cells = cols.multipliedReportingOverflow(by: rows)
        let per = max(1, expandedCount(key))
        if !inBlock {
            let (cost, o) = per.multipliedReportingOverflow(by: cells.overflow ? Int.max : cells.partialValue)
            if o || cells.overflow || budgetUsed.addingReportingOverflow(cost).overflow || budgetUsed + cost > maxEntities {
                skippedForBudget += 1
                return
            }
            budgetUsed += cost
        }
        let isDim = countAs == "DIMENSION"
        let base = isDim ? Vec2.zero : block.basePoint
        let attrs = Dictionary(ins.attributes.map { ($0.tag, $0.text.text) }, uniquingKeysWith: { a, _ in a })
        var ok = false
        for c in 0..<cols {
            for r in 0..<rows {
                let t = isDim ? Transform2.identity : ins.transform(basePoint: base, column: c, row: r)
                if options.explodeBlocks {
                    let mt = m * t
                    let childStack = stack + [key]
                    // Pushed in reverse so they are converted in source order; processed iteratively by `convertTree`.
                    for e in block.entities.reversed() {
                        spawned.append(WorkItem(entity: e, m: mt, depth: depth + 1, inherited: p, stack: childStack))
                    }
                    ok = true
                } else {
                    // Block content is stored in meters about the block's own origin: T' = m · T · S(1/s).
                    let tr = m * t * Transform2.scale(1 / s, 1 / s)
                    out.append(.insert(block: key, transform: tr, attributes: attrs, st))
                    if !queued.contains(key) { queued.insert(key); neededBlocks.append(key) }
                    ok = true
                }
            }
        }
        if ok && !inBlock { converted += 1 }
    }

    /// Removes insert entities in converted blocks that would form reference cycles or exceed the depth limit.
    mutating func pruneBlockGraph() {
        guard !options.explodeBlocks, !blockOut.isEmpty else { return }
        var state: [String: Int] = [:] // 1 visiting, 2 done
        var depthOf: [String: Int] = [:]
        func visit(_ k: String, _ depth: Int) {
            if state[k] == 2, (depthOf[k] ?? 0) >= depth { return }
            state[k] = 1
            depthOf[k] = depth
            guard let ents = blockOut[k] else { state[k] = 2; return }
            var kept: [Entity] = []
            kept.reserveCapacity(ents.count)
            for e in ents {
                if case .insert(let child, _, _, _) = e {
                    if state[child] == 1 { cycleRefs.insert(child); continue }
                    if depth + 1 >= maxBlockDepth { depthLimited += 1; continue }
                    visit(child, depth + 1)
                }
                kept.append(e)
            }
            blockOut[k] = kept
            state[k] = 2
        }
        for k in blockOut.keys.sorted() where state[k] == nil { visit(k, 1) }
    }

    var onceWarnings: Set<String> = []
    mutating func warningOnce(_ w: String) {
        if onceWarnings.insert(w).inserted { warnings.append(w) }
    }
}

extension CADImportReport {
    /// Internal carrier for conversion results.
    struct ResultBox {
        var drawing: ReferenceDrawing
        var report: CADImportReport
    }
}

enum CADConversionMath {
    /// Smooth curve through fit points (Catmull-Rom), for splines defined only by fit points.
    static func smooth(_ pts: [Vec2]) -> [Vec2] {
        guard pts.count > 2 else { return pts }
        var out: [Vec2] = [pts[0]]
        let segs = 8
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(pts.count - 1, i + 2)]
            for k in 1...segs {
                let t = Double(k) / Double(segs)
                let t2 = t * t, t3 = t2 * t
                let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                out.append(Vec2(x, y))
            }
        }
        return out
    }

    /// Greedy word wrap using an average glyph width of 0.6 × height.
    static func wrap(_ lines: [String], width: Double, height: Double) -> [String] {
        let maxChars = max(1, Int(width / (height * 0.6)))
        var out: [String] = []
        for l in lines {
            if l.count <= maxChars { out.append(l); continue }
            var cur = ""
            for w in l.split(separator: " ", omittingEmptySubsequences: false) {
                if cur.isEmpty { cur = String(w) } else if cur.count + 1 + w.count <= maxChars { cur += " " + w } else { out.append(cur); cur = String(w) }
            }
            out.append(cur)
        }
        return out
    }
}
