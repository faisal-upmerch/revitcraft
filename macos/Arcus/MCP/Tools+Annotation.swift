import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// AITOOLS: the Annotate tab: text notes, detail lines, filled and masking regions, detail components, spot elevations
// and coordinates, keynotes, legends, revision clouds, and arrange_dimensions (respacing strings that overlap).
// Annotations belong to a view (default the active one); points are in that view's coordinates (plans: x, y;
// sections and elevations: along the view, height).

extension ArcusToolCatalog {
    static let viewNote = "view: name or id (default the active view). Points are in the view (plan x, y; in sections/elevations: across, height). "
    static let annotationTools: [ToolSpec] = [
        ToolSpec("add_text", "Text", "Text notes in a view, optionally with a leader to a point. " + viewNote + lengthNote,
                 risk: .edit, group: .annotation, modes: .model,
                 properties: ["view": S.ref(), "notes": S.array(S.object(["text": S.str(), "point": S.point(), "leader_to": S.point(), "width": S.len("Wrap width (model units)"), "type": S.ref()], required: ["text", "point"]))],
                 required: ["notes"]),
        ToolSpec("add_detail_lines", "Detail Lines", "View-specific detail lines along segments, with a line style (Thin Lines, Medium Lines, Wide Lines, Hidden, …). " + viewNote,
                 risk: .edit, group: .annotation, modes: .model,
                 properties: ["view": S.ref(), "segments": S.array(S.points()), "style": S.str()], required: ["segments"]),
        ToolSpec("add_region", "Filled/Masking Region", "A filled region (hatch: type name such as 'Solid Black', 'Diagonal Crosshatch') or a masking region from a boundary. " + viewNote,
                 risk: .edit, group: .annotation, modes: .model,
                 properties: ["view": S.ref(), "boundary": S.points(), "masking": S.bool(), "type": S.ref()], required: ["boundary"]),
        ToolSpec("place_detail_components", "Detail Component", "Detail components (2D families such as wood blocking, studs, break lines) at points in a view. " + viewNote,
                 risk: .edit, group: .annotation, modes: .model,
                 properties: ["view": S.ref(), "type": S.ref("Detail component type (list_types category detailComponents)"), "points": S.points(), "rotation": S.num("Degrees")],
                 required: ["points"]),
        ToolSpec("add_spot_dimensions", "Spot Dimension", "Spot elevations (plans: the surface below the point; sections/elevations: the point's height) or spot coordinates (plans) at points. " + viewNote,
                 risk: .edit, group: .annotation, modes: .model,
                 properties: ["view": S.ref(), "kind": S.oneOf(["elevation", "coordinate"], "Default elevation"), "points": S.points(), "leader": S.bool()], required: ["points"]),
        ToolSpec("add_keynotes", "Keynote", "Keynote tags on elements in a view: element keynote (from the type), material keynote, or a user keynote with a key from the keynote table. " + viewNote,
                 risk: .edit, group: .annotation, modes: .model,
                 properties: ["view": S.ref(), "elements": S.ids(), "kind": S.oneOf(["element", "material", "user"], "Default element"), "key": S.str("User keynote key, e.g. '09 21 16.A1'")],
                 required: ["elements"]),
        ToolSpec("create_legend", "Legend", "A legend view with a component of each named type in rows (doors, windows, wall/floor types…), and a label for each. Place it on sheets with place_on_sheet.",
                 risk: .edit, group: .annotation, modes: .model,
                 properties: ["name": S.str(), "types": S.array(S.ref(), "Type names or ids"), "category": S.str("Or the types of a category in use, e.g. doors"), "scale": S.int("Default 48 / 50")]),
        ToolSpec("add_revision_cloud", "Revision Cloud", "A revision cloud around a boundary in a view, tagged with a revision (default the latest; add_revision makes one). " + viewNote,
                 risk: .edit, group: .annotation, modes: .model,
                 properties: ["view": S.ref(), "boundary": S.points(), "revision": S.ref("Revision number or description")], required: ["boundary"]),
        ToolSpec("arrange_dimensions", "Arrange Dimensions", "Fix overlapping dimensions in a view: delete duplicates and respace parallel strings that lie on top of each other to a clean paper spacing, moving outward. verify_drawing reports what's left.",
                 risk: .edit, group: .annotation, modes: .model,
                 properties: ["view": S.ref(), "spacing_mm": S.num("Paper spacing between strings, default 8"), "remove_duplicates": S.bool("Default true")]),
    ]
}

extension ArcusToolbox {
    static let annotationHandlers: [String: ToolHandler] = [
        "add_text": { b, c in try b.addText(c) },
        "add_detail_lines": { b, c in try b.addDetailLines(c) },
        "add_region": { b, c in try b.addRegion(c) },
        "place_detail_components": { b, c in try b.placeDetailComponents(c) },
        "add_spot_dimensions": { b, c in try b.addSpots(c) },
        "add_keynotes": { b, c in try b.addKeynotes(c) },
        "create_legend": { b, c in try b.createLegend(c) },
        "add_revision_cloud": { b, c in try b.addRevisionCloud(c) },
        "arrange_dimensions": { b, c in try b.arrangeDimensions(c) },
    ]

    /// The view an annotation goes in: 2D views and sheets, not 3D or schedules.
    func annotationView(_ c: ToolContext) throws(ToolError) -> Element {
        let v = try c.viewOrActive(allowSheets: true)
        if v.view?.kind == .threeD { throw ToolError("Annotations go in 2D views and sheets; “\(v.name)” is a 3D view. Open a plan, section, elevation, drafting view or sheet.") }
        return v
    }

    func addText(_ c: ToolContext) throws -> ToolOutput {
        let view = try annotationView(c)
        let m = try c.model()
        var specs: [(TextNoteData, ElementID?)] = []
        for (k, n) in try c.args.requireArray("notes").enumerated() {
            guard let text = n["text"]?.stringValue, !text.isEmpty, let pv = n["point"] else { throw ToolError("notes[\(k)] needs text and point.") }
            var d = TextNoteData(position: try c.point(pv, "notes[\(k)].point"), text: text, width: try n["width"].map { try c.length($0, "notes[\(k)].width") } ?? 0)
            if let lv = n["leader_to"] { d.leaders = [try c.point(lv, "notes[\(k)].leader_to")] }
            let t = try n["type"].map { try c.type($0, category: .textNotes) }?.id ?? m.types(for: .textNotes).first?.id
            specs.append((d, t))
        }
        let r = try c.edit("Text") { tx in for (d, t) in specs { tx.create(.textNotes, data: .textNote(d), typeID: t, ownerViewID: view.id) } }
        let ids = ToolContext.created(r)
        return result(c, ["notes": .array(ids.map(\.json)), "view": .string(view.name)], ids: ids)
    }

    func lineStyle(_ name: String?, _ m: BIMModel) throws(ToolError) -> ElementID? {
        guard let name else { return nil }
        let styles = m.elements(.lineStyles)
        if let s = styles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) ?? styles.first(where: { $0.name.lowercased().contains(name.lowercased()) }) { return s.id }
        throw ToolError("No line style “\(name)”. Styles: \(styles.map(\.name).sorted().joined(separator: ", ")).")
    }

    func addDetailLines(_ c: ToolContext) throws -> ToolOutput {
        let view = try annotationView(c)
        let segs = try segments(c)
        let style = try lineStyle(c.args.string("style"), try c.model())
        let r = try c.edit("Detail Lines") { tx in for s in segs { tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(s), styleID: style)), ownerViewID: view.id) } }
        let ids = ToolContext.created(r)
        return result(c, ["lines": .array(ids.map(\.json)), "view": .string(view.name)], ids: ids)
    }

    func addRegion(_ c: ToolContext) throws -> ToolOutput {
        let view = try annotationView(c)
        guard let b = try boundary(c) else { throw ToolError("Missing boundary.") }
        let masking = c.args.bool("masking", default: false)
        let cat: Category = masking ? .maskingRegions : .filledRegions
        let m = try c.model()
        let type = try c.args["type"].map { try c.type($0, category: .filledRegions).id } ?? m.types(for: cat).first?.id ?? m.types(for: .filledRegions).first?.id
        let r = try c.edit(masking ? "Masking Region" : "Filled Region") { tx in
            tx.create(cat, data: .filledRegion(FilledRegionData(boundary: Sketch(polygon: b), isMasking: masking)), typeID: type, ownerViewID: view.id)
        }
        let ids = ToolContext.created(r)
        return result(c, ["region": ids.first?.json ?? .null, "area": .string(c.formatArea(b.area, m))], ids: ids)
    }

    func placeDetailComponents(_ c: ToolContext) throws -> ToolOutput {
        let view = try annotationView(c)
        let type = try c.type(c.args["type"], category: .detailComponents)
        let pts = try c.points(c.args["points"] ?? .null, "points", min: 1)
        let rot = (c.args.double("rotation") ?? 0) * .pi / 180
        let r = try c.edit("Detail Component") { tx in
            for p in pts { tx.create(.detailComponents, data: .detailComponent(DetailComponentData(location: p, rotation: rot)), typeID: type.id, ownerViewID: view.id) }
        }
        let ids = ToolContext.created(r)
        return result(c, ["components": .array(ids.map(\.json)), "type": .string(ToolContext.typeLabel(type, try c.model()))], ids: ids)
    }

    func addSpots(_ c: ToolContext) throws -> ToolOutput {
        let view = try annotationView(c)
        let m = try c.model()
        let coordinate = c.args.string("kind")?.lowercased() == "coordinate"
        let vertical = view.view?.kind.isVerticalCut ?? false
        if coordinate && vertical { throw ToolError("Spot coordinates are placed in plan views.") }
        let pts = try c.points(c.args["points"] ?? .null, "points", min: 1)
        let leader = c.args.bool("leader", default: true)
        let off = Vec2(1, 1).normalized * (0.006 * Double(view.view?.scale ?? 100))
        var values: [JSONValue] = []
        let r = try c.edit(coordinate ? "Spot Coordinate" : "Spot Elevation") { tx in
            for p in pts {
                let (z, ref): (Double, ElementID?)
                if vertical { (z, ref) = (p.y, nil) } else { let s = SpotGeometry.surface(at: p, levelID: view.levelID, m); (z, ref) = (s.elevation, s.reference) }
                let sd = SpotData(kind: coordinate ? .coordinate : .elevation, point: p, elevation: z, leaderHead: leader ? p + off : p, referenceID: ref)
                tx.create(coordinate ? .spotCoordinates : .spotElevations, data: .spot(sd), ownerViewID: view.id)
                values.append(.string(coordinate ? "\(c.formatLength(p.x, m)), \(c.formatLength(p.y, m))" : c.formatLength(z, m)))
            }
        }
        let ids = ToolContext.created(r)
        return result(c, ["spots": .array(ids.map(\.json)), "values": .array(values)], ids: ids)
    }

    func addKeynotes(_ c: ToolContext) throws -> ToolOutput {
        let view = try annotationView(c)
        let m = try c.model()
        let ids = try c.elementIDs("elements")
        let kind: TagKind = switch c.args.string("kind")?.lowercased() { case "material": .keynoteMaterial; case "user": .keynoteUser; default: .keynoteElement }
        let key = c.args.string("key")
        if kind == .keynoteUser {
            guard let key else { throw ToolError("A user keynote needs key. Keys: \(Keynoting.pickable(m).prefix(20).map { "\($0.key) \($0.text)" }.joined(separator: "; ")).") }
            guard Keynoting.text(for: key, m) != nil else { throw ToolError("No keynote “\(key)” in the keynote table. Close: \(Keynoting.pickable(m).filter { $0.key.hasPrefix(String(key.prefix(2))) }.prefix(8).map(\.key).joined(separator: ", ")).") }
        }
        let scale = Double(view.view?.scale ?? 100)
        let r = try c.edit("Keynote") { tx in
            for id in ids {
                guard let e = m[id], let anchor = AnnotationGeometry.leaderAnchor(e, m, view: view) else { continue }
                var t = TagData(taggedID: id, head: anchor + Vec2(1, 1).normalized * (0.012 * scale), hasLeader: true)
                t.kind = kind
                t.leaderEnd = anchor
                if kind == .keynoteUser { t.keynote = key }
                if kind == .keynoteMaterial { t.materialID = m.typeData(of: e)?.assembly?.layers.first?.materialID }
                t.keynoteDisplay = Keynoting.display(m)
                tx.create(.tags, data: .tag(t), ownerViewID: view.id)
            }
        }
        let made = ToolContext.created(r)
        let nm = try c.model()
        let blank = made.compactMap { nm[$0] }.filter { e in e.tag.map { $0.kind == .keynoteElement && (nm[$0.taggedID].flatMap { nm.typeData(of: $0)?.params[ParameterID("keynote")] } == nil) } ?? false }
        return result(c, ["keynotes": .array(made.map(\.json))], ids: made,
                      problems: made.count < ids.count ? ["\(ids.count - made.count) element(s) can't be keynoted in this view."] : [] + (blank.isEmpty ? [] : ["\(blank.count) element keynote(s) show no key: the types have no Keynote value (set_parameters type:true {\"Keynote\": …})."]))
    }

    func createLegend(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        var types: [Element] = []
        for (k, t) in (c.args.array("types") ?? []).enumerated() {
            if let raw = t.intValue, let e = m[ElementID(UInt64(max(0, raw)))], e.typeData != nil { types.append(e); continue }
            guard let s = t.stringValue else { throw ToolError("types[\(k)] must be a type name or id.") }
            let hits = m.elements(.elementTypes).filter { ToolContext.typeLabel($0, m).caseInsensitiveCompare(s) == .orderedSame || $0.name.caseInsensitiveCompare(s) == .orderedSame }
            guard let e = hits.first ?? m.elements(.elementTypes).first(where: { ToolContext.typeLabel($0, m).localizedCaseInsensitiveContains(s) }) else { throw ToolError("types[\(k)]: no type “\(s)”. list_types shows them.") }
            types.append(e)
        }
        if let cs = c.args.string("category") {
            // The category's types in use (a legend shows what the project has), else its first dozen.
            let all = m.types(for: try Self.category(cs))
            let used = all.filter { m.instanceCount(ofType: $0.id) > 0 }
            types += used.isEmpty ? Array(all.prefix(12)) : used
        }
        guard !types.isEmpty else { throw ToolError("Give types or a category.") }
        let scale = c.args.int("scale") ?? (m.units.system == .imperial ? 48 : 50)
        let name = c.args.string("name") ?? "Legend \(m.views.filter { $0.view?.kind == .legend }.count + 1)"
        let row = 0.03 * Double(scale)
        let textType = m.types(for: .textNotes).first?.id
        var vid: ElementID?
        try c.edit("Legend") { tx in
            var vd = ViewData(kind: .legend, scale: scale); vd.phaseID = tx.model.latestPhase?.id
            let v = tx.create(.views, name: name, data: .view(vd))
            vid = v
            for (k, t) in types.enumerated() {
                var d = DetailComponentData(location: Vec2(0, -Double(k) * row))
                d.legendTypeID = t.id
                if t.typeData?.assembly != nil { d.legendLength = row * 1.5 }
                tx.create(.detailComponents, data: .detailComponent(d), ownerViewID: v)
                tx.create(.textNotes, data: .textNote(TextNoteData(position: Vec2(row * 1.2, -Double(k) * row), text: ToolContext.typeLabel(t, m))), typeID: textType, ownerViewID: v)
            }
        }
        if let vid { _ = (host as? any DocumentUIHost)?.activateView(vid) }
        return result(c, ["legend": vid?.json ?? .null, "name": .string(name), "rows": .int(types.count)], ids: vid.map { [$0] } ?? [])
    }

    func revision(_ v: JSONValue?, _ m: BIMModel) throws(ToolError) -> Element? {
        let revs = m.elements(.revisions).sorted { ($0.revisionData?.sequence ?? 0) < ($1.revisionData?.sequence ?? 0) }
        guard let v else { return revs.last }
        if let i = v.intValue, let r = revs.first(where: { $0.revisionData?.sequence == i || $0.id.raw == UInt64(max(0, i)) }) { return r }
        if let s = v.stringValue, let r = revs.first(where: { $0.revisionData?.description.localizedCaseInsensitiveContains(s) == true || "\($0.revisionData?.sequence ?? 0)" == s }) { return r }
        throw ToolError("No revision “\(v.stringValue ?? v.jsonText)”. Revisions: \(revs.map { "\($0.revisionData?.sequence ?? 0) \($0.revisionData?.description ?? "")" }.joined(separator: "; ")). add_revision makes one.")
    }

    func addRevisionCloud(_ c: ToolContext) throws -> ToolOutput {
        let view = try annotationView(c)
        guard let b = try boundary(c) else { throw ToolError("Missing boundary.") }
        let rev = try revision(c.args["revision"], try c.model())
        let r = try c.edit("Revision Cloud") { tx in tx.create(.revisionClouds, data: .revisionCloud(RevisionCloudData(outline: b, revisionID: rev?.id)), ownerViewID: view.id) }
        let ids = ToolContext.created(r)
        return result(c, ["cloud": ids.first?.json ?? .null, "revision": .string(rev?.revisionData?.description ?? "none")], ids: ids,
                      problems: rev == nil ? ["The cloud has no revision. add_revision makes one, then set it on the cloud."] : [])
    }

    func arrangeDimensions(_ c: ToolContext) throws -> ToolOutput {
        let view = try c.viewOrActive()
        let m = try c.model()
        let before = DrawingCheck.dimensionProblems(view, m)
        let spacing = (c.args.double("spacing_mm") ?? 8) / 1000
        guard spacing >= 0.002, spacing <= 0.05 else { throw ToolError("spacing_mm must be 2…50.") }
        var moved = 0, deleted = 0
        if !before.isEmpty || c.args.bool("remove_duplicates", default: true) {
            try c.edit("Arrange Dimensions") { tx in (moved, deleted) = DrawingCheck.arrange(view, spacing: spacing, removeDuplicates: c.args.bool("remove_duplicates", default: true), in: tx) }
        }
        let nm = try c.model()
        let after = DrawingCheck.dimensionProblems(nm[view.id] ?? view, nm)
        return result(c, ["view": .string(view.name), "moved": .int(moved), "deleted_duplicates": .int(deleted), "problems_before": .int(before.count)],
                      ids: [], problems: after.map(\.message))
    }
}
