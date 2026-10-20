import Foundation
import ArcusGeometry

// FM8: compile fidelity (Docs/FurnitureMode.md §3, "Load into Project and Edit Family"). Helpers the parts and fronts
// compilers share to keep planes on formulas (so nothing drifts when a loaded piece flexes).

extension FurnitureCompiler {
    /// The planes of `f` whose position never comes from the dimension solver: formula planes, origin planes, and
    /// planes no dimension references (they stay where they are).
    static func stablePlanes(_ f: FamilyDefinition) -> Set<String> {
        let constrained = Set(f.dimensions.flatMap { [$0.planeA, $0.planeB] + ($0.planeC.map { [$0] } ?? []) })
        var out: Set<String> = []
        for p in f.referencePlanes {
            let numeric = Double(p.offset.trimmingCharacters(in: .whitespaces)) != nil
            if !numeric || p.definesOrigin || !constrained.contains(p.name) { out.insert(p.name) }
        }
        return out
    }

    /// A coordinate as a length expression ("(Width / 2) - 0.01905 m") when its plane is stable, or a fixed value
    /// that doesn't follow a plane; nil when it follows a plane the solver places.
    static func stableExpression(_ v: PartValue, _ f: FamilyDefinition, _ stable: Set<String>) -> String? {
        guard let p = v.plane else { return "\(PartSolidContext.number(v.value)) m" }
        guard stable.contains(p), f.referencePlanes.contains(where: { $0.name == p }) else { return nil }
        return lengthExpression(v, f)
    }
}

// MARK: - Plan representation

extension FurnitureCompiler {
    /// The compiled piece's plan symbols, as casework and furniture families draw them: at Coarse the overall outline on
    /// the framing planes (Left, Right, Front, Back); at Medium and Fine the edges seen from above (each part's footprint
    /// less the edges a higher part hides), bound to the parts' planes so they follow the flex. Fixed-size nested
    /// shapes (legs) carry their own footprint. Plans show only symbols when a family has some, so every detail level
    /// gets them; door swings (FurnitureCompiler+Fronts) add to Medium and Fine.
    static func addPlanRepresentation(to f: inout FamilyDefinition) {
        let planes = Set(f.referencePlanes.map(\.name))
        if ["Left", "Right", "Front", "Back"].allSatisfy(planes.contains) {
            let c = [FamilyPoint(.plane("Left"), .plane("Front")), FamilyPoint(.plane("Right"), .plane("Front")),
                     FamilyPoint(.plane("Right"), .plane("Back")), FamilyPoint(.plane("Left"), .plane("Back"))]
            for i in 0..<4 {
                var l = FamilyLine(shape: .line(c[i], c[(i + 1) % 4]))
                l.visibleAt = [.coarse]
                f.planLines.append(l)
            }
        }
        guard let type = f.types.first?.name else { return }
        let ev = FamilyEvaluator.evaluate(f, typeName: type, units: .imperial)
        let shown = ev.solids.filter { !$0.isVoid && $0.visibleIn3D && !$0.visibleAt.isDisjoint(with: [.medium, .fine]) }
        let feet = shown.map { (poly: $0.profile.outer, top: $0.zMax) }
        func hidden(_ p: Vec2, under top: Double) -> Bool {
            feet.contains { $0.top > top + 0.001 && $0.poly.contains(p, onBoundary: true) }
        }
        func edgeHidden(_ a: Vec2, _ b: Vec2, under top: Double) -> Bool {
            [0.1, 0.5, 0.9].allSatisfy { hidden(a + (b - a) * $0, under: top) }
        }
        func num(_ b: FamilyBound) -> Double? {
            switch b {
            case .plane(let n): ev.planes[n]
            case .expr(let e): Double(e.trimmingCharacters(in: .whitespaces))
            }
        }
        // Edges already drawn (and the plan line drawing each): a part's cut and uncut solids share most edges.
        var drawn: [(seg: Segment2, line: Int)] = []
        func drawnLine(_ s: Segment2) -> Int? {
            drawn.first { ($0.seg.start.distance(to: s.start) < 1e-5 && $0.seg.end.distance(to: s.end) < 1e-5)
                || ($0.seg.start.distance(to: s.end) < 1e-5 && $0.seg.end.distance(to: s.start) < 1e-5) }?.line
        }
        let byID = Dictionary(f.solids.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for s in shown {
            guard let id = s.sourceID, let src = byID[id], let corners = footprint(src, num) else { continue }
            for i in corners.indices {
                let a = corners[i], b = corners[(i + 1) % corners.count]
                let seg = Segment2(a.at, b.at)
                let levels = s.visibleAt.intersection([.medium, .fine])
                guard seg.length > Tolerance.shortCurve, !edgeHidden(a.at, b.at, under: s.zMax) else { continue }
                if let k = drawnLine(seg) { f.planLines[k].visibleAt.formUnion(levels); continue }
                drawn.append((seg, f.planLines.count))
                var l = FamilyLine(shape: .line(a.point, b.point))
                l.visibleAt = levels
                f.planLines.append(l)
            }
        }
        // Nested shapes of a fixed size (legs, feet): their own footprint, when any of their instances shows.
        for i in f.nestedFamilies.indices {
            let nf = f.nestedFamilies[i]
            let instances = f.nestedInstances.filter { $0.familyName == nf.name }
            guard !instances.isEmpty, nf.planLines.isEmpty, FurnitureHardware.kinds[nf.name] == nil,
                  instances.allSatisfy({ Set($0.bindings.keys).isSubset(of: ["Height", "Material"]) }) else { continue }
            let mine = shown.filter { $0.name.hasPrefix(nf.name + ": ") }
            guard mine.contains(where: { s in !s.profile.outer.points.allSatisfy { hidden($0, under: s.zMax) } }) else { continue }
            let local = FamilyEvaluator.evaluate(nf, typeName: nf.types.first?.name ?? "", units: .imperial)
            for s in local.solids where !s.isVoid && s.visibleIn3D {
                let pts = s.profile.outer.points
                for k in pts.indices {
                    let a = pts[k], b = pts[(k + 1) % pts.count]
                    guard a.distance(to: b) > Tolerance.shortCurve else { continue }
                    var l = FamilyLine(shape: .line(FamilyPoint(PartSolidContext.number(a.x), PartSolidContext.number(a.y)),
                                                    FamilyPoint(PartSolidContext.number(b.x), PartSolidContext.number(b.y))))
                    l.visibleAt = [.medium, .fine]
                    f.nestedFamilies[i].planLines.append(l)
                }
            }
        }
    }

    /// A solid's plan footprint corners, each as a family point (bound like the solid) and its value for the current
    /// type; nil for forms that aren't box or polygon extrusions.
    static func footprint(_ s: FamilySolid, _ num: (FamilyBound) -> Double?) -> [(point: FamilyPoint, at: Vec2)]? {
        func corner(_ x: FamilyBound, _ y: FamilyBound) -> (point: FamilyPoint, at: Vec2)? {
            guard let vx = num(x), let vy = num(y) else { return nil }
            return (FamilyPoint(x, y), Vec2(vx, vy))
        }
        let rect: [(FamilyBound, FamilyBound)]
        switch (s.profile, s.workPlane ?? .xy) {
        case (.rectangle(let x0, let x1, let y0, let y1), .xy): rect = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        case (.rectangle(let u0, let u1, _, _), .xz): rect = [(u0, s.zMin), (u1, s.zMin), (u1, s.zMax), (u0, s.zMax)]
        case (.rectangle(let u0, let u1, _, _), .yz): rect = [(s.zMin, u0), (s.zMax, u0), (s.zMax, u1), (s.zMin, u1)]
        case (.polygon(let pts), .xy):
            let out = pts.compactMap { corner($0.x, $0.y) }
            return out.count == pts.count && out.count >= 3 ? out : nil
        default: return nil
        }
        let out = rect.compactMap { corner($0.0, $0.1) }
        return out.count == 4 ? out : nil
    }
}

// MARK: - Hinge sets

extension FurnitureCompiler {
    /// A compiled hinge instance: where it is in `f.nestedInstances`, its front and its slot ("hinge.<leaf>.<k>").
    struct HingeRecord {
        var index: Int; var front: ElementID; var slot: String
        /// FMG3: a Leaf Count variant's model and its yes/no parameter (nil: the document's, always shown).
        var model: BIMModel? = nil
        var visibility: String? = nil
    }

    /// Hinges per door height, as the document's rule places them (2 up to 40", 3 up to 60", 4 up to 80", then 5):
    /// each hinged leaf gets a "<Mark> Hinge Count" parameter calculated from its hinge edge, and a set of instances
    /// for each count, shown by a "<Mark> Hinges <n>" yes/no parameter, so a loaded door that flexes taller gains its
    /// hinges as it does in the Furniture document. A leaf whose hinge edge doesn't follow formula planes keeps the
    /// instances the document placed. FMG3: each concealed hinge bores its cup at Fine (so the machining follows the
    /// count), and "Hinges" totals the hinges of the type for schedules.
    static func expandHingeSets(_ records: [HingeRecord], _ m: BIMModel, to f: inout FamilyDefinition) {
        let stable = stablePlanes(f)
        var replace: [Int: [NestedFamilyInstance]] = [:]
        let groups = Dictionary(grouping: records) { r -> String in
            let parts = r.slot.split(separator: ".")
            return "\(r.front.raw)|\(r.visibility ?? "")|\(parts.count > 1 ? String(parts[1]) : "0")" // FMG3: per Leaf Count variant
        }
        var params: [FamilyParameter] = []
        var totals: [String: String] = [:] // FMG3: the hinge count of each group, as a formula
        for key in groups.keys.sorted() {
            if let group = groups[key], let first = group.first { // FMG3: groups kept as placed count as placed
                totals[key] = first.visibility.map { "if(\($0), \(group.count), 0)" } ?? "\(group.count)"
            }
            guard let group = groups[key]?.sorted(by: { $0.index < $1.index }), let first = group.first, case let m = first.model ?? m, let front = m[first.front],
                  let g = FurnitureFronts.geometry(front, m), let li = Int(key.split(separator: "|").last ?? ""), g.leaves.indices.contains(li),
                  let hinge = g.leaves[li].hinge, let ht = FurnitureFronts.hingeType(front, m), !FurnitureHardware.Values(m[ht]?.typeData).isPiano else { continue }
            let leaf = g.leaves[li]
            let vertical = hinge == .left || hinge == .right
            // FMG3: hinges along u on a turned face run along its model axis (the set is the same either way round).
            let fr = g.frame
            if !vertical, !fr.isSquare { continue }
            let along = vertical ? (axis: FamilyAxis.z, sign: 1.0) : (fr.uAxis ?? (.x, 1))
            var ends = vertical ? leaf.v : leaf.u
            ends = (ends.0.scaled(along.sign), ends.1.scaled(along.sign))
            if ends.0.value > ends.1.value { ends = (ends.1, ends.0) }
            guard let lo = stableExpression(ends.0, f, stable), let hi = stableExpression(ends.1, f, stable) else { continue }
            let inset = FurnitureFrontTypes.values(of: front, m).hingeInset
            let mark = first.visibility ?? (front.mark.isEmpty ? "Front \(front.id.raw)" : front.mark) // FMG3: "D1 Single", "D1 Pair"
            let label = g.leaves.count > 1 ? "\(mark) Leaf \(li + 1)" : mark
            let length = "((\(hi)) - (\(lo)))"
            let countName = "\(label) Hinge Count"
            totals[key] = first.visibility.map { "if(\($0), \(countName), 0)" } ?? countName // FMG3
            params.append(FamilyParameter(name: countName, type: .integer, group: .other,
                                          formula: "if(\(length) <= 40.001\", 2, if(\(length) <= 60.001\", 3, if(\(length) <= 80.001\", 4, 5)))"))
            let a = "(\(lo)) + min(\(PartSolidContext.number(inset)) m, \(length) / 4)", b = "(\(hi)) - min(\(PartSolidContext.number(inset)) m, \(length) / 4)"
            var set: [NestedFamilyInstance] = []
            for n in 2...5 {
                let shown = "\(label) Hinges \(n)"
                params.append(FamilyParameter(name: shown, type: .bool, group: .other,
                                              formula: first.visibility.map { "and(\($0), \(countName) = \(n))" } ?? "\(countName) = \(n)")) // FMG3
                for k in 0..<n {
                    var inst = f.nestedInstances[first.index]
                    inst.id = UUID().uuidString
                    let at: FamilyBound = .expr("(\(a)) + ((\(b)) - (\(a))) * \(k) / \(n - 1)")
                    switch along.axis { case .z: inst.z = at; case .y: inst.y = at; case .x: inst.x = at } // FMG3
                    inst.visibilityParameter = shown
                    set.append(inst)
                }
            }
            replace[first.index] = set
            for r in group.dropFirst() { replace[r.index] = [] }
        }
        if !totals.isEmpty, f.parameter(named: "Hinges") == nil { // FMG3: the piece's hinges for the current height, for schedules
            params.append(FamilyParameter(name: "Hinges", type: .integer, group: .other, formula: totals.keys.sorted().compactMap { totals[$0] }.joined(separator: " + ")))
        }
        for p in params where f.parameter(named: p.name) == nil { f.parameters.append(p) }
        guard !replace.isEmpty else { return }
        var out: [NestedFamilyInstance] = []
        for (i, inst) in f.nestedInstances.enumerated() { out += replace[i] ?? [inst] }
        f.nestedInstances = out
    }
}

// MARK: - Drawer depth

extension FurnitureCompiler {
    /// The stock slide length a drawer gets as a formula of its bay's depth, as the document picks it (the longest
    /// standard length that fits with its rear clearance), so a loaded cabinet made shallower or deeper gets the slides
    /// and drawer boxes that fit. FMG4: on any face square to the piece (back and side drawers too), `start` being the
    /// box front's model coordinate along `axis` and the box running toward `sign` along it. nil when the bay's depth
    /// doesn't follow formula planes.
    static func slideLengthFormula(_ front: Element, _ m: BIMModel, _ f: FamilyDefinition)
        -> (formula: String, start: String, axis: FamilyAxis, sign: Double)? {
        guard let g = FurnitureFronts.geometry(front, m), let depth = g.frame.vAxis, let box = FurnitureFronts.drawerBox(front, m), let st = box.slideTypeID else { return nil }
        let sv = FurnitureHardware.Values(m[st]?.typeData)
        let tv = FurnitureFrontTypes.values(of: front, m)
        let stable = stablePlanes(f)
        let start = tv.overlay == .inset ? g.opening.value("y0").shifted(tv.thickness) : g.opening.value("y0")
        // FMG4: a turned face's coordinates follow sums of planes (its local depth is ± a model axis).
        func local(_ v: PartValue) -> String? {
            guard PlaneTerms.isSum(v.plane), let n = v.plane else { return stableExpression(v, f, stable) }
            return PlaneTerms.expression(n, offset: v.offset) { stableExpression(PartValue(0, plane: $0), f, stable) }
        }
        guard let y0 = local(start), let y1 = local(g.opening.value("y1")) else { return nil }
        let available = "((\(y1)) - (\(y0)))"
        var formula = "\(PartSolidContext.number(box.depth)) m"
        for l in FurnitureHardware.slideLengths.sorted() {
            formula = "if(\(available) >= \(PartSolidContext.number(l * 0.0254 + sv.rearClearance)) m, \(PartSolidContext.number(l * 0.0254)) m, \(formula))"
        }
        return (formula, depth.sign > 0 ? y0 : "-(\(y0))", depth.axis, depth.sign)
    }

    /// Rewrites a drawer's box solids so their depth is `length` (a formula) from the box front at `start` (the model
    /// coordinate along `axis`), running toward `sign` (FMG4: back and side drawers run along -y and ±x).
    static func flexDrawerBox(_ solids: inout [FamilySolid], mark: String, length: String, start: String, back: Double, axis: FamilyAxis = .y, sign: Double = 1) {
        let b = PartSolidContext.number(back)
        let op = sign > 0 ? "+" : "-"
        func at(_ d: String) -> String { "(\(start)) \(op) (\(d))" }
        for i in solids.indices {
            guard solids[i].name.hasPrefix("\(mark) Box "), case .rectangle(let x0, let x1, let y0, let y1) = solids[i].profile else { continue }
            let r: (String, String)? = switch solids[i].name.dropFirst(mark.count + 5) {
            case "Left Side", "Right Side": (at("0 m"), at(length))
            case "Front": (at("0 m"), at("\(b) m"))
            case "Back": (at("(\(length)) - \(b) m"), at(length))
            case "Bottom": (at("\(b) m"), at("(\(length)) - \(b) m"))
            default: nil
            }
            guard let r else { continue }
            let lo = sign > 0 ? r.0 : r.1, hi = sign > 0 ? r.1 : r.0
            solids[i].profile = axis == .y ? .rectangle(xMin: x0, xMax: x1, yMin: .expr(lo), yMax: .expr(hi))
                                           : .rectangle(xMin: .expr(lo), xMax: .expr(hi), yMin: y0, yMax: y1)
        }
    }
}

// MARK: - Handles

extension FurnitureCompiler {
    /// Handles placed at a share of their leaf (a drawer pull centred on its front) rather than at a distance from a
    /// face: the share is kept as a formula of the leaf's edges, so they stay centred as a loaded piece flexes.
    static func anchorHandles(_ records: [HingeRecord], _ m: BIMModel, to f: inout FamilyDefinition) {
        let stable = stablePlanes(f)
        for r in records {
            let m = r.model ?? m // FMG3
            guard let front = m[r.front], let g = FurnitureFronts.geometry(front, m), let li = Int(r.slot.split(separator: ".").last ?? ""),
                  g.leaves.indices.contains(li), g.frame.isSquare, let p = FurnitureFronts.localHardware(front, m).first(where: { $0.slot == r.slot }) else { continue } // FMG3
            let leaf = g.leaves[li]
            let along = g.frame.uAxis ?? (.x, 1)
            func share(_ c: PartValue, _ ends: (PartValue, PartValue), sign: Double = 1) -> FamilyBound? {
                guard c.plane == nil, ends.1.value - ends.0.value > Tolerance.length,
                      let lo = stableExpression(ends.0.scaled(sign), f, stable), let hi = stableExpression(ends.1.scaled(sign), f, stable) else { return nil }
                let k = PartSolidContext.number((c.value - ends.0.value) / (ends.1.value - ends.0.value))
                return .expr("(\(lo)) + ((\(hi)) - (\(lo))) * \(k)")
            }
            if let x = share(p.at.x, leaf.u, sign: along.sign) { if along.axis == .y { f.nestedInstances[r.index].y = x } else { f.nestedInstances[r.index].x = x } }
            if g.face == .front { if let z = share(p.at.z, leaf.v) { f.nestedInstances[r.index].z = z } }
            else if let y = share(p.at.y, leaf.v) { f.nestedInstances[r.index].y = y }
        }
    }
}
