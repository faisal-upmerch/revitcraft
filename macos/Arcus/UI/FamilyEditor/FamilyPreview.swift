import SwiftUI
import ArcusGeometry
import ArcusDomain

// W4-FAMED: the family views of the editor. The drawing carries the identity of what it shows so the canvas can select it.

enum FamilyPreviewMode: String, CaseIterable, Identifiable {
    // F1415: RevitCraft's family views: Ref. Level, the four elevations and the default 3D view.
    case plan = "Plan", front = "Front", back = "Back", left = "Left", right = "Right", threeD = "3D"
    var id: String { rawValue }
    /// Name in the browser and canvas title, in the style of project views.
    var viewTitle: String {
        switch self {
        case .plan: "Floor Plan: Ref. Level"
        case .front: "Elevation: Front"
        case .back: "Elevation: Back"
        case .left: "Elevation: Left"
        case .right: "Elevation: Right"
        case .threeD: "3D View: {3D}"
        }
    }
    /// The view tab's short name.
    var tabTitle: String { self == .plan ? "Ref. Level" : self == .threeD ? "{3D}" : rawValue }
    var symbol: String {
        switch self {
        case .plan: "square.split.bottomrightquarter"
        case .front, .back, .left, .right: "rectangle.portrait"
        case .threeD: "cube"
        }
    }
    /// F1415: the view's sketch frame (nil in 3D).
    var frame: FamilyEditing.ViewFrame? {
        switch self {
        case .plan: .plan
        case .front: .front
        case .back: .back
        case .left: .left
        case .right: .right
        case .threeD: nil
        }
    }
    /// The elevation whose frame is `f`.
    static func view(for f: FamilyEditing.ViewFrame) -> FamilyPreviewMode {
        allCases.first { $0.frame == f } ?? .front
    }
    /// Family axis shown horizontally (u) and vertically (v) in this view; nil in 3D where planes aren't drawn.
    var axes: (u: FamilyAxis, v: FamilyAxis)? { frame.map { ($0.plane.axes.u, $0.plane.axes.v) } }
    /// −1 when the view's horizontal axis runs against the family axis (Back, Left).
    var uSign: Double { frame?.uSign ?? 1 }
}

/// F1415: where the Default 3D view looks from (degrees): yaw about Z from +X, pitch above the horizon (negative looks down).
struct FamilyOrbit: Equatable {
    var yaw = 45.0
    var pitch = -35.264
    /// The 3D projection: the view looks along the orbit direction.
    var projection: ViewProjection {
        let y = yaw * .pi / 180, p = pitch * .pi / 180
        let f = Vec3(cos(p) * cos(y), cos(p) * sin(y), sin(p))
        var r = f.cross(.unitZ)
        if r.length < 1e-6 { r = Vec3(sin(y), -cos(y), 0) }
        r = r.normalized
        return ViewProjection(origin: .zero, right: r, up: r.cross(f), near: -1_000, far: 1_000)
    }
}

/// F1415: Draw panel shapes in sketch mode.
enum FamilySketchDraw: String, CaseIterable { case line = "Line", rectangle = "Rectangle" }

/// 2D content of a family view in view coordinates (u right, v up, metres).
struct FamilyPreviewDrawing {
    enum Style { case solid, symbol, swing, void, hiddenByVisibility, reference } // F1415: reference lines
    struct Stroke { var points: [Vec2]; var closed: Bool; var style: Style; var item: FamilyEditing.Item? }
    struct Fill { var polygon: Polygon2; var item: FamilyEditing.Item?; var masking = false }
    /// F1415: a flip control glyph at its plan position.
    struct Control { var position: Vec2; var kind: FamilyControlKind; var item: FamilyEditing.Item? }
    /// A reference plane seen edge-on: a vertical (u = value) or horizontal (v = value) line.
    struct PlaneLine { var vertical: Bool; var value: Double; var name: String; var strong: Bool; var origin: Bool }
    struct Dimension { var id: String; var vertical: Bool; var a: Double; var b: Double; var c: Double?; var text: String; var conflict: Bool; var labeled: Bool }
    struct Label { var position: Vec2; var text: String; var item: FamilyEditing.Item? }

    var fills: [Fill] = []
    var strokes: [Stroke] = []
    var planes: [PlaneLine] = []
    var dimensions: [Dimension] = []
    var labels: [Label] = []
    var controls: [Control] = [] // F1415

    var contentBounds: Rect2 {
        var b = Rect2.empty
        for f in fills { b.include(f.polygon.bounds) }
        for s in strokes { for p in s.points { b.include(p) } }
        for l in labels { b.include(l.position) }
        for c in controls { b.include(c.position) }
        return b
    }

    /// Content plus the planes, for fitting the view.
    var fitBounds: Rect2 {
        var bounds = contentBounds
        for p in planes {
            if p.vertical { bounds.include(Vec2(p.value, bounds.isEmpty ? 0 : bounds.center.y)) } else { bounds.include(Vec2(bounds.isEmpty ? 0 : bounds.center.x, p.value)) }
        }
        return bounds.isEmpty ? Rect2(center: .zero, halfSize: Vec2(0.5, 0.5)) : bounds
    }

    /// Outlines of selectable content for hit-testing.
    var outlines: [(item: FamilyEditing.Item, points: [Vec2], closed: Bool)] {
        var out: [(FamilyEditing.Item, [Vec2], Bool)] = []
        for f in fills { if let i = f.item { out.append((i, f.polygon.points, true)) } }
        for s in strokes { if let i = s.item { out.append((i, s.points, s.closed)) } }
        return out.map { (item: $0.0, points: $0.1, closed: $0.2) }
    }

    static func make(_ ev: EvaluatedFamily, _ family: FamilyDefinition, mode: FamilyPreviewMode, detail: DetailLevel, applyVisibility: Bool,
                     orbit: FamilyOrbit = FamilyOrbit(), fast: Bool = false, formatLength: (Double) -> String) -> FamilyPreviewDrawing {
        var d = FamilyPreviewDrawing()
        let textIDs = Set(family.modelTexts.map(\.id)) // F1415
        /// Selection identity of an evaluated solid: its own form or model text, or the nested instance it came from.
        func item(_ s: EvaluatedFamily.Solid) -> FamilyEditing.Item? {
            if let id = s.sourceID { return textIDs.contains(id) ? .modelText(id) : .solid(id) }
            return nestedItem(s.name)
        }
        func nestedItem(_ name: String) -> FamilyEditing.Item? {
            for inst in family.nestedInstances where name.hasPrefix(inst.familyName + ": ") { return .nested(inst.id) }
            return nil
        }
        /// Whether a project view of this kind and detail level shows the solid.
        func visible(_ s: EvaluatedFamily.Solid) -> Bool {
            guard s.visibleAt.contains(detail) else { return false }
            switch mode {
            case .plan: return s.visibleInPlan
            case .front, .back: return s.visibleInFrontBack
            case .left, .right: return s.visibleInLeftRight
            case .threeD: return s.visibleIn3D
            }
        }
        let solids = ev.solids.filter { !$0.isVoid }
        let voids = ev.solids.filter(\.isVoid)
        switch mode {
        case .plan:
            let allSymbols = ev.planLines + ev.annotationLines
            let symbolLines = allSymbols.filter { !applyVisibility || $0.visibleAt.contains(detail) }
            // A project plan shows symbolic lines when a family has them, otherwise the forms' outlines.
            let showSolids = !applyVisibility || symbolLines.isEmpty
            for s in solids where showSolids {
                if visible(s) {
                    d.fills.append(Fill(polygon: s.profile.outer, item: item(s)))
                    for loop in s.profile.loops { d.strokes.append(Stroke(points: loop.points, closed: true, style: .solid, item: item(s))) }
                } else if !applyVisibility {
                    d.strokes.append(Stroke(points: s.profile.outer.points, closed: true, style: .hiddenByVisibility, item: item(s)))
                }
            }
            if !applyVisibility {
                for v in voids { d.strokes.append(Stroke(points: v.profile.outer.points, closed: true, style: .void, item: item(v))) }
            }
            for f in ev.fills { // F1415: regions are selectable; masking regions draw as masks
                let item = f.sourceID.map { FamilyEditing.Item.fill($0) }
                d.fills.append(Fill(polygon: f.polygon, item: item, masking: f.isMasking))
                d.strokes.append(Stroke(points: f.polygon.points, closed: true, style: f.isMasking ? .hiddenByVisibility : .symbol, item: item))
            }
            for c in ev.controls { d.controls.append(Control(position: c.position, kind: c.kind, item: c.sourceID.map { .control($0) })) }
            for l in allSymbols {
                let on = l.visibleAt.contains(detail)
                guard on || !applyVisibility else { continue }
                let style: Style = !on ? .hiddenByVisibility : (l.subcategory == .swing ? .swing : .symbol)
                d.strokes.append(Stroke(points: l.curve.tessellate(chordTolerance: 0.002), closed: false, style: style, item: l.sourceID.map { .line($0) }))
            }
            for lb in ev.labels {
                d.labels.append(Label(position: lb.position, text: lb.parameterName.map { "〈\($0)〉" } ?? lb.staticText, item: lb.sourceID.map { .label($0) }))
            }
        case .front, .back, .left, .right, .threeD:
            let proj = mode == .threeD ? orbit.projection : projection(mode)
            if fast { // F1415: plain edges while orbiting
                for s in solids where visible(s) { d.strokes += featureEdges(s.displayMesh, proj).map { Stroke(points: $0, closed: false, style: .solid, item: item(s)) } }
            } else {
                var inputs: [HLRInput] = []
                for (i, s) in solids.enumerated() where visible(s) { inputs.append(HLRInput(tag: i, mesh: s.displayMesh)) }
                for e in HiddenLineRenderer.render(inputs, projection: proj) {
                    let src = solids.indices.contains(e.tag) ? item(solids[e.tag]) : nil
                    d.strokes.append(Stroke(points: [e.segment.start, e.segment.end], closed: false, style: .solid, item: src))
                }
            }
            if !applyVisibility {
                for s in solids where !visible(s) {
                    d.strokes += featureEdges(s.displayMesh, proj).map { Stroke(points: $0, closed: false, style: .hiddenByVisibility, item: item(s)) }
                }
                for v in voids { d.strokes += featureEdges(v.displayMesh, proj).map { Stroke(points: $0, closed: false, style: .void, item: item(v)) } }
            }
        }
        // F1415: model lines (black) and reference lines (green) on their work planes, in every view.
        let proj = mode == .plan ? nil : (mode == .threeD ? orbit.projection : projection(mode))
        for l in ev.modelLines where !applyVisibility || l.isReference || l.visibleAt.contains(detail) {
            let a = proj.map { $0.project(l.start).uv } ?? l.start.xy, b = proj.map { $0.project(l.end).uv } ?? l.end.xy
            d.strokes.append(Stroke(points: [a, b], closed: false, style: l.isReference ? .reference : .symbol, item: l.sourceID.map { .modelLine($0) }))
        }
        if d.contentBounds.isEmpty {
            d.strokes.append(Stroke(points: [Vec2(-0.05, 0), Vec2(0.05, 0)], closed: false, style: .symbol, item: nil))
            d.strokes.append(Stroke(points: [Vec2(0, -0.05), Vec2(0, 0.05)], closed: false, style: .symbol, item: nil))
        }

        // Reference planes and dimensions that are seen edge-on in this view.
        func orientation(_ axis: FamilyAxis) -> Bool? {
            guard let axes = mode.axes else { return nil }
            if axis == axes.u { return true }
            if axis == axes.v { return false }
            return nil
        }
        let sign = mode.uSign // F1415: Back and Left run their horizontal axis the other way
        for p in family.referencePlanes {
            guard let vertical = orientation(p.axis), let v = ev.planes[p.name] else { continue }
            d.planes.append(PlaneLine(vertical: vertical, value: vertical ? v * sign : v, name: p.name, strong: p.strength != .weak && p.strength != .notAReference, origin: p.definesOrigin))
        }
        let axisOf = Dictionary(family.referencePlanes.map { ($0.name, $0.axis) }, uniquingKeysWith: { a, _ in a })
        for dim in family.dimensions {
            guard let axis = axisOf[dim.planeA], let vertical = orientation(axis), let a0 = ev.planes[dim.planeA], let b0 = ev.planes[dim.planeB] else { continue }
            let k = vertical ? sign : 1
            let a = a0 * k, b = b0 * k
            let c = dim.isEquality ? dim.planeC.flatMap { ev.planes[$0] }.map { $0 * k } : nil
            let value = formatLength(abs(b - a))
            let text: String
            if dim.isEquality { text = "EQ" } else if let l = dim.labelParameter { text = "\(l) = \(value)" } else { text = dim.isLocked ? "🔒 \(value)" : value }
            d.dimensions.append(Dimension(id: dim.id, vertical: vertical, a: a, b: b, c: c, text: text, conflict: ev.conflictingDimensions.contains(dim.id),
                                          labeled: dim.labelParameter != nil))
        }
        return d
    }

    static func projection(_ mode: FamilyPreviewMode) -> ViewProjection {
        switch mode {
        case .front: ViewProjection.elevation(lookingAt: Vec2(0, 1), origin: .zero, near: -1_000, far: 1_000)
        case .back: ViewProjection.elevation(lookingAt: Vec2(0, -1), origin: .zero, near: -1_000, far: 1_000) // F1415
        case .left: ViewProjection.elevation(lookingAt: Vec2(1, 0), origin: .zero, near: -1_000, far: 1_000)
        case .right: ViewProjection.elevation(lookingAt: Vec2(-1, 0), origin: .zero, near: -1_000, far: 1_000)
        default: ViewProjection(origin: .zero, right: Vec3(1, -1, 0), up: Vec3(1, 1, 2), near: -1_000, far: 1_000)
        }
    }

    /// Feature edges of a mesh projected without hidden-line removal (for voids).
    static func featureEdges(_ m: Mesh, _ proj: ViewProjection) -> [[Vec2]] {
        stride(from: 0, to: m.featureEdges.count - 1, by: 2).map { i in
            [proj.project(m.positions[Int(m.featureEdges[i])]).uv, proj.project(m.positions[Int(m.featureEdges[i + 1])]).uv]
        }
    }
}
