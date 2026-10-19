import Foundation
import ArcusGeometry

// FM6: the joint solver. At regeneration (lazily, once per model state) it finds every pair of parts that touch or
// overlap, classifies the pair (Side – Top, Shelf – Side, Rail – Leg…), applies the document's Joint Rules unless the
// user set the joint, decides which part runs through and trims or extends the parts, as Revit-style wall joins do.
// Drawn touching, a corner keeps the part that was drawn through; drawn overlapping (a rectangle of panels), the rule
// decides. The result is cached by the model's content stamp; nothing is stored.

/// A part as the joint solver sees it: its box (with the planes its faces follow) and what it is.
public struct JointPart: Sendable {
    public var id: ElementID
    public var role: JointRole
    /// Faces per axis (x, y, z): min and max.
    public var lo: [PartValue]
    public var hi: [PartValue]
    /// The box came from the part's own single box solid (it can be trimmed); otherwise (shaped legs) it only hosts
    /// machining.
    public var reshapeable: Bool

    func l(_ a: FamilyAxis) -> Double { lo[a.idx].value }
    func h(_ a: FamilyAxis) -> Double { hi[a.idx].value }
    func ext(_ a: FamilyAxis) -> Double { h(a) - l(a) }
    /// The axis the part is thinnest along (its thickness, for sheet parts).
    var thin: FamilyAxis { FamilyAxis.allCases.min { ext($0) < ext($1) } ?? .z }
    var longest: Double { FamilyAxis.allCases.map(ext).max() ?? 0 }
    public var box: Box3 { Box3(min: Vec3(l(.x), l(.y), l(.z)), max: Vec3(h(.x), h(.y), h(.z))) }
}

/// A joint between two parts, as solved.
public struct FurnitureJoint: Sendable {
    public var key: JointKey
    public var pair: JointPairKind
    public var type: JointType
    /// What Joint Rules gives the pair (the type when the user hasn't set one).
    public var ruleType: JointType
    /// The joint's parameters with every default filled in.
    public var parameters: JointParameters
    /// The part that runs through, and the one that is trimmed to it (or housed in it).
    public var throughID: ElementID
    public var otherID: ElementID
    /// The axis along which the other part ends at the through part, and the side of the other part that end is on.
    public var axis: FamilyAxis
    public var otherEndAtMax: Bool
    /// An L corner: either part may run through, and a miter is possible.
    public var isCorner: Bool
    /// The user's joint element (nil for automatic joints).
    public var elementID: ElementID?
    /// The middle of the joint face (marker position).
    public var marker: Vec3
    /// Internal: the solver's order (A ends at nothing, B ends at A).
    var a: ElementID
    var b: ElementID
    var a2: FamilyAxis?
    var aEndAtMax: Bool
    var bEndAtMax: Bool
    var a1: FamilyAxis

    /// Set by the user (type, through part or parameters), not by the rules.
    public var isUserSet: Bool { elementID != nil }

    /// The configurations Previous/Next cycles through: each type with each part running through (corners), or each type.
    public var configurations: [(type: JointType, through: ElementID)] {
        var out: [(JointType, ElementID)] = []
        for t in JointType.allCases {
            if t == .miter { if isCorner { out.append((t, a)) }; continue }
            out.append((t, a))
            if isCorner { out.append((t, b)) }
        }
        return out
    }
    public var configurationIndex: Int {
        configurations.firstIndex { $0.type == type && ($0.type == .miter || $0.through == throughID) } ?? 0
    }
}

/// Face changes, miters and Fine-level solids the joints make on one part.
struct PartJointMods: Sendable {
    /// Face (axis, max side) → new value; extensions first, trims win.
    var extend: [PartEnd: PartValue] = [:]
    var trim: [PartEnd: PartValue] = [:]
    var miters: [Miter] = []
    /// Tongues and tenons (shown at Fine), and the grooves and mortises cut in this part (Fine).
    var fineSolids: [JBox] = []
    var fineVoids: [JBox] = []
    var isEmpty: Bool { extend.isEmpty && trim.isEmpty && miters.isEmpty && fineSolids.isEmpty && fineVoids.isEmpty }
    var reshapes: Bool { !extend.isEmpty || !trim.isEmpty || !miters.isEmpty }
}

/// A miter: in the part's rectangle on the plane normal to `normal`, the corner at (`lAxis` side `lAtMax`, `tAxis`
/// side `tAtMax`) moves along `lAxis` to `to`.
struct Miter: Sendable {
    var normal: FamilyAxis
    var lAxis: FamilyAxis
    var lAtMax: Bool
    var tAxis: FamilyAxis
    var tAtMax: Bool
    var to: PartValue
}

/// A box of PartValues.
struct JBox: Sendable {
    var lo: [PartValue]
    var hi: [PartValue]
    func l(_ a: FamilyAxis) -> Double { lo[a.idx].value }
    func h(_ a: FamilyAxis) -> Double { hi[a.idx].value }
    func ext(_ a: FamilyAxis) -> Double { h(a) - l(a) }
    var box: Box3 { Box3(min: Vec3(l(.x), l(.y), l(.z)), max: Vec3(h(.x), h(.y), h(.z))) }
}

/// Everything the joints of a model state make.
public struct JointSolution: Sendable {
    public var parts: [ElementID: JointPart] = [:]
    public var joints: [FurnitureJoint] = []
    var mods: [ElementID: PartJointMods] = [:]
    /// Each part's box after its trims and extensions.
    var finalBoxes: [ElementID: JBox] = [:]
    /// Each part's cut envelope (final box with tongues and tenons).
    var envelopes: [ElementID: JBox] = [:]
    public var machining: [MachiningEntry] = []
    /// Fasteners and shelf pins, by kind.
    public var hardware: [String: Int] = [:]
    /// Parts each part joins or touches (for cache keys and invalidation).
    public var partners: [ElementID: Set<ElementID>] = [:]
    /// Adjustable shelves and the parts drilled for their pins.
    var pinContacts: [(shelf: ElementID, side: ElementID, axis: FamilyAxis, shelfEndAtMax: Bool)] = []

    public func joint(_ key: JointKey) -> FurnitureJoint? { joints.first { $0.key == key } }
    public func joints(of id: ElementID) -> [FurnitureJoint] { joints.filter { $0.key.a == id || $0.key.b == id } }
}

extension FamilyAxis {
    var idx: Int { self == .x ? 0 : self == .y ? 1 : 2 }
    var unit: Vec3 { self == .x ? .unitX : self == .y ? .unitY : .unitZ }
    /// The two other axes, in x, y, z order.
    var others: (FamilyAxis, FamilyAxis) { self == .x ? (.y, .z) : self == .y ? (.x, .z) : (.x, .y) }
}

/// The solver's cache (one entry per recent model state).
final class JointSolveCache: @unchecked Sendable {
    static let shared = JointSolveCache()
    private let lock = NSLock()
    private var entries: [(UInt64, JointSolution)] = []
    func get(_ stamp: UInt64) -> JointSolution? { lock.lock(); defer { lock.unlock() }; return entries.first { $0.0 == stamp }?.1 }
    func put(_ stamp: UInt64, _ s: JointSolution) {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.0 == stamp }
        entries.insert((stamp, s), at: 0)
        if entries.count > 6 { entries.removeLast() }
    }
}

public enum JointSolver {
    /// Touching tolerance (0.01 mm).
    static let eps = 1e-5
    static let inch = 0.0254

    /// The joints of a Furniture document (cached per model state; empty in projects).
    public static func solve(_ m: BIMModel) -> JointSolution {
        guard m.isFurniture else { return JointSolution() }
        if let s = JointSolveCache.shared.get(m.contentStamp) { return s }
        let s = compute(m)
        JointSolveCache.shared.put(m.contentStamp, s)
        return s
    }

    // MARK: Parts

    static func role(_ e: Element, thin: FamilyAxis) -> JointRole? {
        switch e.data {
        case .furniturePanel(let p):
            switch p.role {
            case .back: return .back
            case .plinth: return .plinth
            case .divider: return thin == .z ? .shelf : .divider
            default: return thin == .z ? .shelf : .side
            }
        case .furnitureShelf(let s): return s.role == .top ? .top : s.role == .bottom ? .bottom : (s.adjustable ? .adjustableShelf : .shelf)
        case .furnitureLeg: return .leg
        case .furnitureRail(let r): return r.slats == nil ? .rail : nil
        default: return nil
        }
    }

    /// The part's box: its single box solid's, or for shaped legs the box round the leg's top.
    static func part(_ e: Element, _ m: BIMModel) -> JointPart? {
        var lo: [PartValue], hi: [PartValue], reshapeable = true
        if let b = FurniturePartSolids.partBox(e, m) {
            lo = [b.x.0, b.y.0, b.z.0]; hi = [b.x.1, b.y.1, b.z.1]
        } else if let l = e.furnitureLeg {
            let tv = FurniturePartTypes.values(of: e, m)
            let quarter = abs((l.rotation / (.pi / 2)).rounded()).truncatingRemainder(dividingBy: 2) == 1
            let (hw, hd) = quarter ? (tv.depth / 2, tv.width / 2) : (tv.width / 2, tv.depth / 2)
            let x = FurniturePartSolids.pv(e, l.location.x, "x"), y = FurniturePartSolids.pv(e, l.location.y, "y")
            lo = [x.shifted(-hw), y.shifted(-hd), FurniturePartSolids.pv(e, l.base, "base")]
            hi = [x.shifted(hw), y.shifted(hd), FurniturePartSolids.pv(e, l.top, "top")]
            reshapeable = false
        } else {
            return nil
        }
        guard (0..<3).allSatisfy({ hi[$0].value - lo[$0].value > Tolerance.length }) else { return nil }
        // EQ dividers: their faces follow the centre plane Load into Project gives each divider (FurnitureCompiler).
        if let p = e.furniturePanel, let q = p.eq, let f = FurniturePartSolids.linearFrame(p.plane, p.start, p.end) {
            let r = FurnitureBoundResolver(m)
            if let low = r.resolve(q.low), let high = r.resolve(q.high), q.count > 0 {
                let c = low + (high - low) * Double(q.index) / Double(q.count)
                let name = "\(e.mark.isEmpty ? "Divider \(e.id.raw)" : e.mark) Center"
                let i = f.crossAxis.idx
                lo[i] = PartValue(lo[i].value, plane: name, offset: lo[i].value - c)
                hi[i] = PartValue(hi[i].value, plane: name, offset: hi[i].value - c)
            }
        }
        var jp = JointPart(id: e.id, role: .side, lo: lo, hi: hi, reshapeable: reshapeable)
        guard let r = role(e, thin: jp.thin) else { return nil }
        jp.role = r
        return jp
    }

    // MARK: Classification

    static let pairTable: [(Set<JointRole>, Set<JointRole>, JointPairKind)] = [
        ([.side], [.top], .sideTop), ([.side], [.bottom], .sideBottom), ([.side], [.side], .sideSide),
        ([.side, .top, .bottom, .divider, .plinth], [.back], .sideBack), ([.shelf, .adjustableShelf], [.back], .shelfBack),
        ([.shelf], [.side], .shelfSide), ([.divider], [.shelf, .top, .bottom], .dividerShelf),
        ([.plinth], [.side, .bottom, .shelf, .divider], .plinthCarcass),
        ([.rail], [.leg], .railLeg), ([.rail], [.side, .divider, .back, .plinth], .railPanel), ([.rail], [.top, .shelf, .bottom], .railTop),
        ([.top, .shelf, .bottom], [.leg], .topLeg),
    ]

    /// The pair kind of two parts and which is its first part; nil when they don't join (an adjustable shelf sits on
    /// pins between its sides).
    static func classify(_ p: JointPart, _ q: JointPart) -> (JointPairKind, first: ElementID)? {
        let pins: Set<JointRole> = [.side, .divider]
        if (p.role == .adjustableShelf && pins.contains(q.role)) || (q.role == .adjustableShelf && pins.contains(p.role)) { return nil }
        for (s1, s2, k) in pairTable {
            if s1.contains(p.role) && s2.contains(q.role) { return (k, s1 == s2 ? min(p.id, q.id) : p.id) }
            if s1.contains(q.role) && s2.contains(p.role) { return (k, q.id) }
        }
        return (.other, min(p.id, q.id))
    }

    static func overlap(_ p: JointPart, _ q: JointPart, _ a: FamilyAxis) -> Double { min(p.h(a), q.h(a)) - max(p.l(a), q.l(a)) }

    /// B's end lies on or in A along `a` with B's body on one side: true when it is B's max end, false its min end.
    static func endsAt(_ b: JointPart, _ a: JointPart, _ axis: FamilyAxis) -> Bool? {
        let bl = b.l(axis), bh = b.h(axis), al = a.l(axis), ah = a.h(axis)
        if bh >= al - eps && bh <= ah + eps && bl < al - eps { return true }
        if bl >= al - eps && bl <= ah + eps && bh > ah + eps { return false }
        return nil
    }

    /// How B meets A: the axis B ends at A along (not B's thickness), and, at an L corner, the axis A ends at B along.
    struct Config { var a: JointPart; var b: JointPart; var a1: FamilyAxis; var bEndAtMax: Bool; var a2: FamilyAxis?; var aEndAtMax: Bool }

    static func config(_ a: JointPart, _ b: JointPart) -> Config? {
        for a1 in FamilyAxis.allCases where a1 != b.thin {
            guard let bMax = endsAt(b, a, a1) else { continue }
            let (c1, c2) = a1.others
            guard overlap(a, b, c1) > eps, overlap(a, b, c2) > eps else { continue }
            // An L corner: A ends within B's range along another axis too (its end may only touch B's end).
            for a2 in [c1, c2] where a2 != a.thin {
                let a3 = a2 == c1 ? c2 : c1
                if let aMax = endsAt(a, b, a2), overlap(a, b, a3) > eps { return Config(a: a, b: b, a1: a1, bEndAtMax: bMax, a2: a2, aEndAtMax: aMax) }
            }
            return Config(a: a, b: b, a1: a1, bEndAtMax: bMax, a2: nil, aEndAtMax: false)
        }
        return nil
    }

    // MARK: Solve

    static func compute(_ m: BIMModel) -> JointSolution {
        var sol = JointSolution()
        var list: [JointPart] = []
        for c in [Category.furniturePanels, .furnitureShelves, .furnitureLegs, .furnitureRails] {
            for e in m.elements(c) { if let p = part(e, m) { list.append(p) } }
        }
        list.sort { $0.id < $1.id }
        for p in list { sol.parts[p.id] = p }
        guard list.count >= 2 else { return sol }
        // The user's joints and disallowed ends.
        var user: [JointKey: (ElementID, JointData)] = [:]
        var disallowed: [ElementID: [PartEnd?]] = [:]
        for j in m.elements(.furnitureJoints) {
            guard let d = j.furnitureJoint else { continue }
            if d.isPair { user[JointKey(d.parts[0], d.parts[1])] = (j.id, d) }
            else if d.parts.count == 1 { disallowed[d.parts[0], default: []].append(d.disallowedEnd) }
        }
        func isDisallowed(_ id: ElementID, _ end: PartEnd) -> Bool {
            disallowed[id]?.contains { $0 == nil || $0 == end } ?? false
        }
        let category = m.furnitureSetup?.category ?? .casework
        let rules = m.furnitureJointRules
        let center = list.reduce(Box3.empty) { $0.union($1.box) }.center

        // Pairs.
        for i in list.indices {
            for j in list.indices where j > i {
                let p = list[i], q = list[j]
                guard FamilyAxis.allCases.allSatisfy({ overlap(p, q, $0) >= -eps }),
                      FamilyAxis.allCases.filter({ overlap(p, q, $0) > eps }).count >= 2 else { continue }
                guard let cfg = config(p, q) ?? config(q, p) else { continue }
                guard let (kind, first) = classify(p, q) else {
                    // Adjustable shelves: pin rows in the parts they end at.
                    let shelf = p.role == .adjustableShelf ? p : q
                    if shelf.id == cfg.b.id, cfg.a1 != .z { sol.pinContacts.append((shelf.id, cfg.a.id, cfg.a1, cfg.bEndAtMax)) }
                    sol.partners[p.id, default: []].insert(q.id); sol.partners[q.id, default: []].insert(p.id)
                    continue
                }
                if isDisallowed(cfg.b.id, PartEnd(axis: cfg.a1, atMax: cfg.bEndAtMax)) { continue }
                if let a2 = cfg.a2, isDisallowed(cfg.a.id, PartEnd(axis: a2, atMax: cfg.aEndAtMax)) { continue }
                sol.partners[p.id, default: []].insert(q.id); sol.partners[q.id, default: []].insert(p.id)
                let key = JointKey(p.id, q.id)
                let mine = user[key]
                let rule = rules.rule(kind, category: category)
                var type = mine?.1.type ?? rule.type
                if type == .miter && cfg.a2 == nil { type = .butt }
                var params = JointParameters.defaults(type)
                if type == rule.type { params = rule.parameters.over(params) }
                if let up = mine?.1.parameters { params = up.over(params) }
                // Which part runs through.
                let a = cfg.a, b = cfg.b
                var through = a.id
                if let a2 = cfg.a2 {
                    let aOwns = a.l(a2) <= b.l(a2) + eps && a.h(a2) >= b.h(a2) - eps
                    let bOwns = b.l(cfg.a1) <= a.l(cfg.a1) + eps && b.h(cfg.a1) >= a.h(cfg.a1) - eps
                    if let t = mine?.1.throughPartID, t == a.id || t == b.id {
                        through = t
                    } else if aOwns && bOwns {
                        switch rule.through {
                        case .first: through = first
                        case .second: through = first == a.id ? b.id : a.id
                        case .longer: through = a.longest >= b.longest - eps ? a.id : b.id
                        }
                    } else if bOwns {
                        through = b.id
                    }
                }
                let other = through == a.id ? b.id : a.id
                let axis = through == a.id ? cfg.a1 : (cfg.a2 ?? cfg.a1)
                let oMax = through == a.id ? cfg.bEndAtMax : cfg.aEndAtMax
                let t = through == a.id ? a : b
                let nearT = oMax ? t.lo[axis.idx] : t.hi[axis.idx]
                let o = through == a.id ? b : a
                let (c1, c2) = axis.others
                var mk = [0.0, 0.0, 0.0]
                mk[axis.idx] = nearT.value
                for c in [c1, c2] { mk[c.idx] = (max(o.l(c), t.l(c)) + min(o.h(c), t.h(c))) / 2 }
                sol.joints.append(FurnitureJoint(key: key, pair: kind, type: type, ruleType: rule.type, parameters: params, throughID: through, otherID: other,
                                                 axis: axis, otherEndAtMax: oMax, isCorner: cfg.a2 != nil, elementID: mine?.0, marker: Vec3(mk[0], mk[1], mk[2]),
                                                 a: a.id, b: b.id, a2: cfg.a2, aEndAtMax: cfg.aEndAtMax, bEndAtMax: cfg.bEndAtMax, a1: cfg.a1))
            }
        }

        // Phase 1: trims, extensions and miters.
        for j in sol.joints {
            guard let a = sol.parts[j.a], let b = sol.parts[j.b] else { continue }
            if j.type == .miter, let a2 = j.a2 {
                // Both run to the outer corner, then each loses the triangle beyond the diagonal.
                sol.mods[b.id, default: .init()].extend[PartEnd(axis: j.a1, atMax: j.bEndAtMax)] = j.bEndAtMax ? a.hi[j.a1.idx] : a.lo[j.a1.idx]
                sol.mods[a.id, default: .init()].extend[PartEnd(axis: a2, atMax: j.aEndAtMax)] = j.aEndAtMax ? b.hi[a2.idx] : b.lo[a2.idx]
                let a3 = a2.others.0 == j.a1 ? a2.others.1 : a2.others.0
                sol.mods[b.id, default: .init()].miters.append(Miter(normal: a3, lAxis: j.a1, lAtMax: j.bEndAtMax, tAxis: a2, tAtMax: !j.aEndAtMax,
                                                                     to: j.bEndAtMax ? a.lo[j.a1.idx] : a.hi[j.a1.idx]))
                sol.mods[a.id, default: .init()].miters.append(Miter(normal: a3, lAxis: a2, lAtMax: j.aEndAtMax, tAxis: j.a1, tAtMax: !j.bEndAtMax,
                                                                     to: j.aEndAtMax ? b.lo[a2.idx] : b.hi[a2.idx]))
                continue
            }
            let t = j.throughID == a.id ? a : b, o = j.throughID == a.id ? b : a
            // The through part runs over the corner; the other stops at its face.
            if j.isCorner, let a2 = j.a2 {
                if t.id == a.id { sol.mods[a.id, default: .init()].extend[PartEnd(axis: a2, atMax: j.aEndAtMax)] = j.aEndAtMax ? b.hi[a2.idx] : b.lo[a2.idx] }
                else { sol.mods[b.id, default: .init()].extend[PartEnd(axis: j.a1, atMax: j.bEndAtMax)] = j.bEndAtMax ? a.hi[j.a1.idx] : a.lo[j.a1.idx] }
            }
            let near = j.otherEndAtMax ? t.lo[j.axis.idx] : t.hi[j.axis.idx]
            let end = PartEnd(axis: j.axis, atMax: j.otherEndAtMax)
            if let cur = sol.mods[o.id]?.trim[end] {
                // Two joints trim the same end: the one further in wins.
                sol.mods[o.id]?.trim[end] = (j.otherEndAtMax ? near.value < cur.value : near.value > cur.value) ? near : cur
            } else {
                sol.mods[o.id, default: .init()].trim[end] = near
            }
        }
        for p in list {
            var box = JBox(lo: p.lo, hi: p.hi)
            if let md = sol.mods[p.id], p.reshapeable {
                for (e, v) in md.extend { if e.atMax { box.hi[e.axis.idx] = v } else { box.lo[e.axis.idx] = v } }
                for (e, v) in md.trim { if e.atMax { box.hi[e.axis.idx] = v } else { box.lo[e.axis.idx] = v } }
            }
            sol.finalBoxes[p.id] = box
            sol.envelopes[p.id] = box
        }

        // Phase 2: housings, tenons and machining, on the final boxes.
        for j in sol.joints {
            guard let tb = sol.finalBoxes[j.throughID], let ob = sol.finalBoxes[j.otherID] else { continue }
            joinery(j, through: tb, other: ob, center: center, &sol)
        }
        shelfPins(m, &sol)
        return sol
    }

    // MARK: Joinery

    /// The larger / smaller of two coordinates.
    static func maxV(_ a: PartValue, _ b: PartValue) -> PartValue { a.value >= b.value ? a : b }
    static func minV(_ a: PartValue, _ b: PartValue) -> PartValue { a.value <= b.value ? a : b }

    /// A world point from coordinates per axis.
    static func point(_ c: [FamilyAxis: Double]) -> Vec3 { Vec3(c[.x] ?? 0, c[.y] ?? 0, c[.z] ?? 0) }

    /// Fastener positions along [lo, hi]: by count, or as many as the spacing needs, `edge` in from the ends.
    static func positions(_ lo: Double, _ hi: Double, _ p: JointParameters) -> [Double] {
        let len = hi - lo
        guard len > Tolerance.length else { return [] }
        let e = p.edgeDistance ?? 0.0381
        if len <= 2 * e + Tolerance.length { return [(lo + hi) / 2] }
        let n: Int
        if let c = p.count, c > 0 { n = c }
        else { n = Int(((len - 2 * e) / max(p.spacing ?? 0.15, 0.01) - 1e-9).rounded(.up)) + 1 }
        if n == 1 { return [(lo + hi) / 2] }
        return (0..<n).map { lo + e + (len - 2 * e) * Double($0) / Double(n - 1) }
    }

    static func joinery(_ j: FurnitureJoint, through tb: JBox, other ob: JBox, center: Vec3, _ sol: inout JointSolution) {
        let ax = j.axis
        let (c1, c2) = ax.others
        let near = j.otherEndAtMax ? tb.lo[ax.idx] : tb.hi[ax.idx]
        let far = j.otherEndAtMax ? tb.hi[ax.idx] : tb.lo[ax.idx]
        let sign: Double = j.otherEndAtMax ? 1 : -1 // into the through part along `ax`
        let into = ax.unit * sign
        let tThick = tb.ext(ax)
        // The joint face: where the parts meet across the other two axes.
        var cLo: [FamilyAxis: PartValue] = [:], cHi: [FamilyAxis: PartValue] = [:]
        for c in [c1, c2] { cLo[c] = maxV(ob.lo[c.idx], tb.lo[c.idx]); cHi[c] = minV(ob.hi[c.idx], tb.hi[c.idx]) }
        guard let l1 = cLo[c1], let h1 = cHi[c1], let l2 = cLo[c2], let h2 = cHi[c2], h1.value - l1.value > Tolerance.length, h2.value - l2.value > Tolerance.length else { return }
        // The other part's thickness across the joint face, and the face's long direction.
        let tO = ob.ext(c1) <= ob.ext(c2) ? c1 : c2
        let L = tO == c1 ? c2 : c1
        guard let tLo = cLo[tO], let tHi = cHi[tO], let lLo = cLo[L], let lHi = cHi[L] else { return }
        let thick = tHi.value - tLo.value
        let mid = (tLo.value + tHi.value) / 2
        let p = j.parameters
        let src = MachiningSource.joint(j.elementID ?? j.otherID)
        func box(along a: (PartValue, PartValue), _ t: (PartValue, PartValue), _ l: (PartValue, PartValue)) -> JBox {
            var lo = [PartValue(0), PartValue(0), PartValue(0)], hi = lo
            lo[ax.idx] = a.0.value <= a.1.value ? a.0 : a.1; hi[ax.idx] = a.0.value <= a.1.value ? a.1 : a.0
            lo[tO.idx] = t.0; hi[tO.idx] = t.1; lo[L.idx] = l.0; hi[L.idx] = l.1
            return JBox(lo: lo, hi: hi)
        }
        func at(_ along: Double, _ t: Double, _ l: Double) -> Vec3 { point([ax: along, tO: t, L: l]) }
        // The other part's face toward the middle of the piece (cams and pockets go on the hidden face).
        let innerMax = mid < [center.x, center.y, center.z][tO.idx]
        let innerFace = innerMax ? tHi.value : tLo.value
        let intoO = tO.unit * (innerMax ? -1 : 1)

        switch j.type {
        case .butt, .miter:
            break
        case .dado, .rabbet, .groove, .mortiseTenon:
            let tenon = j.type == .mortiseTenon
            var d = p.depth ?? 0.25 * inch
            d = min(d, max(0, tThick - 0.125 * inch))
            if tenon { d = min(d, max(0.125 * inch, tThick / 2 - (p.tenonThickness ?? thick / 3) / 2 - inch / 32)) }
            guard d > 0.001 else { break }
            var t0 = tLo, t1 = tHi, s0 = lLo, s1 = lHi
            if tenon {
                let tt = min(p.tenonThickness ?? (thick / 3 * 16 / inch).rounded() / 16 * inch, thick - 0.0016)
                t0 = tLo.shifted((thick - tt) / 2); t1 = tHi.shifted(-(thick - tt) / 2)
                let sh = p.shoulder ?? 0.25 * inch
                if lHi.value - lLo.value > 2 * sh + 0.25 * inch { s0 = lLo.shifted(sh); s1 = lHi.shifted(-sh) }
            }
            let tongue = box(along: (near, near.shifted(sign * d)), (t0, t1), (s0, s1))
            sol.mods[j.otherID, default: .init()].fineSolids.append(tongue)
            if var env = sol.envelopes[j.otherID] {
                if j.otherEndAtMax { env.hi[ax.idx] = maxV(env.hi[ax.idx], near.shifted(d)) } else { env.lo[ax.idx] = minV(env.lo[ax.idx], near.shifted(-d)) }
                sol.envelopes[j.otherID] = env
            }
            let clear = tenon ? 0 : (p.clearance ?? 0) / 2
            let extra = tenon ? inch / 16 : 0
            let void = box(along: (near, near.shifted(sign * (d + extra))), (t0.shifted(-clear), t1.shifted(clear)), (s0, s1))
            sol.mods[j.throughID, default: .init()].fineVoids.append(void)
            let tw = t1.value - t0.value + 2 * clear
            if tenon {
                let tm = (t0.value + t1.value) / 2
                let outline = [at(near.value, tm - tw / 2, s0.value), at(near.value, tm + tw / 2, s0.value), at(near.value, tm + tw / 2, s1.value), at(near.value, tm - tw / 2, s1.value)]
                sol.machining.append(MachiningEntry(partID: j.throughID, op: .pocket(outline: outline, axis: into, depth: d + extra), source: src, label: "Mortise"))
            } else {
                sol.machining.append(MachiningEntry(partID: j.throughID, op: .groove(start: at(near.value, mid, s0.value), end: at(near.value, mid, s1.value), axis: into, width: tw, depth: d),
                                                    source: src, label: j.type.rawValue))
            }
        case .dowel, .camLock, .confirmat, .pocketScrew, .biscuit:
            let ps = positions(lLo.value, lHi.value, p)
            let label = hardwareName(j.type, p)
            sol.hardware[label, default: 0] += ps.count
            for s in ps {
                let c = at(near.value, mid, s)
                switch j.type {
                case .dowel:
                    let len = p.length ?? 0.03, dia = p.diameter ?? 0.008
                    let face = max(0.004, min(0.4 * len, tThick - 0.003))
                    sol.machining.append(MachiningEntry(partID: j.throughID, op: .drill(center: c, axis: into, diameter: dia, depth: face), source: src, label: "Dowel"))
                    sol.machining.append(MachiningEntry(partID: j.otherID, op: .drill(center: c, axis: into * -1, diameter: dia, depth: len - face + 0.001), source: src, label: "Dowel"))
                case .camLock:
                    let camD = p.diameter ?? 0.015
                    sol.machining.append(MachiningEntry(partID: j.throughID, op: .drill(center: c, axis: into, diameter: 0.005, depth: min(0.011, tThick - 0.003)), source: src, label: "Cam bolt"))
                    sol.machining.append(MachiningEntry(partID: j.otherID, op: .drill(center: c, axis: into * -1, diameter: 0.008, depth: 0.034), source: src, label: "Cam bolt hole"))
                    let cam = at(near.value - sign * 0.024, innerFace, s)
                    sol.machining.append(MachiningEntry(partID: j.otherID, op: .drill(center: cam, axis: intoO, diameter: camD, depth: min(0.0127, thick - 0.003)), source: src, label: "Cam lock"))
                case .confirmat:
                    sol.machining.append(MachiningEntry(partID: j.throughID, op: .drill(center: at(far.value, mid, s), axis: into * -1, diameter: p.diameter ?? 0.007, depth: tThick),
                                                        source: src, label: "Confirmat"))
                    sol.machining.append(MachiningEntry(partID: j.otherID, op: .drill(center: c, axis: into * -1, diameter: 0.005, depth: max(0.02, 0.05 - tThick)), source: src, label: "Confirmat pilot"))
                case .pocketScrew:
                    let ang = max(5 * .pi / 180, min(p.angle ?? 15 * .pi / 180, 45 * .pi / 180))
                    let run = (thick / 2) / tan(ang)
                    let entry = at(near.value - sign * run, innerFace, s)
                    let dir = (into * cos(ang) + intoO * sin(ang)).normalized
                    sol.machining.append(MachiningEntry(partID: j.otherID, op: .drill(center: entry, axis: dir, diameter: p.diameter ?? 0.0095, depth: (run * run + thick * thick / 4).squareRoot()),
                                                        source: src, label: "Pocket"))
                case .biscuit:
                    let half = 0.0635 / 2
                    let lu = L.unit
                    sol.machining.append(MachiningEntry(partID: j.throughID, op: .groove(start: c - lu * half, end: c + lu * half, axis: into, width: 0.004, depth: min(0.0127, tThick - 0.003)),
                                                        source: src, label: "Biscuit slot"))
                    sol.machining.append(MachiningEntry(partID: j.otherID, op: .groove(start: c - lu * half, end: c + lu * half, axis: into * -1, width: 0.004, depth: 0.0127),
                                                        source: src, label: "Biscuit slot"))
                default: break
                }
            }
        }
    }

    /// The name hardware schedules count a joint's fasteners by.
    static func hardwareName(_ t: JointType, _ p: JointParameters) -> String {
        switch t {
        case .dowel: "Dowel \(FurnitureSizeText.inches(p.diameter ?? 0.008)) x \(FurnitureSizeText.inches(p.length ?? 0.03))"
        case .camLock: "Cam Lock 15 mm"
        case .confirmat: "Confirmat Screw 7 x 50 mm"
        case .pocketScrew: "Pocket Screw 1 1/4\""
        case .biscuit: "Biscuit #20"
        default: t.rawValue
        }
    }

    // MARK: Shelf pins

    /// Adjustable shelves: two rows of holes in each side they sit between, `pins.above`/`below` holes either side of
    /// the shelf at the pin spacing, the rows `pins.inset` in from the side's front and back edges.
    static func shelfPins(_ m: BIMModel, _ sol: inout JointSolution) {
        var seen: [ElementID: Set<String>] = [:]
        for c in sol.pinContacts {
            guard let s = m[c.shelf]?.furnitureShelf, let pins = s.pins, let sp = sol.parts[c.shelf], let side = sol.finalBoxes[c.side] else { continue }
            let ax = c.axis
            let near = c.shelfEndAtMax ? side.l(ax) : side.h(ax)
            let into = ax.unit * (c.shelfEndAtMax ? 1 : -1)
            // Rows run up the side; they sit `inset` in from its edges across.
            guard let across = [ax.others.0, ax.others.1].first(where: { $0 != .z }) else { continue }
            let rows = [side.l(across) + pins.inset, side.h(across) - pins.inset].filter { $0 > sp.l(across) - 1e-6 && $0 < sp.h(across) + 1e-6 }
            let under = sp.l(.z) - pins.diameter
            let depth = min(0.0095, side.ext(ax) - 0.004)
            guard depth > 0.002 else { continue }
            sol.hardware["Shelf Pin \(Int((pins.diameter * 1000).rounded())) mm", default: 0] += rows.count
            for r in rows {
                for k in -pins.below...pins.above {
                    let z = under + Double(k) * pins.spacing
                    guard z > side.l(.z) + pins.diameter, z < side.h(.z) - pins.diameter else { continue }
                    let ctr = point([ax: near, across: r, .z: z])
                    let key = "\(Int((ctr.x * 2000).rounded())),\(Int((ctr.y * 2000).rounded())),\(Int((ctr.z * 2000).rounded()))"
                    guard seen[c.side, default: []].insert(key).inserted else { continue }
                    sol.machining.append(MachiningEntry(partID: c.side, op: .drill(center: ctr, axis: into, diameter: pins.diameter, depth: depth), source: .shelfPins(c.shelf), label: "Shelf pin"))
                }
            }
        }
    }
}
