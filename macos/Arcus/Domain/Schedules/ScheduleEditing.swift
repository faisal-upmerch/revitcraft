import Foundation
import ArcusCalc

// BL-SCHED: in-place cell editing, schedule definition edits (fields, filters, header groups) and appearance.

/// How a schedule is drawn on screen, on sheets and in PDF: grid lines, outline, text sizes and header shading.
public struct ScheduleAppearance: Hashable, Codable, Sendable {
    /// Vertical and horizontal lines between cells.
    public var gridLines: Bool
    /// Heavy frame around the table and under the headers.
    public var outline: Bool
    /// An empty row between the headers and the first data row.
    public var blankRowBeforeData: Bool
    /// Text heights on paper (meters).
    public var titleTextHeight: Double
    public var headerTextHeight: Double
    public var bodyTextHeight: Double
    public var boldTitle: Bool
    public var boldHeaders: Bool
    /// Background of the header row (nil = none).
    public var headerShading: RGBColor?
    public init(gridLines: Bool = true, outline: Bool = true, blankRowBeforeData: Bool = false, titleTextHeight: Double = 0.003,
                headerTextHeight: Double = 0.0022, bodyTextHeight: Double = 0.0022, boldTitle: Bool = true, boldHeaders: Bool = true,
                headerShading: RGBColor? = nil) {
        self.gridLines = gridLines; self.outline = outline; self.blankRowBeforeData = blankRowBeforeData
        self.titleTextHeight = titleTextHeight; self.headerTextHeight = headerTextHeight; self.bodyTextHeight = bodyTextHeight
        self.boldTitle = boldTitle; self.boldHeaders = boldHeaders; self.headerShading = headerShading
    }
}

/// A header cell spanning several adjacent columns ("grouped" or merged column headers).
public struct ScheduleHeaderGroup: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// Fields under the group, in schedule order.
    public var fieldIDs: [String]
    public init(title: String, fieldIDs: [String]) { id = UUID().uuidString; self.title = title; self.fieldIDs = fieldIDs }
}

/// A header group resolved against the visible columns of a computed table.
public struct ScheduleHeaderSpan: Hashable, Sendable {
    public var title: String
    public var columns: Range<Int>
    public var groupID: String
}

extension ScheduleDefinition {
    public var appearance: ScheduleAppearance {
        get { appearanceStorage ?? ScheduleAppearance() }
        set { appearanceStorage = newValue == ScheduleAppearance() ? nil : newValue }
    }

    public var headerGroups: [ScheduleHeaderGroup] {
        get { headerGroupStorage ?? [] }
        set { headerGroupStorage = newValue.isEmpty ? nil : newValue }
    }

    /// Removes a field together with the filters, sort levels and header group memberships that refer to it.
    public mutating func removeField(_ id: String) {
        fields.removeAll { $0.id == id }
        filters.removeAll { $0.fieldID == id }
        sorting.removeAll { $0.fieldID == id }
        headerGroups = headerGroups.compactMap { g in
            var g = g
            g.fieldIDs.removeAll { $0 == id }
            return g.fieldIDs.isEmpty ? nil : g
        }
    }

    /// Inserts a field before `beforeID` (or at the end).
    public mutating func insertField(_ f: ScheduleField, before beforeID: String? = nil) {
        if let beforeID, let i = fields.firstIndex(where: { $0.id == beforeID }) { fields.insert(f, at: i) } else { fields.append(f) }
    }

    /// Groups the given fields under one header (they need not be adjacent in `fields`; the table shows one span per
    /// contiguous run). Fields leave any group they were in.
    public mutating func groupHeaders(_ ids: [String], title: String) {
        let ordered = fields.map(\.id).filter { ids.contains($0) }
        guard !ordered.isEmpty else { return }
        var groups = headerGroups.compactMap { g -> ScheduleHeaderGroup? in
            var g = g
            g.fieldIDs.removeAll { ordered.contains($0) }
            return g.fieldIDs.isEmpty ? nil : g
        }
        groups.append(ScheduleHeaderGroup(title: title, fieldIDs: ordered))
        headerGroups = groups
    }

    /// Removes the header groups containing any of the fields.
    public mutating func ungroupHeaders(_ ids: [String]) {
        headerGroups = headerGroups.filter { g in !g.fieldIDs.contains { ids.contains($0) } }
    }

    /// The field of a heading, or nil.
    public func field(_ id: String) -> ScheduleField? { fields.first { $0.id == id } }
}

/// What editing a schedule cell offers.
public enum ScheduleCellEditor: Hashable, Sendable {
    /// Free text; numbers accept units ("900", "2.1 m", "3' 6\"") and are parsed by the parameter type.
    case text
    /// A drop-down (types, levels, materials, phases, Yes/No, choice lists).
    case options([ScheduleCellOption])
    /// The cell can't be edited; the reason is shown as a subtle cue.
    case readOnly(String)

    public var isEditable: Bool { if case .readOnly = self { return false }; return true }
}

public struct ScheduleCellOption: Hashable, Sendable {
    public var title: String
    public var value: ParamValue
    public init(title: String, value: ParamValue) { self.title = title; self.value = value }
}

/// Where a cell edit is written: the parameter, its type and every element of the row (grouped rows have several).
public struct ScheduleCellTarget: Hashable, Sendable {
    public var parameterID: ParameterID
    public var type: ParamType
    public var elementIDs: [ElementID]
    public var heading: String
    public var editor: ScheduleCellEditor
}

/// In-place editing of schedule cells. Edits go to the elements (or their types) through `Parameters.set`, so a
/// schedule edit behaves exactly like the same edit in the Properties palette.
public enum ScheduleEditing {
    static let typeNameID = ParameterID("typeName")
    static let familyAndTypeID = ParameterID("familyAndType")

    /// The edit target of a cell, or a read-only reason.
    public static func target(_ table: ScheduleTable, row: Int, column: Int, schedule: Element, model: BIMModel) -> ScheduleCellTarget {
        let heading = column >= 0 && column < table.columns.count ? table.columns[column].heading : ""
        func readOnly(_ why: String) -> ScheduleCellTarget {
            ScheduleCellTarget(parameterID: ParameterID(""), type: .text, elementIDs: [], heading: heading, editor: .readOnly(why))
        }
        guard let def = schedule.schedule, row >= 0, row < table.rows.count, column >= 0, column < table.columns.count else { return readOnly("") }
        let r = table.rows[row]
        guard r.kind == .data else {
            return readOnly(r.kind == .groupHeader || r.kind == .blank ? "Group headers are set in Sorting/Grouping." : "Totals are calculated from the rows above.")
        }
        let f = table.columns[column]
        let elements = r.elementIDs.compactMap { model[$0] }
        guard !elements.isEmpty else { return readOnly("This row has no elements.") }
        switch f.source {
        case .count: return readOnly("Count is calculated.")
        case .formula: return readOnly("“\(f.heading)” is a calculated value.")
        case .percentage: return readOnly("“\(f.heading)” is calculated from another field.")
        case .material: return readOnly("Material quantities are measured from the model.")
        case .roomParameter: return readOnly("Room values are edited on the room itself.")
        case .combined: return readOnly("“\(f.heading)” combines several parameters; edit them in their own columns.") // F12
        case .parameter(let p):
            let type = ScheduleEngine.fieldType(f, def, model)
            if p == typeNameID { return typeSwapTarget(elements, heading: f.heading, model: model) }
            guard elements.allSatisfy({ Parameters.isEditable(p, on: $0, model) }) else {
                let reason = Parameters.allEntries(elements[0], model).first { $0.id == p }?.readOnlyReason
                return readOnly(reason.map { "“\(f.heading)” is read-only. \($0)" } ?? "“\(f.heading)” is read-only.")
            }
            let editor = options(for: type, elements: elements, model: model).map(ScheduleCellEditor.options) ?? .text
            return ScheduleCellTarget(parameterID: p, type: type, elementIDs: r.elementIDs, heading: f.heading, editor: editor)
        }
    }

    /// Cheap per-cell affordance for drawing a table (no values or option lists are built): whether a data cell is
    /// editable, whether it edits with a drop-down, and a short read-only hint. `target` gives the full answer.
    public static func affordance(_ table: ScheduleTable, row: Int, column: Int, def: ScheduleDefinition, model: BIMModel) -> (editable: Bool, dropDown: Bool, hint: String?) {
        guard row >= 0, row < table.rows.count, column >= 0, column < table.columns.count, table.rows[row].kind == .data else { return (false, false, nil) }
        let f = table.columns[column], r = table.rows[row]
        if case .parameter(let p) = f.source, p == typeNameID { return (true, true, nil) }
        guard column < r.cells.count, r.cells[column].isEditable else {
            switch f.source {
            case .count: return (false, false, "Count is calculated.")
            case .formula, .percentage: return (false, false, "“\(f.heading)” is a calculated value.")
            case .material: return (false, false, "Material quantities are measured from the model.")
            case .roomParameter: return (false, false, "Room values are edited on the room itself.")
            case .combined: return (false, false, "“\(f.heading)” combines several parameters.") // F12
            case .parameter: return (false, false, "“\(f.heading)” is read-only.")
            }
        }
        switch ScheduleEngine.fieldType(f, def, model) {
        case .bool, .choice, .elementRef: return (true, true, nil)
        default: return (true, false, nil)
        }
    }

    /// "Type" (the type name) edits by swapping to another type of the same family.
    static func typeSwapTarget(_ elements: [Element], heading: String, model: BIMModel) -> ScheduleCellTarget {
        let families = Set(elements.map { model.typeData(of: $0).map { "\($0.instanceCategory.rawValue)|\($0.familyName)" } ?? "" })
        guard families.count == 1, let first = elements.first, let td = model.typeData(of: first) else {
            return ScheduleCellTarget(parameterID: typeNameID, type: .text, elementIDs: [], heading: heading,
                                      editor: .readOnly("The row mixes families; change the type in the Properties palette."))
        }
        let opts = model.types(for: first.category).filter { $0.typeData?.familyName == td.familyName }
            .map { ScheduleCellOption(title: $0.name, value: .ref($0.id)) }
        return ScheduleCellTarget(parameterID: familyAndTypeID, type: .elementRef(.elementTypes), elementIDs: elements.map(\.id), heading: heading, editor: .options(opts))
    }

    /// Drop-down choices for a parameter type, or nil for free text.
    public static func options(for type: ParamType, elements: [Element], model: BIMModel) -> [ScheduleCellOption]? {
        func refs(_ es: [Element], none: String?) -> [ScheduleCellOption] {
            (none.map { [ScheduleCellOption(title: $0, value: .ref(nil))] } ?? []) + es.map { ScheduleCellOption(title: Parameters.format(.ref($0.id), type: type, model: model), value: .ref($0.id)) }
        }
        switch type {
        case .bool: return [ScheduleCellOption(title: "Yes", value: .bool(true)), ScheduleCellOption(title: "No", value: .bool(false))]
        case .choice(let o): return o.map { ScheduleCellOption(title: $0, value: .text($0)) }
        case .elementRef(.levels): return refs(model.levels, none: nil)
        case .elementRef(.elementTypes):
            let cats = Set(elements.map(\.category))
            guard cats.count == 1, let c = cats.first else { return [] }
            return refs(model.types(for: c), none: nil)
        case .elementRef(.materials): return refs(model.materials, none: "<By Category>")
        case .elementRef(.phases): return refs(model.phases, none: "<None>")
        case .elementRef(let c): return refs(model.elements(c).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, none: "<None>")
        default: return nil
        }
    }

    /// Parses typed text for a target: numbers with units by the parameter type; drop-down cells accept an option title.
    public static func parse(_ text: String, for target: ScheduleCellTarget, model: BIMModel) throws(ParameterError) -> ParamValue {
        switch target.editor {
        case .readOnly(let why): throw ParameterError(why.isEmpty ? "This cell can't be edited." : why)
        case .options(let opts):
            let t = text.trimmingCharacters(in: .whitespaces)
            if let o = opts.first(where: { $0.title.caseInsensitiveCompare(t) == .orderedSame }) { return o.value }
            if target.parameterID == familyAndTypeID {
                // A bare type name: prefer the row's own family when several families have a type of that name.
                let family = target.elementIDs.first.flatMap { model[$0] }.flatMap { model.typeData(of: $0)?.familyName }
                let named = opts.filter { $0.title.hasSuffix(": " + t) }
                if let o = named.first(where: { $0.value.refValue.flatMap { model[$0]?.typeData?.familyName } == family }) ?? named.first { return o.value }
            }
            return try Parameters.parse(text, type: target.type, model: model)
        case .text:
            return try Parameters.parse(text, type: target.type, model: model)
        }
    }

    /// Writes a value to every element of the row inside one transaction (one undo step).
    public static func apply(_ value: ParamValue, to target: ScheduleCellTarget, in tx: TransactionContext) throws(ParameterError) {
        if case .readOnly(let why) = target.editor { throw ParameterError(why) }
        for id in target.elementIDs { try Parameters.set(target.parameterID, to: value, on: id, in: tx) }
    }

    /// Whether the edit lands on a type (so it changes every instance of that type, not only the row).
    public static func writesToType(_ target: ScheduleCellTarget, model: BIMModel) -> Bool {
        guard target.parameterID != familyAndTypeID, let e = target.elementIDs.first.flatMap({ model[$0] }) else { return false }
        return Parameters.allEntries(e, model).first { $0.id == target.parameterID }?.isType ?? false
    }

    // MARK: Filters

    /// A filter rule with its value converted to the field's type: "900" on a length field is 900 mm in metric
    /// projects, "Level 1" on a level field matches the level's name, "Yes" matches a Yes/No field.
    struct ResolvedFilter {
        var fieldID: String
        var op: FilterRule.Op
        var value: ParamValue
        /// Compare formatted text (element references: levels, types, phases…).
        var byName: Bool
        var type: ParamType
    }

    static func resolve(_ flt: ScheduleFilter, _ def: ScheduleDefinition, _ model: BIMModel) -> ResolvedFilter {
        guard let f = def.field(flt.fieldID) else { return ResolvedFilter(fieldID: flt.fieldID, op: flt.op, value: flt.value, byName: false, type: .text) }
        let type = ScheduleEngine.fieldType(f, def, model)
        if case .elementRef = type { return ResolvedFilter(fieldID: flt.fieldID, op: flt.op, value: flt.value, byName: true, type: type) }
        var value = flt.value
        if let s = flt.value.textValue, type.isNumeric || type == .bool, !s.trimmingCharacters(in: .whitespaces).isEmpty {
            if case .integer = type, let i = Int(s.trimmingCharacters(in: .whitespaces)) { value = .int(i) }
            else if let v = try? Parameters.parse(s, type: type, model: model) { value = v }
        }
        return ResolvedFilter(fieldID: flt.fieldID, op: flt.op, value: value, byName: false, type: type)
    }

    static func matches(_ r: ResolvedFilter, _ v: ParamValue?, _ model: BIMModel) -> Bool {
        guard r.byName else { return FilterEvaluation.evaluate(r.op, lhs: v, rhs: r.value) }
        guard let v, v.refValue != nil else { return FilterEvaluation.evaluate(r.op, lhs: nil, rhs: r.value) }
        let name = Parameters.format(v, type: r.type, model: model)
        let rhs: ParamValue = r.value.refValue.map { .text(Parameters.format(.ref($0), type: r.type, model: model)) } ?? r.value
        return FilterEvaluation.evaluate(r.op, lhs: .text(name), rhs: rhs)
    }

    /// Operators that take no value.
    public static func opNeedsValue(_ op: FilterRule.Op) -> Bool { op != .hasValue && op != .hasNoValue }
}

extension ScheduleTable {
    /// Header spans of the table's header groups over its visible columns (one per contiguous run).
    public var headerSpans: [ScheduleHeaderSpan] {
        var out: [ScheduleHeaderSpan] = []
        for g in headerGroups {
            var start: Int?
            for i in 0...columns.count {
                let inGroup = i < columns.count && g.fieldIDs.contains(columns[i].id)
                if inGroup, start == nil { start = i }
                if !inGroup, let s = start { out.append(ScheduleHeaderSpan(title: g.title, columns: s..<i, groupID: g.id)); start = nil }
            }
        }
        return out.sorted { $0.columns.lowerBound < $1.columns.lowerBound }
    }
}
