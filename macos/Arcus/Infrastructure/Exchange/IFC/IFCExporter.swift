import Foundation
import ArcusGeometry
import ArcusDomain

/// Writes IFC2X3 Coordination View 2.0 / IFC4 Reference View files from a model snapshot.
///
/// Export is a pure function of the value-type model and the options, so it runs on any thread.
/// Output is deterministic: entities are numbered in a fixed order (project context, then elements
/// sorted by element id, then relationships), so identical inputs produce identical bytes.
public enum IFCExporter {
    public static func export(_ model: BIMModel, options: IFCExportOptions, progress: @Sendable (Double) -> Void = { _ in },
                              isCancelled: @Sendable () -> Bool = { false }) throws -> (files: [(name: String, data: Data)], report: IFCExportReport) {
        let started = Date()
        let plan = try ExportPlan(model: model, options: options)
        var report = IFCExportReport()
        report.skipped = plan.skipped
        var warnings = plan.warnings
        var files: [(name: String, data: Data)] = []

        struct Job { var name: String; var storeys: [Int]; var elements: [PlannedElement] }
        var jobs: [Job] = []
        let fileName = options.fileName.isEmpty ? "Project.ifc" : options.fileName
        if options.splitByStorey {
            let base = (fileName as NSString).deletingPathExtension
            for (k, s) in plan.storeys.enumerated() {
                // Site-level elements (topography) go with the lowest storey's file.
                let els = plan.elements.filter { $0.storey == k || ($0.storey == nil && k == 0) }
                let safe = s.name.map { "/:\\".contains($0) ? "-" : $0 }
                jobs.append(Job(name: "\(base) - \(String(safe)).ifc", storeys: [k], elements: els))
            }
        } else {
            jobs.append(Job(name: fileName, storeys: Array(plan.storeys.indices), elements: plan.elements))
        }

        let total = max(1, jobs.reduce(0) { $0 + $1.elements.count })
        var done = 0
        var exported: Set<ElementID> = []
        for job in jobs {
            if isCancelled() { throw IFCError.cancelled }
            let builder = IFCFileBuilder(model: model, options: options, plan: plan, storeyIndices: job.storeys, fileName: job.name)
            let data = try builder.build(elements: job.elements) {
                done += 1
                progress(Double(done) / Double(total))
                return isCancelled()
            }
            files.append((job.name, data))
            report.files.append(job.name)
            for (k, v) in builder.writer.counts { report.entityCounts[k, default: 0] += v }
            exported.formUnion(builder.exportedElements)
            for w in builder.warnings where !warnings.contains(w) { warnings.append(w) }
        }
        report.exportedElements = exported.count
        report.warnings = warnings
        report.elapsed = Date().timeIntervalSince(started)
        progress(1)
        return (files, report)
    }
}

// MARK: - Planning

struct StoreyInfo {
    var levelID: ElementID?
    var name: String
    var elevation: Double
    var guid: IFCGUID
}

enum ExportKind: Equatable {
    case wall, slab(String), roof, covering, door, window, space, column, beam, stair, railing, furniture, sanitary, proxy, geographic, ramp
    case reference(String)
    case group
    case light, vegetation // W2-LIB: lighting fixtures, planting
    case reinforcingBar, reinforcingMesh // F34: rebar sets, area and path reinforcement; fabric
}

struct PlannedElement {
    var element: Element
    var kind: ExportKind
    /// Index into `ExportPlan.storeys`; nil = contained in the site (topography).
    var storey: Int?
}

/// Decides which elements are exported, as what, and on which storey.
struct ExportPlan {
    let model: BIMModel
    let options: IFCExportOptions
    var storeys: [StoreyInfo] = []
    var elements: [PlannedElement] = []
    var skipped: [(ElementID, String)] = []
    var warnings: [String] = []
    let projectGUID: IFCGUID

    init(model: BIMModel, options: IFCExportOptions) throws {
        self.model = model
        self.options = options
        projectGUID = model.projectInfoElement?.ifcGUID ?? IFCGUID.deterministic("Arcus/IfcProject")

        // Storeys: building-storey levels, else all levels, else a synthetic ground storey.
        var levels = model.levels.filter { $0.level?.isBuildingStorey == true }
        if levels.isEmpty { levels = model.levels }
        storeys = levels.map { StoreyInfo(levelID: $0.id, name: $0.name, elevation: $0.level?.elevation ?? 0, guid: $0.ifcGUID) }
        if storeys.isEmpty {
            storeys = [StoreyInfo(levelID: nil, name: "Level 0", elevation: 0, guid: IFCGUID.deterministic("\(projectGUID.value)/storey"))]
            warnings.append("The model has no levels; a storey \"Level 0\" at elevation 0 was created for the export.")
        }

        // Phase and view filters.
        var phaseOrder: Int? = model.latestPhase?.phase?.order
        if let pid = options.phaseID {
            guard let o = model.phaseOrder(pid) else { throw IFCError("The selected phase does not exist in the model.") }
            phaseOrder = o
        }
        var resolver: VisibilityResolver?
        if let vid = options.visibleInViewID {
            guard let v = model[vid], v.view != nil else { throw IFCError("The selected view does not exist in the model.") }
            resolver = VisibilityResolver(model: model, view: v)
        }

        var unleveled = 0
        let lowestStoreyLevel = storeys.first?.levelID
        for e in model.allElements {
            let kind: ExportKind
            switch classify(e, lowestStoreyLevel: lowestStoreyLevel) {
            case .ignore: continue
            case .skip(let reason): skipped.append((e.id, reason)); continue
            case .export(let k): kind = k
            }
            if kind != .group {
                if let po = phaseOrder {
                    if let c = model.phaseOrder(e.phaseCreated), c > po { skipped.append((e.id, "Created in a later phase than the exported phase.")); continue }
                    if let d = model.phaseOrder(e.phaseDemolished), d <= po { skipped.append((e.id, "Demolished by the exported phase.")); continue }
                }
                if let r = resolver {
                    if r.resolve(e) == nil { skipped.append((e.id, "Not visible in the selected view.")); continue }
                } else if let opt = e.designOptionID, let od = model[opt]?.designOption, !od.isPrimary {
                    skipped.append((e.id, "Belongs to a secondary design option.")); continue
                }
            }
            var storey: Int?
            if kind == .geographic || kind == .group {
                storey = nil
            } else {
                let lid = e.levelID ?? model[e.hostID]?.levelID
                if let lid {
                    storey = storeyIndex(for: lid)
                } else {
                    unleveled += 1
                    storey = 0
                }
            }
            elements.append(PlannedElement(element: e, kind: kind, storey: storey))
        }
        if unleveled > 0 {
            warnings.append("\(unleveled) element\(unleveled == 1 ? "" : "s") without a level \(unleveled == 1 ? "was" : "were") assigned to storey \"\(storeys[0].name)\".")
        }
        if elements.contains(where: { $0.kind == .roof }) {
            warnings.append("Roofs are exported as a single IfcRoof body each (no IfcSlab ROOF parts).")
        }
        if options.schema == .ifc2x3 && options.coordinateBase == .sharedCoordinates {
            warnings.append("IFC2X3 has no map conversion: coordinates are relative to the survey point and the survey values are recorded in the Arcus_SharedCoordinates property set on IfcSite.")
        }
    }

    /// Index of the storey for a level: the level itself when it is a storey, else the nearest storey at or below it.
    func storeyIndex(for levelID: ElementID) -> Int {
        if let i = storeys.firstIndex(where: { $0.levelID == levelID }) { return i }
        let z = model.elevation(ofLevel: levelID)
        var best = 0
        for (i, s) in storeys.enumerated() where s.elevation <= z + 1e-6 { best = i }
        return best
    }

    enum Classification { case ignore, skip(String), export(ExportKind) }

    func classify(_ e: Element, lowestStoreyLevel: ElementID?) -> Classification {
        switch e.category.categoryClass {
        case .internal_: return .ignore
        case .view: return .skip("Views, sheets and schedules are documentation and are not exported to IFC.")
        case .annotation: return .skip("Annotation and detail elements are view-specific and are not exported to IFC.")
        case .datum:
            if e.category == .levels { return .ignore } // exported as IfcBuildingStorey
            return .skip("Grids and reference planes are not exported.")
        case .model: break
        }
        switch (e.category, e.data) {
        case (.walls, .wall): return .export(.wall)
        case (.floors, .slab):
            return .export(.slab(e.levelID != nil && e.levelID == lowestStoreyLevel ? "BASESLAB" : "FLOOR"))
        case (.buildingPads, .slab): return .export(.slab("BASESLAB"))
        case (.ceilings, .slab): return .export(.covering)
        case (.roofs, .roof): return .export(.roof)
        case (.doors, .insert): return .export(.door)
        case (.windows, .insert): return .export(.window)
        case (.rooms, .room), (.spaces, .room): // F5: spaces export as IfcSpace too
            if RoomGeometry.boundary(e, model).profile == nil { return .skip("The \(e.category.singularName.lowercased()) is not enclosed, so it has no boundary to export.") }
            return .export(.space)
        case (.areas, _): return .skip("Areas are area-plan annotations and are not exported.")
        case (.columns, .column), (.structuralColumns, .column): return .export(.column)
        case (.structuralFraming, .beam): return .export(.beam)
        case (.stairs, .stair): return .export(.stair)
        case (.ramps, .ramp): return .export(.ramp)
        case (.railings, .railing): return .export(.railing)
        case (.furniture, .component), (.casework, .component): return .export(.furniture)
        case (.plumbingFixtures, .component): return .export(.sanitary)
        case (.lightingFixtures, .component): return .export(.light) // W2-LIB
        case (.planting, .component): return .export(.vegetation) // W2-LIB
        case (.genericModels, _), (.specialtyEquipment, _), (.parking, _): return .export(.proxy)
        case (.topography, .topography): return .export(.geographic)
        case (.ifcReference, .referenceGeometry(let r)): return .export(.reference(r.ifcType))
        case (.modelGroups, .group): return .export(.group)
        case (.importedCAD, _): return .skip("Imported CAD geometry is not exported.")
        case (.linkedModels, _), (.coordinationModels, _), (.pointClouds, _): return .skip("Linked models and point clouds are references and are not exported.") // F67
        case (.decals, _): return .skip("Decals are images for rendering and are not exported.") // F67
        case (.mass, _): return .skip("Masses are conceptual forms and are not exported; export the walls, floors and roofs made from them.") // F5
        case (.wallOpenings, _): return .ignore // WP3: exported as IfcOpeningElement voids of their host wall
        case (.reveals, _): return .ignore // F1: the groove is part of the host wall's body
        case (.shaftOpenings, _): return .skip("Shaft openings are exported as holes in the floors, ceilings and roofs they cut.") // WP3
        case (.roomSeparationLines, _), (.areaBoundaryLines, _), (.propertyLines, _), (.spaceSeparationLines, _): return .skip("Lines are not exported.") // F5
        case (.structuralRebar, _), (.areaReinforcement, _), (.pathReinforcement, _): return .export(.reinforcingBar) // F34
        case (.fabricAreas, _), (.fabricReinforcement, _): return .export(.reinforcingMesh) // F34
        case (.beamSystems, _): return .skip("Beam systems are exported as their beams.") // F34
        default:
            if ElementMeshes.hasModelGeometry(e) { return .export(.proxy) }
            return .skip("\(e.category.displayName) elements without 3D geometry are not exported.")
        }
    }
}
