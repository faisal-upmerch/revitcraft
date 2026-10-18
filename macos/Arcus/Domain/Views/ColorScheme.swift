import Foundation
import ArcusGeometry

// MARK: - Data

/// How a colour scheme assigns colours: one row per distinct value, or one row per numeric range.
public enum ColorFillMode: String, Codable, Sendable, CaseIterable {
    case byValue = "By Value"
    case byRange = "By Range"
}

/// One row of a colour scheme.
public struct ColorFillEntry: Hashable, Codable, Sendable {
    /// By value: the parameter value as displayed ("" = elements with no value). Unused by ranges.
    public var value: String
    /// By range: inclusive lower bound in internal units. The first row of a range scheme has no lower bound.
    public var lower: Double?
    public var color: RGBColor
    public var pattern: FillPatternKind
    /// Hidden rows are neither filled nor listed in legends.
    public var visible: Bool

    public init(value: String = "", lower: Double? = nil, color: RGBColor, pattern: FillPatternKind = .solid, visible: Bool = true) {
        self.value = value; self.lower = lower; self.color = color; self.pattern = pattern; self.visible = visible
    }
}

/// A colour fill scheme: rooms or areas coloured by a parameter (Department, Name, Area ranges…).
public struct ColorSchemeData: Hashable, Codable, Sendable {
    /// `.rooms` or `.areas`.
    public var category: Category
    /// Heading shown on colour fill legends.
    public var title: String
    public var parameter: ParameterID
    /// Parameter name and type captured when the scheme was defined (formatting and legends).
    public var parameterName: String
    public var parameterType: ParamType
    public var mode: ColorFillMode
    /// By value: rows in legend order. By range: rows sorted by `lower` (the first has no lower bound).
    public var entries: [ColorFillEntry]
    /// Areas: restrict the scheme to one area scheme (nil = any).
    public var areaSchemeID: ElementID?

    public init(category: Category = .rooms, title: String, parameter: ParameterID, parameterName: String, parameterType: ParamType = .text,
                mode: ColorFillMode = .byValue, entries: [ColorFillEntry] = [], areaSchemeID: ElementID? = nil) {
        self.category = category; self.title = title; self.parameter = parameter; self.parameterName = parameterName
        self.parameterType = parameterType; self.mode = mode; self.entries = entries; self.areaSchemeID = areaSchemeID
    }

    /// Default rooms scheme: colour by Department.
    public static let department = ColorSchemeData(category: .rooms, title: "Department Legend", parameter: ParameterID("room.department"),
                                                   parameterName: "Department")
}

/// A colour fill legend placed in a plan or section; it lists the rows of the view's colour scheme that are in use.
public struct ColorFillLegendData: Hashable, Codable, Sendable {
    /// Top-left corner in view coordinates.
    public var position: Vec2
    public init(position: Vec2) { self.position = position }
}

extension Element {
    public var colorScheme: ColorSchemeData? {
        get { if case .colorScheme(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .colorScheme(v) } }
    }
    public var colorFillLegend: ColorFillLegendData? {
        get { if case .colorFillLegend(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .colorFillLegend(v) } }
    }
}

// MARK: - Evaluation

/// Colour fill evaluation shared by plans, sections, legends and the scheme editor.
public enum ColorFill {
    /// Distinct, print-friendly fill colours used for new values.
    public static let palette: [RGBColor] = [
        RGBColor(hex: 0x8DB6E2), RGBColor(hex: 0xF2B880), RGBColor(hex: 0xA8D5A2), RGBColor(hex: 0xE89B9B),
        RGBColor(hex: 0xC3A8DD), RGBColor(hex: 0xF4E08A), RGBColor(hex: 0x8FD3CF), RGBColor(hex: 0xE3B5CF),
        RGBColor(hex: 0xB9C98A), RGBColor(hex: 0xD6B38E), RGBColor(hex: 0x9EC1C9), RGBColor(hex: 0xF0C6A0),
        RGBColor(hex: 0xB0B7E8), RGBColor(hex: 0xD9D2A4), RGBColor(hex: 0xA3D9B8), RGBColor(hex: 0xE6A8A0),
    ]

    /// The category a view's colour fill applies to: areas in area plans, rooms elsewhere.
    public static func category(for view: ViewData) -> Category { view.kind == .areaPlan ? .areas : .rooms }

    /// The colour scheme assigned to a view, when it matches what the view shows.
    public static func scheme(for view: Element, _ model: BIMModel) -> ColorSchemeData? {
        guard let vd = view.view, let s = model[vd.colorSchemeID]?.colorScheme else { return nil }
        guard vd.kind.isPlan || vd.kind == .section || vd.kind == .detail, s.category == category(for: vd) else { return nil }
        if vd.kind.isVerticalCut, s.category != .rooms { return nil }
        return s
    }

    /// The display label of an element's value (by-value schemes).
    public static func valueLabel(of e: Element, _ s: ColorSchemeData, _ model: BIMModel) -> String {
        Parameters.format(Parameters.value(s.parameter, of: e, model), type: s.parameterType, model: model)
    }

    /// Numeric value for range schemes.
    public static func numericValue(of e: Element, _ s: ColorSchemeData, _ model: BIMModel) -> Double? {
        guard let v = Parameters.value(s.parameter, of: e, model) else { return nil }
        if let d = v.doubleValue { return d }
        if let i = v.intValue { return Double(i) }
        return nil
    }

    /// Row index for an element in a (completed) scheme.
    public static func entryIndex(for e: Element, in s: ColorSchemeData, _ model: BIMModel) -> Int? {
        switch s.mode {
        case .byValue:
            let label = valueLabel(of: e, s, model)
            return s.entries.firstIndex { $0.value == label }
        case .byRange:
            guard let v = numericValue(of: e, s, model), !s.entries.isEmpty else { return nil }
            var index = 0
            for (i, row) in s.entries.enumerated() {
                if let lo = row.lower, v >= lo - 1e-9 { index = i } else if row.lower != nil { break }
            }
            return index
        }
    }

    /// Adds rows (with automatic colours) for values in use that a by-value scheme does not list yet.
    /// Colours come from a stable hash of the value, skipping colours already taken where possible.
    public static func completed(_ s: ColorSchemeData, values: some Sequence<String>) -> ColorSchemeData {
        guard s.mode == .byValue else { return s }
        var out = s
        var listed = Set(s.entries.map(\.value))
        var used = Set(s.entries.map(\.color))
        let missing = Set(values).subtracting(listed).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for v in missing {
            out.entries.append(ColorFillEntry(value: v, color: autoColor(for: v, avoiding: used)))
            used.insert(out.entries.last!.color)
            listed.insert(v)
        }
        return out
    }

    /// A palette colour for a value: stable across sessions (FNV-1a hash), avoiding `used` when a free colour remains.
    public static func autoColor(for value: String, avoiding used: Set<RGBColor>) -> RGBColor {
        var h: UInt64 = 0xcbf29ce484222325
        for b in value.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        let start = Int(h % UInt64(palette.count))
        for k in 0..<palette.count {
            let c = palette[(start + k) % palette.count]
            if !used.contains(c) { return c }
        }
        // Every palette colour is taken: derive a lighter or darker variant so rows stay distinguishable.
        let base = palette[start]
        let t = Double((h >> 8) % 5 + 1) / 10
        return (h >> 16) % 2 == 0 ? base.mixed(with: .white, amount: t) : base.mixed(with: .black, amount: t * 0.6)
    }

    /// Display label for a row ("Office", "(none)", "Less than 20 m²", "20 m² – 40 m²", "40 m² or more").
    public static func label(_ s: ColorSchemeData, row i: Int, _ model: BIMModel) -> String {
        guard s.entries.indices.contains(i) else { return "" }
        switch s.mode {
        case .byValue:
            return s.entries[i].value.isEmpty ? "(none)" : s.entries[i].value
        case .byRange:
            func fmt(_ d: Double) -> String { Parameters.format(.double(d), type: s.parameterType, model: model) }
            let lo = s.entries[i].lower
            let hi = s.entries.indices.contains(i + 1) ? s.entries[i + 1].lower : nil
            switch (lo, hi) {
            case (nil, let h?): return "Less than \(fmt(h))"
            case (let l?, let h?): return "\(fmt(l)) – \(fmt(h))"
            case (let l?, nil): return "\(fmt(l)) or more"
            case (nil, nil): return "All values"
            }
        }
    }

    /// Evenly spaced range rows covering `values` (five bands with rounded bounds), for a new range scheme.
    public static func defaultRanges(for values: [Double]) -> [ColorFillEntry] {
        let finite = values.filter(\.isFinite)
        let lo = finite.min() ?? 0, hi = finite.max() ?? 100
        let span = max(hi - lo, 1e-6)
        let raw = span / 5
        let mag = pow(10, floor(log10(raw)))
        let step = [1.0, 2, 2.5, 5, 10].map { $0 * mag }.first { $0 >= raw } ?? raw
        let first = (lo / step).rounded(.down) * step + step
        var rows = [ColorFillEntry(lower: nil, color: palette[0])]
        var b = first
        var k = 1
        while b <= hi + 1e-9 && k < 12 {
            rows.append(ColorFillEntry(lower: b, color: palette[k % palette.count]))
            b += step; k += 1
        }
        if rows.count == 1 { rows.append(ColorFillEntry(lower: first, color: palette[1])) }
        return rows
    }

    /// Elements of the scheme's category that a plan view colours: bounded rooms/areas on the view's level
    /// (areas limited to the view's and the scheme's area scheme).
    public static func planMembers(_ s: ColorSchemeData, view: Element, _ model: BIMModel) -> [(Element, Profile2)] {
        guard let vd = view.view, let level = view.levelID else { return [] }
        let bounds = RoomBoundaryCache.shared.boundaries(level: level, model)
        var out: [(Element, Profile2)] = []
        for r in model.elements(s.category) where r.levelID == level {
            if s.category == .areas {
                if let a = vd.areaSchemeID, r.room?.areaSchemeID != a { continue }
                if let a = s.areaSchemeID, r.room?.areaSchemeID != a { continue }
            } else if r.room?.areaSchemeID != nil { continue }
            guard let b = bounds[r.id], b.state == .bounded, let p = b.profile else { continue }
            out.append((r, p))
        }
        return out
    }

    /// Rooms cut by a section plane: the (u, z) rectangles where the plane passes through each room.
    static func sectionMembers(_ s: ColorSchemeData, view: ViewData, frame fr: VerticalGraphics.Frame, _ model: BIMModel) -> [(Element, [Polygon2])] {
        guard s.category == .rooms else { return [] }
        var out: [(Element, [Polygon2])] = []
        let line = Segment2(fr.origin.xy - fr.right * 10_000, fr.origin.xy + fr.right * 10_000)
        for r in model.elements(.rooms) where r.room?.areaSchemeID == nil {
            let b = RoomGeometry.boundary(r, model)
            guard b.state == .bounded, let prof = b.profile else { continue }
            var ts: [Double] = []
            for loop in prof.loops {
                for edge in loop.edges {
                    guard !edge.isParallel(to: line), let hit = edge.lineIntersection(line), hit.t >= 0, hit.t < 1 else { continue }
                    ts.append(fr.u(hit.point))
                }
            }
            ts.sort()
            guard ts.count >= 2 else { continue }
            let z0 = model.baseElevation(of: r)
            let z1 = z0 + RoomGeometry.height(r, model)
            guard z1 > z0 + 1e-6 else { continue }
            var rects: [Polygon2] = []
            var i = 0
            while i + 1 < ts.count {
                let u0 = ts[i], u1 = ts[i + 1]
                let mid = fr.origin.xy + fr.right * ((u0 + u1) / 2)
                if u1 - u0 > 1e-6, prof.contains(mid) {
                    var rect = Rect2(min: Vec2(u0, z0), max: Vec2(u1, z1))
                    if let crop = view.cropRegion, view.cropActive {
                        guard rect.intersects(crop) else { i += 1; continue }
                        rect = Rect2(min: Vec2(max(rect.min.x, crop.min.x), max(rect.min.y, crop.min.y)),
                                     max: Vec2(min(rect.max.x, crop.max.x), min(rect.max.y, crop.max.y)))
                    }
                    rects.append(.rectangle(rect))
                }
                i += 1
            }
            if !rects.isEmpty { out.append((r, rects)) }
        }
        return out
    }

    /// The scheme completed with the values a view shows, and the rows those values use (legend order).
    public static func legendRows(view: Element, _ model: BIMModel) -> (scheme: ColorSchemeData, rows: [Int])? {
        guard let s = scheme(for: view, model), let vd = view.view else { return nil }
        let members: [Element]
        if vd.kind.isPlan {
            members = planMembers(s, view: view, model).map(\.0)
        } else if let fr = VerticalGraphics.frame(vd) {
            members = sectionMembers(s, view: vd, frame: fr, model).map(\.0)
        } else {
            members = []
        }
        let full = completed(s, values: s.mode == .byValue ? members.map { valueLabel(of: $0, s, model) } : [])
        var used = Set<Int>()
        for m in members { if let i = entryIndex(for: m, in: full, model), full.entries[i].visible { used.insert(i) } }
        return (full, used.sorted())
    }

    /// The scheme completed with every value in use anywhere in the project (what the scheme editor stores).
    public static func completedWithProjectValues(_ s: ColorSchemeData, _ model: BIMModel) -> ColorSchemeData {
        guard s.mode == .byValue else { return s }
        let members = model.elements(s.category).filter { s.category == .rooms ? $0.room?.areaSchemeID == nil : (s.areaSchemeID == nil || $0.room?.areaSchemeID == s.areaSchemeID) }
        return completed(s, values: members.map { valueLabel(of: $0, s, model) })
    }

    /// Values of the scheme's parameter in use in the project, with how many elements use each.
    public static func valuesInUse(_ s: ColorSchemeData, _ model: BIMModel) -> [String: Int] {
        var out: [String: Int] = [:]
        for e in model.elements(s.category) {
            if s.category == .rooms, e.room?.areaSchemeID != nil { continue }
            if s.category == .areas, let a = s.areaSchemeID, e.room?.areaSchemeID != a { continue }
            out[valueLabel(of: e, s, model), default: 0] += 1
        }
        return out
    }

    static func gfill(_ row: ColorFillEntry, halftone: Bool) -> GFill {
        GFill(pattern: row.pattern, color: row.color, background: row.pattern == .solid ? nil : .white, transparency: 0, halftone: halftone)
    }
}

// MARK: - Plan and section fills

extension PlanGraphics {
    /// Colour fill regions for the view's colour scheme (drawn behind model lines; not selectable).
    func colorFills() -> [GItem] {
        guard let s = ColorFill.scheme(for: builder.view, model) else { return [] }
        let members = ColorFill.planMembers(s, view: builder.view, model)
        let full = ColorFill.completed(s, values: s.mode == .byValue ? members.map { ColorFill.valueLabel(of: $0.0, s, model) } : [])
        var items: [GItem] = []
        for (r, prof) in members {
            guard let o = builder.resolver.resolve(r), let i = ColorFill.entryIndex(for: r, in: full, model), full.entries[i].visible else { continue }
            items.append(GItem(elementID: nil, category: s.category, layer: .fills,
                               primitives: [.fill(prof.loops, ColorFill.gfill(full.entries[i], halftone: o.halftone ?? false))], selectable: false))
        }
        return items
    }
}

extension VerticalGraphics {
    /// Colour fill of rooms cut by a section, between each room's base and its upper limit.
    func colorFills(_ fr: Frame) -> [GItem] {
        guard data.kind != .elevation, let s = ColorFill.scheme(for: builder.view, model) else { return [] }
        let members = ColorFill.sectionMembers(s, view: data, frame: fr, model)
        let full = ColorFill.completed(s, values: s.mode == .byValue ? members.map { ColorFill.valueLabel(of: $0.0, s, model) } : [])
        var items: [GItem] = []
        for (r, rects) in members {
            guard let o = builder.resolver.resolve(r), let i = ColorFill.entryIndex(for: r, in: full, model), full.entries[i].visible else { continue }
            items.append(GItem(elementID: nil, category: .rooms, layer: .fills,
                               primitives: [.fill(rects, ColorFill.gfill(full.entries[i], halftone: o.halftone ?? false))], selectable: false))
        }
        return items
    }
}

// MARK: - Legend

extension AnnotationRenderer {
    /// A colour fill legend: title, then one swatch and label per row in use in the legend's view.
    static func colorFillLegend(_ e: Element, _ l: ColorFillLegendData, model: BIMModel, scale s: Double, st: GStroke) -> GItem {
        let textH = 0.0025, titleH = 0.003
        let swatch = Vec2(0.009, 0.0045) * s
        let pitch = 0.0065 * s
        var prims: [GPrimitive] = []
        var y = l.position.y
        var width = 0.0
        let view = model[e.ownerViewID]
        let rows = view.flatMap { ColorFill.legendRows(view: $0, model) }
        let title = rows?.scheme.title ?? "Color Fill Legend"
        prims.append(.text(GText(position: Vec2(l.position.x, y), height: titleH, string: title, verticalAnchor: 1, bold: true, color: st.color, halftone: st.halftone)))
        width = Double(title.count) * titleH * 0.62 * s
        y -= titleH * s + 0.003 * s
        if let (scheme, used) = rows, !used.isEmpty {
            for i in used {
                let row = scheme.entries[i]
                let r = Rect2(min: Vec2(l.position.x, y - swatch.y), max: Vec2(l.position.x + swatch.x, y))
                prims.append(.fill([.rectangle(r)], ColorFill.gfill(row, halftone: st.halftone)))
                prims.append(.polyline(r.corners, closed: true, GStroke(weight: 1, color: st.color, halftone: st.halftone)))
                let text = ColorFill.label(scheme, row: i, model)
                prims.append(.text(GText(position: Vec2(r.max.x + 0.003 * s, y - swatch.y / 2), height: textH, string: text, verticalAnchor: 0.5,
                                         color: st.color, halftone: st.halftone)))
                width = max(width, swatch.x + 0.003 * s + Double(text.count) * textH * 0.6 * s)
                y -= pitch
            }
        } else {
            let text = rows == nil ? "No color scheme is assigned to this view." : "No colored elements in this view."
            prims.append(.text(GText(position: Vec2(l.position.x, y), height: textH, string: text, verticalAnchor: 1, color: st.color, halftone: st.halftone)))
            width = max(width, Double(text.count) * textH * 0.6 * s)
            y -= pitch
        }
        let hit = Rect2(min: Vec2(l.position.x, y + pitch - swatch.y - 0.001 * s), max: Vec2(l.position.x + width, l.position.y))
        return GItem(elementID: e.id, category: .colorFillLegends, layer: .annotation, primitives: prims, hitPolygons: [.rectangle(hit)])
    }
}
