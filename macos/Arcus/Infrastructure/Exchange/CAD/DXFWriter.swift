import Foundation
import ArcusGeometry
import ArcusDomain

/// ASCII DXF export of 2D view graphics (AutoCAD 2000 / AC1015 structure).
public enum DXFWriter {
    /// Exports a 2D view display list (view coordinates in meters) to ASCII DXF (AC1015/R2000) with a layer per category, polylines/arcs/text/hatches, $INSUNITS and a unit scale.
    public static func write(_ g: ViewGraphics, units: CADUnits = .millimeters, layerName: (ArcusDomain.Category) -> String = { $0.displayName }) -> Data {
        var w = DXFEmitter(units: units == .unitless ? .millimeters : units, scale: max(1, g.scale))
        return w.build(g, layerName: layerName)
    }

    /// Standard DXF lineweights (1/100 mm).
    static let lineWeights = [0, 5, 9, 13, 15, 18, 20, 25, 30, 35, 40, 50, 53, 60, 70, 80, 90, 100, 106, 120, 140, 158, 200, 211]

    static func lineWeightCode(mm: Double) -> Int {
        let v = mm * 100
        return lineWeights.min { abs(Double($0) - v) < abs(Double($1) - v) } ?? 25
    }

    /// Makes a valid DXF symbol table name.
    static func sanitize(_ name: String) -> String {
        let bad = Set("<>/\\\":;?*|=`,")
        var s = String(name.map { bad.contains($0) || $0.isNewline ? "_" : $0 })
        s = s.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { s = "Layer" }
        if s.count > 255 { s = String(s.prefix(255)) }
        return s
    }

    /// Encodes text for an ANSI_1252 R2000 file: ASCII as is, other characters as \U+XXXX.
    static func encodeText(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            if u.value >= 32 && u.value < 127 { out.unicodeScalars.append(u) } else if u.value == 9 { out += " " } else if u.value < 32 {
                continue
            } else if u.value <= 0xFFFF {
                out += String(format: "\\U+%04X", u.value)
            } else {
                out += "?"
            }
        }
        return out
    }
}

private struct DXFEmitter {
    let units: CADUnits
    let scale: Int
    var out = ""
    var handle = 0x20
    var layers: [(name: String, color: RGBColor, lw: Int)] = []
    var layerIndex: [String: Int] = [:]
    var lineTypesUsed: Set<LinePatternKind> = []
    let mpu: Double

    init(units: CADUnits, scale: Int) {
        self.units = units; self.scale = scale; self.mpu = units.metersPerUnit
        out.reserveCapacity(1 << 16)
    }

    mutating func next() -> String { handle += 1; return String(handle, radix: 16, uppercase: true) }

    // MARK: Primitive writers

    mutating func g(_ code: Int, _ value: String) {
        out += String(repeating: " ", count: max(0, 3 - String(code).count)) + String(code) + "\n" + value + "\n"
    }
    mutating func g(_ code: Int, _ v: Int) { g(code, String(v)) }
    mutating func g(_ code: Int, _ v: Double) {
        let x = v.isFinite ? (v == 0 ? 0 : v) : 0
        var s = String(x)
        if s.hasSuffix(".0") { s.removeLast(2); s += ".0" }
        g(code, s)
    }
    mutating func point(_ code: Int, _ p: Vec2, z: Double? = 0) {
        g(code, p.x / mpu); g(code + 10, p.y / mpu)
        if let z { g(code + 20, z) }
    }
    func len(_ v: Double) -> Double { v / mpu }

    // MARK: Build

    mutating func build(_ gr: ViewGraphics, layerName: (ArcusDomain.Category) -> String) -> Data {
        // Pass 1: entities (collect layers and linetypes).
        let msRecord = "1F", psRecord = "1E"
        var ents = DXFEmitter(units: units, scale: scale)
        ents.handle = 0x100
        ents.layers = [("0", .black, -3)]
        ents.layerIndex = ["0": 0]
        var ext = Rect2.empty
        for item in gr.items {
            let lname = DXFWriter.sanitize(layerName(item.category))
            let style = ObjectStyles.style(item.category)
            let li = ents.addLayer(lname, color: style.color, weight: style.projectionWeight)
            for p in item.primitives {
                ents.primitive(p, layer: ents.layers[li].name, layerColor: ents.layers[li].color, owner: msRecord, ext: &ext)
            }
        }
        if ext.isEmpty { ext = Rect2(min: .zero, max: .zero) }
        let body = ents.out
        handle = ents.handle + 16

        // HEADER
        section("HEADER")
        g(9, "$ACADVER"); g(1, "AC1015")
        g(9, "$ACADMAINTVER"); g(70, 6)
        g(9, "$DWGCODEPAGE"); g(3, "ANSI_1252")
        g(9, "$INSBASE"); point(10, .zero)
        g(9, "$EXTMIN"); point(10, ext.min)
        g(9, "$EXTMAX"); point(10, ext.max)
        g(9, "$LIMMIN"); point(10, ext.min, z: nil)
        g(9, "$LIMMAX"); point(10, ext.max, z: nil)
        g(9, "$LTSCALE"); g(40, 1.0)
        g(9, "$PSLTSCALE"); g(70, 0)
        g(9, "$INSUNITS"); g(70, units.rawValue)
        g(9, "$MEASUREMENT"); g(70, [CADUnits.inches, .feet, .yards, .miles, .usSurveyFeet].contains(units) ? 0 : 1)
        g(9, "$LUNITS"); g(70, 2)
        g(9, "$TEXTSTYLE"); g(7, "Standard")
        g(9, "$CLAYER"); g(8, "0")
        g(9, "$HANDSEED"); g(5, String(handle + 0x1000, radix: 16, uppercase: true))
        g(0, "ENDSEC")

        section("CLASSES")
        g(0, "ENDSEC")

        // TABLES
        section("TABLES")
        let viewH = max(1e-9, ext.height), viewW = max(1e-9, ext.width)
        table("VPORT", count: 1) { e, owner in
            e.g(0, "VPORT"); e.g(5, e.next()); e.g(330, owner)
            e.g(100, "AcDbSymbolTableRecord"); e.g(100, "AcDbViewportTableRecord")
            e.g(2, "*Active"); e.g(70, 0)
            e.g(10, 0.0); e.g(20, 0.0); e.g(11, 1.0); e.g(21, 1.0)
            e.point(12, ext.center, z: nil)
            e.g(13, 0.0); e.g(23, 0.0); e.g(14, 1.0); e.g(24, 1.0); e.g(15, 1.0); e.g(25, 1.0)
            e.g(16, 0.0); e.g(26, 0.0); e.g(36, 1.0); e.g(17, 0.0); e.g(27, 0.0); e.g(37, 0.0)
            e.g(40, e.len(viewH * 1.1)); e.g(41, viewW / viewH); e.g(42, 50.0); e.g(43, 0.0); e.g(44, 0.0); e.g(50, 0.0); e.g(51, 0.0)
            e.g(71, 0); e.g(72, 100); e.g(73, 1); e.g(74, 3); e.g(75, 0); e.g(76, 0); e.g(77, 0); e.g(78, 0)
        }
        let used = ents.lineTypesUsed.sorted { $0.rawValue < $1.rawValue }
        table("LTYPE", count: 3 + used.count) { e, owner in
            for (n, d) in [("ByBlock", ""), ("ByLayer", ""), ("Continuous", "Solid line")] {
                e.ltype(n, d, [], owner)
            }
            for p in used {
                // Paper millimeters → drawing units at the view scale.
                let dashes = p.dashPattern.enumerated().map { i, v in (i % 2 == 0 ? 1.0 : -1.0) * v / 1000 * Double(e.scale) / e.mpu }
                e.ltype(DXFEmitter.ltypeName(p), p.rawValue, dashes, owner)
            }
        }
        let layerList = ents.layers
        table("LAYER", count: layerList.count) { e, owner in
            for l in layerList {
                e.g(0, "LAYER"); e.g(5, e.next()); e.g(330, owner)
                e.g(100, "AcDbSymbolTableRecord"); e.g(100, "AcDbLayerTableRecord")
                e.g(2, l.name); e.g(70, 0); e.g(62, ACIColor.nearest(l.color))
                if ACIColor.nearest(l.color) != 7 { e.g(420, ACIColor.trueColorValue(l.color)) }
                e.g(6, "Continuous"); e.g(290, 1); e.g(370, l.lw)
            }
        }
        table("STYLE", count: 1) { e, owner in
            e.g(0, "STYLE"); e.g(5, e.next()); e.g(330, owner)
            e.g(100, "AcDbSymbolTableRecord"); e.g(100, "AcDbTextStyleTableRecord")
            e.g(2, "Standard"); e.g(70, 0); e.g(40, 0.0); e.g(41, 1.0); e.g(50, 0.0); e.g(71, 0); e.g(42, 2.5); e.g(3, "arial.ttf"); e.g(4, "")
        }
        table("VIEW", count: 0) { _, _ in }
        table("UCS", count: 0) { _, _ in }
        table("APPID", count: 1) { e, owner in
            e.g(0, "APPID"); e.g(5, e.next()); e.g(330, owner)
            e.g(100, "AcDbSymbolTableRecord"); e.g(100, "AcDbRegAppTableRecord"); e.g(2, "ACAD"); e.g(70, 0)
        }
        table("DIMSTYLE", count: 1, subclass: "AcDbDimStyleTable") { e, owner in
            e.g(0, "DIMSTYLE"); e.g(105, e.next()); e.g(330, owner)
            e.g(100, "AcDbSymbolTableRecord"); e.g(100, "AcDbDimStyleTableRecord"); e.g(2, "Standard"); e.g(70, 0)
        }
        let modelLayout = "1D", paperLayout = "1C"
        table("BLOCK_RECORD", count: 2) { e, owner in
            for (h, n, lo) in [(msRecord, "*Model_Space", modelLayout), (psRecord, "*Paper_Space", paperLayout)] {
                e.g(0, "BLOCK_RECORD"); e.g(5, h); e.g(330, owner)
                e.g(100, "AcDbSymbolTableRecord"); e.g(100, "AcDbBlockTableRecord"); e.g(2, n); e.g(340, lo)
            }
        }
        g(0, "ENDSEC")

        // BLOCKS
        section("BLOCKS")
        for (rec, name, paper) in [(msRecord, "*Model_Space", false), (psRecord, "*Paper_Space", true)] {
            g(0, "BLOCK"); g(5, next()); g(330, rec); g(100, "AcDbEntity")
            if paper { g(67, 1) }
            g(8, "0"); g(100, "AcDbBlockBegin"); g(2, name); g(70, 0); point(10, .zero); g(3, name); g(1, "")
            g(0, "ENDBLK"); g(5, next()); g(330, rec); g(100, "AcDbEntity")
            if paper { g(67, 1) }
            g(8, "0"); g(100, "AcDbBlockEnd")
        }
        g(0, "ENDSEC")

        // ENTITIES
        section("ENTITIES")
        out += body
        g(0, "ENDSEC")

        // OBJECTS
        section("OBJECTS")
        let root = "C", groups = "D", layoutsDict = "1A"
        g(0, "DICTIONARY"); g(5, root); g(330, "0"); g(100, "AcDbDictionary"); g(281, 1)
        g(3, "ACAD_GROUP"); g(350, groups); g(3, "ACAD_LAYOUT"); g(350, layoutsDict)
        g(0, "DICTIONARY"); g(5, groups); g(330, root); g(100, "AcDbDictionary"); g(281, 1)
        g(0, "DICTIONARY"); g(5, layoutsDict); g(330, root); g(100, "AcDbDictionary"); g(281, 1)
        g(3, "Layout1"); g(350, paperLayout); g(3, "Model"); g(350, modelLayout)
        layout(modelLayout, name: "Model", record: msRecord, owner: layoutsDict, tab: 0, ext: ext)
        layout(paperLayout, name: "Layout1", record: psRecord, owner: layoutsDict, tab: 1, ext: ext)
        g(0, "ENDSEC")
        g(0, "EOF")
        return Data(out.utf8)
    }

    static func ltypeName(_ p: LinePatternKind) -> String { "ARCUS_" + p.rawValue.uppercased().replacingOccurrences(of: " ", with: "") }

    mutating func section(_ name: String) { g(0, "SECTION"); g(2, name) }

    mutating func table(_ name: String, count: Int, subclass: String? = nil, _ body: (inout DXFEmitter, String) -> Void) {
        let h = next()
        g(0, "TABLE"); g(2, name); g(5, h); g(330, "0"); g(100, "AcDbSymbolTable"); g(70, count)
        if let subclass { g(100, subclass) }
        body(&self, h)
        g(0, "ENDTAB")
    }

    mutating func ltype(_ name: String, _ desc: String, _ dashes: [Double], _ owner: String) {
        g(0, "LTYPE"); g(5, next()); g(330, owner)
        g(100, "AcDbSymbolTableRecord"); g(100, "AcDbLinetypeTableRecord")
        g(2, name); g(70, 0); g(3, DXFWriter.encodeText(desc)); g(72, 65); g(73, dashes.count)
        g(40, dashes.reduce(0) { $0 + abs($1) })
        for d in dashes { g(49, d); g(74, 0) }
    }

    mutating func layout(_ h: String, name: String, record: String, owner: String, tab: Int, ext: Rect2) {
        g(0, "LAYOUT"); g(5, h); g(330, owner)
        g(100, "AcDbPlotSettings"); g(1, ""); g(2, "none_device"); g(4, "ISO_A3_(420.00_x_297.00_MM)"); g(6, "")
        g(40, 7.5); g(41, 20.0); g(42, 7.5); g(43, 20.0); g(44, 420.0); g(45, 297.0); g(46, 0.0); g(47, 0.0)
        g(48, 0.0); g(49, 0.0); g(140, 0.0); g(141, 0.0); g(142, 1.0); g(143, 1.0); g(70, 688); g(72, 1); g(73, 0); g(74, 5)
        g(7, ""); g(75, 16); g(147, 1.0); g(148, 0.0); g(149, 0.0)
        g(100, "AcDbLayout"); g(1, name); g(70, 1); g(71, tab)
        g(10, 0.0); g(20, 0.0); g(11, 420.0); g(21, 297.0); g(12, 0.0); g(22, 0.0); g(32, 0.0)
        point(14, ext.min); point(15, ext.max)
        g(146, 0.0); g(13, 0.0); g(23, 0.0); g(33, 0.0); g(16, 1.0); g(26, 0.0); g(36, 0.0); g(17, 0.0); g(27, 1.0); g(37, 0.0)
        g(76, 0); g(330, record)
    }

    // MARK: Entities

    mutating func addLayer(_ name: String, color: RGBColor, weight: Int) -> Int {
        let key = name.uppercased()
        if let i = layerIndex[key] { return i }
        layers.append((name, color, DXFWriter.lineWeightCode(mm: LineWeights.paperWidth(weight, scale: scale))))
        layerIndex[key] = layers.count - 1
        return layers.count - 1
    }

    mutating func common(_ type: String, layer: String, owner: String, color: RGBColor?, layerColor: RGBColor, weight: Int?, pattern: LinePatternKind?) {
        g(0, type); g(5, next()); g(330, owner); g(100, "AcDbEntity"); g(8, layer)
        if let pattern, pattern != .solid {
            lineTypesUsed.insert(pattern)
            g(6, DXFEmitter.ltypeName(pattern))
        }
        if let c = color, c != layerColor {
            let aci = ACIColor.nearest(c)
            g(62, aci)
            g(420, ACIColor.trueColorValue(c))
        }
        if let weight { g(370, DXFWriter.lineWeightCode(mm: LineWeights.paperWidth(weight, scale: scale))) }
    }

    func strokeColor(_ s: GStroke) -> RGBColor { s.halftone ? s.color.mixed(with: .white, amount: 0.5) : s.color }

    mutating func primitive(_ p: GPrimitive, layer: String, layerColor: RGBColor, owner: String, ext: inout Rect2) {
        switch p {
        case .polyline(let pts, let closed, let st):
            let clean = pts.filter { $0.x.isFinite && $0.y.isFinite }
            guard clean.count >= 2 else { return }
            for q in clean { ext.include(q) }
            common("LWPOLYLINE", layer: layer, owner: owner, color: strokeColor(st), layerColor: layerColor, weight: st.weight, pattern: st.pattern)
            g(100, "AcDbPolyline"); g(90, clean.count); g(70, closed ? 1 : 0); g(43, 0.0)
            for q in clean { point(10, q, z: nil) }
        case .arc(let a, let st):
            guard a.radius.isFinite, a.radius > 0, a.center.x.isFinite, a.center.y.isFinite else { return }
            ext.include(a.bounds)
            if a.isFullCircle {
                common("CIRCLE", layer: layer, owner: owner, color: strokeColor(st), layerColor: layerColor, weight: st.weight, pattern: st.pattern)
                g(100, "AcDbCircle"); point(10, a.center); g(40, len(a.radius))
            } else {
                let (s, e) = a.sweep >= 0 ? (a.startAngle, a.endAngle) : (a.endAngle, a.startAngle)
                common("ARC", layer: layer, owner: owner, color: strokeColor(st), layerColor: layerColor, weight: st.weight, pattern: st.pattern)
                g(100, "AcDbCircle"); point(10, a.center); g(40, len(a.radius))
                g(100, "AcDbArc"); g(50, Angle.degrees(Angle.normalize(s))); g(51, Angle.degrees(Angle.normalize(e)))
            }
        case .fill(let polys, let f):
            let loops = polys.map { $0.points.filter { $0.x.isFinite && $0.y.isFinite } }.filter { $0.count >= 3 }
            guard !loops.isEmpty else { return }
            for l in loops { for q in l { ext.include(q) } }
            let solid = f.pattern == .solid
            let color = f.halftone ? f.color.mixed(with: .white, amount: 0.5) : f.color
            let hatch = solid ? nil : f.hatch.flatMap { $0.isEmpty ? nil : $0 } // W4-HATCH: project pattern → HATCH pattern definition lines
            common("HATCH", layer: layer, owner: owner, color: color, layerColor: layerColor, weight: nil, pattern: nil)
            g(100, "AcDbHatch"); g(10, 0.0); g(20, 0.0); g(30, 0.0); g(210, 0.0); g(220, 0.0); g(230, 1.0)
            g(2, solid ? "SOLID" : (hatch != nil ? DXFWriter.hatchPatternName(f) : "ANSI31")); g(70, solid ? 1 : 0); g(71, 0); g(91, loops.count)
            for (i, l) in loops.enumerated() {
                g(92, i == 0 ? 3 : 2); g(72, 0); g(73, 1); g(93, l.count)
                for q in l { point(10, q, z: nil) }
                g(97, 0)
            }
            g(75, 0); g(76, hatch != nil ? 0 : 1)
            if let hatch {
                // Each line family becomes a pattern definition line (angle, base point, offset vector, dashes) in
                // drawing units; drafting patterns are sized for this view's scale, model patterns in model size.
                let unit = HatchGenerator.viewUnitsPerMM(isModel: hatch.isModel, scale: scale) / mpu
                let families = hatch.families.filter(\.isValid)
                g(52, 0.0); g(41, 1.0); g(77, 0); g(78, families.count)
                for fam in families {
                    let a = fam.angle * .pi / 180
                    let d = Vec2(cos(a), sin(a)), n = Vec2(-sin(a), cos(a))
                    let off = n * (fam.spacing * unit) + d * (fam.shift * unit)
                    g(53, fam.angle); g(43, fam.origin.x * unit); g(44, fam.origin.y * unit); g(45, off.x); g(46, off.y)
                    g(79, fam.dashes.count)
                    for dash in fam.dashes { g(49, dash * unit) }
                }
            } else if !solid {
                // ANSI31: 45° lines, 3.175 mm apart on paper.
                let spacing = 3.175 / 1000 * Double(scale) / mpu
                g(52, 0.0); g(41, 1.0); g(77, 0); g(78, 1)
                let d = spacing * sqrt(0.5)
                g(53, 45.0); g(43, 0.0); g(44, 0.0); g(45, -d); g(46, d); g(79, 0)
            }
            g(98, 0)
        case .text(let t):
            guard !t.string.isEmpty, t.position.x.isFinite, t.position.y.isFinite, t.height > 0 else { return }
            ext.include(t.position)
            let h = t.height * Double(scale)
            let color = t.halftone ? t.color.mixed(with: .white, amount: 0.5) : t.color
            // W2-ANNOT: bold, italic and underlined text go out as MTEXT with inline formatting codes.
            let styled = t.bold || t.italic || t.underline
            if t.wrapWidth > 0 || t.string.contains("\n") || styled {
                common("MTEXT", layer: layer, owner: owner, color: color, layerColor: layerColor, weight: nil, pattern: nil)
                g(100, "AcDbMText"); point(10, t.position); g(40, len(h)); g(41, len(t.wrapWidth * Double(scale)))
                let col = t.alignment == .left ? 1 : (t.alignment == .center ? 2 : 3)
                let row = t.verticalAnchor >= 0.75 ? 0 : (t.verticalAnchor >= 0.25 ? 1 : 2)
                g(71, row * 3 + col); g(72, 1)
                var encoded = t.string.components(separatedBy: "\n")
                    .map { DXFWriter.encodeText($0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "{", with: "\\{").replacingOccurrences(of: "}", with: "\\}")) }
                    .joined(separator: "\\P")
                if styled {
                    let font = t.bold || t.italic ? "\\fArial|b\(t.bold ? 1 : 0)|i\(t.italic ? 1 : 0)|c0|p34;" : ""
                    encoded = "{" + font + (t.underline ? "\\L" : "") + encoded + (t.underline ? "\\l" : "") + "}"
                }
                var rest = Substring(encoded)
                while rest.count > 250 { g(3, String(rest.prefix(250))); rest = rest.dropFirst(250) }
                g(1, String(rest)); g(7, "Standard")
                let dir = Vec2.fromAngle(t.rotation)
                g(11, dir.x); g(21, dir.y); g(31, 0.0)
            } else {
                common("TEXT", layer: layer, owner: owner, color: color, layerColor: layerColor, weight: nil, pattern: nil)
                let hAlign = t.alignment == .left ? 0 : (t.alignment == .center ? 1 : 2)
                let vAlign = t.verticalAnchor >= 0.75 ? 3 : (t.verticalAnchor >= 0.25 ? 2 : 0)
                g(100, "AcDbText"); point(10, t.position); g(40, len(h)); g(1, DXFWriter.encodeText(t.string))
                g(50, Angle.degrees(t.rotation)); g(7, "Standard")
                if hAlign != 0 || vAlign != 0 { g(72, hAlign); point(11, t.position) }
                g(100, "AcDbText")
                if vAlign != 0 { g(73, vAlign) }
            }
        }
    }
}
