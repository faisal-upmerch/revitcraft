import Foundation
import ArcusGeometry

// W4-HATCH: line-family fill patterns — the model behind cut and surface hatches, the standard library, the text
// format and the undoable edits behind Manage ▸ Additional Settings ▸ Fill Patterns.

/// One family of parallel lines of a fill pattern. Lengths are millimetres: paper millimetres for drafting patterns
/// (the hatch looks the same at every view scale) and model millimetres for model patterns (it scales with the view).
public struct HatchFamily: Hashable, Codable, Sendable {
    /// Direction of the lines, degrees counter-clockwise from the +X axis.
    public var angle: Double
    /// A point every line of the family passes through (before the perpendicular spacing is applied).
    public var origin: Vec2
    /// Offset along the line direction between successive parallel lines (staggers dashes; 0 keeps them aligned).
    public var shift: Double
    /// Perpendicular distance between successive lines (> 0).
    public var spacing: Double
    /// Dash pattern along each line: positive = pen down, negative = gap, 0 = a dot. Empty = continuous.
    public var dashes: [Double]

    public init(angle: Double, origin: Vec2 = .zero, shift: Double = 0, spacing: Double, dashes: [Double] = []) {
        self.angle = angle; self.origin = origin; self.shift = shift; self.spacing = spacing; self.dashes = dashes
    }

    /// Length of one dash period (0 for a continuous line).
    public var period: Double { dashes.reduce(0) { $0 + abs($1) } }
    /// Whether the family is drawable: a positive finite spacing and a positive period (or continuous).
    public var isValid: Bool {
        spacing.isFinite && spacing > 0.01 && angle.isFinite && origin.x.isFinite && origin.y.isFinite && shift.isFinite
            && dashes.allSatisfy(\.isFinite) && (dashes.isEmpty || (period > 0.01 && dashes.contains { $0 >= 0 }))
    }
}

/// The geometry of a fill pattern as renderers see it: its line families and whether it is sized on paper or in the model.
public struct HatchPattern: Hashable, Sendable {
    public var families: [HatchFamily]
    public var isModel: Bool
    public init(families: [HatchFamily], isModel: Bool) { self.families = families; self.isModel = isModel }
    public var isEmpty: Bool { families.isEmpty }
}

extension FillPatternData {
    /// Line-family definition (nil for solid fills and for patterns of older files, which keep the procedural `kind`).
    public var hatch: HatchPattern? {
        guard let f = families, !f.isEmpty, kind != .solid else { return nil }
        return HatchPattern(families: f.filter(\.isValid), isModel: isModelPattern)
    }
    public var isSolid: Bool { kind == .solid && (families?.isEmpty ?? true) }
    public var typeName: String { isModelPattern ? "Model" : "Drafting" }
}

// MARK: - Standard library

/// A standard fill pattern definition (original Arcus content: conventional architectural hatches expressed as line
/// families in millimetres).
public struct StandardFillPattern: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var isModel: Bool
    /// The closest procedural kind — the fallback when a hatch is too dense to draw and the legacy pattern for the
    /// 14 names older projects already have.
    public var kind: FillPatternKind
    public var families: [HatchFamily]
    public var description: String

    public var data: FillPatternData {
        var d = FillPatternData(kind: kind, isModelPattern: isModel, spacing: families.first?.spacing ?? 2.0)
        d.families = families
        d.description = description
        return d
    }
}

/// The built-in fill pattern library: drafting hatches for cut materials and model patterns for surfaces.
public enum FillPatternLibrary {
    static func f(_ angle: Double, _ ox: Double, _ oy: Double, _ shift: Double, _ spacing: Double, _ dashes: [Double] = []) -> HatchFamily {
        HatchFamily(angle: angle, origin: Vec2(ox, oy), shift: shift, spacing: spacing, dashes: dashes)
    }
    static func d(_ name: String, _ kind: FillPatternKind, _ description: String, _ families: [HatchFamily]) -> StandardFillPattern {
        StandardFillPattern(name: name, isModel: false, kind: kind, families: families, description: description)
    }
    static func m(_ name: String, _ kind: FillPatternKind, _ description: String, _ families: [HatchFamily]) -> StandardFillPattern {
        StandardFillPattern(name: name, isModel: true, kind: kind, families: families, description: description)
    }
    /// Parallel lines at `angle`, `s` apart.
    static func lines(_ angle: Double, _ s: Double) -> [HatchFamily] { [f(angle, 0, 0, 0, s)] }
    static func cross(_ a: Double, _ s: Double) -> [HatchFamily] { [f(a, 0, 0, 0, s), f(a + 90, 0, 0, 0, s)] }
    /// Running bond of `l` × `h` units (model mm): bed joints every course, head joints staggered by half a unit.
    static func runningBond(_ l: Double, _ h: Double) -> [HatchFamily] {
        [f(0, 0, 0, 0, h), f(90, 0, 0, 0, l, [h, -h]), f(90, l / 2, h, 0, l, [h, -h])]
    }
    /// Stack bond / grid of `l` × `h`.
    static func grid(_ l: Double, _ h: Double) -> [HatchFamily] { [f(0, 0, 0, 0, h), f(90, 0, 0, 0, l)] }
    /// Sand-like stipple: two dot families whose periods don't line up.
    static func stipple(_ s: Double) -> [HatchFamily] {
        [f(0, 0, 0, s * 1.31, s, [0, -s * 2.23]), f(37, s * 0.23, s * 0.54, s * 1.46, s * 1.3, [0, -s * 2.38])]
    }

    public static let drafting: [StandardFillPattern] = [
        d("Solid Fill", .solid, "Poché: coarse-scale cut fill and solid regions", []),
        d("Diagonal Up", .diagonalUp, "45° lines, 3 mm apart", lines(45, 3)),
        d("Diagonal Down", .diagonalDown, "135° lines, 3 mm apart", lines(135, 3)),
        d("Diagonal Up - Small", .diagonalUp, "45° lines, 1.5 mm apart", lines(45, 1.5)),
        d("Diagonal Down - Small", .diagonalDown, "135° lines, 1.5 mm apart", lines(135, 1.5)),
        d("Diagonal Up - Large", .diagonalUp, "45° lines, 6 mm apart", lines(45, 6)),
        d("Horizontal", .horizontal, "Horizontal lines, 3 mm apart", lines(0, 3)),
        d("Horizontal - Small", .horizontal, "Horizontal lines, 1.5 mm apart", lines(0, 1.5)),
        d("Vertical", .vertical, "Vertical lines, 3 mm apart", lines(90, 3)),
        d("Vertical - Small", .vertical, "Vertical lines, 1.5 mm apart", lines(90, 1.5)),
        d("Crosshatch", .crosshatch, "Square crosshatch, 3 mm", cross(0, 3)),
        d("Crosshatch - Small", .crosshatch, "Square crosshatch, 1.5 mm", cross(0, 1.5)),
        d("Diagonal Crosshatch", .diagonalCrosshatch, "45°/135° crosshatch, 3 mm", cross(45, 3)),
        d("Diagonal Crosshatch - Small", .diagonalCrosshatch, "45°/135° crosshatch, 1.5 mm", cross(45, 1.5)),
        d("Dashed Diagonal", .diagonalUp, "45° dashed lines, 3 mm apart", [f(45, 0, 0, 1.5, 3, [3, -1.5])]),
        d("Dots", .sand, "Regular dot grid, 1.5 mm", [f(0, 0, 0, 0, 1.5, [0, -1.5])]),
        d("Dots - Staggered", .sand, "Staggered dots, 2 mm", [f(0, 0, 0, 1, 2, [0, -2])]),
        // Section hatches for materials (drafting: the same on paper at every scale).
        d("Steel", .diagonalUp, "Steel and iron: 45° lines, 3.175 mm apart (ANSI 31 style)", lines(45, 3.175)),
        d("Steel - Double Line", .diagonalUp, "Steel: pairs of 45° lines (ANSI 32 style)", [f(45, 0, 0, 0, 9.525), f(45, 4.49, 0, 0, 9.525)]),
        d("Brass - Bronze", .diagonalUp, "Brass, bronze, copper: 45° line and dashed line pairs (ANSI 33 style)",
          [f(45, 0, 0, 0, 6.35), f(45, 4.49, 0, 0, 6.35, [3.175, -1.5875])]),
        d("Plastic - Rubber", .diagonalUp, "Plastic and rubber: groups of 45° lines (ANSI 34 style)",
          [f(45, 0, 0, 0, 19.05), f(45, 4.49, 0, 0, 19.05), f(45, 8.98, 0, 0, 19.05), f(45, 13.47, 0, 0, 19.05)]),
        d("Fire Brick", .diagonalUp, "Fire brick and refractory: 45° lines with dash-dot lines (ANSI 35 style)",
          [f(45, 0, 0, 0, 6.35), f(45, 4.49, 0, 0, 6.35, [7.9375, -1.5875, 0, -1.5875])]),
        d("Marble - Slate", .diagonalUp, "Marble, slate, glass in section: staggered 45° dash-dot lines (ANSI 36 style)",
          [f(45, 0, 0, 5.5563, 6.35, [7.9375, -1.5875, 0, -1.5875])]),
        d("Lead - Zinc", .diagonalCrosshatch, "Lead, zinc, magnesium: 45°/135° crosshatch, 3.175 mm (ANSI 37 style)", cross(45, 3.175)),
        d("Aluminum", .diagonalUp, "Aluminium: staggered 45° dashed lines (ANSI 38 style)", [f(45, 0, 0, 4.7625, 6.35, [7.9375, -4.7625])]),
        d("Concrete", .concrete, "Cast-in-place concrete: aggregate triangles with stipple",
          [f(50, 0, 0, 4.12, 5.9, [0.75, -8.3, 0, -6.6]), f(355, 0, 0, 4.3, 6.1, [0.6, -7.9, 0, -5.5]),
           f(100.4, 0.6, 0, 3.7, 5.3, [0.7, -9.1, 0, -7.2]), f(46, 0, 0, 3.3, 4.7, [0, -6.1])]),
        d("Concrete - Precast", .concrete, "Precast concrete: aggregate with fewer dots",
          [f(50, 0, 0, 4.12, 7.9, [0.75, -10.3, 0, -8.6]), f(355, 0, 0, 4.3, 8.1, [0.6, -9.9, 0, -7.5]), f(100.4, 0.6, 0, 3.7, 7.3, [0.7, -11.1])]),
        d("Concrete - Lightweight", .sand, "Lightweight concrete and screed: fine stipple", stipple(1.1)),
        d("Masonry - Brick", .diagonalUp, "Brick in section: 45° lines, 2 mm apart", lines(45, 2)),
        d("Masonry - Concrete Block", .diagonalCrosshatch, "Concrete block (CMU) in section: 45°/135° crosshatch, 4 mm", cross(45, 4)),
        d("Masonry - Stone", .crosshatch, "Stone in section: irregular broken lines",
          [f(0, 0, 0, 4.7, 4.0, [7.2, -1.3, 3.4, -0.9]), f(90, 0.7, 0.3, 3.3, 5.5, [2.9, -4.1, 1.2, -5.1]), f(45, 0, 0, 6.7, 8.9, [1.1, -9.3])]),
        d("Earth", .earth, "Earth and compacted fill: groups of three short 45° strokes",
          [f(45, 0, 0, 4.0, 3.9, [2.2, -4.8]), f(45, 0, 1.3, 4.0, 3.9, [2.2, -4.8]), f(45, 0, 2.6, 4.0, 3.9, [2.2, -4.8])]),
        d("Sand", .sand, "Sand and mortar: fine random stipple", stipple(0.9)),
        d("Gravel", .earth, "Gravel and hardcore: short strokes at mixed angles",
          [f(30, 0, 0, 2.3, 3.1, [1.2, -3.7]), f(140, 1, 1, 2.9, 3.7, [1.4, -4.1]), f(85, 0.5, 1.5, 3.1, 3.3, [0.9, -4.5])]),
        d("Insulation", .insulation, "Batt insulation: zigzag bands, 3 mm high",
          [f(60, 0, 0, 0, 3, [3.4641, -3.4641]), f(120, 0, 0, 0, 3, [3.4641, -3.4641])]),
        d("Insulation - Rigid", .diagonalCrosshatch, "Rigid insulation: 45°/135° crosshatch, 2 mm", cross(45, 2)),
        d("Insulation - Rigid Board", .diagonalUp, "Rigid board: 45° lines, 2 mm apart", lines(45, 2)),
        d("Wood - Framing", .diagonalCrosshatch, "Cut lumber: diagonal cross, 4 mm", cross(45, 4)),
        d("Wood - Blocking", .diagonalUp, "Blocking and continuous framing: 45° lines, 2 mm", lines(45, 2)),
        d("Wood Grain", .wood, "Finish wood: broken grain lines", [f(0, 0, 0, 5.3, 1.5, [9.5, -1.3, 4.2, -0.9]), f(0, 2.1, 0.75, 7.1, 1.5, [6.1, -2.3])]),
        d("Wood - Plywood", .horizontal, "Plywood and sheathing: horizontal lines with a diagonal", [f(0, 0, 0, 0, 1.2), f(45, 0, 0, 0, 6)]),
        d("Gypsum - Plaster", .sand, "Plaster and gypsum board: dense stipple", stipple(1.0)),
        d("Glass", .horizontal, "Glass in section: fine horizontal lines", lines(0, 1.2)),
        d("Tile", .crosshatch, "Ceramic tile in section: 45° lines with dots", [f(45, 0, 0, 0, 2.5), f(0, 0, 0, 1.25, 2.5, [0, -2.5])]),
        d("Membrane", .horizontal, "Membranes and felts: dense horizontal lines", lines(0, 0.9)),
        d("Metal Deck - Grating", .crosshatch, "Grating and mesh: 2 mm square crosshatch", cross(0, 2)),
        d("Water", .horizontal, "Water: dashed horizontal lines", [f(0, 0, 0, 2, 2, [4, -2])]),
        d("Paper Grid 3mm", .grid, "Fine paper grid, 3 mm", cross(0, 3)),
    ]

    public static let model: [StandardFillPattern] = [
        m("Brick", .brick, "Brick running bond, 225 × 75 mm courses", runningBond(225, 75)),
        m("Brick - Stack Bond", .brick, "Brick stack bond, 225 × 75 mm", grid(225, 75)),
        m("Brick - Modular 8 x 2 2/3 in", .brick, "Modular brick running bond, 203 × 68 mm", runningBond(203.2, 67.7)),
        m("Concrete Block - Running Bond", .brick, "Concrete block, 400 × 200 mm", runningBond(400, 200)),
        m("Concrete Block - Stack Bond", .grid, "Concrete block stack bond, 400 × 200 mm", grid(400, 200)),
        m("Stone - Ashlar", .brick, "Coursed ashlar, 600 × 300 mm", runningBond(600, 300)),
        m("Stone - Coursed 300", .horizontal, "Coursed stone, 300 mm courses", lines(0, 300)),
        m("Tile 100 x 100", .grid, "Mosaic tile, 100 mm", grid(100, 100)),
        m("Tile 200 x 200", .grid, "Tile, 200 mm", grid(200, 200)),
        m("Tile 300 x 300", .grid, "Tile, 300 mm", grid(300, 300)),
        m("Tile 300 x 600", .grid, "Tile, 300 × 600 mm", grid(600, 300)),
        m("Tile 600 x 600", .grid, "Tile, 600 mm", grid(600, 600)),
        m("Tile 450 x 450 Diagonal", .diagonalCrosshatch, "Tile, 450 mm set diagonally", cross(45, 450)),
        m("Paving 400 x 400", .grid, "Paving slabs, 400 mm", grid(400, 400)),
        m("Paving 600 x 600", .grid, "Paving slabs, 600 mm", grid(600, 600)),
        m("Paving - Herringbone 200 x 100", .diagonalCrosshatch, "Block paving, herringbone", [f(45, 0, 0, 0, 141.42, [141.42, -141.42]), f(135, 0, 0, 70.71, 141.42, [141.42, -141.42])]),
        m("Wood - Plank 100", .horizontal, "Timber boards, 100 mm", lines(0, 100)),
        m("Wood - Plank 150", .horizontal, "Timber boards, 150 mm", lines(0, 150)),
        m("Wood - Plank 200", .horizontal, "Timber boards, 200 mm", lines(0, 200)),
        m("Wood - Parquet 300", .grid, "Parquet blocks, 300 mm", [f(0, 0, 0, 0, 300), f(90, 0, 0, 0, 300), f(0, 0, 0, 0, 100, [300, -300]), f(90, 0, 0, 0, 100, [300, -300])]),
        m("Grid", .grid, "600 mm grid", grid(600, 600)),
        m("Ceiling 600 x 600", .grid, "Suspended ceiling grid, 600 mm", grid(600, 600)),
        m("Ceiling 600 x 1200", .grid, "Suspended ceiling grid, 600 × 1200 mm", grid(1200, 600)),
        m("Ceiling 2 x 2 ft", .grid, "Suspended ceiling grid, 2 ft", grid(609.6, 609.6)),
        m("Ceiling 2 x 4 ft", .grid, "Suspended ceiling grid, 2 × 4 ft", grid(1219.2, 609.6)),
        m("Roofing - Standing Seam 450", .vertical, "Standing seam roofing, 450 mm", lines(90, 450)),
        m("Roofing - Tile 300", .horizontal, "Roof tiles, 300 mm courses", [f(0, 0, 0, 0, 300), f(90, 0, 0, 0, 200, [300, -300]), f(90, 100, 300, 0, 200, [300, -300])]),
        m("Roofing - Shingle 250", .brick, "Shingles, 250 mm exposure", runningBond(500, 250)),
        m("Cladding - Board 150", .horizontal, "Horizontal boarding, 150 mm", lines(0, 150)),
        m("Cladding - Panel 1200 x 2400", .grid, "Panel cladding, 1200 × 2400 mm", grid(1200, 2400)),
        m("Metal Panel 900", .vertical, "Profiled metal panels, 900 mm cover", lines(90, 900)),
        m("Glass - Curtain Wall 1500", .grid, "Curtain wall grid, 1500 mm", grid(1500, 1500)),
        m("Gravel - Model", .sand, "Gravel surface: staggered dots, 50 mm", [f(0, 0, 0, 25, 50, [0, -50]), f(0, 12, 17, 25, 50, [0, -50])]),
        m("Grass", .earth, "Grass: short vertical tufts, 200 mm", [f(90, 0, 0, 0, 200, [40, -260]), f(90, 100, 150, 0, 200, [40, -260])]),
        m("Earth - Model", .earth, "Earth for model-scale sections: 45° strokes, 300 mm", [f(45, 0, 0, 300, 250, [180, -320]), f(45, 0, 80, 300, 250, [180, -320])]),
        m("Sand - Model", .sand, "Sand for model-scale sections: dots, 80 mm", [f(0, 0, 0, 40, 80, [0, -80]), f(0, 15, 25, 40, 80, [0, -80])]),
    ]

    public static let all: [StandardFillPattern] = drafting + model
    static let index: [String: StandardFillPattern] = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
    public static func named(_ name: String) -> StandardFillPattern? { index[name] }
    public static func isStandard(_ name: String) -> Bool { index[name] != nil }

    /// Adds every standard pattern this model doesn't have yet. Existing patterns of the same name that came from an
    /// older file (no line families) get the standard definition. Returns the number of patterns created or upgraded.
    @discardableResult
    public static func ensureStandard(in tx: TransactionContext) -> Int {
        var n = 0
        var byName: [String: Element] = [:]
        for e in tx.model.elements(.fillPatterns) where byName[e.name] == nil { byName[e.name] = e }
        for p in all {
            if let e = byName[p.name] {
                if e.fillPattern?.families == nil, p.kind != .solid {
                    tx.update(e.id) { $0.fillPattern = p.data }
                    n += 1
                }
            } else {
                tx.create(.fillPatterns, name: p.name, data: .fillPattern(p.data))
                n += 1
            }
        }
        return n
    }

    /// Standard patterns a model lacks.
    public static func missing(_ model: BIMModel) -> [StandardFillPattern] {
        let names = Set(model.elements(.fillPatterns).map(\.name))
        return all.filter { !names.contains($0.name) }
    }
}

// MARK: - Text format

/// Arcus's fill pattern text format (`.pat`-style, documented in Docs/FillPatternFormat.md):
///
///     ;%UNITS=MM                      (MM or INCH; default MM — applies to the whole file)
///     *Concrete, cast-in-place       (a pattern: name, optional description)
///     ;%TYPE=DRAFTING                (DRAFTING or MODEL; default DRAFTING — applies to the pattern above)
///     50, 0,0, 4.12,5.9, 0.75,-8.3,0,-6.6
///     ...                            (one line family per line: angle, x, y, shift, spacing, dashes…)
///
/// Comments start with `;` (except `;%` directives); blank lines are ignored.
public enum FillPatternText {
    public struct Entry: Hashable, Sendable {
        public var name: String
        public var description: String
        public var isModel: Bool
        public var families: [HatchFamily]
        public init(name: String, description: String = "", isModel: Bool = false, families: [HatchFamily]) {
            self.name = name; self.description = description; self.isModel = isModel; self.families = families
        }
        public var data: FillPatternData {
            var d = FillPatternData(kind: FillPatternText.closestKind(families), isModelPattern: isModel, spacing: families.first?.spacing ?? 2)
            d.families = families
            d.description = description
            return d
        }
    }

    public enum ParseError: Error, Hashable, Sendable, CustomStringConvertible {
        case familyBeforePattern(line: Int)
        case badFamily(line: Int, text: String)
        case emptyPattern(name: String)
        public var description: String {
            switch self {
            case .familyBeforePattern(let l): "Line \(l): a line family appears before any *Name header."
            case .badFamily(let l, let t): "Line \(l): expected “angle, x, y, shift, spacing[, dashes…]” but found “\(t)”."
            case .emptyPattern(let n): "Pattern “\(n)” has no line families."
            }
        }
    }

    /// Parses every pattern in `text`.
    public static func parse(_ text: String) throws(ParseError) -> [Entry] {
        var out: [Entry] = []
        var current: Entry?
        var unitScale = 1.0
        func flush() throws(ParseError) {
            if let c = current {
                if c.families.isEmpty { throw .emptyPattern(name: c.name) }
                out.append(c)
            }
            current = nil
        }
        for (i, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix(";%") {
                let body = line.dropFirst(2).uppercased().replacingOccurrences(of: " ", with: "")
                if body.hasPrefix("UNITS=") { unitScale = body.hasSuffix("INCH") || body.hasSuffix("IN") ? 25.4 : 1 }
                if body.hasPrefix("TYPE="), var c = current { c.isModel = body.hasSuffix("MODEL"); current = c }
                continue
            }
            if line.hasPrefix(";") { continue }
            if line.hasPrefix("*") {
                try flush()
                let rest = line.dropFirst()
                let parts = rest.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                current = Entry(name: parts.first ?? "", description: parts.count > 1 ? parts[1] : "", families: [])
                continue
            }
            guard var c = current else { throw .familyBeforePattern(line: i + 1) }
            let nums = line.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" }).compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard nums.count >= 5, nums.allSatisfy(\.isFinite), nums[4] > 0 else { throw .badFamily(line: i + 1, text: line) }
            let s = unitScale
            c.families.append(HatchFamily(angle: nums[0], origin: Vec2(nums[1] * s, nums[2] * s), shift: nums[3] * s, spacing: nums[4] * s,
                                          dashes: nums.dropFirst(5).map { $0 * s }))
            current = c
        }
        try flush()
        return out
    }

    /// Formats patterns in the text format (millimetres).
    public static func format(_ entries: [Entry]) -> String {
        var lines = [";%UNITS=MM"]
        for e in entries {
            lines.append("*" + e.name + (e.description.isEmpty ? "" : ", " + e.description))
            lines.append(";%TYPE=" + (e.isModel ? "MODEL" : "DRAFTING"))
            for f in e.families {
                let nums = [f.angle, f.origin.x, f.origin.y, f.shift, f.spacing] + f.dashes
                lines.append(nums.map { num($0) }.joined(separator: ", "))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Formats one family as a line of the text format.
    public static func formatFamily(_ f: HatchFamily) -> String {
        ([f.angle, f.origin.x, f.origin.y, f.shift, f.spacing] + f.dashes).map { num($0) }.joined(separator: ", ")
    }

    static func num(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1e9 { return String(Int(v)) }
        var s = String(format: "%.4f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// The procedural kind that best stands in for a set of families (density fallback and legacy pickers).
    public static func closestKind(_ families: [HatchFamily]) -> FillPatternKind {
        guard let a = families.first else { return .solid }
        let angles = families.map { Angle.normalizeDegrees($0.angle) }
        func near(_ x: Double, _ t: Double) -> Bool { abs(x - t) < 5 || abs(x - t - 180) < 5 }
        let dotted = families.allSatisfy { $0.dashes.contains(0) && !$0.dashes.contains { $0 > 0 } }
        if dotted { return .sand }
        if families.count >= 2, angles.contains(where: { near($0, 0) }), angles.contains(where: { near($0, 90) }) { return .crosshatch }
        if families.count >= 2, angles.contains(where: { near($0, 45) }), angles.contains(where: { near($0, 135) }) { return .diagonalCrosshatch }
        if families.count >= 3 { return .concrete }
        if near(angles[0], 0) { return a.dashes.isEmpty ? .horizontal : .wood }
        if near(angles[0], 90) { return .vertical }
        if near(angles[0], 135) { return .diagonalDown }
        return .diagonalUp
    }
}

extension Angle {
    /// Degrees folded into 0 ≤ a < 180 (a line's direction has no sign).
    static func normalizeDegrees(_ a: Double) -> Double {
        var d = a.truncatingRemainder(dividingBy: 180)
        if d < 0 { d += 180 }
        return d
    }
}

// MARK: - Edits

/// Undoable edits of the project's fill patterns (each runs inside a transaction).
public enum FillPatternEdits {
    public enum EditError: Error, Hashable, Sendable, CustomStringConvertible {
        case emptyName, duplicateName(String), notFound, noFamilies, invalidFamily(Int), solidLocked
        public var description: String {
            switch self {
            case .emptyName: "Enter a name."
            case .duplicateName(let n): "A fill pattern named “\(n)” already exists."
            case .notFound: "The fill pattern no longer exists."
            case .noFamilies: "A pattern needs at least one line family."
            case .invalidFamily(let i): "Line family \(i + 1) has an invalid spacing, angle or dash pattern."
            case .solidLocked: "Solid Fill cannot be edited or deleted."
            }
        }
    }

    public static func validName(_ raw: String, excluding: ElementID? = nil, _ model: BIMModel) throws(EditError) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw .emptyName }
        if model.elements(.fillPatterns).contains(where: { $0.id != excluding && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            throw .duplicateName(name)
        }
        return name
    }

    static func validate(_ families: [HatchFamily]) throws(EditError) {
        if families.isEmpty { throw .noFamilies }
        for (i, f) in families.enumerated() where !f.isValid { throw .invalidFamily(i) }
    }

    @discardableResult
    public static func create(name: String, isModel: Bool, families: [HatchFamily], description: String = "", in tx: TransactionContext) throws(EditError) -> ElementID {
        let n = try validName(name, tx.model)
        try validate(families)
        var d = FillPatternData(kind: FillPatternText.closestKind(families), isModelPattern: isModel, spacing: families.first?.spacing ?? 2)
        d.families = families
        d.description = description
        return tx.create(.fillPatterns, name: n, data: .fillPattern(d))
    }

    /// Replaces a pattern's definition (name and/or families/type); the procedural fallback follows the families.
    public static func edit(_ id: ElementID, name: String? = nil, isModel: Bool? = nil, families: [HatchFamily]? = nil, description: String? = nil,
                            in tx: TransactionContext) throws(EditError) {
        guard let e = tx.model[id], var d = e.fillPattern else { throw .notFound }
        if d.isSolid { throw .solidLocked }
        let newName = try name.map { (n) throws(EditError) in try validName(n, excluding: id, tx.model) }
        if let families {
            try validate(families)
            d.families = families
            d.kind = FillPatternText.closestKind(families)
            d.spacing = families.first?.spacing ?? d.spacing
        }
        if let isModel { d.isModelPattern = isModel }
        if let description { d.description = description }
        tx.update(id) { el in
            if let newName { el.name = newName }
            el.fillPattern = d
        }
    }

    @discardableResult
    public static func duplicate(_ id: ElementID, in tx: TransactionContext) throws(EditError) -> ElementID {
        guard let e = tx.model[id], let d = e.fillPattern else { throw .notFound }
        var n = 2
        var name = "Copy of \(e.name)"
        while (try? validName(name, tx.model)) == nil { name = "Copy (\(n)) of \(e.name)"; n += 1 }
        return tx.create(.fillPatterns, name: name, data: .fillPattern(d))
    }

    /// Imports parsed entries; names that exist get " (2)", " (3)"… Returns the created ids in order.
    @discardableResult
    public static func importEntries(_ entries: [FillPatternText.Entry], in tx: TransactionContext) throws(EditError) -> [ElementID] {
        var ids: [ElementID] = []
        for e in entries {
            var name = e.name.isEmpty ? "Imported Pattern" : e.name
            var n = 2
            while (try? validName(name, tx.model)) == nil { name = "\(e.name) (\(n))"; n += 1 }
            ids.append(try create(name: name, isModel: e.isModel, families: e.families, description: e.description, in: tx))
        }
        return ids
    }

    /// Everything that references a pattern: materials (cut or surface), filled region types, type coarse fills,
    /// and views whose overrides name it.
    public static func users(of id: ElementID, _ model: BIMModel) -> [Element] {
        var out: [Element] = []
        for e in model.elements(.materials) where e.material?.cutPatternID == id || e.material?.surfacePatternID == id { out.append(e) }
        for e in model.elements(.elementTypes) {
            guard let p = e.typeData?.params else { continue }
            if p[ParameterID("region.fillPattern")]?.refValue == id || p[ParameterID("type.coarseFillPattern")]?.refValue == id { out.append(e) }
        }
        for e in model.views {
            guard let v = e.view else { continue }
            let all = Array(v.visibility.categoryOverrides.values) + Array(v.visibility.elementOverrides.values)
            if all.contains(where: { $0.cutPatternID == id || $0.surfacePatternID == id }) { out.append(e) }
        }
        return out
    }

    /// Deletes a pattern; references fall back to their category defaults.
    public static func delete(_ id: ElementID, in tx: TransactionContext) throws(EditError) {
        guard let e = tx.model[id], let d = e.fillPattern else { throw .notFound }
        if d.isSolid { throw .solidLocked }
        for u in users(of: id, tx.model) {
            tx.update(u.id) { el in
                if el.material?.cutPatternID == id { el.material?.cutPatternID = nil }
                if el.material?.surfacePatternID == id { el.material?.surfacePatternID = nil }
                if el.typeData?.params[ParameterID("region.fillPattern")]?.refValue == id { el.typeData?.params[ParameterID("region.fillPattern")] = nil }
                if el.typeData?.params[ParameterID("type.coarseFillPattern")]?.refValue == id { el.typeData?.params[ParameterID("type.coarseFillPattern")] = nil }
                if var v = el.view {
                    for k in v.visibility.categoryOverrides.keys {
                        if v.visibility.categoryOverrides[k]?.cutPatternID == id { v.visibility.categoryOverrides[k]?.cutPatternID = nil }
                        if v.visibility.categoryOverrides[k]?.surfacePatternID == id { v.visibility.categoryOverrides[k]?.surfacePatternID = nil }
                    }
                    for k in v.visibility.elementOverrides.keys {
                        if v.visibility.elementOverrides[k]?.cutPatternID == id { v.visibility.elementOverrides[k]?.cutPatternID = nil }
                        if v.visibility.elementOverrides[k]?.surfacePatternID == id { v.visibility.elementOverrides[k]?.surfacePatternID = nil }
                    }
                    el.view = v
                }
            }
        }
        tx.delete(id)
    }

    /// The project's patterns sorted for display: Solid Fill, then drafting, then model, each alphabetically.
    public static func sorted(_ model: BIMModel) -> [Element] {
        model.elements(.fillPatterns).sorted { a, b in
            let sa = a.fillPattern?.isSolid == true, sb = b.fillPattern?.isSolid == true
            if sa != sb { return sa }
            let ma = a.fillPattern?.isModelPattern == true, mb = b.fillPattern?.isModelPattern == true
            if ma != mb { return !ma }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// The project's pattern with this name.
    public static func pattern(named name: String, _ model: BIMModel) -> Element? {
        model.elements(.fillPatterns).first { $0.name == name }
    }
}

// MARK: - Material defaults

/// Default cut and surface patterns for a material, by name and class — what the material library and new materials
/// start with (standard pattern names).
public enum MaterialPatternDefaults {
    public struct Defaults: Hashable, Sendable {
        public var cut: String?
        public var surface: String?
        public var cutColor: RGBColor
    }

    static let ink = RGBColor(0.25, 0.25, 0.25)

    public static func defaults(name: String, materialClass c: MaterialClass) -> Defaults {
        let n = name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
        var cut: String?
        var surface: String?
        switch c {
        case .concrete:
            cut = has("precast") ? "Concrete - Precast" : has("lightweight", "screed", "mortar", "grout", "terrazzo") ? "Concrete - Lightweight" : "Concrete"
            if has("paving") { surface = "Paving 400 x 400" }
            if has("block", "masonry unit") { cut = "Masonry - Concrete Block"; surface = "Concrete Block - Running Bond" }
        case .masonry:
            if has("block", "cmu", "masonry unit", "aac", "concrete masonry") { cut = "Masonry - Concrete Block"; surface = "Concrete Block - Running Bond" }
            else if has("stone", "rubble") { cut = "Masonry - Stone"; surface = "Stone - Ashlar" }
            else if has("adobe", "rammed", "cob") { cut = "Earth" }
            else { cut = "Masonry - Brick"; surface = has("stack") ? "Brick - Stack Bond" : "Brick" }
            if has("paver", "paving") { surface = "Paving - Herringbone 200 x 100" }
        case .metal:
            cut = has("aluminum", "aluminium") ? "Aluminum" : has("brass", "bronze", "copper") ? "Brass - Bronze" : has("lead", "zinc") ? "Lead - Zinc" : "Steel"
            if has("deck", "grating", "mesh") { cut = "Metal Deck - Grating" }
            if has("roof", "seam") { surface = "Roofing - Standing Seam 450" }
            else if has("panel", "cladding", "composite") { surface = "Metal Panel 900" }
        case .wood:
            if has("stud", "joist", "rafter", "framing", "lumber", "sawn", "timber") && !has("cladding", "floor", "deck") { cut = "Wood - Framing" }
            else if has("blocking", "batten", "furring") { cut = "Wood - Blocking" }
            else if has("plywood", "osb", "strand", "sheathing", "mdf", "fiberboard", "particle", "clt", "lvl", "glulam", "laminated") { cut = "Wood - Plywood" }
            else { cut = "Wood Grain" }
            if has("floor", "parquet", "plank") { surface = has("parquet") ? "Wood - Parquet 300" : "Wood - Plank 150" }
            else if has("cladding", "siding", "board") { surface = "Cladding - Board 150" }
            else if has("deck") { surface = "Wood - Plank 150" }
        case .glass:
            cut = "Glass"
            if has("curtain") { surface = "Glass - Curtain Wall 1500" }
        case .plaster:
            cut = has("acoustic", "ceiling tile") ? "Gypsum - Plaster" : "Gypsum - Plaster"
            if has("acoustic", "ceiling tile") { surface = "Ceiling 600 x 600" }
        case .insulation:
            cut = has("rigid", "xps", "eps", "pir", "polyiso", "foam", "board", "phenolic") ? "Insulation - Rigid" : "Insulation"
            if has("air") { cut = nil }
        case .stone:
            cut = has("marble", "slate", "granite", "polished", "quartz") ? "Marble - Slate" : "Masonry - Stone"
            if has("paving", "paver", "flag") { surface = "Paving 600 x 600" }
            else if has("tile") { surface = "Tile 300 x 600" }
            else if has("ashlar", "cladding", "veneer", "coursed") { surface = "Stone - Ashlar" }
        case .ceramic:
            cut = "Tile"
            if has("roof") { surface = "Roofing - Tile 300" }
            else if has("mosaic") { surface = "Tile 100 x 100" }
            else if has("porcelain", "large") { surface = "Tile 600 x 600" }
            else if has("tile") { surface = "Tile 300 x 300" }
        case .plastic:
            cut = has("membrane", "felt", "epdm", "tpo", "pvc roof", "vapor", "vapour", "damp", "barrier", "sheet") ? "Membrane" : "Plastic - Rubber"
            if has("panel", "cladding", "composite") { surface = "Cladding - Panel 1200 x 2400" }
        case .earth:
            cut = has("sand") ? "Sand" : has("gravel", "hardcore", "crushed", "aggregate", "ballast") ? "Gravel" : "Earth"
            if has("grass", "turf", "lawn") { surface = "Grass"; cut = "Earth" }
            else if has("gravel") { surface = "Gravel - Model" }
        case .paint, .generic:
            cut = c == .generic ? "Diagonal Up" : nil
        case .liquid:
            cut = "Water"
        case .gas:
            cut = nil
        }
        return Defaults(cut: cut, surface: surface, cutColor: ink)
    }

    /// Applies the defaults to a material, resolving pattern names through `patterns` (name → id).
    public static func apply(to m: inout MaterialData, name: String, patterns: [String: ElementID]) {
        let d = defaults(name: name, materialClass: m.materialClass)
        m.cutPatternID = d.cut.flatMap { patterns[$0] }
        m.cutPatternColor = d.cutColor
        m.surfacePatternID = d.surface.flatMap { patterns[$0] }
        m.surfacePatternColor = RGBColor(0.45, 0.45, 0.45)
    }

    /// Name → id of the model's fill patterns.
    public static func patternIndex(_ model: BIMModel) -> [String: ElementID] {
        var out: [String: ElementID] = [:]
        for p in model.elements(.fillPatterns) where out[p.name] == nil { out[p.name] = p.id }
        return out
    }
}
