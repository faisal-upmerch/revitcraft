import Foundation
import ArcusGeometry

// W4-FAMED: Family Editor model logic (selection identity, renames that keep references, plane dragging, canvas camera and
// hit-testing) kept out of the window so it can be unit-tested.

/// Pure edits and queries the Family Editor window applies to a `FamilyDefinition`.
public enum FamilyEditing {
    /// What the editor can select: an item is addressed by the identity the definition already carries (type, plane and
    /// parameter names; ids for dimensions, solids, lines, labels and nested instances).
    public enum Item: Hashable, Sendable {
        case type(String), plane(String), dimension(String), solid(String), line(String), label(String), nested(String)
        case parameter(String)
        /// F1415: a model or reference line, a flip control, model text and a filled or masking region (by id).
        case modelLine(String), control(String), modelText(String), fill(String)
    }

    // MARK: Names and numbers

    /// "Base", "Base 2", "Base 3"… — the first name that `taken` doesn't claim.
    public static func uniqueName(_ base: String, taken: (String) -> Bool) -> String {
        guard taken(base) else { return base }
        var k = 2
        while taken("\(base) \(k)") { k += 1 }
        return "\(base) \(k)"
    }

    /// "Plane 1", "Plane 2"… counting from the number of existing items, skipping names in use.
    public static func numberedName(_ prefix: String, count: Int, taken: (String) -> Bool) -> String {
        var k = count + 1
        while taken("\(prefix) \(k)") { k += 1 }
        return "\(prefix) \(k)"
    }

    /// Parameter and plane names must be usable in formulas: letters, digits, spaces and underscores, not starting with a digit.
    public static func isValidName(_ raw: String) -> Bool {
        let n = raw.trimmingCharacters(in: .whitespaces)
        guard let first = n.unicodeScalars.first, !CharacterSet.decimalDigits.contains(first) else { return false }
        return n.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "_" }
    }

    /// A metre value as the shortest plain decimal a formula field accepts (rounded to a micrometre): 0.45, -1.2, 0.
    public static func numberText(_ v: Double) -> String {
        let r = (v * 1e6).rounded() / 1e6
        if r == 0 { return "0" }
        var s = String(format: "%.6f", r)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// The number a plain numeric offset or formula field holds, or nil when it is an expression.
    public static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces))
    }

    // MARK: Formula token replacement

    static func isIdentifierScalar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    /// Replaces whole-name occurrences of `old` in a formula with `new`. A match must sit on identifier boundaries and must
    /// not be part of a longer known name (`"Width"` inside `"Frame Width"` is left alone when `known` lists it).
    public static func replacingName(in formula: String, _ old: String, with new: String, known: [String]) -> String {
        guard !old.isEmpty, formula.contains(old) else { return formula }
        let longer = known.filter { $0 != old && $0.contains(old) }
        var out = ""
        var i = formula.startIndex
        while i < formula.endIndex {
            if formula[i...].hasPrefix(old) {
                let end = formula.index(i, offsetBy: old.count)
                let before = i > formula.startIndex ? formula[formula.index(before: i)] : nil
                let after = end < formula.endIndex ? formula[end] : nil
                let bounded = !(before.map(isIdentifierScalar) ?? false) && !(after.map(isIdentifierScalar) ?? false)
                let covered = longer.contains { n in
                    guard let inner = n.range(of: old) else { return false }
                    let lead = n.distance(from: n.startIndex, to: inner.lowerBound)
                    guard let start = formula.index(i, offsetBy: -lead, limitedBy: formula.startIndex) else { return false }
                    return formula[start...].hasPrefix(n)
                }
                if bounded && !covered { out += new; i = end; continue }
            }
            out.append(formula[i]); i = formula.index(after: i)
        }
        return out
    }

    /// Applies `f` to every expression string in the family (formulas, plane offsets, bounds, points, rotations, bindings).
    static func mapExpressions(_ family: inout FamilyDefinition, _ f: (String) -> String) {
        func b(_ x: FamilyBound) -> FamilyBound { if case .expr(let e) = x { return .expr(f(e)) }; return x }
        func p(_ x: FamilyPoint) -> FamilyPoint { FamilyPoint(b(x.x), b(x.y)) }
        for i in family.parameters.indices { family.parameters[i].formula = family.parameters[i].formula.map(f) }
        for i in family.referencePlanes.indices { family.referencePlanes[i].offset = f(family.referencePlanes[i].offset) }
        for i in family.solids.indices {
            var s = family.solids[i]
            switch s.profile {
            case .rectangle(let x0, let x1, let y0, let y1): s.profile = .rectangle(xMin: b(x0), xMax: b(x1), yMin: b(y0), yMax: b(y1))
            case .polygon(let pts): s.profile = .polygon(pts.map(p))
            case .circle(let c, let r): s.profile = .circle(center: p(c), radius: f(r))
            case .sweep(var sw): sw.path = sw.path.map(p); sw.profile = sw.profile.map(p); sw.endProfile = sw.endProfile?.map(p); s.profile = .sweep(sw) // F1415: swept blends
            case .blend(let bl): s.profile = .blend(FamilyBlend(bottom: bl.bottom.map(p), top: bl.top.map(p)))
            case .revolve(var rv): rv.profile = rv.profile.map(p); rv.axis = p(rv.axis); rv.startDegrees = f(rv.startDegrees); rv.endDegrees = f(rv.endDegrees); s.profile = .revolve(rv)
            }
            s.zMin = b(s.zMin); s.zMax = b(s.zMax)
            family.solids[i] = s
        }
        func line(_ l: inout FamilyLine) {
            switch l.shape {
            case .line(let a, let c): l.shape = .line(p(a), p(c))
            case .arc(let c, let r, let sa, let sw): l.shape = .arc(center: p(c), radius: f(r), startDegrees: f(sa), sweepDegrees: f(sw))
            }
        }
        for i in family.planLines.indices { line(&family.planLines[i]) }
        for i in family.annotationLines.indices { line(&family.annotationLines[i]) }
        for i in family.fills.indices { family.fills[i].points = family.fills[i].points.map(p) }
        for i in family.labels.indices { family.labels[i].position = p(family.labels[i].position) }
        family.profileLoop = family.profileLoop.map(p)
        if let o = family.opening { family.opening = FamilyOpening(xMin: b(o.xMin), xMax: b(o.xMax), zMin: b(o.zMin), zMax: b(o.zMax)) }
        for i in family.nestedInstances.indices {
            var n = family.nestedInstances[i]
            n.x = b(n.x); n.y = b(n.y); n.z = b(n.z); n.rotation = f(n.rotation)
            n.bindings = n.bindings.mapValues(f)
            family.nestedInstances[i] = n
        }
        mapF1415(&family, bound: b) // F1415
    }

    /// Applies `f` to every plane reference (bounds locked to a plane).
    static func mapPlaneBounds(_ family: inout FamilyDefinition, _ f: (String) -> FamilyBound) {
        func b(_ x: FamilyBound) -> FamilyBound { if case .plane(let n) = x { return f(n) }; return x }
        func p(_ x: FamilyPoint) -> FamilyPoint { FamilyPoint(b(x.x), b(x.y)) }
        for i in family.solids.indices {
            var s = family.solids[i]
            switch s.profile {
            case .rectangle(let x0, let x1, let y0, let y1): s.profile = .rectangle(xMin: b(x0), xMax: b(x1), yMin: b(y0), yMax: b(y1))
            case .polygon(let pts): s.profile = .polygon(pts.map(p))
            case .circle(let c, let r): s.profile = .circle(center: p(c), radius: r)
            case .sweep(var sw): sw.path = sw.path.map(p); sw.profile = sw.profile.map(p); sw.endProfile = sw.endProfile?.map(p); s.profile = .sweep(sw) // F1415: swept blends
            case .blend(let bl): s.profile = .blend(FamilyBlend(bottom: bl.bottom.map(p), top: bl.top.map(p)))
            case .revolve(var rv): rv.profile = rv.profile.map(p); rv.axis = p(rv.axis); s.profile = .revolve(rv)
            }
            s.zMin = b(s.zMin); s.zMax = b(s.zMax)
            family.solids[i] = s
        }
        func line(_ l: inout FamilyLine) {
            switch l.shape {
            case .line(let a, let c): l.shape = .line(p(a), p(c))
            case .arc(let c, let r, let sa, let sw): l.shape = .arc(center: p(c), radius: r, startDegrees: sa, sweepDegrees: sw)
            }
        }
        for i in family.planLines.indices { line(&family.planLines[i]) }
        for i in family.annotationLines.indices { line(&family.annotationLines[i]) }
        for i in family.fills.indices { family.fills[i].points = family.fills[i].points.map(p) }
        for i in family.labels.indices { family.labels[i].position = p(family.labels[i].position) }
        family.profileLoop = family.profileLoop.map(p)
        if let o = family.opening { family.opening = FamilyOpening(xMin: b(o.xMin), xMax: b(o.xMax), zMin: b(o.zMin), zMax: b(o.zMax)) }
        for i in family.nestedInstances.indices { family.nestedInstances[i].x = b(family.nestedInstances[i].x); family.nestedInstances[i].y = b(family.nestedInstances[i].y); family.nestedInstances[i].z = b(family.nestedInstances[i].z) }
        mapF1415(&family, bound: b) // F1415
    }

    // MARK: Types

    /// Adds a type named `name` with the values of `copying` (or empty values). False when the name exists or is blank.
    @discardableResult
    public static func addType(_ f: inout FamilyDefinition, named name: String, copying source: String? = nil) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, f.type(named: n) == nil else { return false }
        f.types.append(FamilyTypeDefinition(name: n, values: source.flatMap { f.type(named: $0)?.values } ?? [:]))
        return true
    }

    /// Renames a type; nested instances that use this family's type by name are not affected (they name nested types).
    @discardableResult
    public static func renameType(_ f: inout FamilyDefinition, _ old: String, to new: String) -> Bool {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != old, f.type(named: n) == nil, let i = f.types.firstIndex(where: { $0.name == old }) else { return false }
        f.types[i].name = n
        return true
    }

    /// Deletes a type; the last type can't be deleted.
    @discardableResult
    public static func deleteType(_ f: inout FamilyDefinition, _ name: String) -> Bool {
        guard f.types.count > 1, f.type(named: name) != nil else { return false }
        f.types.removeAll { $0.name == name }
        return true
    }

    // MARK: Parameters

    /// Renames a parameter and every reference to it: type values, formulas, dimension labels, visibility and material
    /// parameters, nested bindings (both the nested name when it is the host's own parameter and host formulas).
    @discardableResult
    public static func renameParameter(_ f: inout FamilyDefinition, _ old: String, to new: String) -> Bool {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard isValidName(n), n != old, f.parameter(named: n) == nil, let i = f.parameters.firstIndex(where: { $0.name == old }) else { return false }
        let known = f.parameters.map(\.name) + f.referencePlanes.map(\.name)
        f.parameters[i].name = n
        for t in f.types.indices { if let v = f.types[t].values.removeValue(forKey: old) { f.types[t].values[n] = v } }
        for d in f.dimensions.indices where f.dimensions[d].labelParameter == old { f.dimensions[d].labelParameter = n }
        for s in f.solids.indices {
            if f.solids[s].visibilityParameter == old { f.solids[s].visibilityParameter = n }
            if f.solids[s].materialParameter == old { f.solids[s].materialParameter = n }
        }
        for l in f.planLines.indices where f.planLines[l].visibilityParameter == old { f.planLines[l].visibilityParameter = n }
        for l in f.annotationLines.indices where f.annotationLines[l].visibilityParameter == old { f.annotationLines[l].visibilityParameter = n }
        for l in f.labels.indices where f.labels[l].parameterName == old { f.labels[l].parameterName = n }
        for k in f.nestedInstances.indices where f.nestedInstances[k].visibilityParameter == old { f.nestedInstances[k].visibilityParameter = n }
        for k in f.modelTexts.indices { // F1415
            if f.modelTexts[k].visibilityParameter == old { f.modelTexts[k].visibilityParameter = n }
            if f.modelTexts[k].materialParameter == old { f.modelTexts[k].materialParameter = n }
        }
        mapExpressions(&f) { replacingName(in: $0, old, with: n, known: known) }
        return true
    }

    /// Deletes a parameter and clears the labels, visibility and material settings that named it (formulas keep the name
    /// and are reported by the flex test).
    public static func deleteParameter(_ f: inout FamilyDefinition, _ name: String) {
        f.parameters.removeAll { $0.name == name }
        for i in f.types.indices { f.types[i].values.removeValue(forKey: name) }
        for i in f.dimensions.indices where f.dimensions[i].labelParameter == name { f.dimensions[i].labelParameter = nil }
        for i in f.solids.indices {
            if f.solids[i].visibilityParameter == name { f.solids[i].visibilityParameter = nil }
            if f.solids[i].materialParameter == name { f.solids[i].materialParameter = nil }
        }
        for i in f.planLines.indices where f.planLines[i].visibilityParameter == name { f.planLines[i].visibilityParameter = nil }
        for i in f.annotationLines.indices where f.annotationLines[i].visibilityParameter == name { f.annotationLines[i].visibilityParameter = nil }
        for i in f.nestedInstances.indices where f.nestedInstances[i].visibilityParameter == name { f.nestedInstances[i].visibilityParameter = nil }
        for i in f.modelTexts.indices { // F1415
            if f.modelTexts[i].visibilityParameter == name { f.modelTexts[i].visibilityParameter = nil }
            if f.modelTexts[i].materialParameter == name { f.modelTexts[i].materialParameter = nil }
        }
    }

    // MARK: Reference planes

    /// Renames a reference plane and every dimension and locked bound that refers to it.
    @discardableResult
    public static func renamePlane(_ f: inout FamilyDefinition, _ old: String, to new: String) -> Bool {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard isValidName(n), n != old, !f.referencePlanes.contains(where: { $0.name == n }), let i = f.referencePlanes.firstIndex(where: { $0.name == old }) else { return false }
        f.referencePlanes[i].name = n
        for d in f.dimensions.indices {
            if f.dimensions[d].planeA == old { f.dimensions[d].planeA = n }
            if f.dimensions[d].planeB == old { f.dimensions[d].planeB = n }
            if f.dimensions[d].planeC == old { f.dimensions[d].planeC = n }
        }
        mapPlaneBounds(&f) { $0 == old ? .plane(n) : .plane($0) }
        return true
    }

    /// Deletes a plane with the dimensions that measure it; bounds locked to it become the plane's solved position
    /// (`positions`, from the current evaluation) so forms keep their shape. Returns how many bounds were unlocked.
    @discardableResult
    public static func deletePlane(_ f: inout FamilyDefinition, _ name: String, positions: [String: Double]) -> Int {
        guard let p = f.referencePlanes.first(where: { $0.name == name }), !p.definesOrigin else { return 0 }
        f.referencePlanes.removeAll { $0.name == name }
        f.dimensions.removeAll { [$0.planeA, $0.planeB, $0.planeC].contains(name) }
        var baked = 0
        let value = numberText(positions[name] ?? number(p.offset) ?? 0)
        mapPlaneBounds(&f) { n in
            if n == name { baked += 1; return .expr(value) }
            return .plane(n)
        }
        return baked
    }

    /// New plane on `axis` at `value`, named "Plane N".
    public static func newPlane(_ f: FamilyDefinition, axis: FamilyAxis, at value: Double) -> FamilyReferencePlane {
        let n = numberedName("Plane", count: f.referencePlanes.count) { name in f.referencePlanes.contains { $0.name == name } }
        return FamilyReferencePlane(name: n, axis: axis, offset: numberText(value))
    }

    /// How dragging a plane to a new position is applied.
    public enum PlaneMove: Equatable, Sendable {
        /// Rewrite the plane's sketch offset.
        case offset(String)
        /// Set a length parameter (the label of the dimension that drives the plane) in the current type.
        case parameter(String, Double)
        /// The plane can't be moved this way, with the reason.
        case refused(String)
    }

    /// Decides what a drag of `plane` to `value` (metres along its axis) changes: a labelled dimension's parameter when one
    /// drives the plane, else its numeric offset; origin planes, EQ-held planes, locked planes and formula offsets refuse.
    public static func planeMove(_ f: FamilyDefinition, plane name: String, to value: Double, positions: [String: Double]) -> PlaneMove {
        guard let p = f.referencePlanes.first(where: { $0.name == name }) else { return .refused("There is no plane named “\(name)”.") }
        if p.definesOrigin { return .refused("“\(name)” defines the family origin and doesn't move.") }
        for d in f.dimensions where d.planeA == name || d.planeB == name {
            if d.isEquality {
                if d.planeB == name { return .refused("“\(name)” is held midway by an EQ constraint. Move the outer planes instead.") }
                continue
            }
            if let label = d.labelParameter {
                if f.parameter(named: label)?.formula != nil { return .refused("“\(name)” is driven by \(label), which is a formula.") }
                let other = d.planeA == name ? d.planeB : d.planeA
                guard let o = positions[other] else { continue }
                return .parameter(label, abs(value - o))
            }
            if d.isLocked { return .refused("“\(name)” is locked by a dimension. Unlock it to move the plane.") }
        }
        guard number(p.offset) != nil else { return .refused("“\(name)” is placed by the formula “\(p.offset)”. Edit the formula in Properties.") }
        return .offset(numberText(value))
    }

    // MARK: Dimensions

    /// A dimension between two parallel planes (nil for the same plane or different axes).
    public static func dimension(_ f: FamilyDefinition, between a: String, and b: String) -> FamilyDimension? {
        guard a != b, let pa = f.referencePlanes.first(where: { $0.name == a }), let pb = f.referencePlanes.first(where: { $0.name == b }), pa.axis == pb.axis else { return nil }
        return FamilyDimension(planeA: a, planeB: b)
    }

    // MARK: Forms and lines

    /// A rectangular extrusion (or void) covering `rect` in plan between two heights, named "Extrusion N" / "Void N".
    public static func newExtrusion(_ f: FamilyDefinition, rect: Rect2, zMin: Double, zMax: Double, void: Bool) -> FamilySolid {
        let n = numberedName(void ? "Void" : "Extrusion", count: f.solids.count) { name in f.solids.contains { $0.name == name } }
        return FamilySolid(name: n, profile: .rectangle(xMin: .expr(numberText(rect.min.x)), xMax: .expr(numberText(rect.max.x)),
                                                        yMin: .expr(numberText(rect.min.y)), yMax: .expr(numberText(rect.max.y))),
                           zMin: .expr(numberText(zMin)), zMax: .expr(numberText(zMax)), isVoid: void)
    }

    /// A straight symbolic line between two plan points.
    public static func newLine(from a: Vec2, to b: Vec2, subcategory: FamilySubcategory = .general) -> FamilyLine {
        FamilyLine(shape: .line(FamilyPoint(numberText(a.x), numberText(a.y)), FamilyPoint(numberText(b.x), numberText(b.y))), subcategory: subcategory)
    }

    /// A label at a plan point showing `parameter` (or static text when nil).
    public static func newLabel(at p: Vec2, parameter: String?, text: String = "Text") -> FamilyLabel {
        FamilyLabel(position: FamilyPoint(numberText(p.x), numberText(p.y)), parameterName: parameter, staticText: parameter == nil ? text : "")
    }

    /// A copy of a form named "<name> Copy".
    public static func duplicate(_ s: FamilySolid) -> FamilySolid {
        var copy = FamilySolid(name: s.name + " Copy", profile: s.profile, zMin: s.zMin, zMax: s.zMax, materialParameter: s.materialParameter,
                               subcategory: s.subcategory, isVoid: s.isVoid, visibleInPlan: s.visibleInPlan)
        copy.visibilityParameter = s.visibilityParameter; copy.visibleAt = s.visibleAt
        copy.visibleIn3D = s.visibleIn3D; copy.visibleInFrontBack = s.visibleInFrontBack; copy.visibleInLeftRight = s.visibleInLeftRight
        copy.workPlane = s.workPlane // F1415
        return copy
    }

    /// Removes the selected item (and what depends on it). Returns false when nothing was removed.
    @discardableResult
    public static func delete(_ item: Item, from f: inout FamilyDefinition, positions: [String: Double]) -> Bool {
        switch item {
        case .type(let n): return deleteType(&f, n)
        case .plane(let n): let before = f.referencePlanes.count; deletePlane(&f, n, positions: positions); return f.referencePlanes.count < before
        case .dimension(let id): let before = f.dimensions.count; f.dimensions.removeAll { $0.id == id }; return f.dimensions.count < before
        case .solid(let id): let before = f.solids.count; f.solids.removeAll { $0.id == id }; return f.solids.count < before
        case .line(let id):
            let before = f.planLines.count + f.annotationLines.count
            f.planLines.removeAll { $0.id == id }; f.annotationLines.removeAll { $0.id == id }
            return f.planLines.count + f.annotationLines.count < before
        case .label(let id): let before = f.labels.count; f.labels.removeAll { $0.id == id }; return f.labels.count < before
        case .nested(let id): let before = f.nestedInstances.count; f.nestedInstances.removeAll { $0.id == id }; return f.nestedInstances.count < before
        case .parameter(let n):
            guard let p = f.parameter(named: n), !p.isBuiltIn else { return false }
            deleteParameter(&f, n); return true
        case .modelLine, .control, .modelText, .fill: return deleteF1415(item, from: &f) // F1415
        }
    }

    // MARK: Canvas camera

    /// Pan and zoom of the family canvas: `center` is the model point (view u/v, metres) at the middle of the view and
    /// `scale` the points per metre. Screen coordinates have their origin at the top-left corner, y down.
    public struct Camera: Equatable, Sendable {
        public var center: Vec2
        public var scale: Double
        public init(center: Vec2 = .zero, scale: Double = 400) { self.center = center; self.scale = scale }

        public func toScreen(_ p: Vec2, size: Vec2) -> Vec2 {
            Vec2((p.x - center.x) * scale + size.x / 2, size.y / 2 - (p.y - center.y) * scale)
        }
        public func toModel(_ s: Vec2, size: Vec2) -> Vec2 {
            Vec2((s.x - size.x / 2) / scale + center.x, (size.y / 2 - s.y) / scale + center.y)
        }
        /// Zooms by `factor` keeping the model point under `screen` where it is. The scale is clamped to 5–200 000 pt/m.
        public func zoomed(by factor: Double, at screen: Vec2, size: Vec2) -> Camera {
            let anchor = toModel(screen, size: size)
            var c = self
            c.scale = Swift.min(200_000, Swift.max(5, scale * factor))
            let after = c.toModel(screen, size: size)
            c.center = c.center + (anchor - after)
            return c
        }
        /// Pans by a screen-space delta (points; positive y is down).
        public func panned(by delta: Vec2) -> Camera {
            var c = self
            c.center = Vec2(center.x - delta.x / scale, center.y + delta.y / scale)
            return c
        }
        /// A camera showing `bounds` with `inset` points of margin on every side.
        public static func fitting(_ bounds: Rect2, size: Vec2, inset: Double = 48) -> Camera {
            let b = bounds.isEmpty ? Rect2(center: .zero, halfSize: Vec2(0.5, 0.5)) : bounds
            let w = Swift.max(b.width, 1e-3), h = Swift.max(b.height, 1e-3)
            let usable = Vec2(Swift.max(40, size.x - 2 * inset), Swift.max(40, size.y - 2 * inset))
            return Camera(center: b.center, scale: Swift.min(usable.x / w, usable.y / h))
        }
    }

    // MARK: Hit-testing

    /// A reference plane seen edge-on: a vertical (u = value) or horizontal (v = value) line.
    public struct PlaneLine: Equatable, Sendable {
        public var name: String
        public var vertical: Bool
        public var value: Double
        public init(name: String, vertical: Bool, value: Double) { self.name = name; self.vertical = vertical; self.value = value }
    }

    /// The nearest plane within `tolerance` (model units) of `p`.
    public static func hitPlane(_ planes: [PlaneLine], at p: Vec2, tolerance: Double) -> String? {
        var best: (String, Double)?
        for pl in planes {
            let d = abs((pl.vertical ? p.x : p.y) - pl.value)
            if d <= tolerance, best == nil || d < best!.1 { best = (pl.name, d) }
        }
        return best?.0
    }

    /// Distance from `p` to the polyline `points` (closed when `closed`).
    public static func distance(_ p: Vec2, toPolyline points: [Vec2], closed: Bool) -> Double {
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return p.distance(to: first) }
        var best = Double.infinity
        let n = points.count
        for i in 0..<(closed ? n : n - 1) {
            let a = points[i], b = points[(i + 1) % n]
            let ab = b - a
            let t = ab.lengthSquared > 0 ? Swift.max(0, Swift.min(1, (p - a).dot(ab) / ab.lengthSquared)) : 0
            best = Swift.min(best, p.distance(to: a + ab * t))
        }
        return best
    }

    /// The first outline containing `p` (smallest area wins so a form inside another is still pickable), else the nearest
    /// outline within `tolerance`.
    public static func hitOutline(_ outlines: [(item: Item, points: [Vec2], closed: Bool)], at p: Vec2, tolerance: Double) -> Item? {
        var inside: (Item, Double)?
        for o in outlines where o.closed && o.points.count >= 3 {
            let poly = Polygon2(o.points)
            if poly.contains(p) {
                let area = abs(poly.signedArea)
                if inside == nil || area < inside!.1 { inside = (o.item, area) }
            }
        }
        if let inside { return inside.0 }
        var best: (Item, Double)?
        for o in outlines {
            let d = distance(p, toPolyline: o.points, closed: o.closed)
            if d <= tolerance, best == nil || d < best!.1 { best = (o.item, d) }
        }
        return best?.0
    }
}
