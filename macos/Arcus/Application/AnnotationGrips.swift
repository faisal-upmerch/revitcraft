import Foundation
import ArcusGeometry
import ArcusDomain

// W2-ANNOT: grips of annotations — text position, wrap width, leader ends and elbows; tag heads, leader ends and
// elbows; dimension lines, witness lines and value texts; spot points and heads; repeating detail paths.
extension GripService {
    /// View units per paper meter for an annotation (its owner view's scale; 1 on sheets and in unknown views).
    static func paperScale(of e: Element, _ model: BIMModel) -> Double {
        guard let v = model[e.ownerViewID], let vd = v.view else { return 1 }
        return Double(max(vd.scale, 1))
    }

    /// Grips of annotation elements; nil for other elements.
    static func annotationGrips(for e: Element, _ model: BIMModel) -> [Grip]? {
        let s = paperScale(of: e, model)
        let view = model[e.ownerViewID]
        switch e.data {
        case .textNote(let n):
            let style = TextNoteStyle.resolve(e, model)
            let box = TextNoteGeometry.box(n, style, scale: s)
            var g = [Grip(elementID: e.id, kind: .textPosition, position: n.position)]
            // Wrap width: the middle of the side opposite the insertion point (the right side of left-aligned text).
            let widthX = n.alignment == .right ? 0.0 : 1.0
            g.append(Grip(elementID: e.id, kind: .textWidth, position: box.point(widthX, 0.5), direction: box.u.normalized))
            for i in n.leaders.indices {
                g.append(Grip(elementID: e.id, kind: .leaderEnd(i), position: n.leaders[i]))
                if n.leaderShape != .arc, let el = TextNoteGeometry.elbowPoint(n, i, style, scale: s) {
                    g.append(Grip(elementID: e.id, kind: .leaderElbow(i), position: el))
                }
            }
            return g
        case .tag(let t):
            var g = [Grip(elementID: e.id, kind: .tagHead, position: t.head)]
            if t.hasLeader, t.kind != .treadNumber, let end = TagGeometry.leaderEnd(t, model, view: view) {
                g.append(Grip(elementID: e.id, kind: .tagLeaderEnd, position: end))
                g.append(Grip(elementID: e.id, kind: .tagLeaderElbow, position: t.leaderElbow ?? t.head.midpoint(end)))
            }
            return g
        case .dimension(let d) where d.kind == .linear || d.kind == .aligned:
            var g = [Grip(elementID: e.id, kind: .dimensionLine, position: d.linePoint)]
            guard let lay = DimensionLayout.make(e, d, model, scale: s, view: view) else { return g }
            g += lay.points.indices.map { Grip(elementID: e.id, kind: .witness($0), position: lay.points[$0]) }
            if d.chainStyle == nil || d.chainStyle == .continuous {
                g += lay.textPositions.indices.map { Grip(elementID: e.id, kind: .dimensionText($0), position: lay.textPositions[$0]) }
            }
            return g
        case .spot(let sp):
            return [Grip(elementID: e.id, kind: .spotPoint, position: sp.point), Grip(elementID: e.id, kind: .spotHead, position: sp.leaderHead)]
        case .detailComponent(let d):
            var g = [Grip(elementID: e.id, kind: .point, position: d.location)]
            if let end = d.repeatEnd { g.append(Grip(elementID: e.id, kind: .repeatEnd, position: end)) }
            return g
        case .insulation(let ins):
            return [Grip(elementID: e.id, kind: .start, position: ins.line.start), Grip(elementID: e.id, kind: .end, position: ins.line.end)]
        default:
            return nil
        }
    }

    /// Applies an annotation grip drag. Returns false when `g` is not an annotation grip.
    static func applyAnnotation(_ g: Grip, to p: Vec2, in tx: TransactionContext) -> Bool {
        guard let e = tx.model[g.elementID] else { return false }
        let s = paperScale(of: e, tx.model)
        switch (e.data, g.kind) {
        case (.textNote(let n), .textWidth):
            let style = TextNoteStyle.resolve(e, tx.model)
            let box = TextNoteGeometry.box(n, style, scale: s)
            let u = box.u.lengthSquared > 0 ? box.u.normalized : Vec2.fromAngle(n.rotation)
            let along = (p - n.position).dot(u)
            let paper: Double
            switch n.alignment {
            case .left: paper = along / s
            case .center: paper = 2 * abs(along) / s
            case .right: paper = -along / s
            }
            // A width smaller than one letter would wrap every character: keep at least a few.
            let w = max(style.size * 3, paper)
            tx.update(e.id) { $0.textNote?.width = w }
        case (.textNote, .leaderEnd(let i)):
            tx.update(e.id) { if var n = $0.textNote, i < n.leaders.count { n.leaders[i] = p; $0.textNote = n } }
        case (.textNote, .leaderElbow(let i)):
            tx.update(e.id) { el in
                guard var n = el.textNote, i < n.leaders.count else { return }
                var elbows = n.leaderElbows ?? []
                while elbows.count < n.leaders.count { elbows.append(nil) }
                elbows[i] = p
                n.leaderElbows = elbows
                el.textNote = n
            }
        case (.tag, .tagLeaderEnd):
            tx.update(e.id) { $0.tag?.leaderEnd = p }
        case (.tag, .tagLeaderElbow):
            tx.update(e.id) { $0.tag?.leaderElbow = p }
        case (.spot, .spotPoint):
            tx.update(e.id) { $0.spot?.point = p }
        case (.spot, .spotHead):
            tx.update(e.id) { $0.spot?.leaderHead = p }
        case (.detailComponent, .repeatEnd):
            tx.update(e.id) { $0.detailComponent?.repeatEnd = p }
        case (.detailComponent, .point):
            // Moving a repeating detail's start keeps its end in place.
            tx.update(e.id) { $0.detailComponent?.location = p }
        case (.insulation, .start):
            tx.update(e.id) { $0.insulation?.line.start = p }
        case (.insulation, .end):
            tx.update(e.id) { $0.insulation?.line.end = p }
        case (.dimension(let d), .dimensionText(let k)):
            var base = d
            base.textOffsets = nil
            guard let lay = DimensionLayout.make(e, base, tx.model, scale: s, view: tx.model[e.ownerViewID]), k < lay.textPositions.count else { return true }
            let offset = p - lay.textPositions[k]
            tx.update(e.id) { el in
                guard var dd = el.dimension else { return }
                var offs = dd.textOffsets ?? []
                while offs.count < lay.textPositions.count { offs.append(.zero) }
                offs[k] = offset
                dd.textOffsets = offs.allSatisfy({ $0.lengthSquared == 0 }) ? nil : offs
                el.dimension = dd
            }
        default:
            return false
        }
        return true
    }
}
