import Foundation
import ArcusGeometry

// FM5: this batch's machining and derived parts (see FurnitureMachining.swift). Machining comes from each front's
// hardware: hinge cups bored in the back of doors and flaps (35 mm × 13 mm at the cup offset from the edge) and the
// hinge plate's screw holes in the carcass, the slides' screw holes in both sides, the stays' screws, and the handle
// holes drilled through the front. Derived parts are the front's own pieces (a slab, or the stiles, rails and panel of a
// framed front) and the drawer box (sides, front, back and bottom) sized from the bay and the slide clearances.

extension FurnitureMachining {
    static func fm5Machining(_ m: BIMModel) -> [MachiningEntry] {
        var out: [MachiningEntry] = []
        for front in m.elements(.furnitureFronts).sorted(by: { $0.id < $1.id }) {
            guard let g = FurnitureFronts.geometry(front, m) else { continue }
            let hardware = Dictionary(m.hosted(by: front.id).compactMap { h in h.params[FurnitureHardware.slotParam]?.textValue.map { ($0, h) } },
                                      uniquingKeysWith: { a, _ in a })
            var mine: [MachiningEntry] = []
            for p in FurnitureFronts.localHardware(front, m) { // FMG3: worked out in the bay's frame, turned at the end
                let hv = FurnitureHardware.Values(m[p.typeID]?.typeData)
                let src: MachiningSource = hardware[p.slot].map { .hardware($0.id) } ?? .front(front.id)
                switch hv.kind {
                case .hinge?: mine += hinge(p, hv, g, front, src)
                case .handle?: mine += handle(p, hv, g, front, src)
                case .slide?: mine += slides(p, hv, g, src)
                case .stay?: mine += stay(p, hv, g, src)
                default: break
                }
            }
            out += g.frame.isIdentity ? mine : mine.map { fmg3World($0, g.frame) }
        }
        return out
    }

    /// Unit vectors of the hinge frame (a into the opening, b along the edge, c behind the front) in model space.
    static func hingeAxes(_ p: HardwarePlacement) -> (a: Vec3, b: Vec3, c: Vec3) {
        let top = p.values["Top Edge"]?.boolValue == true, bottom = p.values["Bottom Edge"]?.boolValue == true, back = p.values["Back Edge"]?.boolValue == true
        if back { return (Vec3(0, -1, 0), Vec3(1, 0, 0), Vec3(0, 0, -1)) }
        if top { return (Vec3(0, 0, -1), Vec3(1, 0, 0), Vec3(0, 1, 0)) }
        if bottom { return (Vec3(0, 0, 1), Vec3(1, 0, 0), Vec3(0, 1, 0)) }
        return (Vec3(p.mirrored ? -1 : 1, 0, 0), Vec3(0, 0, 1), Vec3(0, 1, 0))
    }

    static func hinge(_ p: HardwarePlacement, _ hv: FurnitureHardware.Values, _ g: FrontGeometry, _ front: Element, _ src: MachiningSource) -> [MachiningEntry] {
        let ax = hingeAxes(p)
        var out: [MachiningEntry] = []
        let side = p.values["Side Offset"]?.doubleValue ?? 0, frontEdge = p.values["Front Edge"]?.doubleValue ?? 0
        if hv.isConcealed {
            // The cup in the front's back face, drilled toward the front face.
            let cup = p.origin + ax.a * hv.cupOffset
            out.append(MachiningEntry(partID: front.id, op: .drill(center: cup, axis: -ax.c, diameter: hv.cupDiameter, depth: hv.cupDepth), source: src,
                                      label: "Hinge cup \(Int((hv.cupDiameter * 1000).rounded())) mm"))
            // The plate's two screws in the carcass's inside face, at the setback from its front edge.
            if let part = p.carcassPartID {
                let face = p.origin + ax.a * side + ax.c * (frontEdge + hv.plateSetback)
                for s in [-0.5, 0.5] {
                    out.append(MachiningEntry(partID: part, op: .drill(center: face + ax.b * (s * hv.plateHoleSpacing), axis: -ax.a, diameter: hv.screwHoleDiameter, depth: hv.screwHoleDepth),
                                              source: src, label: "Hinge plate screw"))
                }
            }
        } else {
            // Butt and piano hinges: pilot holes in the front's edge.
            let n = hv.isPiano ? max(2, Int(((p.values["Length"]?.doubleValue ?? 0.6) / max(0.05, hv.d("Screw Spacing", 0.1))).rounded(.down)) + 1) : 2
            let len = hv.isPiano ? (p.values["Length"]?.doubleValue ?? 0.6) : hv.d("Leaf Height", 0.06) * 0.6
            for k in 0..<n {
                let t = n == 1 ? 0 : -len / 2 + len * Double(k) / Double(n - 1)
                out.append(MachiningEntry(partID: front.id, op: .drill(center: p.origin + ax.b * t - ax.c * (g.thickness / 2), axis: ax.a, diameter: hv.screwHoleDiameter, depth: hv.screwHoleDepth),
                                          source: src, label: "Hinge screw"))
            }
        }
        return out
    }

    static func handle(_ p: HardwarePlacement, _ hv: FurnitureHardware.Values, _ g: FrontGeometry, _ front: Element, _ src: MachiningSource) -> [MachiningEntry] {
        // Holes through the front, from its face.
        let into = g.face == .front ? Vec3(0, 1, 0) : Vec3(0, 0, -1)
        if hv.isEdgePull {
            let down = Vec3(0, 0, -1)
            return [-0.5, 0.5].map { s in
                MachiningEntry(partID: front.id, op: .drill(center: p.origin + Vec3(s * hv.handleHoleSpacing, 0, 0) + Vec3(0, g.thickness / 2, 0), axis: down,
                                                            diameter: hv.handleHoleDiameter, depth: 0.5 * 0.0254), source: src, label: "Edge pull screw")
            }
        }
        let vertical = p.values["Vertical"]?.boolValue == true
        let along = g.face == .top ? Vec3(1, 0, 0) : (vertical ? Vec3(0, 0, 1) : Vec3(1, 0, 0))
        let offsets = hv.handleHoleSpacing > 0 ? [-hv.handleHoleSpacing / 2, hv.handleHoleSpacing / 2] : [0]
        return offsets.map { o in
            MachiningEntry(partID: front.id, op: .drill(center: p.origin + along * o, axis: into, diameter: hv.handleHoleDiameter, depth: g.thickness), source: src,
                           label: "Handle hole \(LX.num((hv.handleHoleDiameter * 1000).rounded())) mm")
        }
    }

    static func slides(_ p: HardwarePlacement, _ hv: FurnitureHardware.Values, _ g: FrontGeometry, _ src: MachiningSource) -> [MachiningEntry] {
        let o = g.opening
        let z = o.z0 + (p.values["Mount Height"]?.doubleValue ?? 0)
        var out: [MachiningEntry] = []
        var y = hv.firstHole
        var holes: [Double] = []
        while y <= hv.slideLength - 0.01 + 1e-9 { holes.append(y); y += max(0.016, hv.holeSpacing) }
        // Undermount slides screw into the sides near their bottom edge; side-mount slides on the slide's centreline.
        let zHole = hv.isUndermount ? o.z0 + max(0.009, z - o.z0) : z
        for (part, x, axis) in [(o.left, o.x0, Vec3(-1, 0, 0)), (o.right, o.x1, Vec3(1, 0, 0))] {
            guard let part else { continue }
            for h in holes {
                out.append(MachiningEntry(partID: part, op: .drill(center: Vec3(x, p.origin.y + hv.d("Front Setback", 0) + h, zHole), axis: axis, diameter: hv.screwHoleDiameter,
                                                                   depth: hv.screwHoleDepth), source: src, label: "Slide screw"))
            }
        }
        return out
    }

    static func stay(_ p: HardwarePlacement, _ hv: FurnitureHardware.Values, _ g: FrontGeometry, _ src: MachiningSource) -> [MachiningEntry] {
        guard let part = p.carcassPartID else { return [] }
        let axis = Vec3(p.mirrored ? 1 : -1, 0, 0)
        let spacing = hv.d("Screw Spacing", 0.032), len = hv.d("Body Length", 0.15)
        let drop = hv.td?.params[Parameters.familyParamID("Drop Down")]?.boolValue == true
        let z = p.origin.z + (drop ? 0.006 : -0.02)
        return [0.03, 0.03 + spacing, min(len, 0.03 + 3 * spacing)].map { y in
            MachiningEntry(partID: part, op: .drill(center: Vec3(p.origin.x, p.origin.y + y, z), axis: axis, diameter: hv.screwHoleDiameter, depth: hv.screwHoleDepth),
                           source: src, label: "Flap stay screw")
        }
    }

    // MARK: Derived parts

    static func fm5DerivedParts(_ m: BIMModel) -> [DerivedPart] {
        var out: [DerivedPart] = []
        let inch = 0.0254
        for front in m.elements(.furnitureFronts).sorted(by: { $0.id < $1.id }) {
            guard let g = FurnitureFronts.geometry(front, m) else { continue }
            let tv = FurnitureFrontTypes.values(of: front, m)
            let key = "\(front.id.raw)"
            let label = front.mark.isEmpty ? g.kind.rawValue : front.mark
            let style = FurnitureFrontSolids.lidStyle(tv.style, g.face) // FMG3
            for (li, leaf) in g.leaves.enumerated() {
                let lk = g.leaves.count > 1 ? "\(key)/leaf\(li + 1)" : key
                let ln = g.leaves.count > 1 ? "\(label) Leaf \(li + 1)" : label
                let framed = style != .slab && leaf.width >= 3 * tv.stileWidth && leaf.height >= 3 * tv.railWidth
                if !framed {
                    out.append(DerivedPart(key: "\(lk)/front", sourceID: front.id, name: "\(ln) \(g.kind.rawValue) Front", materialID: tv.material,
                                           length: max(leaf.width, leaf.height), width: min(leaf.width, leaf.height), thickness: tv.thickness,
                                           grain: tv.grain, banding: tv.banding))
                    continue
                }
                let tenon = FurnitureFrontSolids.grooveDepth
                out.append(DerivedPart(key: "\(lk)/stile", sourceID: front.id, name: "\(ln) Stile", materialID: tv.material, length: leaf.height, width: tv.stileWidth,
                                       thickness: tv.thickness, grain: .length, quantity: 2))
                out.append(DerivedPart(key: "\(lk)/rail", sourceID: front.id, name: "\(ln) Rail", materialID: tv.material, length: leaf.width - 2 * tv.stileWidth + 2 * tenon,
                                       width: tv.railWidth, thickness: tv.thickness, grain: .length, quantity: 2))
                let pw = leaf.width - 2 * tv.stileWidth + 2 * tenon - 0.125 * inch, ph = leaf.height - 2 * tv.railWidth + 2 * tenon - 0.125 * inch
                switch style {
                case .louvered:
                    let h = leaf.height - 2 * tv.railWidth
                    let n = max(1, Int((h / tv.louverPitch).rounded(.down)))
                    out.append(DerivedPart(key: "\(lk)/louver", sourceID: front.id, name: "\(ln) Louver", materialID: tv.material, length: leaf.width - 2 * tv.stileWidth + 2 * 0.25 * inch,
                                           width: min(tv.thickness, h / Double(n)) * 1.1, thickness: 0.125 * inch * 2, grain: .length, quantity: n))
                default:
                    out.append(DerivedPart(key: "\(lk)/panel", sourceID: front.id, name: "\(ln) \(style == .glass ? "Glass" : "Panel")", materialID: tv.panelMaterial,
                                           length: max(pw, ph), width: min(pw, ph), thickness: tv.panelThickness, grain: style == .glass ? .none : .length))
                }
            }
            // The drawer box.
            guard g.kind == .drawer, let b = FurnitureFronts.drawerBox(front, m) else { continue }
            let between = b.width - 2 * b.side
            let frontBack = tv.boxJoint == .dovetail || tv.boxJoint == .boxJoint ? b.width - 2 * b.side + 2 * (b.side * 0.75) : between
            let groove = 0.25 * inch
            out.append(DerivedPart(key: "\(key)/box-side", sourceID: front.id, name: "\(label) Box Side", materialID: tv.boxMaterial, length: b.depth, width: b.height,
                                   thickness: b.side, grain: .length, quantity: 2))
            out.append(DerivedPart(key: "\(key)/box-front", sourceID: front.id, name: "\(label) Box Front", materialID: tv.boxMaterial, length: frontBack, width: b.height,
                                   thickness: b.back, grain: .length))
            out.append(DerivedPart(key: "\(key)/box-back", sourceID: front.id, name: "\(label) Box Back", materialID: tv.boxMaterial, length: frontBack, width: b.height,
                                   thickness: b.back, grain: .length))
            out.append(DerivedPart(key: "\(key)/box-bottom", sourceID: front.id, name: "\(label) Box Bottom", materialID: tv.bottomMaterial ?? tv.boxMaterial,
                                   length: b.depth - 2 * b.back + 2 * groove, width: between + 2 * groove, thickness: b.bottom, grain: .length))
        }
        return out
    }
}

extension FurnitureMachining {
    /// FMG3: a machining operation worked out in a bay's frame, in the model.
    static func fmg3World(_ e: MachiningEntry, _ f: BayFrame) -> MachiningEntry {
        var out = e
        switch e.op {
        case .drill(let c, let a, let d, let depth): out.op = .drill(center: f.world(c), axis: f.world(a), diameter: d, depth: depth)
        case .groove(let s, let t, let a, let w, let depth): out.op = .groove(start: f.world(s), end: f.world(t), axis: f.world(a), width: w, depth: depth)
        case .pocket(let o, let a, let depth): out.op = .pocket(outline: o.map(f.world), axis: f.world(a), depth: depth)
        }
        return out
    }
}
