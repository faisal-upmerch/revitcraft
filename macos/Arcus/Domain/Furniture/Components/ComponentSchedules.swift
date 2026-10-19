import Foundation
import ArcusGeometry

// COMP: the component schedules. The Hardware Schedule gains Component Category, Subcategory, SKU, Power and Supply
// fields; the Component BOM groups every hardware line by component category with counts and cost subtotals; the
// Power Summary lists the electronics by supply with total watts. They're ordinary fabrication schedules (Fields,
// Sorting/Grouping and Formatting work as usual).

public enum ComponentSchedules {
    public static let bomName = "Component BOM", powerName = "Power Summary"

    /// Fields added to the Hardware Schedule kind.
    static let hardwareFields: [(name: String, type: ParamType)] = [
        ("Component Category", .text), ("Subcategory", .text), ("SKU", .text), ("Power", .number), ("Supply", .text),
    ]

    /// The component values of a hardware line.
    static func hardwareValues(_ h: HardwareItem, _ m: BIMModel) -> [String: ParamValue] {
        let type = m[h.typeID]
        let d = type.flatMap { ComponentDocument.definition(of: $0, m) } ?? ComponentCatalog.current.definition(named: h.family)
        var out: [String: ParamValue] = [
            "Component Category": .text(d.map { "\($0.category.code) \($0.category.title)" } ?? "Other"),
            "Subcategory": .text(d?.subcategory ?? h.kind),
            "SKU": .text(type?.typeData?.params[ComponentKit.skuParam]?.textValue ?? ""),
            "Power": .double(0), "Supply": .text(""),
        ]
        if let id = h.elementID, m[id]?.isType == false, let p = ComponentFabrication.power(m).first(where: { $0.elementID == id }) {
            out["Power"] = .double(p.watts * Double(h.count))
            out["Supply"] = .text(p.supply)
        }
        return out
    }

    /// The Component BOM: by category, then family and type, with count and cost subtotals per category.
    public static func bom() -> ScheduleDefinition {
        let k = ScheduleKind.hardwareSchedule
        typealias F = FabricationSchedules
        var d = ScheduleDefinition(kind: k, categories: [.furnitureHardware], fields: [
            F.field("Component Category", k, 0.04, hidden: true), F.field("Family", k, 0.045), F.field("Type", k, 0.03), F.field("SKU", k, 0.022),
            F.field("Count", k, 0.012, total: true), F.field("Unit Cost", k, 0.018), F.field("Total Cost", k, 0.02, total: true),
            F.field("Manufacturer", k, 0.02),
        ])
        func id(_ n: String) -> String { d.fields.first { $0.heading == n }!.id }
        var group = ScheduleSort(fieldID: id("Component Category"), header: true, footer: true, blankLine: false)
        group.footerShowsTitleCountTotals = true
        d.sorting = [group, ScheduleSort(fieldID: id("Family")), ScheduleSort(fieldID: id("Type"))]
        d.itemizeEveryInstance = false
        d.grandTotals = true
        return d
    }

    /// The Power Summary: electronics by supply, with watts.
    public static func powerSummary() -> ScheduleDefinition {
        let k = ScheduleKind.hardwareSchedule
        typealias F = FabricationSchedules
        var d = ScheduleDefinition(kind: k, categories: [.furnitureHardware], fields: [
            F.field("Supply", k, 0.03, hidden: true), F.field("Family", k, 0.045), F.field("Type", k, 0.03), F.field("Count", k, 0.012, total: true),
            F.field("Power", k, 0.02, total: true),
        ])
        func id(_ n: String) -> String { d.fields.first { $0.heading == n }!.id }
        d.filters = [ScheduleFilter(fieldID: id("Power"), op: .greater, value: .double(0))]
        var group = ScheduleSort(fieldID: id("Supply"), header: true, footer: true, blankLine: false)
        group.footerShowsTitleCountTotals = true
        d.sorting = [group, ScheduleSort(fieldID: id("Family"))]
        d.itemizeEveryInstance = false
        d.grandTotals = true
        return d
    }

    /// The schedule named `name`, created when missing; returns its id.
    @discardableResult
    public static func ensure(_ name: String, in tx: TransactionContext) -> ElementID {
        if let e = tx.model.elements(.schedules).first(where: { $0.name == name && $0.schedule?.kind == .hardwareSchedule }) { return e.id }
        return tx.create(.schedules, name: name, data: .schedule(name == powerName ? powerSummary() : bom()))
    }
}
