import Foundation
import ArcusGeometry
import ArcusDomain

extension IFCImportSession {
    /// Creates levels, materials, types and elements from the analysis. Never throws.
    func apply(to tx: TransactionContext) {
        let a = IFCImportApplier(session: self, tx: tx)
        a.run()
        report.nativeCounts = a.nativeCounts
        report.referenceCounts = a.referenceCounts
        for w in a.warnings where !report.warnings.contains(w) { report.warnings.append(w) }
    }
}

final class IFCImportApplier {
    let s: IFCImportSession
    let tx: TransactionContext
    var nativeCounts: [String: Int] = [:]
    var referenceCounts: [String: Int] = [:]
    var warnings: [String] = []
    private var usedGUIDs: Set<String>
    private var levelForStorey: [Int: ElementID] = [:]
    private var materialCache: [String: ElementID] = [:]
    private var wallIDs: [Int: ElementID] = [:]
    private var duplicateGUIDs = 0

    init(session: IFCImportSession, tx: TransactionContext) {
        s = session
        self.tx = tx
        usedGUIDs = Set(tx.model.allElements.map(\.ifcGUID.value))
    }

    func count(_ c: ArcusDomain.Category) { nativeCounts[c.rawValue, default: 0] += 1 }
    func warn(_ w: String) { if !warnings.contains(w) { warnings.append(w) } }

    func guid(_ raw: String, entity: Int) -> IFCGUID {
        if let g = IFCGUID(raw), !usedGUIDs.contains(raw) {
            usedGUIDs.insert(raw)
            return g
        }
        if IFCGUID(raw) != nil { duplicateGUIDs += 1 }
        var seed = "\(s.fileName)/#\(entity)/\(raw)"
        var g = IFCGUID.deterministic(seed)
        while usedGUIDs.contains(g.value) { seed += "+"; g = IFCGUID.deterministic(seed) }
        usedGUIDs.insert(g.value)
        return g
    }

    func run() {
        createLevels()
        for id in s.wallOrder { if let w = s.walls[id] { createWall(w, entity: id) } }
        for f in s.floors { createFloor(f) }
        for c in s.columns { createColumn(c) }
        for b in s.beams { createBeam(b) }
        for sp in s.spaces { createRoom(sp) }
        for i in s.inserts { createInsert(i) }
        for r in s.references { createReference(r.product, mesh: r.mesh) }
        if duplicateGUIDs > 0 {
            warn("\(duplicateGUIDs) GlobalId\(duplicateGUIDs == 1 ? " was" : "s were") already used in the model or repeated in the file; new GlobalIds were assigned.")
        }
    }

    // MARK: Levels

    func createLevels() {
        let tol = s.options.targetLevelMatchTolerance
        for st in s.storeys {
            if let existing = tx.model.levels.first(where: { abs(($0.level?.elevation ?? 0) - st.elevation) <= tol }) {
                levelForStorey[st.entity] = existing.id
                continue
            }
            var name = st.name.isEmpty ? "Level \(STEPFormat.shortReal((st.elevation * 1000).rounded() / 1000))" : st.name
            let names = Set(tx.model.levels.map(\.name))
            if names.contains(name) {
                var k = 1
                var candidate = "\(name) (IFC)"
                while names.contains(candidate) { k += 1; candidate = "\(name) (IFC \(k))" }
                name = candidate
            }
            let id = tx.create(.levels, name: name, data: .level(LevelData(elevation: st.elevation)), ifcGUID: guid(st.guid, entity: st.entity))
            levelForStorey[st.entity] = id
            count(.levels)
            if !tx.model.views.contains(where: { $0.name == name && $0.view?.kind == .floorPlan }) {
                var v = ViewData(kind: .floorPlan, scale: 100)
                v.phaseID = tx.model.latestPhase?.id
                tx.create(.views, name: name, data: .view(v), levelID: id)
                count(.views)
            }
        }
    }

    /// Level for a product: its storey, else the highest level at or below `z`, else the lowest level.
    func level(storey: Int?, z: Double?) -> ElementID {
        if let st = storey, let l = levelForStorey[st] { return l }
        let levels = tx.model.levels
        if levels.isEmpty {
            let id = tx.create(.levels, name: "Level 1", data: .level(LevelData(elevation: 0)))
            count(.levels)
            return id
        }
        if storey == nil { warn("Some elements are not contained in a building storey; they were assigned to the level below them.") }
        if let z, let l = levels.last(where: { ($0.level?.elevation ?? 0) <= z + 1e-3 }) { return l.id }
        return levels[0].id
    }

    func elevation(_ l: ElementID) -> Double { tx.model.elevation(ofLevel: l) }

    // MARK: Materials and types

    func material(_ name: String?, category: String?, color: RGBColor?) -> ElementID? {
        guard let name, !name.isEmpty else { return nil }
        if let id = materialCache[name] { return id }
        if let m = tx.model.material(named: name) { materialCache[name] = m.id; return m.id }
        let cls = category.flatMap { MaterialClass(rawValue: $0) } ?? .generic
        let id = tx.create(.materials, name: name, data: .material(MaterialData(materialClass: cls, color: color ?? RGBColor(0.75, 0.75, 0.75))))
        materialCache[name] = id
        count(.materials)
        return id
    }

    func assembly(_ layers: [LayerSpec], color: RGBColor?) -> CompoundAssembly {
        var out: [AssemblyLayer] = []
        for l in layers {
            let f = l.function ?? .structure
            if f == .membrane {
                out.append(AssemblyLayer(function: .membrane, materialID: material(l.materialName, category: l.materialCategory, color: color), thickness: 0))
            } else if l.thickness > 1e-5 {
                out.append(AssemblyLayer(function: f, materialID: material(l.materialName, category: l.materialCategory, color: color), thickness: l.thickness))
            }
        }
        return CompoundAssembly(layers: out)
    }

    static func mm(_ m: Double) -> String {
        let v = (m * 10000).rounded() / 10
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    func uniqueTypeName(_ base: String, category: ArcusDomain.Category) -> String {
        let names = Set(tx.model.types(for: category).map(\.name))
        guard names.contains(base) else { return base }
        var k = 2
        while names.contains("\(base) (\(k))") { k += 1 }
        return "\(base) (\(k))"
    }

    func sameAssembly(_ a: CompoundAssembly, _ b: CompoundAssembly) -> Bool {
        guard a.layers.count == b.layers.count else { return false }
        for (x, y) in zip(a.layers, b.layers) {
            guard abs(x.thickness - y.thickness) <= 0.0005 else { return false }
            let nx = x.materialID.flatMap { tx.model[$0]?.name }, ny = y.materialID.flatMap { tx.model[$0]?.name }
            if nx != ny { return false }
        }
        return true
    }

    /// Finds or creates a compound (wall/floor) type.
    func compoundType(category: ArcusDomain.Category, family: SystemFamily, familyName: String, thickness: Double, layers: [LayerSpec], typeName: String?, color: RGBColor?) -> ElementID {
        if let n = typeName, let t = tx.model.type(category: category, name: n), let a = t.typeData?.assembly, abs(a.totalThickness - thickness) <= 0.0005 {
            return t.id
        }
        let asm = assembly(layers, color: color)
        if let t = tx.model.types(for: category).first(where: { $0.typeData?.assembly.map { sameAssembly($0, asm) } ?? false }) {
            return t.id
        }
        let name = uniqueTypeName(typeName.flatMap { $0.isEmpty ? nil : $0 } ?? "Imported \(Self.mm(thickness)) mm", category: category)
        let id = tx.create(.elementTypes, name: name, data: .type(TypeData(instanceCategory: category, systemFamily: family, familyName: familyName, assembly: asm)))
        count(.elementTypes)
        return id
    }

    func configure(_ info: ProductInfo) -> (inout Element) -> Void {
        let schema = s.schema, file = s.fileName
        return { e in
            e.source = SourceMetadata(format: schema, fileName: file, originalID: info.guid, originalType: info.cls, attributes: info.properties)
            if let m = info.properties["Arcus_Parameters.Mark"] ?? (info.tag.isEmpty ? nil : info.tag) { e.mark = m }
            if let c = info.properties["Arcus_Parameters.Comments"] { e.comments = c }
            e.classification = info.classification
        }
    }

    // MARK: Native elements

    func createWall(_ w: WallSpec, entity: Int) {
        let lv = level(storey: w.product.storey, z: w.baseZ)
        let type = compoundType(category: .walls, family: .basicWall, familyName: "Basic Wall", thickness: w.thickness, layers: w.layers,
                                typeName: w.typeName, color: w.product.color)
        var d = WallData(location: .line(w.location), locationLine: .wallCenterline, baseOffset: w.baseZ - elevation(lv), unconnectedHeight: w.height)
        d.flipped = w.flipped
        d.structural = w.product.properties["Pset_WallCommon.LoadBearing"] == "TRUE"
        let id = tx.create(.walls, data: .wall(d), typeID: type, levelID: lv, ifcGUID: guid(w.product.guid, entity: entity), configure: configure(w.product))
        wallIDs[entity] = id
        count(.walls)
    }

    func createFloor(_ f: FloorSpec) {
        let lv = level(storey: f.product.storey, z: f.topZ - f.thickness)
        let type = compoundType(category: .floors, family: .floor, familyName: "Floor", thickness: f.thickness, layers: f.layers, typeName: f.typeName,
                                color: f.product.color)
        var d = SlabData(boundary: f.sketch, offset: f.topZ - elevation(lv))
        d.structural = f.product.properties["Pset_SlabCommon.LoadBearing"] == "TRUE"
        tx.create(.floors, data: .slab(d), typeID: type, levelID: lv, ifcGUID: guid(f.product.guid, entity: f.product.entity.id), configure: configure(f.product))
        count(.floors)
    }

    func createRoom(_ sp: SpaceSpec) {
        let lv = level(storey: sp.product.storey, z: sp.baseZ)
        var d = RoomData(point: sp.point, number: sp.number, limitOffset: sp.height)
        d.baseOffset = sp.baseZ - elevation(lv)
        tx.create(.rooms, name: sp.roomName, data: .room(d), levelID: lv, ifcGUID: guid(sp.product.guid, entity: sp.product.entity.id), configure: configure(sp.product))
        count(.rooms)
    }

    func createColumn(_ c: ColumnSpec) {
        let lv = level(storey: c.product.storey, z: c.baseZ)
        var rotation = c.rotation
        let tol = 0.0005
        func len(_ t: Element, _ k: String) -> Double { t.typeData?.params[ParameterID(k)]?.doubleValue ?? 0 }
        var typeID: ElementID?
        for t in tx.model.types(for: .columns) where t.typeData?.familyID == nil {
            if c.diameter > 0 {
                if abs(len(t, "column.diameter") - c.diameter) <= 0.002 { typeID = t.id; break }
            } else if len(t, "column.diameter") <= tol {
                if abs(len(t, "column.width") - c.width) <= tol && abs(len(t, "column.depth") - c.depth) <= tol { typeID = t.id; break }
                if abs(len(t, "column.width") - c.depth) <= tol && abs(len(t, "column.depth") - c.width) <= tol { typeID = t.id; rotation += .pi / 2; break }
            }
        }
        if typeID == nil {
            let name = c.diameter > 0 ? "Imported Round \(Self.mm(c.diameter))" : "Imported \(Self.mm(c.width)) x \(Self.mm(c.depth))"
            var params: [ParameterID: ParamValue] = [ParameterID("column.width"): .double(c.width), ParameterID("column.depth"): .double(c.depth),
                                                     ParameterID("column.diameter"): .double(c.diameter)]
            if let m = material(s.layers(for: c.product).layers.first?.materialName, category: nil, color: c.product.color) { params[ParameterID("type.material")] = .ref(m) }
            typeID = tx.create(.elementTypes, name: uniqueTypeName(name, category: .columns),
                               data: .type(TypeData(instanceCategory: .columns, familyName: "Column", params: params)))
            count(.elementTypes)
        }
        let d = ColumnData(location: c.center, rotation: rotation, baseOffset: c.baseZ - elevation(lv), unconnectedHeight: c.height)
        tx.create(.columns, data: .column(d), typeID: typeID, levelID: lv, ifcGUID: guid(c.product.guid, entity: c.product.entity.id), configure: configure(c.product))
        count(.columns)
    }

    func createBeam(_ b: BeamSpec) {
        let lv = level(storey: b.product.storey, z: b.topZ - b.depth)
        let tol = 0.0005
        func len(_ t: Element, _ k: String) -> Double { t.typeData?.params[ParameterID(k)]?.doubleValue ?? 0 }
        var typeID = tx.model.types(for: .structuralFraming).first { abs(len($0, "beam.width") - b.width) <= tol && abs(len($0, "beam.depth") - b.depth) <= tol }?.id
        if typeID == nil {
            var params: [ParameterID: ParamValue] = [ParameterID("beam.width"): .double(b.width), ParameterID("beam.depth"): .double(b.depth)]
            if let m = material(s.layers(for: b.product).layers.first?.materialName, category: nil, color: b.product.color) { params[ParameterID("type.material")] = .ref(m) }
            typeID = tx.create(.elementTypes, name: uniqueTypeName("Imported \(Self.mm(b.width)) x \(Self.mm(b.depth))", category: .structuralFraming),
                               data: .type(TypeData(instanceCategory: .structuralFraming, familyName: "Beam", params: params)))
            count(.elementTypes)
        }
        let z = b.topZ - elevation(lv)
        let d = BeamData(curve: .line(b.line), startOffset: z, endOffset: z, zJustification: .top)
        tx.create(.structuralFraming, data: .beam(d), typeID: typeID, levelID: lv, ifcGUID: guid(b.product.guid, entity: b.product.entity.id), configure: configure(b.product))
        count(.structuralFraming)
    }

    func createInsert(_ i: InsertSpec) {
        guard let hostID = wallIDs[i.hostEntity], let host = tx.model[hostID], let seg = host.wall?.location.asSegment else {
            createReference(i.product, mesh: nil); return
        }
        let template: FamilyTemplate = i.isDoor ? .door : .window
        let category: ArcusDomain.Category = i.isDoor ? .doors : .windows
        var fam = tx.model.family(named: i.familyName)
        if fam?.family?.template != template {
            fam = tx.model.family(named: i.isDoor ? "Door - Single Flush" : "Window - Casement")
                ?? tx.model.elements(.families).first { $0.family?.template == template }
        }
        guard let fam, let def = fam.family else {
            warn("No \(i.isDoor ? "door" : "window") family is loaded; \(i.isDoor ? "doors" : "windows") were imported as reference geometry.")
            createReference(i.product, mesh: s.geo.bodyMesh(of: i.product.entity)); return
        }
        let wID = Parameters.familyParamID("Width"), hID = Parameters.familyParamID("Height")
        let famTypes = tx.model.elements(.elementTypes).filter { $0.typeData?.familyID == fam.id }
        var typeID = famTypes.first {
            abs(($0.typeData?.params[wID]?.doubleValue ?? -1) - i.width) <= 0.0005 && abs(($0.typeData?.params[hID]?.doubleValue ?? -1) - i.height) <= 0.0005
        }?.id
        if typeID == nil {
            var params = famTypes.first?.typeData?.params ?? [:]
            if params.isEmpty, let t = def.types.first { for (k, v) in t.values { params[Parameters.familyParamID(k)] = v } }
            params[wID] = .double(i.width)
            params[hID] = .double(i.height)
            params[ParameterID("type.mark")] = nil
            let name = uniqueTypeName("Imported \(Self.mm(i.width)) x \(Self.mm(i.height))", category: category)
            typeID = tx.create(.elementTypes, name: name, data: .type(TypeData(instanceCategory: category, familyID: fam.id, familyName: fam.name, params: params)))
            count(.elementTypes)
        }
        let t = seg.length > 0 ? min(1, max(0, i.station / seg.length)) : 0
        var d = InsertData(location: seg.point(at: t), sillHeight: i.sill)
        d.handFlipped = i.handFlipped
        d.facingFlipped = i.facingFlipped
        tx.create(category, data: .insert(d), typeID: typeID, levelID: host.levelID, hostID: hostID,
                  ifcGUID: guid(i.product.guid, entity: i.product.entity.id), configure: configure(i.product))
        count(category)
    }

    // MARK: Reference geometry

    func createReference(_ info: ProductInfo, mesh: TriMesh?) {
        let lv = level(storey: info.storey, z: info.minZ)
        let data = ReferenceGeometryData(mesh: mesh?.domainMesh ?? Mesh(), ifcType: info.cls, properties: info.properties)
        tx.create(.ifcReference, name: info.name.isEmpty ? info.cls : info.name, data: .referenceGeometry(data), levelID: lv,
                  ifcGUID: guid(info.guid, entity: info.entity.id), configure: configure(info))
        referenceCounts[info.cls, default: 0] += 1
    }
}
