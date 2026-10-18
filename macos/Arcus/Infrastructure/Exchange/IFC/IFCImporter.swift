import Foundation
import ArcusGeometry
import ArcusDomain

/// Reads IFC2X3 / IFC4 files into a transaction.
///
/// Import runs in two phases. The analysis phase parses the file, evaluates placements and geometry and
/// decides what each product becomes; it may throw (malformed input, cancellation) and never touches the
/// transaction. The apply phase then creates levels, materials, types and elements and cannot fail, so a
/// thrown error never leaves a partially imported model in the transaction.
public enum IFCImporter {
    /// Parses and imports into the transaction (creates levels, types, native elements, reference geometry).
    /// Throws IFCError on malformed input. Never partially commits (caller commits tx).
    public static func importFile(_ data: Data, fileName: String, into tx: TransactionContext, options: IFCImportOptions = IFCImportOptions(),
                                  progress: @Sendable (Double) -> Void = { _ in }, isCancelled: @Sendable () -> Bool = { false }) throws -> IFCImportReport {
        let started = Date()
        let file = try STEPParser.parse(data, limits: options.limits, progress: { progress($0 * 0.3) }, isCancelled: isCancelled)
        if isCancelled() { throw IFCError.cancelled }
        let session = try IFCImportSession(file: file, fileName: fileName, options: options)
        try session.analyze(progress: { progress(0.3 + $0 * 0.6) }, isCancelled: isCancelled)
        if isCancelled() { throw IFCError.cancelled }
        session.apply(to: tx)
        var report = session.report
        report.elapsed = Date().timeIntervalSince(started)
        progress(1)
        return report
    }
}

// MARK: - Analysis results

struct LayerSpec {
    var materialName: String?
    var materialCategory: String?
    var thickness: Double
    var function: LayerFunction?
}

struct ProductInfo {
    let entity: STEPEntity
    let cls: String
    let guid: String
    let name: String
    let objectType: String
    let tag: String
    let description: String
    var storey: Int?
    var properties: [String: String]
    var typeEntity: STEPEntity?
    var classification: Classification?
    var color: RGBColor?
    var minZ: Double?
}

struct WallSpec { var product: ProductInfo; var location: Segment2; var thickness: Double; var baseZ: Double; var height: Double; var flipped: Bool; var layers: [LayerSpec]; var typeName: String? }
struct FloorSpec { var product: ProductInfo; var sketch: Sketch; var topZ: Double; var thickness: Double; var layers: [LayerSpec]; var typeName: String? }
struct SpaceSpec { var product: ProductInfo; var point: Vec2; var baseZ: Double; var height: Double; var roomName: String; var number: String }
struct ColumnSpec { var product: ProductInfo; var center: Vec2; var rotation: Double; var width: Double; var depth: Double; var diameter: Double; var baseZ: Double; var height: Double }
struct BeamSpec { var product: ProductInfo; var line: Segment2; var topZ: Double; var width: Double; var depth: Double }
struct InsertSpec {
    var product: ProductInfo; var isDoor: Bool; var hostEntity: Int; var station: Double; var sill: Double; var width: Double; var height: Double
    var familyName: String; var handFlipped: Bool; var facingFlipped: Bool
}
struct ReferenceSpec { var product: ProductInfo; var mesh: TriMesh? }

// MARK: - Session

final class IFCImportSession {
    let file: STEPFile
    let fileName: String
    let options: IFCImportOptions
    let schema: String
    var report: IFCImportReport
    private(set) var geo: IFCGeometryEvaluator
    let lengthScale: Double

    // Relationship indices.
    var containedIn: [Int: Int] = [:]
    var parentOf: [Int: Int] = [:]
    var openingHost: [Int: Int] = [:]
    var openingsOf: [Int: [Int]] = [:]
    var fillerOpening: [Int: Int] = [:]
    var typeOf: [Int: Int] = [:]
    var psetsOf: [Int: [Int]] = [:]
    var materialOf: [Int: Int] = [:]
    var classOf: [Int: Int] = [:]
    var styleColor: [Int: RGBColor] = [:]

    struct StoreySpec { var entity: Int; var name: String; var elevation: Double; var guid: String }
    var storeys: [StoreySpec] = []

    var walls: [Int: WallSpec] = [:]
    var wallOrder: [Int] = []
    var floors: [FloorSpec] = []
    var spaces: [SpaceSpec] = []
    var columns: [ColumnSpec] = []
    var beams: [BeamSpec] = []
    var inserts: [InsertSpec] = []
    var references: [ReferenceSpec] = []

    init(file: STEPFile, fileName: String, options: IFCImportOptions) throws {
        self.file = file
        self.fileName = fileName
        self.options = options
        guard let raw = file.header.schemas.first?.uppercased(), !raw.isEmpty else {
            throw IFCError("The file does not declare a schema (FILE_SCHEMA is empty).")
        }
        if raw.hasPrefix("IFC2X3") { schema = "IFC2X3" }
        else if raw.hasPrefix("IFC4") { schema = raw == "IFC4" ? "IFC4" : raw }
        else { throw IFCError("Unsupported schema \(raw). Arcus reads IFC2X3 and IFC4 files.") }
        report = IFCImportReport(schema: schema, fileName: fileName, entityCount: file.count)
        if raw.hasPrefix("IFC4X") || (raw.hasPrefix("IFC4") && raw != "IFC4") {
            report.warnings.append("\(raw) is read with the IFC4 subset; entities introduced after IFC4 are counted as unsupported.")
        }
        guard let project = file.all("IFCPROJECT").first else { throw IFCError("The file contains no IfcProject.") }
        var length = 1.0, angle = 1.0
        let ua = file[project[8]] ?? file.all("IFCUNITASSIGNMENT").first
        var foundLength = false
        if let ua {
            (length, angle, foundLength) = IFCImportSession.units(ua, file: file)
        }
        if !foundLength { report.warnings.append("No length unit is declared; meters were assumed.") }
        lengthScale = length
        geo = IFCGeometryEvaluator(file: file, lengthScale: length, angleScale: angle)
    }

    static func units(_ ua: STEPEntity, file: STEPFile) -> (length: Double, angle: Double, foundLength: Bool) {
        var length = 1.0, angle = 1.0, found = false
        func siScale(_ e: STEPEntity) -> Double {
            let prefix: [String: Double] = ["EXA": 1e18, "PETA": 1e15, "TERA": 1e12, "GIGA": 1e9, "MEGA": 1e6, "KILO": 1e3, "HECTO": 1e2, "DECA": 1e1,
                                            "DECI": 1e-1, "CENTI": 1e-2, "MILLI": 1e-3, "MICRO": 1e-6, "NANO": 1e-9, "PICO": 1e-12, "FEMTO": 1e-15, "ATTO": 1e-18]
            return e[2].enumValue.flatMap { prefix[$0] } ?? 1
        }
        func scale(_ e: STEPEntity, depth: Int = 0) -> Double? {
            switch e.type {
            case "IFCSIUNIT": return siScale(e)
            case "IFCCONVERSIONBASEDUNIT", "IFCCONVERSIONBASEDUNITWITHOFFSET":
                guard depth < 8, let m = file[e[3]], let v = m[0].doubleValue, v.isFinite, v > 0 else { return nil }
                let inner = file[m[1]].flatMap { scale($0, depth: depth + 1) } ?? 1
                return v * inner
            default: return nil
            }
        }
        for u in ua[0].listValue ?? [] {
            guard let e = file[u], let kind = e[1].enumValue, let s = scale(e), s.isFinite, s > 0 else { continue }
            if kind == "LENGTHUNIT" { length = s; found = true }
            if kind == "PLANEANGLEUNIT" { angle = s }
        }
        return (length, angle, found)
    }

    func warn(_ s: String) { if !report.warnings.contains(s) { report.warnings.append(s) } }

    // MARK: Indices

    func buildIndices() {
        for e in file.all("IFCRELCONTAINEDINSPATIALSTRUCTURE") {
            guard let s = e[5].refValue else { continue }
            for x in e[4].listValue ?? [] { if let r = x.refValue { containedIn[r] = s } }
        }
        for e in file.all("IFCRELAGGREGATES") + file.all("IFCRELNESTS") {
            guard let p = e[4].refValue else { continue }
            for x in e[5].listValue ?? [] { if let r = x.refValue, parentOf[r] == nil { parentOf[r] = p } }
        }
        for e in file.all("IFCRELVOIDSELEMENT") {
            if let h = e[4].refValue, let o = e[5].refValue { openingHost[o] = h; openingsOf[h, default: []].append(o) }
        }
        for e in file.all("IFCRELFILLSELEMENT") { if let o = e[4].refValue, let f = e[5].refValue { fillerOpening[f] = o } }
        for e in file.all("IFCRELDEFINESBYTYPE") {
            guard let t = e[5].refValue else { continue }
            for x in e[4].listValue ?? [] { if let r = x.refValue { typeOf[r] = t } }
        }
        for e in file.all("IFCRELDEFINESBYPROPERTIES") {
            var defs: [Int] = []
            if let d = e[5].refValue { defs = [d] } else if let l = e[5].listValue { defs = l.compactMap(\.refValue) }
            for x in e[4].listValue ?? [] { if let r = x.refValue { psetsOf[r, default: []].append(contentsOf: defs) } }
        }
        for e in file.all("IFCRELASSOCIATESMATERIAL") {
            guard let m = e[5].refValue else { continue }
            for x in e[4].listValue ?? [] { if let r = x.refValue { materialOf[r] = m } }
        }
        for e in file.all("IFCRELASSOCIATESCLASSIFICATION") {
            guard let c = e[5].refValue else { continue }
            for x in e[4].listValue ?? [] { if let r = x.refValue { classOf[r] = c } }
        }
        for e in file.all("IFCSTYLEDITEM") {
            guard let item = e[0].refValue, let c = color(ofStyles: e[1]) else { continue }
            styleColor[item] = c
        }
    }

    func color(ofStyles v: STEPValue) -> RGBColor? {
        for s in v.listValue ?? [] {
            guard let st = file[s] else { continue }
            if st.type == "IFCPRESENTATIONSTYLEASSIGNMENT", let c = color(ofStyles: st[0]) { return c }
            if st.type == "IFCSURFACESTYLE" {
                for r in st[2].listValue ?? [] {
                    guard let sh = file[r], sh.type.hasPrefix("IFCSURFACESTYLE"), let rgb = file[sh[0]], rgb.type == "IFCCOLOURRGB",
                          let red = rgb[1].doubleValue, let g = rgb[2].doubleValue, let b = rgb[3].doubleValue else { continue }
                    let tr = sh[1].doubleValue ?? 0
                    return RGBColor(max(0, min(1, red)), max(0, min(1, g)), max(0, min(1, b)), 1 - max(0, min(1, tr)))
                }
            }
        }
        return nil
    }

    // MARK: Products

    static let spatial: Set<String> = ["IFCPROJECT", "IFCBUILDING", "IFCBUILDINGSTOREY", "IFCSITE", "IFCSPACE", "IFCOPENINGELEMENT", "IFCOPENINGSTANDARDCASE"]

    /// Structural test for IfcProduct instances (GlobalId, OwnerHistory, Name, Description, ObjectType, ObjectPlacement, Representation…).
    func isProduct(_ e: STEPEntity) -> Bool {
        guard e.args.count >= 7, e.type.hasPrefix("IFC"), !e.type.hasSuffix("TYPE"), !e.type.hasSuffix("STYLE"), !e.type.hasPrefix("IFCREL") else { return false }
        guard let g = e[0].stringValue, g.count == 22 else { return false }
        switch e[5] {
        case .null: break
        case .ref(let r): guard let p = file[r], p.type.hasSuffix("PLACEMENT") else { return false }
        default: return false
        }
        switch e[6] {
        case .null: break
        case .ref(let r): guard file[r]?.type == "IFCPRODUCTDEFINITIONSHAPE" else { return false }
        default: return false
        }
        return true
    }

    func storey(of id: Int) -> Int? {
        var cur = id
        for _ in 0..<32 {
            guard let next = containedIn[cur] ?? parentOf[cur], let e = file[next] else { return nil }
            if e.type == "IFCBUILDINGSTOREY" { return next }
            if e.type == "IFCBUILDING" || e.type == "IFCSITE" || e.type == "IFCPROJECT" { return nil }
            cur = next
        }
        return nil
    }

    func measureString(_ v: STEPValue) -> String {
        if case .typed(let t, let args) = v, args.count == 1, let d = args[0].doubleValue {
            switch t {
            case "IFCLENGTHMEASURE", "IFCPOSITIVELENGTHMEASURE", "IFCNONNEGATIVELENGTHMEASURE": return STEPFormat.shortReal(d * lengthScale)
            case "IFCAREAMEASURE": return STEPFormat.shortReal(d * lengthScale * lengthScale)
            case "IFCVOLUMEMEASURE": return STEPFormat.shortReal(d * lengthScale * lengthScale * lengthScale)
            default: break
            }
        }
        return v.displayString
    }

    func flattenPropertySet(_ id: Int, into out: inout [String: String]) {
        guard let d = file[id] else { return }
        let setName = d[2].stringValue ?? d.type
        switch d.type {
        case "IFCPROPERTYSET":
            for p in d[4].listValue ?? [] {
                guard let prop = file[p], let n = prop[0].stringValue else { continue }
                let key = "\(setName).\(n)"
                switch prop.type {
                case "IFCPROPERTYSINGLEVALUE": out[key] = measureString(prop[2])
                case "IFCPROPERTYENUMERATEDVALUE", "IFCPROPERTYLISTVALUE": out[key] = (prop[2].listValue ?? []).map(measureString).joined(separator: ", ")
                case "IFCPROPERTYBOUNDEDVALUE": out[key] = "\(measureString(prop[3]))..\(measureString(prop[2]))"
                default: break
                }
            }
        case "IFCELEMENTQUANTITY":
            for q in d[5].listValue ?? [] {
                guard let qe = file[q], let n = qe[0].stringValue, let v = qe[3].doubleValue else { continue }
                var s = v
                switch qe.type {
                case "IFCQUANTITYLENGTH": s = v * lengthScale
                case "IFCQUANTITYAREA": s = v * lengthScale * lengthScale
                case "IFCQUANTITYVOLUME": s = v * lengthScale * lengthScale * lengthScale
                default: break
                }
                out["\(setName).\(n)"] = STEPFormat.shortReal(s)
            }
        default:
            break
        }
    }

    func productInfo(_ e: STEPEntity) -> ProductInfo {
        var props: [String: String] = [:]
        let type = typeOf[e.id].flatMap { file[$0] }
        if let t = type { for p in t[5].listValue ?? [] { if let r = p.refValue { flattenPropertySet(r, into: &props) } } }
        for p in psetsOf[e.id] ?? [] { flattenPropertySet(p, into: &props) }
        let cls = IFCClassTable.name(for: e.type)
        let name = e[2].stringValue ?? "", objectType = e[4].stringValue ?? "", desc = e[3].stringValue ?? ""
        let tag = e.args.count > 7 ? (e[7].stringValue ?? "") : ""
        props["GlobalId"] = e[0].stringValue ?? ""
        props["IfcClass"] = cls
        if !name.isEmpty { props["Name"] = name }
        if !objectType.isEmpty { props["ObjectType"] = objectType }
        if !desc.isEmpty { props["Description"] = desc }
        if !tag.isEmpty && e.type != "IFCSPACE" { props["Tag"] = tag }
        if let t = type, let tn = t[2].stringValue { props["TypeName"] = tn }
        var classification: Classification?
        if let c = classOf[e.id].flatMap({ file[$0] }), c.type == "IFCCLASSIFICATIONREFERENCE" {
            let system = file[c[3]].flatMap { $0[3].stringValue } ?? ""
            classification = Classification(system: system, code: c[1].stringValue ?? "", title: c[2].stringValue ?? "")
        }
        var color: RGBColor?
        for rep in geo.representations(of: e) where rep.id == "Body" || rep.id.isEmpty {
            for item in rep.items {
                if let r = item.refValue, let c = styleColor[r] { color = c; break }
                if let mi = file[item], mi.type == "IFCMAPPEDITEM", let map = file[mi[0]], let mrep = file[map[1]] {
                    for x in mrep[3].listValue ?? [] { if let r = x.refValue, let c = styleColor[r] { color = c; break } }
                }
                if color != nil { break }
            }
            if color != nil { break }
        }
        return ProductInfo(entity: e, cls: cls, guid: e[0].stringValue ?? "", name: name, objectType: objectType, tag: tag, description: desc,
                           storey: storey(of: e.id), properties: props, typeEntity: type, classification: classification, color: color, minZ: nil)
    }

    // MARK: Analysis

    func analyze(progress: (Double) -> Void, isCancelled: () -> Bool) throws {
        buildIndices()
        for s in file.all("IFCBUILDINGSTOREY") {
            let z = s[5].isNull ? (s[9].doubleValue ?? 0) * lengthScale : geo.placement(s[5]).origin.z
            storeys.append(StoreySpec(entity: s.id, name: s[2].stringValue ?? "", elevation: z, guid: s[0].stringValue ?? ""))
        }
        storeys.sort { ($0.elevation, $0.entity) < ($1.elevation, $1.entity) }

        let productIDs = file.order.filter { id in
            guard let e = file[id] else { return false }
            if IFCImportSession.spatial.contains(e.type) { return e.type == "IFCSPACE" || (e.type == "IFCSITE" && !e[6].isNull) }
            return isProduct(e)
        }
        var booleans = 0
        var pendingInserts: [ProductInfo] = []
        for (n, id) in productIDs.enumerated() {
            if n & 63 == 0 {
                if isCancelled() { throw IFCError.cancelled }
                progress(Double(n) / Double(max(1, productIDs.count)))
            }
            guard let e = file[id] else { continue }
            var info = productInfo(e)
            let mesh = geo.bodyMesh(of: e)
            if geo.approximatedBoolean { booleans += 1 }
            info.minZ = mesh.map { $0.bounds.min.z }
            if options.mapToNative {
                switch e.type {
                case "IFCWALL", "IFCWALLSTANDARDCASE", "IFCWALLELEMENTEDCASE":
                    if let m = mesh, let w = analyzeWall(info, mesh: m) { walls[id] = w; wallOrder.append(id); continue }
                case "IFCSLAB", "IFCSLABSTANDARDCASE", "IFCSLABELEMENTEDCASE":
                    if isFloorSlab(e, type: info.typeEntity), let m = mesh, let f = analyzeFloor(info, mesh: m) { floors.append(f); continue }
                case "IFCSPACE":
                    if let s = analyzeSpace(info, mesh: mesh) { spaces.append(s); continue }
                case "IFCCOLUMN", "IFCCOLUMNSTANDARDCASE":
                    if let m = mesh, let c = analyzeColumn(info, mesh: m) { columns.append(c); continue }
                case "IFCBEAM", "IFCBEAMSTANDARDCASE":
                    if let m = mesh, let b = analyzeBeam(info, mesh: m) { beams.append(b); continue }
                case "IFCDOOR", "IFCDOORSTANDARDCASE", "IFCWINDOW", "IFCWINDOWSTANDARDCASE":
                    pendingInserts.append(info)
                    references.append(ReferenceSpec(product: info, mesh: mesh)) // replaced below if mapped
                    continue
                default:
                    break
                }
            }
            references.append(ReferenceSpec(product: info, mesh: mesh))
        }
        // Doors and windows need their host walls analysed first.
        var mapped: Set<Int> = []
        for info in pendingInserts {
            if let s = analyzeInsert(info) { inserts.append(s); mapped.insert(info.entity.id) }
        }
        references.removeAll { mapped.contains($0.product.entity.id) }
        // Openings: those filled by a native door/window are recreated by it; others cannot be represented natively.
        let filledOpenings = Set(inserts.compactMap { fillerOpening[$0.product.entity.id] })
        var lostOpenings = 0, referenceHostsWithOpenings = 0
        let referenceIDs = Set(references.map(\.product.entity.id))
        for (host, openings) in openingsOf {
            if walls[host] != nil {
                lostOpenings += openings.filter { !filledOpenings.contains($0) }.count
            } else if referenceIDs.contains(host) {
                referenceHostsWithOpenings += 1
            }
        }
        if lostOpenings > 0 {
            report.unsupported["IfcOpeningElement", default: 0] += lostOpenings
            warn("\(lostOpenings) opening\(lostOpenings == 1 ? "" : "s") without a native door or window could not be recreated in imported walls.")
        }
        if referenceHostsWithOpenings > 0 {
            warn("\(referenceHostsWithOpenings) reference element\(referenceHostsWithOpenings == 1 ? " has" : "s have") openings; openings are only visible where the source geometry already contains them.")
        }
        if booleans > 0 {
            warn("\(booleans) element\(booleans == 1 ? "" : "s") used boolean operations; the first operand was used (openings/clippings were not applied).")
        }
        for w in geo.warnings { warn(w) }
        for (k, v) in geo.unsupported { report.unsupported[k, default: 0] += v }
        let noGeometry = references.filter { $0.mesh == nil }.count
        if noGeometry > 0 {
            warn("\(noGeometry) element\(noGeometry == 1 ? " has" : "s have") no supported 3D body and \(noGeometry == 1 ? "was" : "were") kept as reference elements without geometry.")
        }
        // Everything in the file that is neither a product nor used by one is still accounted for.
        let productTypes = Set(productIDs.compactMap { file[$0]?.type })
        let known: Set<String> = ["IFCPROJECT", "IFCBUILDING", "IFCBUILDINGSTOREY", "IFCSITE", "IFCOPENINGELEMENT", "IFCOPENINGSTANDARDCASE"]
        for (type, ids) in file.byType where ids.count > 0 && !productTypes.contains(type) && !known.contains(type) {
            // Resource entities (geometry, properties, relationships) are consumed through products; only unrecognised
            // rooted objects (GlobalId + OwnerHistory) that are not relationships/definitions are reported.
            guard let first = file[ids[0]], first[0].stringValue?.count == 22, first.args.count >= 7, !type.hasPrefix("IFCREL"),
                  !type.hasSuffix("TYPE"), !type.hasSuffix("STYLE"), !isProduct(first) else { continue }
            if ["IFCPROPERTYSET", "IFCELEMENTQUANTITY", "IFCGROUP", "IFCSYSTEM", "IFCZONE"].contains(type) { continue }
            report.unsupported[IFCClassTable.name(for: type), default: 0] += ids.count
        }
        progress(1)
    }

    func isFloorSlab(_ e: STEPEntity, type: STEPEntity?) -> Bool {
        let floorish: Set<String> = ["FLOOR", "BASESLAB"]
        let generic: Set<String> = ["NOTDEFINED", "USERDEFINED"]
        if let p = e[8].enumValue, !generic.contains(p) { return floorish.contains(p) }
        if let tp = type?[9].enumValue, !generic.contains(tp) { return floorish.contains(tp) }
        return true
    }

    // MARK: Materials

    func layers(for info: ProductInfo) -> (layers: [LayerSpec], sense: String?, setName: String?) {
        let matID = materialOf[info.entity.id] ?? info.typeEntity.flatMap { materialOf[$0.id] }
        guard let m = matID.flatMap({ file[$0] }) else { return ([], nil, nil) }
        var set = m
        var sense: String?
        if m.type == "IFCMATERIALLAYERSETUSAGE", let s = file[m[0]] { set = s; sense = m[2].enumValue }
        switch set.type {
        case "IFCMATERIALLAYERSET":
            let out: [LayerSpec] = (set[0].listValue ?? []).compactMap { l in
                guard let le = file[l], let t = le[1].doubleValue, t.isFinite, t >= 0 else { return nil }
                let mat = file[le[0]]
                var function: LayerFunction?
                if let d = le[4].stringValue { function = LayerFunction(rawValue: d) }
                if function == nil, let c = le[5].stringValue {
                    switch c.lowercased() {
                    case "loadbearing": function = .structure
                    case "insulation": function = .thermal
                    case "finish": function = .finish1
                    case "substrate": function = .substrate
                    case "membrane": function = .membrane
                    default: break
                    }
                }
                return LayerSpec(materialName: mat?[0].stringValue, materialCategory: mat?[2].stringValue, thickness: t * lengthScale, function: function)
            }
            return (out, sense, set[1].stringValue)
        case "IFCMATERIAL":
            return ([LayerSpec(materialName: set[0].stringValue, materialCategory: set[2].stringValue, thickness: 0, function: nil)], nil, nil)
        case "IFCMATERIALLIST":
            let first = (set[0].listValue ?? []).first.flatMap { file[$0] }
            return first.map { ([LayerSpec(materialName: $0[0].stringValue, materialCategory: $0[2].stringValue, thickness: 0, function: nil)], nil, nil) } ?? ([], nil, nil)
        case "IFCMATERIALCONSTITUENTSET":
            let first = (set[2].listValue ?? []).first.flatMap { file[$0] }.flatMap { file[$0[2]] }
            return first.map { ([LayerSpec(materialName: $0[0].stringValue, materialCategory: $0[2].stringValue, thickness: 0, function: nil)], nil, nil) } ?? ([], nil, nil)
        default:
            return ([], nil, nil)
        }
    }

    /// Layer specs when they describe the full thickness; otherwise a single structure layer with the element's material.
    func resolvedLayers(_ info: ProductInfo, thickness: Double) -> (layers: [LayerSpec], sense: String?, name: String?) {
        let (ls, sense, setName) = layers(for: info)
        let total = ls.reduce(0) { $0 + $1.thickness }
        if !ls.isEmpty, abs(total - thickness) <= 0.002, ls.contains(where: { $0.thickness > 0 }) {
            var out = ls
            if !out.contains(where: { $0.function != nil }) {
                let thickest = out.indices.max { out[$0].thickness < out[$1].thickness }!
                for i in out.indices { out[i].function = i == thickest ? .structure : (out[i].thickness > 0 ? .finish1 : .membrane) }
            }
            for i in out.indices where out[i].function == nil { out[i].function = out[i].thickness > 0 ? .finish1 : .membrane }
            return (out, sense, setName)
        }
        let mat = ls.first
        return ([LayerSpec(materialName: mat?.materialName, materialCategory: mat?.materialCategory, thickness: thickness, function: .structure)], sense, nil)
    }

    // MARK: Shape analysis

    struct Welded { var pts: [Vec3]; var tris: [(Int, Int, Int)] }

    func weld(_ m: TriMesh, grid: Double = 1e-5) -> Welded {
        var map: [SIMD3<Int64>: Int] = [:]
        var pts: [Vec3] = []
        var remap: [Int] = []
        remap.reserveCapacity(m.positions.count)
        for p in m.positions {
            let k = SIMD3<Int64>(Int64((p.x / grid).rounded()), Int64((p.y / grid).rounded()), Int64((p.z / grid).rounded()))
            if let i = map[k] { remap.append(i) } else { map[k] = pts.count; remap.append(pts.count); pts.append(p) }
        }
        var tris: [(Int, Int, Int)] = []
        var i = 0
        while i + 2 < m.indices.count {
            let a = remap[Int(m.indices[i])], b = remap[Int(m.indices[i + 1])], c = remap[Int(m.indices[i + 2])]
            i += 3
            if a != b && b != c && a != c { tris.append((a, b, c)) }
        }
        return Welded(pts: pts, tris: tris)
    }

    /// Outline loops of the top face of a vertical prism (nil when the body is not a prism).
    func prismOutline(_ mesh: TriMesh) -> (loops: [Polygon2], top: Double, bottom: Double)? {
        let w = weld(mesh)
        guard !w.tris.isEmpty else { return nil }
        let zs = w.pts.map(\.z)
        let top = zs.max()!, bottom = zs.min()!
        guard top - bottom > 0.001 else { return nil }
        var topArea = 0.0, botArea = 0.0
        var edges: [UInt64: Int] = [:]
        for (a, b, c) in w.tris {
            let pa = w.pts[a], pb = w.pts[b], pc = w.pts[c]
            let n = (pb - pa).cross(pc - pa)
            let area = n.length / 2
            guard area > 1e-12, abs(n.normalized.z) > 0.999 else { continue }
            if [pa, pb, pc].allSatisfy({ abs($0.z - top) < 0.001 }) {
                topArea += area
                for (u, v) in [(a, b), (b, c), (c, a)] { edges[UInt64(min(u, v)) << 32 | UInt64(max(u, v)), default: 0] += 1 }
            } else if [pa, pb, pc].allSatisfy({ abs($0.z - bottom) < 0.001 }) {
                botArea += area
            }
        }
        guard topArea > 1e-4, abs(topArea - botArea) <= 0.02 * topArea else { return nil }
        var adj: [Int: [Int]] = [:]
        for (k, n) in edges where n == 1 {
            let u = Int(k >> 32), v = Int(k & 0xFFFF_FFFF)
            adj[u, default: []].append(v); adj[v, default: []].append(u)
        }
        guard !adj.isEmpty, adj.values.allSatisfy({ $0.count == 2 }) else { return nil }
        var visited: Set<Int> = []
        var loops: [Polygon2] = []
        for start in adj.keys.sorted() where !visited.contains(start) {
            var loop: [Vec2] = []
            var prev = -1, cur = start
            while !visited.contains(cur) {
                visited.insert(cur)
                loop.append(w.pts[cur].xy)
                let nb = adj[cur]!
                let next = nb[0] != prev ? nb[0] : nb[1]
                prev = cur; cur = next
            }
            let poly = Polygon2(loop).simplified()
            if poly.count >= 3 && poly.area > 1e-6 { loops.append(poly) }
        }
        guard !loops.isEmpty else { return nil }
        loops.sort { $0.area > $1.area }
        return (loops, top, bottom)
    }

    func analyzeWall(_ info: ProductInfo, mesh: TriMesh) -> WallSpec? {
        let w = weld(mesh)
        guard w.pts.count >= 8 else { return nil }
        var a: Vec2, b: Vec2
        if let axis = geo.axisPoints(of: info.entity) {
            a = axis.first!.xy; b = axis.last!.xy
            guard a.distance(to: b) > 0.01 else { return nil }
            let seg = Segment2(a, b)
            guard axis.allSatisfy({ abs(seg.signedDistance(to: $0.xy)) < 0.002 }) else { return nil }
        } else {
            guard let dir = boxDirection(w) else { return nil }
            let o = w.pts[0].xy
            let ss = w.pts.map { ($0.xy - o).dot(dir) }
            a = o + dir * ss.min()!; b = o + dir * ss.max()!
        }
        let dir = (b - a).normalized, n = dir.perpendicular
        let ts = w.pts.map { ($0.xy - a).dot(n) }
        let tmin = ts.min()!, tmax = ts.max()!
        let thickness = tmax - tmin
        guard thickness >= 0.01, thickness <= 5 else { return nil }
        // Box-like: every vertex lies on one of the two faces, except join points at the wall ends (mitred/tee caps).
        // Opening reveals (already cut into tessellated bodies) may also add vertices inside the wall.
        let length = a.distance(to: b)
        var openingRanges: [(Double, Double)] = []
        for o in openingsOf[info.entity.id] ?? [] {
            guard let oe = file[o], let om = geo.bodyMesh(of: oe), !om.positions.isEmpty else { continue }
            let ss = om.positions.map { ($0.xy - a).dot(dir) }
            openingRanges.append((ss.min()! - 0.003, ss.max()! + 0.003))
        }
        for (p, t) in zip(w.pts, ts) where abs(t - tmin) >= 0.003 && abs(t - tmax) >= 0.003 {
            let sv = (p.xy - a).dot(dir)
            if sv < 1.5 * thickness + 0.003 || sv > length - 1.5 * thickness - 0.003 { continue }
            guard openingRanges.contains(where: { sv >= $0.0 && sv <= $0.1 }) else { return nil }
        }
        let zs = w.pts.map(\.z)
        let z0 = zs.min()!, z1 = zs.max()!
        guard z1 - z0 > 0.05 else { return nil }
        let c = (tmin + tmax) / 2
        let (ls, sense, setName) = resolvedLayers(info, thickness: thickness)
        let typeName = info.typeEntity?[2].stringValue ?? setName
        return WallSpec(product: info, location: Segment2(a + n * c, b + n * c), thickness: thickness, baseZ: z0, height: z1 - z0,
                        flipped: sense == "POSITIVE", layers: ls, typeName: typeName)
    }

    /// Horizontal edge directions, longest first (deduplicated to 0.01°).
    func horizontalDirections(_ w: Welded) -> [Vec2] {
        var cands: [(Double, Vec2)] = []
        var seen: Set<Int> = []
        for (a, b, c) in w.tris {
            for (u, v) in [(a, b), (b, c), (c, a)] {
                let d = w.pts[v] - w.pts[u]
                guard abs(d.z) < 1e-3 else { continue }
                let l = d.xy.length
                guard l > 0.01 else { continue }
                var dir = d.xy / l
                if dir.x < -1e-12 || (abs(dir.x) <= 1e-12 && dir.y < 0) { dir = -dir }
                let key = Int((atan2(dir.y, dir.x) * 180 / .pi * 100).rounded())
                if seen.insert(key).inserted { cands.append((l, dir)) } else if let i = cands.firstIndex(where: { abs($0.1.cross(dir)) < 2e-4 }), cands[i].0 < l { cands[i].0 = l }
            }
        }
        return cands.sorted { $0.0 > $1.0 }.map(\.1)
    }

    /// Axis-aligned (in some horizontal direction) box: returns the direction along its longest side.
    func boxDirection(_ w: Welded) -> Vec2? {
        let o = w.pts[0].xy
        for dir in horizontalDirections(w).prefix(16) {
            let n = dir.perpendicular
            let ss = w.pts.map { ($0.xy - o).dot(dir) }, ts = w.pts.map { ($0.xy - o).dot(n) }
            func two(_ xs: [Double]) -> Bool { let lo = xs.min()!, hi = xs.max()!; return xs.allSatisfy { abs($0 - lo) < 0.001 || abs($0 - hi) < 0.001 } }
            if two(ss) && two(ts) { return (ss.max()! - ss.min()!) >= (ts.max()! - ts.min()!) ? dir : n }
        }
        return nil
    }

    func analyzeFloor(_ info: ProductInfo, mesh: TriMesh) -> FloorSpec? {
        guard let o = prismOutline(mesh) else { return nil }
        let outer = o.loops[0]
        let holes = o.loops.dropFirst().filter { outer.contains($0.points[0]) }
        let sketch = Sketch(loops: ([outer.counterClockwise] + holes.map(\.clockwise)).map { $0.edges.map { Curve2.line($0) } })
        guard case .success = sketch.profile() else { return nil }
        let th = o.top - o.bottom
        let (ls, _, setName) = resolvedLayers(info, thickness: th)
        return FloorSpec(product: info, sketch: sketch, topZ: o.top, thickness: th, layers: ls, typeName: info.typeEntity?[2].stringValue ?? setName)
    }

    func analyzeSpace(_ info: ProductInfo, mesh: TriMesh?) -> SpaceSpec? {
        let e = info.entity
        let longName = e[7].stringValue ?? ""
        let roomName = longName.isEmpty ? info.name : longName
        let number = longName.isEmpty ? "" : info.name
        guard let mesh else {
            let p = geo.placement(e[5]).origin
            return SpaceSpec(product: info, point: p.xy, baseZ: p.z, height: 2.7, roomName: roomName, number: number)
        }
        let w = weld(mesh)
        let zs = w.pts.map(\.z)
        let z0 = zs.min() ?? 0, z1 = zs.max() ?? 0
        var best: (area: Double, c: Vec2)?
        for (a, b, c) in w.tris {
            let pa = w.pts[a], pb = w.pts[b], pc = w.pts[c]
            guard [pa, pb, pc].allSatisfy({ abs($0.z - z0) < 0.001 }) else { continue }
            let area = (pb - pa).cross(pc - pa).length / 2
            if area > (best?.area ?? 0) { best = (area, (pa.xy + pb.xy + pc.xy) / 3) }
        }
        let point = best?.c ?? mesh.bounds.center.xy
        return SpaceSpec(product: info, point: point, baseZ: z0, height: max(0.1, z1 - z0), roomName: roomName, number: number)
    }

    func analyzeColumn(_ info: ProductInfo, mesh: TriMesh) -> ColumnSpec? {
        guard let o = prismOutline(mesh), o.loops.count == 1 else { return nil }
        let poly = o.loops[0].counterClockwise
        let pts = poly.points
        if pts.count == 4 {
            let e0 = pts[1] - pts[0], e1 = pts[2] - pts[1]
            guard abs(e0.normalized.dot(e1.normalized)) < 1e-3 else { return nil }
            let c = pts.reduce(Vec2.zero, +) / 4
            return ColumnSpec(product: info, center: c, rotation: e0.angle, width: e0.length, depth: e1.length, diameter: 0, baseZ: o.bottom, height: o.top - o.bottom)
        }
        if pts.count >= 8 {
            let c = pts.reduce(Vec2.zero, +) / Double(pts.count)
            let rs = pts.map { $0.distance(to: c) }
            let r = rs.reduce(0, +) / Double(rs.count)
            guard r > 0.01, rs.allSatisfy({ abs($0 - r) < 0.02 * r }) else { return nil }
            // Polygonal approximation: use the circumscribed radius so the tessellation matches the source.
            return ColumnSpec(product: info, center: c, rotation: 0, width: 0, depth: 0, diameter: 2 * (rs.max() ?? r), baseZ: o.bottom, height: o.top - o.bottom)
        }
        return nil
    }

    func analyzeBeam(_ info: ProductInfo, mesh: TriMesh) -> BeamSpec? {
        let w = weld(mesh)
        guard w.pts.count == 8, let dir = boxDirection(w) else { return nil }
        let n = dir.perpendicular
        let o = w.pts[0]
        func twoValues(_ xs: [Double]) -> (Double, Double)? {
            let lo = xs.min()!, hi = xs.max()!
            return xs.allSatisfy({ abs($0 - lo) < 0.001 || abs($0 - hi) < 0.001 }) && hi - lo > 0.005 ? (lo, hi) : nil
        }
        guard let (s0, s1) = twoValues(w.pts.map { ($0.xy - o.xy).dot(dir) }), let (t0, t1) = twoValues(w.pts.map { ($0.xy - o.xy).dot(n) }),
              let (z0, z1) = twoValues(w.pts.map(\.z)) else { return nil }
        let tm = (t0 + t1) / 2
        let line = Segment2(o.xy + dir * s0 + n * tm, o.xy + dir * s1 + n * tm)
        return BeamSpec(product: info, line: line, topZ: z1, width: t1 - t0, depth: z1 - z0)
    }

    func analyzeInsert(_ info: ProductInfo) -> InsertSpec? {
        let e = info.entity
        let isDoor = e.type.hasPrefix("IFCDOOR")
        guard let opening = fillerOpening[e.id], let host = openingHost[opening], let wall = walls[host] else { return nil }
        let refMesh = file[opening].flatMap { geo.bodyMesh(of: $0) } ?? geo.bodyMesh(of: e)
        let seg = wall.location
        let dir = seg.direction
        var station: Double, zMin: Double
        var sExtent = 0.0, zExtent = 0.0
        if let m = refMesh, !m.positions.isEmpty {
            let ss = m.positions.map { ($0.xy - seg.start).dot(dir) }
            let zs = m.positions.map(\.z)
            station = (ss.min()! + ss.max()!) / 2
            zMin = zs.min()!
            sExtent = ss.max()! - ss.min()!; zExtent = zs.max()! - zMin
        } else {
            let p = geo.placement(e[5]).origin
            station = (p.xy - seg.start).dot(dir)
            zMin = p.z
        }
        guard station >= -0.001, station <= seg.length + 0.001 else { return nil }
        let width = e[9].doubleValue.map { $0 * lengthScale } ?? sExtent
        let height = e[8].doubleValue.map { $0 * lengthScale } ?? zExtent
        guard width > 0.05, height > 0.05, width < 50, height < 50 else { return nil }
        let pl = geo.placement(e[5])
        let hand = pl.xAxis.xy.dot(dir) < -0.5
        let expectedY = dir.perpendicular * (wall.flipped ? -1 : 1)
        let facing = pl.yAxis.xy.dot(expectedY) < -0.5
        var family = isDoor ? "Door - Single Flush" : "Window - Casement"
        if let r = info.objectType.range(of: ": ") { family = String(info.objectType[..<r.lowerBound]) }
        return InsertSpec(product: info, isDoor: isDoor, hostEntity: host, station: station, sill: max(0, zMin - wall.baseZ), width: width, height: height,
                          familyName: family, handFlipped: hand, facingFlipped: facing)
    }
}
