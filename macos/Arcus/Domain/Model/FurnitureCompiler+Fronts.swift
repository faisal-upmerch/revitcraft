import Foundation
import ArcusGeometry

// FM5: Load into Project for fronts and hardware. Each door, drawer and flap becomes family solids bounded by the
// planes its bay follows (shown at Medium and Fine, the drawer box at Fine only), so a loaded cabinet's fronts resize
// when it flexes; the EQ lines of a Bay Divide become planes chained by EQ dimensions between the bay's faces. Hardware
// instances become nested families placed on the same planes. Door swings are drawn as symbolic lines: arcs in plan
// and the dashed hinge triangles in the front elevation, as casework families draw them.

extension FurnitureCompiler {
    /// Adds the document's fronts and hardware to the compiled family `f` (after the parts).
    static func addFronts(_ source: BIMModel, to f: inout FamilyDefinition) {
        let m = withDividerPlanes(source)
        let fronts = m.elements(.furnitureFronts).sorted { $0.id < $1.id }
        let hardware = m.elements(.furnitureHardware).sorted { $0.id < $1.id }
        guard !fronts.isEmpty || !hardware.isEmpty else { return }
        var known = Set(f.referencePlanes.map(\.name))
        let ctx = PartSolidContext(symbolic: true, knownPlanes: known)

        // EQ Bay Divide lines: a plane per line whose formula keeps it at its share of the bay (low + (high - low) · k/n).
        var eqPlanes: [(name: String, axis: FamilyAxis, at: Double)] = []
        var eqFormulas: [String: String] = [:]
        for bay in m.elements(.furnitureBays).sorted(by: { $0.id < $1.id }) {
            guard let d = bay.furnitureBay, let div = d.division, div.layout == .equal, div.count > 1, let o = d.opening else { continue }
            let rows = div.direction == .rows
            let frame = BayFrame(d) // FMG3: columns on a turned face are planes along its u in the model; canted ones aren't planes
            if !rows, !frame.isSquare { continue }
            let (kLo, kHi) = rows ? (d.face == .front ? ("z0", "z1") : ("y0", "y1")) : ("x0", "x1")
            let axis: FamilyAxis = rows ? (d.face == .front ? .z : .y) : (frame.uAxis?.axis ?? .x)
            let sign = rows ? 1 : (frame.uAxis?.sign ?? 1)
            let lo = lengthExpression(o.value(kLo).scaled(sign), f), hi = lengthExpression(o.value(kHi).scaled(sign), f)
            let cells = FurnitureBays.cells(o, d.face, div, number: d.number, frame: frame)
            for k in 1..<cells.count {
                let name = FurnitureBays.lineName(d.number, k)
                eqPlanes.append((name, axis, sign * (rows ? (d.face == .front ? cells[k].z0 : cells[k].y0) : cells[k].x0)))
                eqFormulas[name] = "(\(lo)) + ((\(hi)) - (\(lo))) * \(k) / \(cells.count)"
            }
        }
        for p in eqPlanes { known.insert(p.name) }
        ctx.knownPlanes = known
        let planeOffsets = Dictionary(f.referencePlanes.map { ($0.name, $0.offset) }, uniquingKeysWith: { a, _ in a }).merging(eqFormulas) { a, _ in a }
        ctx.planeFormula = { planeOffsets[$0] } // FMG3: canted faces write their coordinates as formulas of these planes

        var materialParams: [String: String] = [:]
        func materialParameter(_ id: ElementID?, label: String) -> String? {
            guard let id, m[id]?.material != nil else { return nil }
            let key = "\(label)|\(id.raw)"
            if let p = materialParams[key] { return p }
            var name = label.replacingOccurrences(of: "\"", with: " in").trimmingCharacters(in: .whitespaces) + " Material"
            var k = 2
            while f.parameter(named: name) != nil { name = "\(label) Material \(k)"; k += 1 }
            f.parameters.append(FamilyParameter(name: name, type: .elementRef(.materials), group: .materials))
            for i in f.types.indices { f.types[i].values[name] = .ref(id) }
            materialParams[key] = name
            return name
        }

        var slideLengths: [ElementID: String] = [:] // FM8: drawers' stock slide length by bay depth
        for front in fronts {
            var ps = FurnitureFrontSolids.solids(front, m, ctx, boxDetail: [.fine], frontDetail: [.medium, .fine])
            let label = "\(front.furnitureFront?.kind.rawValue ?? "Front") \(m.type(of: front)?.name ?? "")"
            if let (length, start) = slideLengthFormula(front, m, f), let box = FurnitureFronts.drawerBox(front, m) { // FM8
                slideLengths[front.id] = length
                flexDrawerBox(&ps.solids, mark: front.mark.isEmpty ? (front.furnitureFront?.kind.rawValue ?? "Front") : front.mark, length: length, start: start, back: box.back)
            }
            for var s in ps.solids {
                s.visibleAt = s.visibleAt.intersection([.medium, .fine])
                guard !s.visibleAt.isEmpty else { continue }
                if !s.isVoid { s.materialParameter = materialParameter(ps.materials[s.id] ?? nil, label: label) }
                f.solids.append(s)
            }
            for p in ps.placed {
                var nf = p.family
                var name = nf.name
                var k = 2
                while f.nestedFamily(named: name) != nil { name = "\(nf.name) \(k)"; k += 1 }
                nf.name = name
                f.nestedFamilies.append(nf)
                var inst = NestedFamilyInstance(familyName: nf.name, typeName: nf.types.first?.name, x: ctx.bound(p.x), y: ctx.bound(p.y), z: ctx.bound(p.z),
                                                rotation: PartSolidContext.number(p.rotation), mirrored: p.mirrored)
                if let span = p.span, nf.parameter(named: "Length") != nil { inst.bindings["Length"] = "(\(lengthExpression(span.end, f))) - (\(lengthExpression(span.start, f)))" } // FM9: lengths on both sides
                inst.visibleAt = [.medium, .fine]
                f.nestedInstances.append(inst)
            }
            f.planLines += planSwings(front, m)
            addElevationSwings(front, m, to: &f) // FMG3: on every face
        }

        // Hardware: nested families, owned instances on the front's planes, the others where they are.
        var hinges: [HingeRecord] = [], handles: [HingeRecord] = [] // FM8: hinge sets by door height, centred handles (FurnitureCompiler+FM8)
        let placements: [String: HardwarePlacement] = Dictionary(fronts.flatMap { fr in FurnitureFronts.hardware(fr, m).map { ("\(fr.id.raw)|\($0.slot)", $0) } },
                                                                 uniquingKeysWith: { a, _ in a })
        // FMG3: hardware of fronts on canted faces stays between the face's corners (CantAnchors).
        var canted: [String: (FamilyBound, FamilyBound)] = [:]
        for fr in fronts {
            guard let g = FurnitureFronts.geometry(fr, m), let a = CantAnchors(g.opening, g.frame) else { continue }
            for p in FurnitureFronts.localHardware(fr, m) { canted["\(fr.id.raw)|\(p.slot)"] = a.point(p.at.x.value, p.at.y.value, ctx) }
        }
        for h in hardware {
            guard let c = h.component, let t = m[h.typeID], let td = t.typeData, let nested = m[td.familyID]?.family else { continue }
            if f.nestedFamily(named: nested.name) == nil {
                var copy = nested
                copy.furnitureSource = nil
                for i in copy.types.indices {
                    guard let pt = m.types(for: .furnitureHardware).first(where: { $0.typeData?.familyID == td.familyID && $0.name == copy.types[i].name })?.typeData else { continue }
                    for (k, v) in pt.params where k.key.hasPrefix(Parameters.familyParamID("").key) {
                        copy.types[i].values[String(k.key.dropFirst(Parameters.familyParamID("").key.count))] = v
                    }
                }
                f.nestedFamilies.append(copy)
            }
            var x: FamilyBound = .expr(PartSolidContext.number(c.location.x)), y: FamilyBound = .expr(PartSolidContext.number(c.location.y))
            var z: FamilyBound = .expr(PartSolidContext.number(m.baseElevation(of: h)))
            if let owner = h.params[FurnitureHardware.ownerParam]?.refValue, let slot = h.params[FurnitureHardware.slotParam]?.textValue,
               let p = placements["\(owner.raw)|\(slot)"] {
                x = ctx.bound(p.at.x); y = ctx.bound(p.at.y); z = ctx.bound(p.at.z)
                if let c = canted["\(owner.raw)|\(slot)"] { x = c.0; y = c.1 } // FMG3
            }
            var inst = NestedFamilyInstance(familyName: nested.name, typeName: t.name, x: x, y: y, z: z, rotation: PartSolidContext.number(c.rotation * 180 / .pi), mirrored: c.mirrored)
            for (k, v) in Parameters.familyInstanceValues(h) {
                guard let p = nested.parameter(named: k), p.isInstance else { continue }
                switch v {
                case .bool(let b): inst.bindings[k] = b ? "true" : "false"
                case .double(let d): inst.bindings[k] = "\(PartSolidContext.number(d)) m"
                default: break
                }
            }
            // A slide pair spans its opening: its width follows the bay's sides.
            if let owner = h.params[FurnitureHardware.ownerParam]?.refValue, let front = m[owner], let o = m[front.hostID]?.furnitureBay?.opening,
               nested.parameter(named: "Opening Width") != nil {
                inst.bindings["Opening Width"] = "(\(sumExpression(o.value("x1"), f, planeOffsets))) - (\(sumExpression(o.value("x0"), f, planeOffsets)))" // FM9: lengths on both sides; FMG3: any face
                if let length = slideLengths[owner], nested.parameter(named: "Slide Length") != nil { inst.bindings["Slide Length"] = length } // FM8
            }
            inst.visibleAt = [.medium, .fine]
            if let owner = h.params[FurnitureHardware.ownerParam]?.refValue, let slot = h.params[FurnitureHardware.slotParam]?.textValue { // FM8
                if slot.hasPrefix("hinge.") { hinges.append(HingeRecord(index: f.nestedInstances.count, front: owner, slot: slot)) }
                if slot.hasPrefix("handle.") { handles.append(HingeRecord(index: f.nestedInstances.count, front: owner, slot: slot)) }
            }
            f.nestedInstances.append(inst)
        }

        for p in eqPlanes where !f.referencePlanes.contains(where: { $0.name == p.name }) {
            f.referencePlanes.append(FamilyReferencePlane(name: p.name, axis: p.axis, offset: eqFormulas[p.name] ?? PartSolidContext.number(p.at), strength: .weak))
        }
        addHelperPlanes(ctx, eqPlanes: eqPlanes, m, to: &f)
        anchorHandles(handles, m, to: &f) // FM8 (before the hinge sets change the instance indices)
        expandHingeSets(hinges, m, to: &f) // FM8
    }

    /// A coordinate as a length expression of the family's parameters ("(Height) - 0.01905 m", or "0.12 m").
    static func lengthExpression(_ v: PartValue, _ f: FamilyDefinition) -> String {
        let e = expression(v, f)
        return Double(e.trimmingCharacters(in: .whitespaces)).map { "\(FurnitureFormLocks.num($0)) m" } ?? e // FM9: no exponents in formulas
    }

    /// The model with every bay face on an EQ divider bound to the divider's centre plane (the plane the compiled family
    /// keeps the divider on, see FurnitureCompiler+Parts), so fronts beside dividers flex with them.
    static func withDividerPlanes(_ m: BIMModel) -> BIMModel {
        let r = FurnitureBoundResolver(m)
        var centres: [ElementID: (name: String, at: Double, axis: FamilyAxis)] = [:]
        for e in m.elements(.furniturePanels) {
            guard let p = e.furniturePanel, let q = p.eq, q.count > 0, let lo = r.resolve(q.low), let hi = r.resolve(q.high),
                  let lf = FurniturePartSolids.linearFrame(p.plane, p.start, p.end) else { continue }
            centres[e.id] = ("\(e.mark.isEmpty ? "Divider \(e.id.raw)" : e.mark) Center", lo + (hi - lo) * Double(q.index) / Double(q.count), lf.crossAxis)
        }
        guard !centres.isEmpty else { return m }
        var out = m
        for bay in m.elements(.furnitureBays) {
            guard var d = bay.furnitureBay, var o = d.opening else { continue }
            let faces: [(String, ElementID?, Double, FamilyAxis)] = [("x0", o.left, o.x0, .x), ("outer0", o.left, o.outer0, .x), ("x1", o.right, o.x1, .x),
                                                                     ("outer1", o.right, o.outer1, .x), ("z0", o.bottom, o.z0, .z), ("outerLow", o.bottom, o.outerLow, .z),
                                                                     ("z1", o.top, o.z1, .z), ("outerHigh", o.top, o.outerHigh, .z)]
            var changed = false
            let frame = BayFrame(d)
            for (key, part, value, axis) in faces where o.bounds[key] == nil {
                guard let id = part, let c = centres[id], d.face == .front else { continue }
                // FMG3: on a turned face, u runs along the model axis `uAxis` (negated when it runs against it).
                let along: (axis: FamilyAxis, sign: Double)? = axis == .z ? (.z, 1) : frame.uAxis
                guard let along, c.axis == along.axis else { continue }
                let local = PartValue(along.sign * value, plane: c.name, offset: along.sign * value - c.at).scaled(along.sign)
                o.bounds[key] = local.plane.map { .plane($0, offset: local.offset) }
                changed = true
            }
            guard changed else { continue }
            d.opening = o
            var e = bay
            e.furnitureBay = d
            out.put(e)
        }
        return out
    }

    /// The helper planes the fronts' faces follow that the parts didn't already add: at a formula's offset, or kept at
    /// their distance by a labelled dimension.
    static func addHelperPlanes(_ ctx: PartSolidContext, eqPlanes: [(name: String, axis: FamilyAxis, at: Double)], _ m: BIMModel, to f: inout FamilyDefinition) {
        let axes = Dictionary(f.referencePlanes.map { ($0.name, $0.axis) }, uniquingKeysWith: { a, _ in a })
        let offsets = Dictionary(f.referencePlanes.map { ($0.name, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let origins = Set(f.referencePlanes.filter(\.definesOrigin).map(\.name))
        let constrained = Set(f.dimensions.flatMap { [$0.planeA, $0.planeB] + ($0.planeC.map { [$0] } ?? []) })
        let positions = FurnitureBoundResolver(m).positions
        var labelCount = 0
        for name in ctx.helpers.keys.sorted() where !f.referencePlanes.contains(where: { $0.name == name }) {
            guard let h = ctx.helpers[name], let axis = axes[h.plane] ?? eqPlanes.first(where: { $0.name == h.plane })?.axis else { continue }
            let eq = eqPlanes.first { $0.name == h.plane }
            let baseOffset = offsets[h.plane] ?? PartSolidContext.number(eq?.at ?? 0)
            let base = positions[h.plane] ?? eq?.at ?? Double(baseOffset.trimmingCharacters(in: .whitespaces)) ?? 0
            let isFormula = Double(baseOffset.trimmingCharacters(in: .whitespaces)) == nil
            let follows = isFormula || origins.contains(h.plane) || (!constrained.contains(h.plane) && eq == nil)
            if follows {
                let formula = isFormula ? "(\(baseOffset)) \(lengthTerm(h.offset))" : PartSolidContext.number(base + h.offset)
                f.referencePlanes.append(FamilyReferencePlane(name: name, axis: axis, offset: formula, strength: .notAReference))
            } else {
                labelCount += 1
                var param = "Front Offset \(labelCount)"
                while f.parameter(named: param) != nil { labelCount += 1; param = "Front Offset \(labelCount)" }
                f.parameters.append(FamilyParameter(name: param, type: .length, group: .dimensions, formula: "\(PartSolidContext.number(abs(h.offset))) m"))
                f.referencePlanes.append(FamilyReferencePlane(name: name, axis: axis, offset: PartSolidContext.number(base + h.offset), strength: .notAReference))
                var d = FamilyDimension(planeA: h.plane, planeB: name, labelParameter: param)
                d.direction = h.offset >= 0 ? 1 : -1
                f.dimensions.append(d)
            }
        }
    }

    /// Plan swings: an arc from each door leaf's open position round its hinge (doors seen from the front).
    static func planSwings(_ front: Element, _ m: BIMModel) -> [FamilyLine] {
        FurnitureSwings.plan(front, m).map { s in
            var l: FamilyLine
            switch s {
            case .line(let seg): l = FamilyLine(shape: .line(FamilyPoint(PartSolidContext.number(seg.start.x), PartSolidContext.number(seg.start.y)),
                                                             FamilyPoint(PartSolidContext.number(seg.end.x), PartSolidContext.number(seg.end.y))), subcategory: .swing)
            case .arc(let a): l = FamilyLine(shape: .arc(center: FamilyPoint(PartSolidContext.number(a.center.x), PartSolidContext.number(a.center.y)), radius: PartSolidContext.number(a.radius),
                                                         startDegrees: PartSolidContext.number(a.startAngle * 180 / .pi), sweepDegrees: PartSolidContext.number(a.sweep * 180 / .pi)), subcategory: .swing)
            }
            l.visibleAt = [.medium, .fine]
            return l
        }
    }

    /// Elevation swings: the dashed hinge triangles on the front face (model lines on the front's plane).
    static func elevationSwings(_ front: Element, _ m: BIMModel) -> [FamilyModelLine] {
        guard let g = FurnitureFronts.geometry(front, m), g.face == .front, g.frame.isIdentity else { return [] }
        return FurnitureSwings.elevation(front, m).map { seg in
            var l = FamilyModelLine(plane: .xz, offset: .expr(PartSolidContext.number(g.outerFace - 0.0005)),
                                    start: FamilyPoint(PartSolidContext.number(seg.start.x), PartSolidContext.number(seg.start.y)),
                                    end: FamilyPoint(PartSolidContext.number(seg.end.x), PartSolidContext.number(seg.end.y)))
            l.subcategory = .elevationSwing
            l.visibleAt = [.medium, .fine]
            return l
        }
    }
}

/// FM5: door and flap swing symbols, as casework drawings show them.
public enum FurnitureSwings {
    /// The plan swing of a front's door leaves: the leaf open at 90° and the arc its free edge sweeps (model x, y).
    public static func plan(_ front: Element, _ m: BIMModel) -> [Curve2] {
        guard front.furnitureFront?.kind == .door, let g = FurnitureFronts.geometry(front, m), g.face == .front else { return [] }
        var out: [Curve2] = []
        let y = g.outerFace
        for leaf in g.leaves {
            guard let h = leaf.hinge, h == .left || h == .right else { continue }
            let w = leaf.width
            let hinge = Vec2(h == .left ? leaf.u.0.value : leaf.u.1.value, y)
            let open = hinge + Vec2(0, -w)
            out.append(.line(Segment2(hinge, open)))
            // From the open leaf (pointing -Y) to the closed one (along ±X).
            let start: Double = h == .left ? -.pi / 2 : .pi
            out.append(.arc(Arc2(center: hinge, radius: w, startAngle: start, sweep: .pi / 2)))
        }
        return out.map(g.frame.worldCurve) // FMG3: turned with the bay's face
    }

    /// FMG3: the elevation swing as model segments on the front face (its leaves' face, a hair in front of it).
    public static func elevationLines(_ front: Element, _ m: BIMModel) -> [(Vec3, Vec3)] {
        guard let g = FurnitureFronts.geometry(front, m), g.face == .front else { return [] }
        let y = g.outerFace - 0.0005
        return elevation(front, m).map { (g.frame.world(Vec3($0.start.x, y, $0.start.y)), g.frame.world(Vec3($0.end.x, y, $0.end.y))) }
    }

    /// The elevation swing of each leaf (model x, z, on the front face): the two dashed lines from the far corners to
    /// the middle of the hinge edge, pointing at the hinges.
    public static func elevation(_ front: Element, _ m: BIMModel) -> [Segment2] {
        guard let f = front.furnitureFront, f.kind != .drawer, let g = FurnitureFronts.geometry(front, m), g.face == .front else { return [] }
        var out: [Segment2] = []
        for leaf in g.leaves {
            let r = leaf.rect
            switch leaf.hinge {
            case .left?:
                let apex = Vec2(r.min.x, r.center.y)
                out += [Segment2(Vec2(r.max.x, r.max.y), apex), Segment2(apex, Vec2(r.max.x, r.min.y))]
            case .right?:
                let apex = Vec2(r.max.x, r.center.y)
                out += [Segment2(Vec2(r.min.x, r.max.y), apex), Segment2(apex, Vec2(r.min.x, r.min.y))]
            case .top?:
                let apex = Vec2(r.center.x, r.max.y)
                out += [Segment2(Vec2(r.min.x, r.min.y), apex), Segment2(apex, Vec2(r.max.x, r.min.y))]
            case .bottom?:
                let apex = Vec2(r.center.x, r.min.y)
                out += [Segment2(Vec2(r.min.x, r.max.y), apex), Segment2(apex, Vec2(r.max.x, r.max.y))]
            default: break
            }
        }
        return out
    }
}
