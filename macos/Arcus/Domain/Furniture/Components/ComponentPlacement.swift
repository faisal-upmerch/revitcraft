import Foundation
import ArcusGeometry

// COMP: placing components on hosts, Revit-style (face-based families). An instance is an ordinary component element
// (`.component`) in the Furniture Hardware category, hosted by the part, front or bay it's on (`hostID`, so it goes
// when its host is deleted). Its instance parameters say where it is on the host: the face, the alignment
// (Center, Left, Right, Top, Bottom, the corners, Inside/Outside, Full Length) and the offsets from the aligned edge,
// a rotation on the face and whether it follows the host. Regeneration puts it back on the face whenever the host
// moves, resizes or flexes, so a handle 2 1/2" from the top of a door stays 2 1/2" from the top.

/// Instance parameter ids of placed components.
public enum ComponentInstanceKeys {
    public static let face = ParameterID("comp.face")
    public static let alignment = ParameterID("comp.align")
    public static let offsetX = ParameterID("comp.offsetX")
    public static let offsetY = ParameterID("comp.offsetY")
    public static let offsetZ = ParameterID("comp.offsetZ")
    public static let rotation = ParameterID("comp.rotation")
    public static let vertical = ParameterID("comp.vertical")
    public static let follows = ParameterID("comp.follows")
    /// Instances placed together (hinge sets, slide pairs): a shared group id, the index and the count (0 = by rule).
    public static let group = ParameterID("comp.group")
    public static let index = ParameterID("comp.index")
    public static let count = ParameterID("comp.count")
}

/// Where an instance is on its host.
public struct ComponentSettings: Hashable, Sendable {
    public var face: ComponentFace
    public var alignment: ComponentAlignment
    /// From the aligned edge (Left/Right…) or from the centre (Center) along the face's X and Y.
    public var offsetX: Double
    public var offsetY: Double
    /// Out of the face.
    public var offsetZ: Double
    /// Turned on the face (radians).
    public var rotation: Double
    public var vertical: Bool
    /// Moves with the host (Constraints ▸ Follow Host); off keeps it where it is.
    public var followsHost: Bool
    public init(face: ComponentFace, alignment: ComponentAlignment, offsetX: Double = 0, offsetY: Double = 0, offsetZ: Double = 0, rotation: Double = 0,
                vertical: Bool = false, followsHost: Bool = true) {
        self.face = face; self.alignment = alignment; self.offsetX = offsetX; self.offsetY = offsetY; self.offsetZ = offsetZ
        self.rotation = rotation; self.vertical = vertical; self.followsHost = followsHost
    }

    /// The rule's defaults.
    public init(_ rule: ComponentPlacementRule, face: ComponentFace? = nil) {
        self.init(face: face ?? rule.faces.first ?? .front, alignment: rule.alignment, offsetX: rule.offsetX, offsetY: rule.offsetY, offsetZ: rule.offsetZ,
                  vertical: rule.vertical)
    }

    public init?(_ e: Element) {
        guard let f = e.params[ComponentInstanceKeys.face]?.textValue.flatMap(ComponentFace.init(rawValue:)) else { return nil }
        let K = ComponentInstanceKeys.self
        self.init(face: f, alignment: e.params[K.alignment]?.textValue.flatMap(ComponentAlignment.init(rawValue:)) ?? .center,
                  offsetX: e.params[K.offsetX]?.doubleValue ?? 0, offsetY: e.params[K.offsetY]?.doubleValue ?? 0, offsetZ: e.params[K.offsetZ]?.doubleValue ?? 0,
                  rotation: e.params[K.rotation]?.doubleValue ?? 0, vertical: e.params[K.vertical]?.boolValue ?? false,
                  followsHost: e.params[K.follows]?.boolValue ?? true)
    }

    public func write(_ e: inout Element) {
        let K = ComponentInstanceKeys.self
        e.params[K.face] = .text(face.rawValue)
        e.params[K.alignment] = .text(alignment.rawValue)
        e.params[K.offsetX] = .double(offsetX)
        e.params[K.offsetY] = .double(offsetY)
        e.params[K.offsetZ] = .double(offsetZ)
        e.params[K.rotation] = .double(rotation)
        e.params[K.vertical] = .bool(vertical)
        e.params[K.follows] = .bool(followsHost)
    }
}

/// A face of a host in the model: centre, axes (u along, v up, n out of the material) and size.
public struct ComponentHostFace: Hashable, Sendable {
    public var hostID: ElementID
    public var face: ComponentFace
    public var origin: Vec3
    public var u: Vec3
    public var v: Vec3
    public var n: Vec3
    public var width: Double
    public var height: Double
    /// The host's size through the face (part or front thickness; bay: the opening's size across).
    public var thickness: Double
    /// Fronts: the hinge edge seen on this face (left/right in u), for Inside/Outside.
    public var hingeOnLeft: Bool?

    /// The model point at face coordinates (a, b), lifted `c` out of the face.
    public func point(_ a: Double, _ b: Double, _ c: Double = 0) -> Vec3 { origin + u * a + v * b + n * c }
    /// Face coordinates (a, b) of a model point (projected on the face).
    public func local(_ p: Vec3) -> Vec2 { let d = p - origin; return Vec2(d.dot(u), d.dot(v)) }
    public func contains(_ a: Double, _ b: Double, margin: Double = 1e-6) -> Bool { abs(a) <= width / 2 + margin && abs(b) <= height / 2 + margin }
}

public enum ComponentPlacement {
    // MARK: Hosts

    /// What kind of host an element is (nil = it can't host components).
    public static func hostKind(_ e: Element, _ m: BIMModel) -> ComponentHostKind? {
        switch e.data {
        case .furnitureFront(let f):
            switch f.kind {
            case .door: return .door
            case .drawer: return .drawerFront
            case .flap: return m[e.hostID]?.furnitureBay?.face == .top ? .lid : .flap
            }
        case .furnitureBay: return .bay
        case .furniturePanel(let p):
            switch p.role {
            case .back: return .back
            case .divider: return .divider
            case .plinth: return .plinth
            default: return .sidePanel
            }
        case .furnitureShelf(let s):
            switch s.role {
            case .top: return .top
            case .bottom: return .bottom
            default: return .shelf
            }
        case .furnitureLeg: return .leg
        case .furnitureRail: return .rail
        case .furnitureForm: return .form
        case .wall: return .wall
        case .level: return .floor
        default: return nil
        }
    }

    /// Whether a host kind takes a definition.
    public static func accepts(_ d: ComponentDefinition, _ kind: ComponentHostKind) -> Bool {
        let hosts = d.placement.hosts
        if hosts.contains(kind) { return true }
        if hosts.contains(.anyPart), ![.bay, .floor, .wall].contains(kind) { return true }
        if kind == .lid, hosts.contains(.flap) { return true }
        if kind == .drawerFront, hosts.contains(.drawerBox) { return true }
        return false
    }

    /// The box a host spans, in its bay frame (fronts and bays) or the model (parts).
    struct HostBox {
        var lo: Vec3, hi: Vec3, frame: BayFrame
        var isOpening: Bool
        var hingeOnLeft: Bool?
    }

    static func box(_ e: Element, _ m: BIMModel) -> HostBox? {
        switch e.data {
        case .furnitureFront:
            guard let g = FurnitureFronts.geometry(e, m), !g.leaves.isEmpty else { return nil }
            var lo = Vec3(.infinity, .infinity, .infinity), hi = Vec3(-.infinity, -.infinity, -.infinity)
            for l in g.leaves {
                let us = [l.u.0.value, l.u.1.value], vs = [l.v.0.value, l.v.1.value], ws = [l.w.0.value, l.w.1.value]
                let (ys, zs) = g.face == .front ? (ws, vs) : (vs, ws)
                lo = Vec3(min(lo.x, us.min()!), min(lo.y, ys.min()!), min(lo.z, zs.min()!))
                hi = Vec3(max(hi.x, us.max()!), max(hi.y, ys.max()!), max(hi.z, zs.max()!))
            }
            let hinge = g.leaves.first?.hinge
            return HostBox(lo: lo, hi: hi, frame: g.frame, isOpening: false, hingeOnLeft: hinge == .left ? true : (hinge == .right ? false : nil))
        case .furnitureBay(let b):
            guard let o = b.opening else { return nil }
            return HostBox(lo: Vec3(o.x0, o.y0, o.z0), hi: Vec3(o.x1, o.y1, o.z1), frame: BayFrame(b), isOpening: true, hingeOnLeft: nil)
        default:
            let bb = ElementMeshes.bounds(e, m)
            guard bb.min.x <= bb.max.x, (bb.max - bb.min).length > Tolerance.length else { return nil }
            return HostBox(lo: bb.min, hi: bb.max, frame: .front, isOpening: false, hingeOnLeft: nil)
        }
    }

    /// The faces of a host (solid hosts: outside faces; bays: the opening's inside faces).
    public static func faces(_ e: Element, _ m: BIMModel) -> [ComponentHostFace] {
        guard let b = box(e, m) else { return [] }
        let c = (b.lo + b.hi) * 0.5, d = b.hi - b.lo
        let X = Vec3.unitX, Y = Vec3(0, 1, 0), Z = Vec3.unitZ
        var out: [(ComponentFace, Vec3, Vec3, Vec3, Vec3, Double, Double, Double)] = []
        if b.isOpening {
            out = [(.left, Vec3(b.lo.x, c.y, c.z), Y, Z, X, d.y, d.z, d.x), (.right, Vec3(b.hi.x, c.y, c.z), -Y, Z, -X, d.y, d.z, d.x),
                   (.bottom, Vec3(c.x, c.y, b.lo.z), X, Y, Z, d.x, d.y, d.z), (.top, Vec3(c.x, c.y, b.hi.z), X, -Y, -Z, d.x, d.y, d.z),
                   (.back, Vec3(c.x, b.hi.y, c.z), X, Z, -Y, d.x, d.z, d.y), (.front, Vec3(c.x, b.lo.y, c.z), -X, Z, Y, d.x, d.z, d.y)]
        } else {
            out = [(.front, Vec3(c.x, b.lo.y, c.z), X, Z, -Y, d.x, d.z, d.y), (.back, Vec3(c.x, b.hi.y, c.z), -X, Z, Y, d.x, d.z, d.y),
                   (.left, Vec3(b.lo.x, c.y, c.z), -Y, Z, -X, d.y, d.z, d.x), (.right, Vec3(b.hi.x, c.y, c.z), Y, Z, X, d.y, d.z, d.x),
                   (.top, Vec3(c.x, c.y, b.hi.z), X, Y, Z, d.x, d.y, d.z), (.bottom, Vec3(c.x, c.y, b.lo.z), X, -Y, -Z, d.x, d.y, d.z)]
        }
        // A drawer's box: its inside faces (the box is derived from the bay and the slides, not an element).
        if e.furnitureFront?.kind == .drawer, let db = FurnitureFronts.drawerBox(e, m) {
            let lo = Vec3(db.x0 + db.side, db.y0 + db.back, db.z0 + db.bottom), hi = Vec3(db.x0 + db.width - db.side, db.y0 + db.depth - db.back, db.z0 + db.height)
            let c2 = (lo + hi) * 0.5, d2 = hi - lo
            out += [(.boxBottom, Vec3(c2.x, c2.y, lo.z), X, Y, Z, d2.x, d2.y, d2.z), (.boxLeft, Vec3(lo.x, c2.y, c2.z), Y, Z, X, d2.y, d2.z, d2.x),
                    (.boxRight, Vec3(hi.x, c2.y, c2.z), -Y, Z, -X, d2.y, d2.z, d2.x), (.boxBack, Vec3(c2.x, hi.y, c2.z), X, Z, -Y, d2.x, d2.z, d2.y),
                    (.boxFront, Vec3(c2.x, lo.y, c2.z), -X, Z, Y, d2.x, d2.z, d2.y)]
        }
        let fr = b.frame
        return out.map { f in
            ComponentHostFace(hostID: e.id, face: f.0, origin: fr.world(f.1), u: fr.world(f.2), v: fr.world(f.3), n: fr.world(f.4),
                              width: f.5, height: f.6, thickness: f.7,
                              hingeOnLeft: f.0 == .front ? b.hingeOnLeft : (f.0 == .back ? b.hingeOnLeft.map { !$0 } : nil))
        }
    }

    /// The piece's centre (between its framing planes; the origin when it has none).
    static func pieceCenter(_ m: BIMModel) -> Vec3 {
        let p = FurniturePlanes.positionsByName(m)
        let x = ((p["Left"] ?? 0) + (p["Right"] ?? 0)) / 2, y = ((p["Front"] ?? 0) + (p["Back"] ?? 0)) / 2
        let z = ((p["Bottom"] ?? p["Ref. Level"] ?? 0) + (p["Top"] ?? 0.8)) / 2
        return Vec3(x, y, z)
    }

    /// A host face by name; Inside/Outside and the edges resolve to the actual face (Any: the front, or a bay's bottom).
    public static func face(_ e: Element, _ which: ComponentFace, _ m: BIMModel) -> ComponentHostFace? {
        let all = faces(e, m)
        guard !all.isEmpty else { return nil }
        let isBay = e.furnitureBay != nil
        func named(_ f: ComponentFace) -> ComponentHostFace? { all.first { $0.face == f } }
        switch which {
        case .front, .back, .left, .right, .top, .bottom, .boxBottom, .boxLeft, .boxRight, .boxBack, .boxFront: return named(which)
        case .topEdge: return named(.top)
        case .bottomEdge: return named(.bottom)
        case .leftEdge: return named(.left)
        case .rightEdge: return named(.right)
        case .frontEdge: return named(.front)
        case .any: return named(isBay ? .bottom : .front)
        case .inside, .outside:
            if isBay { return named(which == .inside ? .bottom : .top) }
            if e.furnitureFront != nil {
                let lid = m[e.hostID]?.furnitureBay?.face == .top
                return named(which == .inside ? (lid ? .bottom : .back) : (lid ? .top : .front))
            }
            // The two broad faces (across the thinnest direction); Inside faces the piece's centre.
            guard let thin = all.min(by: { $0.thickness < $1.thickness }) else { return nil }
            let pair = all.filter { abs($0.n.dot(thin.n)) > 0.99 }
            let c = pieceCenter(m)
            let inward = pair.max { (c - $0.origin).dot($0.n) < (c - $1.origin).dot($1.n) }
            let outward = pair.first { $0.face != inward?.face }
            return which == .inside ? inward : outward
        }
    }

    /// The face of a host nearest a model point (for picking a face with the pointer).
    public static func nearestFace(_ e: Element, to p: Vec3, _ m: BIMModel, among allowed: [ComponentFace] = []) -> ComponentHostFace? {
        let resolved = allowed.isEmpty || allowed.contains(.any) ? faces(e, m) : allowed.compactMap { face(e, $0, m) }
        return resolved.min { abs(($0.origin - p).dot($0.n)) + outside($0, p) < abs(($1.origin - p).dot($1.n)) + outside($1, p) }
    }
    static func outside(_ f: ComponentHostFace, _ p: Vec3) -> Double {
        let l = f.local(p)
        return max(0, abs(l.x) - f.width / 2) + max(0, abs(l.y) - f.height / 2)
    }

    // MARK: Mount points

    /// The anchor (a, b) on a face for an alignment and offsets.
    public static func anchor(_ f: ComponentHostFace, _ s: ComponentSettings) -> Vec2 {
        let hw = f.width / 2, hh = f.height / 2
        var a = s.offsetX, b = s.offsetY
        var align = s.alignment
        if align == .inside || align == .outside {
            let hingeLeft = f.hingeOnLeft ?? true
            align = (align == .inside) == hingeLeft ? .left : .right
        }
        switch align {
        case .left, .topLeft, .bottomLeft: a = -hw + s.offsetX
        case .right, .topRight, .bottomRight: a = hw - s.offsetX
        default: break
        }
        switch align {
        case .top, .topLeft, .topRight: b = hh - s.offsetY
        case .bottom, .bottomLeft, .bottomRight: b = -hh + s.offsetY
        default: break
        }
        return Vec2(a, b)
    }

    /// The settings that put an instance at face point (a, b) keeping the alignment (offsets measured from it).
    public static func settings(_ base: ComponentSettings, at p: Vec2, on f: ComponentHostFace) -> ComponentSettings {
        var s = base
        s.offsetX = 0; s.offsetY = 0
        let zero = anchor(f, s)
        let dx = p.x - zero.x, dy = p.y - zero.y
        var align = s.alignment
        if align == .inside || align == .outside { align = (align == .inside) == (f.hingeOnLeft ?? true) ? .left : .right }
        switch align {
        case .right, .topRight, .bottomRight: s.offsetX = -dx
        default: s.offsetX = dx
        }
        switch align {
        case .top, .topLeft, .topRight: s.offsetY = -dy
        default: s.offsetY = dy
        }
        return s
    }

    /// The component data and instance values for a definition at face point (a, b).
    public static func data(_ d: ComponentDefinition, on f: ComponentHostFace, at p: Vec2, _ s: ComponentSettings, mirrored: Bool = false,
                            _ m: BIMModel, levelZ: Double) -> (ComponentData, [String: ParamValue]) {
        let o = f.point(p.x, p.y, s.offsetZ)
        var values: [String: ParamValue] = [:]
        for name in ["Host Thickness", "Front Thickness"] where d.parameter(named: name)?.isInstance == true || d.family.parameter(named: name)?.isInstance == true {
            values[name] = .double(f.thickness)
        }
        if s.alignment == .full, let l = d.parameter(named: "Length"), l.isInstance {
            values["Length"] = .double(max(Tolerance.length * 10, f.width - 2 * s.offsetX))
        }
        let rot = s.rotation + (s.vertical && d.frame == .face ? .pi / 2 : 0)
        switch d.frame {
        case .face:
            var c = ComponentData(location: .zero, rotation: rot, offset: 0, mirrored: mirrored)
            c.sketchPlane = WorkPlaneHost(frame: WorkPlaneFrame(origin: o, u: f.u, v: f.v))
            return (c, values)
        case .legacyFront:
            values["Vertical"] = .bool(s.vertical)
            if abs(f.n.z) > 0.9 {
                values["On Lid"] = .bool(true)
                return (ComponentData(location: o.xy, rotation: s.rotation + atan2(f.u.y, f.u.x), offset: o.z - levelZ, mirrored: mirrored), values)
            }
            values["On Lid"] = .bool(false)
            return (ComponentData(location: o.xy, rotation: atan2(f.n.x, -f.n.y) + s.rotation, offset: o.z - levelZ, mirrored: mirrored), values)
        case .legacyOpening:
            // Slide pairs: the origin at the opening's bottom-left-front corner, across the opening.
            if let bay = m[f.hostID]?.furnitureBay, let op = bay.opening {
                let fr = BayFrame(bay)
                values["Opening Width"] = .double(op.width)
                if d.family.parameter(named: "Opening Depth") != nil { values["Opening Depth"] = .double(op.y1 - op.y0) }
                if d.family.parameter(named: "Opening Height") != nil { values["Opening Height"] = .double(op.z1 - op.z0) }
                let corner = fr.world(Vec3(op.x0, op.y0, op.z0))
                return (ComponentData(location: corner.xy, rotation: fr.angle, offset: corner.z - levelZ + s.offsetY, mirrored: false), values)
            }
            return (ComponentData(location: o.xy, rotation: s.rotation, offset: o.z - levelZ), values)
        case .plan, .legacyHinge:
            let r: Double = abs(f.n.z) > 0.9 ? atan2(f.u.y, f.u.x) : atan2(f.n.y, f.n.x)
            return (ComponentData(location: o.xy, rotation: r + s.rotation, offset: o.z - levelZ, mirrored: mirrored), values)
        }
    }

    // MARK: Sets (hinges, pairs)

    /// The (face, point, mirrored) of every instance a placement makes: one, a hinge set along the edge by the count
    /// rule, or a mirrored pair on the opposite face.
    public static func layout(_ d: ComponentDefinition, host: Element, _ s: ComponentSettings, at p: Vec2?, count fixed: Int? = nil, _ m: BIMModel)
        -> [(face: ComponentHostFace, point: Vec2, mirrored: Bool)] {
        guard let f = face(host, s.face, m) else { return [] }
        let a = p ?? anchor(f, s)
        if let rule = ComponentRules.countRule(d, m), d.frame != .legacyOpening {
            let n = max(1, fixed ?? rule.count(forEdge: f.height))
            let inset = min(rule.inset, f.height / 4)
            let lo = -f.height / 2 + inset, hi = f.height / 2 - inset
            return (0..<n).map { k in (f, Vec2(a.x, n == 1 ? 0 : lo + (hi - lo) * Double(k) / Double(n - 1)), false) }
        }
        if d.placement.mirroredPair, d.frame != .legacyOpening {
            let opposite: ComponentFace? = switch f.face {
            case .left: .right
            case .right: .left
            case .top: .bottom
            case .bottom: .top
            case .front: .back
            case .back: .front
            default: nil
            }
            if let o = opposite, let g = face(host, o, m) {
                return [(f, a, false), (g, Vec2(-a.x, a.y), true)]
            }
        }
        return [(f, a, false)]
    }

    // MARK: Operations

    /// Places a component on a host (or on the level when `hostID` is nil): loads it, makes its instance(s) and returns
    /// their ids. `at` is a face point (nil = the alignment's anchor).
    @discardableResult
    public static func place(_ d: ComponentDefinition, typeName: String? = nil, hostID: ElementID?, settings: ComponentSettings? = nil, at p: Vec2? = nil,
                             levelPoint: Vec3? = nil, values extra: [String: ParamValue] = [:], in tx: TransactionContext) throws(TransactionError) -> [ElementID] {
        guard let tid = ComponentDocument.load(d, typeName: typeName, in: tx) else { throw TransactionError("\(d.name) has no types.") }
        let level = tx.model.levels.first?.id
        let levelZ = tx.model.elevation(ofLevel: level)
        guard let hostID else {
            let q = levelPoint ?? .zero
            let id = tx.create(.furnitureHardware, data: .component(ComponentData(location: q.xy, offset: q.z - levelZ)), typeID: tid, levelID: level) { e in
                e.params[ComponentKit.definitionParam] = .text(d.id)
                for (k, v) in extra { e.params[Parameters.familyParamID(k)] = v }
            }
            return [id]
        }
        guard let host = tx.model[hostID], let kind = hostKind(host, tx.model) else { throw TransactionError("Pick a part, front or bay to put \(d.name) on.") }
        guard accepts(d, kind) else {
            throw TransactionError("\(d.name) doesn't go on a \(kind.rawValue.lowercased()).", elements: [hostID],
                                   resolution: "It goes on: \(d.placement.hosts.map(\.rawValue).joined(separator: ", ")).")
        }
        let s = settings ?? ComponentSettings(d.placement)
        let spots = layout(d, host: host, s, at: p, tx.model)
        guard !spots.isEmpty else { throw TransactionError("\(host.category.singularName) has no \(s.face.rawValue.lowercased()) face to place on.", elements: [hostID]) }
        let group = spots.count > 1 ? UUID().uuidString : nil
        var ids: [ElementID] = []
        for (k, spot) in spots.enumerated() {
            var ss = Self.settings(s, at: spot.point, on: spot.face)
            ss.face = spot.face.face
            let (data, values) = Self.data(d, on: spot.face, at: spot.point, ss, mirrored: spot.mirrored, tx.model, levelZ: levelZ)
            let id = tx.create(.furnitureHardware, data: .component(data), typeID: tid, levelID: host.levelID ?? level, hostID: hostID) { e in
                e.params[ComponentKit.definitionParam] = .text(d.id)
                ss.write(&e)
                if let group {
                    e.params[ComponentInstanceKeys.group] = .text(group)
                    e.params[ComponentInstanceKeys.index] = .int(k)
                    e.params[ComponentInstanceKeys.count] = .int(0)
                }
                for (key, v) in values.merging(extra, uniquingKeysWith: { _, b in b }) { e.params[Parameters.familyParamID(key)] = v }
            }
            ids.append(id)
        }
        return ids
    }

    /// Puts placed instances back on their host faces (the host moved, resized or flexed, or its settings changed);
    /// hinge sets gain or lose hinges by the count rule. Called from Furniture regeneration.
    public static func regenerate(_ tx: TransactionContext, _ touched: [ElementID]) {
        let all = tx.model.elements(.furnitureHardware).filter { !$0.isType && $0.params[ComponentInstanceKeys.face] != nil && $0.params[FurnitureHardware.slotParam] == nil }
        guard !all.isEmpty else { return }
        let touchedSet = Set(touched)
        // A change anywhere in the piece can move a host (joints, planes): re-place every instance whose host is in
        // the document; unchanged ones aren't written.
        let affected = all.filter { touchedSet.contains($0.id) || $0.hostID.map { touchedSet.contains($0) || tx.model[$0] != nil } ?? false }
        let levelZ = tx.model.elevation(ofLevel: tx.model.levels.first?.id)
        var doneGroups: Set<String> = []
        for e in affected {
            guard let s = ComponentSettings(e), s.followsHost || touchedSet.contains(e.id), let hostID = e.hostID, let host = tx.model[hostID],
                  let d = ComponentDocument.definition(of: e, tx.model) else { continue }
            if let g = e.params[ComponentInstanceKeys.group]?.textValue {
                guard !doneGroups.contains(g) else { continue }
                doneGroups.insert(g)
                regenerateGroup(g, d, host, tx, levelZ: levelZ)
                continue
            }
            guard let f = face(host, s.face, tx.model) else {
                tx.warn(ModelWarning(.warning, code: "comp.host", "\(e.name.isEmpty ? d.name : e.name) lost its face on its host.", elements: [e.id]))
                continue
            }
            let p = anchor(f, s)
            if !f.contains(p.x, p.y, margin: 0.002) {
                tx.warn(ModelWarning(.warning, code: "comp.off", "\(d.name) is off the edge of its host. Move it, or change its offsets in Properties.",
                                     elements: [e.id, hostID]))
            }
            let (data, values) = Self.data(d, on: f, at: p, s, mirrored: e.component?.mirrored ?? false, tx.model, levelZ: levelZ)
            write(e, data, values, tx)
        }
        // Live warnings: the rules of components placed, edited or whose host changed in this transaction.
        for e in all where touchedSet.contains(e.id) || (e.hostID.map(touchedSet.contains) ?? false) {
            guard let now = tx.model[e.id] else { continue }
            ComponentChecks.check(instance: now, tx.model).forEach(tx.warn)
        }
    }

    static func write(_ e: Element, _ data: ComponentData, _ values: [String: ParamValue], _ tx: TransactionContext, settings: ComponentSettings? = nil) {
        var x = e
        settings?.write(&x)
        var cd = data
        cd.facingFlipped = e.component?.facingFlipped
        x.data = .component(cd)
        for (k, v) in values { x.params[Parameters.familyParamID(k)] = v }
        if x != e { tx.propagate(e.id) { $0 = x } }
    }

    static func regenerateGroup(_ g: String, _ d: ComponentDefinition, _ host: Element, _ tx: TransactionContext, levelZ: Double) {
        let members = tx.model.hosted(by: host.id).filter { $0.params[ComponentInstanceKeys.group]?.textValue == g }
            .sorted { ($0.params[ComponentInstanceKeys.index]?.intValue ?? 0) < ($1.params[ComponentInstanceKeys.index]?.intValue ?? 0) }
        guard let first = members.first, var s = ComponentSettings(first), s.followsHost else { return }
        let fixed = first.params[ComponentInstanceKeys.count]?.intValue.flatMap { $0 > 0 ? $0 : nil }
        // The set's anchor: the first member's offsets along the face's X (hinge sets keep their side offset).
        if d.placement.mirroredPair { s.face = first.params[ComponentInstanceKeys.face]?.textValue.flatMap(ComponentFace.init(rawValue:)) ?? s.face }
        let spots = layout(d, host: host, s, at: nil, count: fixed, tx.model)
        for (k, spot) in spots.enumerated() {
            var ss = Self.settings(s, at: spot.point, on: spot.face)
            ss.face = spot.face.face
            let (data, values) = Self.data(d, on: spot.face, at: spot.point, ss, mirrored: spot.mirrored, tx.model, levelZ: levelZ)
            if k < members.count {
                write(members[k], data, values, tx, settings: ss)
            } else {
                tx.create(.furnitureHardware, data: .component(data), typeID: first.typeID, levelID: first.levelID, hostID: host.id) { e in
                    e.params = first.params
                    ss.write(&e)
                    e.params[ComponentInstanceKeys.index] = .int(k)
                    for (key, v) in values { e.params[Parameters.familyParamID(key)] = v }
                }
            }
        }
        for extra in members.dropFirst(spots.count) { tx.delete(extra.id) }
    }

    /// Replace: swaps instances to another component (or type), keeping host, face, alignment and offsets; mounting is
    /// recalculated by regeneration. Returns warnings for hosts the new component doesn't suit (it is still placed).
    @discardableResult
    public static func replace(_ ids: [ElementID], with d: ComponentDefinition, typeName: String? = nil, in tx: TransactionContext) throws(TransactionError) -> [ModelWarning] {
        guard let tid = ComponentDocument.load(d, typeName: typeName, in: tx) else { throw TransactionError("\(d.name) has no types.") }
        var warnings: [ModelWarning] = []
        for id in ids {
            guard let e = tx.model[id], e.category == .furnitureHardware, !e.isType else { continue }
            if let host = tx.model[e.hostID], let k = hostKind(host, tx.model), !accepts(d, k) {
                warnings.append(ModelWarning(.warning, code: "comp.replace", "\(d.name) isn't made for a \(k.rawValue.lowercased()); check its fit.", elements: [id]))
            }
            tx.update(id) { x in
                x.typeID = tid
                x.params[ComponentKit.definitionParam] = .text(d.id)
                // Values of the old family that the new one doesn't have go.
                for k in x.params.keys where k.key.hasPrefix(Parameters.familyPrefix) {
                    let name = String(k.key.dropFirst(Parameters.familyPrefix.count))
                    if d.family.parameter(named: name) == nil { x.params.removeValue(forKey: k) }
                }
                if x.params[ComponentInstanceKeys.face] == nil, let host = tx.model[x.hostID], let f = face(host, d.placement.faces.first ?? .front, tx.model) {
                    var s = ComponentSettings(d.placement, face: f.face)
                    if let c = x.component { s = Self.settings(s, at: f.local(Vec3(c.location, z: tx.model.baseElevation(of: x))), on: f) }
                    s.write(&x)
                }
            }
            if let host = tx.model[id]?.hostID, let other = tx.model[host], let k = hostKind(other, tx.model) {
                warnings += ComponentChecks.requirements(d, typeName: tx.model[tid]?.name, host: other, kind: k, tx.model).map {
                    var w = $0; w.elements = [id] + w.elements.filter { $0 != id }; return w
                }
            }
        }
        warnings.forEach(tx.warn)
        return warnings
    }
}
