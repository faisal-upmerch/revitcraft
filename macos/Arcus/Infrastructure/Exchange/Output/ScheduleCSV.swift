import Foundation
import ArcusDomain

/// A structural problem with a CSV file (encoding, size, missing key column…). Per-cell problems are reported as
/// `CSVImportPreview.RowError` instead.
public struct ScheduleCSVError: Error, Sendable, CustomStringConvertible, Hashable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Result of matching a CSV file against a schedule. Nothing is changed until `ScheduleCSV.apply` runs.
public struct CSVImportPreview: Sendable {
    public var keyColumn: String
    public var changes: [Change]
    public var errors: [RowError]
    /// Key values that match no row of the schedule.
    public var unmatchedKeys: [String]

    public struct Change: Sendable, Hashable {
        public var elementID: ElementID
        public var parameterID: ParameterID
        public var parameterName: String
        public var oldText: String
        public var newText: String
        public var newValue: ParamValue
    }

    /// `row` is the 1-based record number in the file (the header is row 1); `column` is the CSV column heading.
    public struct RowError: Sendable, Hashable {
        public var row: Int
        public var column: String
        public var message: String
    }
}

/// CSV exchange for schedules.
///
/// Export format: UTF-8 **with a byte-order mark** (so Excel on macOS and Windows detects UTF-8), RFC 4180 quoting,
/// CRLF record separators, comma delimiters. Cells that a spreadsheet would evaluate as a formula (leading `=`, `@`,
/// tab, CR, or `+`/`-` not followed by a plain number) are prefixed with `'`; import strips that prefix again.
///
/// Import accepts UTF-8 with or without BOM (and UTF-16 with BOM), CRLF/LF/CR line endings, quoted fields with
/// embedded delimiters, quotes and newlines. A header line without commas but with semicolons or tabs switches the
/// delimiter (European Excel exports). Completely blank lines are skipped. Invalid UTF-8 is rejected rather than guessed.
public enum ScheduleCSV {
    public static let maxBytes = 32 * 1024 * 1024
    public static let maxRows = 200_000
    public static let maxColumns = 1_000
    public static let maxFieldBytes = 64 * 1024
    /// Header used for the optional element-id column and accepted as a key column.
    public static let elementIDColumn = "Element ID"

    // MARK: Export

    public static func export(_ table: ScheduleTable) -> Data { export(table, includeElementIDs: false) }

    /// Export with an optional leading "Element ID" column (ids of each data row, `;`-separated for grouped rows),
    /// which makes a reliable key for re-import.
    public static func export(_ table: ScheduleTable, includeElementIDs: Bool) -> Data {
        let n = table.columns.count
        let withIDs = includeElementIDs && !table.columns.contains { $0.heading == elementIDColumn }
        var records: [[String]] = []
        records.append((withIDs ? [elementIDColumn] : []) + table.columns.map(\.heading))
        for r in table.rows {
            var cells: [String]
            switch r.kind {
            case .data, .groupFooter, .grandTotal:
                cells = r.cells.map(\.text)
                if r.kind != .data, !r.title.isEmpty {
                    if cells.isEmpty { cells = [r.title] } else if cells[0].isEmpty { cells[0] = r.title }
                }
            case .groupHeader:
                cells = [r.title]
            case .blank:
                cells = []
            }
            if cells.count < n { cells += Array(repeating: "", count: n - cells.count) }
            if withIDs { cells.insert(r.kind == .data ? r.elementIDs.map { String($0.raw) }.joined(separator: ";") : "", at: 0) }
            records.append(cells)
        }
        var out = Data([0xEF, 0xBB, 0xBF])
        for rec in records {
            out.append(contentsOf: Array((rec.map(encodeField).joined(separator: ",") + "\r\n").utf8))
        }
        return out
    }

    static func encodeField(_ s: String) -> String {
        var v = s
        if let f = v.unicodeScalars.first {
            let risky = f == "=" || f == "@" || f == "\t" || f == "\r" || ((f == "+" || f == "-") && Double(v) == nil)
            if risky { v = "'" + v }
        }
        let needsQuotes = v.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == ";" }
            || v.first == " " || v.last == " "
        return needsQuotes ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
    }

    /// Removes the formula-injection guard added by `export`.
    static func decodeCell(_ s: String) -> String {
        guard s.hasPrefix("'"), let second = s.unicodeScalars.dropFirst().first else { return s }
        if second == "=" || second == "@" || second == "\t" || second == "\r" || second == "+" || second == "-" { return String(s.dropFirst()) }
        return s
    }

    // MARK: Parse

    /// Robust RFC 4180 parser. Throws `ScheduleCSVError` for invalid encoding, unterminated quotes or exceeded limits.
    public static func parse(_ data: Data) throws -> [[String]] {
        guard data.count <= maxBytes else {
            throw ScheduleCSVError("The file is too large (\(data.count / 1_048_576) MB). The limit is \(maxBytes / 1_048_576) MB.")
        }
        var bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes.removeFirst(3)
        } else if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            guard let s = String(data: data, encoding: .utf16) else { throw ScheduleCSVError("The file is not valid UTF-16 text.") }
            bytes = Array(s.utf8)
        }
        guard String(bytes: bytes, encoding: .utf8) != nil else {
            throw ScheduleCSVError("The file is not valid UTF-8 text. Save it as “CSV UTF-8” and try again.")
        }
        if bytes.contains(0) { throw ScheduleCSVError("The file contains binary data and is not a CSV file.") }

        let quote = UInt8(ascii: "\""), cr = UInt8(ascii: "\r"), lf = UInt8(ascii: "\n")
        let delimiter = detectDelimiter(bytes)
        var rows: [[String]] = []
        var row: [String] = []
        var field: [UInt8] = []
        field.reserveCapacity(64)
        var inQuotes = false, quoted = false
        var line = 1, quoteLine = 1
        var i = 0
        let n = bytes.count

        func endField() throws {
            row.append(String(decoding: field, as: UTF8.self))
            field.removeAll(keepingCapacity: true)
            quoted = false
            if row.count > maxColumns { throw ScheduleCSVError("Line \(line) has more than \(maxColumns) columns.") }
        }
        func endRow() throws {
            defer { row.removeAll(keepingCapacity: true) }
            if row.count == 1 && row[0].isEmpty { return }
            rows.append(row)
            if rows.count > maxRows { throw ScheduleCSVError("The file has more than \(maxRows) rows.") }
        }

        while i < n {
            let b = bytes[i]
            if inQuotes {
                if b == quote {
                    if i + 1 < n && bytes[i + 1] == quote { field.append(quote); i += 2; continue }
                    inQuotes = false
                } else {
                    if b == lf || (b == cr && !(i + 1 < n && bytes[i + 1] == lf)) { line += 1 }
                    field.append(b)
                    if field.count > maxFieldBytes { throw ScheduleCSVError("A value starting on line \(quoteLine) is longer than \(maxFieldBytes / 1024) KB.") }
                }
                i += 1
                continue
            }
            if b == quote && field.isEmpty && !quoted {
                inQuotes = true; quoted = true; quoteLine = line
            } else if b == delimiter {
                try endField()
            } else if b == cr || b == lf {
                try endField()
                try endRow()
                if b == cr && i + 1 < n && bytes[i + 1] == lf { i += 1 }
                line += 1
            } else {
                // Characters after a closing quote, or stray quotes inside an unquoted field, are kept literally.
                field.append(b)
                if field.count > maxFieldBytes { throw ScheduleCSVError("A value on line \(line) is longer than \(maxFieldBytes / 1024) KB.") }
            }
            i += 1
        }
        if inQuotes { throw ScheduleCSVError("A quoted value starting on line \(quoteLine) is never closed.") }
        if !field.isEmpty || !row.isEmpty || quoted {
            try endField()
            try endRow()
        }
        return rows
    }

    static func detectDelimiter(_ bytes: [UInt8]) -> UInt8 {
        var commas = 0, semis = 0, tabs = 0, inQ = false
        for b in bytes {
            if b == UInt8(ascii: "\"") { inQ.toggle(); continue }
            if inQ { continue }
            if b == UInt8(ascii: "\n") || b == UInt8(ascii: "\r") { break }
            if b == UInt8(ascii: ",") { commas += 1 } else if b == UInt8(ascii: ";") { semis += 1 } else if b == UInt8(ascii: "\t") { tabs += 1 }
        }
        if commas == 0 && (semis > 0 || tabs > 0) { return semis >= tabs ? UInt8(ascii: ";") : UInt8(ascii: "\t") }
        return UInt8(ascii: ",")
    }

    // MARK: Import

    static func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// Matches rows to schedule elements by a key column (e.g. "Mark" or "Element ID") and prepares changes ONLY for
    /// explicitly selected writable columns; validates through `Parameters.parse` and read-only checks.
    ///
    /// Throws `ScheduleCSVError` when the file can't be read or has no usable key column. Everything else — unknown or
    /// read-only columns, invalid values, ambiguous keys, ragged rows, conflicting type values — is reported per cell in
    /// `errors`, and the affected cells produce no change.
    public static func preview(_ data: Data, schedule: Element, model: BIMModel, keyColumn: String, columns: Set<String>) throws -> CSVImportPreview {
        guard schedule.schedule != nil else { throw ScheduleCSVError("“\(schedule.name)” is not a schedule.") }
        let records = try parse(data)
        guard let header = records.first else { throw ScheduleCSVError("The file is empty.") }
        var headerIndex: [String: Int] = [:]
        for (i, h) in header.enumerated() where headerIndex[norm(h)] == nil { headerIndex[norm(h)] = i }
        guard let keyIdx = headerIndex[norm(keyColumn)] else { throw ScheduleCSVError("The file has no “\(keyColumn)” column.") }

        let table = ScheduleEngine.compute(schedule, model)
        var fieldIndex: [String: Int] = [:]
        for (i, c) in table.columns.enumerated() where fieldIndex[norm(c.heading)] == nil { fieldIndex[norm(c.heading)] = i }
        let dataRows = table.rows.filter { $0.kind == .data && !$0.elementIDs.isEmpty }
        let scheduled = Set(dataRows.flatMap(\.elementIDs))

        // Key resolution.
        enum KeyMode { case elementID, column(Int) }
        let mode: KeyMode
        var byKey: [String: [[ElementID]]] = [:]
        if let ci = fieldIndex[norm(keyColumn)] {
            mode = .column(ci)
            for r in dataRows where ci < r.cells.count {
                let k = r.cells[ci].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty { byKey[k, default: []].append(r.elementIDs) }
            }
        } else if norm(keyColumn) == norm(elementIDColumn) {
            mode = .elementID
        } else {
            throw ScheduleCSVError("“\(keyColumn)” is not a column of “\(schedule.name)”, so rows can't be matched by it.")
        }

        var errors: [CSVImportPreview.RowError] = []
        // Selected columns → (csv index, heading, parameter).
        var targets: [(csv: Int, heading: String, pid: ParameterID)] = []
        for c in columns.sorted() {
            if norm(c) == norm(keyColumn) {
                errors.append(.init(row: 1, column: c, message: "The key column can't be updated by the import that uses it to match rows.")); continue
            }
            guard let csvIdx = headerIndex[norm(c)] else {
                errors.append(.init(row: 1, column: c, message: "The file has no “\(c)” column.")); continue
            }
            guard let fi = fieldIndex[norm(c)] else {
                errors.append(.init(row: 1, column: c, message: "“\(c)” is not a column of “\(schedule.name)”.")); continue
            }
            guard case .parameter(let pid) = table.columns[fi].source else {
                errors.append(.init(row: 1, column: c, message: "“\(c)” is calculated and read-only.")); continue
            }
            targets.append((csvIdx, header[csvIdx], pid))
        }

        var entriesCache: [ElementID: [ParameterEntry]] = [:]
        func entry(_ id: ElementID, _ pid: ParameterID) -> ParameterEntry? {
            if entriesCache[id] == nil { entriesCache[id] = model[id].map { Parameters.allEntries($0, model) } ?? [] }
            return entriesCache[id]!.first { $0.id == pid }
        }

        var changes: [CSVImportPreview.Change] = []
        var unmatched: [String] = []
        // (target element — the type for type parameters — , parameter) → (value, row) for conflict detection.
        var planned: [String: (ParamValue, Int)] = [:]
        let keyHeading = header[keyIdx]
        for (ri, rec) in records.enumerated().dropFirst() {
            let rowNumber = ri + 1
            if rec.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            let key = keyIdx < rec.count ? decodeCell(rec[keyIdx]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if key.isEmpty {
                // Group headers, blank lines and totals rows have no key and nothing to import; anything else is an error.
                let hasValues = targets.contains { $0.csv < rec.count && !rec[$0.csv].trimmingCharacters(in: .whitespaces).isEmpty }
                if hasValues { errors.append(.init(row: rowNumber, column: keyHeading, message: "The row has no \(keyHeading) value.")) }
                continue
            }
            var ids: [ElementID] = []
            switch mode {
            case .column:
                guard let matches = byKey[key] else { unmatched.append(key); continue }
                if matches.count > 1 {
                    errors.append(.init(row: rowNumber, column: keyHeading, message: "“\(key)” matches \(matches.count) rows of the schedule; make the key unique."))
                    continue
                }
                ids = matches[0]
            case .elementID:
                var bad = false
                for part in key.split(separator: ";") {
                    let t = part.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                    guard let raw = UInt64(t), scheduled.contains(ElementID(raw)) else { bad = true; break }
                    ids.append(ElementID(raw))
                }
                if bad || ids.isEmpty { unmatched.append(key); continue }
            }
            for target in targets {
                guard target.csv < rec.count else {
                    errors.append(.init(row: rowNumber, column: target.heading, message: "The row has only \(rec.count) columns; “\(target.heading)” is missing."))
                    continue
                }
                let newText = decodeCell(rec[target.csv])
                for id in ids {
                    guard let e = model[id], let en = entry(id, target.pid) else {
                        errors.append(.init(row: rowNumber, column: target.heading, message: "“\(target.heading)” doesn't apply to \(key).")); continue
                    }
                    let oldText = Parameters.format(en.value, type: en.type, model: model)
                    if newText == oldText { continue }
                    if en.isReadOnly {
                        let why = en.readOnlyReason.map { " " + $0 } ?? ""
                        errors.append(.init(row: rowNumber, column: target.heading, message: "“\(target.heading)” is read-only.\(why)")); continue
                    }
                    let value: ParamValue
                    switch parseValue(newText, type: en.type, model: model) {
                    case .success(let v): value = v
                    case .failure(let error):
                        errors.append(.init(row: rowNumber, column: target.heading, message: "“\(newText)” is not a valid \(target.heading): \(error.message)")); continue
                    }
                    if let d = value.doubleValue, en.type.unitKind != nil, !d.isFinite {
                        errors.append(.init(row: rowNumber, column: target.heading, message: "“\(newText)” is not a finite number.")); continue
                    }
                    if value == en.value { continue }
                    let owner = en.isType ? (e.isType ? e.id : e.typeID) : e.id
                    let conflictKey = "\(owner?.raw ?? 0)|\(target.pid.key)"
                    if let (prev, prevRow) = planned[conflictKey] {
                        if prev != value {
                            errors.append(.init(row: rowNumber, column: target.heading,
                                                message: "“\(target.heading)” is a type value shared with row \(prevRow), which sets a different value."))
                        }
                        continue
                    }
                    planned[conflictKey] = (value, rowNumber)
                    changes.append(.init(elementID: id, parameterID: target.pid, parameterName: en.name, oldText: oldText, newText: newText, newValue: value))
                }
            }
        }
        return CSVImportPreview(keyColumn: keyColumn, changes: changes, errors: errors, unmatchedKeys: unmatched)
    }

    /// `Parameters.parse`, plus element references written the way `Parameters.format` displays them
    /// ("Family: Type", "A101 - Sheet"), which is how they appear in exported schedules.
    static func parseValue(_ text: String, type: ParamType, model: BIMModel) -> Result<ParamValue, ParameterError> {
        do {
            return .success(try Parameters.parse(text, type: type, model: model))
        } catch {
            if case .elementRef(let c) = type {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let hits = model.elements(c).filter { Parameters.format(.ref($0.id), type: type, model: model) == t }
                if hits.count == 1 { return .success(.ref(hits[0].id)) }
            }
            return .failure(error)
        }
    }

    /// Applies a preview inside a transaction (uses `Parameters.set`). Throws if an element was deleted or a value
    /// changed since the preview was made. Returns the number of parameter values written.
    public static func apply(_ preview: CSVImportPreview, in tx: TransactionContext) throws -> Int {
        var count = 0
        for c in preview.changes {
            guard let e = tx.model[c.elementID] else {
                throw ScheduleCSVError("An element in the import (\(c.elementID)) no longer exists. Preview the file again.")
            }
            if let en = Parameters.allEntries(e, tx.model).first(where: { $0.id == c.parameterID }) {
                let current = Parameters.format(en.value, type: en.type, model: tx.model)
                if current != c.oldText && en.value != c.newValue {
                    throw ScheduleCSVError("“\(c.parameterName)” of \(e.mark.isEmpty ? e.name : e.mark) changed since the preview (now “\(current)”). Preview the file again.")
                }
                if en.value == c.newValue { continue }
            }
            do {
                try Parameters.set(c.parameterID, to: c.newValue, on: c.elementID, in: tx)
            } catch {
                throw ScheduleCSVError("Couldn't set “\(c.parameterName)”: \(error.message)")
            }
            count += 1
        }
        return count
    }
}
