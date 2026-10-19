import Foundation
import ArcusGeometry
import ArcusDomain

// FM4: what the Furniture part tools share: how a view's 2D coordinates map to a part's sketch plane (plans draw on
// XY; Front/Back elevations on XZ; Left/Right on YZ), the planes the Options Bar offers, default types, and the
// Base/Top Constraint options every tool has.

/// How a view's coordinates map to a part sketch plane: plan (x, y) as is; vertical views (u, z) with u along the
/// view's right vector, which must run along X or Y.
public struct FurnitureSketchMap: Sendable, Equatable {
    public var plane: FamilySketchPlane
    /// Sketch u = a·(view u) + b in vertical views.
    var a: Double
    var b: Double
    /// The plan origin and right and forward vectors of a vertical view.
    var origin: Vec2
    var right: Vec2
    var forward: Vec2

    /// True when the view's u runs against the sketch's u (a Back or Right elevation): left and right swap.
    public var mirrored: Bool { plane != .xy && a < 0 }

    public func toSketch(_ p: Vec2) -> Vec2 { plane == .xy ? p : Vec2(a * p.x + b, p.y) }
    public func toView(_ p: Vec2) -> Vec2 { plane == .xy ? p : Vec2((p.x - b) / a, p.y) }

    /// A view point as a world point at depth `w` along the plane's normal (or height in plans).
    public func world(_ p: Vec2, w: Double) -> Vec3 { plane.point(toSketch(p).x, toSketch(p).y, w) }

    /// The sketch map of a view: plans, and elevations and sections square to the piece. nil for other views.
    public static func of(_ v: ViewData?) -> FurnitureSketchMap? {
        guard let v else { return nil }
        if v.kind.isPlan { return FurnitureSketchMap(plane: .xy, a: 1, b: 0, origin: .zero, right: .unitX, forward: Vec2(0, 1)) }
        guard v.kind.isVerticalCut, let o = v.planeOrigin, let r = v.rightVector, let f = v.viewDirection?.normalized else { return nil }
        if abs(abs(r.x) - 1) < 1e-6 { return FurnitureSketchMap(plane: .xz, a: r.x > 0 ? 1 : -1, b: o.x, origin: o.xy, right: r, forward: f) }
        if abs(abs(r.y) - 1) < 1e-6 { return FurnitureSketchMap(plane: .yz, a: r.y > 0 ? 1 : -1, b: o.y, origin: o.xy, right: r, forward: f) }
        return nil
    }

    /// The planes a part drawn on this sketch plane runs between by default (Bottom→Top, Front→Back, Left→Right).
    public var defaultExtent: (base: String, top: String) {
        switch plane {
        case .xy: ("Bottom", "Top")
        case .xz: ("Front", "Back")
        case .yz: ("Left", "Right")
        }
    }

    /// A view point projected to view coordinates from world (for vertical views: (u, z); plans: (x, y)).
    public func project(_ p: Vec3) -> Vec2 {
        plane == .xy ? p.xy : Vec2((p.xy - origin).dot(right), p.z)
    }
}

/// The Furniture tools' common Options Bar pieces.
@MainActor
public enum FurnitureToolOptions {
    /// The document's planes along `axis`, in order along it.
    public static func planeNames(_ axis: FamilyAxis, _ m: BIMModel) -> [String] {
        FurniturePartCoordinates.planes(along: axis, m).sorted { $0.position < $1.position }.map(\.name)
    }

    /// The part type the tool places: the Type Selector's choice, else the category's default.
    public static func type(_ cat: Category, family: String? = nil, _ ctx: ToolContext) -> ElementID? {
        if let t = ctx.currentTypes[cat], let td = ctx.model[t]?.typeData, td.instanceCategory == cat, family == nil || td.familyName == family { return t }
        return FurniturePartTypes.firstType(cat, family: family, ctx.model)
    }

    /// Base Constraint / Base Offset / Top Constraint / Top Offset or Unconnected Height options for `extent`.
    public static func extentOptions(_ e: PartExtent, axis: FamilyAxis, _ m: BIMModel, topLabel: String = "Height") -> [ToolOption] {
        let names = planeNames(axis, m)
        var o = [ToolOption(id: "basePlane", label: "Base", kind: .choice(["None"] + names), value: .text(e.basePlane ?? "None")),
                 ToolOption(id: "baseOffset", label: "Offset", kind: .length, value: .double(e.baseOffset)),
                 ToolOption(id: "topPlane", label: topLabel, kind: .choice(["Unconnected"] + names), value: .text(e.topPlane ?? "Unconnected"))]
        if e.topPlane == nil { o.append(ToolOption(id: "height", label: "", kind: .length, value: .double(e.height))) }
        else { o.append(ToolOption(id: "topOffset", label: "Top Offset", kind: .length, value: .double(e.topOffset))) }
        return o
    }

    /// Applies one of the extent options; false when `id` isn't one.
    public static func setExtent(_ e: inout PartExtent, _ id: String, _ v: ParamValue) -> Bool {
        switch id {
        case "basePlane": e.basePlane = v.textValue == "None" ? nil : v.textValue
        case "baseOffset": e.baseOffset = v.doubleValue ?? 0
        case "topPlane": e.topPlane = v.textValue == "Unconnected" ? nil : v.textValue
        case "topOffset": e.topOffset = v.doubleValue ?? 0
        case "height": if let d = v.doubleValue, d > Tolerance.length { e.height = d }
        default: return false
        }
        return true
    }

    /// Parts of `categories` whose plan or view outline is under a point (nearest first), using their boxes.
    public static func parts(at p: Vec2, _ cats: Set<Category>, map: FurnitureSketchMap, tolerance: Double, _ m: BIMModel) -> [Element] {
        var hits: [(Element, Double)] = []
        for c in cats {
            for e in m.elements(c) {
                guard let b = FurniturePartSolids.partBox(e, m)?.box else { continue }
                let r = Rect2(points: b.corners.map(map.project))
                guard r.expanded(by: tolerance).contains(p) else { continue }
                let d = r.contains(p) ? 0 : min(abs(p.x - r.min.x), abs(p.x - r.max.x), abs(p.y - r.min.y), abs(p.y - r.max.y))
                hits.append((e, d + r.width * r.height * 1e-6))
            }
        }
        return hits.sorted { $0.1 < $1.1 }.map(\.0)
    }
}
