import Foundation
import ArcusGeometry

// BL-VG: project graphics control — Object Styles, subcategories, filter rule sets, view templates, warnings
// reports and element id lists.

// MARK: - Object Styles

/// A project's change to the built-in object style of a category or subcategory. nil fields keep the default.
public struct ObjectStyleOverride: Hashable, Codable, Sendable {
    public var projectionWeight: Int?
    public var cutWeight: Int?
    public var color: RGBColor?
    public var pattern: LinePatternKind?
    /// Material used for cut patterns and shading when an element has none of its own.
    public var materialID: ElementID?
    public init(projectionWeight: Int? = nil, cutWeight: Int? = nil, color: RGBColor? = nil, pattern: LinePatternKind? = nil, materialID: ElementID? = nil) {
        self.projectionWeight = projectionWeight; self.cutWeight = cutWeight; self.color = color; self.pattern = pattern; self.materialID = materialID
    }
    public var isEmpty: Bool { self == ObjectStyleOverride() }
}

/// Project Object Styles: overrides keyed by `Subcategories.key` (a category, or "category/Subcategory").
public struct ObjectStyleSettings: Hashable, Codable, Sendable {
    public var styles: [String: ObjectStyleOverride]
    public init(styles: [String: ObjectStyleOverride] = [:]) { self.styles = styles }

    public subscript(_ c: Category, _ subcategory: String?) -> ObjectStyleOverride? {
        get { styles[Subcategories.key(c, subcategory)] }
        set {
            let k = Subcategories.key(c, subcategory)
            if let v = newValue, !v.isEmpty { styles[k] = v } else { styles[k] = nil }
        }
    }
}

extension ObjectStyles {
    /// The style every view starts from before any view, filter or element override: the built-in default, then the
    /// project's category override, then its subcategory override.
    public static func effective(_ c: Category, subcategory: String? = nil, _ settings: ObjectStyleSettings?) -> ObjectStyle {
        var s = style(c)
        guard let settings else { return s }
        for o in [settings[c, nil], subcategory.flatMap { settings[c, $0] }].compactMap({ $0 }) {
            if let w = o.projectionWeight { s.projectionWeight = w }
            if let w = o.cutWeight { s.cutWeight = w }
            if let col = o.color { s.color = col }
            if let p = o.pattern { s.pattern = p }
        }
        return s
    }

    public static func effective(_ c: Category, subcategory: String? = nil, model: BIMModel) -> ObjectStyle {
        effective(c, subcategory: subcategory, model.projectInfo.objectStyles)
    }

    /// Object-style material of a category (subcategory first), if the project set one.
    public static func material(_ c: Category, subcategory: String? = nil, _ settings: ObjectStyleSettings?) -> ElementID? {
        subcategory.flatMap { settings?[c, $0]?.materialID } ?? settings?[c, nil]?.materialID
    }
}

// MARK: - Subcategories

/// Subcategories shown under a category in Visibility/Graphics and Object Styles. They are the family subcategories
/// that plan symbols of doors, windows and components are drawn with, so hiding or overriding one changes the drawing.
public enum Subcategories {
    public static func key(_ c: Category, _ subcategory: String?) -> String {
        subcategory.map { "\(c.rawValue)/\($0)" } ?? c.rawValue
    }

    public static func names(for c: Category) -> [String] {
        switch c {
        case .doors: [FamilySubcategory.frame, .panel, .glass, .opening, .swing, .elevationSwing, .sill, .hidden].map(\.rawValue)
        case .windows: [FamilySubcategory.frame, .glass, .opening, .sill, .panel, .elevationSwing, .hidden].map(\.rawValue)
        case .furniture, .casework, .genericModels, .plumbingFixtures, .specialtyEquipment, .lightingFixtures, .electricalFixtures,
             .mechanicalEquipment, .columns, .planting, .entourage, .site, .parking:
            [FamilySubcategory.hidden.rawValue]
        case .stairs: StairSubcategory.stairs // STAIR: Outlines, Nosing Lines, Cut Marks, Stair Path, Supports and their <Above>
        case .railings: StairSubcategory.railings // STAIR: Top Rails, Balusters and their <Above>
        default: []
        }
    }
}

// MARK: - Filters

/// A nested set of filter rules with its own AND/OR.
public struct FilterRuleGroup: Hashable, Codable, Sendable {
    public var rules: [FilterRule]
    public var matchAll: Bool
    public init(rules: [FilterRule], matchAll: Bool = true) { self.rules = rules; self.matchAll = matchAll }
}

extension FilterEvaluation {
    /// Whether an element passes a filter: its category is one of the filter's and its rules (and rule sets) match,
    /// combined by the filter's AND/OR. A filter without rules matches every element of its categories.
    public static func matches(_ f: ViewFilterData, _ e: Element, _ model: BIMModel) -> Bool {
        func rule(_ r: FilterRule) -> Bool { evaluate(r.op, lhs: Parameters.value(r.parameter, of: e, model), rhs: r.value) }
        var results = f.rules.map(rule)
        for g in f.groups ?? [] where !g.rules.isEmpty {
            results.append(g.matchAll ? g.rules.allSatisfy(rule) : g.rules.contains(where: rule))
        }
        guard !results.isEmpty else { return true }
        return f.matchAll ? !results.contains(false) : results.contains(true)
    }

    /// Parameters a filter on these categories can test: those common to the categories' elements in the model
    /// (a category with no elements yet doesn't narrow the list), plus Mark and Comments.
    public static func parameters(for categories: [Category], _ model: BIMModel) -> [(id: ParameterID, name: String, type: ParamType)] {
        var common: [ParameterID: (String, ParamType)]?
        for c in categories {
            let sample = model.elements(c).prefix(3)
            guard !sample.isEmpty else { continue }
            var here: [ParameterID: (String, ParamType)] = [:]
            for e in sample { for p in Parameters.allEntries(e, model) { here[p.id] = (p.name, p.type) } }
            common = common.map { $0.filter { here[$0.key] != nil } } ?? here
        }
        var out = common ?? [:]
        out[.mark] = out[.mark] ?? ("Mark", .text)
        out[ParameterID("comments")] = out[ParameterID("comments")] ?? ("Comments", .text)
        return out.map { (id: $0.key, name: $0.value.0, type: $0.value.1) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - View templates

public enum ViewTemplates {
    /// Settings a view template can control.
    public enum Setting: String, CaseIterable, Sendable {
        case scale = "View Scale", detailLevel = "Detail Level", visualStyle = "Visual Style", discipline = "Discipline"
        case viewRange = "View Range", phaseFilter = "Phase Filter", visibility = "V/G Overrides"
    }

    /// A template controlling every applicable setting of a view (Create Template from Current View).
    public static func make(from v: ViewData) -> ViewTemplateData {
        var t = ViewTemplateData(appliesTo: v.kind)
        t.scale = v.scale; t.detailLevel = v.detailLevel; t.visualStyle = v.visualStyle; t.discipline = v.discipline
        t.viewRange = v.kind.isPlan ? v.viewRange : nil
        t.phaseFilter = v.phaseFilter
        var vg = v.visibility
        vg.hiddenElements = []; vg.elementOverrides = [:]
        t.visibility = vg
        return t
    }

    /// Whether a template can be used by views of a kind (plan templates serve every plan kind).
    public static func compatible(_ t: ViewTemplateData, with kind: ViewKind) -> Bool {
        t.appliesTo == kind || (t.appliesTo.isPlan && kind.isPlan)
    }

    /// Copies the settings a template controls into a view (Apply Template Properties). Element-level hides and
    /// overrides stay with the view.
    public static func apply(_ t: ViewTemplateData, to v: inout ViewData) {
        if let s = t.scale { v.scale = s }
        if let s = t.detailLevel { v.detailLevel = s }
        if let s = t.visualStyle { v.visualStyle = s }
        if let s = t.discipline { v.discipline = s }
        if let s = t.viewRange, v.kind.isPlan { v.viewRange = s }
        if let s = t.phaseFilter { v.phaseFilter = s }
        if var vg = t.visibility {
            vg.hiddenElements = v.visibility.hiddenElements
            vg.elementOverrides = v.visibility.elementOverrides
            v.visibility = vg
        }
    }

    public static func controls(_ t: ViewTemplateData, _ s: Setting) -> Bool {
        switch s {
        case .scale: t.scale != nil
        case .detailLevel: t.detailLevel != nil
        case .visualStyle: t.visualStyle != nil
        case .discipline: t.discipline != nil
        case .viewRange: t.viewRange != nil
        case .phaseFilter: t.phaseFilter != nil
        case .visibility: t.visibility != nil
        }
    }

    /// Turns control of a setting on (taking the value from `source`) or off.
    public static func setControls(_ t: inout ViewTemplateData, _ s: Setting, _ on: Bool, source: ViewData) {
        switch s {
        case .scale: t.scale = on ? (t.scale ?? source.scale) : nil
        case .detailLevel: t.detailLevel = on ? (t.detailLevel ?? source.detailLevel) : nil
        case .visualStyle: t.visualStyle = on ? (t.visualStyle ?? source.visualStyle) : nil
        case .discipline: t.discipline = on ? (t.discipline ?? source.discipline) : nil
        case .viewRange: t.viewRange = on ? (t.viewRange ?? source.viewRange) : nil
        case .phaseFilter: t.phaseFilter = on ? (t.phaseFilter ?? source.phaseFilter) : nil
        case .visibility: t.visibility = on ? (t.visibility ?? make(from: source).visibility) : nil
        }
    }

    /// The template that controls a setting of a view, if any.
    public static func controllingTemplate(_ view: Element, _ s: Setting, _ model: BIMModel) -> Element? {
        guard let t = model[view.view?.templateID], let td = t.viewTemplate, controls(td, s) else { return nil }
        return t
    }

    public static func views(using template: ElementID, _ model: BIMModel) -> [Element] {
        model.views.filter { $0.view?.templateID == template }
    }

    /// Pushes a template's controlled settings into every view that uses it (after the template changed).
    public static func propagate(_ template: ElementID, in tx: TransactionContext) {
        guard let td = tx.model[template]?.viewTemplate else { return }
        for v in views(using: template, tx.model) { tx.update(v.id) { e in if var d = e.view { apply(td, to: &d); e.view = d } } }
    }

    /// Assigns (or removes, with nil) a view's template, copying the controlled settings into the view.
    public static func assign(_ template: ElementID?, to view: ElementID, in tx: TransactionContext) throws(TransactionError) {
        guard var d = tx.model[view]?.view else { return }
        if let template {
            guard let td = tx.model[template]?.viewTemplate else { throw TransactionError("Not a view template.") }
            guard compatible(td, with: d.kind) else { throw TransactionError("This template is for \(td.appliesTo.rawValue) views.") }
            apply(td, to: &d)
        }
        d.templateID = template
        tx.update(view) { $0.view = d }
    }
}

// MARK: - Warnings

/// Warnings with the same code, as the Warnings dialog lists them (expandable to each warning and its elements).
public struct WarningGroup: Identifiable, Hashable, Sendable {
    public var id: String { code }
    public var code: String
    public var title: String
    public var severity: ModelWarning.Severity
    public var warnings: [ModelWarning]
}

public enum WarningsReport {
    static let titles: [String: String] = [
        "mark.duplicate": "Elements have duplicate Mark values.",
        "room.unbounded": "Room is not in a properly enclosed region.",
        "room.redundant": "Multiple rooms are in the same enclosed region.",
        "room.unplaced": "Room is not placed.",
        "host.orphan": "Door or window has no host.",
        "type.missing": "Element references a missing type.",
        "level.missing": "Element references a missing level.",
        "material.missing": "Type uses a material that no longer exists.",
        "sketch.invalid": "Sketch boundary is invalid.",
        "wall.overlap": "Walls overlap.",
        "extents.far": "Element is far from the internal origin.",
    ]

    /// Groups warnings by code, errors first, then by title.
    public static func groups(_ warnings: [ModelWarning]) -> [WarningGroup] {
        let byCode = Dictionary(grouping: warnings, by: \.code)
        return byCode.map { code, ws in
            WarningGroup(code: code, title: titles[code] ?? ws[0].message, severity: ws.map(\.severity).max() ?? .info,
                         warnings: ws.sorted { $0.message.localizedStandardCompare($1.message) == .orderedAscending })
        }
        .sorted { ($0.severity, $1.title) > ($1.severity, $0.title) }
    }

    /// "Walls : Basic Wall : Generic - 200mm : #123".
    public static func describe(_ id: ElementID, _ model: BIMModel) -> String {
        guard let e = model[id] else { return "Deleted element : \(id)" }
        var parts = [e.category.displayName]
        if let t = model.type(of: e) {
            if let f = t.typeData?.familyName, !f.isEmpty { parts.append(f) }
            parts.append(t.name)
        } else if !e.name.isEmpty {
            parts.append(e.name)
        }
        parts.append(id.description)
        return parts.joined(separator: " : ")
    }

    /// Self-contained HTML report (no scripts, no external resources).
    public static func html(_ warnings: [ModelWarning], _ model: BIMModel, projectName: String, date: Date = Date()) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        var out = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(esc(projectName)) Warnings</title>"
        out += "<style>body{font:13px -apple-system,Helvetica,sans-serif;margin:24px}table{border-collapse:collapse;width:100%}"
        out += "td,th{border:1px solid #bbb;padding:4px 8px;text-align:left;vertical-align:top}th{background:#eee}</style></head><body>"
        out += "<h1>Warnings: \(esc(projectName))</h1><p>\(warnings.count) warning(s), \(esc(f.string(from: date)))</p>"
        out += "<table><tr><th>Severity</th><th>Message</th><th>Elements</th></tr>"
        for g in groups(warnings) {
            for w in g.warnings {
                out += "<tr><td>\(w.severity.rawValue.capitalized)</td><td>\(esc(w.message))</td><td>"
                out += w.elements.map { esc(describe($0, model)) }.joined(separator: "<br>") + "</td></tr>"
            }
        }
        return out + "</table></body></html>"
    }
}

// MARK: - Element ids

/// Element ids as users type and copy them ("12; 15; #20").
public enum ElementIDList {
    /// Parses ids separated by semicolons, commas or spaces (a leading # is allowed). Returns the ids in order
    /// (duplicates dropped) and the tokens that aren't ids.
    public static func parse(_ text: String) -> (ids: [ElementID], invalid: [String]) {
        var ids: [ElementID] = [], invalid: [String] = [], seen = Set<UInt64>()
        for token in text.split(whereSeparator: { $0 == ";" || $0 == "," || $0.isWhitespace }) {
            let t = token.hasPrefix("#") ? token.dropFirst() : token[...]
            if let v = UInt64(t), v > 0 { if seen.insert(v).inserted { ids.append(ElementID(v)) } } else { invalid.append(String(token)) }
        }
        return (ids, invalid)
    }

    public static func format(_ ids: [ElementID]) -> String { ids.sorted().map { String($0.raw) }.joined(separator: "; ") }
}
