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
            // Family (x, y) on the mount face → model; the drill axis goes into the host.
            func at(_ x: Double, _ y: Double) -> Vec3 {
                switch d.frame {
                case .face: return w.apply(Vec3(x, y, 0))
                default:
                    let o = w.apply(.zero)
                    return o + f.u * x + f.v * y
                }
            }
            let into = -f.n
            let target = { (t: ComponentMountTarget, p: Vec3) -> ElementID in t == .host ? host.id : counterpart(host, near: p, m) ?? host.id }
            for op in d.mounting {
                switch op {
                case .drill(let label, let x, let y, let dia, let depth, let through, let t):
                    let c = at(v(x), v(y))
                    out.append(MachiningEntry(partID: target(t, c), op: .drill(center: c, axis: into, diameter: v(dia), depth: through ? f.thickness : v(depth)),
                                              source: .hardware(e.id), label: label))
                case .pocket(let label, let x, let y, let wd, let ht, let depth, let through, let t):
                    let c = (v(x), v(y)), hw = v(wd) / 2, hh = v(ht) / 2
                    let outline = [at(c.0 - hw, c.1 - hh), at(c.0 + hw, c.1 - hh), at(c.0 + hw, c.1 + hh), at(c.0 - hw, c.1 + hh)]
                    out.append(MachiningEntry(partID: target(t, outline[0]), op: .pocket(outline: outline, axis: into, depth: through ? f.thickness : v(depth)),
                                              source: .hardware(e.id), label: label))
                case .groove(let label, let x0, let y0, let x1, let y1, let wd, let depth, let t):
                    let a = at(v(x0), v(y0)), b = at(v(x1), v(y1))
                    out.append(MachiningEntry(partID: target(t, a), op: .groove(start: a, end: b, axis: into, width: v(wd), depth: v(depth)),
                                              source: .hardware(e.id), label: label))
                case .edgeDrill(let label, let x, let z, let dia, let depth, let t):
                    let c = at(v(x), 0) + f.n * v(z)
                    out.append(MachiningEntry(partID: target(t, c), op: .drill(center: c, axis: -f.v, diameter: v(dia), depth: v(depth)),
                                              source: .hardware(e.id), label: label))
                }
            }
        }
        return out
    }

    /// The part across the gap from a host near a point: a front's or bay's side part on that side.
    static func counterpart(_ host: Element, near p: Vec3, _ m: BIMModel) -> ElementID? {
        let bay = host.furnitureBay ?? m[host.hostID]?.furnitureBay
        guard let b = bay, let o = b.opening else { return nil }
        let local = BayFrame(b).local(p)
        return abs(local.x - o.x0) <= abs(local.x - o.x1) ? (o.left ?? o.right) : (o.right ?? o.left)
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

    /// Total watts by supply ("DC 12 V": 36), and the driver size each needs (20% headroom, standard sizes).
    public static func powerSummary(_ m: BIMModel) -> [(supply: String, watts: Double, driver: Double?)] {
        var by: [String: Double] = [:]
        for l in power(m) { by[l.supply, default: 0] += l.watts }
        let sizes: [Double] = [15, 30, 36, 60, 100, 150, 200, 300]
        return by.keys.sorted().map { s in
            let w = by[s] ?? 0
            let low = s.hasPrefix("DC")
            return (s, w, low ? sizes.first { $0 >= w * 1.2 } ?? (w * 1.2).rounded(.up) : nil)
        }
    }
}
