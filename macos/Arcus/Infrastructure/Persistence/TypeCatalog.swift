import Foundation
import ArcusDomain

/// Type catalogs: family types as CSV (UTF-8, comma-separated, RFC 4180 quoting).
///
/// Row 1 is the header: the first cell is `Type Name` (or empty); every other cell names a family parameter and its
/// value type/unit in brackets, e.g. `Width [length:mm]`, `Fire Rating [text]`, `Glazed [bool]`, `Area [area:m2]`.
/// Each following row is one type: its name, then one value per column. Empty cells leave the parameter unset for
/// that type. Numbers use `.` as the decimal separator; values are converted to SI on import.
/// See Docs/FileFormat.md for the full grammar.
public enum TypeCatalog {
    /// Value kinds accepted in headers.
    enum ValueKind: String, CaseIterable {
        case length, area, volume, angle, slope, number, integer, percentage, currency, text, bool

        var defaultUnit: String? {
            switch self {
            case .length: "mm"
            case .area: "m2"
            case .volume: "m3"
            case .angle: "deg"
            case .slope: "ratio"
            case .percentage: "%"
            default: nil
            }
        }
        /// Unit → rational factor: SI = value × num ÷ den (exact for metric units).
        var units: [String: (num: Double, den: Double)] {
            let inch = 0.0254, foot = 0.3048
            switch self {
            case .length: return ["mm": (1, 1_000), "cm": (1, 100), "m": (1, 1), "in": (inch, 1), "ft": (foot, 1)]
            case .area: return ["mm2": (1, 1_000_000), "cm2": (1, 10_000), "m2": (1, 1), "in2": (inch * inch, 1), "ft2": (foot * foot, 1)]
            case .volume: return ["mm3": (1, 1e9), "cm3": (1, 1e6), "l": (1, 1_000), "m3": (1, 1), "in3": (inch * inch * inch, 1), "ft3": (foot * foot * foot, 1)]
            case .angle: return ["deg": (Double.pi, 180), "rad": (1, 1)]
            case .slope: return ["ratio": (1, 1), "%": (1, 100)]
            case .percentage: return ["%": (1, 100), "fraction": (1, 1)]
            default: return [:]
            }
        }
        func toSI(_ v: Double, unit: String) -> Double? {
            guard let f = units[unit] else { return nil }
            return f.den == 1 ? v * f.num : (f.num == 1 ? v / f.den : v * f.num / f.den)
        }
        func fromSI(_ v: Double, unit: String) -> Double? {
            guard let f = units[unit] else { return nil }
            return f.num == 1 ? v * f.den : v * f.den / f.num
        }

        init?(paramType: ParamType) {
            switch paramType {
            case .length: self = .length
            case .area: self = .area
            case .volume: self = .volume
            case .angle: self = .angle
            case .slope: self = .slope
            case .number: self = .number
            case .integer: self = .integer
            case .percentage: self = .percentage
            case .currency: self = .currency
            case .text, .multilineText, .url, .choice: self = .text
            case .bool: self = .bool
            case .elementRef: return nil
            }
        }
    }

    struct Column {
        var parameter: String
        var kind: ValueKind
        var unit: String?
        var paramType: ParamType
    }

    public struct CatalogError: Error, Sendable, CustomStringConvertible {
        public var description: String
    }

    /// Parses a catalog for `family`. Throws only when the file as a whole is unusable (not UTF-8, no header, bad
    /// first column); per-row and per-column problems are returned in `errors` (prefixed with the 1-based row number)
    /// and those cells or rows are skipped.
    public static func parse(_ data: Data, family: FamilyDefinition) throws -> (types: [FamilyTypeDefinition], errors: [String]) {
        try parse(data, family: family, limits: .default)
    }

    public static func parse(_ data: Data, family: FamilyDefinition, limits: PersistenceLimits) throws -> (types: [FamilyTypeDefinition], errors: [String]) {
        guard data.count <= 64 << 20 else { throw CatalogError(description: "The type catalog is too large (over 64 MB).") }
        guard var text = String(data: data, encoding: .utf8) else {
            throw CatalogError(description: "The type catalog isn’t UTF-8 text. Save it as “CSV UTF-8” and try again.")
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let rows = try csvRows(text, maxRows: limits.maxCatalogRows + 1)
        guard let header = rows.first(where: { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }) else {
            throw CatalogError(description: "The type catalog is empty. The first row must list “Type Name” followed by parameter columns.")
        }
        let headerIndex = rows.firstIndex(where: { $0 == header })!
        let first = header[0].trimmingCharacters(in: .whitespaces).lowercased()
        guard first.isEmpty || first == "type name" || first == "type" || first == "name" else {
            throw CatalogError(description: "The first header cell must be “Type Name” (found “\(header[0])”).")
        }

        var errors: [String] = []
        var columns: [Column?] = [nil]
        var seenParams = Set<String>()
        for (ci, cell) in header.enumerated().dropFirst() {
            let h = cell.trimmingCharacters(in: .whitespaces)
            if h.isEmpty { columns.append(nil); continue }
            switch parseHeader(h, family: family) {
            case .success(let col):
                if seenParams.contains(col.parameter) {
                    errors.append("Row \(headerIndex + 1): column \(ci + 1) repeats parameter “\(col.parameter)”; the column is ignored.")
                    columns.append(nil)
                } else {
                    seenParams.insert(col.parameter)
                    columns.append(col)
                }
            case .failure(let e):
                errors.append("Row \(headerIndex + 1): column \(ci + 1) (“\(h)”): \(e.description) The column is ignored.")
                columns.append(nil)
            }
        }

        var types: [FamilyTypeDefinition] = []
        var names = Set<String>()
        for (ri, row) in rows.enumerated() where ri > headerIndex {
            let rowNumber = ri + 1
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            let name = row[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { errors.append("Row \(rowNumber): the type name is empty; the row is skipped."); continue }
            guard !names.contains(name) else { errors.append("Row \(rowNumber): duplicate type name “\(name)”; the row is skipped."); continue }
            if row.count > header.count { errors.append("Row \(rowNumber): has \(row.count) cells but the header has \(header.count); extra cells are ignored.") }
            var values: [String: ParamValue] = [:]
            var rowOK = true
            for ci in 1..<min(row.count, columns.count) {
                guard let col = columns[ci] else { continue }
                let raw = row[ci].trimmingCharacters(in: .whitespaces)
                if raw.isEmpty { continue }
                switch convert(raw, col) {
                case .success(let v): values[col.parameter] = v
                case .failure(let e):
                    errors.append("Row \(rowNumber): \(col.parameter): \(e.description)")
                    rowOK = false
                }
            }
            guard rowOK else { errors.append("Row \(rowNumber): type “\(name)” was not imported because of the errors above."); continue }
            names.insert(name)
            types.append(FamilyTypeDefinition(name: name, values: values))
        }
        return (types, errors)
    }

    static func parseHeader(_ h: String, family: FamilyDefinition) -> Result<Column, CatalogError> {
        var name = h
        var spec: String?
        if let open = h.lastIndex(of: "["), h.hasSuffix("]") {
            name = h[..<open].trimmingCharacters(in: .whitespaces)
            spec = String(h[h.index(after: open)..<h.index(before: h.endIndex)]).trimmingCharacters(in: .whitespaces).lowercased()
        }
        guard let param = family.parameter(named: name) else {
            return .failure(CatalogError(description: "“\(name)” is not a parameter of \(family.name)."))
        }
        guard let paramKind = ValueKind(paramType: param.type) else {
            return .failure(CatalogError(description: "“\(name)” refers to other elements and can’t be set from a catalog."))
        }
        if param.formula != nil {
            return .failure(CatalogError(description: "“\(name)” is driven by a formula."))
        }
        var kind = paramKind
        var unit = paramKind.defaultUnit
        if let spec {
            let parts = spec.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let kindName = parts[0] == "yes/no" || parts[0] == "yesno" ? "bool" : parts[0]
            guard let k = ValueKind(rawValue: kindName) else {
                return .failure(CatalogError(description: "unknown value type “\(parts[0])” (use \(ValueKind.allCases.map(\.rawValue).joined(separator: ", ")))."))
            }
            guard k == paramKind || (k == .number && [.integer, .currency].contains(paramKind)) else {
                return .failure(CatalogError(description: "declared as \(k.rawValue) but the family parameter is \(param.type.displayName.lowercased())."))
            }
            kind = paramKind
            if parts.count == 2 {
                let u = parts[1].replacingOccurrences(of: "²", with: "2").replacingOccurrences(of: "³", with: "3").replacingOccurrences(of: "°", with: "deg")
                guard kind.units[u] != nil else {
                    let allowed = kind.units.keys.sorted()
                    return .failure(CatalogError(description: allowed.isEmpty ? "\(kind.rawValue) values have no unit." : "unknown unit “\(parts[1])” for \(kind.rawValue) (use \(allowed.joined(separator: ", ")))."))
                }
                unit = u
            }
        }
        return .success(Column(parameter: param.name, kind: kind, unit: unit, paramType: param.type))
    }

    static func convert(_ raw: String, _ col: Column) -> Result<ParamValue, CatalogError> {
        switch col.kind {
        case .text:
            if case .choice(let options) = col.paramType, !options.contains(raw) {
                return .failure(CatalogError(description: "“\(raw)” is not one of \(options.joined(separator: ", "))."))
            }
            return .success(.text(raw))
        case .bool:
            switch raw.lowercased() {
            case "yes", "true", "1", "y": return .success(.bool(true))
            case "no", "false", "0", "n": return .success(.bool(false))
            default: return .failure(CatalogError(description: "“\(raw)” is not Yes or No."))
            }
        case .integer:
            guard let i = Int(raw) else { return .failure(CatalogError(description: "“\(raw)” is not a whole number.")) }
            return .success(.int(i))
        default:
            guard let d = parseNumber(raw) else { return .failure(CatalogError(description: "“\(raw)” is not a number (use digits with “.” as the decimal separator).")) }
            guard let unit = col.unit else { return .success(.double(d)) }
            if [.length, .area, .volume].contains(col.kind), d < 0 {
                return .failure(CatalogError(description: "\(raw) is negative; \(col.kind.rawValue) values must be zero or more."))
            }
            guard let si = col.kind.toSI(d, unit: unit) else { return .failure(CatalogError(description: "unknown unit")) }
            return .success(.double(si))
        }
    }

    static func parseNumber(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: "_", with: "")
        guard t.count <= 64, t.allSatisfy({ $0.isASCII && ($0.isNumber || "+-.eE".contains($0)) }), let d = Double(t), d.isFinite else { return nil }
        return d
    }

    // MARK: Export

    /// Exports every type parameter that a catalog can express (non-formula; no element references), using
    /// mm / m² / m³ / degrees for measured values.
    public static func export(_ family: FamilyDefinition) -> Data {
        let params = family.parameters.filter { $0.formula == nil && !$0.isInstance && ValueKind(paramType: $0.type) != nil }
        var lines: [String] = []
        var header = ["Type Name"]
        for p in params {
            let k = ValueKind(paramType: p.type)!
            header.append(k.defaultUnit.map { "\(p.name) [\(k.rawValue):\($0)]" } ?? "\(p.name) [\(k.rawValue)]")
        }
        lines.append(header.map(quote).joined(separator: ","))
        for t in family.types {
            var row = [t.name]
            for p in params {
                let k = ValueKind(paramType: p.type)!
                guard let v = t.values[p.name] else { row.append(""); continue }
                row.append(format(v, kind: k))
            }
            lines.append(row.map(quote).joined(separator: ","))
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    static func format(_ v: ParamValue, kind: ValueKind) -> String {
        switch kind {
        case .text: return v.textValue ?? v.description
        case .bool: return (v.boolValue ?? false) ? "Yes" : "No"
        case .integer: return v.intValue.map(String.init) ?? ""
        default:
            guard let d = v.doubleValue, d.isFinite else { return "" }
            let display = kind.defaultUnit.flatMap { kind.fromSI(d, unit: $0) } ?? d
            return formatNumber(display)
        }
    }

    /// Up to 9 decimals, trailing zeros trimmed, never exponent notation.
    static func formatNumber(_ d: Double) -> String {
        var s = String(format: "%.9f", d)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    static func quote(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) || s != s.trimmingCharacters(in: .whitespaces) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: CSV

    /// RFC 4180 parser (quoted fields, doubled quotes, CRLF/LF line ends). Rows are padded to at least one cell.
    static func csvRows(_ text: String, maxRows: Int) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var afterQuote = false
        var it = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil
        func next() -> Unicode.Scalar? {
            if let p = pending { pending = nil; return p }
            return it.next()
        }
        while let c = next() {
            if inQuotes {
                if c == "\"" {
                    if let n = next() {
                        if n == "\"" { field.unicodeScalars.append("\"") } else { inQuotes = false; afterQuote = true; pending = n }
                    } else { inQuotes = false }
                } else {
                    field.unicodeScalars.append(c)
                }
                continue
            }
            switch c {
            case "\"":
                if field.trimmingCharacters(in: .whitespaces).isEmpty && !afterQuote { field = ""; inQuotes = true } else { field.unicodeScalars.append(c) }
            case ",":
                row.append(field); field = ""; afterQuote = false
            case "\r":
                if let n = next(), n != "\n" { pending = n }
                fallthrough
            case "\n":
                row.append(field); field = ""; afterQuote = false
                rows.append(row); row = []
                if rows.count > maxRows { throw CatalogError(description: "The type catalog has more than \(maxRows - 1) types.") }
            default:
                if afterQuote && c != " " { field.unicodeScalars.append(c) } else if !afterQuote { field.unicodeScalars.append(c) }
            }
        }
        if inQuotes { throw CatalogError(description: "The type catalog ends inside a quoted value (a closing \" is missing).") }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
