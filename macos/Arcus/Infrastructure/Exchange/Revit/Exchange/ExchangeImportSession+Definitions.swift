import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// Materials, levels, grids, system types, families and project information.
extension ExchangeImportSession {
    func clean(_ s: String?, max: Int = 200) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return String(t.prefix(max))
    }

    /// The existing element this object would update (nil with the `.duplicate` policy).
    func matchedExisting(_ uniqueId: String?, _ id: String?, _ kind: String) -> ElementID? {
        guard options.existingElements != .duplicate else { return nil }
        return existingByGUID[IFCGUID.deterministic(seed(uniqueId, id, kind)).value]
    }
    func isReimport(_ uniqueId: String?, _ id: String?, _ kind: String) -> Bool { matchedExisting(uniqueId, id, kind) != nil }

    func uniqueName(_ base: String, taken: (String) -> Bool) -> String {
        guard taken(base) else { return base }
        var candidate = "\(base) (Revit)"
        var n = 2
        while taken(candidate) { candidate = "\(base) (Revit \(n))"; n += 1 }
        return candidate
    }

    // MARK: Materials

    static func materialClass(_ s: String?) -> MaterialClass {
        let t = (s ?? "").lowercased()
        if let m = MaterialClass.allCases.first(where: { $0.rawValue.lowercased() == t }) { return m }
        for (key, cls) in [("concrete", MaterialClass.concrete), ("masonry", .masonry), ("brick", .masonry), ("metal", .metal), ("steel", .metal),
                           ("wood", .wood), ("timber", .wood), ("glass", .glass), ("plaster", .plaster), ("gypsum", .plaster),
                           ("insulation", .insulation), ("stone", .stone), ("ceramic", .ceramic), ("tile", .ceramic), ("plastic", .plastic),
                           ("earth", .earth), ("soil", .earth), ("paint", .paint), ("coating", .paint), ("liquid", .liquid), ("gas", .gas)] where t.contains(key) {
            return cls
        }
        return .generic
    }

    static func color(_ s: String?) -> RGBColor? {
        guard var t = s?.trimmingCharacters(in: .whitespaces) else { return nil }
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return RGBColor(hex: v)
    }

    func importMaterials() {
        for m in doc.materials.items {
            guard let xid = m.id else { skip("materials", "material.noId", "A material without an id was skipped.", nil); continue }
            let base = clean(m.name) ?? "Material \(xid)"
            let reimport = isReimport(m.uniqueId, xid, "materials")
            if !reimport, options.reuseMaterialsByName, let existing = tx.model.material(named: base) {
                materialIDs[xid] = existing.id
                report.elementMap[xid] = existing.id
                report.kept["materials", default: 0] += 1
                continue
            }
            let name = reimport ? base : uniqueName(base) { tx.model.material(named: $0) != nil }
            var md = MaterialData(materialClass: Self.materialClass(m.materialClass), color: Self.color(m.color) ?? RGBColor(0.75, 0.75, 0.75),
                                  transparency: min(1, max(0, finite(m.transparency) ?? 0)), description: clean(m.description, max: 2000) ?? "")
            md.manufacturer = clean(m.manufacturer) ?? ""
            md.model = clean(m.model) ?? ""
            md.mark = clean(m.mark) ?? ""
            md.keynote = clean(m.keynote) ?? ""
            md.cost = finite(m.cost) ?? 0
            materialIDs[xid] = upsert("materials", .materials, name: name, data: .material(md), id: xid, uniqueId: m.uniqueId, source: "Material")
        }
    }

    // MARK: Levels and grids

    func importLevels() {
        let items = doc.levels.items.sorted { (finite($0.elevation) ?? 0) < (finite($1.elevation) ?? 0) }
        for l in items {
            guard let xid = l.id, let elev = finite(l.elevation) else {
                skip("levels", "level.invalid", "\(label("Level", l.id)) has no id or elevation and was skipped.", l.id); continue
            }
            let base = clean(l.name) ?? "Level \(ExchangeFamilyConverter.fmt((elev * 1000).rounded() / 1000))"
            let reimport = isReimport(l.uniqueId, xid, "levels")
            if !reimport, options.mergeLevelsByName, let ex = tx.model.level(named: base), abs((ex.level?.elevation ?? .nan) - elev) <= 0.001 {
                levelIDs[xid] = ex.id
                report.elementMap[xid] = ex.id
                report.kept["levels", default: 0] += 1
                continue
            }
            let matched = matchedExisting(l.uniqueId, xid, "levels")
            let name = uniqueName(base) { n in tx.model.levels.contains { $0.name == n && $0.id != matched } }
            if name != base { warn("level.renamed", "Level “\(base)” was renamed “\(name)” because the model already has a level with that name.", xid) }
            let ld = LevelData(elevation: elev, isBuildingStorey: l.isBuildingStorey ?? true, isStructural: l.isStructural ?? false)
            let before = report.created["levels"] ?? 0
            let id = upsert("levels", .levels, name: name, data: .level(ld), id: xid, uniqueId: l.uniqueId, source: "Level")
            levelIDs[xid] = id
            if (report.created["levels"] ?? 0) > before, options.createPlanViews,
               !tx.model.views.contains(where: { $0.name == name && $0.view?.kind == .floorPlan }) {
                var v = ViewData(kind: .floorPlan, scale: 100)
                v.phaseID = tx.model.latestPhase?.id
                let vid = tx.create(.views, name: name, data: .view(v), levelID: id)
                report.created["views", default: 0] += 1
                touched.append((vid, "views", true))
            }
        }
    }

    func importGrids() {
        for g in doc.grids.items {
            guard let c = curve(g.curve) else {
                skip("grids", "grid.invalid", "\(label("Grid", g.id)) has no usable line or arc and was skipped.", g.id); continue
            }
            let base = clean(g.name) ?? "G\((report.created["grids"] ?? 0) + 1)"
            let matched = matchedExisting(g.uniqueId, g.id, "grids")
            let name = uniqueName(base) { n in tx.model.elements(.grids).contains { $0.name == n && $0.id != matched } }
            if name != base { warn("grid.renamed", "Grid “\(base)” was renamed “\(name)” because the model already has a grid with that name.", g.id) }
            var gd = GridData(curve: c)
            gd.bottomElevation = finite(g.bottomElevation)
            gd.topElevation = finite(g.topElevation)
            upsert("grids", .grids, name: name, data: .grid(gd), id: g.id, uniqueId: g.uniqueId, source: "Grid")
        }
    }

    // MARK: System types

    static func layerFunction(_ s: String?) -> LayerFunction {
        switch (s ?? "").lowercased() {
        case "structure", "structuraldeck": .structure
        case "substrate": .substrate
        case "thermal", "insulation", "thermal/air layer": .thermal
        case "membrane": .membrane
        case "finish1", "finish 1": .finish1
        case "finish2", "finish 2": .finish2
        default: .structure
        }
    }

    static func wrapping(_ s: String?) -> WrappingPreference {
        switch (s ?? "").lowercased() {
        case "exterior": .exterior
        case "interior": .interior
        case "both", "exteriorandinterior": .both
        default: .doNotWrap
        }
    }

    func assembly(_ t: XType) -> CompoundAssembly? {
        var layers: [AssemblyLayer] = []
        var origIndex: [Int] = []
        var dropped = 0
        for (i, l) in (t.layers ?? []).enumerated() {
            let f = Self.layerFunction(l.function)
            let mat = l.materialId.flatMap { materialIDs[$0] }
            if f == .membrane {
                layers.append(AssemblyLayer(function: .membrane, materialID: mat, thickness: 0))
            } else if let th = finite(l.thickness), th > Tolerance.length {
                var al = AssemblyLayer(function: f, materialID: mat, thickness: th, wraps: l.wraps ?? false)
                al.isVariable = l.isVariable ?? false
                layers.append(al)
            } else {
                dropped += 1
                continue
            }
            origIndex.append(i)
        }
        if dropped > 0 { approximate("types", "type.layerDropped", "Type “\(t.name ?? "?")”: \(dropped) layer\(dropped == 1 ? "" : "s") without thickness were left out.", t.id) }
        if layers.isEmpty {
            guard let th = finite(t.thickness), th > Tolerance.length else { return nil }
            layers = [AssemblyLayer(function: .structure, materialID: t.materialId.flatMap { materialIDs[$0] }, thickness: th)]
            origIndex = [0]
        }
        // Core range in original indices (explicit range, else per-layer flags).
        var core: Set<Int> = []
        if let s = t.coreStart, let e = t.coreEnd, s >= 0, e > s, e <= 10_000 { core = Set(s..<e) }
        else { for (i, l) in (t.layers ?? []).enumerated() where l.isCore == true { core.insert(i) } }
        let newCore = origIndex.enumerated().filter { core.contains($0.element) }.map(\.offset)
        var a = CompoundAssembly(layers: layers, coreStart: newCore.first, coreEnd: newCore.last.map { $0 + 1 })
        if a.validate() != nil { a = CompoundAssembly(layers: layers) }
        if let err = a.validate() {
            warn("type.assembly", "Type “\(t.name ?? "?")” has an invalid layer structure (\(err)).", t.id)
            return nil
        }
        a.wrappingAtInserts = Self.wrapping(t.wrappingAtInserts)
        a.wrappingAtEnds = Self.wrapping(t.wrappingAtEnds)
        return a
    }

    func typeParams(_ t: XType) -> [ParameterID: ParamValue] {
        var p: [ParameterID: ParamValue] = [:]
        if let v = clean(t.typeMark) { p[ParameterID("type.mark")] = .text(v) }
        if let v = clean(t.description, max: 2000) { p[ParameterID("type.description")] = .text(v) }
        if let v = clean(t.fireRating) { p[ParameterID("type.fireRating")] = .text(v) }
        if let v = clean(t.function) { p[ParameterID("type.function")] = .text(v) }
        if let m = t.materialId.flatMap({ materialIDs[$0] }) { p[ParameterID("type.material")] = .ref(m) }
        return p
    }

    func createType(_ t: XType, _ xid: String, category: ArcusDomain.Category, data td: TypeData) {
        let base = clean(t.name) ?? "\(category.singularName) \(xid)"
        let reimport = isReimport(t.uniqueId, xid, "types")
        if !reimport, let a = td.assembly,
           let same = tx.model.types(for: category).first(where: { $0.name == base && $0.typeData?.assembly.map { sameAssembly($0, a) } == true }) {
            typeIDs[xid] = same.id
            report.elementMap[xid] = same.id
            report.kept["types", default: 0] += 1
            return
        }
        let matched = matchedExisting(t.uniqueId, xid, "types")
        let name = uniqueName(base) { n in tx.model.types(for: category).contains { $0.name == n && $0.id != matched } }
        typeIDs[xid] = upsert("types", .elementTypes, name: name, data: .type(td), id: xid, uniqueId: t.uniqueId, source: "\(category.singularName) Type")
    }

    func sameAssembly(_ a: CompoundAssembly, _ b: CompoundAssembly) -> Bool {
        guard a.layers.count == b.layers.count else { return false }
        for (x, y) in zip(a.layers, b.layers) {
            guard x.function == y.function, abs(x.thickness - y.thickness) <= 0.0005 else { return false }
            if x.materialID.flatMap({ tx.model[$0]?.name }) != y.materialID.flatMap({ tx.model[$0]?.name }) { return false }
        }
        return true
    }

    func importSystemTypes() {
        for t in doc.types.items {
            guard let xid = t.id else { skip("types", "type.noId", "A type without an id was skipped.", nil); continue }
            systemTypes[xid] = t
            var params = typeParams(t)
            let cat = t.category ?? ""
            func compound(_ c: ArcusDomain.Category, _ f: SystemFamily, _ family: String) {
                guard let a = assembly(t) else {
                    skip("types", "type.noLayers", "Type “\(t.name ?? xid)” has no usable layers or thickness and was skipped.", xid); return
                }
                createType(t, xid, category: c, data: TypeData(instanceCategory: c, systemFamily: f, familyName: clean(t.familyName) ?? family, params: params, assembly: a))
            }
            switch cat {
            case "walls":
                let kind = (t.kind ?? "basic").lowercased()
                if kind != "basic" {
                    unsupportedWallTypes.insert(xid)
                    warn("type.wallKind", "Wall type “\(t.name ?? xid)” is a \(kind) wall, which Arcus can't model natively; its walls are imported as reference geometry when the file includes their shape.", xid)
                    continue
                }
                compound(.walls, .basicWall, "Basic Wall")
            case "floors": compound(.floors, .floor, "Floor")
            case "ceilings": compound(.ceilings, .ceiling, "Compound Ceiling")
            case "roofs": compound(.roofs, .roof, "Basic Roof")
            case "buildingPads": compound(.buildingPads, .buildingPad, "Building Pad")
            case "columns", "structuralColumns":
                let c: ArcusDomain.Category = cat == "columns" ? .columns : .structuralColumns
                let s = t.section
                if (s?.shape ?? "").lowercased() == "circle", let d = finite(s?.diameter), d > Tolerance.length {
                    params[ParameterID("column.diameter")] = .double(d)
                } else if let w = finite(s?.width), let d = finite(s?.depth), w > Tolerance.length, d > Tolerance.length {
                    params[ParameterID("column.width")] = .double(w)
                    params[ParameterID("column.depth")] = .double(d)
                } else {
                    params[ParameterID("column.width")] = .double(0.4)
                    params[ParameterID("column.depth")] = .double(0.4)
                    approximate("types", "type.section", "Column type “\(t.name ?? xid)” has no section size; 400 × 400 mm was used.", xid)
                }
                createType(t, xid, category: c, data: TypeData(instanceCategory: c, familyName: clean(t.familyName) ?? (c == .columns ? "Column" : "Structural Column"), params: params))
            case "structuralFraming":
                let w = finite(t.section?.width) ?? 0, d = finite(t.section?.depth) ?? 0
                if w > Tolerance.length, d > Tolerance.length {
                    params[ParameterID("beam.width")] = .double(w); params[ParameterID("beam.depth")] = .double(d)
                } else {
                    params[ParameterID("beam.width")] = .double(0.3); params[ParameterID("beam.depth")] = .double(0.5)
                    approximate("types", "type.section", "Beam type “\(t.name ?? xid)” has no section size; 300 × 500 mm was used.", xid)
                }
                createType(t, xid, category: .structuralFraming, data: TypeData(instanceCategory: .structuralFraming, familyName: clean(t.familyName) ?? "Beam", params: params))
            case "stairs":
                let s = t.stair
                params[ParameterID("stair.maxRiser")] = .double(finite(s?.maxRiserHeight).map { max(0.1, $0) } ?? 0.18)
                params[ParameterID("stair.minTread")] = .double(finite(s?.minTreadDepth).map { max(0.18, $0) } ?? 0.28)
                params[ParameterID("stair.treadThickness")] = .double(finite(s?.treadThickness) ?? 0.04)
                params[ParameterID("stair.waist")] = .double(finite(s?.waist) ?? 0.15)
                createType(t, xid, category: .stairs, data: TypeData(instanceCategory: .stairs, systemFamily: .stair, familyName: clean(t.familyName) ?? "Assembled Stair", params: params))
            case "railings":
                let r = t.railing
                params[ParameterID("railing.height")] = .double(finite(r?.height) ?? 1.0)
                params[ParameterID("railing.balusterSpacing")] = .double(finite(r?.balusterSpacing) ?? 0.12)
                params[ParameterID("railing.balusterSize")] = .double(finite(r?.balusterSize) ?? 0.02)
                params[ParameterID("railing.railSize")] = .double(finite(r?.railSize) ?? 0.05)
                createType(t, xid, category: .railings, data: TypeData(instanceCategory: .railings, systemFamily: .railing, familyName: clean(t.familyName) ?? "Railing", params: params))
            default:
                skip("types", "type.category", "Type “\(t.name ?? xid)” has category “\(cat)”, which is not an Arcus system type; it was skipped.", xid)
            }
        }
    }

    /// A shared fallback type for instances whose type is missing.
    func fallbackType(_ category: ArcusDomain.Category) -> ElementID {
        if let t = fallbackTypes[category.rawValue] { return t }
        let td: TypeData
        let concrete = tx.model.material(named: "Concrete, Cast-in-Place")?.id
        switch category {
        case .walls: td = TypeData(instanceCategory: .walls, systemFamily: .basicWall, familyName: "Basic Wall", assembly: CompoundAssembly(layers: [AssemblyLayer(function: .structure, materialID: concrete, thickness: 0.2)]))
        case .floors: td = TypeData(instanceCategory: .floors, systemFamily: .floor, familyName: "Floor", assembly: CompoundAssembly(layers: [AssemblyLayer(function: .structure, materialID: concrete, thickness: 0.2)]))
        case .ceilings: td = TypeData(instanceCategory: .ceilings, systemFamily: .ceiling, familyName: "Compound Ceiling", assembly: CompoundAssembly(layers: [AssemblyLayer(function: .finish1, materialID: nil, thickness: 0.0125)]))
        case .roofs: td = TypeData(instanceCategory: .roofs, systemFamily: .roof, familyName: "Basic Roof", assembly: CompoundAssembly(layers: [AssemblyLayer(function: .structure, materialID: nil, thickness: 0.25)]))
        case .stairs: td = TypeData(instanceCategory: .stairs, systemFamily: .stair, familyName: "Assembled Stair", params: [ParameterID("stair.maxRiser"): .double(0.19), ParameterID("stair.minTread"): .double(0.25)])
        case .railings: td = TypeData(instanceCategory: .railings, systemFamily: .railing, familyName: "Railing", params: [ParameterID("railing.height"): .double(1.0)])
        case .structuralFraming: td = TypeData(instanceCategory: .structuralFraming, familyName: "Beam", params: [ParameterID("beam.width"): .double(0.3), ParameterID("beam.depth"): .double(0.5)])
        default: td = TypeData(instanceCategory: category, familyName: category.singularName, params: [ParameterID("column.width"): .double(0.4), ParameterID("column.depth"): .double(0.4)])
        }
        let name = uniqueName("Imported \(category.singularName) (type missing)") { n in tx.model.types(for: category).contains { $0.name == n } }
        let id = tx.create(.elementTypes, name: name, data: .type(td))
        report.created["types", default: 0] += 1
        touched.append((id, "types", true))
        fallbackTypes[category.rawValue] = id
        return id
    }

    /// Resolves an instance's type, checking its category; uses (and reports) a fallback type when missing.
    func systemType(_ xid: String?, _ category: ArcusDomain.Category, _ what: String, _ source: String?) -> ElementID {
        if let xid, let t = typeIDs[xid], let td = tx.model[t]?.typeData,
           td.instanceCategory == category || (category == .structuralColumns && td.instanceCategory == .columns) {
            return t
        }
        approximate(category.rawValue, "ref.type", "\(what) refers to a type that was not imported; a generic type was used.", source)
        return fallbackType(category)
    }

    // MARK: Families

    func importFamilies() {
        let names = Dictionary(doc.materials.items.compactMap { m in m.id.map { ($0, m.name ?? $0) } }, uniquingKeysWith: { a, _ in a })
        for (k, f) in doc.families.items.enumerated() {
            let fxid = f.id ?? "family-\(k + 1)"
            let conv = ExchangeFamilyConverter.convert(f, materialName: { names[$0] }, options: options)
            for w in conv.warnings { warn("family", w, fxid) }
            if conv.approximated > 0 { report.approximated["family items", default: 0] += conv.approximated }
            if conv.skipped > 0 { report.skipped["family items", default: 0] += conv.skipped }
            var def = conv.definition
            let matched = matchedExisting(f.uniqueId, fxid, "families")
            def.name = uniqueName(def.name) { n in tx.model.elements(.families).contains { $0.name == n && $0.id != matched } }
            let famID = upsert("families", .families, name: def.name, data: .family(def), id: fxid, uniqueId: f.uniqueId, source: f.revitCategory ?? "Family")
            report.familyDefinitions.append(def)
            if conv.synthesized { report.approximated["families", default: 0] += 1 }
            let info = FamilyInfo(familyElement: famID, definition: def, category: conv.instanceCategory, hasGeometry: conv.hasGeometry)
            // Project types, one per family type (exchange ids map to Arcus type names).
            var byName: [String: (id: String, x: XFamilyType?)] = [:]
            for (xid, n) in conv.typeNames { byName[n] = (xid, conv.typeExtras[xid]) }
            for t in def.types {
                let entry = byName[t.name]
                let txid = entry?.id ?? "\(fxid)/\(t.name)"
                var params: [ParameterID: ParamValue] = [:]
                for (k, v) in t.values { params[Parameters.familyParamID(k)] = v }
                for (p, mid) in conv.typeMaterials[t.name] ?? [:] {
                    if let m = materialIDs[mid] { params[Parameters.familyParamID(p)] = .ref(m) } else {
                        warn("ref.material", "Family “\(def.name)” type “\(t.name)”: material “\(mid)” of “\(p)” was not in the file.", txid)
                    }
                }
                for (p, mid) in conv.fixedMaterials { if let m = materialIDs[mid] { params[Parameters.familyParamID(p)] = .ref(m) } }
                if let x = entry?.x {
                    if let v = clean(x.typeMark) { params[ParameterID("type.mark")] = .text(v) }
                    if let v = clean(x.description, max: 2000) { params[ParameterID("type.description")] = .text(v) }
                    if let v = clean(x.fireRating) { params[ParameterID("type.fireRating")] = .text(v) }
                }
                let td = TypeData(instanceCategory: conv.instanceCategory, familyID: famID, familyName: def.name, params: params)
                let tid = upsert("types", .elementTypes, name: t.name, data: .type(td), id: txid, uniqueId: entry?.x?.uniqueId, source: "Family Type")
                typeIDs[txid] = tid
                familyOfType[txid] = info
            }
        }
    }

    // MARK: Project information

    func importProjectInfo() {
        guard report.documentKind == .project, options.applyProjectInfo || options.applyUnits else { return }
        var info = tx.model.projectInfo
        let before = info
        if options.applyProjectInfo, let p = doc.projectInfo {
            if let v = clean(p.name) { info.projectName = v }
            if let v = clean(p.number) { info.projectNumber = v }
            if let v = clean(p.clientName) { info.clientName = v }
            if let v = clean(p.address, max: 2000) { info.address = v }
            if let v = clean(p.status) { info.status = v }
            if let v = clean(p.issueDate) { info.issueDate = v }
            if let v = clean(p.author) { info.author = v }
            if let v = clean(p.organization) { info.organization = v }
            if let v = clean(p.buildingName) { info.buildingName = v }
            if let v = clean(p.siteName) { info.siteName = v }
            if let v = finite(p.latitude), abs(v) <= 90 { info.latitude = v }
            if let v = finite(p.longitude), abs(v) <= 180 { info.longitude = v }
            if let v = finite(p.elevation) { info.elevationAboveSeaLevel = v }
            if let v = finite(p.trueNorthAngle) { info.trueNorthAngle = v }
            if let v = vec3(p.projectBasePoint) { info.projectBasePoint = v }
            if let v = vec3(p.surveyPoint) { info.surveyPoint = v }
        }
        if options.applyUnits, let sys = doc.units?.system?.lowercased() {
            info.units = sys == "imperial" ? .imperial : .metric
            if let l = doc.units?.length, let ld = LengthDisplay.allCases.first(where: { $0.rawValue.lowercased() == l.lowercased() }) { info.units.length = ld }
        }
        guard info != before else { return }
        if let e = tx.model.projectInfoElement {
            tx.update(e.id) { $0.projectInfo = info }
            report.updated["project information", default: 0] += 1
        } else {
            let id = tx.create(.projectInfo, name: "Project Information", data: .projectInfo(info))
            report.created["project information", default: 0] += 1
            touched.append((id, "project information", true))
        }
    }
}
