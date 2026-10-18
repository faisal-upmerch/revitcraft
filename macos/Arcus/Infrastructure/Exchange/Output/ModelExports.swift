import Foundation
import ArcusGeometry
import ArcusDomain

// F13: File ▸ Export ▸ STL, gbXML, Reports ▸ Room/Area Report and Family Types (ports of RevitCraft rc-core
// imports.rs `write_stl`, `write_gbxml`, `room_report`, `family_type_catalog`). Everything is written locally.

/// Model elements exported as geometry: main model plus primary design options, existing in the latest phase.
enum ExportScope {
    static func modelElements(_ model: BIMModel) -> [Element] {
        model.allElements.filter { e in
            guard !e.isType, e.ownerViewID == nil, e.category.isModel, ElementMeshes.hasModelGeometry(e) else { return false }
            if let o = e.designOptionID, model[o]?.designOption?.isPrimary == false { return false }
            if e.phaseDemolished != nil { return false }
            return true
        }
    }
}

/// Binary STL of the 3D model (millimetres, as RevitCraft writes it).
public enum STLExporter {
    public static func write(_ model: BIMModel) -> (data: Data, triangles: Int) {
        var tris: [(Vec3, Vec3, Vec3)] = []
        for e in ExportScope.modelElements(model) {
            for part in ElementMeshes.parts(e, model) {
                let m = part.mesh
                var i = 0
                while i + 2 < m.indices.count {
                    let a = Int(m.indices[i]), b = Int(m.indices[i + 1]), c = Int(m.indices[i + 2])
                    if a < m.positions.count, b < m.positions.count, c < m.positions.count { tris.append((m.positions[a], m.positions[b], m.positions[c])) }
                    i += 3
                }
            }
        }
        var out = Data(count: 80)
        let header = Array("Arcus STL export (mm)".utf8)
        out.replaceSubrange(0..<header.count, with: header)
        appendLE(&out, UInt32(tris.count))
        for (a, b, c) in tris {
            let nrm = (b - a).cross(c - a)
            let len = nrm.length
            let unit = len > 0 ? nrm / len : Vec3(0, 0, 0)
            for v in [unit, a * 1000, b * 1000, c * 1000] { for x in [v.x, v.y, v.z] { appendLE(&out, Float(x).bitPattern) } }
            out.append(contentsOf: [0, 0])
        }
        return (out, tris.count)
    }

    static func appendLE(_ d: inout Data, _ v: UInt32) { for s in stride(from: 0, to: 32, by: 8) { d.append(UInt8((v >> UInt32(s)) & 0xFF)) } }
}

/// gbXML: rooms (and areas) as spaces with closed shells — floor, ceiling and one wall face per boundary edge.
public enum GbXMLExporter {
    /// The spaces exported: bounded rooms and areas.
    static func spaces(_ model: BIMModel) -> [(element: Element, profile: Profile2, z0: Double, z1: Double)] {
        (model.elements(.rooms) + model.elements(.areas)).compactMap { r in
            let b = RoomGeometry.boundary(r, model)
            guard b.state == .bounded, let p = b.profile, p.outer.points.count >= 3 else { return nil }
            let z0 = model.baseElevation(of: r)
            let h = RoomGeometry.height(r, model)
            return (r, p, z0, z0 + (h > 0.01 ? h : 2.5))
        }
    }

    public static func write(_ model: BIMModel) -> (text: String, spaces: Int) {
        func f(_ v: Double) -> String { String(format: "%.4f", v) }
        func loop(_ pts: [Vec3]) -> String {
            "<PolyLoop>" + pts.map { "<CartesianPoint><Coordinate>\(f($0.x))</Coordinate><Coordinate>\(f($0.y))</Coordinate><Coordinate>\(f($0.z))</Coordinate></CartesianPoint>" }.joined() + "</PolyLoop>"
        }
        var storeys = ""
        for l in model.levels {
            storeys += "<BuildingStorey id=\"lvl\(l.id.raw)\"><Name>\(esc(l.name))</Name><Level>\(f(l.level?.elevation ?? 0))</Level></BuildingStorey>"
        }
        let list = spaces(model)
        var body = ""
        for s in list {
            let outer = s.profile.outer.signedArea < 0 ? Array(s.profile.outer.points.reversed()) : s.profile.outer.points
            var shell = loop(outer.reversed().map { Vec3($0, z: s.z0) }) + loop(outer.map { Vec3($0, z: s.z1) })
            for i in outer.indices {
                let a = outer[i], b = outer[(i + 1) % outer.count]
                shell += loop([Vec3(a, z: s.z0), Vec3(b, z: s.z0), Vec3(b, z: s.z1), Vec3(a, z: s.z1)])
            }
            let r = s.element.room
            let name = [r?.number ?? "", s.element.name].filter { !$0.isEmpty }.joined(separator: " ")
            let storey = s.element.levelID.map { " buildingStoreyIdRef=\"lvl\($0.raw)\"" } ?? ""
            body += "<Space id=\"sp\(s.element.id.raw)\"\(storey)><Name>\(esc(name))</Name><Area>\(f(s.profile.area))</Area><Volume>\(f(s.profile.area * (s.z1 - s.z0)))</Volume>"
                + "<ShellGeometry id=\"sh\(s.element.id.raw)\"><ClosedShell>\(shell)</ClosedShell></ShellGeometry></Space>"
        }
        let info = model.projectInfo
        let text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gbXML xmlns=\"http://www.gbxml.org/schema\" lengthUnit=\"Meters\" areaUnit=\"SquareMeters\" volumeUnit=\"CubicMeters\" temperatureUnit=\"C\" useSIUnitsForResults=\"true\" version=\"0.37\">"
            + "<Campus id=\"campus\"><Name>\(esc(info.siteName))</Name><Location><Latitude>\(f(info.latitude))</Latitude><Longitude>\(f(info.longitude))</Longitude></Location>"
            + "<Building id=\"building\" buildingType=\"Unknown\"><Name>\(esc(info.projectName))</Name>\(storeys)\(body)</Building></Campus></gbXML>\n"
        return (text, list.count)
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Reports ▸ Room/Area Report: rooms and areas with their level, area, perimeter and (HTML) a drawing of each.
public enum RoomAreaReport {
    public enum Format: String, CaseIterable, Sendable { case html = "HTML", csv = "CSV" }

    struct Row { var number: String; var name: String; var level: String; var kind: String; var area: Double; var perimeter: Double; var profile: Profile2 }

    static func rows(_ model: BIMModel) -> [Row] {
        GbXMLExporter.spaces(model).map { s in
            Row(number: s.element.room?.number ?? "", name: s.element.name, level: model[s.element.levelID]?.name ?? "",
                kind: s.element.category == .areas ? "Area" : "Room", area: s.profile.area, perimeter: s.profile.perimeter, profile: s.profile)
        }.sorted { ($0.kind, $0.level, $0.number) < ($1.kind, $1.level, $1.number) }
    }

    public static func write(_ model: BIMModel, format: Format) -> (text: String, rows: Int) {
        let rows = rows(model)
        func area(_ v: Double) -> String { Parameters.format(.double(v), type: .area, model: model) }
        func length(_ v: Double) -> String { Parameters.format(.double(v), type: .length, model: model) }
        let total = rows.filter { $0.kind == "Room" }.reduce(0) { $0 + $1.area }
        switch format {
        case .csv:
            func q(_ s: String) -> String { s.contains(where: { ",\"\n".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
            var lines = ["Kind,Number,Name,Level,Area,Perimeter"]
            lines += rows.map { [$0.kind, $0.number, $0.name, $0.level, area($0.area), length($0.perimeter)].map(q).joined(separator: ",") }
            lines.append(["Total", "", "", "", area(total), ""].joined(separator: ","))
            return (lines.joined(separator: "\n") + "\n", rows.count)
        case .html:
            var body = ""
            for r in rows {
                let b = r.profile.bounds
                let k = 140 / max(b.width, b.height, 1e-6)
                func pts(_ p: Polygon2) -> String { p.points.map { String(format: "%.1f,%.1f", ($0.x - b.min.x) * k + 5, (b.max.y - $0.y) * k + 5) }.joined(separator: " ") }
                let shape = ([r.profile.outer] + r.profile.holes).map { "<polygon points=\"\(pts($0))\" fill=\"#e8f0fb\" stroke=\"#245\" stroke-width=\"1\"/>" }.joined()
                body += "<tr><td>\(esc(r.kind))</td><td>\(esc(r.number))</td><td>\(esc(r.name))</td><td>\(esc(r.level))</td><td>\(esc(area(r.area)))</td><td>\(esc(length(r.perimeter)))</td><td><svg width=\"150\" height=\"150\">\(shape)</svg></td></tr>"
            }
            let name = esc(model.projectInfo.projectName)
            let html = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Room/Area Report - \(name)</title><style>body{font-family:-apple-system,Helvetica,Arial,sans-serif;margin:24px}table{border-collapse:collapse}td,th{border:1px solid #999;padding:4px 8px;text-align:left;vertical-align:top}th{background:#eee}</style></head><body><h2>Room/Area Report</h2><p>Project: \(name)</p><table><tr><th>Kind</th><th>Number</th><th>Name</th><th>Level</th><th>Area</th><th>Perimeter</th><th>Shape</th></tr>\(body)</table><p>Total room area: \(esc(area(total)))</p></body></html>\n"
            return (html, rows.count)
        }
    }

    static func esc(_ s: String) -> String { GbXMLExporter.esc(s) }
}

/// Export ▸ Family Types: a family's types as a type catalog text file, comma-separated with `Name##KIND##UNITS`
/// headings (RevitCraft `family_type_catalog`), lengths in millimetres.
public enum FamilyTypesExport {
    public static func write(_ family: FamilyDefinition) -> String {
        let params = family.parameters.filter { !$0.isInstance && $0.formula == nil && !isReference($0.type) }
        func kind(_ t: ParamType) -> String {
            switch t {
            case .length: "LENGTH##MILLIMETERS"
            case .area: "AREA##SQUARE_METERS"
            case .volume: "VOLUME##CUBIC_METERS"
            case .angle: "ANGLE##DEGREES"
            default: "OTHER##"
            }
        }
        func value(_ v: ParamValue?, _ t: ParamType) -> String {
            guard let v else { return "" }
            switch t {
            case .length: return v.doubleValue.map { trim($0 * 1000) } ?? ""
            case .angle: return v.doubleValue.map { trim($0 * 180 / .pi) } ?? ""
            case .area, .volume, .number, .currency, .slope, .percentage: return v.doubleValue.map(trim) ?? ""
            case .integer: return v.doubleValue.map { String(Int($0.rounded())) } ?? ""
            case .bool: return (v.boolValue ?? false) ? "1" : "0"
            default: return (v.textValue ?? v.description).replacingOccurrences(of: ",", with: " ")
            }
        }
        var out = params.map { ",\($0.name.replacingOccurrences(of: ",", with: " "))##\(kind($0.type))" }.joined() + "\n"
        for t in family.types {
            out += t.name.replacingOccurrences(of: ",", with: " ")
            for p in params { out += "," + value(t.values[p.name] ?? p.type.defaultValue, p.type) }
            out += "\n"
        }
        return out
    }

    static func isReference(_ t: ParamType) -> Bool { if case .elementRef = t { return true }; return false }
    static func trim(_ v: Double) -> String {
        var s = String(format: "%.4f", v)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
