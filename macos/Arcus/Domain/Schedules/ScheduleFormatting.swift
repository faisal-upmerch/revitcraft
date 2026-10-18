import Foundation

// F12: the Modify Schedule/Quantities tools Arcus lacked (RevitCraft rc-app dialogs/schedule_tools.rs; rc-core
// model.rs `HeaderRow`, `CellStyle`, `FontSpec`, `CombinedField`; schedule.rs `layout`): header rows between the
// title and the column headings, cell Shading/Font/Borders/alignment, Insert Image, Freeze Header and Combine
// Parameters.

/// A picture in a schedule's title or header cell, kept in the project (PNG, downscaled on insert).
public struct ScheduleImage: Hashable, Codable, Sendable {
    public var png: Data
    public var pixelWidth: Int
    public var pixelHeight: Int
    public init(png: Data, pixelWidth: Int, pixelHeight: Int) { self.png = png; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight }
}

/// A row of free text in the schedule header (Rows ▸ Insert), one cell per visible column, with merged runs.
public struct ScheduleHeaderRow: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var cells: [String]
    /// Merged runs of columns (first, last), inclusive.
    public var merges: [ScheduleMerge]
    /// Row height on paper (meters); nil = the schedule's row height.
    public var height: Double?
    /// Images by column.
    public var images: [Int: ScheduleImage]
    public init(columns: Int) { id = UUID().uuidString; cells = Array(repeating: "", count: max(1, columns)); merges = []; height = nil; images = [:] }

    /// Span of the cell starting at `column` (1 when not merged).
    public func span(at column: Int, columns: Int) -> Int {
        guard let m = merges.first(where: { $0.first == column }) else { return 1 }
        return max(1, min(m.last, columns - 1) - column + 1)
    }
    /// The first column of the (merged) cell containing `column`.
    public func cellStart(_ column: Int) -> Int { merges.first { column >= $0.first && column <= $0.last }?.first ?? column }
    public func text(_ column: Int) -> String { column >= 0 && column < cells.count ? cells[column] : "" }
}

public struct ScheduleMerge: Hashable, Codable, Sendable {
    public var first: Int
    public var last: Int
    public init(first: Int, last: Int) { self.first = min(first, last); self.last = max(first, last) }
}

/// Edit Font.
public struct ScheduleFont: Hashable, Codable, Sendable {
    public var family: String
    /// Text height on paper (meters).
    public var size: Double
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var color: RGBColor
    public init(family: String = "Helvetica", size: Double = 0.0022, bold: Bool = false, italic: Bool = false, underline: Bool = false, color: RGBColor = .black) {
        self.family = family; self.size = size; self.bold = bold; self.italic = italic; self.underline = underline; self.color = color
    }
}

public enum ScheduleVerticalAlign: String, Codable, Sendable, CaseIterable { case top = "Top", middle = "Middle", bottom = "Bottom" }

/// Line weight of a cell border (Borders): none, thin, medium or wide.
public enum ScheduleBorder: Int, Codable, Sendable, CaseIterable, Comparable {
    case none = 0, thin = 1, medium = 2, wide = 3
    public var title: String { ["None", "Thin Lines", "Medium Lines", "Wide Lines"][rawValue] }
    /// Arcus line weight number the border prints with.
    public var lineWeight: Int { [0, 1, 3, 5][rawValue] }
    public static func < (a: ScheduleBorder, b: ScheduleBorder) -> Bool { a.rawValue < b.rawValue }
}

/// Appearance of a cell (or of a column's body cells): Shading, Font, Borders and alignment.
public struct ScheduleCellStyle: Hashable, Codable, Sendable {
    public var shading: RGBColor?
    public var font: ScheduleFont?
    /// All four edges.
    public var border: ScheduleBorder?
    /// Edges set one by one: top, right, bottom, left (wins over `border`).
    public var edges: [ScheduleBorder]?
    public var horizontal: HorizontalAlign?
    public var vertical: ScheduleVerticalAlign?
    public init() {}
    public var isEmpty: Bool { self == ScheduleCellStyle() }
}

/// Which cell of a schedule's layout (selection and styles). Body cells share their column's style.
public enum ScheduleCellKey: Hashable, Sendable {
    case title
    /// A header row's cell: (row index, column index).
    case headerRow(Int, Int)
    /// A header group (its id).
    case group(String)
    /// A column heading (field id).
    case heading(String)
    /// A column's body cells (field id).
    case body(String)

    /// The key its appearance is stored under.
    public var styleKey: String {
        switch self {
        case .title: "title"
        case .headerRow(let r, let c): "x\(r):\(c)"
        case .group(let g): "g:\(g)"
        case .heading(let f): "h:\(f)"
        case .body(let f): "b:\(f)"
        }
    }
}

/// One part of a combined parameter: a parameter's value with its prefix and suffix, then the separator before the next.
public struct ScheduleCombinedPart: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var parameterID: ParameterID
    /// The parameter's name when the part was made (shown in the dialog).
    public var name: String
    public var prefix: String
    public var suffix: String
    public var separator: String
    public init(parameterID: ParameterID, name: String, prefix: String = "", suffix: String = "", separator: String = " / ") {
        id = UUID().uuidString; self.parameterID = parameterID; self.name = name; self.prefix = prefix; self.suffix = suffix; self.separator = separator
    }
}

/// The F12 additions to a schedule definition: header rows, cell styles, title image and height, Freeze Header.
public struct ScheduleFormatting: Hashable, Codable, Sendable {
    public var headerRows: [ScheduleHeaderRow] = []
    /// Cell appearance by `ScheduleCellKey.styleKey`.
    public var styles: [String: ScheduleCellStyle] = [:]
    public var titleImage: ScheduleImage?
    /// Title row height on paper (meters); nil = the default.
    public var titleHeight: Double?
    /// The title, header rows and headings stay in view while the rows scroll.
    public var freezeHeader = false
    public init() {}
    public var isEmpty: Bool { self == ScheduleFormatting() }

    public func style(_ key: ScheduleCellKey) -> ScheduleCellStyle { styles[key.styleKey] ?? ScheduleCellStyle() }
    public mutating func setStyle(_ key: ScheduleCellKey, _ change: (inout ScheduleCellStyle) -> Void) {
        var s = style(key)
        change(&s)
        styles[key.styleKey] = s.isEmpty ? nil : s
    }
}

extension ScheduleDefinition {
    /// Header rows, cell styles, title image and Freeze Header (optional storage: older documents decode unchanged).
    public var formatting: ScheduleFormatting {
        get { formattingStorage ?? ScheduleFormatting() }
        set { formattingStorage = newValue.isEmpty ? nil : newValue }
    }
}

/// Edits of the F12 schedule data.
public enum ScheduleFormattingEdits {
    /// Inserts an empty header row at `index` (clamped), with one cell per visible column.
    public static func insertHeaderRow(at index: Int, _ def: inout ScheduleDefinition) {
        let n = max(1, def.fields.filter { !$0.hidden }.count)
        var f = def.formatting
        f.headerRows.insert(ScheduleHeaderRow(columns: n), at: max(0, min(index, f.headerRows.count)))
        // Styles of later rows move down with them.
        f.styles = shiftedRowStyles(f.styles, from: index, by: 1)
        def.formatting = f
    }

    /// Deletes header rows.
    public static func deleteHeaderRows(_ rows: Set<Int>, _ def: inout ScheduleDefinition) {
        var f = def.formatting
        for r in rows.sorted(by: >) where r < f.headerRows.count {
            f.headerRows.remove(at: r)
            f.styles = f.styles.filter { !$0.key.hasPrefix("x\(r):") }
            f.styles = shiftedRowStyles(f.styles, from: r + 1, by: -1)
        }
        def.formatting = f
    }

    static func shiftedRowStyles(_ styles: [String: ScheduleCellStyle], from row: Int, by d: Int) -> [String: ScheduleCellStyle] {
        var out: [String: ScheduleCellStyle] = [:]
        for (k, v) in styles {
            if k.hasPrefix("x"), let colon = k.firstIndex(of: ":"), let r = Int(k.dropFirst().prefix(upTo: colon)), r >= row {
                out["x\(r + d)" + k[colon...]] = v
            } else { out[k] = v }
        }
        return out
    }

    /// Merge Unmerge: merges a run of cells of one header row (keeping the first non-empty text), or splits a merged
    /// cell back into its columns when one cell is chosen.
    public static func mergeOrUnmerge(row: Int, columns: [Int], _ def: inout ScheduleDefinition) {
        var f = def.formatting
        guard row < f.headerRows.count, let lo = columns.min(), let hi = columns.max() else { return }
        var h = f.headerRows[row]
        if lo == hi {
            let start = h.cellStart(lo)
            h.merges.removeAll { $0.first == start }
        } else {
            h.merges.removeAll { $0.last >= lo && $0.first <= hi }
            h.merges.append(ScheduleMerge(first: lo, last: hi))
            let text = (lo...hi).map { h.text($0) }.first { !$0.isEmpty } ?? ""
            while h.cells.count <= hi { h.cells.append("") }
            for c in lo...hi { h.cells[c] = c == lo ? text : "" }
        }
        f.headerRows[row] = h
        def.formatting = f
    }

    /// Sets the text of a header row cell (the merged cell when the column is inside a merge).
    public static func setText(_ text: String, row: Int, column: Int, _ def: inout ScheduleDefinition) {
        var f = def.formatting
        guard row < f.headerRows.count, column >= 0 else { return }
        let c = f.headerRows[row].cellStart(column)
        while f.headerRows[row].cells.count <= c { f.headerRows[row].cells.append("") }
        f.headerRows[row].cells[c] = text
        def.formatting = f
    }

    /// Clear Cell: the text and image of header row cells, the title image, a group's heading.
    public static func clear(_ keys: [ScheduleCellKey], _ def: inout ScheduleDefinition) {
        var f = def.formatting
        var groups = def.headerGroups
        for k in keys {
            switch k {
            case .title: f.titleImage = nil
            case .headerRow(let r, let c) where r < f.headerRows.count:
                let s = f.headerRows[r].cellStart(c)
                if s < f.headerRows[r].cells.count { f.headerRows[r].cells[s] = "" }
                f.headerRows[r].images[s] = nil
            case .group(let g): if let i = groups.firstIndex(where: { $0.id == g }) { groups[i].title = "" }
            default: break
            }
        }
        def.formatting = f
        def.headerGroups = groups
    }

    /// Insert Image into the title or a header row cell.
    public static func insertImage(_ image: ScheduleImage, at key: ScheduleCellKey, _ def: inout ScheduleDefinition) {
        var f = def.formatting
        switch key {
        case .title: f.titleImage = image
        case .headerRow(let r, let c) where r < f.headerRows.count: f.headerRows[r].images[f.headerRows[r].cellStart(c)] = image
        default: return
        }
        def.formatting = f
    }

    /// Applies a style change to cells. A column's horizontal body alignment is its field alignment (Format Unit),
    /// as in RevitCraft.
    public static func style(_ keys: [ScheduleCellKey], _ def: inout ScheduleDefinition, _ change: (inout ScheduleCellStyle) -> Void) {
        var f = def.formatting
        for k in keys { f.setStyle(k, change) }
        for k in keys {
            guard case .body(let fid) = k, let h = f.style(k).horizontal, let i = def.fields.firstIndex(where: { $0.id == fid }) else { continue }
            def.fields[i].alignment = h
            f.setStyle(k) { $0.horizontal = nil }
        }
        def.formatting = f
    }

    /// Reset: the cells' appearance goes back to the schedule's defaults.
    public static func reset(_ keys: [ScheduleCellKey], _ def: inout ScheduleDefinition) {
        var f = def.formatting
        for k in keys { f.styles[k.styleKey] = nil }
        def.formatting = f
    }

    /// Combine Parameters: a new column made of several parameters.
    @discardableResult
    public static func combine(_ parts: [ScheduleCombinedPart], heading: String, _ def: inout ScheduleDefinition) -> String? {
        guard !parts.isEmpty else { return nil }
        let name = heading.trimmingCharacters(in: .whitespaces).isEmpty ? parts.map(\.name).joined(separator: " / ") : heading
        let f = ScheduleField(source: .combined(parts), heading: name, width: 0.04)
        def.fields.append(f)
        return f.id
    }

    /// Combined text of one element: prefix, value and suffix of each part, then the separator.
    public static func combinedText(_ parts: [ScheduleCombinedPart], of e: Element, _ model: BIMModel) -> String {
        var out = ""
        for (i, p) in parts.enumerated() {
            let v = Parameters.value(p.parameterID, of: e, model)
            let type = Parameters.allEntries(e, model).first { $0.id == p.parameterID }?.type ?? .text
            out += p.prefix + (v.map { Parameters.format($0, type: type, model: model) } ?? "") + p.suffix
            if i + 1 < parts.count { out += p.separator }
        }
        return out
    }
}

extension ScheduleTable {
    /// The F12 formatting carried from the definition (filled by `ScheduleEngine.compute`).
    public var formatting: ScheduleFormatting {
        get { formattingStorage ?? ScheduleFormatting() }
        set { formattingStorage = newValue.isEmpty ? nil : newValue }
    }
}
