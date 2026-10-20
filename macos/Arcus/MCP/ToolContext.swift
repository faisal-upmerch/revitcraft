import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication

// MCP: what every tool handler gets: its arguments, the document, unit conversion and name lookup (Docs/MCP.md §4).

/// Arguments of one call with typed, validating accessors. Missing or malformed values throw actionable errors.
public struct ToolArgs: Sendable {
    public var values: [String: JSONValue]
    public init(_ values: [String: JSONValue]) { self.values = values }
    public subscript(_ key: String) -> JSONValue? { values[key].flatMap { $0.isNull ? nil : $0 } }

    public func string(_ key: String) -> String? { self[key]?.stringValue ?? self[key]?.intValue.map(String.init) }
    public func requireString(_ key: String) throws(ToolError) -> String {
        guard let s = string(key), !s.trimmingCharacters(in: .whitespaces).isEmpty else { throw ToolError("Missing “\(key)”.") }
        return s
    }
    public func bool(_ key: String, default d: Bool) -> Bool { self[key]?.boolValue ?? d }
    public func int(_ key: String) -> Int? { self[key]?.intValue }
    public func double(_ key: String) -> Double? { self[key]?.doubleValue ?? self[key]?.stringValue.flatMap(Double.init) }
    public func array(_ key: String) -> [JSONValue]? { self[key]?.arrayValue }
    public func requireArray(_ key: String) throws(ToolError) -> [JSONValue] {
        guard let a = array(key), !a.isEmpty else { throw ToolError("“\(key)” must be a non-empty array.") }
        return a
    }
}

/// The document and helpers a handler works with.
@MainActor
public final class ToolContext {
    public let host: any DocumentHost
    public let args: ToolArgs

    /// AITOOLS: the toolbox running the call (mode, active view, family host).
    public weak var toolbox: ArcusToolbox?

    init(host: any DocumentHost, args: ToolArgs) { self.host = host; self.args = args }

    public func session() throws(ToolError) -> DocumentSession {
        guard let s = host.session else {
            throw ToolError("No document is open. Call create_project (or create_furniture) to start one, or open_document to open a file.")
        }
        return s
    }
    public func model() throws(ToolError) -> BIMModel { try session().model }

    // MARK: Units

    /// Meters per document unit: ft (Imperial projects), mm (Metric projects), in (Furniture documents).
    public static func unitScale(_ m: BIMModel) -> (meters: Double, symbol: String) {
        if m.isFurniture { return (0.0254, "in") }
        return m.units.system == .imperial ? (0.3048, "ft") : (0.001, "mm")
    }

    /// A length from a number (document units) or text such as `12'-6"`, `3600 mm` or `30"`. Returns meters.
    public func length(_ v: JSONValue, _ what: String) throws(ToolError) -> Double {
        let m = try model()
        let scale = Self.unitScale(m).meters
        if let d = v.doubleValue { return d * scale }
        guard let s = v.stringValue?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { throw ToolError("“\(what)” must be a length (a number or text like 12'-6\").") }
        if let d = Double(s) { return d * scale }
        do { return try QuantityParser.parse(s, kind: .length, units: m.isFurniture ? .imperial : m.units) } catch {
            throw ToolError("“\(what)”: can't read “\(s)” as a length. Use a number in \(Self.unitScale(m).symbol) or text like 12'-6\" or 3600 mm.")
        }
    }
    public func length(_ key: String) throws(ToolError) -> Double? {
        guard let v = args[key] else { return nil }
        return try length(v, key)
    }
    public func requireLength(_ key: String) throws(ToolError) -> Double {
        guard let v = try length(key) else { throw ToolError("Missing “\(key)” (a length).") }
        return v
    }

    /// A plan point `[x, y]` or `{"x":…,"y":…}` in meters.
    public func point(_ v: JSONValue, _ what: String) throws(ToolError) -> Vec2 {
        if let a = v.arrayValue, a.count >= 2 { return Vec2(try length(a[0], what + ".x"), try length(a[1], what + ".y")) }
        if let x = v["x"], let y = v["y"] { return Vec2(try length(x, what + ".x"), try length(y, what + ".y")) }
        throw ToolError("“\(what)” must be a point [x, y].")
    }
    public func points(_ v: JSONValue, _ what: String, min: Int = 2) throws(ToolError) -> [Vec2] {
        guard let a = v.arrayValue, a.count >= min else { throw ToolError("“\(what)” must be a list of at least \(min) points [[x, y], …].") }
        var out: [Vec2] = []
        for (k, p) in a.enumerated() { out.append(try point(p, "\(what)[\(k)]")) }
        return out
    }

    /// An angle in radians from degrees (CCW from east) or a compass word.
    public func angle(_ v: JSONValue, _ what: String) throws(ToolError) -> Double {
        if let d = v.doubleValue { return d * .pi / 180 }
        switch v.stringValue?.lowercased() {
        case "east", "e", "right": return 0
        case "north", "n", "up": return .pi / 2
        case "west", "w", "left": return .pi
        case "south", "s", "down": return -.pi / 2
        default:
            if let s = v.stringValue, let d = Double(s.replacingOccurrences(of: "°", with: "")) { return d * .pi / 180 }
            throw ToolError("“\(what)” must be degrees (counter-clockwise from east) or north/south/east/west.")
        }
    }

    // MARK: Output values

    /// A length in document units, rounded for display in results.
    public func out(_ meters: Double, _ m: BIMModel) -> JSONValue { .double((meters / Self.unitScale(m).meters * 10_000).rounded() / 10_000) }
    public func out(_ p: Vec2, _ m: BIMModel) -> JSONValue { [out(p.x, m), out(p.y, m)] }
    public func formatLength(_ meters: Double, _ m: BIMModel) -> String {
        QuantityFormatter.format(meters, kind: .length, units: m.isFurniture ? .imperial : m.units, locale: Locale(identifier: "en_US_POSIX"))
    }
    public func formatArea(_ m2: Double, _ m: BIMModel) -> String {
        QuantityFormatter.format(m2, kind: .area, units: m.isFurniture ? .imperial : m.units, locale: Locale(identifier: "en_US_POSIX"))
    }
    /// Area as a number in SF (Imperial) or m² (Metric).
    public func areaNumber(_ m2: Double, _ m: BIMModel) -> JSONValue {
        let v = m.units.system == .imperial || m.isFurniture ? m2 / (0.3048 * 0.3048) : m2
        return .double((v * 10).rounded() / 10)
    }

    // MARK: Lookup

    public func element(_ v: JSONValue, _ what: String) throws(ToolError) -> Element {
        let m = try model()
        guard let raw = v.intValue, raw >= 0 else { throw ToolError("“\(what)” must be an element id (an integer from an earlier result).") }
        guard let e = m[ElementID(UInt64(raw))] else { throw ToolError("No element \(raw) in the document. query_model lists elements and their ids.") }
        return e
    }
    public func elementIDs(_ key: String) throws(ToolError) -> [ElementID] {
        guard let a = args[key]?.arrayValue ?? args[key].map({ [$0] }) else { throw ToolError("Missing “\(key)” (element ids).") }
        var out: [ElementID] = []
        for (k, v) in a.enumerated() { out.append(try element(v, "\(key)[\(k)]").id) }
        return out
    }

    /// A level by name (case-insensitive) or id; nil value → the lowest level.
    public func level(_ v: JSONValue?, _ what: String = "level") throws(ToolError) -> Element {
        let m = try model()
        let levels = m.levels.sorted { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) }
        guard let v else {
            guard let l = levels.first else { throw ToolError("The document has no levels. Call add_level first.") }
            return l
        }
        if let raw = v.intValue, let e = m[ElementID(UInt64(max(0, raw)))], e.level != nil { return e }
        if let s = v.stringValue {
            if let e = levels.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) { return e }
            let hits = levels.filter { $0.name.lowercased().contains(s.lowercased()) }
            if hits.count == 1 { return hits[0] }
        }
        throw ToolError("No level “\(v.stringValue ?? v.jsonText)”. Levels: \(levels.map(\.name).joined(separator: ", ")).")
    }

    /// The display label of a type: "Family: Type" for loadable families, else the type name.
    public static func typeLabel(_ t: Element, _ m: BIMModel) -> String {
        let fam = m[t.typeData?.familyID]?.name ?? t.typeData?.familyName ?? ""
        return fam.isEmpty || fam == t.name ? t.name : "\(fam): \(t.name)"
    }

    /// Lower-case words and numbers: "36x80" → ["36", "x", "80"].
    static func tokens(_ s: String) -> [String] {
        var out: [String] = [], cur = ""
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber {
                if let last = cur.last, last.isNumber != ch.isNumber { out.append(cur); cur = "" }
                cur.append(ch)
            } else if !cur.isEmpty { out.append(cur); cur = "" }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// A type of `category` by id, exact name, "Family: Type", or a unique (else shortest) token match.
    public func type(_ v: JSONValue?, category: ArcusDomain.Category, what: String = "type", default fallback: (([Element]) -> Element?)? = nil) throws(ToolError) -> Element {
        let m = try model()
        let types = m.types(for: category)
        guard let v else {
            if let f = fallback?(types) ?? types.first { return f }
            throw ToolError("The document has no \(category.displayName.lowercased()) types. list_families shows what can be loaded.")
        }
        if let raw = v.intValue, let e = m[ElementID(UInt64(max(0, raw)))], e.typeData?.instanceCategory == category { return e }
        guard let s = v.stringValue else { throw ToolError("“\(what)” must be a type name or id.") }
        if let e = types.first(where: { $0.name == s || Self.typeLabel($0, m) == s }) { return e }
        if let e = types.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame || Self.typeLabel($0, m).caseInsensitiveCompare(s) == .orderedSame }) { return e }
        let q = Self.tokens(s)
        let hits = types.filter { t in let hay = Self.tokens(Self.typeLabel(t, m)); return q.allSatisfy { w in hay.contains(where: { $0.hasPrefix(w) }) } }
        if let best = hits.min(by: { Self.typeLabel($0, m).count < Self.typeLabel($1, m).count }) { return best }
        let close = types.map { Self.typeLabel($0, m) }.sorted { a, b in
            Self.tokens(a).filter { q.contains($0) }.count > Self.tokens(b).filter { q.contains($0) }.count
        }.prefix(8)
        throw ToolError("No \(category.singularName.lowercased()) type matches “\(s)”. Closest: \(close.joined(separator: "; ")). list_types shows them all.")
    }

    /// A view by name or id (optionally of given kinds).
    public func view(_ v: JSONValue?, what: String = "view", kinds: Set<ViewKind>? = nil, allowSheets: Bool = false) throws(ToolError) -> Element {
        let m = try model()
        let candidates = m.views.filter { e in kinds.map { k in e.view.map { k.contains($0.kind) } ?? false } ?? true } + (allowSheets ? m.sheets : [])
        guard let v else { throw ToolError("Missing “\(what)”. Views: \(candidates.prefix(20).map(\.name).joined(separator: ", ")).") }
        if let raw = v.intValue, let e = m[ElementID(UInt64(max(0, raw)))], candidates.contains(where: { $0.id == e.id }) { return e }
        if let s = v.stringValue {
            if allowSheets, let e = m.sheets.first(where: { $0.sheet?.number.caseInsensitiveCompare(s) == .orderedSame }) { return e }
            let exact = candidates.filter { $0.name.caseInsensitiveCompare(s) == .orderedSame }
            // Plan names repeat across kinds ("Level 1" floor plan and ceiling plan): prefer floor plans.
            if let e = exact.first(where: { $0.view?.kind == .floorPlan }) ?? exact.first { return e }
            let hits = candidates.filter { $0.name.lowercased().contains(s.lowercased()) }
            if let e = hits.first(where: { $0.view?.kind == .floorPlan }) ?? (hits.count == 1 ? hits[0] : nil) { return e }
        }
        throw ToolError("No \(what) “\(v.stringValue ?? v.jsonText)”. Views: \(candidates.prefix(30).map { "\($0.name) (\($0.view?.kind.rawValue ?? "Sheet \($0.sheet?.number ?? "")"))" }.joined(separator: ", ")).")
    }

    /// The floor plan of a level, if any.
    public func planView(of level: ElementID, _ m: BIMModel) -> Element? {
        m.views.first { $0.levelID == level && $0.view?.kind == .floorPlan }
    }

    // MARK: Editing

    /// Runs `body` as one transaction on the document. Throws the rejection as an actionable error.
    /// Whether this call has opened its undo group (on its first edit, so a call that changes nothing adds no step).
    var undoGroupOpen = false
    /// False for calls that manage undo themselves (undo, redo) or replace the document.
    var groupsUndo = true

    @discardableResult
    public func edit(_ name: String, _ body: (TransactionContext) throws -> Void) throws(ToolError) -> TransactionRecord? {
        let s = try session()
        if groupsUndo && !undoGroupOpen {
            s.undoManager.beginUndoGrouping()
            undoGroupOpen = true
        }
        if healthBefore == nil { healthBefore = ModelHealth.check(s.model) }
        healthAfterCache = nil
        do {
            let r = try s.performThrowing(name, body)
            if let r { records.append(r) }
            return r
        } catch let e as TransactionError {
            throw ToolError(e.message + (e.resolution.map { " " + $0 } ?? ""))
        } catch {
            throw ToolError("\(error)")
        }
    }

    /// AITOOLS: model health before this call's first edit, and the call's transactions (the verification block).
    var healthBefore: [ModelWarning]?
    var records: [TransactionRecord] = []
    /// Health after the call, computed once.
    var healthAfterCache: [ModelWarning]?
    func healthAfter() -> [ModelWarning] {
        if let h = healthAfterCache { return h }
        let h = host.session.map { ModelHealth.check($0.model) } ?? []
        healthAfterCache = h
        return h
    }

    /// What this call changed and whether it left new problems: `{"ok", "problems", "changed", "health_delta"}`.
    public func verification(ids: [ElementID], extra: [String] = []) -> JSONValue {
        let after = healthAfter()
        let beforeIDs = Set((healthBefore ?? after).map(\.id))
        let fresh = after.filter { !beforeIDs.contains($0.id) && $0.severity >= .warning }
        var problems = fresh.prefix(8).map(\.message) + extra
        if let e = host.session?.lastWarnings.filter({ $0.severity == .error }).first, !problems.contains(e.message) { problems.append(e.message) }
        var created = 0, modified = 0, deleted = 0
        for r in records {
            for ch in r.changes {
                switch (ch.before == nil, ch.after == nil) {
                case (true, false): created += 1
                case (false, true): deleted += 1
                default: modified += 1
                }
            }
        }
        var o: [String: JSONValue] = ["ok": .bool(problems.isEmpty), "problems": .array(problems.map { .string($0) })]
        if !records.isEmpty { o["changed"] = ["created": .int(created), "modified": .int(modified), "deleted": .int(deleted)] }
        if let b = healthBefore, after.count != b.count { o["health_delta"] = .int(after.count - b.count) }
        return .object(o)
    }

    /// Ids created by a transaction, in creation order.
    public static func created(_ r: TransactionRecord?) -> [ElementID] {
        (r?.changes ?? []).filter { $0.before == nil && $0.after != nil }.map(\.id).sorted()
    }

    /// The commit's warnings and the model health items about `ids`, plus the document's health count.
    public func checks(_ ids: [ElementID]) -> [String: JSONValue] {
        guard let s = host.session else { return [:] }
        let set = Set(ids)
        let health = healthAfter()
        var items = s.lastWarnings.filter { $0.severity != .info || set.isEmpty || !set.isDisjoint(with: $0.elements) }
        for w in health where !set.isDisjoint(with: w.elements) && !items.contains(where: { $0.id == w.id }) { items.append(w) }
        var out: [String: JSONValue] = ["health": .int(health.count)]
        if !items.isEmpty { out["warnings"] = .array(items.prefix(12).map(Self.warningJSON)) }
        return out
    }

    static func warningJSON(_ w: ModelWarning) -> JSONValue {
        ["severity": .string(w.severity.rawValue), "message": .string(w.message), "elements": .array(w.elements.prefix(10).map { .int(Int($0.raw)) })]
    }
}

extension ElementID {
    var json: JSONValue { .int(Int(raw)) }
}
