import Foundation
import ArcusGeometry

// POLISH: Part Tags on shop drawings laid out as on a Revit construction set. The tags stand outside the piece in a
// column on each side, clear of the dimensions, the datum labels and each other, stacked in the order of the parts
// they point at, with a short horizontal shoulder and a leader to the part. Fabricate ▸ Shop Drawings uses it for the
// Front elevation and Section A (FurnitureShopDrawings.tagParts).

public enum FurnitureTagLayout {
    /// Half the Part Tag's box on paper (24 × 7 mm, FurniturePartTypes.ensurePartTag; documents made before keep 18 mm boxes).
    public static let boxHalf = Vec2(0.012, 0.0035)
    /// Paper space between stacked tags, and between a column and what it keeps clear of.
    static let gap = 0.0015, clearance = 0.0025

    /// A tag's head, the point its leader ends at on the part, and the leader's elbow (nil for a straight leader).
    public struct Placement: Hashable, Sendable {
        public var part: ElementID
        public var head: Vec2
        public var anchor: Vec2
        public var elbow: Vec2?
    }

    /// What a view draws, in view coordinates: the outline of the piece (model graphics, without datums) and the boxes
    /// of its annotations (texts, dimensions, tags), skipping the tags in `skipping`.
    public static func scene(_ g: ViewGraphics, skipping: Set<ElementID> = []) -> (outline: Rect2, obstacles: [Rect2]) {
        let s = Double(max(g.scale, 1))
        var outline = Rect2.empty
        var obstacles: [Rect2] = []
        let datums: Set<Category> = [.referencePlanes, .levels, .grids]
        for item in g.items {
            if let id = item.elementID, skipping.contains(id) { continue }
            let annotation = item.layer == .annotation || item.layer == .overlay || datums.contains(item.category)
            if !annotation {
                if [.model, .cut, .fills].contains(item.layer) { outline.include(item.bounds) }
                continue
            }
            for p in item.primitives { if case .text(let t) = p { obstacles.append(textBox(t, scale: s)) } }
            if item.category == .dimensions || item.category == .tags || item.category == .textNotes {
                obstacles.append(item.hitPolygons.isEmpty ? item.bounds : Rect2(points: item.hitPolygons.flatMap(\.points)))
            }
        }
        if let c = g.crop, !outline.isEmpty { outline = outline.intersection(c) }
        return (outline, obstacles.filter { !$0.isEmpty })
    }

    /// The view box of a text: its estimated extent, turned with the text.
    static func textBox(_ t: GText, scale s: Double) -> Rect2 {
        let size = TextMetrics.blockSize(t.string, height: t.height, bold: t.bold, wrap: t.wrapWidth) * s
        let x0: Double = t.alignment == .left ? 0 : t.alignment == .center ? -size.x / 2 : -size.x
        let y0 = -t.verticalAnchor * size.y
        let corners = [Vec2(x0, y0), Vec2(x0 + size.x, y0), Vec2(x0 + size.x, y0 + size.y), Vec2(x0, y0 + size.y)]
        let c = cos(t.rotation), sn = sin(t.rotation)
        return Rect2(points: corners.map { t.position + Vec2($0.x * c - $0.y * sn, $0.x * sn + $0.y * c) }).expanded(by: t.height * s * 0.25)
    }

    /// Lays out tags for `parts` (each with the point its leader ends at) around `outline`, at view scale `scale`:
    /// parts left of the middle in the left column, right of it in the right one, those in the middle shared out; each
    /// column is sorted top to bottom, spaced a tag apart, centred on its parts, and pushed out past every obstacle
    /// beside it, so no tag covers the piece, a dimension, a label or another tag.
    public static func layout(_ parts: [(id: ElementID, anchor: Vec2)], outline: Rect2, obstacles: [Rect2], scale: Int) -> [Placement] {
        guard !parts.isEmpty, !outline.isEmpty else { return [] }
        let s = Double(max(scale, 1))
        let half = boxHalf * s, pitch = 2 * half.y + gap * s, clear = clearance * s
        var left: [(id: ElementID, anchor: Vec2)] = [], right: [(id: ElementID, anchor: Vec2)] = []
        let mid = outline.center.x, band = outline.width * 0.06
        for p in parts.sorted(by: { ($0.anchor.y, -$0.anchor.x, $1.id) > ($1.anchor.y, -$1.anchor.x, $0.id) }) {
            if p.anchor.x < mid - band { left.append(p) } else if p.anchor.x > mid + band { right.append(p) }
            else if left.count <= right.count { left.append(p) } else { right.append(p) }
        }
        func column(_ items: [(id: ElementID, anchor: Vec2)], side: Double) -> [Placement] {
            guard !items.isEmpty else { return [] }
            let desired = items.map(\.anchor.y)
            var ys: [Double] = []
            for y in desired { ys.append(ys.last.map { min(y, $0 - pitch) } ?? y) }
            let shift = desired.reduce(0, +) / Double(desired.count) - ys.reduce(0, +) / Double(ys.count)
            ys = ys.map { $0 + shift }
            let top = ys.first! + half.y + clear, bottom = ys.last! - half.y - clear
            // The column's inner edge: outside the piece, then past each obstacle in the column's band.
            var edge = side < 0 ? outline.min.x - clear : outline.max.x + clear
            var moved = true, guardCount = 0
            while moved && guardCount < 200 {
                moved = false; guardCount += 1
                for o in obstacles where o.max.y > bottom && o.min.y < top {
                    if side < 0, o.min.x < edge, o.max.x > edge - 2 * half.x - clear { edge = o.min.x - clear; moved = true }
                    if side > 0, o.max.x > edge, o.min.x < edge + 2 * half.x + clear { edge = o.max.x + clear; moved = true }
                }
            }
            let x = edge + side * half.x
            // The shoulder: a short horizontal run from the tag towards the piece, then the leader turns to the part.
            let shoulder = side < 0 ? edge + min(2 * clear, (outline.min.x - edge) / 2) : edge - min(2 * clear, (edge - outline.max.x) / 2)
            let items = uncrossed(items, ys, shoulder: shoulder) // FMG4: tags in the order of their parts along the leaders
            return zip(items, ys).map { it, y in
                let elbow: Vec2? = abs(y - it.anchor.y) < 1e-6 ? nil : Vec2(shoulder, y)
                return Placement(part: it.id, head: Vec2(x, y), anchor: it.anchor, elbow: elbow)
            }
        }
        return column(left, side: -1) + column(right, side: 1)
    }

    /// FMG4: the column's parts reordered so no two leaders cross: each leader runs from the shoulder at its tag's
    /// height to its part, and two that cross swap parts (which shortens them both; so it ends).
    static func uncrossed(_ items: [(id: ElementID, anchor: Vec2)], _ ys: [Double], shoulder: Double) -> [(id: ElementID, anchor: Vec2)] {
        var out = items
        guard out.count > 1 else { return out }
        func leader(_ k: Int) -> Segment2 { Segment2(Vec2(shoulder, ys[k]), out[k].anchor) }
        for _ in 0..<(out.count * out.count) {
            var swapped = false
            for i in out.indices { for j in out.indices where j > i {
                if leader(i).intersection(leader(j)) != nil { out.swapAt(i, j); swapped = true }
            } }
            if !swapped { break }
        }
        return out
    }

    /// The paper box of a tag placed at `head` in a view at `scale`.
    public static func box(_ head: Vec2, scale: Int) -> Rect2 { Rect2(center: head, halfSize: boxHalf * Double(max(scale, 1))) }
}
