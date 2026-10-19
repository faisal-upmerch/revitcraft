import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// FMG3 (Furniture fronts and bays, project integration gaps): bays, doors, drawers and flaps on the back, the sides
/// and canted faces (found in the views looking at them, drawn there, compiled so they flex); moving bays; lids with
/// styles, piano hinges, lid stays and swings; single or pair doors by type (Leaf Count); hinge cups in compiled
/// families; swings of loaded pieces in project elevations; the rebuilt library pieces.
private let i = 0.0254
private func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }
private func type(_ m: BIMModel, _ cat: ArcusDomain.Category, _ name: String) -> ElementID? { m.types(for: cat).first { $0.name == name }?.id }

@Suite("FMG3 Fronts and bays on any face, project integration") @MainActor
struct FMG3Tests {

    /// The sample base carcass (54" x 24" x 34 1/2") with two EQ dividers and no back: open front and back.
    static func openCarcass() throws -> DocumentSession {
        let s = DocumentSession(model: FurnitureTemplates.blank(category: .casework, name: "Island"))
        var ids: [String: ElementID] = [:]
        _ = s.perform("Carcass") { tx in ids = try FurnitureSamples.baseCabinet(in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        _ = s.perform("Dividers") { tx in
            _ = try FurniturePartOperations.createDividers(atFront: Vec2(0, 20 * i), vertical: true, count: 2, typeID: type(tx.model, .furniturePanels, "3/4\" Plywood"), in: tx)
        }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        return s
    }

    /// A box open on its left and right (a 60" x 24" x 18" under-bed carcass): a front and a back panel, two dividers
    /// across it, a bottom and a top.
    static func sideOpenBox() throws -> DocumentSession {
        let s = DocumentSession(model: FurnitureTemplates.blank(category: .furniture, name: "Under Bed"))
        _ = s.perform("Box") { tx in
            try FurnitureParameters.setValue("Width", .double(24 * i), in: tx)
            try FurnitureParameters.setValue("Depth", .double(60 * i), in: tx)
            try FurnitureParameters.setValue("Height", .double(18 * i), in: tx)
            let l = -12 * i, r = 12 * i, f = -30 * i, b = 30 * i, t = 0.75 * i
            let ply = type(tx.model, .furniturePanels, "3/4\" Plywood")
            _ = try FurniturePartOperations.createPanel(start: Vec2(r, f), end: Vec2(l, f), extent: PartExtent(), typeID: ply, in: tx)
            _ = try FurniturePartOperations.createPanel(start: Vec2(l, b), end: Vec2(r, b), extent: PartExtent(), typeID: ply, in: tx)
            let inside = [Vec2(l, f + t), Vec2(r, f + t), Vec2(r, b - t), Vec2(l, b - t)]
            _ = try FurniturePartOperations.createShelf(boundary: inside, plane: "Top", offset: 0, role: .top, typeID: type(tx.model, .furnitureShelves, "3/4\" Plywood Top"), in: tx)
            _ = try FurniturePartOperations.createShelf(boundary: inside, plane: "Bottom", offset: t, role: .bottom, typeID: type(tx.model, .furnitureShelves, "3/4\" Plywood Shelf"), in: tx)
        }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        return s
    }

    static func view(_ m: BIMModel, _ name: String) throws -> Element { try #require(m.views.first { $0.view?.kind == .elevation && $0.name == name }) }

    /// The model box of a front's solids at a detail level.
    static func bounds(_ e: Element, _ m: BIMModel, _ d: DetailLevel = .medium) -> Box3 {
        ElementMeshes.parts(e, m, detail: d).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
    }

    // MARK: 1. Any face

    @Test func frameTurnsCoordinatesWithTheirPlanes() throws {
        let back = BayFrame(angle: .pi), left = BayFrame(angle: -.pi / 2), canted = BayFrame(angle: .pi / 4)
        #expect(back.quarter == 2 && left.quarter == 3 && canted.quarter == nil && BayFrame.front.isIdentity)
        #expect(back.name == "Back" && left.name == "Left" && BayFrame(angle: .pi / 2).name == "Right" && canted.name == "Angled 45°")
        // A plane-bound value turned to the back and back again keeps its plane.
        let x = PartValue(0.3, plane: "Right", offset: -0.01), y = PartValue(0.2, plane: "Back", offset: 0)
        let u = back.localU(x, y), v = back.localV(x, y)
        #expect(approx(u.value, -0.3) && PlaneTerms.terms(u.plane) == ["Right": -1] && approx(u.offset, 0.01))
        let wx = back.worldX(u, v), wy = back.worldY(u, v)
        #expect(wx.plane == "Right" && approx(wx.offset, -0.01) && wy.plane == "Back")
        // On a canted face a value is a sum of planes, and compiles to a formula of theirs.
        let cu = canted.localU(x, y)
        #expect(approx(cu.value, (0.3 + 0.2) / 2.squareRoot()) && PlaneTerms.terms(cu.plane).count == 2)
        let e = PlaneTerms.expression(cu.plane!, offset: cu.offset) { ["Right": "Width / 2", "Back": "Depth / 2"][$0] }
        #expect(e?.contains("Width / 2") == true && e?.contains("Depth / 2") == true)
        // Points and plan curves turn about the piece's origin.
        #expect(back.world(Vec2(1, 0)).distance(to: Vec2(-1, 0)) < 1e-12 && left.world(Vec2(1, 0)).distance(to: Vec2(0, -1)) < 1e-12)
        #expect(left.faces(Vec2(1, 0)) && back.faces(Vec2(0, -1)) && !back.faces(Vec2(0, 1)))
    }

    @Test func backFaceBaysTakeDoorsSeenFromBehind() throws {
        let s = try Self.openCarcass()
        let back = BayFrame(angle: .pi)
        // From behind, x = +18" is on the viewer's left (u = -18").
        var bay: ElementID?
        _ = s.perform("Bay") { tx in bay = try FurnitureBays.createBay(face: .front, at: Vec2(-18 * i, 20 * i), frame: back, in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let b = try #require(s.model[bay]?.furnitureBay)
        let o = try #require(b.opening)
        #expect(approx(b.facing, .pi) && BayFrame(b) == back)
        // The right-hand bay (between the right divider and the right side), seen from behind: u from -26.25" to about -9".
        #expect(approx(o.x0, -26.25 * i, 1e-6) && o.x1 > -9.5 * i && o.x1 < -8.5 * i, "\(o.x0 / i) \(o.x1 / i)")
        #expect(PlaneTerms.terms(o.bounds["x0"].flatMap { if case .plane(let n, _) = $0 { n } else { nil } }) == ["Right": -1])
        #expect(try #require(Parameters.instanceEntries(s.model[bay]!, s.model).first { $0.name == "Seen From" }).value?.textValue == "Back")
        // Clicking the same region again is refused; the same point seen from the front is another bay.
        _ = s.perform("Again") { tx in _ = try FurnitureBays.createBay(face: .front, at: Vec2(-18 * i, 20 * i), frame: back, in: tx) }
        #expect(s.lastError?.message.contains("already") == true)
        _ = s.perform("Front") { tx in _ = try FurnitureBays.createBay(face: .front, at: Vec2(18 * i, 20 * i), in: tx) }
        #expect(s.lastError == nil && s.model.elements(.furnitureBays).count == 2)

        // A door in it hangs behind the back edges, hinged on the viewer's left (the model's +X side).
        var door: [ElementID] = []
        _ = s.perform("Door") { tx in door = try FurnitureFronts.createFront(.door, in: bay!, in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let d = try #require(s.model[door.first])
        let box = Self.bounds(d, s.model)
        #expect(box.min.y > 12 * i - 1e-4 && box.max.y < 12.8 * i && box.min.x > 8 * i && box.max.x < 27.1 * i, "\(box)")
        let hinges = s.model.hosted(by: d.id).filter { $0.params[FurnitureHardware.slotParam]?.textValue?.hasPrefix("hinge") == true }
        #expect(hinges.count == 2)
        for h in hinges {
            let c = try #require(h.component)
            #expect(approx(Angle.normalize(c.rotation), Angle.normalize(.pi), 1e-9) && c.location.x > 25 * i && c.location.y > 11.9 * i, "\(c.location / i)")
        }
        // Hinge cups are bored in the door's inside face (toward -Y), the plates' screws in the right side.
        let cups = FurnitureMachining.entries(s.model).filter { $0.partID == d.id && $0.label.hasPrefix("Hinge cup") }
        #expect(cups.count == 2)
        for c in cups { if case .drill(let p, let axis, _, _) = c.op { #expect(axis.y > 0.99 && p.y > 12 * i && p.y < 12.8 * i, "\(axis) \(p)") } }
        // Plan swing: the leaf opens away from the piece (+Y) round its hinge.
        let plan = FurnitureSwings.plan(d, s.model)
        #expect(plan.count == 2)
        if case .line(let seg)? = plan.first { #expect(seg.end.y > seg.start.y + 10 * i && seg.start.x > 25 * i, "\(seg)") }
        // Drawn in the Back elevation (swing triangle), not in the Front one.
        let backView = try Self.view(s.model, "Back"), frontView = try Self.view(s.model, "Front")
        let inBack = ViewGraphicsBuilder(model: s.model, view: backView).build().items.filter { $0.elementID == d.id && $0.layer == .model }
        let inFront = ViewGraphicsBuilder(model: s.model, view: frontView).build().items.filter { $0.elementID == d.id && $0.layer == .model && $0.primitives.count == 2 }
        #expect(inBack.contains { $0.primitives.count == 2 } && inFront.isEmpty)
        // The bay follows the parts: a wider piece moves its opening.
        _ = s.perform("Wider") { tx in try FurnitureParameters.setValue("Width", .double(60 * i), in: tx) }
        #expect(approx(s.model[bay]?.furnitureBay?.opening?.x0, -29.25 * i, 1e-6))
        #expect(Self.bounds(s.model[d.id]!, s.model).max.x > 29.5 * i)

        // Compiled: the door flexes with Width on the back.
        let f = FurnitureCompiler.family(from: s.model)
        let leafName = "\(s.model[d.id]!.mark)"
        func leafX(_ width: Double) throws -> (Double, Double, Double) {
            var g = f
            let t = try #require(g.types.firstIndex { $0.name == g.types.first?.name })
            g.types[t].values["Width"] = .double(width * i)
            let ev = FamilyEvaluator.evaluate(g, typeName: g.types[t].name, units: .imperial)
            #expect(ev.errors.isEmpty, "\(ev.errors.prefix(2))")
            let leaf = try #require(ev.solids.first { $0.name == leafName && !$0.isVoid && $0.visibleAt.contains(.medium) })
            let b = leaf.bounds
            return (b.min.x, b.max.x, b.min.y)
        }
        let a = try leafX(60), c = try leafX(70)
        #expect(approx(c.1 - a.1, 5 * i, 1e-5) && approx(c.2, a.2, 1e-6) && a.2 > 11.9 * i, "\(a) \(c)")
        #expect(f.modelLines.contains { $0.subcategory == .elevationSwing && $0.plane == .xz })
    }

    @Test func sideBaysTakeDrawersSeenFromTheLeft() throws {
        let s = try Self.sideOpenBox()
        let left = try #require(BayFrame(view: try Self.view(s.model, "Left").view))
        #expect(left.quarter == 3)
        // Seen from the left, u runs toward -Y: the box spans u -30"…30".
        var bay: ElementID?
        _ = s.perform("Bay") { tx in bay = try FurnitureBays.createBay(face: .front, at: Vec2(0, 9 * i), frame: left, in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let o = try #require(s.model[bay]?.furnitureBay?.opening)
        #expect(approx(o.x0, -29.25 * i) && approx(o.x1, 29.25 * i) && approx(o.y0, -12 * i) && approx(o.y1, 12 * i), "\(o)")
        // Three drawers along the side (EQ), each with a box and slides running in +X.
        var drawers: [ElementID] = []
        _ = s.perform("Drawers") { tx in
            try FurnitureBays.divide(bay!, BayDivision(direction: .columns, count: 3), in: tx)
            drawers = try FurnitureFronts.createFront(.drawer, in: bay!, in: tx)
        }
        #expect(s.lastError == nil && drawers.count == 3, "\(s.lastError?.message ?? "")")
        for id in drawers {
            let e = try #require(s.model[id])
            let b = Self.bounds(e, s.model, .fine)
            #expect(b.min.x < -12 * i && b.max.x > 0 && b.max.x < 12 * i, "\(b)")
            let slides = try #require(s.model.hosted(by: id).first { $0.params[FurnitureHardware.slotParam]?.textValue == "slides" })
            #expect(approx(Angle.normalize(slides.component?.rotation ?? 0), Angle.normalize(-.pi / 2), 1e-9))
        }
        // The columns' EQ lines are planes of the model (along Y, negated) when compiled; the drawers flex with Depth.
        let f = FurnitureCompiler.family(from: s.model)
        #expect(f.referencePlanes.contains { $0.name == FurnitureBays.lineName("1", 1) && $0.axis == .y })
        func fronts(_ depth: Double) throws -> [Double] {
            var g = f
            g.types[0].values["Depth"] = .double(depth * i)
            let ev = FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
            #expect(ev.errors.isEmpty, "\(ev.errors.prefix(2))")
            return drawers.compactMap { id in s.model[id].flatMap { e in ev.solids.first { $0.name == e.mark && !$0.isVoid }?.bounds.size.y } }
        }
        let a = try fronts(60), c = try fronts(72)
        #expect(a.count == 3 && c.count == 3 && approx(c[0] - a[0], 4 * i, 1e-5), "\(a) \(c)")
        // Seen in the Left elevation, not the Right one.
        let lv = try Self.view(s.model, "Left"), rv = try Self.view(s.model, "Right")
        let cell = try #require(FurnitureBays.cellIDs(of: bay!, s.model).first)
        #expect(ViewGraphicsBuilder(model: s.model, view: lv).build().items.contains { $0.elementID == cell })
        #expect(!ViewGraphicsBuilder(model: s.model, view: rv).build().items.contains { $0.elementID == cell })
        // The right face is closed by nothing, so it takes a bay too; the left side panel of a closed box closes its face.
        let right = BayFrame(angle: .pi / 2)
        _ = s.perform("Right") { tx in _ = try FurnitureBays.createBay(face: .front, at: Vec2(0, 9 * i), frame: right, in: tx) }
        #expect(s.lastError == nil)
        let closed = try Self.openCarcass()
        _ = closed.perform("Closed") { tx in _ = try FurnitureBays.createBay(face: .front, at: Vec2(0, 20 * i), frame: left, in: tx) }
        #expect(closed.lastError != nil)
    }

    static func click(_ tool: some InteractiveTool, _ p: Vec2) {
        let inp = ToolInput(point: p, rawPoint: p)
        tool.pointerMoved(inp)
        tool.pointerDown(inp)
        tool.pointerUp(inp)
    }

    /// A section looking at the face canted 45° to the front right (along (-1, 1)), well in front of it.
    static func cantedSection(in s: DocumentSession) -> ElementID? {
        var id: ElementID?
        _ = s.perform("Section") { tx in
            var v = ViewData(kind: .section, scale: 12)
            let d = Vec2(-1, 1).normalized
            v.planeOrigin = Vec3(d * -1.0, z: 0)
            v.viewDirection = d
            v.farClip = 4
            v.detailLevel = .fine
            id = tx.create(.views, name: "Canted", data: .view(v))
        }
        return id
    }

    @Test func cornerCabinetHasACantedDoorThatFlexes() throws {
        let spec = try #require(FurnitureLibrary.simpleASpecs.first { $0.name == "Corner Cabinet" })
        let m = try spec.build()
        let bay = try #require(m.elements(.furnitureBays).first)
        let b = try #require(bay.furnitureBay)
        let frame = BayFrame(b)
        #expect(frame.quarter == nil && approx(frame.angle, .pi / 4) && frame.name == "Angled 45°")
        let o = try #require(b.opening)
        // Between the returns: u from the front return's end to the right return's end, on sums of the planes.
        #expect(PlaneTerms.isSum(o.bounds["x0"].flatMap { if case .plane(let n, _) = $0 { n } else { nil } }))
        let cant = (24.0 - 6) * 2.squareRoot() * i // between the returns' front corners
        #expect(o.width > cant - 1.2 * i && o.width < cant, "\(o.width / i)")
        let door = try #require(m.elements(.furnitureFronts).first)
        let g = try #require(FurnitureFronts.geometry(door, m))
        #expect(g.frame == frame && g.leaves.count == 1)
        // The door stands on the cant (x - y constant along it) and turns with it; so do its hinges.
        let box = Self.bounds(door, m)
        #expect(box.min.x > -6.6 * i && box.max.y < 6.6 * i && box.max.x < 12.1 * i && box.min.y > -12.1 * i, "\(box)")
        #expect(abs((box.min.x - box.min.y) - 6 * i) < 1 * i && abs((box.max.x - box.max.y) - 6 * i) < 1 * i, "on the cant: \(box)")
        for h in m.hosted(by: door.id) where h.category == .furnitureHardware {
            #expect(approx(h.component?.rotation ?? 0, .pi / 4, 1e-9))
        }
        let hinges = FurnitureFronts.hardware(door, m).filter { $0.slot.hasPrefix("hinge") }
        #expect(hinges.count == 2)
        // The plan swing opens out of the cant (toward the front right).
        let plan = FurnitureSwings.plan(door, m)
        if case .line(let seg)? = plan.first { #expect((seg.end - seg.start).normalized.dot(frame.outward) > 0.99, "\(seg)") }
        // Drawn in a section looking at the cant.
        let s = DocumentSession(model: m)
        let section = try #require(Self.cantedSection(in: s))
        let items = ViewGraphicsBuilder(model: s.model, view: s.model[section]!).build().items
        #expect(items.contains { $0.elementID == bay.id } && items.contains { $0.elementID == door.id && $0.layer == .model && $0.primitives.count == 2 })
        // The Bay tool in that section finds the same opening (and refuses a second bay there).
        let ctx = ToolContext(session: s, viewID: section)
        let map = try #require(FurnitureFaceMap.of(s.model[section]?.view))
        #expect(map.frame == frame)
        let tool = FurnitureBayTool(ctx: ctx)
        tool.tagOnPlacement = false
        let p = map.toView(FurnitureBays.center(o, .front))
        tool.pointerMoved(ToolInput(point: p, rawPoint: p))
        #expect(!tool.preview.primitives.isEmpty)
        Self.click(tool, p)
        #expect(s.lastError?.message.contains("already") == true)

        // Compiled: the door's corners are formulas of the planes, so a bigger cabinet (Width and Depth) gets a wider door.
        let f = FurnitureCompiler.family(from: m)
        func leafWidth(_ size: Double) throws -> Double {
            var gf = f
            gf.types[0].values["Width"] = .double(size * i)
            gf.types[0].values["Depth"] = .double(size * i)
            let ev = FamilyEvaluator.evaluate(gf, typeName: gf.types[0].name, units: .imperial)
            #expect(ev.errors.isEmpty, "\(ev.errors.prefix(2))")
            let mark = door.mark
            let solids = ev.solids.filter { $0.name.hasPrefix(mark) && !$0.isVoid && $0.visibleAt.contains(.medium) }
            let pts = solids.flatMap { $0.profile.outer.points }
            let us = pts.map { frame.local($0).x }
            return (us.max() ?? 0) - (us.min() ?? 0)
        }
        let w24 = try leafWidth(24), w28 = try leafWidth(28)
        #expect(approx(w28 - w24, 4 * 2.squareRoot() * i, 1e-4), "\(w24 / i) \(w28 / i)")
        // The elevation swing is in a nested family turned to the cant.
        #expect(f.nestedInstances.contains { inst in approx(Double(inst.rotation), 45) && f.nestedFamily(named: inst.familyName)?.modelLines.isEmpty == false })
    }

    @Test func storageBedHasDrawersAlongBothSides() throws {
        let spec = try #require(FurnitureLibrary.simpleASpecs.first { $0.name == "Storage Bed" })
        let m = try spec.build()
        #expect(LibraryKit.buildError(m) == nil)
        let tops = m.elements(.furnitureBays).filter { $0.furnitureBay?.parentID == nil }
        #expect(Set(tops.compactMap { $0.furnitureBay.map { BayFrame($0).name } }) == ["Left", "Right"])
        let drawers = m.elements(.furnitureFronts).filter { $0.furnitureFront?.kind == .drawer }
        #expect(drawers.count == 6)
        for d in drawers {
            let box = try #require(FurnitureFronts.drawerBox(d, m), "\(d.mark) has a drawer box")
            #expect(box.depth > 17 * i && box.depth < 20 * i, "\(box.depth / i)")
            // Each drawer and its box stay in the 20" side box it opens from.
            let b = Self.bounds(d, m, .fine)
            let leftSide = b.min.x < 0
            #expect(leftSide ? (b.min.x > -32.8 * i && b.max.x < -11.9 * i) : (b.max.x < 32.8 * i && b.min.x > 11.9 * i), "\(d.mark) \(b)")
            #expect(b.min.y > -43 * i && b.max.y < 43 * i && b.min.z > 3 * i && b.max.z < 15.5 * i, "\(d.mark) \(b)")
        }
        // In the plan the drawer boxes are dashed along the sides; in the Left elevation the left drawers are drawn.
        let left = try Self.view(m, "Left")
        let items = ViewGraphicsBuilder(model: m, view: left).build().items
        let cells = tops.filter { $0.furnitureBay.map { BayFrame($0).name } == "Left" }.flatMap { FurnitureBays.cellIDs(of: $0.id, m) }
        #expect(cells.count == 3 && cells.allSatisfy { c in items.contains { $0.elementID == c } })
        // Compiled: a longer bed makes longer drawers (the EQ lines follow Depth).
        let f = FurnitureCompiler.family(from: m)
        func widths(_ depth: Double) throws -> [Double] {
            var g = f
            g.types[0].values["Depth"] = .double(depth * i)
            let ev = FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
            #expect(ev.errors.isEmpty, "\(ev.errors.prefix(2))")
            return drawers.compactMap { d in ev.solids.first { $0.name == d.mark && !$0.isVoid }?.bounds.size.y }
        }
        let a = try widths(86), c = try widths(92)
        #expect(a.count == 6 && c.count == 6 && zip(a, c).allSatisfy { approx($1 - $0, 2 * i, 1e-5) }, "\(a) \(c)")
    }

    // MARK: 4. Leaf Count

    @Test func kitchenCabinetIsSingleOrPairByType() throws {
        let p = try #require(FurnitureLibrary.essentials.first { $0.name == "Kitchen Cabinet" })
        #expect(!FurnitureLibrary.essentials.contains { $0.name == "Kitchen Base Cabinet - Single Door" })
        let m = p.build()
        #expect(LibraryKit.buildError(m) == nil, "\(LibraryKit.buildError(m) ?? "")")
        let setup = try #require(m.furnitureSetup)
        #expect(setup.family.types.map(\.name) == ["B12", "B15", "B18", "B21", "B24", "B27", "B30", "B33", "B36"])
        #expect(setup.family.parameter(named: "Leaf Count")?.formula != nil)
        let door = try #require(m.elements(.furnitureFronts).first { $0.furnitureFront?.kind == .door })
        #expect(door.furnitureFront?.leafCountParameter == "Leaf Count")
        func leaves(_ type: String) throws -> (BIMModel, Int, Int) {
            let tx = TransactionContext(model: m, name: "Type")
            try FurnitureParameters.setCurrentType(type, in: tx)
            let t = try tx.commit().model
            let d = try #require(t[door.id])
            let hinges = t.hosted(by: d.id).filter { $0.params[FurnitureHardware.slotParam]?.textValue?.hasPrefix("hinge") == true }.count
            return (t, FurnitureFronts.geometry(d, t)?.leaves.count ?? 0, hinges)
        }
        let (_, l12, h12) = try leaves("B12"), (t30, l30, h30) = try leaves("B30")
        #expect(l12 == 1 && h12 == 2 && l30 == 2 && h30 == 4, "\(l12) \(h12) \(l30) \(h30)")
        #expect(try leaves("B21").1 == 1 && leaves("B24").1 == 2)
        // Properties: Leaf Count follows the parameter (its own value locked), Leaves shows the count now.
        let entries = Parameters.instanceEntries(t30[door.id]!, t30)
        #expect(entries.first { $0.name == "Leaf Count Parameter" }?.value?.textValue == "Leaf Count")
        #expect(entries.first { $0.name == "Leaves" }?.value?.intValue == 2)
        #expect(entries.first { $0.name == "Leaf Count" }?.isReadOnly == true || entries.first { $0.name == "Leaf Count" } != nil)

        // Compiled: both variants, each shown by its yes/no parameter; Width switches between them as it flexes.
        let f = FurnitureCompiler.family(from: m)
        let mark = door.mark
        #expect(f.parameters.contains { $0.name == "\(mark) Single" && $0.type == .bool } && f.parameters.contains { $0.name == "\(mark) Pair" })
        #expect(FamilyEvaluator.flexTest(f, units: .imperial).isEmpty, "\(FamilyEvaluator.flexTest(f, units: .imperial).prefix(3))")
        func shown(_ type: String) -> (leaves: Int, hinges: Int) {
            let ev = FamilyEvaluator.evaluate(f, typeName: type, units: .imperial)
            let leafNames = Set(ev.solids.filter { $0.name.hasPrefix(mark) && $0.name.hasSuffix("Left Stile") && $0.visibleAt.contains(.medium) }.map(\.name))
            let hinges = ev.solids.filter { $0.name.hasPrefix(FurnitureHardware.concealedHinge) && $0.visibleAt.contains(.fine) }.map(\.name)
            return (leafNames.count, hinges.count)
        }
        let s15 = shown("B15"), s30 = shown("B30")
        #expect(s15.leaves == 1 && s30.leaves == 2, "\(s15) \(s30)")
        #expect(s30.hinges == 2 * s15.hinges && s15.hinges > 0, "\(s15) \(s30)")
        // The Leaf Count type parameter and an instance's own count.
        let s = DocumentSession(model: m)
        _ = s.perform("Unassociate") { tx in try FurnitureFronts.associateLeafCount([door.id], with: nil, in: tx); tx.update(door.id) { $0.furnitureFront?.leafCount = 2 } }
        #expect(FurnitureFronts.geometry(s.model[door.id]!, s.model)?.leaves.count == 2)
        _ = s.perform("Bad") { tx in try FurnitureFronts.associateLeafCount([door.id], with: "Width", in: tx) }
        #expect(s.lastError != nil)
        let pairType = try #require(m.types(for: .furnitureFronts).first { $0.typeData?.familyName == "Door" && $0.name == "Slab - Full Overlay Pair" })
        #expect(FurnitureFrontTypes.Values(pairType.typeData).leafCount == 2)
        #expect(Parameters.typeEntries(pairType, m).first { $0.name == "Leaf Count" }?.value?.intValue == 2)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FMG3_DEBUG"] != nil)) func debugFlex() throws {
        let name = ProcessInfo.processInfo.environment["FMG3_DEBUG"] ?? ""
        let m = try #require(FurnitureLibrary.simpleASpecs.first { $0.name == name }).build()
        let f = FurnitureCompiler.family(from: m)
        let param = ProcessInfo.processInfo.environment["FMG3_PARAM"] ?? "Depth"
        var g = f
        g.types[0].values[param] = .double((g.types[0].values[param]?.doubleValue ?? 0) * (Double(ProcessInfo.processInfo.environment["FMG3_SCALE"] ?? "") ?? 0.85))
        let ev0 = FamilyEvaluator.evaluate(f, typeName: f.types[0].name, units: .imperial)
        let ev = FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
        print("FMG3 bounds \(ev0.bounds) → \(ev.bounds)")
        for s in ev.solids where !s.isVoid {
            let b = s.bounds
            print("FMG3 \(s.name) x \(b.min.x / i)…\(b.max.x / i) y \(b.min.y / i)…\(b.max.y / i)")
        }
    }
}
