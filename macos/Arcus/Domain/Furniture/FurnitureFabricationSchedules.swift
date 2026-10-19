import Foundation
import ArcusGeometry
import ArcusCalc

// FM7: the fabrication schedules (Docs/FurnitureMode.md §3 "Fabrication outputs"): Part List (cut list), Hardware
// Schedule, Edge Banding and Cost. They are ordinary schedule views (Fields, Filter, Sorting/Grouping, Formatting and
// Appearance work as for any schedule) whose rows come from the fabrication data rather than one per element: every
// part and derived part, every hardware line (placed instances and joint fasteners), every banded part, and the cost
// lines of the piece. Their fields are `.fabrication(name)` sources; identical rows group as with Itemize every
// instance off (Qty, Count, Area and Cost add up; Marks list). The Material Takeoff gains Cost, Cost Unit and Sheet
// Count fields (`.material(...)`).

/// One row of a fabrication schedule: its values by field name and the elements it selects.
public struct FabricationRow: Sendable {
    public var elementID: ElementID
    public var values: [String: ParamValue]
}

public enum FabricationSchedules {
    static let inch = 0.0254, foot = 0.3048

    /// Global parameters the Cost schedule reads (Manage ▸ Global Parameters).
    public static let laborHours = "Labor Hours", laborRate = "Labor Rate", markup = "Markup"

    /// Text fields that list their values when rows group ("P1, P2").
    public static let joinedFields: Set<String> = ["Mark"]
    /// Length fields shown in inches and fractions (cut sizes), not feet and inches.
    public static let inchFields: Set<String> = ["Cut Length", "Cut Width", "Thickness", "Banding Thickness"]

    /// The fields a fabrication schedule offers (name and type), in Fields dialog order.
    public static func fields(_ kind: ScheduleKind) -> [(name: String, type: ParamType)] {
        switch kind {
        case .partList:
            [("Mark", .text), ("Part", .text), ("Type", .text), ("Material", .text), ("Material and Thickness", .text), ("Thickness", .length),
             ("Cut Length", .length), ("Cut Width", .length), ("Grain", .text), ("Edge Banding", .text), ("L1", .bool), ("L2", .bool), ("W1", .bool),
             ("W2", .bool), ("Banding Material", .text), ("Banding Length", .length), ("Qty", .integer), ("Area", .area), ("Material Cost", .currency),
             ("Banding Cost", .currency), ("Cost", .currency), ("Derived", .bool)]
        case .hardwareSchedule:
            [("Family", .text), ("Type", .text), ("Kind", .text), ("Source", .text), ("Count", .integer), ("Unit Cost", .currency),
             ("Total Cost", .currency), ("Manufacturer", .text), ("Model", .text), ("Description", .text)]
        case .edgeBanding:
            [("Banding Material", .text), ("Banding Thickness", .length), ("Mark", .text), ("Part", .text), ("Edges", .text), ("Length", .length),
             ("Linear Feet", .number), ("Cost", .currency)]
        case .costSummary:
            [("Order", .integer), ("Category", .text), ("Item", .text), ("Basis", .text), ("Cost", .currency)]
        default: []
        }
    }

    /// The type of a fabrication field.
    public static func type(_ name: String, _ kind: ScheduleKind) -> ParamType { fields(kind).first { $0.name == name }?.type ?? .text }

    // MARK: Rows

    /// The rows of a fabrication schedule (empty outside Furniture documents).
    public static func rows(_ kind: ScheduleKind, _ m: BIMModel) -> [FabricationRow] {
        guard m.isFurniture else { return [] }
        switch kind {
        case .partList: return FurnitureFabrication.parts(m).map { partRow($0, m) }
        case .hardwareSchedule: return FurnitureFabrication.hardware(m).map { hardwareRow($0, m) }
        case .edgeBanding: return FurnitureFabrication.banding(m).map { bandingRow($0, m) }
        case .costSummary: return costRows(m)
        default: return []
        }
    }

    static func name(_ id: ElementID?, _ m: BIMModel) -> String { m[id]?.name ?? "" }

    static func partRow(_ p: CutPart, _ m: BIMModel) -> FabricationRow {
        let material = m[p.materialID]?.name ?? "No Material"
        let mc = FurnitureFabrication.materialCost(p, m), bc = FurnitureFabrication.bandingCost(p, m)
        return FabricationRow(elementID: p.elementID, values: [
            "Mark": .text(p.mark), "Part": .text(p.name), "Type": .text(p.typeName), "Material": .text(material),
            "Material and Thickness": .text("\(material) \(FurnitureSizeText.inches(p.thickness))"),
            "Thickness": .double(p.thickness), "Cut Length": .double(p.length), "Cut Width": .double(p.width), "Grain": .text(p.grain.rawValue),
            "Edge Banding": .text(p.banding.code), "L1": .bool(p.banding.l1), "L2": .bool(p.banding.l2), "W1": .bool(p.banding.w1), "W2": .bool(p.banding.w2),
            "Banding Material": .text(name(p.bandingMaterialID, m)), "Banding Length": .double(p.bandingLength), "Qty": .int(p.quantity),
            "Area": .double(p.area), "Material Cost": .double(mc), "Banding Cost": .double(bc), "Cost": .double(mc + bc), "Derived": .bool(p.isDerived),
        ])
    }

    static func hardwareRow(_ h: HardwareItem, _ m: BIMModel) -> FabricationRow {
        FabricationRow(elementID: h.elementID ?? m.projectInfoElement?.id ?? ElementID(0), values: [
            "Family": .text(h.family), "Type": .text(h.typeName), "Kind": .text(h.kind), "Source": .text(h.source), "Count": .int(h.count),
            "Unit Cost": .double(h.unitCost), "Total Cost": .double(h.totalCost), "Manufacturer": .text(h.manufacturer), "Model": .text(h.model),
            "Description": .text(h.description),
        ])
    }

    static func bandingRow(_ b: FurnitureFabrication.BandingItem, _ m: BIMModel) -> FabricationRow {
        FabricationRow(elementID: b.part.elementID, values: [
            "Banding Material": .text(m[b.materialID]?.name ?? "No Material"), "Banding Thickness": .double(b.part.bandingThickness), "Mark": .text(b.part.mark),
            "Part": .text(b.part.name), "Edges": .text(b.part.banding.code), "Length": .double(b.length), "Linear Feet": .double(b.length / foot),
            "Cost": .double(b.cost),
        ])
    }

    // MARK: Cost

    /// One line of the piece's cost.
    public struct CostLine: Hashable, Sendable {
        public var category: String
        public var item: String
        public var basis: String
        public var cost: Double
    }

    /// The piece's cost: materials (sheet goods by area or by sheets used, solid wood by board foot, the rest by their
    /// unit), edge banding by linear foot, hardware, labor (Labor Hours × Labor Rate) and Markup on the subtotal.
    public static func costLines(_ m: BIMModel) -> [CostLine] {
        guard m.isFurniture else { return [] }
        func money(_ v: Double) -> String { Parameters.format(.double(v), type: .currency, model: m) }
        func area(_ v: Double) -> String { Parameters.format(.double(v), type: .area, model: m) }
        func one(_ v: Double) -> String { String(format: "%.1f", v) }
        let parts = FurnitureFabrication.parts(m)
        let settings = m.stockSheets
        // Materials: core and face, by material.
        var byMaterial: [ElementID: (area: Double, volume: Double, length: Double, count: Int, cost: Double)] = [:]
        var order: [ElementID] = []
        func add(_ id: ElementID?, _ p: CutPart, face: Bool) {
            guard let id else { return }
            if byMaterial[id] == nil { order.append(id) }
            let c = FurnitureFabrication.materialCost(id, length: p.length, width: p.width, thickness: face ? 0 : p.thickness, quantity: p.quantity, m)
            var e = byMaterial[id] ?? (0, 0, 0, 0, 0)
            e.area += p.area; e.volume += p.area * p.thickness; e.length += p.length * Double(p.quantity); e.count += p.quantity; e.cost += c
            byMaterial[id] = e
        }
        for p in parts { add(p.materialID, p, face: false); add(p.faceMaterialID, p, face: true) }
        var lines: [CostLine] = []
        let nesting = FurnitureFabrication.nesting(m)
        for id in order {
            guard let md = m[id]?.material, let e = byMaterial[id] else { continue }
            let n = name(id, m)
            switch md.costUnit {
            case .sheet?:
                let groups = nesting.filter { $0.materialID == id }
                let sheets = groups.reduce(0) { $0 + $1.result.sheets.count }
                if settings.costBasis == .sheets, !groups.isEmpty {
                    let full = groups.reduce(0.0) { $0 + Double($1.result.sheets.count) * ($1.size.cost ?? md.cost) }
                    let over = groups.flatMap(\.result.oversize).reduce(0.0) { $0 + $1.area } // oversize parts still pay by area
                    let overCost = FurnitureFabrication.materialCost(id, length: over, width: 1, thickness: groups[0].thickness, quantity: 1, m)
                    lines.append(CostLine(category: "Sheet Goods", item: n, basis: "\(sheets) \(sheets == 1 ? "sheet" : "sheets") used", cost: full + overCost))
                } else {
                    lines.append(CostLine(category: "Sheet Goods", item: n, basis: "\(area(e.area)) (\(sheets) \(sheets == 1 ? "sheet" : "sheets") nested)", cost: e.cost))
                }
            case .boardFoot?:
                let bf = e.volume / (inch * inch * inch * 144)
                lines.append(CostLine(category: "Solid Wood", item: n, basis: "\(one(bf)) bd ft", cost: e.cost))
            case .squareFoot?:
                lines.append(CostLine(category: "Other Materials", item: n, basis: area(e.area), cost: e.cost))
            case .linearFoot?:
                lines.append(CostLine(category: "Other Materials", item: n, basis: "\(one(e.length / foot)) LF", cost: e.cost))
            case .each?:
                lines.append(CostLine(category: "Other Materials", item: n, basis: "\(e.count) each", cost: e.cost))
            case nil:
                lines.append(CostLine(category: "Other Materials", item: n, basis: "No cost unit", cost: 0))
            }
        }
        // Edge banding by material.
        var banding: [ElementID: (length: Double, cost: Double)] = [:], bandingOrder: [ElementID] = []
        for b in FurnitureFabrication.banding(m) {
            guard let id = b.materialID else { continue }
            if banding[id] == nil { bandingOrder.append(id) }
            banding[id, default: (0, 0)].length += b.length
            banding[id, default: (0, 0)].cost += b.cost
        }
        for id in bandingOrder {
            let e = banding[id]!
            lines.append(CostLine(category: "Edge Banding", item: name(id, m), basis: "\(one(e.length / foot)) LF", cost: e.cost))
        }
        // Hardware.
        let hw = FurnitureFabrication.hardware(m)
        if !hw.isEmpty {
            let count = hw.reduce(0) { $0 + $1.count }
            lines.append(CostLine(category: "Hardware", item: "Hardware", basis: "\(count) pieces", cost: hw.reduce(0) { $0 + $1.totalCost }))
        }
        // Labor and markup (global parameters).
        let hours = GlobalParameters.named(laborHours, m)?.value.doubleValue ?? 0
        let rate = GlobalParameters.named(laborRate, m)?.value.doubleValue ?? 0
        if hours > 0 || rate > 0 {
            lines.append(CostLine(category: "Labor", item: "Labor", basis: "\(one(hours)) h × \(money(rate))/h", cost: hours * rate))
        }
        let subtotal = lines.reduce(0) { $0 + $1.cost }
        let mk = GlobalParameters.named(markup, m)?.value.doubleValue ?? 0
        if mk != 0 {
            lines.append(CostLine(category: "Markup", item: "Markup", basis: "\(one(mk * 100))% of \(money(subtotal))",
                                  cost: subtotal * mk))
        }
        return lines
    }

    /// The piece's total cost (the Cost schedule's grand total).
    public static func pieceCost(_ m: BIMModel) -> Double { costLines(m).reduce(0) { $0 + $1.cost } }

    static func costRows(_ m: BIMModel) -> [FabricationRow] {
        let id = m.projectInfoElement?.id ?? ElementID(0)
        return costLines(m).enumerated().map { i, l in
            FabricationRow(elementID: id, values: ["Order": .int(i + 1), "Category": .text(l.category), "Item": .text(l.item), "Basis": .text(l.basis),
                                                   "Cost": .double(l.cost)])
        }
    }

    // MARK: Material Takeoff fields

    /// Material Takeoff fields FM7 adds (`.material(name)`): Cost, Cost Unit and Sheet Count.
    public static let takeoffFields: [(name: String, type: ParamType)] = [("Cost", .currency), ("Cost Unit", .text), ("Sheet Count", .integer)]

    /// The value of a Material Takeoff field FM7 adds, for one element's material quantity.
    static func takeoffValue(_ what: String, _ e: Element, _ q: MaterialQuantity, _ m: BIMModel) -> ParamValue? {
        let md = m[q.materialID]?.material
        switch what {
        case "Cost Unit": return md?.costUnit.map { .text($0.rawValue) }
        case "Sheet Count":
            guard m.isFurniture, FurnitureFabrication.isSheetGoods(q.materialID, m) else { return nil }
            return .int(FurnitureFabrication.sheetCount(material: q.materialID, m))
        case "Cost":
            guard let md, let unit = md.costUnit else { return nil }
            // Parts at their cut size; other elements from the quantity's area and volume.
            if let p = FurnitureFabrication.parts(m).first(where: { !$0.isDerived && $0.elementID == e.id }), p.materialID == q.materialID {
                return .double(FurnitureFabrication.materialCost(p.materialID, length: p.length, width: p.width, thickness: p.thickness, quantity: p.quantity, m))
            }
            switch unit {
            case .sheet:
                let s = m.stockSheets.size(material: q.materialID, thickness: q.area > 0 ? q.volume / q.area : 0)
                return .double(s.length * s.width > 0 ? (s.cost ?? md.cost) * q.area / (s.length * s.width) : 0)
            case .squareFoot: return .double(md.cost * q.area / (foot * foot))
            case .boardFoot: return .double(md.cost * q.volume / (inch * inch * inch * 144))
            case .linearFoot: return nil
            case .each: return .double(md.cost)
            }
        default: return nil
        }
    }

    // MARK: Default schedules

    static func field(_ name: String, _ kind: ScheduleKind, _ width: Double, total: Bool = false, align: HorizontalAlign? = nil, hidden: Bool = false) -> ScheduleField {
        let t = type(name, kind)
        var f = ScheduleField(source: .fabrication(name), heading: name, width: width, alignment: align ?? (t.isNumeric ? .right : .left))
        if total { f.total = .total }
        f.hidden = hidden
        return f
    }

    /// The Part List: grouped by material and thickness, identical parts on one row, with totals.
    public static func partList() -> ScheduleDefinition {
        let k = ScheduleKind.partList
        var d = ScheduleDefinition(kind: k, categories: [], fields: [
            field("Mark", k, 0.024), field("Part", k, 0.03), field("Material", k, 0.024), field("Thickness", k, 0.014, align: .right),
            field("Cut Length", k, 0.018), field("Cut Width", k, 0.018), field("Grain", k, 0.02), field("Edge Banding", k, 0.02),
            field("Banding Length", k, 0.018, total: true), field("Qty", k, 0.009, total: true), field("Area", k, 0.018, total: true),
            field("Cost", k, 0.017, total: true), field("Material and Thickness", k, 0.03, hidden: true),
        ])
        func id(_ n: String) -> String { d.fields.first { $0.heading == n }!.id }
        var group = ScheduleSort(fieldID: id("Material and Thickness"), header: true, footer: true, blankLine: false)
        group.footerShowsTitleCountTotals = true
        d.sorting = [ScheduleSort(fieldID: id("Material")), ScheduleSort(fieldID: id("Thickness"), ascending: false), group,
                     ScheduleSort(fieldID: id("Part")), ScheduleSort(fieldID: id("Cut Length"), ascending: false),
                     ScheduleSort(fieldID: id("Cut Width"), ascending: false), ScheduleSort(fieldID: id("Grain")), ScheduleSort(fieldID: id("Edge Banding"))]
        d.itemizeEveryInstance = false
        d.grandTotals = true
        return d
    }

    /// The Hardware Schedule: one row per hardware type with count and cost.
    public static func hardwareSchedule() -> ScheduleDefinition {
        let k = ScheduleKind.hardwareSchedule
        var d = ScheduleDefinition(kind: k, categories: [.furnitureHardware], fields: [
            field("Family", k, 0.045), field("Type", k, 0.03), field("Count", k, 0.012, total: true), field("Unit Cost", k, 0.018),
            field("Total Cost", k, 0.02, total: true), field("Manufacturer", k, 0.022), field("Model", k, 0.02), field("Kind", k, 0.02, hidden: true),
        ])
        func id(_ n: String) -> String { d.fields.first { $0.heading == n }!.id }
        d.sorting = [ScheduleSort(fieldID: id("Family")), ScheduleSort(fieldID: id("Type"))]
        d.itemizeEveryInstance = false
        d.grandTotals = true
        return d
    }

    /// Edge Banding: linear feet and cost by banding material.
    public static func edgeBanding() -> ScheduleDefinition {
        let k = ScheduleKind.edgeBanding
        var d = ScheduleDefinition(kind: k, categories: [], fields: [
            field("Banding Material", k, 0.04), field("Mark", k, 0.06), field("Linear Feet", k, 0.02, total: true), field("Cost", k, 0.02, total: true),
        ])
        d.fields[2].decimals = 1
        d.sorting = [ScheduleSort(fieldID: d.fields[0].id)]
        d.itemizeEveryInstance = false
        d.grandTotals = true
        return d
    }

    /// Cost: materials, banding, hardware, labor and markup, totalled as the piece cost.
    public static func costSummary() -> ScheduleDefinition {
        let k = ScheduleKind.costSummary
        var d = ScheduleDefinition(kind: k, categories: [], fields: [
            field("Order", k, 0.01, hidden: true), field("Category", k, 0.03), field("Item", k, 0.04), field("Basis", k, 0.05),
            field("Cost", k, 0.022, total: true),
        ])
        d.sorting = [ScheduleSort(fieldID: d.fields[0].id)]
        d.grandTotals = true
        d.grandTotalTitle = "Piece Cost"
        return d
    }

    /// The furniture Material Takeoff: area, cost and sheets by material.
    public static func materialTakeoff() -> ScheduleDefinition {
        var d = ScheduleDefinition(kind: .materialTakeoff, categories: Category.furnitureParts.filter { $0 != .furnitureEdgeProfiles } + [.furnitureFronts], fields: [
            ScheduleField(source: .material("Name"), heading: "Material", width: 0.04),
            ScheduleField(source: .material("Area"), heading: "Area", width: 0.022, alignment: .right),
            ScheduleField(source: .material("Volume"), heading: "Volume", width: 0.022, alignment: .right),
            ScheduleField(source: .material("Cost Unit"), heading: "Cost Unit", width: 0.022),
            ScheduleField(source: .material("Sheet Count"), heading: "Sheet Count", width: 0.016, alignment: .right),
            ScheduleField(source: .material("Cost"), heading: "Cost", width: 0.02, alignment: .right),
        ])
        d.fields[1].total = .total; d.fields[2].total = .total; d.fields[5].total = .total
        d.sorting = [ScheduleSort(fieldID: d.fields[0].id)]
        d.itemizeEveryInstance = false
        d.grandTotals = true
        return d
    }
}

// MARK: - Fields dialog

extension FabricationSchedules {
    static let entryPrefix = "fabrication:", materialPrefix = "material:"

    /// What Schedule Properties ▸ Fields offers beyond element parameters: a fabrication schedule's fields, and a
    /// Material Takeoff's material fields (Name, Area, Volume, Cost, Cost Unit, Sheet Count).
    public static func availableEntries(_ kind: ScheduleKind) -> [ParameterEntry] {
        func entry(_ id: String, _ name: String, _ t: ParamType) -> ParameterEntry {
            ParameterEntry(id: ParameterID(id), name: name, type: t, group: .other, isType: false, isReadOnly: true, value: nil, formula: nil,
                           tooltip: "Calculated from the parts.", readOnlyReason: "Calculated from the parts.")
        }
        if kind == .materialTakeoff {
            return ([("Name", ParamType.text), ("Area", .area), ("Volume", .volume)] + takeoffFields.map { ($0.name, $0.type) })
                .map { entry(materialPrefix + $0.0, "Material: \($0.0)", $0.1) }
        }
        return fields(kind).map { entry(entryPrefix + $0.name, $0.name, $0.type) }
    }

    /// The schedule field for one of `availableEntries`, or nil for an element parameter.
    public static func field(for entry: ParameterEntry, _ kind: ScheduleKind) -> ScheduleField? {
        let k = entry.id.key
        if k.hasPrefix(entryPrefix) { return field(String(k.dropFirst(entryPrefix.count)), kind, entry.type.isNumeric ? 0.02 : 0.03) }
        if k.hasPrefix(materialPrefix) {
            let n = String(k.dropFirst(materialPrefix.count))
            return ScheduleField(source: .material(n), heading: n == "Name" ? "Material" : n, width: entry.type.isNumeric ? 0.022 : 0.03,
                                 alignment: entry.type.isNumeric ? .right : .left)
        }
        return nil
    }

    /// Whether a definition already schedules `entry`.
    public static func schedules(_ def: ScheduleDefinition, _ entry: ParameterEntry) -> Bool {
        let k = entry.id.key
        return def.fields.contains { f in
            switch f.source {
            case .fabrication(let n): return k == entryPrefix + n
            case .material(let n): return k == materialPrefix + n
            default: return false
            }
        }
    }
}
