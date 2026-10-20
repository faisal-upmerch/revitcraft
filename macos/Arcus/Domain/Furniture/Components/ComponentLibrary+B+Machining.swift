import Foundation
import ArcusGeometry

// COMPB: machining of Group B's bay items (rods, rails, pull-outs, baskets, turntables, towers, carousels) that the
// kit's mounting data (family x, y on the mount face) can't say: screws into the bay's sides at a depth and a height.
// The definitions write them as counterpart drills (x along the depth, y up from the bay's bottom); they're taken out
// of the definitions' mounting (`withoutBaySideDrills`) and drilled here in the left side and, mirrored, the right
// side (one-sided racks: the left only), with the bottom and top screws of the items that have them.

extension ComponentLibrary {
    /// Group B's family names (cached).
    static let groupBNames: Set<String> = Set(groupB.map(\.name))

    /// The side screws of each bay item (its counterpart drills as written), by family name.
    static let baySideDrills: [String: [ComponentMountOp]] = {
        var out: [String: [ComponentMountOp]] = [:]
        for d in groupBRaw where d.frame == .legacyOpening {
            let ops = d.mounting.filter { if case .drill(_, _, _, _, _, _, .counterpart) = $0 { return true }; return false }
            if !ops.isEmpty { out[d.name] = ops }
        }
        return out
    }()

    /// A bay item without its side screws in the kit's mounting data (they're drilled by `compbMachining`).
    static func withoutBaySideDrills(_ d: ComponentDefinition) -> ComponentDefinition {
        guard d.frame == .legacyOpening else { return d }
        var out = d
        out.mounting = d.mounting.filter { if case .drill(_, _, _, _, _, _, .counterpart) = $0 { return false }; return true }
        return out
    }

    /// Bay items mounted on the left side only.
    static let oneSidedBayItems: Set<String> = ["Pull-Out Trouser Rack", "Pull-Out Tie Rack", "Belt Organizer", "Scarf Organizer", "Bag Organizer", "Corner Shelf System"]

    /// A screw into the bay's bottom or top: x across the bay from its left, y into its depth (expressions).
    struct BaySurfaceDrill: Sendable {
        enum Surface: Sendable { case bottom, top }
        var surface: Surface
        var label: String
        var x: String
        var y: String
        var diameter: Double
        var depth: Double
    }

    /// The bottom and top screws of the bay items that have them.
    static let baySurfaceDrills: [String: [BaySurfaceDrill]] = {
        var out: [String: [BaySurfaceDrill]] = [:]
        out["Rotating Shelf"] = (0..<4).map { k in
            let a = Double(k) * .pi / 2
            return BaySurfaceDrill(surface: .bottom, label: "Turntable screw", x: "Opening Width / 2 + Bearing Diameter * \(LX.num(0.4 * cos(a)))",
                                   y: "Opening Depth / 2 + Bearing Diameter * \(LX.num(0.4 * sin(a)))", diameter: 0.003, depth: 0.010)
        }
        out["Wardrobe Divider"] = ["Opening Depth * 0.25", "Opening Depth * 0.75"].map {
            BaySurfaceDrill(surface: .bottom, label: "Divider bracket screw", x: "Divider Position + 0.012 m", y: $0, diameter: 0.0035, depth: 0.013)
        }
        out["Pull-Out Storage Tower"] = ["0.2", "0.8"].flatMap { f in
            [BaySurfaceDrill(surface: .bottom, label: "Tower slide screw", x: "Opening Width / 2", y: "0.02 m + Tower Depth * \(f)", diameter: 0.004, depth: 0.012),
             BaySurfaceDrill(surface: .top, label: "Tower guide screw", x: "Opening Width / 2", y: "0.02 m + Tower Depth * \(f)", diameter: 0.004, depth: 0.012)]
        }
        out["Rotating Wardrobe Carousel"] = [
            BaySurfaceDrill(surface: .bottom, label: "Pole flange screw", x: "Opening Width / 2", y: "Opening Depth / 2", diameter: 0.005, depth: 0.020),
            BaySurfaceDrill(surface: .top, label: "Pole bearing screw", x: "Opening Width / 2", y: "Opening Depth / 2", diameter: 0.005, depth: 0.020),
        ]
        out["Corner Wardrobe System"] = [
            BaySurfaceDrill(surface: .top, label: "Corner hanger screw", x: "Rail Setback", y: "Opening Depth - Rail Setback", diameter: 0.004, depth: 0.013),
        ]
        return out
    }()
}

extension FurnitureMachining {
    /// COMPB: side, bottom and top holes of Group B's bay items.
    static func compbMachining(_ m: BIMModel) -> [MachiningEntry] {
        var out: [MachiningEntry] = []
        for e in ComponentChecks.placed(m) {
            guard let d = ComponentDocument.definition(of: e, m), d.frame == .legacyOpening, ComponentLibrary.groupBNames.contains(d.name),
                  let bay = m[e.hostID]?.furnitureBay, let o = bay.opening else { continue }
            let ev = FamilyInstanceGeometry.evaluate(e, m) ?? ComponentChecks.evaluated(d, typeName: m[e.typeID]?.name)
            func v(_ x: String) -> Double { ComponentChecks.value(x, ev) ?? 0 }
            let fr = BayFrame(bay)
            let lift = ComponentSettings(e)?.offsetY ?? 0
            let sides: [(ElementID?, Double, Double)] = ComponentLibrary.oneSidedBayItems.contains(d.name) ? [(o.left, o.x0, -1)] : [(o.left, o.x0, -1), (o.right, o.x1, 1)]
            for op in ComponentLibrary.baySideDrills[d.name] ?? [] {
                guard case .drill(let label, let x, let y, let dia, let depth, _, _) = op else { continue }
                for (part, sx, dir) in sides {
                    guard let part else { continue }
                    let c = fr.world(Vec3(sx, o.y0 + v(x), o.z0 + lift + v(y)))
                    out.append(MachiningEntry(partID: part, op: .drill(center: c, axis: fr.world(Vec3(dir, 0, 0)), diameter: v(dia), depth: v(depth)), source: .hardware(e.id), label: label))
                }
            }
            for s in ComponentLibrary.baySurfaceDrills[d.name] ?? [] {
                let (part, z, axis) = s.surface == .bottom ? (o.bottom, o.z0, Vec3(0, 0, -1)) : (o.top, o.z1, Vec3(0, 0, 1))
                guard let part else { continue }
                let c = fr.world(Vec3(o.x0 + v(s.x), o.y0 + v(s.y), z))
                out.append(MachiningEntry(partID: part, op: .drill(center: c, axis: axis, diameter: s.diameter, depth: s.depth), source: .hardware(e.id), label: s.label))
            }
        }
        return out
    }
}
