import Foundation
import Compression
import ArcusGeometry
import ArcusDomain

// F67: readers for the Insert tab: point clouds and survey points (XYZ, PTS, CSV, TXT, ASCII PLY), OBJ coordination
// models, gbXML spaces and DWFx markup pages. All of them parse untrusted files with bounded work.

public struct InsertReadError: Error, CustomStringConvertible, Sendable {
    public var description: String
    public init(_ s: String) { description = s }
}

// MARK: - Points

public enum PointFileReader {
    /// Length units a point file can be in. `auto` assumes meters unless the coordinates are evidently millimeters.
    public enum Units: String, CaseIterable, Sendable {
        case auto = "Automatic", meters = "Meters", millimeters = "Millimeters", feet = "Feet", usSurveyFeet = "US survey feet"
        public var scale: Double? {
            switch self {
            case .auto: nil
            case .meters: 1
            case .millimeters: 0.001
            case .feet: 0.3048
            case .usSurveyFeet: 1200.0 / 3937.0
            }
        }
    }

    /// Points of a text point file: lines of `x y z [intensity] [r g b]` separated by spaces, commas, semicolons or tabs.
    /// A PTS count line and other non-numeric lines are skipped. ASCII PLY files are read from their header. At most
    /// `maxPoints` are kept, thinned evenly.
    public static func read(_ text: String, units: Units = .auto, maxPoints: Int = 500_000) throws -> PointSet {
        var raw: [(Vec3, (UInt8, UInt8, UInt8))] = []
        var hasColor = false
        if text.hasPrefix("ply") {
            (raw, hasColor) = try readPLY(text)
        } else {
            var colorScaleOne = true
            var rows: [[Double]] = []
            for line in text.split(whereSeparator: \.isNewline) {
                let v = line.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " || $0 == "\t" }).compactMap { Double($0) }
                guard v.count >= 3, v[0].isFinite, v[1].isFinite, v[2].isFinite else { continue }
                if v.count >= 6 { hasColor = true; if v[(v.count - 3)...].contains(where: { $0 > 1 }) { colorScaleOne = false } }
                rows.append(v)
                if rows.count > 20_000_000 { break }
            }
            for v in rows {
                var c: (UInt8, UInt8, UInt8) = (128, 128, 128)
                if hasColor, v.count >= 6 {
                    let k = colorScaleOne ? 255.0 : 1.0
                    func b(_ x: Double) -> UInt8 { UInt8(max(0, min(255, (x * k).rounded()))) }
                    c = (b(v[v.count - 3]), b(v[v.count - 2]), b(v[v.count - 1]))
                }
                raw.append((Vec3(v[0], v[1], v[2]), c))
            }
        }
        guard raw.count >= 2 else { throw InsertReadError("No points were found. Each line should hold x y z (optionally followed by r g b).") }
        let span = raw.reduce(0.0) { max($0, abs($1.0.x), abs($1.0.y), abs($1.0.z)) }
        let scale = units.scale ?? (span > 5000 ? 0.001 : 1)
        let step = max(1, (raw.count + max(1, maxPoints) - 1) / max(1, maxPoints))
        let kept = stride(from: 0, to: raw.count, by: step).map { (raw[$0].0 * scale, raw[$0].1) }
        return PointSet(points: kept, sourceCount: raw.count, hasColor: hasColor, unitScale: scale)
    }

    static func readPLY(_ text: String) throws -> ([(Vec3, (UInt8, UInt8, UInt8))], Bool) {
        var lines = text.split(whereSeparator: \.isNewline).makeIterator()
        var count = 0, props: [String] = [], inVertex = false, ascii = false
        while let l = lines.next() {
            let w = l.split(separator: " ").map(String.init)
            if w.first == "format" { ascii = w.count > 1 && w[1] == "ascii" }
            if w.first == "element" { inVertex = w.count > 2 && w[1] == "vertex"; if inVertex { count = Int(w[2]) ?? 0 } }
            if w.first == "property", inVertex, let name = w.last { props.append(name) }
            if w.first == "end_header" { break }
        }
        guard ascii else { throw InsertReadError("Only ASCII PLY point clouds can be read. Save the cloud as ASCII PLY, XYZ or PTS.") }
        guard let ix = props.firstIndex(of: "x"), let iy = props.firstIndex(of: "y"), let iz = props.firstIndex(of: "z") else { throw InsertReadError("The PLY file has no x, y, z vertex properties.") }
        let ir = props.firstIndex { $0 == "red" || $0 == "r" || $0 == "diffuse_red" }
        let ig = props.firstIndex { $0 == "green" || $0 == "g" || $0 == "diffuse_green" }
        let ib = props.firstIndex { $0 == "blue" || $0 == "b" || $0 == "diffuse_blue" }
        var out: [(Vec3, (UInt8, UInt8, UInt8))] = []
        out.reserveCapacity(min(count, 2_000_000))
        while out.count < count, let l = lines.next() {
            let v = l.split(separator: " ").compactMap { Double($0) }
            guard v.count > max(ix, iy, iz) else { continue }
            var c: (UInt8, UInt8, UInt8) = (128, 128, 128)
            if let ir, let ig, let ib, v.count > max(ir, ig, ib) {
                func b(_ x: Double) -> UInt8 { UInt8(max(0, min(255, x.rounded()))) }
                c = (b(v[ir]), b(v[ig]), b(v[ib]))
            }
            out.append((Vec3(v[ix], v[iy], v[iz]), c))
        }
        return (out, ir != nil && ig != nil && ib != nil)
    }
}

// MARK: - OBJ

public enum OBJReader {
    /// The faces of an OBJ file, one mesh per object or group. OBJ is Y-up and has no units: positions are turned
    /// Z-up and read as meters unless they are evidently millimeters.
    public static func read(_ text: String, maxTriangles: Int = 4_000_000) throws -> [(name: String, mesh: Mesh)] {
        var v: [Vec3] = []
        var groups: [(String, [UInt32])] = [("Model", [])]
        var tris = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let w = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let head = w.first else { continue }
            switch head {
            case "v":
                let c = w.dropFirst().prefix(3).compactMap { Double($0) }
                if c.count == 3 { v.append(Vec3(c[0], -c[2], c[1])) }
            case "o", "g":
                let name = w.dropFirst().joined(separator: " ")
                if groups.last?.1.isEmpty == true { groups[groups.count - 1].0 = name.isEmpty ? "Model" : name } else { groups.append((name.isEmpty ? "Model" : name, [])) }
            case "f":
                let idx: [UInt32] = w.dropFirst().compactMap { tok in
                    guard let i = Int(tok.split(separator: "/", omittingEmptySubsequences: false).first ?? "") else { return nil }
                    let k = i < 0 ? v.count + i : i - 1
                    return k >= 0 && k < v.count ? UInt32(k) : nil
                }
                guard idx.count >= 3 else { continue }
                for k in 1..<(idx.count - 1) { groups[groups.count - 1].1 += [idx[0], idx[k], idx[k + 1]] }
                tris += idx.count - 2
                if tris > maxTriangles { throw InsertReadError("The OBJ file has more than \(maxTriangles) triangles.") }
            default:
                continue
            }
        }
        guard !v.isEmpty, groups.contains(where: { !$0.1.isEmpty }) else { throw InsertReadError("The OBJ file has no faces.") }
        let span = v.reduce(0.0) { max($0, abs($1.x), abs($1.y), abs($1.z)) }
        let k = span > 5000 ? 0.001 : 1
        return groups.filter { !$0.1.isEmpty }.map { name, ix in
            // Each group gets its own vertices with flat normals (OBJ normals are optional and often missing).
            var m = Mesh()
            for t in stride(from: 0, to: ix.count - 2, by: 3) {
                let a = v[Int(ix[t])] * k, b = v[Int(ix[t + 1])] * k, c = v[Int(ix[t + 2])] * k
                let n = (b - a).cross(c - a).normalized
                let base = UInt32(m.positions.count)
                m.positions += [a, b, c]; m.normals += [n, n, n]; m.indices += [base, base + 1, base + 2]
            }
            return (name, m)
        }
    }
}

// MARK: - gbXML

public enum GbXMLReader {
    /// The spaces of a gbXML file: each from its shell's lowest horizontal polyloop and its height range.
    public static func read(_ xml: String) throws -> [GbXMLSpace] {
        guard let root = xml.range(of: "<gbXML") else { throw InsertReadError("Not a gbXML file.") }
        let rootTag = xml[root.lowerBound...].prefix { $0 != ">" }
        let k: Double = switch attr(String(rootTag), "lengthUnit")?.lowercased() ?? "meters" {
        case "millimeters": 0.001
        case "centimeters": 0.01
        case "feet": 0.3048
        case "inches": 0.0254
        case "kilometers": 1000
        default: 1
        }
        var out: [GbXMLSpace] = []
        var rest = xml[...]
        while let s = rest.range(of: "<Space") {
            let after = rest[s.upperBound...]
            guard after.first == " " || after.first == ">" else { rest = after; continue }
            let e = after.range(of: "</Space>")
            let body = String(e.map { after[..<$0.lowerBound] } ?? after)
            rest = e.map { after[$0.upperBound...] } ?? ""
            let openTag = String(body.prefix { $0 != ">" })
            let name = element(body, "Name") ?? attr(openTag, "id") ?? "Space"
            var loops: [[Vec3]] = []
            var lp = body[...]
            while let ls = lp.range(of: "<PolyLoop>"), let le = lp[ls.upperBound...].range(of: "</PolyLoop>") {
                let loop = lp[ls.upperBound..<le.lowerBound]
                var pts: [Vec3] = []
                var cp = loop
                while let ps = cp.range(of: "<CartesianPoint>"), let pe = cp[ps.upperBound...].range(of: "</CartesianPoint>") {
                    let vals = cp[ps.upperBound..<pe.lowerBound].components(separatedBy: "<Coordinate>").dropFirst()
                        .compactMap { Double($0.components(separatedBy: "</Coordinate>").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") }
                    if vals.count >= 3 { pts.append(Vec3(vals[0] * k, vals[1] * k, vals[2] * k)) }
                    cp = cp[pe.upperBound...]
                }
                if pts.count >= 3 { loops.append(pts) }
                lp = lp[le.upperBound...]
            }
            guard !loops.isEmpty else { continue }
            let zs = loops.flatMap { $0.map(\.z) }
            let z0 = zs.min() ?? 0, z1 = zs.max() ?? 0
            guard let floor = loops.first(where: { $0.allSatisfy { abs($0.z - z0) < 0.001 } }) else { continue }
            var pts = floor.map(\.xy)
            if let f = pts.first, let l = pts.last, (f - l).length < 1e-6 { pts.removeLast() }
            out.append(GbXMLSpace(name: decode(name), number: attr(openTag, "id") ?? "", floor: pts, bottom: z0, top: z1))
        }
        guard !out.isEmpty else { throw InsertReadError("The gbXML file has no spaces with a floor.") }
        return out
    }

    static func element(_ s: String, _ name: String) -> String? {
        guard let a = s.range(of: "<\(name)>"), let b = s[a.upperBound...].range(of: "</\(name)>") else { return nil }
        return s[a.upperBound..<b.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func attr(_ tag: String, _ name: String) -> String? {
        guard let a = tag.range(of: " \(name)=\"") else { return nil }
        return tag[a.upperBound...].prefix { $0 != "\"" }.description
    }
    static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: - Zip

/// Reads the entries of a zip archive (stored and deflated), with bounded sizes.
public enum ZipArchive {
    public static func entries(_ data: Data, maxTotal: Int = 512 << 20) throws -> [String: Data] {
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 2 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0 }
        func u32(_ o: Int) -> Int { o + 4 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 : 0 }
        // End of central directory: the last "PK\5\6" within the final 64 KB.
        var eocd = -1
        var i = b.count - 22
        while i >= max(0, b.count - 65_557) {
            if b[i] == 0x50, b[i + 1] == 0x4b, b[i + 2] == 5, b[i + 3] == 6 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw InsertReadError("The file is not a zip package (DWFx files are zip packages).") }
        let n = u16(eocd + 10)
        var p = u32(eocd + 16)
        var out: [String: Data] = [:]
        var total = 0
        for _ in 0..<n {
            guard p + 46 <= b.count, u32(p) == 0x02014b50 else { throw InsertReadError("The zip directory is damaged.") }
            let method = u16(p + 10), csize = u32(p + 20), usize = u32(p + 24)
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32), local = u32(p + 42)
            guard p + 46 + nameLen <= b.count else { throw InsertReadError("The zip directory is damaged.") }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen
            guard local + 30 <= b.count, u32(local) == 0x04034b50 else { continue }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + csize <= b.count, usize >= 0 else { continue }
            total += usize
            guard total <= maxTotal else { throw InsertReadError("The package is larger than \(maxTotal >> 20) MB when unpacked.") }
            let body = Data(b[start..<(start + csize)])
            switch method {
            case 0: out[name] = body
            case 8: if let d = inflate(body, size: usize) { out[name] = d }
            default: continue
            }
        }
        return out
    }

    static func inflate(_ d: Data, size: Int) -> Data? {
        guard size > 0 else { return Data() }
        var out = Data(count: size)
        let n = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            d.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let s = src.bindMemory(to: UInt8.self).baseAddress, let t = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(t, size, s, d.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n == size ? out : nil
    }
}

// MARK: - DWFx

public enum DWFxReader {
    /// XPS units (1/96 inch) to meters.
    static let unit = 0.0254 / 96
    /// Canvases holding a sheet's own drawing in DWFx files written by RevitCraft or Arcus: left out, so only the
    /// markups added to the page come back.
    static let sheetCanvases: Set<String> = ["RevitCraftSheet", "ArcusSheet"]

    /// The fixed pages of a DWFx (or XPS) package: their paths (lines and fills), glyphs (text) and images.
    public static func read(_ data: Data) throws -> [DWFPage] {
        let files = try ZipArchive.entries(data)
        var pages: [DWFPage] = []
        for name in files.keys.sorted() where name.lowercased().hasSuffix(".fpage") {
            let xml = String(decoding: files[name]!, as: UTF8.self)
            let pageName = String((name.split(separator: "/").last ?? Substring(name)).dropLast(6))
            pages.append(page(xml, name: pageName, resolve: { ref in
                let r = ref.hasPrefix("/") ? String(ref.dropFirst()) : ref
                if let d = files[r] { return d }
                let dir = name.split(separator: "/").dropLast().joined(separator: "/")
                return files[(dir.isEmpty ? "" : dir + "/") + r] ?? files.first { $0.key.hasSuffix(r) }?.value
            }))
        }
        guard !pages.isEmpty else { throw InsertReadError("The file has no pages. Choose a DWFx file exported with its sheets.") }
        return pages
    }

    /// One page from its FixedPage markup.
    public static func page(_ xml: String, name: String, resolve: (String) -> Data? = { _ in nil }) -> DWFPage {
        var page = DWFPage(name: name, size: .zero)
        var height = 0.0
        // Matrix stack for nested canvases (XPS RenderTransform), each with whether it is a sheet canvas.
        var stack: [(Transform2, Bool)] = []
        var openPath: (bounds: Rect2, depth: Int)?
        var current: Transform2 { stack.last?.0 ?? .identity }
        var skipping: Bool { stack.contains { $0.1 } }
        var rest = xml[...]
        while let lt = rest.firstIndex(of: "<") {
            guard let gt = rest[lt...].firstIndex(of: ">") else { break }
            let tag = String(rest[lt...gt])
            rest = rest[rest.index(after: gt)...]
            if tag.hasPrefix("<FixedPage") {
                let w = (attr(tag, "Width").flatMap(Double.init) ?? 0) * unit
                height = (attr(tag, "Height").flatMap(Double.init) ?? 0) * unit
                page.size = Vec2(w, height)
            } else if tag.hasPrefix("<Canvas") {
                let t = current * matrix(attr(tag, "RenderTransform"))
                let sheet = attr(tag, "Name").map { sheetCanvases.contains($0) } ?? false
                if !tag.hasSuffix("/>") { stack.append((t, sheet)) }
            } else if tag.hasPrefix("</Canvas") {
                _ = stack.popLast()
            } else if skipping {
                continue
            } else if tag.hasPrefix("<Path ") || tag == "<Path>" {
                let t = current * matrix(attr(tag, "RenderTransform"))
                let map = { (q: Vec2) -> Vec2 in let p = t.apply(q); return Vec2(p.x * unit, height - p.y * unit) }
                let figs = (attr(tag, "Data").map(figures) ?? []).map { $0.map(map) }
                let stroke = attr(tag, "Stroke").flatMap(color)
                let fill = attr(tag, "Fill").flatMap(color)
                for f in figs where f.count >= 2 {
                    if let fill, f.count >= 3 { page.polylines.append(MarkupData.Polyline(points: f, color: fill, filled: true)) }
                    if stroke != nil || fill == nil { page.polylines.append(MarkupData.Polyline(points: f, color: stroke ?? RGBColor(1, 0, 0))) }
                }
                if !tag.hasSuffix("/>") { openPath = (Rect2(points: figs.flatMap { $0 }), 0) }
            } else if tag.hasPrefix("</Path>") {
                openPath = nil
            } else if tag.hasPrefix("<ImageBrush"), let src = attr(tag, "ImageSource"), let img = resolve(src) {
                var r = openPath?.bounds ?? .empty
                if r.isEmpty, let vp = attr(tag, "Viewport") {
                    let v = vp.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }
                    if v.count == 4 {
                        let a = current.apply(Vec2(v[0], v[1])), b = current.apply(Vec2(v[0] + v[2], v[1] + v[3]))
                        r = Rect2(points: [Vec2(a.x * unit, height - a.y * unit), Vec2(b.x * unit, height - b.y * unit)])
                    }
                }
                if !r.isEmpty { page.pictures.append(MarkupData.Picture(bounds: r, image: img)) }
            } else if tag.hasPrefix("<Glyphs") {
                guard var text = attr(tag, "UnicodeString"), let x = attr(tag, "OriginX").flatMap(Double.init), let y = attr(tag, "OriginY").flatMap(Double.init) else { continue }
                if text.hasPrefix("{}") { text.removeFirst(2) }
                let t = current * matrix(attr(tag, "RenderTransform"))
                let p = t.apply(Vec2(x, y))
                let size = (attr(tag, "FontRenderingEmSize").flatMap(Double.init) ?? 12) * t.uniformScale * unit
                // Cap height is about 0.7 em.
                page.texts.append(MarkupData.Text(position: Vec2(p.x * unit, height - p.y * unit), string: text, height: size * 0.7,
                                                  color: attr(tag, "Fill").flatMap(color) ?? .black))
            }
        }
        return page
    }

    static func attr(_ tag: String, _ name: String) -> String? {
        guard let a = tag.range(of: " \(name)=\"") ?? tag.range(of: "\n\(name)=\"") else { return nil }
        return GbXMLReader.decode(String(tag[a.upperBound...].prefix { $0 != "\"" }))
    }

    /// "#AARRGGBB" or "#RRGGBB" (fully transparent colours are ignored).
    static func color(_ v: String) -> RGBColor? {
        guard v.hasPrefix("#") else { return nil }
        let h = String(v.dropFirst())
        guard let n = UInt32(h, radix: 16) else { return nil }
        if h.count == 8 { return (n >> 24) == 0 ? nil : RGBColor(hex: n & 0xFFFFFF) }
        return h.count == 6 ? RGBColor(hex: n) : nil
    }

    /// "m11,m12,m21,m22,dx,dy" (XPS row-vector convention).
    static func matrix(_ s: String?) -> Transform2 {
        guard let s else { return .identity }
        let v = s.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }
        guard v.count == 6 else { return .identity }
        return Transform2(a: v[0], b: v[2], c: v[1], d: v[3], tx: v[4], ty: v[5])
    }

    /// The figures of XPS abbreviated path geometry (M, L, H, V, C, Q, S, Z, relative forms too) as polylines; curves
    /// are divided into eight segments.
    public static func figures(_ data: String) -> [[Vec2]] {
        var toks: [String] = []
        var num = ""
        for ch in data {
            if ch.isLetter && ch != "e" && ch != "E" {
                if !num.isEmpty { toks.append(num); num = "" }
                toks.append(String(ch))
            } else if ch == "," || ch.isWhitespace {
                if !num.isEmpty { toks.append(num); num = "" }
            } else if ch == "-", !num.isEmpty, !num.hasSuffix("e"), !num.hasSuffix("E") {
                toks.append(num); num = "-"
            } else { num.append(ch) }
        }
        if !num.isEmpty { toks.append(num) }
        var out: [[Vec2]] = [], cur: [Vec2] = []
        var pos = Vec2.zero, start = Vec2.zero
        var cmd: Character = "M"
        var i = 0
        func next() -> Double? { guard i < toks.count, let v = Double(toks[i]) else { return nil }; i += 1; return v }
        while i < toks.count {
            if let c = toks[i].first, c.isLetter {
                cmd = c; i += 1
                if c == "F" { i += 1; continue }
                if c == "Z" || c == "z" {
                    if !cur.isEmpty { cur.append(start); out.append(cur); cur = [] }
                    pos = start
                    continue
                }
            }
            let rel = cmd.isLowercase
            let base = rel ? pos : .zero
            switch cmd.uppercased() {
            case "M":
                guard let x = next(), let y = next() else { i = toks.count; break }
                if cur.count > 1 { out.append(cur) }
                pos = base + Vec2(x, y); start = pos; cur = [pos]
                cmd = rel ? "l" : "L"
            case "L":
                guard let x = next(), let y = next() else { i = toks.count; break }
                pos = base + Vec2(x, y); cur.append(pos)
            case "H":
                guard let x = next() else { i = toks.count; break }
                pos = Vec2(rel ? pos.x + x : x, pos.y); cur.append(pos)
            case "V":
                guard let y = next() else { i = toks.count; break }
                pos = Vec2(pos.x, rel ? pos.y + y : y); cur.append(pos)
            case "C":
                let v = (0..<6).compactMap { _ in next() }
                guard v.count == 6 else { i = toks.count; break }
                let a = pos, c1 = base + Vec2(v[0], v[1]), c2 = base + Vec2(v[2], v[3]), b = base + Vec2(v[4], v[5])
                for k in 1...8 {
                    let t = Double(k) / 8, u = 1 - t
                    cur.append(a * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + b * (t * t * t))
                }
                pos = b
            case "Q", "S":
                let v = (0..<4).compactMap { _ in next() }
                guard v.count == 4 else { i = toks.count; break }
                let a = pos, c = base + Vec2(v[0], v[1]), b = base + Vec2(v[2], v[3])
                for k in 1...8 {
                    let t = Double(k) / 8, u = 1 - t
                    cur.append(a * (u * u) + c * (2 * u * t) + b * (t * t))
                }
                pos = b
            default:
                i += 1
            }
        }
        if cur.count > 1 { out.append(cur) }
        return out
    }
}
