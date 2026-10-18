import Foundation
import ArcusGeometry
import ArcusDomain

/// Builds one IFC file (all storeys, or one storey when splitting) from an `ExportPlan`.
final class IFCFileBuilder {
    let model: BIMModel
    let options: IFCExportOptions
    let plan: ExportPlan
    let storeyIndices: [Int]
    let fileName: String
    let schema: IFCSchema
    let is4: Bool
    let writer = STEPWriter()
    private(set) var warnings: [String] = []
    private(set) var exportedElements: Set<ElementID> = []
    /// Internal coordinates of the IFC origin (coordinate base).
    let base: Vec3
    let timeStamp: Date

    // Context entities.
    var ownerHistory = 0
    var geomContext = 0
    var bodyContext = 0
    var axisContext = 0
    var metreUnit = 0
    var projectEntity = 0
    var siteEntity = 0
    var sitePlacement = 0
    var siteGUID: IFCGUID
    var buildingEntity = 0
    var buildingPlacement = 0
    var storeyEntity: [Int: Int] = [:]
    var storeyPlacement: [Int: Int] = [:]

    // Caches and relationship accumulators (all iterated in sorted / insertion order for determinism).
    private var points3: [String: Int] = [:]
    private var points2: [String: Int] = [:]
    private var dirs: [String: Int] = [:]
    private var placements: [String: Int] = [:]
    private var styles: [String: Int] = [:]
    private var materialEntities: [ElementID: Int] = [:]
    private var layerSets: [ElementID: Int] = [:]
    private var materialDefs: [String: Int] = [:]
    private var materialAssoc: [Int: [Int]] = [:]
    private var materialAssocKey: [Int: String] = [:]
    private var types: [ElementID: Int] = [:]
    private var typeOrder: [ElementID] = []
    private var typeInstances: [ElementID: [Int]] = [:]
    private var classificationSystems: [String: Int] = [:]
    private var classificationRefs: [String: Int] = [:]
    private var classificationRefKeys: [Int: String] = [:]
    private var classificationAssoc: [Int: [Int]] = [:]
    private var contained: [Int: [Int]] = [:]
    private var siteContained: [Int] = []
    private var spaces: [Int: [Int]] = [:]
    private var elementEntity: [ElementID: Int] = [:]
    private var openingForInsert: [ElementID: Int] = [:]
    private var siteItems: [Int] = []
    private var siteItemsType = "Brep"

    init(model: BIMModel, options: IFCExportOptions, plan: ExportPlan, storeyIndices: [Int], fileName: String) {
        self.model = model
        self.options = options
        self.plan = plan
        self.storeyIndices = storeyIndices
        self.fileName = fileName
        schema = options.schema
        is4 = options.schema == .ifc4
        timeStamp = options.timeStamp ?? Date()
        let info = model.projectInfo
        switch options.coordinateBase {
        case .internalOrigin: base = .zero
        case .projectBasePoint: base = info.projectBasePoint
        case .sharedCoordinates: base = info.surveyPoint
        }
        siteGUID = IFCGUID.deterministic("\(plan.projectGUID.value)/site")
    }

    func warn(_ s: String) { if !warnings.contains(s) { warnings.append(s) } }

    func guid(_ seed: String) -> STEPValue { .s(IFCGUID.deterministic(seed).value) }

    // MARK: - Build

    /// `tick` is called once per element and returns true to cancel.
    func build(elements: [PlannedElement], tick: () -> Bool) throws -> Data {
        writeContext()
        writeSpatialStructure()
        if !is4 {
            for pe in elements where pe.kind == .geographic { addSiteTopography(pe.element) }
        }
        for pe in elements where pe.kind != .group {
            if tick() { throw IFCError.cancelled }
            if pe.kind == .geographic && !is4 { exportedElements.insert(pe.element.id); continue }
            exportElement(pe)
        }
        for pe in elements where pe.kind == .group {
            if tick() { throw IFCError.cancelled }
            exportGroup(pe.element)
        }
        writeFills()
        defineSite()
        writeRelationships()

        var header = STEPHeader()
        header.description = ["ViewDefinition [\(schema.viewDefinition)]"]
        header.implementationLevel = "2;1"
        header.name = fileName
        header.timeStamp = Self.isoTimestamp(timeStamp)
        header.author = [options.authorName]
        header.organization = [options.organization]
        header.preprocessorVersion = "Arcus IFC \(options.applicationVersion)"
        header.originatingSystem = "Arcus \(options.applicationVersion)"
        header.authorization = ""
        header.schemas = [schema.rawValue]
        return writer.serialize(header: header)
    }

    static func isoTimestamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: d)
    }

    // MARK: - Geometry primitives

    func point(_ p: Vec3) -> Int {
        let key = "\(STEPFormat.real(p.x)),\(STEPFormat.real(p.y)),\(STEPFormat.real(p.z))"
        if let id = points3[key] { return id }
        let id = writer.add("IfcCartesianPoint", [.reals([p.x, p.y, p.z])])
        points3[key] = id
        return id
    }

    func point2(_ p: Vec2) -> Int {
        let key = "\(STEPFormat.real(p.x)),\(STEPFormat.real(p.y))"
        if let id = points2[key] { return id }
        let id = writer.add("IfcCartesianPoint", [.reals([p.x, p.y])])
        points2[key] = id
        return id
    }

    func direction(_ v: [Double]) -> Int {
        let key = v.map(STEPFormat.real).joined(separator: ",")
        if let id = dirs[key] { return id }
        let id = writer.add("IfcDirection", [.reals(v)])
        dirs[key] = id
        return id
    }

    /// IfcAxis2Placement3D for a rigid transform (axes omitted when they are the defaults).
    func axisPlacement(_ t: Transform3) -> Int {
        let loc = point(t.origin)
        let z = t.zAxis.normalized, x = t.xAxis.normalized
        let args: [STEPValue]
        if z.isAlmostEqual(.unitZ, tolerance: 1e-9) && x.isAlmostEqual(.unitX, tolerance: 1e-9) {
            args = [.r(loc), .null, .null]
        } else {
            args = [.r(loc), .r(direction([z.x, z.y, z.z])), .r(direction([x.x, x.y, x.z]))]
        }
        let key = args.map(\.description).joined(separator: ",")
        if let id = placements[key] { return id }
        let id = writer.add("IfcAxis2Placement3D", args)
        placements[key] = id
        return id
    }

    func localPlacement(relativeTo parent: Int?, _ t: Transform3) -> Int {
        writer.add("IfcLocalPlacement", [.rOpt(parent), .r(axisPlacement(t))])
    }

    /// Rigid frame in export (shifted) coordinates from an internal-coordinate origin and plan x direction.
    func frame(origin: Vec3, xDir: Vec2) -> Transform3 {
        let d = xDir.lengthSquared > 1e-18 ? xDir.normalized : Vec2(1, 0)
        return Transform3.frame(origin: origin - base, xAxis: Vec3(d, z: 0), yAxis: Vec3(d.perpendicular, z: 0))
    }

    /// World transform (export coordinates) of a storey placement.
    func storeyTransform(_ k: Int?) -> Transform3 {
        guard let k else { return .identity }
        return .translation(Vec3(0, 0, plan.storeys[k].elevation - base.z))
    }

    // MARK: - Context

    func writeContext() {
        let person = writer.add("IfcPerson", [.null, .s(options.authorName.isEmpty ? "Unknown" : options.authorName), .null, .null, .null, .null, .null, .null])
        let org = writer.add("IfcOrganization", [.null, .s(options.organization.isEmpty ? (model.projectInfo.organization.isEmpty ? "Unknown" : model.projectInfo.organization) : options.organization), .null, .null, .null])
        let pando = writer.add("IfcPersonAndOrganization", [.r(person), .r(org), .null])
        let dev = writer.add("IfcOrganization", [.null, .s("Arcus"), .null, .null, .null])
        let app = writer.add("IfcApplication", [.r(dev), .s(options.applicationVersion), .s("Arcus"), .s("Arcus")])
        ownerHistory = writer.add("IfcOwnerHistory", [.r(pando), .r(app), .null, .e("ADDED"), .null, .null, .null, .integer(Int(timeStamp.timeIntervalSince1970))])

        metreUnit = writer.add("IfcSIUnit", [.derived, .e("LENGTHUNIT"), .null, .e("METRE")])
        let area = writer.add("IfcSIUnit", [.derived, .e("AREAUNIT"), .null, .e("SQUARE_METRE")])
        let volume = writer.add("IfcSIUnit", [.derived, .e("VOLUMEUNIT"), .null, .e("CUBIC_METRE")])
        let angle = writer.add("IfcSIUnit", [.derived, .e("PLANEANGLEUNIT"), .null, .e("RADIAN")])
        let units = writer.add("IfcUnitAssignment", [.refs([metreUnit, area, volume, angle])])

        let wcs = axisPlacement(.identity)
        let a = model.projectInfo.trueNorthAngle
        let north = direction([-sin(a), cos(a)])
        geomContext = writer.add("IfcGeometricRepresentationContext", [.null, .s("Model"), .integer(3), .d(1e-5), .r(wcs), .r(north)])
        bodyContext = writer.add("IfcGeometricRepresentationSubContext", [.s("Body"), .s("Model"), .derived, .derived, .derived, .derived, .r(geomContext), .null, .e("MODEL_VIEW"), .null])
        axisContext = writer.add("IfcGeometricRepresentationSubContext", [.s("Axis"), .s("Model"), .derived, .derived, .derived, .derived, .r(geomContext), .null, .e("GRAPH_VIEW"), .null])

        let info = model.projectInfo
        let name = info.projectNumber.isEmpty ? info.projectName : info.projectNumber
        projectEntity = writer.add("IfcProject", [.s(plan.projectGUID.value), .r(ownerHistory), .sOpt(name), .null, .null, .sOpt(info.projectName), .sOpt(info.status),
                                                  .refs([geomContext]), .r(units)])

        if options.coordinateBase == .sharedCoordinates && is4 {
            let crs = writer.add("IfcProjectedCRS", [.s("Arcus Shared Coordinates"),
                                                     .s("Survey point shared coordinates. The geodetic coordinate reference system is not specified in Arcus."),
                                                     .null, .null, .null, .null, .r(metreUnit)])
            writer.add("IfcMapConversion", [.r(geomContext), .r(crs), .d(info.surveyEasting), .d(info.surveyNorthing), .d(info.surveyElevation),
                                             .d(cos(-a)), .d(sin(-a)), .d(1)])
        }
    }

    func writeSpatialStructure() {
        let info = model.projectInfo
        sitePlacement = localPlacement(relativeTo: nil, .identity)
        siteEntity = writer.reserve()
        buildingPlacement = localPlacement(relativeTo: sitePlacement, .identity)
        var address: STEPValue = .null
        if !info.address.isEmpty {
            let lines = info.address.split(whereSeparator: \.isNewline).map { STEPValue.s(String($0)) }
            address = .r(writer.add("IfcPostalAddress", [.null, .null, .null, .null, .list(lines), .null, .null, .null, .null, .null]))
        }
        buildingEntity = writer.add("IfcBuilding", [.s(IFCGUID.deterministic("\(plan.projectGUID.value)/building").value), .r(ownerHistory),
                                                    .s(info.buildingName.isEmpty ? "Building" : info.buildingName), .null, .null, .r(buildingPlacement), .null, .null,
                                                    .e("ELEMENT"), .null, .null, address])
        for k in storeyIndices {
            let s = plan.storeys[k]
            let pl = localPlacement(relativeTo: buildingPlacement, storeyTransform(k))
            storeyPlacement[k] = pl
            storeyEntity[k] = writer.add("IfcBuildingStorey", [.s(s.guid.value), .r(ownerHistory), .sOpt(s.name), .null, .null, .r(pl), .null, .null,
                                                               .e("ELEMENT"), .d(s.elevation - base.z)])
        }
        if options.coordinateBase == .sharedCoordinates && !is4 {
            writePset(owner: siteGUID.value, name: "Arcus_SharedCoordinates", objects: [siteEntity], props: [
                ("Eastings", .lengthMeasure(info.surveyEasting)), ("Northings", .lengthMeasure(info.surveyNorthing)),
                ("OrthogonalHeight", .lengthMeasure(info.surveyElevation)), ("TrueNorthAngle", .measure(info.trueNorthAngle, "IFCPLANEANGLEMEASURE")),
            ])
        }
    }

    func defineSite() {
        let info = model.projectInfo
        var shape: STEPValue = .null
        if !siteItems.isEmpty {
            let rep = writer.add("IfcShapeRepresentation", [.r(bodyContext), .s("Body"), .s(siteItemsType), .refs(siteItems)])
            shape = .r(writer.add("IfcProductDefinitionShape", [.null, .null, .refs([rep])]))
        }
        let hasGeo = info.latitude != 0 || info.longitude != 0
        writer.define(siteEntity, "IfcSite", [.s(siteGUID.value), .r(ownerHistory), .sOpt(info.siteName.isEmpty ? "Site" : info.siteName), .null, .null,
                                              .r(sitePlacement), shape, .null, .e("ELEMENT"),
                                              hasGeo ? Self.compoundAngle(info.latitude) : .null, hasGeo ? Self.compoundAngle(info.longitude) : .null,
                                              .d(info.elevationAboveSeaLevel), .null, .null])
    }

    /// IfcCompoundPlaneAngleMeasure (degrees, minutes, seconds, millionths of a second), all with the same sign.
    static func compoundAngle(_ deg: Double) -> STEPValue {
        let sign = deg < 0 ? -1 : 1
        var rest = abs(deg)
        let d = Int(rest.rounded(.down)); rest = (rest - Double(d)) * 60
        let m = Int(rest.rounded(.down)); rest = (rest - Double(m)) * 60
        let s = Int(rest.rounded(.down)); rest = (rest - Double(s)) * 1_000_000
        let u = min(999_999, Int(rest.rounded()))
        return .list([.integer(sign * d), .integer(sign * m), .integer(sign * s), .integer(sign * u)])
    }

    // MARK: - Elements

    func displayName(_ e: Element) -> String {
        if !e.name.isEmpty { return e.name }
        if let t = model.type(of: e), let td = t.typeData { return td.familyName.isEmpty ? t.name : "\(td.familyName): \(t.name)" }
        return e.category.singularName
    }

    func typeLabel(_ e: Element) -> String? {
        guard let t = model.type(of: e), let td = t.typeData else { return nil }
        return td.familyName.isEmpty ? t.name : "\(td.familyName): \(t.name)"
    }

    /// Writes an IfcElement subtype with the 8 common attributes plus `tail`.
    func product(_ e: Element, _ cls: String, placement: Int, shape: Int?, tail: [STEPValue], name: String? = nil, objectType: String? = nil) -> Int {
        writer.add(cls, [.s(e.ifcGUID.value), .r(ownerHistory), .sOpt(name ?? displayName(e)), .null, .sOpt(objectType ?? typeLabel(e)),
                         .r(placement), .rOpt(shape), .sOpt(e.mark)] + tail)
    }

    func register(_ e: Element, _ ent: Int, storey: Int?) {
        elementEntity[e.id] = ent
        exportedElements.insert(e.id)
        if let k = storey { contained[k, default: []].append(ent) } else { siteContained.append(ent) }
    }

    func shape(_ reps: [Int]) -> Int? {
        reps.isEmpty ? nil : writer.add("IfcProductDefinitionShape", [.null, .null, .refs(reps)])
    }

    func exportElement(_ pe: PlannedElement) {
        let e = pe.element
        let k = pe.storey
        let S = storeyTransform(k)
        let parent = k.flatMap { storeyPlacement[$0] } ?? sitePlacement
        switch pe.kind {
        case .wall:
            exportWall(e, storey: k ?? 0)
            return
        case .space:
            exportSpace(e, storey: k ?? 0)
            return
        case .slab, .covering:
            exportSlab(e, kind: pe.kind, storey: k ?? 0)
            return
        default:
            break
        }

        // Placement.
        var W = S
        switch pe.kind {
        case .door, .window:
            if let pl = InsertGeometry.placement(e, model) { W = frame(origin: pl.world.origin, xDir: pl.world.xAxis.xy) }
        case .column, .furniture, .sanitary, .proxy, .light, .vegetation: // W2-LIB: light, vegetation
            if let pl = ComponentGeometry.placement(e, model) { W = frame(origin: pl.world.origin, xDir: pl.world.xAxis.xy) }
        default:
            break
        }
        let placement = localPlacement(relativeTo: parent, S.inverse * W)
        let parts = GeometryCache.shared.parts(e, model, detail: .fine)
        let toLocal = W.inverse * Transform3.translation(-base)
        var reps: [Int] = []
        if let body = meshItems(parts, toLocal: toLocal, category: e.category) {
            reps.append(writer.add("IfcShapeRepresentation", [.r(bodyContext), .s("Body"), .s(body.type), .refs(body.items)]))
        }
        let shp = shape(reps)
        let mats = distinctMaterials(parts)

        let ent: Int
        switch pe.kind {
        case .door, .window:
            let isDoor = pe.kind == .door
            let w = familyLength(e, "Width") ?? InsertGeometry.openingSize(e, model)?.width ?? 0
            let h = familyLength(e, "Height") ?? InsertGeometry.openingSize(e, model)?.height ?? 0
            var tail: [STEPValue] = [w > 0 ? .d(h) : .null, w > 0 ? .d(w) : .null]
            if is4 { tail += [.e(isDoor ? "DOOR" : "WINDOW"), .e("NOTDEFINED"), .null] }
            ent = product(e, isDoor ? "IfcDoor" : "IfcWindow", placement: placement, shape: shp, tail: tail)
        case .roof:
            let slopes = e.roof?.edgeSlopes ?? []
            let shapeType: String
            if e.roof?.extrusion != nil { shapeType = "NOTDEFINED" }
            else if slopes.allSatisfy({ ($0 ?? 0) < 1e-6 }) { shapeType = "FLAT_ROOF" }
            else if slopes.allSatisfy({ ($0 ?? 0) > 1e-6 }) { shapeType = "HIP_ROOF" }
            else { shapeType = "GABLE_ROOF" }
            ent = product(e, "IfcRoof", placement: placement, shape: shp, tail: [.e(shapeType)])
        case .column:
            ent = product(e, "IfcColumn", placement: placement, shape: shp, tail: is4 ? [.e("COLUMN")] : [])
        case .beam:
            ent = product(e, "IfcBeam", placement: placement, shape: shp, tail: is4 ? [.e("BEAM")] : [])
        case .stair:
            let t: String
            switch e.stair?.shape ?? .straight {
            case .straight: t = "STRAIGHT_RUN_STAIR"
            case .lShaped: t = "QUARTER_TURN_STAIR"
            case .uShaped: t = "HALF_TURN_STAIR"
            }
            ent = product(e, "IfcStair", placement: placement, shape: shp, tail: [.e(t)])
        case .ramp:
            ent = product(e, "IfcRamp", placement: placement, shape: shp, tail: [.e(Self.rampShapeType(e.ramp?.path ?? []))])
        case .railing:
            let hand = (model.type(of: e)?.name ?? "").localizedCaseInsensitiveContains("handrail")
            ent = product(e, "IfcRailing", placement: placement, shape: shp, tail: [.e(hand ? "HANDRAIL" : "GUARDRAIL")])
        case .furniture:
            ent = is4 ? product(e, "IfcFurniture", placement: placement, shape: shp, tail: [.e("NOTDEFINED")])
                      : product(e, "IfcFurnishingElement", placement: placement, shape: shp, tail: [])
        case .sanitary:
            ent = is4 ? product(e, "IfcSanitaryTerminal", placement: placement, shape: shp, tail: [.e("NOTDEFINED")])
                      : product(e, "IfcFlowTerminal", placement: placement, shape: shp, tail: [])
        case .geographic:
            ent = product(e, "IfcGeographicElement", placement: placement, shape: shp, tail: [.e("TERRAIN")])
        case .light: // W2-LIB: IFC2X3 CV2.0 has no light fixture occurrence
            ent = is4 ? product(e, "IfcLightFixture", placement: placement, shape: shp, tail: [.e("NOTDEFINED")])
                      : product(e, "IfcFlowTerminal", placement: placement, shape: shp, tail: [])
        case .vegetation: // W2-LIB: IFC2X3 has no geographic element
            ent = is4 ? product(e, "IfcGeographicElement", placement: placement, shape: shp, tail: [.e("NOTDEFINED")])
                      : product(e, "IfcBuildingElementProxy", placement: placement, shape: shp, tail: [.null])
        case .reference(let recorded):
            let props = e.referenceGeometry?.properties ?? [:]
            let name = props["Name"].flatMap { $0.isEmpty ? nil : $0 } ?? displayName(e)
            if let (cls, tail) = IFCClassTable.exportable(recorded, schema: schema) {
                ent = product(e, cls, placement: placement, shape: shp, tail: tail, name: name, objectType: props["ObjectType"])
            } else {
                warn("Reference elements of class \(recorded.isEmpty ? "(unknown)" : recorded) are not valid in \(schema.rawValue) and were exported as IfcBuildingElementProxy.")
                ent = product(e, "IfcBuildingElementProxy", placement: placement, shape: shp, tail: is4 ? [.e("NOTDEFINED")] : [.null],
                              name: name, objectType: props["ObjectType"] ?? recorded)
            }
        default: // proxy
            ent = product(e, "IfcBuildingElementProxy", placement: placement, shape: shp, tail: is4 ? [.e("NOTDEFINED")] : [.null])
        }
        register(e, ent, storey: k)
        if shp == nil { warn("Some elements had no 3D geometry and were exported without a body representation.") }
        associateMaterials(mats, object: ent)
        attachType(e, kind: pe.kind, instance: ent)
        writeElementProperties(e, entity: ent, kind: pe.kind)
        writeQuantities(e, entity: ent, kind: pe.kind)
        classify(e, entity: ent)
    }

    func familyLength(_ e: Element, _ name: String) -> Double? {
        Parameters.value(Parameters.familyParamID(name), of: e, model)?.doubleValue
    }

    // MARK: Walls

    func exportWall(_ e: Element, storey k: Int) {
        if CurtainWallGeometry.isCurtain(e, model) { exportCurtainWall(e, storey: k); return } // WP3
        guard let w = e.wall, let f = WallGeometry.frame(e, model) else { return }
        let S = storeyTransform(k)
        let W = frame(origin: Vec3(w.location.start, z: f.baseZ), xDir: w.location.tangent(at: 0))
        let placement = localPlacement(relativeTo: storeyPlacement[k], S.inverse * W)
        let toLocal = W.inverse * Transform3.translation(-base)

        // Axis: the location line in the wall's local frame.
        let axisPts = w.location.tessellate(chordTolerance: 0.01).map { toLocal.apply(Vec3($0, z: f.baseZ)).xy }
        let polyline = writer.add("IfcPolyline", [.refs(axisPts.map(point2))])
        let axisRep = writer.add("IfcShapeRepresentation", [.r(axisContext), .s("Axis"), .s("Curve2D"), .refs([polyline])])

        let exteriorMaterial = f.assembly.layers.first?.materialID
        let standard = !is4 && f.isStraight && w.profile == nil && abs(w.slantAngle) < 1e-9 && w.attachedTopIDs.isEmpty && w.attachedBaseIDs.isEmpty
        var bodyRep: Int?
        var usedStandard = false
        if standard, let fp = WallGeometry.footprint(e, model), fp.count >= 3 {
            let local = Polygon2(fp.points.map { toLocal.apply(Vec3($0, z: f.baseZ)).xy }).counterClockwise
            let solid = extrudedSolid(Profile2(outer: local), bottom: 0, depth: f.height)
            styleItem(solid, material: exteriorMaterial, category: .walls)
            bodyRep = writer.add("IfcShapeRepresentation", [.r(bodyContext), .s("Body"), .s("SweptSolid"), .refs([solid])])
            usedStandard = true
        } else {
            let parts = GeometryCache.shared.parts(e, model, detail: .fine)
            if let body = meshItems(parts, toLocal: toLocal, category: .walls) {
                bodyRep = writer.add("IfcShapeRepresentation", [.r(bodyContext), .s("Body"), .s(body.type), .refs(body.items)])
            }
        }
        let shp = shape([axisRep] + (bodyRep.map { [$0] } ?? []))
        let cls = is4 ? "IfcWall" : (usedStandard ? "IfcWallStandardCase" : "IfcWall")
        let ent = product(e, cls, placement: placement, shape: shp, tail: is4 ? [.e("NOTDEFINED")] : [])
        register(e, ent, storey: k)

        // Material layer set usage: layers run from the exterior face; exterior is on the left (+y) unless flipped.
        if let t = model.type(of: e), let ls = layerSet(for: t) {
            let sense = f.flipped ? "POSITIVE" : "NEGATIVE"
            let key = "usage/\(t.ifcGUID.value)/AXIS2/\(sense)/\(STEPFormat.real(f.exteriorOffset))"
            let usage = materialDef(key) {
                writer.add("IfcMaterialLayerSetUsage", [.r(ls), .e("AXIS2"), .e(sense), .d(f.exteriorOffset)] + (is4 ? [.null] : []))
            }
            addMaterialAssoc(usage, key: key, object: ent)
        } else {
            associateMaterials(exteriorMaterial.map { [$0] } ?? [], object: ent)
        }
        attachType(e, kind: .wall, instance: ent)
        writeElementProperties(e, entity: ent, kind: .wall)
        writeQuantities(e, entity: ent, kind: .wall)
        classify(e, entity: ent)
        exportOpenings(e, frame: f, wallWorld: W, wallPlacement: placement, wallEntity: ent)
    }

    func exportOpenings(_ wall: Element, frame f: WallFrame, wallWorld W: Transform3, wallPlacement: Int, wallEntity: Int) {
        let margin = 0.01
        for op in WallGeometry.openings(wall, model) {
            guard let ins = model[op.insertID] else { continue }
            let mid = (op.s0 + op.s1) / 2
            let p = WallGeometry.point(atStation: mid, on: f.location)
            let t = f.length > 0 ? min(1, max(0, mid / f.length)) : 0
            let tan = f.location.tangent(at: t)
            let center = p + tan.perpendicular * f.centerOffset
            let O = frame(origin: Vec3(center, z: op.z0), xDir: tan)
            let pl = localPlacement(relativeTo: wallPlacement, W.inverse * O)
            let pos2 = writer.add("IfcAxis2Placement2D", [.r(point2(.zero)), .null])
            let profile = writer.add("IfcRectangleProfileDef", [.e("AREA"), .null, .r(pos2), .d(op.s1 - op.s0), .d(f.thickness + 2 * margin)])
            let solid = writer.add("IfcExtrudedAreaSolid", [.r(profile), .r(axisPlacement(.identity)), .r(direction([0, 0, 1])), .d(op.z1 - op.z0)])
            let rep = writer.add("IfcShapeRepresentation", [.r(bodyContext), .s("Body"), .s("SweptSolid"), .refs([solid])])
            let shp = writer.add("IfcProductDefinitionShape", [.null, .null, .refs([rep])])
            let g = ins.ifcGUID.value
            let opening = writer.add("IfcOpeningElement", [guid("\(g)/opening"), .r(ownerHistory), .s("Opening"), .null, .s("Opening"), .r(pl), .r(shp), .null]
                                     + (is4 ? [.e("OPENING")] : []))
            writer.add("IfcRelVoidsElement", [guid("\(g)/voids"), .r(ownerHistory), .null, .null, .r(wallEntity), .r(opening)])
            openingForInsert[ins.id] = opening
        }
    }

    func writeFills() {
        for (insertID, opening) in openingForInsert.sorted(by: { $0.key < $1.key }) {
            guard let ent = elementEntity[insertID], let ins = model[insertID] else { continue }
            writer.add("IfcRelFillsElement", [guid("\(ins.ifcGUID.value)/fills"), .r(ownerHistory), .null, .null, .r(opening), .r(ent)])
        }
    }

    // MARK: Slabs, coverings, spaces

    func exportSlab(_ e: Element, kind: ExportKind, storey k: Int) {
        let S = storeyTransform(k)
        let placement = localPlacement(relativeTo: storeyPlacement[k], .identity)
        let toLocal = S.inverse * Transform3.translation(-base)
        let levelZ = plan.storeys[k].elevation
        var bodyRep: Int?
        let primary = SlabGeometry.primaryMaterial(e, model)
        if !is4, e.slab?.slopeArrow == nil, ShaftCuts.cutProfiles(e, model) == nil, let prof = SlabGeometry.profile(e), let (b, _) = SlabGeometry.planes(e, model) {
            let th = SlabGeometry.thickness(e, model)
            let local = Profile2(outer: prof.outer.transformed(.translation(-base.xy)), holes: prof.holes.map { $0.transformed(.translation(-base.xy)) })
            let solid = extrudedSolid(local, bottom: b.c - levelZ, depth: th)
            styleItem(solid, material: primary, category: e.category)
            bodyRep = writer.add("IfcShapeRepresentation", [.r(bodyContext), .s("Body"), .s("SweptSolid"), .refs([solid])])
        } else {
            let parts = GeometryCache.shared.parts(e, model, detail: .fine)
            if let body = meshItems(parts, toLocal: toLocal, category: e.category) {
                bodyRep = writer.add("IfcShapeRepresentation", [.r(bodyContext), .s("Body"), .s(body.type), .refs(body.items)])
            }
        }
        let shp = shape(bodyRep.map { [$0] } ?? [])
        let ent: Int
        if case .slab(let predefined) = kind {
            ent = product(e, "IfcSlab", placement: placement, shape: shp, tail: [.e(predefined)])
        } else {
            ent = product(e, "IfcCovering", placement: placement, shape: shp, tail: [.e("CEILING")])
        }
        register(e, ent, storey: k)
        if let t = model.type(of: e), let ls = layerSet(for: t) {
            if kind != .covering, e.slab?.slopeArrow == nil, let (_, top) = SlabGeometry.planes(e, model) {
                let offset = top.c - levelZ
                let key = "usage/\(t.ifcGUID.value)/AXIS3/NEGATIVE/\(STEPFormat.real(offset))"
                let usage = materialDef(key) {
                    writer.add("IfcMaterialLayerSetUsage", [.r(ls), .e("AXIS3"), .e("NEGATIVE"), .d(offset)] + (is4 ? [.null] : []))
                }
                addMaterialAssoc(usage, key: key, object: ent)
            } else {
                addMaterialAssoc(ls, key: "layerset/\(t.ifcGUID.value)", object: ent)
            }
        } else {
            associateMaterials(primary.map { [$0] } ?? [], object: ent)
        }
        attachType(e, kind: kind, instance: ent)
        writeElementProperties(e, entity: ent, kind: kind)
        writeQuantities(e, entity: ent, kind: kind)
        classify(e, entity: ent)
    }

    func exportSpace(_ e: Element, storey k: Int) {
        guard let room = e.room, let prof = RoomGeometry.boundary(e, model).profile else { return }
        let z0 = model.baseElevation(of: e)
        let h = RoomGeometry.height(e, model)
        let S = storeyTransform(k)
        let W = Transform3.translation(Vec3(0, 0, z0 - base.z))
        let placement = localPlacement(relativeTo: storeyPlacement[k], S.inverse * W)
        var bodyRep: Int?
        let local = Profile2(outer: prof.outer.transformed(.translation(-base.xy)), holes: prof.holes.map { $0.transformed(.translation(-base.xy)) })
        if is4 {
            let mesh = MeshBuilder.extrude(local, bottom: 0, top: h)
            if let body = meshItems([MeshPart(mesh: mesh, materialID: nil)], toLocal: .identity, category: .rooms) {
                bodyRep = writer.add("IfcShapeRepresentation", [.r(bodyContext), .s("Body"), .s(body.type), .refs(body.items)])
            }
        } else {
            let solid = extrudedSolid(local, bottom: 0, depth: h)
            bodyRep = writer.add("IfcShapeRepresentation", [.r(bodyContext), .s("Body"), .s("SweptSolid"), .refs([solid])])
        }
        let shp = shape(bodyRep.map { [$0] } ?? [])
        let args: [STEPValue] = [.s(e.ifcGUID.value), .r(ownerHistory), .sOpt(room.number), .null, .null, .r(placement), .rOpt(shp), .sOpt(e.name),
                                 .e("ELEMENT"), is4 ? .e("SPACE") : .e("INTERNAL"), .null]
        let ent = writer.add("IfcSpace", args)
        elementEntity[e.id] = ent
        exportedElements.insert(e.id)
        spaces[k, default: []].append(ent)
        writeElementProperties(e, entity: ent, kind: .space)
        writeQuantities(e, entity: ent, kind: .space)
        classify(e, entity: ent)
    }

    /// Extrusion of a local profile along +Z from `bottom`.
    func extrudedSolid(_ p: Profile2, bottom: Double, depth: Double) -> Int {
        func polyline(_ poly: Polygon2) -> Int {
            var pts = poly.points.map(point2)
            if let f = pts.first { pts.append(f) }
            return writer.add("IfcPolyline", [.refs(pts)])
        }
        let outer = polyline(p.outer.counterClockwise)
        let profile: Int
        if p.holes.isEmpty {
            profile = writer.add("IfcArbitraryClosedProfileDef", [.e("AREA"), .null, .r(outer)])
        } else {
            let inner = p.holes.map { polyline($0.clockwise) }
            profile = writer.add("IfcArbitraryProfileDefWithVoids", [.e("AREA"), .null, .r(outer), .refs(inner)])
        }
        let pos = axisPlacement(.translation(Vec3(0, 0, bottom)))
        return writer.add("IfcExtrudedAreaSolid", [.r(profile), .r(pos), .r(direction([0, 0, 1])), .d(depth)])
    }

    // MARK: Topography (IFC2X3: site representation)

    func addSiteTopography(_ e: Element) {
        let parts = GeometryCache.shared.parts(e, model, detail: .fine)
        guard let body = meshItems(parts, toLocal: .translation(-base), category: .topography) else { return }
        if body.type != "Brep" { siteItemsType = "SurfaceModel" }
        siteItems.append(contentsOf: body.items)
    }

    // MARK: Groups

    func exportGroup(_ e: Element) {
        guard let g = e.group else { return }
        let members = g.members.compactMap { elementEntity[$0] }
        guard !members.isEmpty else { return }
        let ent = writer.add("IfcGroup", [.s(e.ifcGUID.value), .r(ownerHistory), .sOpt(e.name.isEmpty ? g.groupTypeName : e.name), .null, .sOpt(g.groupTypeName)])
        writer.add("IfcRelAssignsToGroup", [guid("\(e.ifcGUID.value)/assigns"), .r(ownerHistory), .null, .null, .refs(members), .null, .r(ent)])
        elementEntity[e.id] = ent
        exportedElements.insert(e.id)
    }

    // MARK: - Mesh bodies

    struct PreparedMesh {
        var positions: [Vec3]
        var triangles: [Int]
        var closed: Bool
        var material: ElementID?
    }

    /// Welds vertices (1 µm grid), drops degenerate triangles and checks closedness.
    static func prepare(_ mesh: Mesh, toLocal: Transform3) -> PreparedMesh? {
        var map: [SIMD3<Int64>: Int] = [:]
        var positions: [Vec3] = []
        var remap: [Int] = []
        remap.reserveCapacity(mesh.positions.count)
        for p in mesh.positions {
            let l = toLocal.apply(p)
            guard l.x.isFinite, l.y.isFinite, l.z.isFinite, abs(l.x) < 1e9, abs(l.y) < 1e9, abs(l.z) < 1e9 else { remap.append(-1); continue }
            let key = SIMD3<Int64>(Int64((l.x * 1e6).rounded()), Int64((l.y * 1e6).rounded()), Int64((l.z * 1e6).rounded()))
            if let i = map[key] { remap.append(i); continue }
            map[key] = positions.count
            remap.append(positions.count)
            positions.append(Vec3(Double(key.x) / 1e6, Double(key.y) / 1e6, Double(key.z) / 1e6))
        }
        var tris: [Int] = []
        var edges: [UInt64: Int] = [:]
        var i = 0
        while i + 2 < mesh.indices.count {
            let ia = Int(mesh.indices[i]), ib = Int(mesh.indices[i + 1]), ic = Int(mesh.indices[i + 2])
            i += 3
            guard ia < remap.count, ib < remap.count, ic < remap.count else { continue }
            let a = remap[ia], b = remap[ib], c = remap[ic]
            guard a >= 0, b >= 0, c >= 0, a != b, b != c, a != c else { continue }
            let area2 = (positions[b] - positions[a]).cross(positions[c] - positions[a]).length
            guard area2 > 1e-12 else { continue }
            tris.append(contentsOf: [a, b, c])
            for (u, v) in [(a, b), (b, c), (c, a)] {
                let key = UInt64(min(u, v)) << 32 | UInt64(max(u, v))
                edges[key, default: 0] += 1
            }
        }
        guard !tris.isEmpty else { return nil }
        let closed = edges.values.allSatisfy { $0 == 2 }
        return PreparedMesh(positions: positions, triangles: tris, closed: closed, material: nil)
    }

    /// Body items for mesh parts: IfcTriangulatedFaceSet (IFC4) or IfcFacetedBrep / IfcFaceBasedSurfaceModel (IFC2X3), styled per part.
    func meshItems(_ parts: [MeshPart], toLocal: Transform3, category: ArcusDomain.Category) -> (items: [Int], type: String)? {
        var prepared: [PreparedMesh] = []
        for p in parts {
            guard var pm = Self.prepare(p.mesh, toLocal: toLocal) else { continue }
            pm.material = p.materialID
            prepared.append(pm)
        }
        guard !prepared.isEmpty else { return nil }
        var items: [Int] = []
        if is4 {
            for pm in prepared {
                let list = writer.add("IfcCartesianPointList3D", [.list(pm.positions.map { .reals([$0.x, $0.y, $0.z]) })])
                var idx: [STEPValue] = []
                idx.reserveCapacity(pm.triangles.count / 3)
                for t in stride(from: 0, to: pm.triangles.count, by: 3) {
                    idx.append(.list([.integer(pm.triangles[t] + 1), .integer(pm.triangles[t + 1] + 1), .integer(pm.triangles[t + 2] + 1)]))
                }
                let item = writer.add("IfcTriangulatedFaceSet", [.r(list), .null, .b(pm.closed), .list(idx), .null])
                styleItem(item, material: pm.material, category: category)
                items.append(item)
            }
            return (items, "Tessellation")
        }
        let allClosed = prepared.allSatisfy(\.closed)
        for pm in prepared {
            let pts = pm.positions.map(point)
            var faces: [Int] = []
            for t in stride(from: 0, to: pm.triangles.count, by: 3) {
                let loop = writer.add("IfcPolyLoop", [.refs([pts[pm.triangles[t]], pts[pm.triangles[t + 1]], pts[pm.triangles[t + 2]]])])
                let bound = writer.add("IfcFaceOuterBound", [.r(loop), .b(true)])
                faces.append(writer.add("IfcFace", [.refs([bound])]))
            }
            let item: Int
            if allClosed {
                let shell = writer.add("IfcClosedShell", [.refs(faces)])
                item = writer.add("IfcFacetedBrep", [.r(shell)])
            } else {
                let set = writer.add("IfcConnectedFaceSet", [.refs(faces)])
                item = writer.add("IfcFaceBasedSurfaceModel", [.refs([set])])
            }
            styleItem(item, material: pm.material, category: category)
            items.append(item)
        }
        return (items, allClosed ? "Brep" : "SurfaceModel")
    }

    // MARK: - Styles and materials

    func styleItem(_ item: Int, material: ElementID?, category: ArcusDomain.Category) {
        let key = material.map { "m\($0.raw)" } ?? "c\(category.rawValue)"
        let style: Int
        if let s = styles[key] {
            style = s
        } else {
            var name = category.displayName
            var color = ElementMeshes.defaultColor(category)
            var transparency = 1 - color.a
            if let m = material.flatMap({ model[$0] }), let md = m.material {
                name = m.name
                color = md.color
                transparency = md.transparency
            }
            let rgb = writer.add("IfcColourRgb", [.null, .d(color.r), .d(color.g), .d(color.b)])
            let rendering = writer.add("IfcSurfaceStyleRendering", [.r(rgb), .d(max(0, min(1, transparency))), .null, .null, .null, .null, .null, .null, .e("NOTDEFINED")])
            let ss = writer.add("IfcSurfaceStyle", [.s(name), .e("BOTH"), .refs([rendering])])
            style = is4 ? ss : writer.add("IfcPresentationStyleAssignment", [.refs([ss])])
            styles[key] = style
        }
        writer.add("IfcStyledItem", [.r(item), .refs([style]), .null])
    }

    func material(_ id: ElementID) -> Int? {
        if let m = materialEntities[id] { return m }
        guard let m = model[id], let md = m.material else { return nil }
        let ent = is4 ? writer.add("IfcMaterial", [.s(m.name), .sOpt(md.description), .s(md.materialClass.rawValue)])
                      : writer.add("IfcMaterial", [.s(m.name)])
        materialEntities[id] = ent
        return ent
    }

    func materialDef(_ key: String, _ make: () -> Int) -> Int {
        if let d = materialDefs[key] { return d }
        let d = make()
        materialDefs[key] = d
        return d
    }

    func addMaterialAssoc(_ def: Int, key: String, object: Int) {
        materialAssoc[def, default: []].append(object)
        materialAssocKey[def] = key
    }

    func distinctMaterials(_ parts: [MeshPart]) -> [ElementID] {
        var out: [ElementID] = []
        for p in parts { if let m = p.materialID, model[m]?.material != nil, !out.contains(m) { out.append(m) } }
        return out
    }

    /// Associates one material (IfcMaterial) or several (IfcMaterialList in IFC2X3, IfcMaterialConstituentSet in IFC4).
    func associateMaterials(_ ids: [ElementID], object: Int) {
        let valid = ids.filter { model[$0]?.material != nil }
        guard !valid.isEmpty else { return }
        if valid.count == 1, let m = material(valid[0]) {
            addMaterialAssoc(m, key: "material/\(model[valid[0]]!.ifcGUID.value)", object: object)
            return
        }
        let key = "list/" + valid.map { model[$0]!.ifcGUID.value }.joined(separator: "+")
        let def = materialDef(key) {
            let mats = valid.compactMap(material)
            if is4 {
                let constituents = mats.map { writer.add("IfcMaterialConstituent", [.null, .null, .r($0), .null, .null]) }
                return writer.add("IfcMaterialConstituentSet", [.null, .null, .refs(constituents)])
            }
            return writer.add("IfcMaterialList", [.refs(mats)])
        }
        addMaterialAssoc(def, key: key, object: object)
    }

    static func layerCategory(_ f: LayerFunction) -> String {
        switch f {
        case .structure: "LoadBearing"
        case .substrate: "Substrate"
        case .thermal: "Insulation"
        case .membrane: "Membrane"
        case .finish1, .finish2: "Finish"
        }
    }

    /// IfcMaterialLayerSet of a type's compound assembly (cached per type).
    func layerSet(for type: Element) -> Int? {
        if let ls = layerSets[type.id] { return ls }
        guard let a = type.typeData?.assembly, !a.layers.isEmpty else { return nil }
        var layers: [Int] = []
        for l in a.layers {
            if !is4 && l.thickness <= 0 { continue }
            let mat = l.materialID.flatMap(material)
            if is4 {
                let mname = l.materialID.flatMap { model[$0]?.name } ?? ""
                layers.append(writer.add("IfcMaterialLayer", [.rOpt(mat), .d(l.thickness), .null, .sOpt(mname), .s(l.function.rawValue),
                                                              .s(Self.layerCategory(l.function)), .null]))
            } else {
                layers.append(writer.add("IfcMaterialLayer", [.rOpt(mat), .d(l.thickness), .null]))
            }
        }
        guard !layers.isEmpty else { return nil }
        let ls = writer.add("IfcMaterialLayerSet", [.refs(layers), .s(type.name)] + (is4 ? [.null] : []))
        layerSets[type.id] = ls
        return ls
    }

    // MARK: - Types

    func attachType(_ e: Element, kind: ExportKind, instance: Int) {
        guard let t = model.type(of: e), let td = t.typeData else { return }
        if types[t.id] != nil {
            typeInstances[t.id, default: []].append(instance)
            return
        }
        let elementType: STEPValue = .sOpt(td.familyName)
        let cls: String
        let rest: [STEPValue]
        switch kind {
        case .wall: cls = "IfcWallType"; rest = [elementType, .e("NOTDEFINED")]
        case .slab: cls = "IfcSlabType"; rest = [elementType, .e("NOTDEFINED")]
        case .covering: cls = "IfcCoveringType"; rest = [elementType, .e("CEILING")]
        case .roof:
            guard is4 else { return }
            cls = "IfcRoofType"; rest = [elementType, .e("NOTDEFINED")]
        case .door:
            if is4 { cls = "IfcDoorType"; rest = [elementType, .e("DOOR"), .e("NOTDEFINED"), .null, .null] }
            else { cls = "IfcDoorStyle"; rest = [.e("NOTDEFINED"), .e("NOTDEFINED"), .b(false), .b(false)] }
        case .window:
            if is4 { cls = "IfcWindowType"; rest = [elementType, .e("WINDOW"), .e("NOTDEFINED"), .null, .null] }
            else { cls = "IfcWindowStyle"; rest = [.e("NOTDEFINED"), .e("NOTDEFINED"), .b(false), .b(false)] }
        case .column: cls = "IfcColumnType"; rest = [elementType, .e("COLUMN")]
        case .beam: cls = "IfcBeamType"; rest = [elementType, .e("BEAM")]
        case .stair:
            guard is4 else { return }
            cls = "IfcStairType"; rest = [elementType, .e("NOTDEFINED")]
        case .ramp:
            guard is4 else { return }
            cls = "IfcRampType"; rest = [elementType, .e("NOTDEFINED")]
        case .railing: cls = "IfcRailingType"; rest = [elementType, .e("NOTDEFINED")]
        case .furniture:
            cls = "IfcFurnitureType"
            rest = is4 ? [elementType, .null, .e("NOTDEFINED")] : [elementType, .e("NOTDEFINED")]
        case .sanitary: cls = "IfcSanitaryTerminalType"; rest = [elementType, .e("NOTDEFINED")]
        case .light: cls = "IfcLightFixtureType"; rest = [elementType, .e("NOTDEFINED")] // W2-LIB
        case .vegetation: // W2-LIB
            cls = is4 ? "IfcGeographicElementType" : "IfcBuildingElementProxyType"; rest = [elementType, .e("NOTDEFINED")]
        case .proxy: cls = "IfcBuildingElementProxyType"; rest = [elementType, .e("NOTDEFINED")]
        default: return
        }
        var psets: STEPValue = .null
        if options.includePropertySets {
            let props = formattedParameters(Parameters.typeEntries(t, model))
            if !props.isEmpty {
                let p = writePropertySet(owner: t.ifcGUID.value, name: "Arcus_TypeParameters", props: props)
                psets = .refs([p])
            }
        }
        let ent = writer.add(cls, [.s(t.ifcGUID.value), .r(ownerHistory), .s(t.name), .null, .null, psets, .null, .null] + rest)
        types[t.id] = ent
        typeOrder.append(t.id)
        typeInstances[t.id, default: []].append(instance)
        if let ls = layerSet(for: t) { addMaterialAssoc(ls, key: "layerset/\(t.ifcGUID.value)", object: ent) }
        classify(t, entity: ent)
    }

    // MARK: - Properties and quantities

    func formattedParameters(_ entries: [ParameterEntry]) -> [(String, STEPValue)] {
        var out: [(String, STEPValue)] = []
        var used: Set<String> = []
        for entry in entries {
            guard entry.value != nil else { continue }
            let s = Parameters.format(entry.value, type: entry.type, model: model)
            guard !s.isEmpty else { continue }
            var name = entry.name
            var n = 2
            while used.contains(name) { name = "\(entry.name) (\(n))"; n += 1 }
            used.insert(name)
            out.append((name, s.count > 255 || s.contains(where: \.isNewline) ? .text(s) : .label(s)))
        }
        return out
    }

    @discardableResult
    func writePropertySet(owner: String, name: String, props: [(String, STEPValue)]) -> Int {
        let values = props.map { writer.add("IfcPropertySingleValue", [.s($0.0), .null, $0.1, .null]) }
        return writer.add("IfcPropertySet", [guid("\(owner)/pset/\(name)"), .r(ownerHistory), .s(name), .null, .refs(values)])
    }

    func writePset(owner: String, name: String, objects: [Int], props: [(String, STEPValue)]) {
        guard !props.isEmpty else { return }
        let pset = writePropertySet(owner: owner, name: name, props: props)
        writer.add("IfcRelDefinesByProperties", [guid("\(owner)/pset/\(name)/rel"), .r(ownerHistory), .null, .null, .refs(objects), .r(pset)])
    }

    func isExteriorWall(_ w: Element?) -> Bool? {
        guard let w, let f = model.typeParam(w, ParameterID("type.function"))?.textValue else { return nil }
        return f == "Exterior"
    }

    func writeElementProperties(_ e: Element, entity: Int, kind: ExportKind) {
        guard options.includePropertySets else { return }
        let g = e.ifcGUID.value
        var common: [(String, STEPValue)] = []
        let typeName = model.type(of: e)?.name
        if let typeName { common.append(("Reference", .identifier(typeName))) }
        let fire = model.typeParam(e, ParameterID("type.fireRating"))?.textValue ?? ""
        var psetName: String?
        switch kind {
        case .wall:
            psetName = "Pset_WallCommon"
            if let ext = isExteriorWall(e) { common.append(("IsExternal", .boolean(ext))) }
            common.append(("LoadBearing", .boolean(e.wall?.structural ?? false)))
            if !fire.isEmpty { common.append(("FireRating", .label(fire))) }
        case .slab:
            psetName = "Pset_SlabCommon"
            common.append(("LoadBearing", .boolean(e.slab?.structural ?? false)))
        case .covering: psetName = "Pset_CoveringCommon"
        case .roof: psetName = "Pset_RoofCommon"; common.append(("IsExternal", .boolean(true)))
        case .door, .window:
            psetName = kind == .door ? "Pset_DoorCommon" : "Pset_WindowCommon"
            if let ext = isExteriorWall(model[e.hostID]) { common.append(("IsExternal", .boolean(ext))) }
            if !fire.isEmpty { common.append(("FireRating", .label(fire))) }
        case .space:
            psetName = "Pset_SpaceCommon"
            common = [("Reference", .identifier(e.room?.number ?? "")), ("IsExternal", .boolean(false))]
        case .column:
            psetName = "Pset_ColumnCommon"
            common.append(("LoadBearing", .boolean(e.category == .structuralColumns)))
        case .beam: psetName = "Pset_BeamCommon"; common.append(("LoadBearing", .boolean(true)))
        case .stair: psetName = "Pset_StairCommon"
        case .ramp: psetName = "Pset_RampCommon"
        case .railing:
            psetName = "Pset_RailingCommon"
            if let h = model.typeParam(e, ParameterID("railing.height"))?.doubleValue, h > 0 { common.append(("Height", .positiveLength(h))) }
        case .proxy: psetName = "Pset_BuildingElementProxyCommon"
        case .vegetation where !is4: psetName = "Pset_BuildingElementProxyCommon" // W2-LIB
        default: break
        }
        if let psetName { writePset(owner: g, name: psetName, objects: [entity], props: common) }
        writePset(owner: g, name: "Arcus_Parameters", objects: [entity], props: formattedParameters(Parameters.instanceEntries(e, model)))

        // Reference elements: re-export their retained IFC property sets ("Pset.Prop" = value).
        if case .reference = kind, let props = e.referenceGeometry?.properties {
            var sets: [String: [(String, STEPValue)]] = [:]
            for key in props.keys.sorted() {
                guard let dot = key.firstIndex(of: "."), dot != key.startIndex else { continue }
                let set = String(key[..<dot]), prop = String(key[key.index(after: dot)...])
                guard !prop.isEmpty, !["Arcus_Parameters", "Arcus_TypeParameters"].contains(set) else { continue }
                if set == psetName { continue }
                sets[set, default: []].append((prop, .label(props[key] ?? "")))
            }
            for set in sets.keys.sorted() { writePset(owner: g, name: set, objects: [entity], props: sets[set]!) }
        }
    }

    func writeQuantities(_ e: Element, entity: Int, kind: ExportKind) {
        guard options.includeBaseQuantities else { return }
        let q = QuantityEngine.quantities(for: e, in: model)
        var list: [(String, String, Double?)] = []
        let name: String
        switch kind {
        case .wall:
            name = "Qto_WallBaseQuantities"
            list = [("Length", "L", q.length), ("Width", "L", q.width), ("Height", "L", q.height), ("NetSideArea", "A", q.area), ("NetVolume", "V", q.volume)]
        case .slab:
            name = "Qto_SlabBaseQuantities"
            list = [("Width", "L", q.thickness), ("Perimeter", "L", q.perimeter), ("NetArea", "A", q.area), ("NetVolume", "V", q.volume)]
        case .covering:
            name = "Qto_CoveringBaseQuantities"
            list = [("Width", "L", q.thickness), ("NetArea", "A", q.area)]
        case .roof:
            name = "Qto_RoofBaseQuantities"
            list = [("NetArea", "A", q.area)]
        case .door, .window:
            name = kind == .door ? "Qto_DoorBaseQuantities" : "Qto_WindowBaseQuantities"
            list = [("Width", "L", q.width), ("Height", "L", q.height), ("Area", "A", q.area)]
        case .space:
            name = "Qto_SpaceBaseQuantities"
            list = [("Height", "L", q.height), ("NetPerimeter", "L", q.perimeter), ("NetFloorArea", "A", q.area), ("NetVolume", "V", q.volume)]
        case .column:
            name = "Qto_ColumnBaseQuantities"
            list = [("Length", "L", q.height), ("NetVolume", "V", q.volume)]
        case .beam:
            name = "Qto_BeamBaseQuantities"
            list = [("Length", "L", q.length), ("NetVolume", "V", q.volume)]
        case .stair:
            name = "Qto_StairBaseQuantities"
            list = [("Length", "L", q.length), ("NetVolume", "V", q.volume)]
        case .railing:
            name = "Qto_RailingBaseQuantities"
            list = [("Length", "L", q.length)]
        default:
            return
        }
        var qs: [Int] = []
        for (n, t, v) in list {
            guard let v, v.isFinite, v >= 0 else { continue }
            let cls = t == "L" ? "IfcQuantityLength" : (t == "A" ? "IfcQuantityArea" : "IfcQuantityVolume")
            qs.append(writer.add(cls, [.s(n), .null, .null, .d(v)] + (is4 ? [.null] : [])))
        }
        guard !qs.isEmpty else { return }
        let g = e.ifcGUID.value
        let qto = writer.add("IfcElementQuantity", [guid("\(g)/qto"), .r(ownerHistory), .s(is4 ? name : "BaseQuantities"), .null, .null, .refs(qs)])
        writer.add("IfcRelDefinesByProperties", [guid("\(g)/qto/rel"), .r(ownerHistory), .null, .null, .refs([entity]), .r(qto)])
    }

    // MARK: - Classification

    func classify(_ e: Element, entity: Int) {
        guard options.includeClassification, let c = e.classification, !c.system.isEmpty || !c.code.isEmpty else { return }
        let sys: Int
        if let s = classificationSystems[c.system] {
            sys = s
        } else {
            sys = is4 ? writer.add("IfcClassification", [.null, .null, .null, .s(c.system), .null, .null, .null])
                      : writer.add("IfcClassification", [.s(c.system), .s(""), .null, .s(c.system)])
            classificationSystems[c.system] = sys
        }
        let key = "\(c.system)|\(c.code)|\(c.title)"
        let ref: Int
        if let r = classificationRefs[key] {
            ref = r
        } else {
            ref = is4 ? writer.add("IfcClassificationReference", [.null, .sOpt(c.code), .sOpt(c.title), .r(sys), .null, .null])
                      : writer.add("IfcClassificationReference", [.null, .sOpt(c.code), .sOpt(c.title), .r(sys)])
            classificationRefs[key] = ref
            classificationRefKeys[ref] = key
        }
        classificationAssoc[ref, default: []].append(entity)
    }

    // MARK: - Relationships

    func writeRelationships() {
        let p = plan.projectGUID.value
        let oh = STEPValue.r(ownerHistory)
        writer.add("IfcRelAggregates", [guid("\(p)/aggregates/site"), oh, .null, .null, .r(projectEntity), .refs([siteEntity])])
        writer.add("IfcRelAggregates", [guid("\(p)/aggregates/building"), oh, .null, .null, .r(siteEntity), .refs([buildingEntity])])
        let storeyEnts = storeyIndices.compactMap { storeyEntity[$0] }
        if !storeyEnts.isEmpty {
            writer.add("IfcRelAggregates", [guid("\(p)/aggregates/storeys"), oh, .null, .null, .r(buildingEntity), .refs(storeyEnts)])
        }
        for k in storeyIndices {
            guard let s = storeyEntity[k] else { continue }
            let sg = plan.storeys[k].guid.value
            if let els = contained[k], !els.isEmpty {
                writer.add("IfcRelContainedInSpatialStructure", [guid("\(sg)/contains"), oh, .null, .null, .refs(els), .r(s)])
            }
            if let sp = spaces[k], !sp.isEmpty {
                writer.add("IfcRelAggregates", [guid("\(sg)/aggregates/spaces"), oh, .null, .null, .r(s), .refs(sp)])
            }
        }
        if !siteContained.isEmpty {
            writer.add("IfcRelContainedInSpatialStructure", [guid("\(siteGUID.value)/contains"), oh, .null, .null, .refs(siteContained), .r(siteEntity)])
        }
        for t in typeOrder {
            guard let ent = types[t], let inst = typeInstances[t], let te = model[t] else { continue }
            writer.add("IfcRelDefinesByType", [guid("\(te.ifcGUID.value)/definesByType"), oh, .null, .null, .refs(inst), .r(ent)])
        }
        if is4 && !typeOrder.isEmpty {
            writer.add("IfcRelDeclares", [guid("\(p)/declares"), oh, .null, .null, .r(projectEntity), .refs(typeOrder.compactMap { types[$0] })])
        }
        for def in materialAssoc.keys.sorted() {
            let key = materialAssocKey[def] ?? "\(def)"
            writer.add("IfcRelAssociatesMaterial", [guid("\(p)/associatesMaterial/\(key)"), oh, .null, .null, .refs(materialAssoc[def]!), .r(def)])
        }
        for ref in classificationAssoc.keys.sorted() {
            let key = classificationRefKeys[ref] ?? "\(ref)"
            writer.add("IfcRelAssociatesClassification", [guid("\(p)/classification/\(key)"), oh, .null, .null, .refs(classificationAssoc[ref]!), .r(ref)])
        }
    }
}

extension IFCFileBuilder {
    /// IfcRampTypeEnum for a ramp run path: counts the runs and classifies the turns at the landings between them.
    static func rampShapeType(_ path: [Vec2]) -> String {
        var pts: [Vec2] = []
        for p in path where pts.last.map({ !$0.isAlmostEqual(p, tolerance: 0.001) }) ?? true { pts.append(p) }
        guard pts.count >= 2 else { return "NOTDEFINED" }
        var turns: [Double] = []
        for i in 1..<max(1, pts.count - 1) {
            let a = (pts[i] - pts[i - 1]).normalized, b = (pts[i + 1] - pts[i]).normalized
            turns.append(atan2(a.cross(b), a.dot(b)))
        }
        func near(_ x: Double, _ y: Double) -> Bool { abs(abs(x) - y) < 0.2 }
        switch turns.count {
        case 0: return "STRAIGHT_RUN_RAMP"
        case 1:
            if near(turns[0], 0) { return "TWO_STRAIGHT_RUN_RAMP" }
            if near(turns[0], .pi / 2) { return "QUARTER_TURN_RAMP" }
            if near(turns[0], .pi) { return "HALF_TURN_RAMP" }
        case 2 where near(turns[0], .pi / 2) && near(turns[1], .pi / 2):
            return turns[0] * turns[1] > 0 ? "HALF_TURN_RAMP" : "TWO_QUARTER_TURN_RAMP"
        default: break
        }
        return "NOTDEFINED"
    }
}

