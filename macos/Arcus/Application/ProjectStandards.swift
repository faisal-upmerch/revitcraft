import Foundation
import ArcusGeometry
import ArcusDomain

// F67: Manage ▸ Transfer Project Standards: copies chosen types and settings from another project. Items are matched
// by name (types by category, family and name); a match is either overwritten or kept ("New Only").

public enum ProjectStandards {
    /// One kind of standard the source project offers.
    public struct Item: Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var count: Int
    }

    public struct Report: Sendable, Equatable {
        public var added: [String] = []
        public var overwritten: [String] = []
        /// Items that already existed and were kept (New Only).
        public var kept: [String] = []
        public init() {}
        public var summary: String {
            var s = ["\(added.count) added, \(overwritten.count) overwritten."]
            if !kept.isEmpty { s.append("\(kept.count) already in this project and kept: \(kept.prefix(8).joined(separator: ", "))\(kept.count > 8 ? "…" : "").") }
            return s.joined(separator: " ")
        }
    }

    static let materials = "materials", lineStyles = "lineStyles", fillPatterns = "fillPatterns", objectStyles = "objectStyles"
    static let viewTemplates = "viewTemplates", filters = "filters", projectParameters = "projectParameters"

    /// System types (walls, floors, roofs…; not loadable family types, which Load Family brings in).
    static func systemTypes(_ m: BIMModel) -> [Element] { m.elements(.elementTypes).filter { $0.typeData != nil && $0.typeData?.familyID == nil } }

    /// The standards `src` has, in RevitCraft's order (alphabetical).
    public static func items(in src: BIMModel) -> [Item] {
        var out: [Item] = []
        let byCat = Dictionary(grouping: systemTypes(src), by: { $0.typeData!.instanceCategory })
        for (c, ts) in byCat { out.append(Item(id: "type." + c.rawValue, title: "\(c.singularName) Types", count: ts.count)) }
        func add(_ id: String, _ title: String, _ n: Int) { if n > 0 { out.append(Item(id: id, title: title, count: n)) } }
        add(materials, "Materials", src.elements(.materials).count)
        add(lineStyles, "Line Styles", src.elements(.lineStyles).count)
        add(fillPatterns, "Fill Patterns", src.elements(.fillPatterns).count)
        add(objectStyles, "Object Styles", src.projectInfo.objectStyles?.styles.count ?? 0)
        add(viewTemplates, "View Templates", src.elements(.viewTemplates).count)
        add(filters, "Filters", src.elements(.filters).count)
        add(projectParameters, "Project Parameters", src.projectParameters.count)
        return out.sorted { $0.title < $1.title }
    }

    /// Names of the chosen items that this project already has (shown before transferring, as in Revit).
    public static func duplicates(_ chosen: Set<String>, from src: BIMModel, into dst: BIMModel) -> [String] {
        var out: [String] = []
        for e in elements(chosen, src) where existing(e, src, dst) != nil { out.append(label(e)) }
        if chosen.contains(objectStyles), let s = src.projectInfo.objectStyles?.styles, let d = dst.projectInfo.objectStyles?.styles {
            out += s.keys.filter { d[$0] != nil }.sorted().map { "Object Style: \($0)" }
        }
        if chosen.contains(projectParameters) {
            let names = Set(dst.projectParameters.map(\.name))
            out += src.projectParameters.filter { names.contains($0.name) }.map { "Project Parameter: \($0.name)" }
        }
        return out
    }

    /// The source elements of the chosen items.
    static func elements(_ chosen: Set<String>, _ src: BIMModel) -> [Element] {
        var out: [Element] = []
        for t in systemTypes(src) where chosen.contains("type." + t.typeData!.instanceCategory.rawValue) { out.append(t) }
        if chosen.contains(materials) { out += src.elements(.materials) }
        if chosen.contains(lineStyles) { out += src.elements(.lineStyles) }
        if chosen.contains(fillPatterns) { out += src.elements(.fillPatterns) }
        if chosen.contains(viewTemplates) { out += src.elements(.viewTemplates) }
        if chosen.contains(filters) { out += src.elements(.filters) }
        return out.sorted { $0.id < $1.id }
    }

    static func label(_ e: Element) -> String {
        if let td = e.typeData { return td.familyName.isEmpty ? e.name : "\(td.familyName): \(e.name)" }
        return "\(e.category.singularName): \(e.name)"
    }

    /// The destination element an item matches.
    static func existing(_ e: Element, _ src: BIMModel, _ dst: BIMModel) -> Element? {
        if let td = e.typeData { return dst.type(category: td.instanceCategory, family: td.familyName, name: e.name) }
        return dst.elements(e.category).first { $0.name == e.name && $0.kind == e.kind }
    }

    /// Copies the chosen standards from `src`. With `overwrite`, matching items take the source's definition; otherwise
    /// they are kept and only new ones are added.
    @discardableResult
    public static func transfer(_ chosen: Set<String>, from src: BIMModel, overwrite: Bool, in tx: TransactionContext) -> Report {
        var report = Report()
        var context: [ElementID: Element] = [:]
        for e in src.allElements where ProjectTransfer.isSupporting(e) || e.viewFilter != nil { context[e.id] = e }
        var r = ProjectTransfer.Resolver(payload: ClipboardPayload(elements: [], context: context, sourceViewID: nil, sourceLevelID: nil), tx: tx)
        func filterID(_ id: ElementID) -> ElementID? {
            guard let f = src[id], f.viewFilter != nil else { return nil }
            if let d = tx.model.elements(.filters).first(where: { $0.name == f.name }) { return d.id }
            return tx.create(.filters, name: f.name, data: f.data)
        }
        func remap(_ o: GraphicOverride) -> GraphicOverride {
            var o = o
            o.surfacePatternID = o.surfacePatternID.flatMap { r.resolve($0) }
            o.cutPatternID = o.cutPatternID.flatMap { r.resolve($0) }
            return o
        }
        for e in elements(chosen, src) {
            let match = existing(e, src, tx.model)
            if match != nil && !overwrite { report.kept.append(label(e)); continue }
            var data = e.data
            switch data {
            case .type(var td):
                td.familyID = td.familyID.flatMap { r.resolve($0) }
                if var a = td.assembly {
                    a.layers = a.layers.map { l in var l = l; l.materialID = l.materialID.flatMap { r.resolve($0) }; return l }
                    td.assembly = a
                }
                td.params = td.params.compactMapValues { v in
                    if case .ref(let id?) = v { return r.resolve(id).map { .ref($0) } }
                    return v
                }
                data = .type(td)
            case .material(var m):
                m.surfacePatternID = m.surfacePatternID.flatMap { r.resolve($0) }
                m.cutPatternID = m.cutPatternID.flatMap { r.resolve($0) }
                data = .material(m)
            case .viewTemplate(var t):
                if var vg = t.visibility {
                    vg.hiddenElements = []; vg.elementOverrides = [:]; vg.hiddenLinkLayers = [:]
                    vg.filters = vg.filters.compactMap { f in filterID(f.filterID).map { var f = f; f.filterID = $0; f.override = remap(f.override); return f } }
                    vg.categoryOverrides = vg.categoryOverrides.mapValues(remap)
                    t.visibility = vg
                }
                data = .viewTemplate(t)
            default:
                break
            }
            if let m = match {
                let params = e.params
                tx.update(m.id) { $0.data = data; if e.typeData != nil { $0.params = params } }
                report.overwritten.append(label(e))
            } else {
                let params = e.params.compactMapValues { v -> ParamValue? in if case .ref = v { return nil }; return v }
                tx.create(e.category, name: e.name, data: data) { $0.params = params }
                report.added.append(label(e))
            }
        }
        if chosen.contains(objectStyles), let s = src.projectInfo.objectStyles, let pi = tx.model.projectInfoElement {
            var merged = tx.model.projectInfo.objectStyles ?? ObjectStyleSettings()
            for (k, v) in s.styles {
                if merged.styles[k] != nil && !overwrite { report.kept.append("Object Style: \(k)"); continue }
                (merged.styles[k] == nil ? { report.added.append("Object Style: \(k)") } : { report.overwritten.append("Object Style: \(k)") })()
                merged.styles[k] = v
            }
            tx.update(pi.id) { $0.projectInfo?.objectStyles = merged }
        }
        if chosen.contains(projectParameters) {
            var params = tx.model.projectParameters
            for p in src.projectParameters {
                if let i = params.firstIndex(where: { $0.name == p.name }) {
                    if overwrite { params[i] = p; report.overwritten.append("Project Parameter: \(p.name)") } else { report.kept.append("Project Parameter: \(p.name)") }
                } else { params.append(p); report.added.append("Project Parameter: \(p.name)") }
            }
            if params != tx.model.projectParameters { tx.setProjectParameters(params) }
        }
        return report
    }
}
