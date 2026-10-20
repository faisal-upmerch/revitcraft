import Foundation
import ArcusGeometry

// FM7: what fabrication outputs read (Docs/FurnitureMode.md §3 "Fabrication outputs"): the cut list (every part and
// derived part at its cut size, from FurnitureJoints.cutSize and FurnitureMachining.derivedParts), material, banding
// and hardware costs, the edge banding takeoff and the nesting groups. Everything is computed from the model and
// cached per model state; nothing is stored. Schedules (FabricationSchedules), nesting views, CNC export and Check
// Parts read it.

/// One line of the cut list: a part (or a derived piece such as a drawer box side) at its cut size.
public struct CutPart: Hashable, Sendable {
    /// Unique within the model state: the element id, or the derived part's key.
    public var key: String
    public var mark: String
    /// What it is: Panel, Shelf, Leg… or a derived piece's name ("D1 Box Side").
    public var name: String
    public var typeName: String
    /// The element (or, for derived pieces, the element it belongs to).
    public var elementID: ElementID
    public var isDerived: Bool
    public var materialID: ElementID?
    /// The face material (veneer, laminate) when it differs from the core.
    public var faceMaterialID: ElementID?
    public var length: Double
    public var width: Double
    public var thickness: Double
    public var grain: GrainDirection
    public var banding: EdgeBanding
    public var bandingMaterialID: ElementID?
    public var bandingThickness: Double
    public var quantity: Int

    /// Banded edge length of all pieces.
    public var bandingLength: Double {
        Double(quantity) * ((banding.l1 ? length : 0) + (banding.l2 ? length : 0) + (banding.w1 ? width : 0) + (banding.w2 ? width : 0))
    }
    /// Face area of all pieces.
    public var area: Double { length * width * Double(quantity) }
}

/// A hardware line: a placed instance, or the fasteners the joints use.
public struct HardwareItem: Hashable, Sendable {
    public var key: String
    /// The instance, or the hardware type the joint fasteners map to (nil when the library has none).
    public var elementID: ElementID?
    public var typeID: ElementID?
    public var family: String
    public var typeName: String
    public var kind: String
    public var count: Int
    public var unitCost: Double
    public var manufacturer: String
    public var model: String
    public var description: String
    /// "Fronts" (placed with doors and drawers), "Joints" (fasteners), or "Placed" (by the user).
    public var source: String
    public var totalCost: Double { unitCost * Double(count) }
}

/// The parts of one material and thickness laid out on their stock.
public struct NestingGroup: Hashable, Sendable {
    /// "<material id>|<thickness in 1/64 in>": what a nesting view shows.
    public var key: String
    public var materialID: ElementID?
    public var thickness: Double
    public var size: StockSheetSize
    public var result: NestResult
    /// The cut part each placement came from (placement key → part key).
    public var partKeys: [String: String]
    /// "Plywood 3/4\"".
    public var title: String
}

public enum FurnitureFabrication {
    /// The material the 5' x 5' default stock size is for.
    public static let balticBirch = "Baltic Birch Plywood"
    static let inch = 0.0254, foot = 0.3048

    // MARK: Cut list

    /// Every part and derived part of a Furniture document at its cut size, in element order (cached).
    public static func parts(_ m: BIMModel) -> [CutPart] {
        guard m.isFurniture else { return [] }
        return FabricationCache.shared.value(m.contentStamp, \.parts) { computeParts(m) }
    }

    static func computeParts(_ m: BIMModel) -> [CutPart] {
        var out: [CutPart] = []
        let cats = Category.furnitureParts.filter { $0 != .furnitureEdgeProfiles }
        for e in m.elements(cats).sorted(by: { $0.id < $1.id }) where !e.isType {
            guard let kind = e.furniturePartKind, let size = FurnitureJoints.cutSize(of: e.id, in: m) else { continue }
            let tv = FurniturePartTypes.values(of: e, m)
            var banding = EdgeBanding.none, grain = GrainDirection.length
            var material = tv.material, face = tv.faceMaterial
            switch e.data {
            case .furniturePanel(let p): banding = p.banding ?? tv.banding; grain = tv.grain
            case .furnitureShelf: banding = tv.banding; grain = tv.grain
            case .furnitureForm(let f): material = f.materialID ?? material; grain = .none; face = nil
            default: break
            }
            if tv.edgeMaterial == nil && tv.edgeThickness <= 0 { banding = .none }
            out.append(CutPart(key: "\(e.id.raw)", mark: e.mark.isEmpty ? "\(kind.markPrefix)?" : e.mark, name: kind.rawValue,
                               typeName: m[e.typeID]?.name ?? "", elementID: e.id, isDerived: false, materialID: material,
                               faceMaterialID: face != material ? face : nil, length: size.length, width: size.width, thickness: size.thickness,
                               grain: grain, banding: banding, bandingMaterialID: banding == .none ? nil : tv.edgeMaterial,
                               bandingThickness: tv.edgeThickness, quantity: FurniturePartMeshes.count(e)))
        }
        var counter: [ElementID: Int] = [:]
        for d in FurnitureMachining.derivedParts(m) {
            let src = m[d.sourceID]
            let k = counter[d.sourceID, default: 0] + 1
            counter[d.sourceID] = k
            let base = src.map { $0.mark.isEmpty ? "X\($0.id.raw)" : $0.mark } ?? "X"
            let banding = d.banding ?? .none
            let edge = src.flatMap { FurniturePartTypes.values(of: $0, m).edgeMaterial }
            out.append(CutPart(key: d.key, mark: "\(base)-\(k)", name: d.name, typeName: src.flatMap { m[$0.typeID]?.name } ?? "", elementID: d.sourceID,
                               isDerived: true, materialID: d.materialID, faceMaterialID: nil,
                               length: max(d.length, d.width), width: min(d.length, d.width), thickness: d.thickness,
                               grain: d.length >= d.width ? d.grain : flipped(d.grain), banding: banding,
                               bandingMaterialID: banding == .none ? nil : edge, bandingThickness: 0, quantity: d.quantity))
        }
        return out
    }

    static func flipped(_ g: GrainDirection) -> GrainDirection { g == .length ? .width : (g == .width ? .length : .none) }

    // MARK: Costs

    /// The cost of `quantity` pieces of `material` at this size, by the material's cost unit: a sheet's share by area
    /// (the stock size's cost or the material's, per sheet), ft², board feet, linear feet or each.
    public static func materialCost(_ material: ElementID?, length: Double, width: Double, thickness: Double, quantity: Int, _ m: BIMModel) -> Double {
        guard let mid = material, let md = m[mid]?.material, let unit = md.costUnit else { return 0 }
        let q = Double(quantity)
        switch unit {
        case .sheet:
            let s = m.stockSheets.size(material: mid, thickness: thickness)
            let area = s.length * s.width
            return area > 0 ? (s.cost ?? md.cost) * length * width * q / area : 0
        case .squareFoot: return md.cost * length * width * q / (foot * foot)
        case .boardFoot: return md.cost * (length / inch) * (width / inch) * (thickness / inch) / 144 * q
        case .linearFoot: return md.cost * length / foot * q
        case .each: return md.cost * q
        }
    }

    /// Cost of a part's banding (the edge material's cost per linear foot).
    public static func bandingCost(_ p: CutPart, _ m: BIMModel) -> Double {
        guard let mid = p.bandingMaterialID, let md = m[mid]?.material else { return 0 }
        return md.costUnit == .linearFoot || md.costUnit == nil ? md.cost * p.bandingLength / foot : 0
    }

    /// Core and face material of a part (no banding).
    public static func materialCost(_ p: CutPart, _ m: BIMModel) -> Double {
        materialCost(p.materialID, length: p.length, width: p.width, thickness: p.thickness, quantity: p.quantity, m)
            + (p.faceMaterialID.map { materialCost($0, length: p.length, width: p.width, thickness: 0, quantity: p.quantity, m) } ?? 0)
    }

    /// Material and banding of a part: the Part List's Cost.
    public static func cost(_ p: CutPart, _ m: BIMModel) -> Double { materialCost(p, m) + bandingCost(p, m) }

    /// Whether a material is sheet goods (priced per sheet, or given a stock size of its own): what nesting lays out.
    public static func isSheetGoods(_ material: ElementID?, _ m: BIMModel) -> Bool {
        guard let mid = material else { return false }
        if m[mid]?.material?.costUnit == .sheet { return true }
        return m.stockSheets.sizes.contains { $0.materialID == mid }
    }

    // MARK: Hardware

    /// Every hardware line: placed Furniture Hardware instances (one per instance) and the joints' fasteners mapped to
    /// the Dowel, Cam Lock and Bolt, Shelf Pin and Confirmat Screw types (cached).
    public static func hardware(_ m: BIMModel) -> [HardwareItem] {
        guard m.isFurniture else { return [] }
        return FabricationCache.shared.value(m.contentStamp, \.hardware) { computeHardware(m) }
    }

    static func identity(_ td: TypeData?, _ key: String) -> String { td?.params[ParameterID("type.\(key)")]?.textValue ?? "" }

    static func computeHardware(_ m: BIMModel) -> [HardwareItem] {
        var out: [HardwareItem] = []
        for h in m.elements(.furnitureHardware).sorted(by: { $0.id < $1.id }) where !h.isType {
            let td = m.typeData(of: h)
            let hv = FurnitureHardware.Values(td)
            let owned = h.params[FurnitureHardware.ownerParam] != nil || h.params[FurnitureHardware.slotParam] != nil
            out.append(HardwareItem(key: "\(h.id.raw)", elementID: h.id, typeID: h.typeID, family: td?.familyName ?? "", typeName: m[h.typeID]?.name ?? "",
                                    kind: hv.kind?.rawValue ?? "", count: 1, unitCost: hv.cost, manufacturer: identity(td, "manufacturer"),
                                    model: identity(td, "model"), description: identity(td, "description"), source: owned ? "Fronts" : "Placed"))
        }
        for (name, count) in FurnitureJoints.hardwareCounts(m) {
            let (family, typeName, fallback) = jointHardware(name)
            let typeID = family.flatMap { f in typeName.flatMap { FurnitureHardware.type(f, $0, m) } ?? m.types(for: .furnitureHardware).first { $0.typeData?.familyName == f }?.id }
            let td = m[typeID]?.typeData
            let hv = FurnitureHardware.Values(td)
            out.append(HardwareItem(key: "joint/\(name)", elementID: typeID, typeID: typeID, family: td?.familyName ?? family ?? name,
                                    typeName: typeID.flatMap { m[$0]?.name } ?? (FurnitureJointFasteners.fastener(named: name) != nil ? typeName : nil) ?? name, // COMPB
                                    kind: hv.kind?.rawValue ?? "Fastener", count: count,
                                    unitCost: td != nil ? hv.cost : fallback, manufacturer: td != nil ? identity(td, "manufacturer") : "Generic",
                                    model: identity(td, "model"), description: td != nil ? identity(td, "description") : name, source: "Joints"))
        }
        return out
    }

    /// The hardware family and type a joint fastener name maps to, and a unit cost when there's no type.
    static func jointHardware(_ name: String) -> (family: String?, type: String?, cost: Double) {
        if let f = FurnitureJointFasteners.fastener(named: name) { return (f.family, f.typeName, f.cost) } // COMPB: a connector component
        if name.hasPrefix("Dowel") {
            // "Dowel 5/16\" x 1 3/16\"" → the 8 x 30 mm type; other sizes pick the nearest by name.
            let sizes: [(String, String)] = [("1/4\" x 1 3/16\"", "6 x 30 mm"), ("5/16\" x 1 3/16\"", "8 x 30 mm"), ("5/16\" x 1 9/16\"", "8 x 40 mm"),
                                             ("3/8\" x 1 9/16\"", "10 x 40 mm"), ("3/8\" x 1 5/8\"", "10 x 40 mm")]
            let t = sizes.first { name.hasSuffix($0.0) }?.1 ?? "8 x 30 mm"
            return (FurnitureHardware.dowel, t, 0.04)
        }
        if name.hasPrefix("Cam Lock") { return (FurnitureHardware.camLock, "15 mm", 0.45) }
        if name.hasPrefix("Confirmat") { return (FurnitureHardware.confirmat, "7 x 50 mm", 0.10) }
        if name.hasPrefix("Shelf Pin") { return (FurnitureHardware.shelfPin, name.contains("6 mm") ? "1/4\" Spoon" : "5 mm Spoon", 0.08) }
        if name.hasPrefix("Pocket Screw") { return (nil, nil, 0.05) }
        if name.hasPrefix("Biscuit") { return (nil, nil, 0.06) }
        return (nil, nil, 0)
    }

    // MARK: Nesting

    /// The sheet-goods parts grouped by material and thickness and nested on their stock (cached).
    public static func nesting(_ m: BIMModel) -> [NestingGroup] {
        guard m.isFurniture else { return [] }
        return FabricationCache.shared.value(m.contentStamp, \.nesting) { computeNesting(m) }
    }

    /// The key of a material and thickness (thickness to 1/64").
    public static func groupKey(_ material: ElementID?, _ thickness: Double) -> String {
        "\(material?.raw ?? 0)|\(Int((thickness / inch * 64).rounded()))"
    }

    static func computeNesting(_ m: BIMModel) -> [NestingGroup] {
        let settings = m.stockSheets
        var groups: [String: [CutPart]] = [:], order: [String] = []
        for p in parts(m) where isSheetGoods(p.materialID, m) {
            let k = groupKey(p.materialID, p.thickness)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(p)
        }
        func sortKey(_ k: String) -> (String, Double) {
            let p = groups[k]![0]
            return (m[p.materialID]?.name ?? "", -p.thickness)
        }
        order.sort { a, b in let x = sortKey(a), y = sortKey(b); return x.0 != y.0 ? x.0.localizedStandardCompare(y.0) == .orderedAscending : x.1 < y.1 }
        return order.map { k in
            let ps = groups[k]!
            let size = settings.size(material: ps[0].materialID, thickness: ps[0].thickness)
            var items: [NestItem] = [], keys: [String: String] = [:]
            for p in ps {
                for i in 0..<max(1, p.quantity) {
                    let key = p.quantity > 1 ? "\(p.key)#\(i + 1)" : p.key
                    items.append(NestItem(key: key, label: p.mark, length: p.length, width: p.width, grain: p.grain))
                    keys[key] = p.key
                }
            }
            let result = NestingEngine.nest(items, on: settings.stock(size), method: settings.method)
            let title = "\(m[ps[0].materialID]?.name ?? "No Material") \(FurnitureSizeText.inches(ps[0].thickness))"
            return NestingGroup(key: k, materialID: ps[0].materialID, thickness: ps[0].thickness, size: size, result: result, partKeys: keys, title: title)
        }
    }

    /// Sheets the nesting uses per material (all thicknesses).
    public static func sheetCount(material: ElementID?, _ m: BIMModel) -> Int {
        nesting(m).filter { $0.materialID == material }.reduce(0) { $0 + $1.result.sheets.count }
    }

    // MARK: Edge banding

    /// One banded part's banding: its edge material and length.
    public struct BandingItem: Hashable, Sendable {
        public var part: CutPart
        public var materialID: ElementID?
        public var length: Double
        public var cost: Double
    }

    /// The banding of every banded part.
    public static func banding(_ m: BIMModel) -> [BandingItem] {
        parts(m).filter { $0.banding != .none && $0.bandingLength > 0 }.map { p in
            BandingItem(part: p, materialID: p.bandingMaterialID, length: p.bandingLength, cost: bandingCost(p, m))
        }
    }
}

/// Fabrication results per model state (a few recent states).
final class FabricationCache: @unchecked Sendable {
    struct Entry { var parts: [CutPart]?; var hardware: [HardwareItem]?; var nesting: [NestingGroup]? }
    static let shared = FabricationCache()
    private let lock = NSLock()
    private var entries: [(UInt64, Entry)] = []

    func value<T>(_ stamp: UInt64, _ path: WritableKeyPath<Entry, T?>, _ make: () -> T) -> T {
        lock.lock()
        if let e = entries.first(where: { $0.0 == stamp })?.1, let v = e[keyPath: path] { lock.unlock(); return v }
        lock.unlock()
        let v = make()
        lock.lock(); defer { lock.unlock() }
        if let i = entries.firstIndex(where: { $0.0 == stamp }) {
            entries[i].1[keyPath: path] = v
        } else {
            var e = Entry()
            e[keyPath: path] = v
            entries.insert((stamp, e), at: 0)
            if entries.count > 6 { entries.removeLast() }
        }
        return v
    }
}
