import Foundation
import ArcusGeometry

// FMG4: the template views' scale follows the piece, as their crop does (FurnitureViews.autoCrop). A Revit-style view
// scale is a view property the user sets; here the template's plan, elevations, Section A and {3D} start on an
// automatic scale: the standard furniture scale (3", 1 1/2", 1", 3/4", 1/2", 3/8" or 1/4" = 1'-0") at which the piece
// fills a sensible area of paper and its annotations stay small beside it. Width, Depth and Height changes pick it
// again; setting View Scale (Properties, or Shop Drawings arranging a sheet) turns it off for that view.
// The template's dimensions (Width, Depth, Height and their EQ strings) sit at paper distances outside the piece, one
// row above another, so their texts never pile up; elevation markers sit just outside the plan's crop.

public enum FurnitureAutoScale {
    /// A view parameter: true while the view's scale follows the piece (nil on a template view of an older document:
    /// automatic too).
    public static let onParam = ParameterID("furniture.autoScale")
    /// The scale the view was last given automatically (a different scale means the user set one).
    public static let valueParam = ParameterID("furniture.autoScale.value")
    /// A dimension parameter: its row outside the piece (1 nearest), while the template keeps it placed.
    public static let rowParam = ParameterID("furniture.annotationRow")
    /// The distance outside the piece it was last placed at (a different one means the user moved it).
    public static let offsetParam = ParameterID("furniture.annotationOffset")

    /// An elevation parameter: where its marker was last placed ("x,y"), or false once the user moved it.
    public static let markerParam = ParameterID("furniture.markerPlaced")
    static func key(_ p: Vec2) -> String { String(format: "%.6f,%.6f", p.x, p.y) }

    /// The standard furniture scales, finest first.
    public static let scales = [4, 8, 12, 16, 24, 32, 48]
    /// The paper a view of the piece should fill at most: the long side, the short side (meters).
    static let paper = (long: 0.13, short: 0.09)
    /// The tallest annotation text (level heads, view titles in the view: 1/8").
    static let textHeight = 0.003175
    /// Paper distance from the piece to the first row of dimensions, and between rows.
    static let firstRow = 0.0064, rowGap = 0.0095
    /// Paper room past the last row (its text) and for an elevation marker's head.
    static let rowText = 0.004, markerReach = 0.0076

    /// The scale for a piece of this size (meters): the finest standard scale at which each view of it fits the paper
    /// area, kept fine enough that annotation text is no more than a sixth of the piece's smallest plan dimension.
    public static func scale(width w: Double, depth d: Double, height h: Double) -> Int {
        let views = [(w, d), (w, h), (d, h)]
        let fit = scales.first { s in
            views.allSatisfy { a, b in max(a, b) / Double(s) <= paper.long && min(a, b) / Double(s) <= paper.short }
        } ?? scales.last!
        let finest = max(min(w, d), 0.01) / (6 * textHeight)
        return scales.last { $0 <= fit && Double($0) <= finest } ?? scales[0]
    }

    /// True when the view's scale is automatic.
    static func isOn(_ v: Element) -> Bool {
        if let b = v.params[onParam]?.boolValue { return b }
        return v.params[FurnitureViews.autoCrop]?.boolValue == true || (v.view?.kind == .threeD && v.name == "{3D}")
    }

    /// Picks the automatic views' scale again, places the template's dimensions and the elevation markers for it, and
    /// turns the automatic scale off on views whose scale was set in this transaction.
    static func regenerate(_ tx: TransactionContext, _ touched: [ElementID]) {
        guard tx.model.isFurniture else { return }
        let touchedSet = Set(touched)
        // A scale set by the user (any edit but ours) switches the view to its own scale.
        for v in tx.model.views where touchedSet.contains(v.id) && isOn(v) {
            guard let now = v.view?.scale else { continue }
            let given = v.params[valueParam]?.intValue ?? tx.originalElement(v.id)?.view?.scale
            if let given, given != now { tx.propagate(v.id) { $0.params[onParam] = .bool(false); $0.params[valueParam] = nil } }
        }
        let e = FurniturePlanes.extents(tx.model)
        let m = FurniturePlanes.margin
        let w = e.x.upperBound - e.x.lowerBound - 2 * m, d = e.y.upperBound - e.y.lowerBound - 2 * m, h = e.z.upperBound - e.z.lowerBound - 2 * m
        guard w > 0, d > 0, h > 0 else { return }
        let s = scale(width: w, depth: d, height: h)
        for v in tx.model.views where isOn(v) && v.view != nil {
            if v.view?.scale != s || v.params[valueParam]?.intValue != s || v.params[onParam] == nil {
                tx.propagate(v.id) { $0.view?.scale = s; $0.params[onParam] = .bool(true); $0.params[valueParam] = .int(s) }
            }
        }
        placeDimensions(tx, e)
        placeMarkers(tx, e)
    }

    /// The template's dimensions and the elevation markers placed for the views' scale now (Shop Drawings, after it
    /// sets the scales of F101's views, before it measures them).
    public static func followScales(_ tx: TransactionContext) {
        guard tx.model.isFurniture else { return }
        let e = FurniturePlanes.extents(tx.model)
        placeDimensions(tx, e)
        placeMarkers(tx, e)
    }

    /// The template's dimensions at their rows outside the piece, at the view's scale.
    static func placeDimensions(_ tx: TransactionContext, _ e: (x: ClosedRange<Double>, y: ClosedRange<Double>, z: ClosedRange<Double>)) {
        var byView: [ElementID: [Element]] = [:]
        for dim in tx.model.elements(.dimensions) {
            // Template dimensions follow their view's scale, automatic or not (Shop Drawings sets the scale of F101's views).
            guard let vid = dim.ownerViewID, let v = tx.model[vid], dim.dimension != nil,
                  dim.params[rowParam] != nil || (v.params[onParam] == nil && v.params[FurnitureViews.autoCrop]?.boolValue == true) else { continue }
            byView[vid, default: []].append(dim)
        }
        let framing = Set(["Left", "Right", "Front", "Back", "Bottom", "Top", "Center (Left/Right)", "Center (Front/Back)"])
        let names = FurniturePlanes.names(tx.model)
        for (vid, dims) in byView {
            guard let v = tx.model[vid], let vd = v.view, let r0 = FurnitureRegeneration.viewRect(vd, e) else { continue }
            let rect = r0.expanded(by: -FurniturePlanes.margin)
            let s = Double(max(vd.scale, 1))
            // Rows: the template's (flagged), or on older documents the framing dimensions by their distance outside.
            var sides: [Int: [(Element, Double)]] = [:]
            for dim in dims {
                guard let dd = dim.dimension else { continue }
                let flagged = dim.params[rowParam] != nil
                if !flagged {
                    guard v.params[onParam] == nil, dd.references.allSatisfy({ $0.elementID.flatMap { names[$0] }.map(framing.contains) == true }) else { continue }
                }
                guard let (side, dist) = Self.side(dd.linePoint, rect) else { continue }
                if let placed = dim.params[offsetParam]?.doubleValue, abs(placed - dist) > 1e-4 {
                    // Moved by the user: theirs from now on.
                    tx.propagate(dim.id) { $0.params[rowParam] = nil; $0.params[offsetParam] = nil }
                    continue
                }
                sides[side, default: []].append((dim, dist))
            }
            for (side, list) in sides {
                let sorted = list.sorted { a, b in
                    let ra = a.0.params[rowParam]?.intValue ?? 0, rb = b.0.params[rowParam]?.intValue ?? 0
                    return ra != rb ? ra < rb : a.1 < b.1
                }
                var row = 0, last: Int?
                for (dim, _) in sorted {
                    let r = dim.params[rowParam]?.intValue
                    if r == nil || r != last { row += 1 }
                    last = r
                    let dist = (firstRow + rowGap * Double(row - 1)) * s
                    guard var lp = dim.dimension?.linePoint else { continue }
                    switch side {
                    case 0: lp.y = rect.min.y - dist
                    case 1: lp.x = rect.max.x + dist
                    case 2: lp.y = rect.max.y + dist
                    default: lp.x = rect.min.x - dist
                    }
                    let rowValue = r ?? row
                    if dim.dimension?.linePoint != lp || dim.params[offsetParam]?.doubleValue.map({ abs($0 - dist) > 1e-9 }) != false || dim.params[rowParam] == nil {
                        tx.propagate(dim.id) { $0.dimension?.linePoint = lp; $0.params[rowParam] = .int(rowValue); $0.params[offsetParam] = .double(dist) }
                    }
                }
            }
        }
    }

    /// The side of `rect` a dimension line point lies outside (0 below, 1 right, 2 above, 3 left) and how far.
    static func side(_ p: Vec2, _ rect: Rect2) -> (Int, Double)? {
        let out = [(0, rect.min.y - p.y), (1, p.x - rect.max.x), (2, p.y - rect.max.y), (3, rect.min.x - p.x)].filter { $0.1 > 1e-6 }
        return out.max { $0.1 < $1.1 }
    }

    /// The elevations' markers (and their view planes) just outside the plan's crop and dimensions, and the plan's
    /// annotation crop taking them in.
    static func placeMarkers(_ tx: TransactionContext, _ e: (x: ClosedRange<Double>, y: ClosedRange<Double>, z: ClosedRange<Double>)) {
        guard let plan = tx.model.views.first(where: { $0.view?.kind.isPlan == true && $0.params[FurnitureViews.autoCrop]?.boolValue == true }),
              let pd = plan.view else { return }
        let s = Double(max(pd.scale, 1))
        let m = FurniturePlanes.margin
        let piece = Rect2(min: Vec2(e.x.lowerBound + m, e.y.lowerBound + m), max: Vec2(e.x.upperBound - m, e.y.upperBound - m))
        let cropReach = m + 0.05 // FurnitureRegeneration.fitCrops' pad
        let dimsReach = (firstRow + rowGap + rowText) * s
        let dist = max(cropReach, dimsReach) + markerReach * s
        for v in tx.model.views where v.view?.kind == .elevation && v.params[FurnitureViews.autoCrop]?.boolValue == true && v.params[markerParam]?.boolValue != false {
            guard let vd = v.view, let dir = vd.viewDirection else { continue }
            // A marker the user moved stays where they put it.
            if let placed = v.params[markerParam]?.textValue, let mp = vd.markerPosition, placed != Self.key(mp) {
                tx.propagate(v.id) { $0.params[markerParam] = .bool(false) }
                continue
            }
            let half = abs(dir.x) * piece.width / 2 + abs(dir.y) * piece.height / 2
            var at = piece.center - dir * (half + dist)
            // The Front and Back markers sit a quarter of the width to the left, off Section A's line and head.
            if abs(dir.y) > 0.5 { at.x -= piece.width / 4 }
            // The view plane moves only along the view direction (across it, it sets the view's coordinates).
            let o = vd.planeOrigin.map { Vec2($0.x, $0.y) } ?? at
            let o2 = o + dir * (at - o).dot(dir)
            let origin = Vec3(o2, z: vd.planeOrigin?.z ?? 0)
            if vd.markerPosition.map({ $0.distance(to: at) > 1e-6 }) != false || vd.planeOrigin != origin {
                tx.propagate(v.id) { $0.view?.markerPosition = at; $0.view?.planeOrigin = origin; $0.params[markerParam] = .text(Self.key(at)) }
            } else if v.params[markerParam] == nil {
                tx.propagate(v.id) { $0.params[markerParam] = .text(Self.key(at)) }
            }
        }
        let need = (dist - cropReach) / s + 0.006
        if need > pd.annotationCropOffset + 1e-6 { tx.propagate(plan.id) { $0.view?.annotationCropOffset = need } }
    }
}
