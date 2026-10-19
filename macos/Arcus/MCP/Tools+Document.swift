import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication
import ArcusPersistence

// MCP: document tools: status, create, open, save, project information.

extension ArcusToolbox {
    func status(_ c: ToolContext) throws -> ToolOutput {
        var o: [String: JSONValue] = ["backend": .string(host.backendName)]
        for (k, v) in statusExtras() { o[k] = v }
        guard let s = host.session else {
            o["document"] = .null
            o["next"] = "Call create_project (buildings) or create_furniture (a piece of furniture), or open_document with a path."
            return ToolOutput(.object(o))
        }
        let m = s.model
        o["document"] = .string(host.documentName)
        o["path"] = host.documentURL.map { .string($0.path) } ?? .null
        o["kind"] = .string(m.isFurniture ? "furniture" : "project")
        o["unit"] = .string(ToolContext.unitScale(m).symbol)
        o["levels"] = .array(m.levels.sorted { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) }.map {
            ["id": $0.id.json, "name": .string($0.name), "elevation": c.out($0.level?.elevation ?? 0, m)]
        })
        var counts: [String: JSONValue] = [:]
        let cats: [Category] = m.isFurniture
            ? [.furniturePanels, .furnitureShelves, .furnitureLegs, .furnitureRails, .furnitureEdgeProfiles]
            : [.walls, .doors, .windows, .floors, .ceilings, .roofs, .stairs, .railings, .rooms, .furniture, .plumbingFixtures, .casework, .grids]
        for cat in cats { let n = m.elements(cat).count; if n > 0 { counts[cat.rawValue] = .int(n) } }
        counts["views"] = .int(m.views.count)
        counts["sheets"] = .int(m.sheets.count)
        o["counts"] = .object(counts)
        o["health"] = .int(ModelHealth.check(m).count)
        o["can_undo"] = .bool(s.canUndo)
        if m.isFurniture {
            var size: [String: JSONValue] = [:]
            for n in ["Width", "Depth", "Height"] { if let v = FurnitureParameters.value(n, m)?.quantityValue { size[n.lowercased()] = c.out(v, m) } }
            o["size"] = .object(size)
        }
        return ToolOutput(.object(o))
    }

    func createProject(_ c: ToolContext) async throws -> ToolOutput {
        let name = try c.args.requireString("name")
        let kind: ProjectTemplateKind = c.args.string("template")?.lowercased() == "empty" ? .empty : .architectural
        let units: UnitsSettings = c.args.string("units")?.lowercased() == "metric" ? .metric : .imperial
        var (model, ids) = ProjectTemplates.make(kind, units: units, projectName: name)
        let scale = units.system == .imperial ? 0.3048 : 0.001
        // Template levels, lowest first, replaced by the requested ones (Imperial default: 10'-0" floor to floor).
        var levelSpecs = c.args.array("levels") ?? []
        if levelSpecs.isEmpty, units.system == .imperial, kind == .architectural {
            levelSpecs = [["name": "Level 1", "elevation": 0], ["name": "Level 2", "elevation": 10], ["name": "Roof", "elevation": 20]]
        }
        if !levelSpecs.isEmpty {
            let specs = levelSpecs
            var wanted: [(String, Double)] = []
            for (k, s) in specs.enumerated() {
                guard let n = s["name"]?.stringValue, let ev = s["elevation"] else { throw ToolError("levels[\(k)] needs name and elevation.") }
                let e: Double
                if let d = ev.doubleValue { e = d * scale } else if let t = ev.stringValue, let d = try? QuantityParser.parse(t, kind: .length, units: units) { e = d } else {
                    throw ToolError("levels[\(k)].elevation must be a length.")
                }
                wanted.append((n, e))
            }
            wanted.sort { $0.1 < $1.1 }
            let tx = TransactionContext(model: model, name: "Levels")
            let existing = ids.levels.sorted { tx.model.elevation(ofLevel: $0) < tx.model.elevation(ofLevel: $1) }
            let phase = tx.model.latestPhase?.id
            for (k, w) in wanted.enumerated() {
                if k < existing.count {
                    let lid = existing[k]
                    tx.update(lid) { $0.name = w.0; $0.level?.elevation = w.1 }
                    for v in tx.model.views where v.levelID == lid { tx.update(v.id) { $0.name = w.0 } }
                } else {
                    let lid = tx.create(.levels, name: w.0, data: .level(LevelData(elevation: w.1)))
                    var fp = ViewData(kind: .floorPlan, scale: 100); fp.phaseID = phase
                    tx.create(.views, name: w.0, data: .view(fp), levelID: lid)
                }
            }
            for lid in existing.dropFirst(wanted.count) {
                for v in tx.model.views where v.levelID == lid { tx.delete(v.id) }
                tx.delete(lid)
            }
            model = try tx.commit().model
            ids.levels = model.levels.map(\.id)
        }
        // Imperial plans at 1/4" = 1'-0", metric at 1:100; an empty starter sheet is removed (create_sheet makes sheets).
        let tx = TransactionContext(model: model, name: "Setup")
        for v in tx.model.views where v.view?.kind.isPlan == true || v.view?.kind == .elevation { tx.update(v.id) { $0.view?.scale = units.system == .imperial ? 48 : 100 } }
        for s in tx.model.sheets where tx.model.owned(byView: s.id).allSatisfy({ $0.category != .viewports }) && s.name == "Unnamed" { tx.delete(s.id) }
        tx.update(tx.model.projectInfoElement!.id) { $0.projectInfo?.buildingName = name }
        model = try tx.commit().model
        try host.adopt(model, name: name)
        var o: [String: JSONValue] = ["document": .string(name), "backend": .string(host.backendName), "unit": .string(ToolContext.unitScale(model).symbol)]
        if let p = c.args.string("path") { o["path"] = .string(try await host.save(to: Self.url(p)).path) }
        o["levels"] = .array(model.levels.sorted { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) }.map {
            ["id": $0.id.json, "name": .string($0.name), "elevation": c.out($0.level?.elevation ?? 0, model)]
        })
        o["views"] = .array(model.views.filter { $0.view?.kind != .threeD || $0.name == "{3D}" }.map { .string("\($0.name) (\($0.view?.kind.rawValue ?? ""))") })
        o["next"] = "create_walls on each level, then place_doors / place_windows, create_floor, create_roof, place_rooms."
        return ToolOutput(.object(o))
    }

    func createFurniture(_ c: ToolContext) async throws -> ToolOutput {
        let name = try c.args.requireString("name")
        let cat: FamilyTemplate = c.args.string("category")?.lowercased() == "casework" ? .casework : .furniture
        var model = FurnitureTemplates.blank(category: cat, name: name)
        let tx = TransactionContext(model: model, name: "Size")
        let inch = 0.0254
        for (key, def) in [("width", 36.0), ("depth", 18.0), ("height", 30.0)] {
            var v = def * inch
            if let a = c.args[key] {
                if let d = a.doubleValue { v = d * inch } else if let s = a.stringValue {
                    if let d = Double(s) { v = d * inch } else if let d = try? QuantityParser.parse(s, kind: .length, units: .imperial) { v = d } else { throw ToolError("\(key): can't read “\(s)”.") }
                }
            }
            guard v > 0.01 else { throw ToolError("\(key) must be at least 1/2\".") }
            try FurnitureParameters.setValue(key.capitalized, .double(v), in: tx)
        }
        model = try tx.commit().model
        try host.adopt(model, name: name)
        var o: [String: JSONValue] = ["document": .string(name), "backend": .string(host.backendName), "unit": "in", "category": .string(cat.rawValue)]
        o["planes"] = .object(FurniturePlanes.positionsByName(model).mapValues { c.out($0, model) })
        if let p = c.args.string("path") { o["path"] = .string(try await host.save(to: Self.url(p)).path) }
        o["next"] = "add_furniture_parts (sides, top, bottom, shelves, back, legs…), then render_view {view:'3D'} or the shop drawing sheet."
        return ToolOutput(.object(o))
    }

    func openDocument(_ c: ToolContext) throws -> ToolOutput {
        let url = Self.url(try c.args.requireString("path"))
        try host.open(url)
        return try status(c)
    }

    func save(_ c: ToolContext) async throws -> ToolOutput {
        let m = try c.model()
        var url = c.args.string("path").map(Self.url)
        if let u = url {
            let ext = FileDocumentHost.fileExtension(m)
            if u.pathExtension != ext { url = u.deletingPathExtension().appendingPathExtension(ext) }
        }
        let saved = try await host.save(to: url)
        return ToolOutput(["path": .string(saved.path), "elements": .int(try c.model().count)])
    }

    func setProjectInfo(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        guard let info = m.projectInfoElement else { throw ToolError("This document has no project information.") }
        let a = c.args
        try c.edit("Project Information") { tx in
            tx.update(info.id) { e in
                guard var p = e.projectInfo else { return }
                if let v = a.string("name") { p.projectName = v; e.name = "Project Information" }
                if let v = a.string("number") { p.projectNumber = v }
                if let v = a.string("client") { p.clientName = v }
                if let v = a.string("address") { p.address = v }
                if let v = a.string("status") { p.status = v }
                if let v = a.string("issue_date") { p.issueDate = v }
                if let v = a.string("building_name") { p.buildingName = v }
                if let v = a.string("author") { p.author = v }
                if let v = a.string("organization") { p.organization = v }
                e.projectInfo = p
            }
        }
        let p = try c.model().projectInfo
        return result(c, ["name": .string(p.projectName), "number": .string(p.projectNumber), "client": .string(p.clientName), "address": .string(p.address),
                          "status": .string(p.status), "issue_date": .string(p.issueDate)], ids: [])
    }
}
