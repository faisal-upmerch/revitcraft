import Foundation
import ArcusGeometry
import ArcusCalc

// FM3: the blank Furniture template (Docs/FurnitureMode.md §3, "Document and file"), set up like a Revit-style
// Furniture or Casework family template: Ref. Level, the eight framing reference planes, Width/Depth/Height labelled
// with EQ about the centres, and the views a shop drawing needs. Always Imperial.

public enum FurnitureTemplates {
    /// Default size of a new piece: 36" wide, 18" deep, 30" high.
    public static let defaultWidth = 36 * 0.0254, defaultDepth = 18 * 0.0254, defaultHeight = 30 * 0.0254
    /// Shop drawings are drawn at 1" = 1'-0".
    public static let viewScale = 12

    /// A material of the furniture set: name, class, colour, cost (USD) and what the cost is per.
    public struct MaterialSpec: Sendable {
        public var name: String
        public var materialClass: MaterialClass
        public var color: UInt32
        public var transparency: Double
        public var cost: Double
        public var unit: MaterialCostUnit
        public var description: String
    }

    /// The furniture materials every Furniture document starts with (prices are typical US retail, editable).
    public static let materials: [MaterialSpec] = [
        MaterialSpec(name: "Plywood", materialClass: .wood, color: 0xD8B98A, transparency: 0, cost: 85, unit: .sheet, description: "Birch plywood, 3/4\", 4'x8' sheet"),
        MaterialSpec(name: "MDF", materialClass: .wood, color: 0xB89B78, transparency: 0, cost: 55, unit: .sheet, description: "Medium-density fiberboard, 3/4\", 4'x8' sheet"),
        MaterialSpec(name: "Particleboard", materialClass: .wood, color: 0xC9AE85, transparency: 0, cost: 40, unit: .sheet, description: "Particleboard, 3/4\", 4'x8' sheet"),
        MaterialSpec(name: "Melamine", materialClass: .plastic, color: 0xF2F0EB, transparency: 0, cost: 65, unit: .sheet, description: "White melamine on particleboard, 3/4\", 4'x8' sheet"),
        MaterialSpec(name: "Solid Oak", materialClass: .wood, color: 0xB8875A, transparency: 0, cost: 9, unit: .boardFoot, description: "Red oak, kiln dried"),
        MaterialSpec(name: "Solid Walnut", materialClass: .wood, color: 0x6B4A33, transparency: 0, cost: 14, unit: .boardFoot, description: "Black walnut, kiln dried"),
        MaterialSpec(name: "Solid Maple", materialClass: .wood, color: 0xE3C99F, transparency: 0, cost: 7, unit: .boardFoot, description: "Hard maple, kiln dried"),
        MaterialSpec(name: "Solid Ash", materialClass: .wood, color: 0xD9C09A, transparency: 0, cost: 6, unit: .boardFoot, description: "White ash, kiln dried"),
        MaterialSpec(name: "Solid Pine", materialClass: .wood, color: 0xE6C88E, transparency: 0, cost: 3, unit: .boardFoot, description: "Eastern white pine"),
        MaterialSpec(name: "Laminate", materialClass: .plastic, color: 0xDDD6CA, transparency: 0, cost: 3, unit: .squareFoot, description: "High-pressure laminate"),
        MaterialSpec(name: "Veneer", materialClass: .wood, color: 0xC59A6B, transparency: 0, cost: 4, unit: .squareFoot, description: "Wood veneer, paper backed"),
        MaterialSpec(name: "Glass", materialClass: .glass, color: 0x9FC4D6, transparency: 0.7, cost: 12, unit: .squareFoot, description: "Tempered glass, 1/4\""),
        MaterialSpec(name: "Steel", materialClass: .metal, color: 0x7D8389, transparency: 0, cost: 6, unit: .linearFoot, description: "Mild steel tube, 1\" square"),
        MaterialSpec(name: "Brass", materialClass: .metal, color: 0xC9A447, transparency: 0, cost: 15, unit: .linearFoot, description: "Brass bar"),
        MaterialSpec(name: "Fabric", materialClass: .generic, color: 0x7E8C9A, transparency: 0, cost: 8, unit: .linearFoot, description: "Upholstery fabric, 54\" wide"),
        MaterialSpec(name: "Leather", materialClass: .generic, color: 0x8A5A3C, transparency: 0, cost: 9, unit: .squareFoot, description: "Full-grain upholstery leather"),
        MaterialSpec(name: "Foam", materialClass: .insulation, color: 0xEDE3B5, transparency: 0, cost: 5, unit: .squareFoot, description: "High-density upholstery foam, 2\""),
    ]

    /// A blank Furniture (or Casework) document named `name`.
    public static func blank(category: FamilyTemplate = .furniture, name: String = "Furniture") -> BIMModel {
        let tx = TransactionContext(model: BIMModel(), name: "New Furniture")
        populate(tx, category: category, name: name)
        // Templates are always valid.
        return try! tx.commit().model
    }

    /// The template's content, created in `tx`.
    public static func populate(_ tx: TransactionContext, category: FamilyTemplate, name: String) {
        let category: FamilyTemplate = category == .casework ? .casework : .furniture
        let units = UnitsSettings.imperial
        _ = LineStyles.ensureStandard(in: tx)
        _ = FillPatternLibrary.ensureStandard(in: tx)
        let patterns = MaterialPatternDefaults.patternIndex(tx.model)

        // Materials (with costs) first: the Material parameter defaults to plywood.
        var materialIDs: [String: ElementID] = [:]
        for spec in materials {
            var m = MaterialData(materialClass: spec.materialClass, color: RGBColor(hex: spec.color), transparency: spec.transparency, description: spec.description)
            MaterialPatternDefaults.apply(to: &m, name: spec.name, patterns: patterns)
            m.cost = spec.cost
            m.costUnit = spec.unit
            materialIDs[spec.name] = tx.create(.materials, name: spec.name, data: .material(m))
        }

        // Project information: Furniture kind, Imperial, the piece's parameters and its first type.
        var family = FamilyDefinition(name: name, template: category)
        family.parameters = [
            FamilyParameter(name: "Width", type: .length, isBuiltIn: true),
            FamilyParameter(name: "Depth", type: .length, isBuiltIn: true),
            FamilyParameter(name: "Height", type: .length, isBuiltIn: true),
            FamilyParameter(name: "Material", type: .elementRef(.materials), group: .materials),
        ]
        var values: [String: ParamValue] = ["Width": .double(defaultWidth), "Depth": .double(defaultDepth), "Height": .double(defaultHeight)]
        if let ply = materialIDs["Plywood"] { values["Material"] = .ref(ply) }
        family.types = [FamilyTypeDefinition(name: typeName(defaultWidth, defaultDepth, defaultHeight), values: values)]
        family.description = category == .casework ? "Casework" : "Furniture"
        var info = ProjectInfoData(projectName: name, units: units)
        info.documentKind = .furniture
        info.furniture = FurnitureSetupData(family: family)
        info.sheetNumberPrefix = "F"
        info.clientName = ""
        info.organization = "Arcus Studio"
        tx.create(.projectInfo, name: "Project Information", data: .projectInfo(info), ifcGUID: .random())
        let phase = tx.create(.phases, name: "New Construction", data: .phase(PhaseData(order: 0, description: "Proposed work")))

        // Annotation types, tags and title blocks.
        let annotation = AnnotationTypes.ensureStandard(in: tx, units: units)
        AnnotationLibrary.ensureAll(in: tx)
        var titleBlocks: [String: ElementID] = [:]
        let tagFamily = StarterLibrary.tagFamily("Generic Mark Tag", categories: [.furniture, .casework, .genericModels], label: "Mark", shape: "circle")
        for fam in [StarterLibrary.titleBlock("Tabloid Title Block", width: PaperSize.ansiB.landscapeSize.x, height: PaperSize.ansiB.landscapeSize.y),
                    StarterLibrary.titleBlock("ARCH D Title Block", width: 0.9144, height: 0.6096), tagFamily] {
            let fid = tx.create(.families, name: fam.name, data: .family(fam))
            let instanceCategory: Category = fam.template == .tag ? .tags : fam.template.category
            for t in fam.types {
                var params: [ParameterID: ParamValue] = [:]
                for (k, v) in t.values { params[Parameters.familyParamID(k)] = v }
                let tid = tx.create(.elementTypes, name: t.name, data: .type(TypeData(instanceCategory: instanceCategory, familyID: fid, familyName: fam.name, params: params)))
                if fam.template == .titleBlock { titleBlocks[fam.name] = tid }
            }
        }

        // Ref. Level and the views.
        let level = tx.create(.levels, name: "Ref. Level", data: .level(LevelData(elevation: 0)))
        var plan = ViewData(kind: .floorPlan, scale: viewScale)
        plan.phaseID = phase
        plan.detailLevel = .fine
        let planID = tx.create(.views, name: "Ref. Level", data: .view(plan), levelID: level)
        var elevations: [String: ElementID] = [:]
        let reach = 1.5
        for (n, dir) in [("Front", Vec2(0, 1)), ("Back", Vec2(0, -1)), ("Left", Vec2(1, 0)), ("Right", Vec2(-1, 0))] {
            var ev = ViewData(kind: .elevation, scale: viewScale)
            let origin = dir * -reach
            ev.planeOrigin = Vec3(origin, z: 0)
            ev.viewDirection = dir
            ev.farClip = reach * 4
            ev.phaseID = phase
            ev.detailLevel = .fine
            ev.markerPosition = origin - dir * 0.15
            elevations[n] = tx.create(.views, name: n, data: .view(ev))
        }
        var v3 = ViewData(kind: .threeD, scale: viewScale)
        v3.camera = Camera3D(eye: Vec3(-1.7, -2.3, 1.5), target: Vec3(0, 0, defaultHeight / 2), orthoHeight: 1.5)
        v3.phaseID = phase
        v3.detailLevel = .fine
        let threeD = tx.create(.views, name: "{3D}", data: .view(v3))

        // The eight framing planes: centres and Bottom define the origin and are pinned.
        let ext = (x: (-defaultWidth / 2 - FurniturePlanes.margin)...(defaultWidth / 2 + FurniturePlanes.margin),
                   y: (-defaultDepth / 2 - FurniturePlanes.margin)...(defaultDepth / 2 + FurniturePlanes.margin),
                   z: (-FurniturePlanes.margin)...(defaultHeight + FurniturePlanes.margin))
        var planes: [String: ElementID] = [:]
        for (n, axis, formula, strength, origin, at) in planeSpecs {
            let rp = FurniturePlanes.make(axis: axis, formula: formula, strength: strength, origin: origin, at: at, extents: ext)
            planes[n] = tx.create(.referencePlanes, name: n, data: .referencePlane(rp)) { $0.pinned = origin }
        }

        // Labelled dimensions with EQ about the centres: plan (Width, Depth), Front (Width, Height), Left (Depth).
        let dimType = annotation[AnnotationTypes.dimensionSpecs(units)[0].name] ?? tx.model.types(for: .dimensions).first?.id
        func ref(_ n: String) -> GeometryReference { GeometryReference(planes[n], .location) }
        func dim(_ view: ElementID, _ refs: [String], at p: Vec2, label: String? = nil, eq: Bool = false) {
            var d = DimensionData(kind: .aligned, references: refs.map(ref), linePoint: p)
            d.labelParameter = label
            d.equality = eq
            tx.create(.dimensions, data: .dimension(d), typeID: dimType, ownerViewID: view)
        }
        let inch = 0.0254
        let front = -defaultDepth / 2, right = defaultWidth / 2
        dim(planID, ["Left", "Right"], at: Vec2(0, front - 10 * inch), label: "Width")
        dim(planID, ["Left", "Center (Left/Right)", "Right"], at: Vec2(0, front - 6 * inch), eq: true)
        dim(planID, ["Front", "Back"], at: Vec2(right + 10 * inch, 0), label: "Depth")
        dim(planID, ["Front", "Center (Front/Back)", "Back"], at: Vec2(right + 6 * inch, 0), eq: true)
        if let fe = elevations["Front"] {
            dim(fe, ["Left", "Right"], at: Vec2(0, -8 * inch), label: "Width")
            dim(fe, ["Left", "Center (Left/Right)", "Right"], at: Vec2(0, -4 * inch), eq: true)
            dim(fe, ["Bottom", "Top"], at: Vec2(right + 8 * inch, 0), label: "Height")
        }
        if let le = elevations["Left"] {
            dim(le, ["Front", "Back"], at: Vec2(0, -8 * inch), label: "Depth")
            dim(le, ["Front", "Center (Front/Back)", "Back"], at: Vec2(0, -4 * inch), eq: true)
        }

        // The shop drawing sheet (Tabloid, 11" x 17") with the plan, front and right elevations and the 3D view.
        let sheet = tx.create(.sheets, name: "Shop Drawing", data: .sheet(SheetData(number: "F101", paper: .ansiB, titleBlockTypeID: titleBlocks["Tabloid Title Block"])))
        let placements: [(ElementID?, Vec2, String)] = [(planID, Vec2(0.10, 0.20), "1"), (elevations["Front"], Vec2(0.10, 0.08), "2"),
                                                        (elevations["Right"], Vec2(0.22, 0.08), "3"), (threeD, Vec2(0.23, 0.19), "4")]
        for (view, center, number) in placements {
            guard let view else { continue }
            tx.create(.viewports, data: .viewport(ViewportData(viewID: view, center: center, detailNumber: number)), ownerViewID: sheet)
        }
        // FM7 schedules: Part List, Hardware Schedule and Material Takeoff are added by the fabrication milestone.
    }

    /// The eight framing planes: name, axis, offset formula, strength, origin, position at the default size.
    static let planeSpecs: [(String, FamilyAxis, String?, ReferenceStrength, Bool, Double)] = [
        ("Center (Left/Right)", .x, nil, .centerLeftRight, true, 0),
        ("Center (Front/Back)", .y, nil, .centerFrontBack, true, 0),
        ("Left", .x, "-Width / 2", .left, false, -defaultWidth / 2),
        ("Right", .x, "Width / 2", .right, false, defaultWidth / 2),
        ("Front", .y, "-Depth / 2", .front, false, -defaultDepth / 2),
        ("Back", .y, "Depth / 2", .back, false, defaultDepth / 2),
        ("Bottom", .z, nil, .bottom, true, 0),
        ("Top", .z, "Height", .top, false, defaultHeight),
    ]

    /// A type name from its size in inches: 36" x 18" x 30".
    public static func typeName(_ w: Double, _ d: Double, _ h: Double) -> String {
        func inches(_ v: Double) -> String {
            let i = v / 0.0254
            let r = (i * 8).rounded() / 8
            return r == r.rounded() ? "\(Int(r))\"" : String(format: "%g\"", r)
        }
        return "\(inches(w)) x \(inches(d)) x \(inches(h))"
    }
}
