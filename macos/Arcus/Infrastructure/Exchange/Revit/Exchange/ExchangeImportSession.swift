import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

/// One import run: resolves references between exchange objects and creates or updates Arcus elements.
final class ExchangeImportSession {
    let doc: ExchangeDocument
    let tx: TransactionContext
    let options: ExchangeImportOptions
    var report = ExchangeImportReport()

    let fileName: String
    let docKey: String
    let formatLabel: String

    var materialIDs: [String: ElementID] = [:]
    var levelIDs: [String: ElementID] = [:]
    /// Exchange type id → Arcus type element (system types and family types).
    var typeIDs: [String: ElementID] = [:]
    /// Exchange system types by id.
    var systemTypes: [String: XType] = [:]
    /// Exchange family type id → converted family.
    var familyOfType: [String: FamilyInfo] = [:]
    /// Imported walls and stairs by exchange id (hosts).
    var hostIDs: [String: ElementID] = [:]
    /// Wall types that are not basic walls (curtain, stacked) by exchange id.
    var unsupportedWallTypes: Set<String> = []

    var existingByGUID: [String: ElementID] = [:]
    var usedGUIDs: Set<String> = []
    /// Every element this import created or updated, with its report kind.
    var touched: [(ElementID, String, created: Bool)] = []
    var totalTriangles = 0
    var fallbackTypes: [String: ElementID] = [:]

    struct FamilyInfo {
        var familyElement: ElementID
        var definition: FamilyDefinition
        var category: ArcusDomain.Category
        var hasGeometry: Bool
    }

    init(doc: ExchangeDocument, tx: TransactionContext, options: ExchangeImportOptions) {
        self.doc = doc
        self.tx = tx
        self.options = options
        fileName = options.fileName ?? doc.source?.fileName ?? "Revit export.\(ExchangeFormat.fileExtension)"
        docKey = doc.source?.documentId ?? doc.source?.fileName ?? options.fileName ?? "document"
        formatLabel = "Arcus Exchange \(doc.schemaVersion ?? ExchangeFormat.schemaVersion)"
        for e in tx.model.allElements {
            existingByGUID[e.ifcGUID.value] = e.id
            usedGUIDs.insert(e.ifcGUID.value)
        }
        report.documentKind = ExchangeDocumentKind(rawValue: doc.documentKind ?? "project") ?? .project
        report.schemaVersion = doc.schemaVersion ?? ""
        report.generator = [doc.generator?.name, doc.generator?.version, doc.generator?.host.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        if report.generator?.isEmpty == true { report.generator = nil }
        report.sourceFileName = doc.source?.fileName
    }

    // MARK: Run

    func run() {
        for s in doc.malformedSections where s != "schemaVersion" {
            warn("file.section", "The “\(s)” section is not in the expected form and was ignored.")
        }
        for (section, n) in doc.decodeFailures.sorted(by: { $0.key < $1.key }) {
            warn("file.item", "\(n) item\(n == 1 ? "" : "s") in “\(section)” could not be read and \(n == 1 ? "was" : "were") skipped.")
            report.skipped[section, default: 0] += n
        }
        importMaterials()
        importLevels()
        importGrids()
        importSystemTypes()
        importFamilies()
        importWalls()
        importSlabs(doc.floors.items, category: .floors, kind: "floors")
        importSlabs(doc.ceilings.items, category: .ceilings, kind: "ceilings")
        importRoofs()
        importInserts()
        importColumns()
        importBeams()
        importStairs()
        importRailings()
        importRooms()
        importComponents()
        importMeshElements()
        importProjectInfo()
        if options.validateWithTrialCommit { validateByTrialCommit() }
        reconcile()
    }

    // MARK: Reporting

    func warn(_ code: String, _ message: String, _ source: String? = nil) {
        if report.warnings.count < 2000 {
            report.warnings.append(ExchangeImportWarning(code: code, message: message, sourceID: source))
        } else if report.warnings.count == 2000 {
            report.warnings.append(ExchangeImportWarning(code: "report.truncated", message: "Further warnings were omitted."))
        }
    }
    func skip(_ kind: String, _ code: String, _ message: String, _ source: String?) {
        report.skipped[kind, default: 0] += 1
        warn(code, message, source)
    }
    func approximate(_ kind: String, _ code: String, _ message: String, _ source: String?) {
        report.approximated[kind, default: 0] += 1
        warn(code, message, source)
    }
    func label(_ kind: String, _ id: String?) -> String { "\(kind) \(id.map { "“\($0)”" } ?? "(no id)")" }

    // MARK: Identity

    /// GlobalId for an exchange object: derived from its source `uniqueId` so re-imports keep identity; from the
    /// document key and exchange id otherwise.
    func seed(_ uniqueId: String?, _ id: String?, _ kind: String) -> String {
        if let u = uniqueId?.trimmingCharacters(in: .whitespaces), !u.isEmpty { return "revit-uniqueid:" + u }
        return "arcusx:\(docKey)/\(kind)/\(id ?? UUID().uuidString)"
    }

    static func guid(forUniqueId u: String) -> IFCGUID { IFCGUID.deterministic("revit-uniqueid:" + u) }

    func freshGUID(_ seed: String) -> IFCGUID {
        var s = seed
        var g = IFCGUID.deterministic(s)
        var n = 0
        while usedGUIDs.contains(g.value) { n += 1; s = seed + "#\(n)"; g = IFCGUID.deterministic(s) }
        usedGUIDs.insert(g.value)
        return g
    }

    /// Creates an element, or updates / keeps the existing element that has the same derived GlobalId.
    @discardableResult
    func upsert(_ kind: String, _ category: ArcusDomain.Category, name: String = "", data: ElementData, typeID: ElementID? = nil,
                levelID: ElementID? = nil, hostID: ElementID? = nil, id: String?, uniqueId: String?,
                source originalType: String? = nil, counted: Bool = true, configure: ((inout Element) -> Void)? = nil) -> ElementID {
        let sd = seed(uniqueId, id, kind)
        let g = IFCGUID.deterministic(sd)
        let src = SourceMetadata(format: formatLabel, fileName: fileName, originalID: uniqueId ?? id ?? "",
                                 originalType: originalType ?? kind, attributes: id.map { ["Exchange id": $0] } ?? [:])
        if let existing = existingByGUID[g.value], let e = tx.model[existing], e.category == category, e.kind == data.kind,
           options.existingElements != .duplicate {
            existingByGUID[g.value] = nil // one exchange object per existing element
            if options.existingElements == .keep {
                if counted { report.kept[kind, default: 0] += 1 }
            } else {
                tx.update(existing) { el in
                    el.name = name; el.data = data; el.typeID = typeID; el.levelID = levelID; el.hostID = hostID
                    el.source = src
                    configure?(&el)
                }
                if counted { report.updated[kind, default: 0] += 1 }
                touched.append((existing, kind, false))
            }
            if let id { report.elementMap[id] = existing }
            return existing
        }
        let guid = freshGUID(sd)
        if guid.value != g.value, uniqueId != nil, existingByGUID[g.value] == nil {
            warn("identity.duplicate", "\(label(kind, id)) repeats a source identity already used in this file; it was given a new GlobalId.", id)
        }
        let newID = tx.create(category, name: name, data: data, typeID: typeID, levelID: levelID, hostID: hostID, ifcGUID: guid) { el in
            el.source = src
            configure?(&el)
        }
        if counted { report.created[kind, default: 0] += 1 }
        touched.append((newID, kind, true))
        if let id { report.elementMap[id] = newID }
        return newID
    }

    /// Applies mark, comments and family instance parameter values.
    func common(mark: String?, comments: String?, parameters: [String: XValue]? = nil, family: FamilyDefinition? = nil) -> (inout Element) -> Void {
        var familyValues: [ParameterID: ParamValue] = [:]
        if let family, let parameters {
            for (k, v) in parameters {
                guard let p = family.parameter(named: k), p.isInstance, p.formula == nil else { continue }
                if case .elementRef = p.type {
                    if case .material(let mid) = v, let m = materialIDs[mid] { familyValues[Parameters.familyParamID(k)] = .ref(m) }
                    continue
                }
                if let pv = ExchangeFamilyConverter.paramValue(v, type: p.type) { familyValues[Parameters.familyParamID(k)] = pv }
            }
        }
        return { e in
            if let m = mark, !m.isEmpty { e.mark = String(m.prefix(1000)) }
            if let c = comments, !c.isEmpty { e.comments = String(c.prefix(10_000)) }
            for (k, v) in familyValues { e.params[k] = v }
        }
    }

    // MARK: Geometry helpers

    func finite(_ d: Double?) -> Double? {
        guard let d, d.isFinite, abs(d) <= options.maxCoordinate else { return nil }
        return d
    }
    func vec2(_ a: [Double]?) -> Vec2? {
        guard let a, a.count >= 2, let x = finite(a[0]), let y = finite(a[1]) else { return nil }
        return Vec2(x, y)
    }
    func vec3(_ a: [Double]?) -> Vec3? {
        guard let a, a.count >= 3, let x = finite(a[0]), let y = finite(a[1]), let z = finite(a[2]) else { return nil }
        return Vec3(x, y, z)
    }
    /// Converts one exchange curve (a circle becomes two arcs).
    func curves(_ c: XCurve) -> [Curve2]? {
        switch c.type ?? "line" {
        case "line":
            guard let a = vec2(c.start), let b = vec2(c.end), !a.isAlmostEqual(b, tolerance: Tolerance.length) else { return nil }
            return [.line(Segment2(a, b))]
        case "arc":
            guard let a = vec2(c.start), let b = vec2(c.end), let m = vec2(c.mid) else { return nil }
            if let arc = Arc2(through: a, m, b), arc.radius < options.maxCoordinate { return [.arc(arc)] }
            return a.isAlmostEqual(b, tolerance: Tolerance.length) ? nil : [.line(Segment2(a, b))]
        case "circle":
            guard let ctr = vec2(c.center), let r = finite(c.radius), r > Tolerance.length else { return nil }
            return [.arc(Arc2(center: ctr, radius: r, startAngle: 0, sweep: .pi)), .arc(Arc2(center: ctr, radius: r, startAngle: .pi, sweep: .pi))]
        default:
            return nil
        }
    }
    func curve(_ c: XCurve?) -> Curve2? {
        guard let c, let cs = curves(c), cs.count == 1 else { return nil }
        return cs[0]
    }
    func sketch(_ loops: [[XCurve]]?) -> Sketch? {
        guard let loops, !loops.isEmpty, loops.reduce(0, { $0 + $1.count }) <= options.maxCurvesPerSketch else { return nil }
        var out: [[Curve2]] = []
        for l in loops {
            var cs: [Curve2] = []
            for c in l {
                guard let x = curves(c) else { return nil }
                cs.append(contentsOf: x)
            }
            if !cs.isEmpty { out.append(cs) }
        }
        return out.isEmpty ? nil : Sketch(loops: out)
    }

    /// Validated mesh (bounded, finite, indices in range) with boundary/crease edges for display.
    func mesh(_ positions: [Double]?, _ indices: [Int]?) -> Mesh? {
        guard let p = positions, let ix = indices, p.count >= 9, p.count % 3 == 0, ix.count >= 3, ix.count % 3 == 0 else { return nil }
        let triangles = ix.count / 3
        guard triangles <= options.maxTrianglesPerMesh, totalTriangles + triangles <= options.maxTotalTriangles else { return nil }
        let vc = p.count / 3
        var pts: [Vec3] = []
        pts.reserveCapacity(vc)
        for i in 0..<vc {
            guard let v = vec3([p[3 * i], p[3 * i + 1], p[3 * i + 2]]) else { return nil }
            pts.append(v)
        }
        var idx: [UInt32] = []
        idx.reserveCapacity(ix.count)
        for i in ix {
            guard i >= 0, i < vc else { return nil }
            idx.append(UInt32(i))
        }
        totalTriangles += triangles
        // Feature edges: edges used by one triangle, or between triangles meeting at more than ~30°.
        struct Key: Hashable { var a: UInt32, b: UInt32 }
        var normals: [Vec3] = []
        normals.reserveCapacity(triangles)
        var edgeTris: [Key: [Int]] = [:]
        for t in 0..<triangles {
            let a = idx[3 * t], b = idx[3 * t + 1], c = idx[3 * t + 2]
            normals.append((pts[Int(b)] - pts[Int(a)]).cross(pts[Int(c)] - pts[Int(a)]).normalized)
            for (u, v) in [(a, b), (b, c), (c, a)] { edgeTris[Key(a: min(u, v), b: max(u, v)), default: []].append(t) }
        }
        var edges: [UInt32] = []
        for (k, ts) in edgeTris {
            if ts.count != 2 || normals[ts[0]].dot(normals[ts[1]]) < 0.866 { edges.append(k.a); edges.append(k.b) }
        }
        return Mesh(positions: pts, normals: [Vec3](repeating: .unitZ, count: pts.count), indices: idx, featureEdges: edges)
    }

    /// Imports fallback geometry for an object Arcus can't represent natively. Returns false when there is none.
    @discardableResult
    func referenceMesh(_ m: XMesh?, kind: String, category label: String, name: String?, levelID: ElementID?, reason: String,
                       id: String?, uniqueId: String?, materialID: String? = nil, parameters: [String: XValue]? = nil) -> Bool {
        guard options.importMeshes, let m, let mesh = mesh(m.positions, m.indices) else { return false }
        var props: [String: String] = ["Source": "Revit (Arcus Exchange)", "Revit Category": label, "Reason": reason]
        if let mid = materialID, let mat = materialIDs[mid].flatMap({ tx.model[$0] }) { props["Material"] = mat.name }
        for (k, v) in (parameters ?? [:]).prefix(200) {
            switch v {
            case .text(let s): props[k] = String(s.prefix(1000))
            case .number(let d): props[k] = ExchangeFamilyConverter.fmt(d)
            case .bool(let b): props[k] = b ? "Yes" : "No"
            default: break
            }
        }
        let data = ReferenceGeometryData(mesh: mesh, ifcType: "Revit: \(label)", properties: props)
        let n = (name?.isEmpty == false ? name! : label) + " (reference)"
        upsert("reference meshes", .ifcReference, name: n, data: .referenceGeometry(data), levelID: levelID, id: id, uniqueId: uniqueId, source: label, counted: false)
        report.referenceMeshes[label, default: 0] += 1
        return true
    }

    // MARK: Levels

    func level(_ xid: String?, z: Double? = nil, _ what: String, _ source: String?) -> ElementID {
        if let xid, let l = levelIDs[xid] { return l }
        let levels = tx.model.levels
        if xid != nil { warn("ref.level", "\(what) refers to a level that was not imported; it was placed on the nearest level.", source) }
        if levels.isEmpty {
            let id = tx.create(.levels, name: "Level 1", data: .level(LevelData(elevation: 0)))
            report.created["levels", default: 0] += 1
            touched.append((id, "levels", true))
            return id
        }
        if let z, let l = levels.last(where: { ($0.level?.elevation ?? 0) <= z + 1e-3 }) { return l.id }
        return levels[0].id
    }
    func optionalLevel(_ xid: String?) -> ElementID? { xid.flatMap { levelIDs[$0] } }
    func elevation(_ l: ElementID?) -> Double { tx.model.elevation(ofLevel: l) }

    // MARK: Trial commit

    /// Commits a scratch copy of the imported elements and removes any the model's validation rejects.
    func validateByTrialCommit() {
        for _ in 0..<50 {
            let ids = Set(touched.map(\.0)).filter { tx.model[$0] != nil }
            guard !ids.isEmpty else { return }
            let scratch = TransactionContext(model: tx.model, name: "Validate import")
            for id in ids.sorted() { if let e = tx.model[id] { scratch.insertPreservingID(e) } }
            do {
                _ = try scratch.commit()
                return
            } catch {
                let bad = error.elements.filter { ids.contains($0) }
                guard !bad.isEmpty else {
                    warn("validate.model", "The model reported a problem not caused by the import: \(error.message)")
                    return
                }
                for id in bad {
                    let kind = touched.first { $0.0 == id }?.1 ?? "elements"
                    warn("validate.removed", "An imported \(kind.hasSuffix("s") ? String(kind.dropLast()) : kind) was removed because Arcus rejected it: \(error.message)",
                         report.elementMap.first { $0.value == id }?.key)
                    tx.delete(id)
                }
            }
        }
    }

    /// Moves counts of elements that no longer exist (deleted by validation or cascades) from created to skipped.
    func reconcile() {
        for (id, kind, created) in touched where tx.model[id] == nil {
            if kind != "reference meshes" {
                if created { report.created[kind, default: 0] -= 1 } else { report.updated[kind, default: 0] -= 1 }
            }
            report.skipped[kind, default: 0] += 1
            for (k, v) in report.elementMap where v == id { report.elementMap[k] = nil }
        }
        report.created = report.created.filter { $0.value > 0 }
        report.updated = report.updated.filter { $0.value > 0 }
    }
}
