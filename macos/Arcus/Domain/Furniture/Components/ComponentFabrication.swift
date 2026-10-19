import Foundation
import ArcusGeometry
import ArcusCalc

// COMP: fabrication data of placed components. Their mounting data (drills, pockets, grooves, edge holes) becomes
// machining on the host part (or the part across the gap), so CNC Export drills it and Check Parts checks it; the
// BOM groups every hardware line by component category and type with cost; the power summary adds up electronics.

extension FurnitureMachining {
    /// Machining from placed components' mounting data.
    static func compMachining(_ m: BIMModel) -> [MachiningEntry] {
        var out: [MachiningEntry] = []
        for e in ComponentChecks.placed(m) {
            guard let d = ComponentDocument.definition(of: e, m), !d.mounting.isEmpty, let host = m[e.hostID], let s = ComponentSettings(e),
                  let f = ComponentPlacement.face(host, s.face, m), let place = ComponentGeometry.placement(e, m) else { continue }
            let ev = FamilyInstanceGeometry.evaluate(e, m) ?? ComponentChecks.evaluated(d, typeName: m[e.typeID]?.name)
            let extra = ["Host Thickness": f.thickness]
            func v(_ x: String) -> Double { ComponentChecks.value(x, ev, extra: extra) ?? 0 }
            let w = place.world
            // Mount coordinates are family coordinates (x, y in the family's XY), placed like the geometry.
            func at(_ x: Double, _ y: Double) -> Vec3 { w.apply(Vec3(x, y, 0)) }
            let into = -f.n
            let target = { (t: ComponentMountTarget, p: Vec3) -> ElementID in
                t == .host ? hostPart(host, face: f.face, m) : counterpart(host, near: p, m) ?? hostPart(host, face: f.face, m)
            }
            // Operations a type switches off (a size of 0) aren't machined.
            func off(_ x: String) -> Bool { v(x) <= 1e-6 }
            for op in d.mounting {
                switch op {
                case .drill(let label, let x, let y, let dia, let depth, let through, let t):
                    guard !off(dia), through || !off(depth) else { continue }
                    let c = at(v(x), v(y))
                    out.append(MachiningEntry(partID: target(t, c), op: .drill(center: c, axis: into, diameter: v(dia), depth: through ? f.thickness : v(depth)),
                                              source: .hardware(e.id), label: label))
                case .pocket(let label, let x, let y, let wd, let ht, let depth, let through, let t):
                    guard !off(wd), !off(ht), through || !off(depth) else { continue }
                    let c = (v(x), v(y)), hw = v(wd) / 2, hh = v(ht) / 2
                    let outline = [at(c.0 - hw, c.1 - hh), at(c.0 + hw, c.1 - hh), at(c.0 + hw, c.1 + hh), at(c.0 - hw, c.1 + hh)]
                    out.append(MachiningEntry(partID: target(t, outline[0]), op: .pocket(outline: outline, axis: into, depth: through ? f.thickness : v(depth)),
                                              source: .hardware(e.id), label: label))
                case .groove(let label, let x0, let y0, let x1, let y1, let wd, let depth, let t):
                    guard !off(wd), !off(depth) else { continue }
                    let a = at(v(x0), v(y0)), b = at(v(x1), v(y1))
                    out.append(MachiningEntry(partID: target(t, a), op: .groove(start: a, end: b, axis: into, width: v(wd), depth: v(depth)),
                                              source: .hardware(e.id), label: label))
                case .edgeDrill(let label, let x, let z, let dia, let depth, let t):
                    guard !off(dia), !off(depth) else { continue }
                    let c = at(v(x), 0) + f.n * v(z)
                    out.append(MachiningEntry(partID: target(t, c), op: .drill(center: c, axis: -f.v, diameter: v(dia), depth: v(depth)),
                                              source: .hardware(e.id), label: label))
                }
            }
        }
        return out
    }

    /// The part a host face machines: a bay's face is the part bounding it (its bottom, top, sides or back); parts and
    /// fronts machine themselves.
    static func hostPart(_ host: Element, face: ComponentFace, _ m: BIMModel) -> ElementID {
        guard let o = host.furnitureBay?.opening else { return host.id }
        let part: ElementID? = switch face {
        case .bottom: o.bottom
        case .top: o.top
        case .left: o.left
        case .right: o.right
        case .back: o.back
        default: nil
        }
        return part ?? host.id
    }

    /// The part across the gap from a host near a point: for a front, its bay's side part on that side; for a bay, its
    /// front; for a carcass part, the door, drawer or flap moving against it (stays, struts and catches) nearest the point.
    static func counterpart(_ host: Element, near p: Vec3, _ m: BIMModel) -> ElementID? {
        if let b = host.furnitureBay {
            return m.hosted(by: host.id).first { $0.furnitureFront != nil }?.id ?? b.opening.map { o in
                let local = BayFrame(b).local(p)
                return abs(local.x - o.x0) <= abs(local.x - o.x1) ? (o.left ?? o.right) : (o.right ?? o.left)
            } ?? nil
        }
        if host.furnitureFront != nil, let b = m[host.hostID]?.furnitureBay, let o = b.opening {
            let local = BayFrame(b).local(p)
            return abs(local.x - o.x0) <= abs(local.x - o.x1) ? (o.left ?? o.right) : (o.right ?? o.left)
        }
        // A carcass part: the fronts of the bays it bounds.
        let fronts = m.elements(.furnitureFronts).filter { f in
            guard let o = m[f.hostID]?.furnitureBay?.opening else { return false }
            return [o.left, o.right, o.top, o.bottom, o.back].contains(host.id)
        }
        func gap(_ f: Element) -> Double { let b = ElementMeshes.bounds(f, m); return ((b.min + b.max) * 0.5 - p).length }
        return fronts.min { gap($0) < gap($1) }?.id
    }
}

/// A line of the component BOM: one component type with its count and cost.
public struct ComponentBOMLine: Sendable, Hashable {
    public var category: ComponentCategory?
    public var subcategory: String
    public var family: String
    public var typeName: String
    public var typeID: ElementID?
    public var count: Int
    public var unitCost: Double
    public var totalCost: Double { unitCost * Double(count) }
    public var manufacturer: String
    public var model: String
    public var sku: String
}

/// An electronics line of the power summary.
public struct ComponentPowerLine: Sendable, Hashable {
    public var elementID: ElementID
    public var family: String
    public var typeName: String
    public var supply: String
    public var volts: Double
    /// Watts of this instance (per-foot ratings times its length).
    public var watts: Double
    public var cable: String
}

public enum ComponentFabrication {
    static func text(_ td: TypeData?, _ key: String) -> String { td?.params[ParameterID(key)]?.textValue ?? "" }

    /// The BOM: every hardware line (placed components, front hardware, joint fasteners) grouped by category and type.
    public static func bom(_ m: BIMModel) -> [ComponentBOMLine] {
        var lines: [String: ComponentBOMLine] = [:]
        for h in FurnitureFabrication.hardware(m) {
            let td = m[h.typeID]?.typeData
            let def = td.flatMap { _ in m[h.typeID].flatMap { ComponentDocument.definition(of: $0, m) } } ?? ComponentCatalog.current.definition(named: h.family)
            let key = "\(h.family)|\(h.typeName)"
            var l = lines[key] ?? ComponentBOMLine(category: def?.category, subcategory: def?.subcategory ?? h.kind, family: h.family, typeName: h.typeName,
                                                   typeID: h.typeID, count: 0, unitCost: h.unitCost, manufacturer: h.manufacturer.isEmpty ? "Generic" : h.manufacturer,
                                                   model: h.model, sku: text(td, ComponentKit.skuParam.key))
            l.count += h.count
            lines[key] = l
        }
        return lines.values.sorted { a, b in
            let ca = a.category?.rawValue ?? 99, cb = b.category?.rawValue ?? 99
            if ca != cb { return ca < cb }
            if a.family != b.family { return a.family.localizedStandardCompare(b.family) == .orderedAscending }
            return a.typeName.localizedStandardCompare(b.typeName) == .orderedAscending
        }
    }

    /// The BOM's total cost.
    public static func bomTotal(_ m: BIMModel) -> Double { bom(m).reduce(0) { $0 + $1.totalCost } }

    /// Electronics in the document with their power.
    public static func power(_ m: BIMModel) -> [ComponentPowerLine] {
        m.elements(.furnitureHardware).filter { !$0.isType }.sorted { $0.id < $1.id }.compactMap { e in
            guard let d = ComponentDocument.definition(of: e, m), let el = d.electrical else { return nil }
            let ev = FamilyInstanceGeometry.evaluate(e, m) ?? ComponentChecks.evaluated(d, typeName: m[e.typeID]?.name)
            func num(_ n: String) -> Double {
                if case .quantity(let v, _)? = ev.values[n] { return v }
                return 0
            }
            var w = num(el.powerParameter)
            if el.perFoot { w *= num("Length") / 0.3048 }
            return ComponentPowerLine(elementID: e.id, family: d.name, typeName: m[e.typeID]?.name ?? "", supply: el.supply, volts: num(el.voltageParameter),
                                      watts: w, cable: el.cable)
        }
    }

    /// Total watts by voltage ("12 V": 36), and the driver size low-voltage circuits need (20% headroom, standard sizes).
    public static func powerSummary(_ m: BIMModel) -> [(supply: String, watts: Double, driver: Double?)] {
        var by: [Double: Double] = [:], supplies: [Double: Set<String>] = [:]
        for l in power(m) {
            let v = (l.volts * 10).rounded() / 10
            by[v, default: 0] += l.watts
            supplies[v, default: []].insert(l.supply)
        }
        let sizes: [Double] = [15, 30, 36, 60, 100, 150, 200, 300]
        return by.keys.sorted().map { v in
            let w = by[v] ?? 0
            // Named by the supply when every line on that voltage says the same ("DC 12 V"), else by the voltage.
            let label = supplies[v].flatMap { $0.count == 1 ? $0.first : nil } ?? "\(LX.num(v)) V"
            return (label, w, v > 0 && v <= 48 ? sizes.first { $0 >= w * 1.2 } ?? (w * 1.2).rounded(.up) : nil)
        }
    }
}
