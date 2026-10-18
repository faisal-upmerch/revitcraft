import Foundation
import ArcusGeometry
import ArcusDomain

/// Grips for direct manipulation of selected elements. Drag grips (`grips(for:)`) move geometry; controls
/// (`controls(for:)`) are click targets drawn on the selection that toggle a setting, such as the flip arrows on walls,
/// doors and windows, grid and level bubble boxes, and the EQ and padlock glyphs on dimensions.
public struct Grip: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case start, end, point, cropEdge(Int), dimensionLine, tagHead, textPosition, sectionEnd(Bool), sketchVertex(Int)
        /// I4: a section's far clip (the triangle beyond its line) and a grid bubble's elbow (drag it across the grid).
        case sectionDepth, gridElbow(atEnd: Bool)
        /// Witness line `i` of a dimension: drag it onto another reference.
        case witness(Int)
        /// Annotation handles: text wrap width, text leader `i` end and elbow, tag leader end and elbow, the value text of
        /// dimension segment `i`, spot point and head, and the far end of a repeating detail.
        case textWidth, leaderEnd(Int), leaderElbow(Int), tagLeaderEnd, tagLeaderElbow, dimensionText(Int), spotPoint, spotHead, repeatEnd
        /// Controls (click to toggle).
        case flipWall, flipFacing, flipHand, bubble(atEnd: Bool), dimensionEquality, dimensionLock
        /// I4 controls (RevitCraft): a grid end's 3D/2D extents switch, Add Elbow, the alignment lock, and a section's flip.
        case gridExtents(atEnd: Bool), addElbow(atEnd: Bool), gridLock(atEnd: Bool), flipSection
    }
    public var elementID: ElementID
    public var kind: Kind
    public var position: Vec2
    /// Glyph axis for controls (the flip arrows point both ways along it).
    public var direction: Vec2 = .unitX
    /// Current state of a toggle control (bubble shown, equality on, dimension locked). Grid ends: 2D extents.
    public var isOn = false
    /// I4: the view whose 2D extents a grid grip edits.
    public var viewID: ElementID? = nil

    public var isControl: Bool {
        switch kind {
        case .flipWall, .flipFacing, .flipHand, .bubble, .dimensionEquality, .dimensionLock, .gridExtents, .addElbow, .gridLock, .flipSection: true
        default: false
        }
    }
}

public enum GripService {
    /// `levelLine`: the drawn start and end of a level line in an elevation or section (from the view graphics), so levels
    /// without explicit extents still get end grips.
    public static func grips(for e: Element, _ model: BIMModel, viewKind: ViewKind?, levelLine: (Double, Double)? = nil, viewID: ElementID? = nil) -> [Grip] {
        if let g = annotationGrips(for: e, model) { return g }
        switch e.data {
        case .wall(let w): return [Grip(elementID: e.id, kind: .start, position: w.location.start), Grip(elementID: e.id, kind: .end, position: w.location.end)]
        case .modelLine(let l): return [Grip(elementID: e.id, kind: .start, position: l.curve.start), Grip(elementID: e.id, kind: .end, position: l.curve.end)]
        case .beam(let b): return [Grip(elementID: e.id, kind: .start, position: b.curve.start), Grip(elementID: e.id, kind: .end, position: b.curve.end)]
        case .grid(let g): return viewKind?.isPlan == true ? gridGrips(e.id, g, viewID: viewID) : []
        case .referencePlane(let r): return [Grip(elementID: e.id, kind: .start, position: r.line.start), Grip(elementID: e.id, kind: .end, position: r.line.end)]
        case .component(let c): return [Grip(elementID: e.id, kind: .point, position: c.location)]
        case .column(let c): return [Grip(elementID: e.id, kind: .point, position: c.location)]
        case .room(let r): return [Grip(elementID: e.id, kind: .point, position: r.point)]
        case .tag(let t): return [Grip(elementID: e.id, kind: .tagHead, position: t.head)]
        case .textNote(let n): return [Grip(elementID: e.id, kind: .textPosition, position: n.position)]
        case .dimension(let d):
            var g = [Grip(elementID: e.id, kind: .dimensionLine, position: d.linePoint)]
            if d.kind == .linear || d.kind == .aligned, let geo = dimensionGeometry(d, model) {
                g += geo.points.indices.map { Grip(elementID: e.id, kind: .witness($0), position: geo.points[$0]) }
            }
            return g
        case .insert(let i): return [Grip(elementID: e.id, kind: .point, position: i.location)]
        case .level(let l) where viewKind?.isVerticalCut == true:
            var g: [Grip] = []
            if let s = l.extentStart ?? levelLine?.0 { g.append(Grip(elementID: e.id, kind: .start, position: Vec2(s, l.elevation))) }
            if let en = l.extentEnd ?? levelLine?.1 { g.append(Grip(elementID: e.id, kind: .end, position: Vec2(en, l.elevation))) }
            return g
        case .view(let vd) where viewKind?.isPlan == true && (vd.kind == .section || vd.kind == .detail): return sectionGrips(e.id, vd) // I4
        case .view: return CameraGrips.grips(for: e, viewKind: viewKind) // W2-CAM
        default: return []
        }
    }

    /// Applies a grip drag. Returns false if not applicable.
    public static func apply(_ g: Grip, to p: Vec2, in tx: TransactionContext) {
        if CameraGrips.apply(g, to: p, in: tx) { return } // W2-CAM
        var p = p
        // A wall end dropped on another wall's end joins it (see WallGeometry.joinEndpoint).
        if g.kind == .start || g.kind == .end, let e = tx.model[g.elementID], let w = e.wall, g.kind == .start ? w.allowJoinAtStart : w.allowJoinAtEnd,
           let q = WallGeometry.joinEndpoint(near: p, levelID: e.levelID, excluding: [e.id], tx.model) { p = q }
        if applyAnnotation(g, to: p, in: tx) { return }
        if applyDatum(g, to: p, in: tx) { return } // I4
        tx.update(g.elementID) { e in
            switch (e.data, g.kind) {
            case (.wall(var w), .start): w.location = replaceEnd(w.location, start: p); e.data = .wall(w)
            case (.wall(var w), .end): w.location = replaceEnd(w.location, end: p); e.data = .wall(w)
            case (.modelLine(var l), .start): l.curve = replaceEnd(l.curve, start: p); e.data = .modelLine(l)
            case (.modelLine(var l), .end): l.curve = replaceEnd(l.curve, end: p); e.data = .modelLine(l)
            case (.beam(var b), .start): b.curve = replaceEnd(b.curve, start: p); e.data = .beam(b)
            case (.beam(var b), .end): b.curve = replaceEnd(b.curve, end: p); e.data = .beam(b)
            case (.grid(var gd), .start): gd.curve = replaceEnd(gd.curve, start: p); e.data = .grid(gd)
            case (.grid(var gd), .end): gd.curve = replaceEnd(gd.curve, end: p); e.data = .grid(gd)
            case (.referencePlane(var r), .start): r.line.start = p; e.data = .referencePlane(r)
            case (.referencePlane(var r), .end): r.line.end = p; e.data = .referencePlane(r)
            case (.component(var c), .point): c.location = p; e.data = .component(c)
            case (.column(var c), .point): c.location = p; e.data = .column(c)
            case (.room(var r), .point): r.point = p; e.data = .room(r)
            case (.tag(var t), .tagHead): t.head = p; e.data = .tag(t)
            case (.textNote(var n), .textPosition): n.position = p; e.data = .textNote(n)
            case (.dimension(var d), .dimensionLine): d.linePoint = p; e.data = .dimension(d)
            case (.insert(var i), .point): i.location = p; e.data = .insert(i)
            case (.level(var l), .start): l.extentStart = p.x; e.data = .level(l)
            case (.level(var l), .end): l.extentEnd = p.x; e.data = .level(l)
            default: break
            }
        }
    }

    // MARK: Controls

    /// Click targets for a selected element. `pixel` is view units per screen point: controls sit a fixed screen
    /// distance from the geometry at any zoom. `levelLine` as for `grips(for:)`.
    public static func controls(for e: Element, _ model: BIMModel, view: Element?, pixel: Double, levelLine: (Double, Double)? = nil) -> [Grip] {
        let kind = view?.view?.kind
        let gap = 16 * pixel
        switch e.data {
        case .wall(let w) where kind?.isPlan == true:
            guard let f = WallGeometry.frame(e, model) else { return [] }
            // The arrows sit just outside the exterior face, the side the wall's exterior layers face.
            let exterior = f.location.normal(at: 0.5) * (w.flipped ? -1 : 1)
            let mid = f.location.point(at: 0.5)
            return [Grip(elementID: e.id, kind: .flipWall, position: mid + exterior * (abs(f.exteriorOffset) + gap), direction: exterior)]
        case .insert where kind?.isPlan == true:
            guard let pl = InsertGeometry.placement(e, model), let host = model[e.hostID], let f = WallGeometry.frame(host, model) else { return [] }
            let origin = pl.plan.apply(.zero)
            let x = pl.plan.applyVector(.unitX).normalized, y = pl.plan.applyVector(Vec2(0, 1)).normalized
            let half = f.thickness / 2 + gap
            // Facing arrows on the side the door or window faces; hand arrows opposite, pointing along the wall.
            return [Grip(elementID: e.id, kind: .flipFacing, position: origin + y * half, direction: y),
                    Grip(elementID: e.id, kind: .flipHand, position: origin - y * half, direction: x)]
        case .grid(let g) where kind?.isPlan == true:
            let r = DatumGraphics.bubbleRadius * Double(view?.view?.scale ?? 100)
            let c = g.curve(in: view?.id)
            // I4: the bubble checkbox sits beyond the bubble along the grid, as in RevitCraft.
            let bubbles = [false, true].map { atEnd in
                let p = (atEnd ? c.end : c.start) + ((atEnd ? g.extent(in: view?.id)?.elbowEnd : g.extent(in: view?.id)?.elbowStart) ?? .zero)
                let out = c.tangent(at: atEnd ? 1 : 0) * (atEnd ? 1 : -1)
                return Grip(elementID: e.id, kind: .bubble(atEnd: atEnd), position: p + out * (2 * r + 12 * pixel), isOn: atEnd ? g.bubbleAtEnd : g.bubbleAtStart)
            }
            return bubbles + gridControls(e, g, model, view: view, pixel: pixel, bubbleRadius: r) // I4
        case .level(let l) where kind?.isVerticalCut == true:
            guard let s = l.extentStart ?? levelLine?.0, let en = l.extentEnd ?? levelLine?.1 else { return [] }
            let left = min(s, en) == s
            return [Grip(elementID: e.id, kind: .bubble(atEnd: false), position: Vec2(s + (left ? gap : -gap), l.elevation - gap), isOn: l.showBubbleStart),
                    Grip(elementID: e.id, kind: .bubble(atEnd: true), position: Vec2(en + (left ? -gap : gap), l.elevation - gap), isOn: l.showBubbleEnd)]
        case .view(let vd) where kind?.isPlan == true && (vd.kind == .section || vd.kind == .detail):
            return sectionControls(e.id, vd, pixel: pixel) // I4
        case .dimension(let d) where d.kind == .linear || d.kind == .aligned:
            guard let geo = dimensionGeometry(e, model) else { return [] }
            let scale = paperScale(of: e, model)
            var out: [Grip] = []
            if d.references.count >= 3 {
                // EQ sits opposite the dimension text, at the middle of the string.
                let mid = (geo.first + geo.last) * 0.5
                out.append(Grip(elementID: e.id, kind: .dimensionEquality, position: mid + geo.textSide * -(gap + 2 * pixel), direction: geo.direction, isOn: d.equality))
            }
            // The padlock goes where a locked dimension draws its lock.
            out.append(Grip(elementID: e.id, kind: .dimensionLock, position: geo.last + geo.direction * scale * 0.003, direction: geo.direction, isOn: d.locked))
            return out
        default: return []
        }
    }

    /// Undo name of a control's action.
    public static func actionName(_ kind: Grip.Kind) -> String? {
        switch kind {
        case .flipWall: "Flip Wall"
        case .flipFacing: "Flip Facing"
        case .flipHand: "Flip Hand"
        case .bubble: "Toggle Bubble"
        case .dimensionEquality: "Toggle Equality"
        case .dimensionLock: "Toggle Lock"
        case .gridExtents: "Toggle 3D/2D Extents"
        case .addElbow: "Add Elbow"
        case .gridLock: "Toggle Alignment Lock"
        case .flipSection: "Flip Section"
        default: nil
        }
    }

    /// Applies a control click. Each control toggles exactly one flag.
    public static func toggle(_ g: Grip, in tx: TransactionContext) {
        if toggleDatum(g, in: tx) { return } // I4
        tx.update(g.elementID) { e in
            switch g.kind {
            case .flipWall: e.wall?.flipped.toggle()
            case .flipFacing: e.insert?.facingFlipped.toggle()
            case .flipHand: e.insert?.handFlipped.toggle()
            case .bubble(let atEnd):
                if atEnd { e.grid?.bubbleAtEnd.toggle(); e.level?.showBubbleEnd.toggle() }
                else { e.grid?.bubbleAtStart.toggle(); e.level?.showBubbleStart.toggle() }
            case .dimensionEquality: e.dimension?.equality.toggle()
            case .dimensionLock: e.dimension?.locked.toggle()
            default: break
            }
        }
    }

    /// Where a linear or aligned dimension draws: the resolved reference points, the measurement direction, the
    /// extreme points on the dimension line and the side its text is on (same rules as the annotation renderer).
    public static func dimensionGeometry(_ e: Element, _ model: BIMModel) -> (points: [Vec2], direction: Vec2, first: Vec2, last: Vec2, textSide: Vec2)? {
        guard let d = e.dimension, let lay = DimensionLayout.make(e, d, model, scale: paperScale(of: e, model), view: model[e.ownerViewID]) else { return nil }
        return (lay.points, lay.direction, lay.first, lay.last, lay.textSide)
    }

    public static func dimensionGeometry(_ d: DimensionData, _ model: BIMModel) -> (points: [Vec2], direction: Vec2, first: Vec2, last: Vec2, textSide: Vec2)? {
        let pts: [Vec2] = d.references.enumerated().map { i, r in
            DimensionQueries.resolve(r, model)?.point ?? (i < d.fallbackPoints.count ? d.fallbackPoints[i] : d.linePoint)
        }
        guard pts.count >= 2 else { return nil }
        let n = DimensionQueries.measurementDirection(d, pts, model)
        let base = d.linePoint
        let proj = pts.map { base + n * ($0 - base).dot(n) }
        let along = proj.map { ($0 - base).dot(n) }
        guard let lo = along.indices.min(by: { along[$0] < along[$1] }), let hi = along.indices.max(by: { along[$0] < along[$1] }) else { return nil }
        let side = (pts[0] - base).dot(n.perpendicular) > 0 ? -1.0 : 1.0
        return (pts, n, proj[lo], proj[hi], n.perpendicular * -side)
    }

    static func replaceEnd(_ c: Curve2, start: Vec2? = nil, end: Vec2? = nil) -> Curve2 {
        switch c {
        case .line(let s): return .line(Segment2(start ?? s.start, end ?? s.end))
        case .arc(let a):
            let ns = start ?? a.start, ne = end ?? a.end
            return Arc2(through: ns, a.mid, ne).map { .arc($0) } ?? .line(Segment2(ns, ne))
        }
    }
}
