import Foundation
import ArcusGeometry
import ArcusCalc

// FM3: the Project Browser of a Furniture document (Docs/FurnitureMode.md §3, "Mode in the shell"): Views (Floor
// Plans, Elevations, Sections, 3D Views, Details), Sheets, Schedules, Nesting, Families, Parts and Parameters and Types.

public enum FurnitureBrowserTree {
    /// Node id prefixes of the Parameters and Types rows (the shell opens Family Types or switches type from them).
    public static let typePrefix = "furniture.type."
    public static let parameterPrefix = "furniture.param."

    /// The view folders a Furniture document lists, in order.
    static let viewKinds: [(ViewKind, String)] = [(.floorPlan, "Floor Plans"), (.elevation, "Elevations"), (.section, "Sections"),
                                                  (.threeD, "3D Views"), (.detail, "Details"), (.drafting, "Drafting Views")]

    /// The Furniture tree made from the project tree of the same model (views, sheets, schedules and families are the
    /// project's nodes; legends, groups and links are left out).
    public static func adapt(_ project: [BrowserNode], _ m: BIMModel, filter: String) -> [BrowserNode] {
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        func matches(_ s: String) -> Bool { f.isEmpty || s.lowercased().contains(f) }
        func node(_ id: String) -> BrowserNode? { project.first { $0.id == id } }

        var out: [BrowserNode] = []
        if var views = node("views") {
            let byKind = Dictionary(uniqueKeysWithValues: (views.children ?? []).map { ($0.id, $0) })
            views.children = viewKinds.compactMap { kind, title in
                guard var folder = byKind["views.\(kind.navigatorGroup)"] else { return nil }
                folder.title = title
                return folder
            }
            views.title = "Views"
            out.append(views)
        }
        if var sheets = node("sheets") { sheets.title = "Sheets"; out.append(sheets) }
        if var schedules = node("schedules") { schedules.title = "Schedules"; out.append(schedules) }
        // FM7 nesting views list here.
        let nesting = FurnitureNestingViews.views(m).filter { matches($0.name) }.map { v in
            BrowserNode(id: ProjectBrowserTree.viewNodeID(v.id), title: v.name, kind: .view, elementID: v.id, symbol: ViewKind.nesting.symbolName,
                        subtitle: m.sheet(containing: v.id).flatMap { $0.sheet?.number }.map { "on \($0)" } ?? "")
        }
        out.append(BrowserNode(id: "nesting", title: "Nesting", kind: .folder, symbol: "square.grid.3x3.square", children: nesting))
        if var families = node("families") {
            // The title blocks and tags every document carries stay out of the way at the end.
            let kids = families.children ?? []
            families.children = kids.filter { !annotationCategories.contains($0.category ?? .genericModels) }
                + kids.filter { annotationCategories.contains($0.category ?? .genericModels) }
            out.append(families)
        }
        // FM4 parts by type list here.
        out.append(BrowserNode(id: "parts", title: "Parts", kind: .folder, symbol: "square.stack.3d.up", children: []))
        if let s = m.furnitureSetup { out.append(parametersNode(s, m, matches: matches)) }
        return out
    }

    static let annotationCategories: Set<Category> = [.titleBlocks, .tags, .genericAnnotations, .detailComponents]

    /// Parameters and Types ▸ Types (the current one marked) and Parameters (with their values).
    static func parametersNode(_ s: FurnitureSetupData, _ m: BIMModel, matches: (String) -> Bool) -> BrowserNode {
        let types = s.family.types.filter { matches($0.name) }.map { t in
            BrowserNode(id: typePrefix + t.name, title: t.name, kind: .folder, symbol: t.name == s.currentType ? "checkmark.circle.fill" : "circle",
                        subtitle: t.name == s.currentType ? "Current" : "", familyName: s.name, category: s.category.category)
        }
        let values = FamilyEvaluator.parameterValues(s.family, typeName: s.currentType, units: m.units).values
        let params = s.family.parameters.filter { matches($0.name) }.sorted { ($0.group, $0.name) < ($1.group, $1.name) }.map { p in
            BrowserNode(id: parameterPrefix + p.name, title: p.name, kind: .folder, symbol: p.formula == nil ? "slider.horizontal.3" : "function",
                        subtitle: values[p.name].map { display($0, p, m) } ?? "")
        }
        return BrowserNode(id: "furniture.parameters", title: "Parameters and Types", kind: .folder, symbol: "tablecells", children: [
            BrowserNode(id: "furniture.types", title: "Types", kind: .folder, symbol: "folder", children: types),
            BrowserNode(id: "furniture.paramlist", title: "Parameters", kind: .folder, symbol: "folder", children: params),
        ])
    }

    /// A parameter value as the browser shows it (lengths in feet and inches, materials by name).
    static func display(_ v: FormulaValue, _ p: FamilyParameter, _ m: BIMModel) -> String {
        switch v {
        case .quantity(let d, _):
            if case .elementRef = p.type { return m[ElementID(UInt64(max(0, d.rounded())))]?.name ?? "" }
            return Parameters.format(.double(d), type: p.type, model: m)
        case .bool(let b): return b ? "Yes" : "No"
        case .text(let t): return t
        }
    }
}
