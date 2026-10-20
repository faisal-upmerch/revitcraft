import Foundation
import ArcusGeometry
import ArcusCalc

/// Result of evaluating a family for one type and a set of instance parameter overrides.
public struct EvaluatedFamily: Sendable {
    public var values: [String: FormulaValue]
    public var planes: [String: Double]
    public enum Form: String, Sendable { case extrusion = "Extrusion", sweep = "Sweep", blend = "Blend", revolve = "Revolve" }
    public struct Solid: Sendable {
        public var name: String
        public var form: Form
        /// Extrusion profile, or the plan footprint of a sweep, blend or revolve.
        public var profile: Profile2
        public var zMin: Double
        public var zMax: Double
        /// Family-space mesh of a sweep, blend or revolve (nil for extrusions, which are built from `profile`).
        public var mesh: Mesh?
        public var materialParameter: String?
        /// Material already resolved (solids of nested families whose material comes from the nested family's values).
        public var resolvedMaterial: ElementID?
        public var subcategory: FamilySubcategory
        public var isVoid: Bool
        public var visibleAt: Set<DetailLevel>
        public var visibleInPlan: Bool
        public var visibleIn3D: Bool
        public var visibleInFrontBack: Bool
        public var visibleInLeftRight: Bool
        /// Id of the `FamilySolid` this came from (nil for solids of nested families). // W4-FAMED
        public var sourceID: String? = nil
        /// FM6: a void's Cut Geometry (the `FamilySolid` ids it cuts; nil = every solid it reaches).
        public var cuts: [String]? = nil

        /// Closed mesh in family coordinates.
        public var familyMesh: Mesh { mesh ?? MeshBuilder.extrude(profile, bottom: zMin, top: zMax) }
        /// VIS: the mesh came out of a Boolean cut (BSP slivers and T-junctions along cut curves).
        public var booleanCut = false
        /// VIS: the mesh for views: a Boolean result without lines inside its smooth surfaces and with its T-junctions
        /// closed, so cut curves draw and shade like the builders' own.
        public var displayMesh: Mesh {
            booleanCut ? MeshSmoothing.fixingTJunctions(MeshSmoothing.droppingSmoothEdges(familyMesh)) : familyMesh
        }
        public var bounds: Box3 {
            if let mesh { return mesh.bounds }
            var b = Box3.empty
            for p in profile.outer.points { b.include(Vec3(p.x, p.y, zMin)); b.include(Vec3(p.x, p.y, zMax)) }
            return b
        }
    }
    public var solids: [Solid]
    public struct Line: Sendable {
        public var curve: Curve2
        public var subcategory: FamilySubcategory
        public var weight: Int
        public var visibleAt: Set<DetailLevel>
        /// Id of the `FamilyLine` this came from (nil for lines of nested families). // W4-FAMED
        public var sourceID: String? = nil
    }
    public var planLines: [Line]
    public var annotationLines: [Line]
    public struct Fill: Sendable {
        public var polygon: Polygon2
        public var pattern: FillPatternKind
        public var isMasking: Bool
        /// Id of the `FamilyFill` this came from (nil for fills of nested families). // F1415
        public var sourceID: String? = nil
    }
    public var fills: [Fill]
    public struct Label: Sendable {
        public var position: Vec2
        public var parameterName: String?
        public var staticText: String
        public var height: Double
        public var alignment: TextAlignment
        public var bold: Bool
        public var sample: String
        /// Id of the `FamilyLabel` this came from (nil for labels of nested families). // W4-FAMED
        public var sourceID: String? = nil
    }
    public var labels: [Label]
    /// Opening rectangle in family X (along host) and Z (from insertion elevation).
    public var opening: (xMin: Double, xMax: Double, zMin: Double, zMax: Double)?
    public var profileLoop: Polygon2?
    /// Measured distance per family dimension id (after solving).
    public var dimensionValues: [String: Double]
    /// Dimension ids whose constraint could not be satisfied.
    public var conflictingDimensions: Set<String>
    /// Problems that make the family's geometry wrong for this type (fail the flex test).
    public var errors: [String]
    /// Notes that don't block loading.
    public var warnings: [String]
    /// F1415: model and reference lines, in family coordinates.
    public var modelLines: [ModelLine] = []
    /// F1415: flip controls, in family plan coordinates.
    public var controls: [Control] = []

    public var bounds: Box3 {
        var b = Box3.empty
        for s in solids where !s.isVoid { b.include(s.bounds) }
        return b
    }
    public func length(_ name: String) -> Double? {
        if case .quantity(let v, _)? = values[name] { return v }
        return nil
    }
    public func bool(_ name: String) -> Bool? {
        if case .bool(let b)? = values[name] { return b }
        return nil
    }
}

public enum FamilyEvaluationError: Error, Hashable, Sendable, CustomStringConvertible {
    case missingType(String)
    case formula(parameter: String, message: String)
    case invalidGeometry(String)
    public var description: String {
        switch self {
        case .missingType(let t): "The family has no type named “\(t)”."
        case .formula(let p, let m): "Parameter “\(p)”: \(m)"
        case .invalidGeometry(let m): m
        }
    }
}

public enum FamilyEvaluator {
    /// Converts a stored parameter value into a formula value.
    public static func formulaValue(_ v: ParamValue, type: ParamType) -> FormulaValue {
        switch type {
        case .text, .multilineText, .url, .choice: return .text(v.textValue ?? v.description)
        case .bool: return .bool(v.boolValue ?? false)
        case .elementRef: return .quantity(Double(v.refValue?.raw ?? 0), .none)
        default: return .quantity(v.doubleValue ?? 0, type.dimension ?? .none)
        }
    }

    public static func paramValue(_ f: FormulaValue, type: ParamType) -> ParamValue {
        switch f {
        case .bool(let b): return type == .bool ? .bool(b) : .int(b ? 1 : 0)
        case .text(let s): return .text(s)
        case .quantity(let v, _):
            if case .elementRef = type { return v >= 1 && v.isFinite ? .ref(ElementID(UInt64(v.rounded()))) : type.defaultValue }
            if type == .integer { return .int(Int(v.rounded())) }
            if type == .bool { return .bool(v != 0) }
            return .double(v)
        }
    }

    /// Evaluates all parameters (formulas included) for a type plus instance overrides.
    public static func parameterValues(_ family: FamilyDefinition, typeName: String, instance: [String: ParamValue] = [:],
                                       units: UnitsSettings = .metric) -> (values: [String: FormulaValue], errors: [String]) {
        let typeDef = family.type(named: typeName) ?? family.types.first
        var inputs: [String: FormulaValue] = [:]
        var formulas: [String: String] = [:]
        var expected: [String: UnitKind] = [:]
        for p in family.parameters {
            if let f = p.formula, !f.trimmingCharacters(in: .whitespaces).isEmpty {
                formulas[p.name] = f
                if let k = p.type.unitKind { expected[p.name] = k }
            } else {
                let raw = (p.isInstance ? instance[p.name] : nil) ?? typeDef?.values[p.name] ?? p.type.defaultValue
                inputs[p.name] = formulaValue(raw, type: p.type)
            }
        }
        var errors: [String] = []
        var values = inputs
        if !formulas.isEmpty {
            let results = FormulaSystem.evaluateAll(formulas: formulas, inputs: inputs, expected: expected, units: units)
            for (name, r) in results.sorted(by: { $0.key < $1.key }) {
                switch r {
                case .success(let v): values[name] = v
                case .failure(let e):
                    errors.append("Parameter “\(name)”: \(e.message)")
                    let t = family.parameter(named: name)?.type ?? .number
                    values[name] = formulaValue(t.defaultValue, type: t)
                }
            }
        }
        return (values, errors)
    }

    /// Evaluates a family. `quality` sets how finely circles, arcs and curved profiles are cut into segments (VIS: one
    /// per view detail level; Medium when nothing asks).
    public static func evaluate(_ family: FamilyDefinition, typeName: String, instance: [String: ParamValue] = [:],
                                units: UnitsSettings = .metric, quality: TessellationQuality = .medium) -> EvaluatedFamily {
        evaluate(family, typeName: typeName, instance: instance, units: units, chain: [], quality: quality)
    }

    /// Nesting depth limit (a chain of families nested in each other).
    public static let maxNestingDepth = 8

    static func evaluate(_ family: FamilyDefinition, typeName: String, instance: [String: ParamValue],
                         units: UnitsSettings, chain: [String], quality: TessellationQuality = .medium) -> EvaluatedFamily {
        let (values, paramErrors) = parameterValues(family, typeName: typeName, instance: instance, units: units)
        var errors = paramErrors
        var warnings: [String] = []
        let names = Set(values.keys)
        // VIS: one name table and one parse per distinct expression (profiles repeat "Height * …" many times).
        let parse = Formula.parser(knownNames: names)
        var parsed: [String: Formula] = [:]

        func formula(_ s: String) -> FormulaValue? {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if let d = Double(trimmed) { return .quantity(d, .none) }
            do {
                let f: Formula
                if let hit = parsed[trimmed] { f = hit } else { f = try parse(trimmed); parsed[trimmed] = f }
                return try f.evaluate(units: units) { values[$0] }
            } catch {
                errors.append("Expression “\(s)”: \(error)")
                return nil
            }
        }
        func expr(_ s: String) -> Double {
            switch formula(s) {
            case .quantity(let d, _)?: return d.isFinite ? d : 0
            case .bool(let b)?: return b ? 1 : 0
            case .text?: errors.append("Expression “\(s)” is text, expected a length."); return 0
            case nil: return 0
            }
        }
        var sketch: [String: Double] = [:]
        for p in family.referencePlanes { sketch[p.name] = expr(p.offset) }
        let solved = FamilyConstraintSolver.solve(family, sketch: sketch) { name in
            if case .quantity(let v, let d)? = values[name], d == .length || d == .none { return v }
            return nil
        }
        errors += solved.errors
        let planes = solved.planes
        func bound(_ b: FamilyBound) -> Double {
            switch b {
            case .plane(let n):
                if let v = planes[n] { return v }
                errors.append("Reference plane “\(n)” does not exist.")
                return 0
            case .expr(let e): return expr(e)
            }
        }
        func point(_ p: FamilyPoint) -> Vec2 { Vec2(bound(p.x), bound(p.y)) }
        func visible(_ param: String?) -> Bool {
            guard let param else { return true }
            if case .bool(let b)? = values[param] { return b }
            return true
        }
        func loop(_ pts: [FamilyPoint]) -> Polygon2? {
            guard pts.count >= 3 else { return nil }
            let poly = Polygon2(CurveRefinement.refine(pts.map(point), closed: true, quality: quality)) // VIS: curves stored as points
            return poly.isDegenerate ? nil : poly
        }

        var solids: [EvaluatedFamily.Solid] = []
        for s in family.solids where visible(s.visibilityParameter) {
            func make(_ form: EvaluatedFamily.Form, _ profile: Profile2, _ z0: Double, _ z1: Double, mesh: Mesh? = nil) -> EvaluatedFamily.Solid {
                var r: EvaluatedFamily.Solid = .init(name: s.name, form: form, profile: profile, zMin: z0, zMax: z1, mesh: mesh, materialParameter: s.materialParameter,
                      resolvedMaterial: nil, subcategory: s.subcategory, isVoid: s.isVoid, visibleAt: s.visibleAt, visibleInPlan: s.visibleInPlan,
                      visibleIn3D: s.visibleIn3D, visibleInFrontBack: s.visibleInFrontBack, visibleInLeftRight: s.visibleInLeftRight, sourceID: s.id) // W4-FAMED
                r.cuts = s.cuts // FM6
                return r
            }
            switch s.profile {
            case .rectangle, .polygon, .circle:
                let profile: Profile2?
                switch s.profile {
                case .rectangle(let x0, let x1, let y0, let y1):
                    let a = bound(x0), b = bound(x1), c = bound(y0), d = bound(y1)
                    let r = Rect2(min: Vec2(min(a, b), min(c, d)), max: Vec2(max(a, b), max(c, d)))
                    profile = r.width > Tolerance.length && r.height > Tolerance.length ? .init(outer: .rectangle(r)) : nil
                case .polygon(let pts):
                    let poly = Polygon2(CurveRefinement.refine(pts.map(point), closed: true, quality: quality)) // VIS
                    profile = poly.isDegenerate ? nil : Profile2(outer: poly)
                case .circle(let c, let r):
                    let rr = expr(r)
                    profile = rr > Tolerance.length ? Profile2(outer: Polygon2(Arc2(center: point(c), radius: rr, startAngle: 0, sweep: Angle.twoPi).tessellate(quality: quality).dropLast())) : nil
                default:
                    profile = nil
                }
                let z0 = bound(s.zMin), z1 = bound(s.zMax)
                guard let profile else {
                    errors.append("Solid “\(s.name)” has zero width or depth for this type.")
                    continue
                }
                guard z1 - z0 > Tolerance.length else {
                    errors.append("Solid “\(s.name)” has zero or negative \(s.workPlane.map { $0 == .xy ? "height" : "depth" } ?? "height") for this type.")
                    continue
                }
                // F1415: an extrusion sketched on an elevation plane runs along that plane's normal.
                if let wp = s.workPlane, wp != .xy {
                    let mesh = FamilyFormGeometry.planeExtrusion(profile, plane: wp, w0: z0, w1: z1)
                    guard let foot = FamilyFormGeometry.boxFootprint(mesh) else {
                        errors.append("Solid “\(s.name)” can't be built for this type.")
                        continue
                    }
                    let b = mesh.bounds
                    solids.append(make(.extrusion, foot, b.min.z, b.max.z, mesh: mesh))
                    continue
                }
                solids.append(make(.extrusion, profile, z0, z1))
            case .sweep(let sw):
                let z0 = bound(s.zMin)
                var path: [Vec2] = []
                for p in sw.path.map(point) where path.last.map({ !$0.isAlmostEqual(p) }) ?? true { path.append(p) }
                path = CurveRefinement.refine(path, closed: false, quality: quality) // VIS: arcs in the path
                guard path.count >= 2 else {
                    errors.append("\(s.profile.kindName) “\(s.name)” needs a path of at least two distinct points.")
                    continue
                }
                // F1415: Swept Blend, from the start profile to the end profile along the path.
                if sw.isSweptBlend, let endPts = sw.endProfile {
                    guard let p1 = loop(sw.profile), let p2 = loop(endPts) else {
                        errors.append("Swept Blend “\(s.name)” needs two closed profiles with area for this type.")
                        continue
                    }
                    var mesh = FamilyFormGeometry.sweptBlendMesh(path: path, z0: z0, start: p1, end: p2)
                    let us = (p1.points + p2.points).map(\.x)
                    if let wp = s.workPlane, wp != .xy, !mesh.isEmpty, let foot = FamilyFormGeometry.boxFootprint(mesh.transformed(wp.transform)) { // FMG1: a path on any work plane
                        mesh = mesh.transformed(wp.transform)
                        let b = mesh.bounds
                        solids.append(make(.sweep, foot, b.min.z, b.max.z, mesh: mesh))
                        continue
                    }
                    guard !mesh.isEmpty, let foot = FamilyFormGeometry.sweepFootprint(path: path, uMin: us.min() ?? 0, uMax: us.max() ?? 0) else {
                        errors.append("Swept Blend “\(s.name)” can't be built for this type.")
                        continue
                    }
                    let b = mesh.bounds
                    solids.append(make(.sweep, foot, b.min.z, b.max.z, mesh: mesh))
                    continue
                }
                var profile: Polygon2?
                if let pfName = sw.profileFamily {
                    guard let pf = family.nestedFamily(named: pfName) else {
                        errors.append("Sweep “\(s.name)” uses the profile family “\(pfName)”, which isn't loaded in this family.")
                        continue
                    }
                    let pev = evaluate(pf, typeName: sw.profileFamilyType ?? pf.types.first?.name ?? "", instance: [:], units: units, chain: chain + [family.name],
                                       quality: quality)
                    errors += pev.errors.map { "Profile “\(pfName)”: \($0)" }
                    profile = pev.profileLoop.flatMap { $0.isDegenerate ? nil : Polygon2(CurveRefinement.refine($0.points, closed: true, quality: quality)) } // VIS
                } else {
                    profile = loop(sw.profile)
                }
                guard let profile else {
                    errors.append("Sweep “\(s.name)” has no closed profile with area for this type.")
                    continue
                }
                let mesh = MeshBuilder.sweep(profile: profile, along: path.map { $0.at(z: z0) })
                let us = profile.points.map(\.x)
                // FMG1: a path sketched on an elevation work plane: built in the sketch's (u, v, w) and turned onto it, the
                // profile's x to the left of the path in the sketch and its y along the plane's normal.
                if let wp = s.workPlane, wp != .xy, !mesh.isEmpty, let foot = FamilyFormGeometry.boxFootprint(mesh.transformed(wp.transform)) {
                    let placed = mesh.transformed(wp.transform)
                    let b = placed.bounds
                    solids.append(make(.sweep, foot, b.min.z, b.max.z, mesh: placed))
                    continue
                }
                guard !mesh.isEmpty, let foot = FamilyFormGeometry.sweepFootprint(path: path, uMin: us.min() ?? 0, uMax: us.max() ?? 0) else {
                    errors.append("Sweep “\(s.name)” can't be built for this type.")
                    continue
                }
                let b = mesh.bounds
                solids.append(make(.sweep, foot, b.min.z, b.max.z, mesh: mesh))
            case .blend(let bl):
                let z0 = bound(s.zMin), z1 = bound(s.zMax)
                guard let bottom = loop(bl.bottom), let top = loop(bl.top) else {
                    errors.append("Blend “\(s.name)” needs a bottom and a top loop with area.")
                    continue
                }
                guard z1 - z0 > Tolerance.length else {
                    errors.append("Blend “\(s.name)” has zero or negative height for this type.")
                    continue
                }
                let mesh = FamilyFormGeometry.blendMesh(bottom: bottom, top: top, z0: z0, z1: z1)
                if let wp = s.workPlane, wp != .xy, !mesh.isEmpty { // COMPA: a blend on a side work plane runs along its normal
                    let placed = mesh.transformed(wp.transform)
                    guard let foot = FamilyFormGeometry.boxFootprint(placed) else {
                        errors.append("Blend “\(s.name)” can't be built for this type.")
                        continue
                    }
                    let b = placed.bounds
                    solids.append(make(.blend, foot, b.min.z, b.max.z, mesh: placed))
                    continue
                }
                guard !mesh.isEmpty, let foot = FamilyFormGeometry.blendFootprint(bottom: bottom, top: top) else {
                    errors.append("Blend “\(s.name)” can't be built for this type.")
                    continue
                }
                solids.append(make(.blend, foot, z0, z1, mesh: mesh))
            case .revolve(let rv):
                let z0 = bound(s.zMin)
                guard let prof = loop(rv.profile) else {
                    errors.append("Revolve “\(s.name)” needs a closed profile with area.")
                    continue
                }
                let rs = prof.points.map(\.x)
                guard (rs.min() ?? 0) >= -Tolerance.length else {
                    errors.append("Revolve “\(s.name)” has a profile that crosses its axis.")
                    continue
                }
                let a0 = Angle.radians(expr(rv.startDegrees)), a1 = Angle.radians(expr(rv.endDegrees))
                var sweep = a1 - a0
                if abs(sweep) > Angle.twoPi { sweep = sweep > 0 ? Angle.twoPi : -Angle.twoPi }
                guard abs(sweep) > Tolerance.angle else {
                    errors.append("Revolve “\(s.name)” has equal start and end angles.")
                    continue
                }
                let axis = point(rv.axis)
                let segments = max(4, quality.segments(radius: max(rs.max() ?? 0, Tolerance.length), sweep: sweep)) // VIS: by size and detail level
                let raw = MeshBuilder.revolve(profile: prof.points.map { Vec2(max(0, $0.x), $0.y + z0) }, around: Vec3(axis, z: 0), segments: segments, angle: sweep)
                let mesh = raw.transformed(Transform3(Transform2.rotation(a0, around: axis)))
                if let wp = s.workPlane, wp != .xy, !mesh.isEmpty { // COMPA: a revolve on a side work plane turns about that plane's normal axis
                    let placed = mesh.transformed(wp.transform)
                    guard let foot = FamilyFormGeometry.boxFootprint(placed) else {
                        errors.append("Revolve “\(s.name)” can't be built for this type.")
                        continue
                    }
                    let b = placed.bounds
                    solids.append(make(.revolve, foot, b.min.z, b.max.z, mesh: placed))
                    continue
                }
                guard !mesh.isEmpty, let foot = FamilyFormGeometry.revolveFootprint(axis: axis, rMin: max(0, rs.min() ?? 0), rMax: rs.max() ?? 0, start: a0, sweep: sweep, quality: quality) else {
                    errors.append("Revolve “\(s.name)” can't be built for this type.")
                    continue
                }
                let b = mesh.bounds
                solids.append(make(.revolve, foot, b.min.z, b.max.z, mesh: mesh))
            }
        }
        // F1415: model text, as extrusions of its glyphs from its work plane.
        for t in family.modelTexts where visible(t.visibilityParameter) && !t.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let w0 = bound(t.offset), w1 = w0 + max(t.depth, 0.0001)
            for (k, prof) in FamilyFormGeometry.textProfiles(t, origin: point(t.position)).enumerated() {
                var solid = EvaluatedFamily.Solid(name: "Model Text \(k + 1)", form: .extrusion, profile: prof, zMin: w0, zMax: w1, mesh: nil,
                                                  materialParameter: t.materialParameter, resolvedMaterial: nil, subcategory: .general, isVoid: false,
                                                  visibleAt: [.coarse, .medium, .fine], visibleInPlan: true, visibleIn3D: true, visibleInFrontBack: true,
                                                  visibleInLeftRight: true, sourceID: t.id)
                if t.plane != .xy {
                    let mesh = FamilyFormGeometry.planeExtrusion(prof, plane: t.plane, w0: w0, w1: w1)
                    guard let foot = FamilyFormGeometry.boxFootprint(mesh) else { continue }
                    let b = mesh.bounds
                    solid.mesh = mesh; solid.profile = foot; solid.zMin = b.min.z; solid.zMax = b.max.z
                }
                solids.append(solid)
            }
        }
        var modelLines: [EvaluatedFamily.ModelLine] = family.modelLines.compactMap { l in
            let w = bound(l.offset), a = point(l.start), b = point(l.end)
            guard !a.isAlmostEqual(b) else { return nil }
            return .init(start: l.plane.point(a.x, a.y, w), end: l.plane.point(b.x, b.y, w), isReference: l.isReference,
                         subcategory: l.subcategory, visibleAt: l.visibleAt, sourceID: l.id)
        }
        let controls = family.controls.map { EvaluatedFamily.Control(position: point($0.position), kind: $0.kind, sourceID: $0.id) }
        func lines(_ ls: [FamilyLine]) -> [EvaluatedFamily.Line] {
            ls.filter { visible($0.visibilityParameter) }.compactMap { l in
                switch l.shape {
                case .line(let a, let b):
                    let s = Segment2(point(a), point(b))
                    return s.isDegenerate ? nil : .init(curve: .line(s), subcategory: l.subcategory, weight: l.weight, visibleAt: l.visibleAt, sourceID: l.id) // W4-FAMED
                case .arc(let c, let r, let sa, let sw):
                    let rr = expr(r)
                    guard rr > Tolerance.length else { return nil }
                    return .init(curve: .arc(Arc2(center: point(c), radius: rr, startAngle: Angle.radians(expr(sa)), sweep: Angle.radians(expr(sw)))),
                                 subcategory: l.subcategory, weight: l.weight, visibleAt: l.visibleAt, sourceID: l.id) // W4-FAMED
                }
            }
        }
        var planLines = lines(family.planLines)
        var annotationLines = lines(family.annotationLines)
        var fills = family.fills.compactMap { f -> EvaluatedFamily.Fill? in
            let poly = Polygon2(f.points.map(point))
            return poly.isDegenerate ? nil : .init(polygon: poly, pattern: f.pattern, isMasking: f.isMasking, sourceID: f.id) // F1415
        }
        var labels = family.labels.map {
            EvaluatedFamily.Label(position: point($0.position), parameterName: $0.parameterName, staticText: $0.staticText,
                                  height: $0.height, alignment: $0.alignment, bold: $0.bold, sample: $0.sample, sourceID: $0.id) // W4-FAMED
        }

        // Nested families: evaluate each instance with its associated (bound) parameters and place it in host coordinates.
        for inst in family.nestedInstances where visible(inst.visibilityParameter) {
            guard let nf = family.nestedFamily(named: inst.familyName) else {
                errors.append("Nested family “\(inst.familyName)” isn't loaded in this family.")
                continue
            }
            if nf.name == family.name || chain.contains(nf.name) {
                errors.append("Nested family “\(nf.name)” contains itself.")
                continue
            }
            guard chain.count < maxNestingDepth else {
                errors.append("Nested family “\(nf.name)” is nested more than \(maxNestingDepth) levels deep.")
                continue
            }
            let tname = inst.typeName.flatMap { nf.type(named: $0) != nil ? $0 : nil } ?? nf.types.first?.name
            if let wanted = inst.typeName, tname != wanted { errors.append("Nested family “\(nf.name)” has no type named “\(wanted)”.") }
            var child = nf
            var tvals = tname.flatMap { nf.type(named: $0)?.values } ?? [:]
            for (param, source) in inst.bindings.sorted(by: { $0.key < $1.key }) where !source.trimmingCharacters(in: .whitespaces).isEmpty {
                guard let np = nf.parameter(named: param) else {
                    errors.append("Nested family “\(nf.name)” has no parameter “\(param)” to associate.")
                    continue
                }
                guard let v = formula(source) else { continue }
                tvals[param] = paramValue(v, type: np.type)
                if let i = child.parameters.firstIndex(where: { $0.name == param }) { child.parameters[i].formula = nil }
            }
            child.types = [FamilyTypeDefinition(name: tname ?? "Nested", values: tvals)]
            let nev = evaluate(child, typeName: tname ?? "Nested", instance: [:], units: units, chain: chain + [family.name], quality: quality)
            errors += nev.errors.map { "Nested “\(nf.name)”: \($0)" }
            warnings += nev.warnings.map { "Nested “\(nf.name)”: \($0)" }
            let origin = Vec3(bound(inst.x), bound(inst.y), bound(inst.z))
            var t2 = Transform2.translation(origin.xy) * Transform2.rotation(Angle.radians(expr(inst.rotation)))
            if inst.mirrored { t2 = t2 * Transform2.scale(-1, 1) }
            let t3 = Transform3(t2, z: origin.z)
            for s in nev.solids {
                var ns = s
                ns.name = "\(nf.name): \(s.name)"
                ns.profile = s.profile.transformed(t2)
                ns.zMin += origin.z; ns.zMax += origin.z
                ns.mesh = s.mesh?.transformed(t3)
                ns.visibleAt = s.visibleAt.intersection(inst.visibleAt)
                if ns.resolvedMaterial == nil, let mp = s.materialParameter, case .quantity(let raw, _)? = nev.values[mp], raw > 0 {
                    ns.resolvedMaterial = ElementID(UInt64(raw))
                }
                ns.materialParameter = nil
                solids.append(ns)
            }
            func placed(_ l: EvaluatedFamily.Line) -> EvaluatedFamily.Line {
                var m = l
                m.curve = l.curve.transformed(t2)
                m.visibleAt = l.visibleAt.intersection(inst.visibleAt)
                return m
            }
            planLines += nev.planLines.map(placed)
            // 2D symbols (detail components, generic annotations) nested in a model family show in its plan.
            if family.template.is3D && !nf.template.is3D { planLines += nev.annotationLines.map(placed) } else { annotationLines += nev.annotationLines.map(placed) }
            fills += nev.fills.map { var f = $0; f.polygon = Polygon2($0.polygon.points.map(t2.apply)); f.sourceID = nil; return f }
            modelLines += nev.modelLines.filter { !$0.isReference }.map { var l = $0; l.start = t3.apply(l.start); l.end = t3.apply(l.end); l.sourceID = nil; return l } // F1415
            labels += nev.labels.map { var l = $0; l.position = t2.apply($0.position); return l }
        }

        // F1415: voids of every form cut the solids they reach. Extrusion from extrusion stays exact (prism minus prism, split
        // at the void's heights, so plan profiles stay crisp); any other pair is cut as meshes (BSP CSG, `MeshCSG`).
        solids = cutVoids(solids)

        var opening: (Double, Double, Double, Double)?
        if let o = family.opening {
            let a = bound(o.xMin), b = bound(o.xMax), c = bound(o.zMin), d = bound(o.zMax)
            if b - a > Tolerance.length && d - c > Tolerance.length {
                opening = (min(a, b), max(a, b), min(c, d), max(c, d))
            } else {
                errors.append("The opening has zero width or height for this type.")
            }
        }
        let profileLoop = family.profileLoop.count >= 3 ? Polygon2(family.profileLoop.map(point)) : nil
        var result = EvaluatedFamily(values: values, planes: planes, solids: solids, planLines: planLines,
                                     annotationLines: annotationLines, fills: fills, labels: labels,
                                     opening: opening.map { (xMin: $0.0, xMax: $0.1, zMin: $0.2, zMax: $0.3) },
                                     profileLoop: profileLoop, dimensionValues: solved.measured, conflictingDimensions: solved.conflicts,
                                     errors: errors, warnings: warnings)
        result.modelLines = modelLines // F1415
        result.controls = controls
        return result
    }

    /// Solid extrusion minus void extrusion: the parts below and above the void keep the full profile, the overlap keeps
    /// the profile difference.
    static func cut(_ s: EvaluatedFamily.Solid, by v: EvaluatedFamily.Solid) -> [EvaluatedFamily.Solid] {
        let lo = max(s.zMin, v.zMin), hi = min(s.zMax, v.zMax)
        guard hi - lo > Tolerance.length, s.profile.bounds.intersects(v.profile.bounds) else { return [s] }
        var out: [EvaluatedFamily.Solid] = []
        if lo - s.zMin > Tolerance.length { var a = s; a.zMax = lo; out.append(a) }
        for p in PolygonBoolean.difference([s.profile], [v.profile]) where p.area > Tolerance.area {
            var m = s; m.profile = p; m.zMin = lo; m.zMax = hi; out.append(m)
        }
        if s.zMax - hi > Tolerance.length { var c = s; c.zMin = hi; out.append(c) }
        return out
    }

    /// Flex test: evaluates every type, plus each type with every instance/type length parameter scaled
    /// by 0.5× and 1.5×, reporting constraint and geometry failures before the family is saved or loaded.
    public static func flexTest(_ family: FamilyDefinition, units: UnitsSettings = .metric) -> [String] {
        var problems: [String] = []
        if family.types.isEmpty { problems.append("The family has no types.") }
        // Cycle check across formulas.
        var deps: [String: Set<String>] = [:]
        let names = Set(family.parameters.map(\.name))
        for p in family.parameters {
            guard let f = p.formula, !f.isEmpty else { continue }
            if let parsed = try? Formula(f, knownNames: names) { deps[p.name] = parsed.referencedNames }
            else { problems.append("Parameter “\(p.name)” has a formula that cannot be parsed.") }
        }
        let (_, cycles) = FormulaSystem.dependencyOrder(formulas: deps)
        for c in cycles { problems.append("Circular formula chain: " + c.joined(separator: " → ")) }

        for t in family.types {
            let r = evaluate(family, typeName: t.name, units: units, quality: .coarse) // VIS: errors don't depend on how fine curves are cut
            for e in r.errors { problems.append("Type “\(t.name)”: \(e)") }
            let flexible = family.parameters.filter { $0.formula == nil && $0.type == .length }
            for p in flexible {
                for factor in [0.5, 1.5] {
                    var vals = t.values
                    let base = vals[p.name]?.doubleValue ?? 0
                    guard base > 0 else { continue }
                    vals[p.name] = .double(base * factor)
                    var fam = family
                    fam.types = [FamilyTypeDefinition(name: t.name, values: vals)]
                    let fr = evaluate(fam, typeName: t.name, units: units, quality: .coarse)
                    for e in fr.errors {
                        let msg = "Flexing “\(p.name)” to \(Int(factor * 100))% in type “\(t.name)”: \(e)"
                        if !problems.contains(msg) { problems.append(msg) }
                    }
                }
            }
        }
        return problems
    }
}
