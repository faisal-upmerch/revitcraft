import Foundation
import ArcusGeometry
import ArcusCalc

// W2-ANNOT: line styles, text and dimension types, keynotes and text metrics shared by annotation tools and graphics.

/// Parameter ids of annotation types (stored in `TypeData.params`).
public enum AnnotationParams {
    // Text types.
    public static let textSize = ParameterID("text.size")
    public static let textBold = ParameterID("text.bold")
    public static let textItalic = ParameterID("text.italic")
    public static let textUnderline = ParameterID("text.underline")
    public static let textBackground = ParameterID("text.background")
    public static let textArrowhead = ParameterID("text.arrowhead")
    public static let textColor = ParameterID("text.color")
    // Dimension types.
    public static let dimensionTextSize = ParameterID("dimension.textSize")
    public static let dimensionTick = ParameterID("dimension.tickMark")
    public static let dimensionWitnessGap = ParameterID("dimension.witnessGap")
    public static let dimensionWitnessExtension = ParameterID("dimension.witnessExtension")
    public static let dimensionLineExtension = ParameterID("dimension.lineExtension")
    public static let dimensionTextOffset = ParameterID("dimension.textOffset")
}

// MARK: - Line styles

/// Line styles: named weight, colour and pattern combinations used by detail and model lines.
///
/// The standard set follows the conventions users of mainstream BIM tools expect: plain weights ("Thin Lines",
/// "Medium Lines", "Wide Lines", "Lines"), bracketed system styles for view graphics ("<Hidden>", "<Overhead>"…)
/// and patterned drafting styles. Standard styles can be edited but not renamed or deleted; user styles can.
public enum LineStyles {
    public struct Standard: Sendable {
        public let name: String
        public let weight: Int
        public let pattern: LinePatternKind
        public let color: RGBColor
    }

    public static let standard: [Standard] = [
        Standard(name: "Thin Lines", weight: 1, pattern: .solid, color: .black),
        Standard(name: "Medium Lines", weight: 3, pattern: .solid, color: .black),
        Standard(name: "Wide Lines", weight: 5, pattern: .solid, color: .black),
        Standard(name: "Lines", weight: 1, pattern: .solid, color: .black),
        Standard(name: "<Hidden>", weight: 1, pattern: .hidden, color: .black),
        Standard(name: "<Overhead>", weight: 1, pattern: .overhead, color: .black),
        Standard(name: "<Beyond>", weight: 1, pattern: .solid, color: RGBColor(0.35, 0.35, 0.35)),
        Standard(name: "<Centerline>", weight: 1, pattern: .center, color: .black),
        Standard(name: "<Demolished>", weight: 1, pattern: .demolished, color: .black),
        Standard(name: "<Sketch>", weight: 3, pattern: .solid, color: RGBColor(0.85, 0.10, 0.60)),
        Standard(name: "Dashed", weight: 1, pattern: .dash, color: .black),
        Standard(name: "Dash Dot", weight: 1, pattern: .dashDot, color: .black),
        Standard(name: "Dotted", weight: 1, pattern: .dot, color: .black),
        Standard(name: "Long Dash", weight: 1, pattern: .longDash, color: .black),
        Standard(name: "Double Dash", weight: 1, pattern: .doubleDash, color: .black),
        Standard(name: "Property Line", weight: 2, pattern: .dashDotDot, color: .black),
    ]

    /// The style new detail and model lines use.
    public static let defaultName = "Thin Lines"

    /// True for the standard styles (they can't be renamed or deleted).
    public static func isStandard(_ name: String) -> Bool { standard.contains { $0.name == name } }

    /// Styles in display order: standard styles first (in their order), then user styles by name.
    public static func sorted(_ model: BIMModel) -> [Element] {
        let all = model.elements(.lineStyles)
        let std = standard.compactMap { s in all.first { $0.name == s.name } }
        let user = all.filter { !isStandard($0.name) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return std + user
    }

    /// Adds every missing standard style. Returns how many were added.
    /// `limit`: only the first `limit` standard styles (templates create the rest last, so earlier element ids stay put).
    @discardableResult
    public static func ensureStandard(in tx: TransactionContext, limit: Int? = nil) -> Int {
        var added = 0
        let existing = Set(tx.model.elements(.lineStyles).map(\.name))
        for s in standard.prefix(limit ?? standard.count) where !existing.contains(s.name) {
            tx.create(.lineStyles, name: s.name, data: .lineStyle(LineStyleData(weight: s.weight, color: s.color, pattern: s.pattern)))
            added += 1
        }
        return added
    }

    /// Checks a new or changed style name. Returns the trimmed name.
    public static func validName(_ raw: String, excluding: ElementID? = nil, _ model: BIMModel) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TransactionError("A line style needs a name.") }
        guard !(name.hasPrefix("<") && name.hasSuffix(">")) else {
            throw TransactionError("Names in angle brackets are reserved for the standard styles.")
        }
        if model.elements(.lineStyles).contains(where: { $0.id != excluding && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            throw TransactionError("A line style named “\(name)” already exists.")
        }
        return name
    }

    /// Creates a user style. Weight is clamped to 1…16.
    @discardableResult
    public static func create(name: String, weight: Int, color: RGBColor = .black, pattern: LinePatternKind = .solid, in tx: TransactionContext) throws -> ElementID {
        let n = try validName(name, tx.model)
        return tx.create(.lineStyles, name: n, data: .lineStyle(LineStyleData(weight: max(1, min(16, weight)), color: color, pattern: pattern)))
    }

    /// Renames a user style.
    public static func rename(_ id: ElementID, to name: String, in tx: TransactionContext) throws {
        guard let e = tx.model[id], e.lineStyle != nil else { throw TransactionError("The line style no longer exists.") }
        guard !isStandard(e.name) else { throw TransactionError("“\(e.name)” is a standard line style and can't be renamed.") }
        let n = try validName(name, excluding: id, tx.model)
        tx.update(id) { $0.name = n }
    }

    /// Changes weight, colour or pattern (any style).
    public static func edit(_ id: ElementID, weight: Int? = nil, color: RGBColor? = nil, pattern: LinePatternKind? = nil, in tx: TransactionContext) throws {
        guard tx.model[id]?.lineStyle != nil else { throw TransactionError("The line style no longer exists.") }
        if let w = weight, !(1...16).contains(w) { throw TransactionError("Line weights run from 1 to 16.") }
        tx.update(id) { e in
            if let w = weight { e.lineStyle?.weight = w }
            if let c = color { e.lineStyle?.color = c }
            if let p = pattern { e.lineStyle?.pattern = p }
        }
    }

    /// Lines drawn with a style.
    public static func users(of id: ElementID, _ model: BIMModel) -> [Element] {
        model.allElements.filter { $0.modelLine?.styleID == id }
    }

    /// Deletes a user style; lines drawn with it move to `replacement` (default "Thin Lines"). Returns how many lines moved.
    @discardableResult
    public static func delete(_ id: ElementID, replacement: ElementID? = nil, in tx: TransactionContext) throws -> Int {
        guard let e = tx.model[id], e.lineStyle != nil else { throw TransactionError("The line style no longer exists.") }
        guard !isStandard(e.name) else { throw TransactionError("“\(e.name)” is a standard line style and can't be deleted.") }
        let target = replacement ?? tx.model.lineStyle(named: defaultName)?.id
        if let r = target, r == id || tx.model[r]?.lineStyle == nil { throw TransactionError("Choose another line style to replace it.") }
        let moved = users(of: id, tx.model)
        for l in moved { tx.update(l.id) { $0.modelLine?.styleID = target } }
        tx.delete(id)
        return moved.count
    }

    /// The stroke of a detail or model line: its style's weight, colour and pattern (halftone from the view).
    public static func stroke(_ styleID: ElementID?, _ model: BIMModel, fallback: GStroke) -> GStroke {
        guard let ls = model[styleID]?.lineStyle else { return fallback }
        return GStroke(weight: ls.weight, color: ls.color, pattern: ls.pattern, halftone: fallback.halftone)
    }
}

// MARK: - Text and dimension types

/// Standard text and dimension types in the project's unit system.
public enum AnnotationTypes {
    public struct TextSpec: Sendable {
        public let name: String
        /// Cap height on paper (meters).
        public let size: Double
        public let bold: Bool
    }

    /// 2.5 / 3.5 / 5 mm (metric) or 3/32", 1/8", 3/16", 1/4" (imperial).
    public static func textSpecs(_ units: UnitsSettings) -> [TextSpec] {
        if units.system == .imperial {
            let inch = 0.0254
            return [TextSpec(name: "3/32\" Arial", size: inch * 3 / 32, bold: false), TextSpec(name: "1/8\" Arial", size: inch / 8, bold: false),
                    TextSpec(name: "3/16\" Arial", size: inch * 3 / 16, bold: false), TextSpec(name: "1/4\" Arial Bold", size: inch / 4, bold: true)]
        }
        return [TextSpec(name: "2.5mm Arial", size: 0.0025, bold: false), TextSpec(name: "3.5mm Arial", size: 0.0035, bold: false),
                TextSpec(name: "5mm Arial Bold", size: 0.005, bold: true)]
    }

    public struct DimensionSpec: Sendable {
        public let name: String
        public let textSize: Double
        public let tick: DimensionTickMark
    }

    public static func dimensionSpecs(_ units: UnitsSettings) -> [DimensionSpec] {
        if units.system == .imperial {
            let t = 0.0254 * 3 / 32
            return [DimensionSpec(name: "Linear - 3/32\" Arial", textSize: t, tick: .diagonal),
                    DimensionSpec(name: "Linear - 3/32\" Arrow", textSize: t, tick: .arrow),
                    DimensionSpec(name: "Linear - 3/32\" Dot", textSize: t, tick: .dot)]
        }
        return [DimensionSpec(name: "Linear - 2.5mm Arial", textSize: 0.0025, tick: .diagonal),
                DimensionSpec(name: "Linear - 2.5mm Arrow", textSize: 0.0025, tick: .arrow),
                DimensionSpec(name: "Linear - 2.5mm Dot", textSize: 0.0025, tick: .dot)]
    }

    public static func textType(_ spec: TextSpec) -> TypeData {
        TypeData(instanceCategory: .textNotes, systemFamily: .textStyle, familyName: "Text",
                 params: [AnnotationParams.textSize: .double(spec.size), AnnotationParams.textBold: .bool(spec.bold),
                          AnnotationParams.textBackground: .text(TextBackground.opaque.rawValue),
                          AnnotationParams.textArrowhead: .text(LeaderArrowhead.arrow.rawValue)])
    }

    public static func dimensionType(_ spec: DimensionSpec) -> TypeData {
        TypeData(instanceCategory: .dimensions, systemFamily: .dimensionStyle, familyName: "Linear Dimension Style",
                 params: [AnnotationParams.dimensionTextSize: .double(spec.textSize), AnnotationParams.dimensionTick: .text(spec.tick.rawValue)])
    }

    /// Creates the standard text and dimension types missing from the model. Returns the ids by name.
    /// `texts` / `dimensions` limit how many are created (templates create the rest last, so earlier ids stay put).
    @discardableResult
    public static func ensureStandard(in tx: TransactionContext, units: UnitsSettings, texts textLimit: Int? = nil, dimensions dimLimit: Int? = nil) -> [String: ElementID] {
        var out: [String: ElementID] = [:]
        let texts = tx.model.types(for: .textNotes), dims = tx.model.types(for: .dimensions)
        for s in textSpecs(units).prefix(textLimit ?? .max) {
            out[s.name] = texts.first { $0.name == s.name }?.id ?? tx.create(.elementTypes, name: s.name, data: .type(textType(s)))
        }
        for s in dimensionSpecs(units).prefix(dimLimit ?? .max) {
            out[s.name] = dims.first { $0.name == s.name }?.id ?? tx.create(.elementTypes, name: s.name, data: .type(dimensionType(s)))
        }
        return out
    }
}

// MARK: - Keynotes

/// A keynote key with its text. Keys are hierarchical ("A1" is the group of "A1.03").
public struct Keynote: Sendable, Hashable, Identifiable {
    public var key: String
    public var text: String
    public var id: String { key }
    public init(_ key: String, _ text: String) { self.key = key; self.text = text }
    /// The parent group key (nil for top-level groups).
    public var parent: String? { key.firstIndex(of: ".").map { String(key[..<$0]) } }
}

/// The built-in keynote table (Arcus's own short architectural list). Element keynotes come from the type's
/// Keynote parameter, material keynotes from the material's, user keynotes from this table.
public enum KeynoteTable {
    public static let standard: [Keynote] = [
        Keynote("A1", "Substructure"), Keynote("A1.01", "Concrete footing"), Keynote("A1.02", "Ground-bearing slab on membrane"),
        Keynote("A1.03", "Compacted hardcore"), Keynote("A1.04", "Damp-proof course"),
        Keynote("A2", "Walls"), Keynote("A2.01", "Brick outer leaf"), Keynote("A2.02", "Rigid insulation in cavity"),
        Keynote("A2.03", "Concrete block inner leaf"), Keynote("A2.04", "Timber stud partition"), Keynote("A2.05", "Plasterboard lining"),
        Keynote("A2.06", "Plaster finish"), Keynote("A2.07", "Movement joint with sealant"),
        Keynote("A3", "Floors"), Keynote("A3.01", "Reinforced concrete slab"), Keynote("A3.02", "Sand and cement screed"),
        Keynote("A3.03", "Timber floor finish"), Keynote("A3.04", "Ceramic tiles on adhesive"), Keynote("A3.05", "Acoustic underlay"),
        Keynote("A4", "Roofs"), Keynote("A4.01", "Clay roof tiles on battens"), Keynote("A4.02", "Breather membrane"),
        Keynote("A4.03", "Mineral wool insulation between rafters"), Keynote("A4.04", "Single-ply roof membrane"), Keynote("A4.05", "Rainwater gutter"),
        Keynote("A5", "Openings"), Keynote("A5.01", "Timber door and frame"), Keynote("A5.02", "Aluminium window"),
        Keynote("A5.03", "Precast concrete sill"), Keynote("A5.04", "Steel lintel"),
        Keynote("A6", "Finishes"), Keynote("A6.01", "Suspended ceiling"), Keynote("A6.02", "Painted plasterboard ceiling"),
        Keynote("A6.03", "Skirting board"), Keynote("A6.04", "Emulsion paint"),
        Keynote("A7", "Site"), Keynote("A7.01", "Paving slabs on sand bed"), Keynote("A7.02", "Topsoil and planting"), Keynote("A7.03", "Kerb"),
    ]

    public static func text(for key: String) -> String? { standard.first { $0.key == key }?.text }
}

// MARK: - Text metrics

/// Approximate text measurements for model-side geometry (hit areas, leader attachment, wrap preview). Renderers use
/// CoreText and are exact; these widths follow Helvetica Neue closely enough for picking and layout of leaders.
public enum TextMetrics {
    /// Advance width of a character as a multiple of the cap height.
    static func advance(_ c: Character, bold: Bool) -> Double {
        let w: Double
        switch c {
        case "i", "j", "l", ".", ",", ":", ";", "!", "|", "'", "`", "I": w = 0.34
        case " ": w = 0.39
        case "f", "t", "r", "(", ")", "[", "]", "-", "/", "\\": w = 0.52
        case "m", "w": w = 1.2
        case "M", "W", "@", "%": w = 1.3
        case "0"..."9": w = 0.78
        case "A"..."Z": w = 0.95
        case "\t": w = 1.6
        default: w = c.isUppercase ? 0.95 : (c.isASCII ? 0.76 : 1.0)
        }
        return bold ? w * 1.07 : w
    }

    /// Width of one line of text on paper (meters) at cap height `height`.
    public static func lineWidth<S: StringProtocol>(_ s: S, height: Double, bold: Bool = false) -> Double {
        s.reduce(0) { $0 + advance($1, bold: bold) } * height
    }

    /// The lines a text wraps into at `wrap` paper meters (0 = only explicit line breaks). Words longer than the wrap
    /// width stay on a line of their own.
    public static func lines(_ text: String, height: Double, bold: Bool = false, wrap: Double = 0) -> [String] {
        var out: [String] = []
        for para in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard wrap > 0, lineWidth(para, height: height, bold: bold) > wrap else { out.append(String(para)); continue }
            var current = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: false) {
                let candidate = current.isEmpty ? String(word) : current + " " + word
                if !current.isEmpty && lineWidth(candidate, height: height, bold: bold) > wrap {
                    out.append(current)
                    current = String(word)
                } else {
                    current = candidate
                }
            }
            out.append(current)
        }
        return out
    }

    /// Size of a text block on paper (meters): the widest line × (cap height + line pitch per extra line).
    public static func blockSize(_ text: String, height: Double, bold: Bool = false, wrap: Double = 0) -> Vec2 {
        let ls = lines(text, height: height, bold: bold, wrap: wrap)
        let w = ls.map { lineWidth($0, height: height, bold: bold) }.max() ?? 0
        let h = height + Double(max(ls.count - 1, 0)) * height * lineSpacing
        return Vec2(wrap > 0 ? min(max(w, 0), wrap) : w, h)
    }

    /// Baseline-to-baseline distance as a multiple of the cap height (matches the renderers).
    public static let lineSpacing = 1.7
}
