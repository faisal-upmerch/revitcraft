import Foundation
import ArcusGeometry

// BL-BROWSER: the Project Browser tree, its naming rules and the titles views carry in tabs and lists.

/// A node of the Project Browser tree. Ids are stable across rebuilds so expansion and selection survive model changes.
public struct BrowserNode: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable { case folder, view, sheet, schedule, placedView, family, type, group, link }
    public var id: String
    public var title: String
    public var kind: Kind
    /// The element the node stands for: the view, sheet, schedule, type, family (loadable families only), group or link.
    public var elementID: ElementID?
    public var symbol: String
    /// Trailing detail (instance count, "Link", …).
    public var subtitle: String = ""
    /// Family nodes: the family's name and category (system families have no family element).
    public var familyName: String?
    public var category: Category?
    public var children: [BrowserNode]?

    public init(id: String, title: String, kind: Kind, elementID: ElementID? = nil, symbol: String, subtitle: String = "",
                familyName: String? = nil, category: Category? = nil, children: [BrowserNode]? = nil) {
        self.id = id; self.title = title; self.kind = kind; self.elementID = elementID; self.symbol = symbol
        self.subtitle = subtitle; self.familyName = familyName; self.category = category; self.children = children
    }

    /// Depth-first search by id.
    public func find(_ id: String) -> BrowserNode? {
        if self.id == id { return self }
        for c in children ?? [] { if let hit = c.find(id) { return hit } }
        return nil
    }
}

/// Builds the Project Browser: Views (all) ▸ one folder per view type, Legends, Schedules/Quantities (all),
/// Sheets (all) with their placed views, Families ▸ Category ▸ Family ▸ Type, Groups ▸ Model/Detail, and Links.
/// Legends, Groups and Links are shown even when empty. Camera views are 3D views and live under 3D Views.
public enum ProjectBrowserTree {
    /// Order of the view-type folders under Views (all).
    public static let viewFolderOrder: [ViewKind] = [.floorPlan, .ceilingPlan, .structuralPlan, .areaPlan, .elevation, .section, .detail, .threeD, .drafting]

    /// Folder title for a view type ("Elevations (Building Elevation)").
    public static func folderTitle(_ k: ViewKind) -> String {
        switch k {
        case .elevation: "Elevations (Building Elevation)"
        case .section: "Sections (Building Section)"
        default: k.navigatorGroup
        }
    }

    public static func viewNodeID(_ id: ElementID) -> String { "v\(id.raw)" }
    public static func sheetNodeID(_ id: ElementID) -> String { "sh\(id.raw)" }
    public static func scheduleNodeID(_ id: ElementID) -> String { "s\(id.raw)" }

    /// The node id that represents an openable element (view, sheet or schedule).
    public static func nodeID(forOpenable id: ElementID, _ m: BIMModel) -> String? {
        guard let e = m[id] else { return nil }
        if e.sheet != nil { return sheetNodeID(id) }
        if e.schedule != nil { return scheduleNodeID(id) }
        if e.view != nil { return viewNodeID(id) }
        return nil
    }

    /// Ids of the folders (and parent views) above a node, outermost first, so the node can be revealed.
    public static func ancestors(of id: String, in roots: [BrowserNode]) -> [String] {
        func walk(_ nodes: [BrowserNode], _ path: [String]) -> [String]? {
            for n in nodes {
                if n.id == id { return path }
                if let c = n.children, let hit = walk(c, path + [n.id]) { return hit }
            }
            return nil
        }
        return walk(roots, []) ?? []
    }

    public static func find(_ id: String, in roots: [BrowserNode]) -> BrowserNode? {
        for r in roots { if let hit = r.find(id) { return hit } }
        return nil
    }

    /// The whole tree. `filter` keeps nodes whose name contains it (case-insensitive); a family matching the filter
    /// keeps all its types, a matching type keeps its family.
    public static func build(_ m: BIMModel, filter: String = "") -> [BrowserNode] {
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        func matches(_ s: String) -> Bool { f.isEmpty || s.lowercased().contains(f) }
        let byName: (BrowserNode, BrowserNode) -> Bool = { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        // Views: dependents nest under their parent view (plans, sections, elevations and callouts).
        let views = m.views.filter { $0.view != nil }
        var dependents: [ElementID: [Element]] = [:]
        for v in views { if let p = v.view?.parentViewID, m[p]?.view != nil { dependents[p, default: []].append(v) } }
        func viewNode(_ v: Element) -> BrowserNode? {
            let kids = (dependents[v.id] ?? []).compactMap(viewNode).sorted(by: byName)
            guard matches(v.name) || !kids.isEmpty else { return nil }
            let sheet = m.sheet(containing: v.id).flatMap { $0.sheet?.number }
            return BrowserNode(id: viewNodeID(v.id), title: v.name, kind: .view, elementID: v.id,
                               symbol: v.isCameraView ? "camera" : (v.view?.kind.symbolName ?? "rectangle"),
                               subtitle: sheet.map { "on \($0)" } ?? "", children: kids.isEmpty ? nil : kids)
        }
        var byKind: [ViewKind: [BrowserNode]] = [:]
        for v in views {
            guard let vd = v.view else { continue }
            if let p = vd.parentViewID, m[p]?.view != nil { continue }
            if let n = viewNode(v) { byKind[vd.kind, default: []].append(n) }
        }
        let viewFolders = viewFolderOrder.compactMap { k -> BrowserNode? in
            guard let items = byKind[k], !items.isEmpty else { return nil }
            return BrowserNode(id: "views.\(k.navigatorGroup)", title: folderTitle(k), kind: .folder, symbol: "folder", children: items.sorted(by: byName))
        }
        var out = [BrowserNode(id: "views", title: "Views (all)", kind: .folder, symbol: "rectangle.stack", children: viewFolders)]
        out.append(BrowserNode(id: "legends", title: "Legends", kind: .folder, symbol: "list.bullet.rectangle", children: (byKind[.legend] ?? []).sorted(by: byName)))

        let schedules = m.schedules.filter { matches($0.name) }.map {
            BrowserNode(id: scheduleNodeID($0.id), title: $0.name, kind: .schedule, elementID: $0.id, symbol: "tablecells",
                        subtitle: m.viewports(showing: $0.id).isEmpty ? "" : "on sheet")
        }
        out.append(BrowserNode(id: "schedules", title: "Schedules/Quantities (all)", kind: .folder, symbol: "tablecells", children: schedules))

        let sheets = m.sheets.compactMap { s -> BrowserNode? in
            let label = ViewTitles.sheetLabel(s)
            let placed = m.owned(byView: s.id).compactMap { vp -> BrowserNode? in
                guard let v = m[vp.viewport?.viewID] else { return nil }
                return BrowserNode(id: "p\(vp.id.raw)", title: ViewTitles.qualified(v), kind: .placedView, elementID: v.id,
                                   symbol: v.schedule != nil ? "tablecells" : (v.view?.kind.symbolName ?? "rectangle"))
            }
            guard matches(label) || placed.contains(where: { matches($0.title) }) else { return nil }
            return BrowserNode(id: sheetNodeID(s.id), title: label, kind: .sheet, elementID: s.id, symbol: "doc.richtext", children: placed.isEmpty ? nil : placed)
        }
        out.append(BrowserNode(id: "sheets", title: "Sheets (all)", kind: .folder, symbol: "doc.on.doc", children: sheets))

        out.append(BrowserNode(id: "families", title: "Families", kind: .folder, symbol: "cube.box", children: familyNodes(m, matches: matches)))
        out.append(BrowserNode(id: "groups", title: "Groups", kind: .folder, symbol: "square.on.square.dashed", children: groupNodes(m, matches: matches)))

        let links = m.elements(.importedCAD).filter { matches($0.link?.sourceName ?? $0.name) }.map {
            BrowserNode(id: "l\($0.id.raw)", title: $0.link?.sourceName ?? $0.name, kind: .link, elementID: $0.id,
                        symbol: $0.link?.isLinked == true ? "link" : "square.and.arrow.down",
                        subtitle: $0.link?.isLoaded == false ? "Unloaded" : ($0.link?.isLinked == true ? "Link" : "Import"))
        }
        out.append(BrowserNode(id: "links", title: "Links", kind: .folder, symbol: "link", children: links))
        return out
    }

    /// Families ▸ Category ▸ Family ▸ Type (instance counts on the type rows).
    static func familyNodes(_ m: BIMModel, matches: (String) -> Bool) -> [BrowserNode] {
        var byCategory: [Category: [String: [Element]]] = [:]
        for t in m.elements(.elementTypes) {
            guard let td = t.typeData else { continue }
            byCategory[td.instanceCategory, default: [:]][td.familyName, default: []].append(t)
        }
        return byCategory.keys.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }.compactMap { cat -> BrowserNode? in
            let families = byCategory[cat]!.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { fam -> BrowserNode? in
                let types = byCategory[cat]![fam]!
                let familyMatches = matches(fam)
                let kept = types.filter { familyMatches || matches($0.name) }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                guard !kept.isEmpty else { return nil }
                let familyIDs = Set(types.compactMap { $0.typeData?.familyID })
                let familyID = familyIDs.count == 1 ? familyIDs.first : nil
                let typeNodes = kept.map { t in
                    BrowserNode(id: "t\(t.id.raw)", title: t.name, kind: .type, elementID: t.id, symbol: "cube",
                                subtitle: "\(m.instanceCount(ofType: t.id))", familyName: fam, category: cat)
                }
                return BrowserNode(id: "fam.\(cat.rawValue).\(fam)", title: fam, kind: .family, elementID: familyID, symbol: "shippingbox",
                                   familyName: fam, category: cat, children: typeNodes)
            }
            guard !families.isEmpty else { return nil }
            return BrowserNode(id: "f.\(cat.rawValue)", title: cat.displayName, kind: .folder, symbol: "folder", category: cat, children: families)
        }
    }

    /// Groups ▸ Model / Detail ▸ one row per group type (the first instance stands for the type).
    static func groupNodes(_ m: BIMModel, matches: (String) -> Bool) -> [BrowserNode] {
        func nodes(_ cat: Category, _ key: String) -> [BrowserNode] {
            let byType = Dictionary(grouping: m.elements(cat), by: { $0.group?.groupTypeName ?? $0.name })
            return byType.keys.filter(matches).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
                let instances = byType[name]!
                return BrowserNode(id: "g.\(key).\(name)", title: name, kind: .group, elementID: instances[0].id, symbol: "square.on.square.dashed",
                                   subtitle: "\(instances.count)", category: cat)
            }
        }
        return [BrowserNode(id: "groups.detail", title: "Detail", kind: .folder, symbol: "folder", category: .detailGroups, children: nodes(.detailGroups, "detail")),
                BrowserNode(id: "groups.model", title: "Model", kind: .folder, symbol: "folder", category: .modelGroups, children: nodes(.modelGroups, "model"))]
    }
}

/// Names of views as BIM users read them in tabs, lists and the window subtitle.
public enum ViewTitles {
    /// "Floor Plan", "Ceiling Plan", "Elevation", "Section", "3D View", "Legend"…
    public static func prefix(_ k: ViewKind) -> String {
        switch k {
        case .ceilingPlan: "Ceiling Plan"
        default: k.rawValue
        }
    }

    /// "A101 - Name".
    public static func sheetLabel(_ s: Element) -> String { "\(s.sheet?.number ?? "") - \(s.name)" }

    /// "Floor Plan: Level 1", "Sheet: A101 - Plans", "Schedule: Door Schedule".
    public static func qualified(_ e: Element) -> String {
        if e.sheet != nil { return "Sheet: " + sheetLabel(e) }
        if e.schedule != nil { return "Schedule: \(e.name)" }
        if let k = e.view?.kind { return "\(prefix(k)): \(e.name)" }
        return e.name
    }
}

/// Naming of new and renamed views, types, families, levels and sheets.
public enum BrowserNaming {
    /// Characters BIM applications don't allow in view, sheet, type and family names.
    public static let forbiddenCharacters: Set<Character> = ["\\", ":", "{", "}", "[", "]", "|", ";", "<", ">", "?", "`", "~"]

    /// Trims spaces and line breaks.
    public static func normalized(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "Copy of X", then "Copy (2) of X", "Copy (3) of X"… — the first name `isTaken` doesn't reject.
    public static func duplicateName(of name: String, isTaken: (String) -> Bool) -> String {
        var candidate = "Copy of \(name)"
        var k = 2
        while isTaken(candidate) { candidate = "Copy (\(k)) of \(name)"; k += 1 }
        return candidate
    }

    /// "X - Dependent 1", "X - Dependent 2"…
    public static func dependentName(of name: String, isTaken: (String) -> Bool) -> String {
        var k = 1
        while isTaken("\(name) - Dependent \(k)") { k += 1 }
        return "\(name) - Dependent \(k)"
    }

    /// Whether a view name is used by another view of the same Project Browser group.
    public static func viewNameTaken(_ name: String, kind: ViewKind, excluding id: ElementID? = nil, in m: BIMModel) -> Bool {
        m.views.contains { $0.id != id && $0.name == name && $0.view?.kind.navigatorGroup == kind.navigatorGroup }
    }

    /// The name for a duplicate of a view ("Copy of Level 1") or schedule.
    public static func duplicateViewName(_ e: Element, in m: BIMModel) -> String {
        if let k = e.view?.kind { return duplicateName(of: e.name) { viewNameTaken($0, kind: k, in: m) } }
        return duplicateName(of: e.name) { n in m.schedules.contains { $0.name == n } }
    }

    /// Why `name` can't be given to element `id`, or nil when it can. Views are unique within their view type,
    /// schedules among schedules, types within their family, families within their category, levels among levels.
    public static func renameProblem(_ id: ElementID, to raw: String, in m: BIMModel) -> String? {
        let name = normalized(raw)
        guard let e = m[id] else { return "The item no longer exists." }
        guard !name.isEmpty else { return "Enter a name. Names can't be empty or only spaces." }
        if e.level == nil, name.contains(where: forbiddenCharacters.contains) {
            return "Names can't contain any of these characters: \\ : { } [ ] | ; < > ? ` ~"
        }
        if let k = e.view?.kind {
            if viewNameTaken(name, kind: k, excluding: id, in: m) {
                return "“\(name)” is already the name of another \(ViewTitles.prefix(k).lowercased()) view. Enter a unique name."
            }
        } else if e.schedule != nil {
            if m.schedules.contains(where: { $0.id != id && $0.name == name }) { return "“\(name)” is already the name of another schedule. Enter a unique name." }
        } else if let td = e.typeData {
            if m.types(for: td.instanceCategory).contains(where: { $0.id != id && $0.name == name && $0.typeData?.familyName == td.familyName }) {
                return "The family “\(td.familyName)” already has a type named “\(name)”. Enter a unique name."
            }
        } else if e.level != nil {
            if m.levels.contains(where: { $0.id != id && $0.name == name }) { return "“\(name)” is already the name of another level. Enter a unique name." }
        } else if e.group != nil {
            if m.elements(e.category).contains(where: { $0.group?.groupTypeName == name && $0.group?.groupTypeName != e.group?.groupTypeName }) {
                return "“\(name)” is already the name of another group. Enter a unique name."
            }
        }
        return nil
    }

    /// Why a family (by name, in a category) can't be renamed to `raw`, or nil.
    public static func familyRenameProblem(_ family: String, category: Category, to raw: String, in m: BIMModel) -> String? {
        let name = normalized(raw)
        guard !name.isEmpty else { return "Enter a name. Names can't be empty or only spaces." }
        if name.contains(where: forbiddenCharacters.contains) { return "Names can't contain any of these characters: \\ : { } [ ] | ; < > ? ` ~" }
        if name != family, m.types(for: category).contains(where: { $0.typeData?.familyName == name }) || m.family(named: name) != nil {
            return "A family named “\(name)” is already loaded. Enter a unique name."
        }
        return nil
    }

    /// Why a sheet can't take this number and name, or nil.
    public static func sheetTitleProblem(_ id: ElementID, number rawNumber: String, name rawName: String, in m: BIMModel) -> String? {
        let number = normalized(rawNumber), name = normalized(rawName)
        guard !number.isEmpty else { return "Enter a sheet number." }
        guard !name.isEmpty else { return "Enter a sheet name." }
        if (number + name).contains(where: forbiddenCharacters.contains) { return "Sheet numbers and names can't contain any of these characters: \\ : { } [ ] | ; < > ? ` ~" }
        if m.sheets.contains(where: { $0.id != id && $0.sheet?.number == number }) { return "Sheet number “\(number)” is already in use. Enter a unique number." }
        return nil
    }

    /// The first free "Name 2", "Name 3"… type name in a family.
    public static func duplicateTypeName(_ name: String, family: String, category: Category, in m: BIMModel) -> String {
        let taken = Set(m.types(for: category).filter { $0.typeData?.familyName == family }.map(\.name))
        var k = 2
        while taken.contains("\(name) \(k)") { k += 1 }
        return "\(name) \(k)"
    }
}

/// Automatic level names: the last created level's trailing number goes up by one ("Level 5" → "Level 6",
/// "L-03" → "L-04"), skipping names already in use.
public enum LevelNaming {
    /// Splits "Level 12" into ("Level ", 12, 2 digits).
    public static func trailingNumber(_ name: String) -> (prefix: String, number: Int, digits: Int)? {
        let digits = name.reversed().prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9, let n = Int(String(digits.reversed())) else { return nil }
        return (String(name.dropLast(digits.count)), n, digits.count)
    }

    public static func nextName(_ m: BIMModel) -> String {
        let taken = Set(m.levels.map(\.name))
        for l in m.elements(.levels).sorted(by: { $0.id > $1.id }) {
            guard let (prefix, n, width) = trailingNumber(l.name) else { continue }
            var k = n + 1
            func format(_ v: Int) -> String {
                let s = String(v)
                return prefix + String(repeating: "0", count: max(0, width - s.count)) + s
            }
            while taken.contains(format(k)) { k += 1 }
            return format(k)
        }
        var k = taken.count + 1
        while taken.contains("Level \(k)") { k += 1 }
        return "Level \(k)"
    }
}

/// Which plan views and which markers point at a view.
public enum ViewReferences {
    /// Views that show a marker (section, elevation or callout head) for `id`.
    public static func referringViews(of id: ElementID, _ m: BIMModel) -> [Element] {
        guard let v = m[id], let vd = v.view else { return [] }
        let plans = m.views.filter { $0.id != id && $0.view?.kind.isPlan == true }
        var out: [Element]
        switch vd.kind {
        case .section, .detail:
            out = plans.filter { p in
                guard vd.parentViewID == nil || vd.parentViewID == p.id else { return false }
                let z = m.elevation(ofLevel: p.levelID)
                let crop = vd.cropRegion ?? Rect2(min: Vec2(-5, z - 1), max: Vec2(5, z + 10))
                return !(crop.max.y < z || crop.min.y > z + 20)
            }
        case .elevation:
            out = plans
        default:
            out = vd.kind.isPlan && vd.cropRegion != nil ? [vd.parentViewID.flatMap { m[$0] }].compactMap { $0 } : []
        }
        return out.sorted { ViewTitles.qualified($0).localizedStandardCompare(ViewTitles.qualified($1)) == .orderedAscending }
    }

    /// The sheet number and detail number of the first referring view placed on a sheet ("Referencing Sheet/Detail").
    public static func referencingSheetAndDetail(of id: ElementID, _ m: BIMModel) -> (sheet: String, detail: String)? {
        for r in referringViews(of: id, m) {
            if let vp = m.viewports(showing: r.id).first, let s = m[vp.ownerViewID]?.sheet {
                return (s.number, vp.viewport?.detailNumber ?? "")
            }
        }
        return nil
    }
}

extension ViewTemplateData {
    /// A template that captures a view's scale, detail level, style, discipline, view range, phase filter and
    /// visibility ("Create View Template From View").
    public static func capturing(_ v: ViewData) -> ViewTemplateData {
        var td = ViewTemplateData(appliesTo: v.kind)
        td.scale = v.scale; td.detailLevel = v.detailLevel; td.visualStyle = v.visualStyle; td.discipline = v.discipline
        td.viewRange = v.kind.isPlan ? v.viewRange : nil; td.phaseFilter = v.phaseFilter; td.visibility = v.visibility
        return td
    }
}
