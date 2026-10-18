import Foundation

// F12: Keynoting Settings and the Keynote Legend (RevitCraft rc-core keynote.rs: tab-delimited keynote tables,
// `display`; schedule.rs `keynote_legend`: one row per key that keynote tags show).

/// A keynote table row as stored in the project (a loaded table).
public struct KeynoteRecord: Hashable, Codable, Sendable {
    public var key: String
    public var text: String
    public var parent: String
    public init(key: String, text: String, parent: String = "") { self.key = key; self.text = text; self.parent = parent }
}

/// The project's keynote table and how keynote tags read.
public enum Keynoting {
    /// The keynote table in use: the loaded one, else Arcus's built-in table.
    public static func table(_ model: BIMModel) -> [Keynote] {
        guard let t = model.manageData.keynoteTable, !t.isEmpty else { return KeynoteTable.standard }
        return t.map { Keynote($0.key, $0.text) }
    }

    /// The text of a key in the table in use.
    public static func text(for key: String, _ model: BIMModel) -> String? {
        guard let t = model.manageData.keynoteTable, !t.isEmpty else { return KeynoteTable.text(for: key) }
        return t.first { $0.key == key }?.text
    }

    /// What keynote tags show when they don't choose for themselves.
    public static func display(_ model: BIMModel) -> KeynoteDisplay { model.manageData.keynoteDisplay ?? .key }

    /// Keys a user keynote can pick: every keynote that has a parent (the items, not the division headings); a flat
    /// loaded table offers all of its keys.
    public static func pickable(_ model: BIMModel) -> [Keynote] {
        let all = table(model)
        let items = all.filter { k in
            if let rec = model.manageData.keynoteTable?.first(where: { $0.key == k.key }) { return !rec.parent.isEmpty }
            return k.parent != nil
        }
        return items.isEmpty ? all : items
    }

    /// Reads a keynote file: one keynote per line, `key <tab> text <tab> parent` (the parent may be left out); empty
    /// lines and lines starting with `#` are skipped. Throws when no line has a tab.
    public static func parse(_ text: String) throws(TransactionError) -> [KeynoteRecord] {
        var out: [KeynoteRecord] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r\u{FEFF}"))
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") { continue }
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 2 else { continue }
            let key = cols[0].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            out.append(KeynoteRecord(key: key, text: cols[1].trimmingCharacters(in: .whitespaces), parent: cols.count > 2 ? cols[2].trimmingCharacters(in: .whitespaces) : ""))
        }
        guard !out.isEmpty else { throw TransactionError("No keynotes found: each line needs a key, a tab and the keynote text.") }
        return out
    }

    /// Writes a table in the same format (for exporting the built-in table to start a custom one).
    public static func write(_ table: [Keynote]) -> String {
        table.map { "\($0.key)\t\($0.text)\t\($0.parent ?? "")" }.joined(separator: "\n") + "\n"
    }

    /// Every key shown by a keynote tag in the project, with the tags showing it, sorted by key.
    public static func usedKeys(_ model: BIMModel) -> [(key: String, tags: [ElementID])] {
        var byKey: [String: [ElementID]] = [:]
        for e in model.elements(.tags) {
            guard let t = e.tag, let kind = t.kind, kind.isKeynote else { continue }
            let key = AnnotationRenderer.keynoteKey(t, kind, target: model[t.taggedID], model: model)
            if !key.isEmpty { byKey[key, default: []].append(e.id) }
        }
        return byKey.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { ($0, byKey[$0]!) }
    }
}

/// The Keynote Legend: a schedule of the keynotes used in the project (Key Value, Keynote Text). Its rows hold the
/// keynote tags showing each key, so Highlight in Model finds them.
public enum KeynoteLegend {
    public static let keyID = ParameterID("keynote.key")
    public static let textID = ParameterID("keynote.text")

    /// The definition of a new keynote legend.
    public static func definition() -> ScheduleDefinition {
        var d = ScheduleDefinition(kind: .keynoteLegend, categories: [.tags],
                                   fields: [ScheduleField(source: .parameter(keyID), heading: "Key Value", width: 0.025),
                                            ScheduleField(source: .parameter(textID), heading: "Keynote Text", width: 0.08)])
        d.sorting = [ScheduleSort(fieldID: d.fields[0].id)]
        return d
    }

    public static func table(_ schedule: Element, _ def: ScheduleDefinition, _ model: BIMModel) -> ScheduleTable {
        let visible = def.fields.filter { !$0.hidden }
        var used = Keynoting.usedKeys(model)
        if def.sorting.first?.ascending == false { used.reverse() }
        let rows = used.map { item -> ScheduleRow in
            let cells = visible.map { f -> ScheduleCell in
                let text: String
                if case .parameter(let p) = f.source, p == textID { text = Keynoting.text(for: item.key, model) ?? "" } else { text = item.key }
                return ScheduleCell(text: text, value: .text(text), parameterID: nil, isEditable: false, background: nil, alignment: f.alignment)
            }
            return ScheduleRow(kind: .data, cells: cells, elementIDs: item.tags, title: "")
        }
        var t = ScheduleTable(title: schedule.name, columns: visible, rows: rows, elementCount: rows.reduce(0) { $0 + $1.elementIDs.count })
        t.showTitle = def.showTitle; t.showHeaders = def.showHeaders
        t.appearance = def.appearance; t.headerGroups = def.headerGroups
        t.formatting = def.formatting
        return t
    }
}
