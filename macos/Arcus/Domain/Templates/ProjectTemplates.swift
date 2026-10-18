import Foundation
import ArcusGeometry
import ArcusCalc

public enum ProjectTemplateKind: String, CaseIterable, Sendable, Codable {
    case architectural = "Architectural"
    case residential = "Residential"
    case empty = "Empty (Units Only)"

    public var summary: String {
        switch self {
        case .architectural: "Commercial and institutional work: masonry and stud walls, concrete floors, A1 sheets, 1:100 plans."
        case .residential: "Houses and apartments: timber-frame walls, suspended floors, pitched-roof types, A3 sheets, 1:50 plans."
        case .empty: "Levels, units and graphics settings only. Load families as you need them."
        }
    }
}

/// Creates new projects from templates. All content is original Arcus content.
public enum ProjectTemplates {
    public struct Ids: Sendable {
        public var levels: [ElementID] = []
        public var materials: [String: ElementID] = [:]
        public var wallTypes: [String: ElementID] = [:]
        public var floorTypes: [String: ElementID] = [:]
        public var roofTypes: [String: ElementID] = [:]
        public var ceilingTypes: [String: ElementID] = [:]
        public var families: [String: ElementID] = [:]
        public var familyTypes: [String: ElementID] = [:]   // "Family: Type"
        public var systemTypes: [String: ElementID] = [:]   // stairs, railings, columns, beams, text, dims…
        public var phases: [ElementID] = []
        public var planViews: [ElementID: ElementID] = [:]  // level → floor plan
        public var ceilingViews: [ElementID: ElementID] = [:]
        public var titleBlocks: [String: ElementID] = [:]
    }

    /// Builds a new model. Returns the model and the ids of the created content.
    public static func make(_ kind: ProjectTemplateKind, units: UnitsSettings, projectName: String = "Untitled Project") -> (BIMModel, Ids) {
        let tx = TransactionContext(model: BIMModel(), name: "New Project")
        let ids = populate(tx, kind: kind, units: units, projectName: projectName)
        // Templates are always valid; commit without the regenerator's per-element validation cost being an issue.
        let result = try! tx.commit()
        return (result.model, ids)
    }

    @discardableResult
    public static func populate(_ tx: TransactionContext, kind: ProjectTemplateKind, units: UnitsSettings, projectName: String) -> Ids {
        var ids = Ids()
        let residential = kind == .residential
        var info = ProjectInfoData(projectName: projectName, units: units)
        info.sheetNumberPrefix = "A"
        info.organization = "Arcus Studio"
        tx.create(.projectInfo, name: "Project Information", data: .projectInfo(info), ifcGUID: .random())

        // Phases.
        ids.phases.append(tx.create(.phases, name: "Existing", data: .phase(PhaseData(order: 0, description: "Existing conditions"))))
        ids.phases.append(tx.create(.phases, name: "New Construction", data: .phase(PhaseData(order: 1, description: "Proposed work"))))

        // Line styles & fill patterns.
        LineStyles.ensureStandard(in: tx, limit: 7) // W2-ANNOT: the standard line styles (the rest are added last)
        FillPatternLibrary.ensureStandard(in: tx) // W4-HATCH: the standard drafting and model pattern library
        let patternIDs = MaterialPatternDefaults.patternIndex(tx.model)

        // Materials.
        let materialSpecs: [(String, MaterialClass, UInt32, Double)] = [
            ("Concrete, Cast-in-Place", .concrete, 0xB9B6AF, 0), ("Concrete Masonry Units", .masonry, 0xA8A49C, 0),
            ("Brick, Common", .masonry, 0xA9573F, 0), ("Plasterboard", .plaster, 0xEEEBE4, 0), ("Plaster", .plaster, 0xF1EEE8, 0),
            ("Rigid Insulation", .insulation, 0xE7D57C, 0), ("Mineral Wool", .insulation, 0xE9DFA8, 0), ("Timber Stud", .wood, 0xCFA774, 0),
            ("Timber Cladding", .wood, 0x9C7650, 0), ("Oak Flooring", .wood, 0xB88A5A, 0), ("Screed", .concrete, 0xC8C4BC, 0),
            ("Steel", .metal, 0x7D8389, 0), ("Aluminum", .metal, 0xB9BEC4, 0), ("Glass", .glass, 0x9FC4D6, 0.7),
            ("Clay Roof Tile", .ceramic, 0x8F4B36, 0), ("Metal Roofing", .metal, 0x5E666E, 0), ("Membrane", .plastic, 0x3C3C3C, 0),
            ("Acoustic Ceiling Tile", .plaster, 0xF4F2EE, 0), ("Paint - White", .paint, 0xF7F6F2, 0), ("Stone Paving", .stone, 0xB3ABA0, 0),
            ("Earth", .earth, 0x8A7556, 0), ("Hardwood", .wood, 0x8F6440, 0), ("Laminate", .plastic, 0xD9D2C6, 0), ("Ceramic Tile", .ceramic, 0xDDD8CF, 0),
        ]
        for (name, cls, hex, tr) in materialSpecs {
            var m = MaterialData(materialClass: cls, color: RGBColor(hex: hex), transparency: tr)
            MaterialPatternDefaults.apply(to: &m, name: name, patterns: patternIDs) // W4-HATCH: cut and surface patterns by material
            ids.materials[name] = tx.create(.materials, name: name, data: .material(m))
        }
        func mat(_ n: String) -> ElementID? { ids.materials[n] }
        func layer(_ f: LayerFunction, _ m: String, _ t: Double) -> AssemblyLayer { AssemblyLayer(function: f, materialID: mat(m), thickness: t) }

        // Wall types (layers exterior → interior).
        var wallSpecs: [(String, String, [AssemblyLayer])] = [
            ("Generic - 200mm", "Interior", [layer(.structure, "Concrete Masonry Units", 0.2)]),
            ("Interior - 100mm Partition", "Interior", [layer(.finish2, "Plasterboard", 0.0125), layer(.structure, "Timber Stud", 0.075), layer(.finish2, "Plasterboard", 0.0125)]),
            ("Interior - 150mm Masonry", "Interior", [layer(.finish1, "Plaster", 0.013), layer(.structure, "Concrete Masonry Units", 0.124), layer(.finish1, "Plaster", 0.013)]),
            ("Exterior - Brick on CMU", "Exterior", [layer(.finish1, "Brick, Common", 0.102), layer(.thermal, "Rigid Insulation", 0.075), layer(.structure, "Concrete Masonry Units", 0.19), layer(.finish2, "Plaster", 0.013)]),
            ("Exterior - Concrete 300mm", "Exterior", [layer(.structure, "Concrete, Cast-in-Place", 0.25), layer(.thermal, "Rigid Insulation", 0.05)]),
            ("Retaining - 300mm Concrete", "Retaining", [layer(.structure, "Concrete, Cast-in-Place", 0.3)]),
        ]
        if residential {
            wallSpecs.insert(("Exterior - Timber Frame Clad", "Exterior", [layer(.finish1, "Timber Cladding", 0.02), layer(.membrane, "Membrane", 0), layer(.thermal, "Mineral Wool", 0.14),
                                                                            layer(.structure, "Timber Stud", 0.09), layer(.finish2, "Plasterboard", 0.0125)]), at: 0)
        }
        for (name, function, layers) in wallSpecs {
            var ls = layers
            for i in ls.indices where ls[i].function == .membrane { ls[i].thickness = 0 }
            var td = TypeData(instanceCategory: .walls, systemFamily: .basicWall, familyName: "Basic Wall", assembly: CompoundAssembly(layers: ls.filter { $0.thickness > 0 || $0.function == .membrane }))
            td.params[ParameterID("type.function")] = .text(function)
            td.params[ParameterID("type.mark")] = .text(String(name.prefix(1)) + "\(ids.wallTypes.count + 1)")
            ids.wallTypes[name] = tx.create(.elementTypes, name: name, data: .type(td))
        }
        // Floors (top → bottom).
        let floorSpecs: [(String, [AssemblyLayer])] = [
            ("Concrete Slab 200mm", [layer(.structure, "Concrete, Cast-in-Place", 0.2)]),
            ("Screed on Concrete 250mm", [layer(.finish1, "Screed", 0.05), layer(.structure, "Concrete, Cast-in-Place", 0.2)]),
            ("Timber Floor 300mm", [layer(.finish1, "Oak Flooring", 0.02), layer(.substrate, "Timber Stud", 0.02), layer(.structure, "Timber Stud", 0.235), layer(.finish2, "Plasterboard", 0.025)]),
            ("Paving on Slab", [layer(.finish1, "Stone Paving", 0.04), layer(.structure, "Concrete, Cast-in-Place", 0.15)]),
        ]
        for (name, layers) in floorSpecs {
            ids.floorTypes[name] = tx.create(.elementTypes, name: name, data: .type(TypeData(instanceCategory: .floors, systemFamily: .floor, familyName: "Floor", assembly: CompoundAssembly(layers: layers))))
        }
        ids.systemTypes["Building Pad"] = tx.create(.elementTypes, name: "Building Pad 300mm",
                                                    data: .type(TypeData(instanceCategory: .buildingPads, systemFamily: .buildingPad, familyName: "Building Pad", assembly: CompoundAssembly(layers: [layer(.structure, "Earth", 0.3)]))))
        for (name, layers) in [("Tiled Roof - Timber", [layer(.finish1, "Clay Roof Tile", 0.05), layer(.thermal, "Mineral Wool", 0.15), layer(.structure, "Timber Stud", 0.1)]),
                               ("Metal Roof - Insulated", [layer(.finish1, "Metal Roofing", 0.01), layer(.thermal, "Rigid Insulation", 0.15), layer(.structure, "Timber Stud", 0.14)]),
                               ("Flat Roof - Concrete", [layer(.membrane, "Membrane", 0), layer(.thermal, "Rigid Insulation", 0.12), layer(.structure, "Concrete, Cast-in-Place", 0.2)])] {
            ids.roofTypes[name] = tx.create(.elementTypes, name: name, data: .type(TypeData(instanceCategory: .roofs, systemFamily: .roof, familyName: "Basic Roof", assembly: CompoundAssembly(layers: layers))))
        }
        for (name, layers) in [("Plasterboard Ceiling", [layer(.finish1, "Plasterboard", 0.0125)]), ("Acoustic Tile 600 x 600", [layer(.finish1, "Acoustic Ceiling Tile", 0.02)])] {
            ids.ceilingTypes[name] = tx.create(.elementTypes, name: name, data: .type(TypeData(instanceCategory: .ceilings, systemFamily: .ceiling, familyName: "Compound Ceiling", assembly: CompoundAssembly(layers: layers))))
        }
        // Stairs, railings, columns, beams.
        ids.systemTypes["Stair"] = tx.create(.elementTypes, name: residential ? "Residential - 190 max riser" : "Monolithic - 175 max riser", data: .type(TypeData(
            instanceCategory: .stairs, systemFamily: .stair, familyName: "Assembled Stair",
            params: [ParameterID("stair.maxRiser"): .double(residential ? 0.19 : 0.175), ParameterID("stair.minTread"): .double(residential ? 0.25 : 0.28),
                     ParameterID("stair.treadThickness"): .double(0.04), ParameterID("stair.waist"): .double(0.15),
                     ParameterID("type.material"): .ref(mat("Concrete, Cast-in-Place"))])))
        ids.systemTypes["Railing"] = tx.create(.elementTypes, name: "Guard - 1100mm", data: .type(TypeData(
            instanceCategory: .railings, systemFamily: .railing, familyName: "Railing",
            params: [ParameterID("railing.height"): .double(1.1), ParameterID("railing.balusterSpacing"): .double(0.11), ParameterID("railing.balusterSize"): .double(0.02),
                     ParameterID("railing.railSize"): .double(0.05), ParameterID("type.material"): .ref(mat("Steel"))])))
        ids.systemTypes["Handrail"] = tx.create(.elementTypes, name: "Handrail - 900mm", data: .type(TypeData(
            instanceCategory: .railings, systemFamily: .railing, familyName: "Railing",
            params: [ParameterID("railing.height"): .double(0.9), ParameterID("railing.balusterSpacing"): .double(0.8), ParameterID("railing.balusterSize"): .double(0.03),
                     ParameterID("railing.railSize"): .double(0.045), ParameterID("type.material"): .ref(mat("Hardwood"))])))
        for (name, w, d, dia) in [("Concrete Column 400 x 400", 0.4, 0.4, 0.0), ("Concrete Column Round 350", 0.0, 0.0, 0.35), ("Timber Post 150 x 150", 0.15, 0.15, 0.0)] {
            ids.systemTypes[name] = tx.create(.elementTypes, name: name, data: .type(TypeData(
                instanceCategory: .columns, familyName: "Column",
                params: [ParameterID("column.width"): .double(w), ParameterID("column.depth"): .double(d), ParameterID("column.diameter"): .double(dia),
                         ParameterID("type.material"): .ref(mat(name.hasPrefix("Timber") ? "Timber Stud" : "Concrete, Cast-in-Place"))])))
        }
        ids.systemTypes["Steel Column"] = tx.create(.elementTypes, name: "Steel Column 200 x 200", data: .type(TypeData(
            instanceCategory: .structuralColumns, familyName: "Structural Column",
            params: [ParameterID("column.width"): .double(0.2), ParameterID("column.depth"): .double(0.2), ParameterID("type.material"): .ref(mat("Steel"))])))
        for (name, w, d, m) in [("Steel Beam 200 x 400", 0.2, 0.4, "Steel"), ("Concrete Beam 300 x 500", 0.3, 0.5, "Concrete, Cast-in-Place"), ("Glulam 140 x 360", 0.14, 0.36, "Timber Stud")] {
            ids.systemTypes[name] = tx.create(.elementTypes, name: name, data: .type(TypeData(
                instanceCategory: .structuralFraming, familyName: "Beam",
                params: [ParameterID("beam.width"): .double(w), ParameterID("beam.depth"): .double(d), ParameterID("type.material"): .ref(mat(m))])))
        }
        // Annotation system types.
        // W2-ANNOT: text and dimension types in the project's unit system ("Text 2.5mm Arial" is the smallest text either way).
        let annotationTypes = AnnotationTypes.ensureStandard(in: tx, units: units, texts: 3, dimensions: 1)
        ids.systemTypes["Text 2.5mm Arial"] = annotationTypes[AnnotationTypes.textSpecs(units)[0].name]
        ids.systemTypes["Dimension"] = annotationTypes[AnnotationTypes.dimensionSpecs(units)[0].name]
        for (name, pattern, hex) in [("Diagonal Hatch", FillPatternKind.diagonalUp, "#000000"), ("Solid Black", .solid, "#000000"), ("Concrete", .concrete, "#555555"), ("Earth", .earth, "#6B5A45")] {
            var params: [ParameterID: ParamValue] = [ParameterID("region.pattern"): .text(pattern.rawValue), ParameterID("region.color"): .text(hex)]
            if let pid = patternIDs[pattern.rawValue] { params[ParameterID("region.fillPattern")] = .ref(pid) } // W4-HATCH: project pattern reference
            ids.systemTypes["Region " + name] = tx.create(.elementTypes, name: name, data: .type(TypeData(instanceCategory: .filledRegions, systemFamily: .filledRegion, familyName: "Filled Region",
                                                                                                          params: params)))
        }

        // Loadable families and their types.
        for fam in StarterLibrary.all {
            let fid = tx.create(.families, name: fam.name, data: .family(fam))
            ids.families[fam.name] = fid
            let instanceCategory: Category = fam.template == .tag ? .tags : fam.template.category
            for t in fam.types {
                var params: [ParameterID: ParamValue] = [:]
                for (k, v) in t.values { params[Parameters.familyParamID(k)] = v }
                if fam.template == .window { params[ParameterID("type.mark")] = .text("W\(ids.familyTypes.count + 1)") }
                if fam.template == .door { params[ParameterID("type.mark")] = .text("D\(ids.familyTypes.count + 1)") }
                let tid = tx.create(.elementTypes, name: t.name, data: .type(TypeData(instanceCategory: instanceCategory, familyID: fid, familyName: fam.name, params: params)))
                ids.familyTypes["\(fam.name): \(t.name)"] = tid
                if fam.template == .titleBlock { ids.titleBlocks[fam.name] = tid }
            }
        }
        // Materials for door/window family material parameters.
        for (key, tid) in ids.familyTypes {
            if key.hasPrefix("Door") {
                tx.update(tid) {
                    $0.typeData?.params[Parameters.familyParamID("Frame Material")] = .ref(mat("Hardwood"))
                    $0.typeData?.params[Parameters.familyParamID("Panel Material")] = .ref(mat("Oak Flooring"))
                }
            } else if key.hasPrefix("Window") {
                tx.update(tid) {
                    $0.typeData?.params[Parameters.familyParamID("Frame Material")] = .ref(mat("Aluminum"))
                    $0.typeData?.params[Parameters.familyParamID("Glass Material")] = .ref(mat("Glass"))
                }
            }
        }

        // Levels and views.
        let levelSpecs: [(String, Double)] = kind == .empty ? [("Level 1", 0), ("Level 2", 3.0)]
            : residential ? [("Ground Floor", 0), ("First Floor", 2.8), ("Roof", 5.6)]
            : [("Level 1", 0), ("Level 2", 4.0), ("Roof", 8.0)]
        let scale = residential ? 50 : 100
        for (name, elev) in levelSpecs {
            let lid = tx.create(.levels, name: name, data: .level(LevelData(elevation: elev)))
            ids.levels.append(lid)
                var fp = ViewData(kind: .floorPlan, scale: scale)
                fp.phaseID = ids.phases.last
                ids.planViews[lid] = tx.create(.views, name: name, data: .view(fp), levelID: lid)
                if kind != .empty && name != "Roof" {
                    var rcp = ViewData(kind: .ceilingPlan, scale: scale)
                    rcp.phaseID = ids.phases.last
                    ids.ceilingViews[lid] = tx.create(.views, name: name, data: .view(rcp), levelID: lid)
                }
        }
        // Four exterior elevations and a default 3D view.
        for (name, dir, origin) in [("North", Vec2(0, -1), Vec2(0, 20)), ("South", Vec2(0, 1), Vec2(0, -20)), ("East", Vec2(-1, 0), Vec2(20, 0)), ("West", Vec2(1, 0), Vec2(-20, 0))] {
            var ev = ViewData(kind: .elevation, scale: scale)
            ev.planeOrigin = Vec3(origin, z: 0)
            ev.viewDirection = dir
            ev.farClip = 80
            ev.phaseID = ids.phases.last
            ev.markerPosition = origin - dir * 1.0
            tx.create(.views, name: name, data: .view(ev))
        }
        var v3 = ViewData(kind: .threeD, scale: scale)
        v3.camera = Camera3D.defaultIsometric
        v3.phaseID = ids.phases.last
        tx.create(.views, name: "{3D}", data: .view(v3))

        // View templates.
        var planTemplate = ViewTemplateData(appliesTo: .floorPlan)
        planTemplate.scale = scale
        planTemplate.detailLevel = .medium
        planTemplate.phaseFilter = .showAll
        tx.create(.viewTemplates, name: "Architectural Plan", data: .viewTemplate(planTemplate))
        var presentation = ViewTemplateData(appliesTo: .floorPlan)
        presentation.detailLevel = .coarse
        var vg = VisibilityGraphics()
        vg.hiddenCategories = [.roomSeparationLines, .referencePlanes]
        presentation.visibility = vg
        tx.create(.viewTemplates, name: "Presentation Plan", data: .viewTemplate(presentation))

        // Default schedules.
        if kind != .empty {
            ScheduleTemplates.createDefaults(tx)
        }
        // Default revision and one sheet.
        tx.create(.revisions, name: "Revision 1", data: .revision(RevisionData(sequence: 1, date: "", description: "Issued for review")))
        if kind != .empty {
            let tb = residential ? ids.titleBlocks["A3 Title Block"] : ids.titleBlocks["A1 Title Block"]
            tx.create(.sheets, name: "Unnamed", data: .sheet(SheetData(number: "A101", paper: residential ? .a3 : .a1, titleBlockTypeID: tb)))
        }
        for (k, v) in CurtainWallDefaults.populate(tx) { ids.systemTypes[k] = v } // WP3: curtain panel and curtain wall types
        StandardContent.populate(tx, ids: &ids, kind: kind, units: units) // W2-TYPES: unit-aware materials, assemblies, doors, windows, columns
        // W2-ANNOT: the rest of the standard line styles, text and dimension types, and the area and multi-category tags.
        LineStyles.ensureStandard(in: tx)
        for (name, id) in AnnotationTypes.ensureStandard(in: tx, units: units) where AnnotationTypes.textSpecs(units).contains(where: { $0.name == name }) { ids.systemTypes["Text " + name] = id }
        AnnotationLibrary.ensureAll(in: tx)
        return ids
    }
}

/// Default schedule definitions used by templates and the "New Schedule" command.
public enum ScheduleTemplates {
    public static func field(_ key: String, _ heading: String, width: Double = 0.025, total: ScheduleTotal = .none, align: HorizontalAlign = .left) -> ScheduleField {
        var f = ScheduleField(source: .parameter(ParameterID(key)), heading: heading, width: width, alignment: align)
        f.total = total
        return f
    }

    public static func doorSchedule() -> ScheduleDefinition {
        var s = ScheduleDefinition(kind: .category, categories: [.doors], fields: [
            field("mark", "Mark", width: 0.015), field("familyAndType", "Type", width: 0.05), field("family:Width", "Width", width: 0.02, align: .right),
            field("family:Height", "Height", width: 0.02, align: .right), field("insert.fromRoom", "From Room", width: 0.035), field("insert.toRoom", "To Room", width: 0.035),
            field("type.fireRating", "Fire Rating", width: 0.02), field("comments", "Comments", width: 0.04),
        ])
        s.sorting = [ScheduleSort(fieldID: s.fields[0].id)]
        s.grandTotals = true
        return s
    }

    public static func windowSchedule() -> ScheduleDefinition {
        var s = ScheduleDefinition(kind: .category, categories: [.windows], fields: [
            field("type.mark", "Type Mark", width: 0.018), field("familyAndType", "Type", width: 0.05), field("family:Width", "Width", width: 0.02, align: .right),
            field("family:Height", "Height", width: 0.02, align: .right), field("insert.sillHeight", "Sill Height", width: 0.022, align: .right),
            ScheduleField(source: .count, heading: "Count", width: 0.015, alignment: .right),
        ])
        s.sorting = [ScheduleSort(fieldID: s.fields[0].id)]
        s.itemizeEveryInstance = false
        s.grandTotals = true
        return s
    }

    public static func roomSchedule() -> ScheduleDefinition {
        var s = ScheduleDefinition(kind: .category, categories: [.rooms], fields: [
            field("room.number", "Number", width: 0.018), field("name", "Name", width: 0.045), field("level", "Level", width: 0.03),
            field("q.area", "Area", width: 0.025, total: .total, align: .right), field("q.perimeter", "Perimeter", width: 0.025, align: .right),
            field("room.department", "Department", width: 0.03), field("room.floorFinish", "Floor Finish", width: 0.03),
        ])
        s.sorting = [ScheduleSort(fieldID: s.fields[2].id, header: true, footer: true), ScheduleSort(fieldID: s.fields[0].id)]
        s.grandTotals = true
        return s
    }

    public static func wallQuantities() -> ScheduleDefinition {
        var s = ScheduleDefinition(kind: .category, categories: [.walls], fields: [
            field("familyAndType", "Type", width: 0.06), field("q.length", "Length", width: 0.025, total: .total, align: .right),
            field("q.area", "Area", width: 0.025, total: .total, align: .right), field("q.volume", "Volume", width: 0.025, total: .total, align: .right),
            ScheduleField(source: .count, heading: "Count", width: 0.015, alignment: .right),
        ])
        s.sorting = [ScheduleSort(fieldID: s.fields[0].id)]
        s.itemizeEveryInstance = false
        s.grandTotals = true
        return s
    }

    public static func sheetList() -> ScheduleDefinition {
        var s = ScheduleDefinition(kind: .sheetList, categories: [.sheets], fields: [
            field("sheet.number", "Sheet Number", width: 0.025), field("name", "Sheet Name", width: 0.07), field("sheet.currentRevision", "Revision", width: 0.018),
        ])
        s.sorting = [ScheduleSort(fieldID: s.fields[0].id)]
        return s
    }

    public static func createDefaults(_ tx: TransactionContext) {
        tx.create(.schedules, name: "Door Schedule", data: .schedule(doorSchedule()))
        tx.create(.schedules, name: "Window Schedule", data: .schedule(windowSchedule()))
        tx.create(.schedules, name: "Room Schedule", data: .schedule(roomSchedule()))
        tx.create(.schedules, name: "Wall Quantities", data: .schedule(wallQuantities()))
        tx.create(.schedules, name: "Sheet List", data: .schedule(sheetList()))
    }
}

// MARK: User templates

extension ProjectTemplates {
    /// True for elements a project template leaves out: model content (walls, doors, rooms, components, imports…).
    /// Everything that depends on them (tags, dimensions, hosted inserts) goes with them.
    static func isProjectContent(_ e: Element) -> Bool { e.category.isModel }

    /// The template form of a project: types, families, materials, styles, levels, grids, views, sheets, schedules,
    /// phases and settings, with no model elements.
    public static func templateModel(from model: BIMModel) -> BIMModel {
        let tx = TransactionContext(model: model, name: "Save as Template")
        for e in model.allElements where isProjectContent(e) && tx.model[e.id] != nil { tx.delete(e.id) }
        let kept = tx.model.allElements
        let usedDrawings = Set(kept.compactMap { $0.link?.contentKey })
        return BIMModel(elements: kept, nextID: tx.model.nextID, referenceDrawings: model.referenceDrawings.filter { usedDrawings.contains($0.key) },
                        projectParameters: model.projectParameters, viewSheetSets: model.viewSheetSets, revision: model.revision)
    }

    /// A new project from a template model: model content removed, fresh IFC GUIDs (projects made from one template
    /// must not share identities) and the given project name.
    public static func instantiate(template: BIMModel, projectName: String) -> BIMModel {
        let base = templateModel(from: template)
        let elements = base.allElements.map { e -> Element in
            var c = e
            c.ifcGUID = .random()
            if var info = c.projectInfo {
                info.projectName = projectName
                c.projectInfo = info
            }
            return c
        }
        return BIMModel(elements: elements, nextID: base.nextID, referenceDrawings: base.referenceDrawings,
                        projectParameters: base.projectParameters, viewSheetSets: base.viewSheetSets)
    }
}
