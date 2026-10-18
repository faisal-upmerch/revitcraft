import Foundation
import ArcusCalc

public struct ScheduleCell: Sendable, Hashable {
    public var text: String
    public var value: ParamValue?
    public var parameterID: ParameterID?
    public var isEditable: Bool
    public var background: RGBColor?
    public var alignment: HorizontalAlign
    public init(text: String, value: ParamValue?, parameterID: ParameterID?, isEditable: Bool, background: RGBColor?, alignment: HorizontalAlign) {
        self.text = text; self.value = value; self.parameterID = parameterID; self.isEditable = isEditable; self.background = background; self.alignment = alignment
    }
}

public struct ScheduleRow: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case groupHeader, data, groupFooter, blank, grandTotal }
    public var kind: Kind
    public var cells: [ScheduleCell]
    public var elementIDs: [ElementID]
    /// Group header/footer title.
    public var title: String
    public init(kind: Kind, cells: [ScheduleCell], elementIDs: [ElementID], title: String) {
        self.kind = kind; self.cells = cells; self.elementIDs = elementIDs; self.title = title
    }
}

public struct ScheduleTable: Sendable {
    public var title: String
    public var columns: [ScheduleField]
    public var rows: [ScheduleRow]
    public var elementCount: Int
    /// Presentation carried from the definition (BL-SCHED): title/header visibility, appearance and header groups.
    public var showTitle = true
    public var showHeaders = true
    public var appearance = ScheduleAppearance()
    public var headerGroups: [ScheduleHeaderGroup] = []
    var formattingStorage: ScheduleFormatting? // F12: read through `formatting`
    public init(title: String, columns: [ScheduleField], rows: [ScheduleRow], elementCount: Int) {
        self.title = title; self.columns = columns; self.rows = rows; self.elementCount = elementCount
    }
    /// Width on paper of all visible columns.
    public var totalWidth: Double { columns.reduce(0) { $0 + $1.width } }
}

/// Computes live schedule tables from the model.
public enum ScheduleEngine {
    public static func compute(_ schedule: Element, _ model: BIMModel) -> ScheduleTable {
        guard let def = schedule.schedule else { return ScheduleTable(title: schedule.name, columns: [], rows: [], elementCount: 0) }
        if def.kind == .keynoteLegend { return KeynoteLegend.table(schedule, def, model) } // F12
        let visibleFields = def.fields.filter { !$0.hidden }
        let sources = sourceRows(def, model)
        // Evaluate every field (hidden fields too, for filters/sorting/formulas).
        var records: [(ids: [ElementID], values: [String: ParamValue?], material: ElementID?)] = []
        for src in sources {
            var vals: [String: ParamValue?] = [:]
            for f in def.fields where !isDeferred(f) { vals[f.id] = fieldValue(f, src.element, material: src.material, model) }
            for f in def.fields where isFormula(f) { vals[f.id] = formulaValue(f, def, vals, model) }
            records.append(([src.element.id], vals, src.material?.materialID))
        }
        // Filters (values converted to the field's type and units; element references match by name). // BL-SCHED
        let filters = def.filters.map { ScheduleEditing.resolve($0, def, model) }
        records = records.filter { r in
            filters.allSatisfy { flt in
                guard let v = r.values[flt.fieldID] else { return true }
                return ScheduleEditing.matches(flt, v, model)
            }
        }
        // Sorting.
        let sortFields = def.sorting
        records.sort { a, b in
            for s in sortFields {
                let c = compare(a.values[s.fieldID] ?? nil, b.values[s.fieldID] ?? nil)
                if c != .orderedSame { return s.ascending ? c == .orderedAscending : c == .orderedDescending }
            }
            return a.ids.first! < b.ids.first!
        }
        // Aggregate when not itemizing: rows with equal sort keys collapse.
        if !def.itemizeEveryInstance && !sortFields.isEmpty {
            var merged: [(ids: [ElementID], values: [String: ParamValue?], material: ElementID?)] = []
            for r in records {
                if let last = merged.last, sortFields.allSatisfy({ compare(last.values[$0.fieldID] ?? nil, r.values[$0.fieldID] ?? nil) == .orderedSame }) {
                    var m = last
                    m.ids += r.ids
                    for f in def.fields {
                        let a = m.values[f.id] ?? nil, b = r.values[f.id] ?? nil
                        switch f.total {
                        case .minimum: m.values[f.id] = extreme(a, b, max: false)
                        case .maximum: m.values[f.id] = extreme(a, b, max: true)
                        case .minAndMax:
                            let key = maxKey(f)
                            m.values[key] = extreme((m.values[key] ?? nil) ?? a, (r.values[key] ?? nil) ?? b, max: true)
                            m.values[f.id] = extreme(a, b, max: false)
                        case .total:
                            m.values[f.id] = sum(a, b)
                        case .none:
                            if isCount(f) { m.values[f.id] = sum(a, b) } else if a != b { m.values[f.id] = .some(nil) }
                        }
                    }
                    merged[merged.count - 1] = m
                } else {
                    merged.append(r)
                }
            }
            records = merged
        }
        // Percentages need totals: of the grand total, or of the record's group (first grouping sort field).
        let grand = totals(records.map(\.values), def.fields)
        let groupField = (sortFields.first { $0.header || $0.footer || $0.blankLine } ?? sortFields.first)?.fieldID
        var groupTotals: [String: [String: Double]] = [:]
        func groupKey(_ values: [String: ParamValue?]) -> String {
            guard let g = groupField, let v = values[g] ?? nil else { return "" }
            return v.description
        }
        if def.fields.contains(where: { if case .percentage(_, true) = $0.source { return true }; return false }) {
            let grouped = Dictionary(grouping: records.map(\.values), by: groupKey)
            for (k, rows) in grouped { groupTotals[k] = totals(rows, def.fields) }
        }
        for i in records.indices {
            for f in def.fields {
                guard case .percentage(let of, let byGroup) = f.source, let v = records[i].values[of]??.doubleValue else { continue }
                let t = byGroup ? groupTotals[groupKey(records[i].values)]?[of] : grand[of]
                if let t, t != 0 { records[i].values[f.id] = .double(v / t) }
            }
        }

        func cells(_ values: [String: ParamValue?], ids: [ElementID], isData: Bool) -> [ScheduleCell] {
            visibleFields.map { f in
                let v = values[f.id] ?? nil
                let type = fieldType(f, def, model)
                var text = v.map { format($0, type: type, field: f, model: model) } ?? ""
                if f.total == .minAndMax, let hi = values[maxKey(f)] ?? nil, let lo = v, hi.doubleValue != lo.doubleValue {
                    text = "\(text) – \(format(hi, type: type, field: f, model: model))"
                }
                if isCount(f), !isData, let d = v?.doubleValue { text = "\(Int(d))" }
                var editable = false
                var pid: ParameterID?
                if isData, case .parameter(let p) = f.source {
                    pid = p
                    editable = ids.allSatisfy { id in
                        guard let e = model[id] else { return false }
                        return Parameters.isEditable(p, on: e, model)
                    }
                }
                var bg: RGBColor?
                if let cf = f.conditionalFormat, let v, FilterEvaluation.evaluate(cf.op, lhs: v, rhs: cf.value) { bg = cf.background }
                return ScheduleCell(text: text, value: v, parameterID: pid, isEditable: editable, background: bg, alignment: f.alignment)
            }
        }

        var rows: [ScheduleRow] = []
        let groupSorts = sortFields.filter { $0.header || $0.footer || $0.blankLine }
        if groupSorts.isEmpty {
            rows = records.map { ScheduleRow(kind: .data, cells: cells($0.values, ids: $0.ids, isData: true), elementIDs: $0.ids, title: "") }
        } else {
            // Group by the first grouping sort (nested grouping flattened to one level for clarity).
            let g = groupSorts[0]
            var i = 0
            while i < records.count {
                let key = records[i].values[g.fieldID] ?? nil
                var j = i
                while j < records.count, compare(records[j].values[g.fieldID] ?? nil, key) == .orderedSame { j += 1 }
                let group = Array(records[i..<j])
                let field = def.fields.first { $0.id == g.fieldID }
                let title = key.map { format($0, type: field.map { fieldType($0, def, model) } ?? .text, field: field, model: model) } ?? "(none)"
                if g.header { rows.append(ScheduleRow(kind: .groupHeader, cells: [], elementIDs: [], title: title)) }
                rows += group.map { ScheduleRow(kind: .data, cells: cells($0.values, ids: $0.ids, isData: true), elementIDs: $0.ids, title: "") }
                if g.footer {
                    let vals = totalValues(totals(group.map(\.values), def.fields), def.fields)
                    rows.append(ScheduleRow(kind: .groupFooter, cells: cells(vals, ids: [], isData: false), elementIDs: group.flatMap(\.ids),
                                            title: g.footerShowsTitleCountTotals ? "\(title): \(group.reduce(0) { $0 + $1.ids.count })" : ""))
                }
                if g.blankLine { rows.append(ScheduleRow(kind: .blank, cells: [], elementIDs: [], title: "")) }
                i = j
            }
        }
        if def.grandTotals {
            let vals = totalValues(grand, def.fields)
            rows.append(ScheduleRow(kind: .grandTotal, cells: cells(vals, ids: [], isData: false), elementIDs: [],
                                    title: "\(def.grandTotalTitle): \(records.reduce(0) { $0 + $1.ids.count })"))
        }
        var table = ScheduleTable(title: schedule.name, columns: visibleFields, rows: rows, elementCount: records.reduce(0) { $0 + $1.ids.count })
        table.showTitle = def.showTitle; table.showHeaders = def.showHeaders // BL-SCHED
        table.appearance = def.appearance; table.headerGroups = def.headerGroups
        table.formatting = def.formatting // F12
        return table
    }

    // MARK: Sources

    struct Source { var element: Element; var material: MaterialQuantity? }

    static func sourceRows(_ def: ScheduleDefinition, _ model: BIMModel) -> [Source] {
        switch def.kind {
        case .sheetList:
            return model.sheets.filter { $0.sheet?.appearsInSheetList ?? true }.map { Source(element: $0, material: nil) }
        case .viewList:
            return model.views.map { Source(element: $0, material: nil) }
        case .revisionSchedule:
            return model.revisions.map { Source(element: $0, material: nil) }
        case .materialTakeoff:
            return instances(def, model).flatMap { e in
                QuantityEngine.quantities(for: e, in: model).materials.map { Source(element: e, material: $0) }
            }
        default:
            return instances(def, model).map { Source(element: $0, material: nil) }
        }
    }

    static func instances(_ def: ScheduleDefinition, _ model: BIMModel) -> [Element] {
        let phaseOrder = model.phaseOrder(def.phaseID ?? model.latestPhase?.id)
        return model.elements(def.categories).filter { e in
            guard !e.isType else { return false }
            if let opt = e.designOptionID, let od = model[opt]?.designOption, !od.isPrimary { return false }
            guard let po = phaseOrder else { return true }
            let created = model.phaseOrder(e.phaseCreated) ?? Int.min
            if created > po { return false }
            if let d = model.phaseOrder(e.phaseDemolished), d <= po {
                switch def.phaseFilter {
                case .showAll, .showDemoAndNew, .none: return d == po
                default: return false
                }
            }
            switch def.phaseFilter {
            case .showNew: return created == po
            case .showPreviousPhase: return created < po
            default: return true
            }
        }
    }

    // MARK: Values

    static func isFormula(_ f: ScheduleField) -> Bool { if case .formula = f.source { return true }; return false }
    static func isCount(_ f: ScheduleField) -> Bool { if case .count = f.source { return true }; return false }
    static func isDeferred(_ f: ScheduleField) -> Bool {
        switch f.source { case .formula, .percentage: return true; default: return false }
    }

    static func fieldValue(_ f: ScheduleField, _ e: Element, material: MaterialQuantity?, _ model: BIMModel) -> ParamValue? {
        switch f.source {
        case .parameter(let p): return Parameters.value(p, of: e, model)
        case .count: return .double(1)
        case .material(let what):
            guard let m = material else { return nil }
            switch what {
            case "Name": return .text(model[m.materialID]?.name ?? "<By Category>")
            case "Area": return .double(m.area)
            case "Volume": return .double(m.volume)
            default: return nil
            }
        case .roomParameter(let p):
            return RoomQueries.room(containing: e, model).flatMap { Parameters.value(p, of: $0, model) }
                ?? (e.insert != nil ? RoomQueries.roomsAround(insert: e, model).to.flatMap { Parameters.value(p, of: $0, model) } : nil)
        case .formula, .percentage:
            return nil
        case .combined(let parts): // F12
            return .text(ScheduleFormattingEdits.combinedText(parts, of: e, model))
        }
    }

    static func formulaValue(_ f: ScheduleField, _ def: ScheduleDefinition, _ vals: [String: ParamValue?], _ model: BIMModel) -> ParamValue? {
        guard case .formula(let src, let type) = f.source else { return nil }
        var inputs: [String: FormulaValue] = [:]
        for other in def.fields where other.id != f.id {
            guard let v = vals[other.id] ?? nil else { continue }
            let t = fieldType(other, def, model)
            inputs[other.heading] = FamilyEvaluator.formulaValue(v, type: t)
        }
        for (name, v) in GlobalParameters.formulaInputs(model) where inputs[name] == nil { inputs[name] = v } // F11: global parameters in formulas
        guard let formula = try? Formula(src, knownNames: Set(inputs.keys)),
              let r = try? formula.evaluate(units: model.units, { inputs[$0] }) else { return nil }
        return FamilyEvaluator.paramValue(r, type: type)
    }

    public static func fieldType(_ f: ScheduleField, _ def: ScheduleDefinition, _ model: BIMModel) -> ParamType {
        switch f.source {
        case .parameter(let p), .roomParameter(let p):
            if let b = BuiltInCatalog.byID[p] { return b.type }
            if let d = model.projectParameters.first(where: { $0.id == p }) { return d.type }
            if p.key.hasPrefix("family:") {
                let name = String(p.key.dropFirst(7))
                for fam in model.elements(.families) { if let fp = fam.family?.parameter(named: name) { return fp.type } }
            }
            return .text
        case .count: return .integer
        case .material(let w): return w == "Area" ? .area : (w == "Volume" ? .volume : .text)
        case .formula(_, let t): return t
        case .percentage: return .percentage
        case .combined: return .text // F12
        }
    }

    static func format(_ v: ParamValue, type: ParamType, field: ScheduleField?, model: BIMModel) -> String {
        if let dec = field?.decimals, let d = v.doubleValue, type.isNumeric, type != .integer {
            var units = model.units
            units.areaDecimals = dec; units.volumeDecimals = dec; units.numberDecimals = dec
            if type == .length, units.system == .metric { units.lengthRounding = pow(10, -Double(dec)) * (units.length == .meters ? 1 : 0.001) }
            return QuantityFormatter.format(d, kind: type.unitKind ?? .number, units: units)
        }
        return Parameters.format(v, type: type, model: model)
    }

    static func compare(_ a: ParamValue?, _ b: ParamValue?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case (let x?, let y?):
            if case .text(let s) = x, case .text(let t) = y { return s.localizedStandardCompare(t) }
            if let dx = x.doubleValue, let dy = y.doubleValue {
                return abs(dx - dy) <= 1e-9 ? .orderedSame : (dx < dy ? .orderedAscending : .orderedDescending)
            }
            return x.description.localizedStandardCompare(y.description)
        }
    }

    static func sum(_ a: ParamValue?, _ b: ParamValue?) -> ParamValue? {
        switch (a?.doubleValue, b?.doubleValue) {
        case (let x?, let y?): return .double(x + y)
        case (let x?, nil): return .double(x)
        case (nil, let y?): return .double(y)
        default: return nil
        }
    }

    static func extreme(_ a: ParamValue?, _ b: ParamValue?, max: Bool) -> ParamValue? {
        switch (a?.doubleValue, b?.doubleValue) {
        case (let x?, let y?): return .double(max ? Swift.max(x, y) : Swift.min(x, y))
        case (let x?, nil): return .double(x)
        case (nil, let y?): return .double(y)
        default: return nil
        }
    }

    /// Hidden value key carrying the maximum of a "minimum and maximum" field (the field's own key holds the minimum).
    static func maxKey(_ f: ScheduleField) -> String { f.id + "#max" }

    static func totals(_ rows: [[String: ParamValue?]], _ fields: [ScheduleField]) -> [String: Double] {
        var out: [String: Double] = [:]
        for f in fields where f.total != .none || isCount(f) {
            let nums = rows.compactMap { ($0[f.id] ?? nil)?.doubleValue }
            guard !nums.isEmpty else { continue }
            switch f.total {
            case .minimum: out[f.id] = nums.min()
            case .maximum: out[f.id] = nums.max()
            case .minAndMax:
                out[f.id] = nums.min()
                out[maxKey(f)] = rows.compactMap { (($0[maxKey(f)] ?? nil) ?? ($0[f.id] ?? nil))?.doubleValue }.max()
            case .total, .none: out[f.id] = nums.reduce(0, +)
            }
        }
        return out
    }

    /// Footer / grand-total values from `totals`, including the hidden maximum of min-and-max fields.
    static func totalValues(_ t: [String: Double], _ fields: [ScheduleField]) -> [String: ParamValue?] {
        var vals: [String: ParamValue?] = [:]
        for f in fields where f.total != .none || isCount(f) {
            vals[f.id] = t[f.id].map { .double($0) }
            if f.total == .minAndMax { vals[maxKey(f)] = t[maxKey(f)].map { .double($0) } }
        }
        return vals
    }

    /// CSV export (RFC 4180 quoting) of the formatted table.
    public static func csv(_ t: ScheduleTable) -> String {
        func q(_ s: String) -> String {
            s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var lines = [t.columns.map { q($0.heading) }.joined(separator: ",")]
        for r in t.rows {
            switch r.kind {
            case .data, .groupFooter, .grandTotal:
                var cells = r.cells.map { q($0.text) }
                if r.kind != .data, !r.title.isEmpty, !cells.isEmpty, cells[0].isEmpty { cells[0] = q(r.title) }
                lines.append(cells.joined(separator: ","))
            case .groupHeader:
                lines.append(q(r.title) + String(repeating: ",", count: max(0, t.columns.count - 1)))
            case .blank:
                lines.append(String(repeating: ",", count: max(0, t.columns.count - 1)))
            }
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
