import Foundation
import ArcusGeometry

/// Phase status of an element relative to a view's phase.
public enum PhaseStatus: Sendable, Hashable { case new, existing, demolished, future, none }

/// Session-only display modifiers (not stored in the model and not undoable): temporary hide/isolate, reveal hidden.
public struct TemporaryVisibility: Sendable, Hashable {
    public var hiddenElements: Set<ElementID> = []
    public var hiddenCategories: Set<Category> = []
    public var isolatedElements: Set<ElementID>? = nil
    public var isolatedCategories: Set<Category>? = nil
    public var revealHidden: Bool = false
    /// Temporary View Properties: a view template applied for this session only (overrides the view's own template).
    public var temporaryTemplateID: ElementID? = nil // BL-VG
    /// Reveal Constraints: locked dimensions, alignments and EQ constraints drawn over the view.
    public var revealConstraints: Bool = false // BL-VG
    public init() {}
    public var isActive: Bool { !hiddenElements.isEmpty || !hiddenCategories.isEmpty || isolatedElements != nil || isolatedCategories != nil }
}

/// Resolves effective visibility and graphic overrides for elements in a view (template → view → filters → element).
public struct VisibilityResolver: Sendable {
    public let model: BIMModel
    public let view: Element
    public let data: ViewData
    public let vg: VisibilityGraphics
    public let temp: TemporaryVisibility
    let phaseOrder: Int?
    let previousPhaseOrder: Int?
    let filters: [(ViewFilterData, AppliedFilter)]

    public init(model: BIMModel, view: Element, temporary: TemporaryVisibility = TemporaryVisibility()) {
        self.model = model
        self.view = view
        var d = view.view ?? ViewData(kind: .drafting)
        var vg = d.visibility
        if let t = temporary.temporaryTemplateID ?? d.templateID, let td = model[t]?.viewTemplate { // BL-VG: temporary view properties
            if let s = td.scale { d.scale = s }
            if let s = td.detailLevel { d.detailLevel = s }
            if let s = td.visualStyle { d.visualStyle = s }
            if let s = td.discipline { d.discipline = s }
            if let s = td.viewRange, d.kind.isPlan { d.viewRange = s }
            if let s = td.phaseFilter { d.phaseFilter = s }
            if let tv = td.visibility {
                // Template controls V/G; element-level hides/overrides stay with the view.
                var merged = tv
                merged.hiddenElements = vg.hiddenElements
                merged.elementOverrides = vg.elementOverrides
                merged.hiddenLinkLayers = vg.hiddenLinkLayers.merging(tv.hiddenLinkLayers) { $0.union($1) }
                vg = merged
            }
        }
        ScopeBoxes.applyViewCrop(&d, model) // WP6a: plan views follow their scope box
        self.data = d
        self.vg = vg
        self.temp = temporary
        let phases = model.phases
        let phaseID = d.phaseID ?? phases.last?.id
        let po = model.phaseOrder(phaseID)
        phaseOrder = po
        previousPhaseOrder = po.flatMap { p in phases.compactMap(\.phase?.order).filter { $0 < p }.max() }
        filters = vg.filters.compactMap { af in model[af.filterID]?.viewFilter.map { ($0, af) } }
    }

    public func phaseStatus(_ e: Element) -> PhaseStatus {
        guard let viewPhase = phaseOrder else { return .none }
        let created = model.phaseOrder(e.phaseCreated) ?? Int.min
        let demolished = model.phaseOrder(e.phaseDemolished)
        if created > viewPhase { return .future }
        if let d = demolished {
            if d < viewPhase { return .future } // gone before this phase: treat as not present
            if d == viewPhase { return .demolished }
        }
        return created == viewPhase ? .new : .existing
    }

    /// Whether the element's design option is shown in this view.
    public func optionVisible(_ e: Element) -> Bool {
        guard let opt = e.designOptionID, let od = model[opt]?.designOption else { return true }
        if let chosen = data.designOptions[od.setName] { return chosen == opt }
        return od.isPrimary
    }

    /// Returns nil when hidden, else the override to apply (phase graphics included).
    public func resolve(_ e: Element) -> GraphicOverride? { resolve(e, subcategory: nil) }

    /// Like `resolve(_:)` for one subcategory of the element (nil when that subcategory is hidden). Precedence, lowest
    /// first: category (view or template) → subcategory → filters (in order) → element ("Override Graphics in View");
    /// object styles sit underneath all of them in `ViewGraphicsBuilder.stroke`.
    public func resolve(_ e: Element, subcategory: String?) -> GraphicOverride? { // BL-VG
        if temp.revealHidden {
            // Reveal hidden shows everything that exists in the model at this phase.
            return phaseStatus(e) == .future ? nil : GraphicOverride()
        }
        if let iso = temp.isolatedElements, !iso.contains(e.id), e.category.isModel || e.category.isAnnotation { return nil }
        if let iso = temp.isolatedCategories, !iso.contains(e.category), e.category.isModel || e.category.isAnnotation { return nil }
        if temp.hiddenElements.contains(e.id) || temp.hiddenCategories.contains(e.category) { return nil }
        if vg.hiddenElements.contains(e.id) || vg.hiddenCategories.contains(e.category) { return nil }
        if !optionVisible(e) { return nil }
        if data.discipline == .structural, e.category.isModel,
           ![.structuralColumns, .structuralFraming, .floors, .walls, .levels, .grids, .stairs].contains(e.category), !Category.f34Structural.contains(e.category) { // F34
            return nil
        }
        let subKey = subcategory.map { Subcategories.key(e.category, $0) } // BL-VG
        if let k = subKey, vg.hiddenSubcategories?.contains(k) == true { return nil }
        var o = vg.categoryOverrides[e.category] ?? GraphicOverride()
        if let k = subKey, let so = vg.subcategoryOverrides?[k] { o = o.merged(with: so) }
        for (f, af) in filters where f.categories.contains(e.category) && matches(f, e) {
            if !af.visible { return nil }
            o = o.merged(with: af.override)
        }
        if let eo = vg.elementOverrides[e.id] { o = o.merged(with: eo) }
        if e.category.isModel {
            switch (phaseStatus(e), data.phaseFilter) {
            case (.future, _): return nil
            case (_, .none): break
            case (.new, .showPreviousPhase): return nil
            case (.demolished, .showComplete), (.demolished, .showNew), (.demolished, .showPreviousAndNew): return nil
            case (.existing, .showNew): return nil
            case (.existing, .showDemoAndNew): return nil
            case (.existing, .showAll), (.existing, .showPreviousAndNew):
                if o.halftone == nil { o.halftone = true }
            case (.demolished, .showAll), (.demolished, .showDemoAndNew):
                if o.projectionLinePattern == nil { o.projectionLinePattern = .hidden }
                if o.cutLinePattern == nil { o.cutLinePattern = .hidden }
            default: break
            }
        }
        return o
    }

    public func matches(_ f: ViewFilterData, _ e: Element) -> Bool { FilterEvaluation.matches(f, e, model) } // BL-VG: rule sets

    /// Link layer visibility.
    public func linkLayerVisible(_ link: ElementID, layer: String) -> Bool {
        !(vg.hiddenLinkLayers[link]?.contains(layer) ?? false)
    }
}

public enum FilterEvaluation {
    public static func evaluate(_ op: FilterRule.Op, lhs: ParamValue?, rhs: ParamValue) -> Bool {
        switch op {
        case .hasValue:
            guard let l = lhs else { return false }
            if case .text(let s) = l { return !s.isEmpty }
            if case .ref(let r) = l { return r != nil }
            return true
        case .hasNoValue:
            guard let l = lhs else { return true }
            if case .text(let s) = l { return s.isEmpty }
            if case .ref(let r) = l { return r == nil }
            return false
        default: break
        }
        guard let l = lhs else { return op == .notEquals || op == .notContains }
        if let a = l.doubleValue, let b = rhs.doubleValue, !(l.textValue != nil && Double(l.textValue!) == nil) {
            let eq = abs(a - b) <= max(1e-9, abs(b) * 1e-9) + (l.textValue == nil ? Tolerance.length / 10 : 0)
            switch op {
            case .equals: return eq
            case .notEquals: return !eq
            case .greater: return a > b && !eq
            case .greaterOrEqual: return a > b || eq
            case .less: return a < b && !eq
            case .lessOrEqual: return a < b || eq
            default: break
            }
        }
        let a = (l.textValue ?? l.description).lowercased(), b = (rhs.textValue ?? rhs.description).lowercased()
        switch op {
        case .equals: return a == b
        case .notEquals: return a != b
        case .contains: return a.contains(b)
        case .notContains: return !a.contains(b)
        case .beginsWith: return a.hasPrefix(b)
        case .endsWith: return a.hasSuffix(b)
        case .greater: return a.localizedStandardCompare(b) == .orderedDescending
        case .greaterOrEqual: return a.localizedStandardCompare(b) != .orderedAscending
        case .less: return a.localizedStandardCompare(b) == .orderedAscending
        case .lessOrEqual: return a.localizedStandardCompare(b) != .orderedDescending
        default: return false
        }
    }
}
