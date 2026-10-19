import Foundation
import ArcusGeometry
import ArcusDomain

// FM6: Fabricate ▸ Joint (JT), which works as Modify ▸ Geometry ▸ Wall Joins: while the tool runs, every joint shows a
// marker (circles for joints the rules make, squares for joints you set) in plans, elevations and sections, and in 3D.
// Hover highlights the two parts; click picks the joint (click the same spot again for the next joint stacked
// behind it). The Options Bar then shows the joint's type, which part runs through (at corners), Previous and Next
// (each type with each part running through), its sizes, By Rule and Disallow Join. Esc drops the joint, then the tool.

/// A marker a tool draws on the model in 3D views (world position).
public struct ToolWorldMarker: Sendable {
    public var position: Vec3
    /// 0 plain, 1 hovered, 2 picked.
    public var emphasis: Int
    /// Square (set by the user) or round (by rule).
    public var square: Bool
}

/// Tools that draw markers on the model in 3D views (the 3D overlay asks for them).
@MainActor public protocol ToolWorldMarkers: AnyObject {
    var worldMarkers: [ToolWorldMarker] { get }
}

@MainActor
public final class FurnitureJointTool: BaseTool, InteractiveTool, ToolWorldMarkers {
    public let commandID: CommandID = .furnitureJoint
    public var title: String { "Joint" }
    let map: FurnitureSketchMap?
    /// Driven from a 3D view (on its work plane's plan context): picks by the surface under the pointer.
    let in3D: Bool
    public private(set) var hovered: JointKey?
    public private(set) var picked: JointKey?

    public init(ctx: ToolContext, in3D: Bool = false) {
        map = FurnitureSketchMap.of(ctx.viewData)
        self.in3D = in3D
        super.init(ctx: ctx)
        rebuild()
    }

    var joints: [FurnitureJoint] { FurnitureJoints.joints(ctx.model) }
    var pickedJoint: FurnitureJoint? { picked.flatMap { k in joints.first { $0.key == k } } }

    public var prompt: String {
        if joints.isEmpty { return "There are no joints: parts join where they touch or overlap." }
        return picked == nil ? "Click a joint marker." : "Set the joint in the Options Bar, or click another marker. Esc to finish."
    }

    func mark(_ id: ElementID) -> String {
        guard let e = ctx.model[id] else { return "" }
        return e.mark.isEmpty ? "\(e.category.singularName) \(id.raw)" : e.mark
    }

    // MARK: Picking

    /// Depth toward the viewer (smaller is nearer).
    func depth(_ p: Vec3) -> Double {
        guard let map else { return 0 }
        return map.plane == .xy ? -p.z : (p.xy - map.origin).dot(map.forward)
    }

    /// Joints under the pointer, nearest the viewer first.
    func candidates(_ i: ToolInput) -> [FurnitureJoint] {
        if in3D, let sp = i.surfacePoint {
            let tol = max(ctx.pixel * 14, 0.02)
            let near = joints.filter { j in
                let d = j.marker.distance(to: sp)
                let onHit = i.hit.map { j.key.a == $0 || j.key.b == $0 } ?? false
                return d <= tol || (onHit && d <= tol * 3)
            }
            return near.sorted { $0.marker.distance(to: sp) < $1.marker.distance(to: sp) }
        }
        guard let map, !in3D else { return [] }
        let tol = ctx.pixel * 8
        return joints.filter { map.project($0.marker).distance(to: i.rawPoint) <= tol }
            .sorted { a, b in
                let da = map.project(a.marker).distance(to: i.rawPoint), db = map.project(b.marker).distance(to: i.rawPoint)
                return abs(da - db) > ctx.pixel ? da < db : depth(a.marker) < depth(b.marker)
            }
    }

    public func pointerMoved(_ i: ToolInput) {
        hovered = candidates(i).first?.key
        rebuild()
    }

    public func pointerDown(_ i: ToolInput) {
        let c = candidates(i)
        guard !c.isEmpty else {
            picked = nil
            ctx.session.selection.clear()
            rebuild()
            return
        }
        // Clicking the picked joint again picks the next one stacked behind it.
        if let p = picked, let k = c.firstIndex(where: { $0.key == p }) { picked = c[(k + 1) % c.count].key } else { picked = c[0].key }
        selectElement()
        rebuild()
    }

    /// Properties show the user's joint element when the picked joint has one.
    func selectElement() {
        if let id = pickedJoint?.elementID { ctx.session.selection.select([id]) } else { ctx.session.selection.clear() }
    }

    public func escape() -> EscapeResult {
        if picked != nil { picked = nil; ctx.session.selection.clear(); rebuild(); return .stayInTool }
        return .exitTool
    }

    // MARK: Options Bar

    public var options: [ToolOption] {
        guard let j = pickedJoint else { return [] }
        let types = JointType.allCases.filter { $0 != .miter || j.isCorner }.map(\.rawValue)
        var o = [ToolOption(id: "type", label: "Joint", kind: .choice(types), value: .text(j.type.rawValue))]
        if j.isCorner && j.type != .miter {
            o.append(ToolOption(id: "through", label: "Runs Through", kind: .choice([mark(j.key.a), mark(j.key.b)]), value: .text(mark(j.throughID))))
        }
        o.append(ToolOption(id: "previous", label: "Previous", kind: .button, value: .bool(false)))
        o.append(ToolOption(id: "next", label: "Next", kind: .button, value: .bool(false)))
        for k in j.type.parameterKeys {
            let v = j.parameters.value(k)
            let kind: ToolOption.Kind = k.isCount ? .integer : k.isAngle ? .angle : .length
            o.append(ToolOption(id: "param.\(k.rawValue)", label: k.label(for: j.type), kind: kind, value: k.isCount ? .int(Int(v ?? 0)) : .double(v ?? 0)))
        }
        if j.isUserSet { o.append(ToolOption(id: "byRule", label: "By Rule", kind: .button, value: .bool(false))) }
        o.append(ToolOption(id: "disallow", label: "Disallow Join", kind: .button, value: .bool(false)))
        return o
    }

    public func setOption(_ id: String, _ value: ParamValue) {
        guard let j = pickedJoint else { return }
        let key = j.key
        switch id {
        case "type":
            guard let t = JointType(rawValue: value.textValue ?? "") else { return }
            ctx.session.perform("Joint Type") { tx in try FurnitureJointOperations.set(key, type: t, in: tx) }
        case "through":
            let t = value.textValue == mark(key.a) ? key.a : key.b
            ctx.session.perform("Runs Through") { tx in try FurnitureJointOperations.set(key, through: t, in: tx) }
        case "previous", "next":
            let step = id == "next" ? 1 : -1
            ctx.session.perform(id == "next" ? "Next Joint" : "Previous Joint") { tx in try FurnitureJointOperations.cycle(key, by: step, in: tx) }
        case "byRule":
            ctx.session.perform("Joint By Rule") { tx in FurnitureJointOperations.reset(key, in: tx) }
        case "disallow":
            ctx.session.perform("Disallow Join") { tx in try FurnitureJointOperations.disallow(key, in: tx) }
            picked = nil
        default:
            guard id.hasPrefix("param."), let k = JointParameterKey(rawValue: String(id.dropFirst(6))) else { return }
            let v: Double? = k.isCount ? Double(value.intValue ?? 0) : value.doubleValue
            if let v, v < 0 { message("\(k.rawValue) can't be negative."); return }
            ctx.session.perform(k.label(for: j.type)) { tx in try FurnitureJointOperations.set(key, k, v, in: tx) }
        }
        if let e = ctx.session.lastError { message(e.message) }
        selectElement()
        rebuild()
    }

    /// Space: the next configuration, as Next.
    public func spaceBar() { setOption("next", .bool(true)) }

    // MARK: Markers

    public var worldMarkers: [ToolWorldMarker] {
        joints.map { ToolWorldMarker(position: $0.marker, emphasis: $0.key == picked ? 2 : $0.key == hovered ? 1 : 0, square: $0.isUserSet) }
    }

    func rebuild() {
        preview = ToolPreview()
        preview.cursor = .pick
        let all = joints
        if let k = hovered ?? picked, let j = all.first(where: { $0.key == k }) { preview.highlight = [j.throughID, j.otherID] }
        if let k = picked, let j = all.first(where: { $0.key == k }) { preview.highlight.formUnion([j.throughID, j.otherID]) }
        guard let map, !in3D else { return }
        let r = ctx.pixel * 4.5
        let plain = GStroke(weight: 1, color: RGBColor(0.18, 0.43, 0.66))
        let strong = GStroke(weight: 2, color: RGBColor(0.10, 0.36, 0.80))
        // Draw the far ones first, so nearer markers sit on top.
        for j in all.sorted(by: { depth($0.marker) > depth($1.marker) }) {
            let c = map.project(j.marker)
            let isPicked = j.key == picked, isHovered = j.key == hovered
            let rr = isPicked || isHovered ? r * 1.4 : r
            let st = isPicked || isHovered ? strong : plain
            let outline: Polygon2 = j.isUserSet ? .rectangle(Rect2(center: c, halfSize: Vec2(rr, rr)))
                                                : Polygon2(Arc2(center: c, radius: rr, startAngle: 0, sweep: 2 * .pi).tessellate(chordTolerance: rr * 0.05).dropLast())
            preview.primitives.append(.fill([outline], GFill(pattern: .solid, color: isPicked ? strong.color : RGBColor(1, 1, 1))))
            preview.primitives.append(.polyline(outline.points, closed: true, st))
        }
    }
}
