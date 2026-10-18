import Foundation

/// Accumulates entity instances with deterministic, sequential numbering and serializes a Part 21 file.
final class STEPWriter {
    private var records: [Int: String] = [:]
    private var reserved: Set<Int> = []
    private var next = 1
    /// Instance counts per entity class (as passed to `add`, e.g. "IfcWall").
    private(set) var counts: [String: Int] = [:]

    var entityCount: Int { records.count }

    /// Adds an instance and returns its id. `type` is the schema name in any case ("IfcWall").
    @discardableResult
    func add(_ type: String, _ args: [STEPValue]) -> Int {
        let id = next
        next += 1
        define(id, type, args)
        return id
    }

    /// Reserves an id for an instance whose attributes are only known later (forward references).
    func reserve() -> Int {
        let id = next
        next += 1
        reserved.insert(id)
        return id
    }

    func define(_ id: Int, _ type: String, _ args: [STEPValue]) {
        reserved.remove(id)
        var s = "#\(id)="
        s += type.uppercased()
        s += "("
        for (i, a) in args.enumerated() {
            if i > 0 { s += "," }
            STEPFormat.write(a, into: &s)
        }
        s += ");"
        records[id] = s
        counts[type, default: 0] += 1
    }

    func serialize(header: STEPHeader) -> Data {
        precondition(reserved.isEmpty, "STEPWriter: reserved ids were never defined: \(reserved.sorted())")
        var out = "ISO-10303-21;\nHEADER;\n"
        func list(_ l: [String]) -> String { "(" + l.map(STEPFormat.string).joined(separator: ",") + ")" }
        out += "FILE_DESCRIPTION(\(list(header.description)),\(STEPFormat.string(header.implementationLevel)));\n"
        out += "FILE_NAME(\(STEPFormat.string(header.name)),\(STEPFormat.string(header.timeStamp)),\(list(header.author)),\(list(header.organization)),"
        out += "\(STEPFormat.string(header.preprocessorVersion)),\(STEPFormat.string(header.originatingSystem)),\(STEPFormat.string(header.authorization)));\n"
        out += "FILE_SCHEMA(\(list(header.schemas)));\nENDSEC;\nDATA;\n"
        for id in records.keys.sorted() {
            out += records[id]!
            out += "\n"
        }
        out += "ENDSEC;\nEND-ISO-10303-21;\n"
        return Data(out.utf8)
    }
}

// MARK: - Value constructors used by the exporter

extension STEPValue {
    static func r(_ id: Int) -> STEPValue { .ref(id) }
    static func rOpt(_ id: Int?) -> STEPValue { id.map { .ref($0) } ?? .null }
    static func refs(_ ids: [Int]) -> STEPValue { .list(ids.map { .ref($0) }) }
    static func s(_ x: String) -> STEPValue { .string(x) }
    /// String or `$` when empty.
    static func sOpt(_ x: String?) -> STEPValue { (x?.isEmpty ?? true) ? .null : .string(x!) }
    static func e(_ x: String) -> STEPValue { .enumeration(x) }
    static func b(_ x: Bool) -> STEPValue { .enumeration(x ? "T" : "F") }
    static func d(_ x: Double) -> STEPValue { .real(x) }
    static func reals(_ xs: [Double]) -> STEPValue { .list(xs.map { .real($0) }) }
    static func label(_ x: String) -> STEPValue { .typed("IFCLABEL", [.string(x)]) }
    static func identifier(_ x: String) -> STEPValue { .typed("IFCIDENTIFIER", [.string(x)]) }
    static func text(_ x: String) -> STEPValue { .typed("IFCTEXT", [.string(x)]) }
    static func boolean(_ x: Bool) -> STEPValue { .typed("IFCBOOLEAN", [.b(x)]) }
    static func lengthMeasure(_ x: Double) -> STEPValue { .typed("IFCLENGTHMEASURE", [.real(x)]) }
    static func positiveLength(_ x: Double) -> STEPValue { .typed("IFCPOSITIVELENGTHMEASURE", [.real(x)]) }
    static func areaMeasure(_ x: Double) -> STEPValue { .typed("IFCAREAMEASURE", [.real(x)]) }
    static func measure(_ x: Double, _ type: String) -> STEPValue { .typed(type, [.real(x)]) }
}
