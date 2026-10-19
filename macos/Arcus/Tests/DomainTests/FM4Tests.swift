import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// FM4 (Furniture parts): panels, shelves, backs, dividers, legs, rails and slats, plinths, edge profiles and forms,
/// made through the model operations the tools call; their plane bindings follow Family Types (Width, Height…), their
/// graphics, quantities and Marks, and Load into Project compiling them to solids that flex.
@Suite("FM4 Furniture parts") @MainActor
struct FM4Tests {
    static let inch = 0.0254
    static func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

    static func position(_ m: BIMModel, _ name: String) -> Double { FurniturePlanes.positionsByName(m)[name] ?? .nan }
    static func box(_ m: BIMModel, _ id: ElementID?) -> Box3 { FurniturePartSolids.partBox(m[id]!, m)!.box }
    static func setWidth(_ s: DocumentSession, _ inches: Double) {
        _ = s.perform("Width") { tx in try FurnitureParameters.setValue("Width", .double(inches * inch), in: tx) }
    }
    static func set(_ s: DocumentSession, _ name: String, _ inches: Double) {
        _ = s.perform(name) { tx in try FurnitureParameters.setValue(name, .double(inches * inch), in: tx) }
    }

    /// A bookcase on the template (36" x 18" x 30"): two sides on Left/Right, a bottom and a top between their inside
    /// faces, and two shelves. Returns the session and the ids (left, right, bottom, top, shelf 1, shelf 2).
    static func bookcase(height: Double = 30) -> (DocumentSession, [String: ElementID]) {
        let s = DocumentSession(model: FurnitureTemplates.blank(name: "Bookcase"))
        if height != 30 { set(s, "Height", height) }
        var ids: [String: ElementID] = [:]
        _ = s.perform("Sides") { tx in
            let m = tx.model
            let l = Self.position(m, "Left"), r = Self.position(m, "Right"), f = Self.position(m, "Front"), b = Self.position(m, "Back")
            // Outside faces out: the left side runs front to back (outside to the left), the right side back to front.
            ids["left"] = try FurniturePartOperations.createPanel(start: Vec2(l, f), end: Vec2(l, b), extent: PartExtent(), in: tx)
            ids["right"] = try FurniturePartOperations.createPanel(start: Vec2(r, b), end: Vec2(r, f), extent: PartExtent(), in: tx)
        }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let t = 0.75 * inch
        _ = s.perform("Bottom and Top") { tx in
            let m = tx.model
            let left = m[ids["left"]!]!, right = m[ids["right"]!]!
            // Pick Panels: the inside faces of the sides, and the front and back planes.
            let a = FurniturePartOperations.pickPanelLine(left, toward: .zero, m)!, c = FurniturePartOperations.pickPanelLine(right, toward: .zero, m)!
            let f = position(m, "Front"), b = position(m, "Back")
            let loop = FurniturePartOperations.closeLoop([a, c, Segment2(Vec2(-1, f), Vec2(1, f)), Segment2(Vec2(-1, b), Vec2(1, b))])!
            ids["bottom"] = try FurniturePartOperations.createShelf(boundary: loop, plane: "Bottom", offset: t, role: .bottom, in: tx)
            ids["top"] = try FurniturePartOperations.createShelf(boundary: loop, plane: "Top", offset: 0, role: .top, in: tx)
            ids["shelf1"] = try FurniturePartOperations.createShelf(boundary: loop, plane: "Bottom", offset: 10 * inch, adjustable: true, in: tx)
            ids["shelf2"] = try FurniturePartOperations.createShelf(boundary: loop, plane: "Bottom", offset: 20 * inch, in: tx)
        }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        return (s, ids)
    }

    // MARK: Types

    @Test func templateHasStandardPartTypesAndThePartTag() {
        let m = FurnitureTemplates.blank()
        let panels = Set(m.types(for: .furniturePanels).map(\.name))
        for n in ["3/4\" Plywood", "3/4\" MDF", "5/8\" Melamine", "1/2\" Plywood", "1/4\" Back Panel (Hardboard)", "3/4\" Solid Oak"] { #expect(panels.contains(n), "missing \(n)") }
        let tops = m.types(for: .furnitureShelves).filter { $0.typeData?.familyName == "Top" }.map(\.name)
        #expect(tops.contains("1 1/2\" Butcher Block"))
        let block = m.types(for: .furnitureShelves).first { $0.name == "1 1/2\" Butcher Block" }!
        let v = FurniturePartTypes.Values(block.typeData)
        #expect(Self.approx(v.thickness, 1.5 * Self.inch) && m[v.coreMaterial]?.name == "Solid Maple" && v.topEdge == .roundOver)
        let ply = FurniturePartTypes.Values(m.types(for: .furniturePanels).first { $0.name == "3/4\" Plywood" }!.typeData)
        #expect(ply.banding == EdgeBanding(l1: true) && ply.grain == .length && m[ply.edgeMaterial]?.name == "Edge Banding")
        #expect(Set(m.types(for: .furnitureLegs).compactMap { FurniturePartTypes.Values($0.typeData).legShape }) == Set(LegShape.allCases))
        #expect(!m.types(for: .furnitureRails).isEmpty && !m.types(for: .furnitureEdgeProfiles).isEmpty)
        let tag = m.elements(.families).first { $0.name == "Part Tag" }?.family
        #expect(tag?.taggedCategories == Category.furnitureParts && tag?.labels.map(\.parameterName) == ["Mark", "Size"])
        // Idempotent.
        let tx = TransactionContext(model: m, name: "Again")
        FurniturePartTypes.ensureStandard(in: tx)
        #expect(!tx.hasChanges)
    }

    // MARK: Panels

    @Test func panelOnALeftPlaneLocksAndFollowsWidthAndHeight() throws {
        let (s, ids) = Self.bookcase()
        let left = try #require(s.model[ids["left"]]?.furniturePanel)
        #expect(left.bounds["start.u"] == .plane("Left", offset: 0) && left.bounds["base"] == .plane("Bottom", offset: 0) && left.bounds["top"] == .plane("Top", offset: 0))
        var b = Self.box(s.model, ids["left"])
        #expect(Self.approx(b.min.x, -18 * Self.inch) && Self.approx(b.max.x, -18 * Self.inch + 0.75 * Self.inch), "outside face on Left, inside face in")
        #expect(Self.approx(b.max.z, 30 * Self.inch))
        Self.setWidth(s, 48)
        Self.set(s, "Height", 42)
        b = Self.box(s.model, ids["left"])
        #expect(Self.approx(b.min.x, -24 * Self.inch) && Self.approx(b.max.z, 42 * Self.inch))
        let rb = Self.box(s.model, ids["right"])
        #expect(Self.approx(rb.max.x, 24 * Self.inch) && Self.approx(rb.min.x, 24 * Self.inch - 0.75 * Self.inch), "the right side's outside face is on Right")
    }

    @Test func shelvesSketchedWithPickPanelsFollowTheSidesInsideFaces() throws {
        let (s, ids) = Self.bookcase()
        let t = 0.75 * Self.inch
        var b = Self.box(s.model, ids["shelf1"])
        #expect(Self.approx(b.min.x, -18 * Self.inch + t) && Self.approx(b.max.x, 18 * Self.inch - t))
        #expect(Self.approx(b.max.z, 10 * Self.inch) && Self.approx(b.min.z, 10 * Self.inch - t), "Height Offset is the top face; the type's thickness hangs below")
        let shelf = try #require(s.model[ids["shelf1"]]?.furnitureShelf)
        #expect(shelf.bounds.values.contains { if case .plane("Left", let o) = $0 { return Self.approx(o, t) }; return false }, "\(shelf.bounds)")
        #expect(shelf.adjustable && shelf.pins?.spacing == 0.032)
        Self.setWidth(s, 30)
        b = Self.box(s.model, ids["shelf1"])
        #expect(Self.approx(b.min.x, -15 * Self.inch + t) && Self.approx(b.max.x, 15 * Self.inch - t))
        // The top follows Height (its top face on Top).
        Self.set(s, "Height", 36)
        #expect(Self.approx(Self.box(s.model, ids["top"]).max.z, 36 * Self.inch))
        #expect(Self.approx(Self.box(s.model, ids["shelf2"]).max.z, 20 * Self.inch), "shelves keep their height offset from Bottom")
    }

    @Test func rectangleInAFrontElevationMakesACarcassAcrossTheDepth() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        var ids: [ElementID] = []
        _ = s.perform("Rectangle") { tx in
            let r = Rect2(min: Vec2(-18 * Self.inch, 0), max: Vec2(18 * Self.inch, 30 * Self.inch))
            ids = try FurniturePartOperations.createPanelRectangle(r, plane: .xz, extent: PartExtent(basePlane: "Front", topPlane: "Back"), in: tx)
        }
        #expect(s.lastError == nil && ids.count == 4)
        let boxes = ids.map { Self.box(s.model, $0) }
        // Every panel spans Front to Back and stays inside the rectangle (outside faces on it).
        for b in boxes { #expect(Self.approx(b.min.y, -9 * Self.inch) && Self.approx(b.max.y, 9 * Self.inch)) }
        let all = boxes.reduce(Box3.empty) { $0.union($1) }
        #expect(Self.approx(all.min.x, -18 * Self.inch) && Self.approx(all.max.x, 18 * Self.inch) && Self.approx(all.max.z, 30 * Self.inch))
        // Depth follows.
        Self.set(s, "Depth", 24)
        #expect(Self.approx(Self.box(s.model, ids[0]).max.y, 12 * Self.inch))
        // Sides and top/bottom lock to Left/Right/Top.
        Self.setWidth(s, 40)
        let after = ids.map { Self.box(s.model, $0) }.reduce(Box3.empty) { $0.union($1) }
        #expect(Self.approx(after.max.x, 20 * Self.inch) && Self.approx(after.min.x, -20 * Self.inch))
    }

    @Test func movingAPanelKeepsFollowingItsPlaneAtTheNewOffset() throws {
        let (s, ids) = Self.bookcase()
        let id = try #require(ids["shelf2"])
        _ = s.perform("Move") { tx in try ElementOperations.transform([id], by: .translation(Vec2(0, -2 * Self.inch)), in: tx, viewID: nil) }
        #expect(s.lastError == nil)
        let sh = try #require(s.model[id]?.furnitureShelf)
        // The front edge moved off Front: it follows Front 2" further forward.
        #expect(sh.bounds.values.contains { if case .plane("Front", let o) = $0 { return Self.approx(o, -2 * Self.inch) }; return false }, "\(sh.bounds)")
        Self.set(s, "Depth", 24)
        #expect(Self.approx(Self.box(s.model, id).min.y, -12 * Self.inch - 2 * Self.inch))
        // Moving a side onto Right locks it there.
        let left = try #require(ids["left"])
        _ = s.perform("Move") { tx in try ElementOperations.transform([left], by: .translation(Vec2(36 * Self.inch, 0)), in: tx, viewID: nil) }
        #expect(s.model[left]?.furniturePanel?.bounds["start.u"] == .plane("Right", offset: 0))
    }

    @Test func movingInAnElevationMovesInThatViewsPlane() throws {
        let (s, ids) = Self.bookcase()
        let id = try #require(ids["shelf1"])
        let front = try #require(s.model.views.first { $0.name == "Front" })
        _ = s.perform("Move") { tx in try ElementOperations.transform([id], by: .translation(Vec2(0, 2 * Self.inch)), in: tx, viewID: front.id) }
        #expect(s.lastError == nil)
        let b = Self.box(s.model, id)
        #expect(Self.approx(b.max.z, 12 * Self.inch) && Self.approx(b.min.x, -18 * Self.inch + 0.75 * Self.inch), "up 2\", not across")
    }

    @Test func mirrorAndRotateKeepPanelsAndShelvesValid() throws {
        let (s, ids) = Self.bookcase()
        let left = try #require(ids["left"])
        _ = s.perform("Mirror") { tx in
            _ = ElementOperations.copy([left], by: .mirror(through: .zero, direction: Vec2(0, 1)), in: tx, viewID: nil)
        }
        #expect(s.lastError == nil)
        let copies = s.model.elements(.furniturePanels).filter { $0.id != left && $0.id != ids["right"] }
        let mirrored = try #require(copies.first)
        let b = Self.box(s.model, mirrored.id)
        #expect(Self.approx(b.max.x, 18 * Self.inch) && Self.approx(b.min.x, 18 * Self.inch - 0.75 * Self.inch), "the mirrored side keeps its outside face out")
        #expect(mirrored.mark != s.model[left]!.mark && mirrored.mark.hasPrefix("P"), "a copy gets the next Mark")
        _ = s.perform("Rotate") { tx in try ElementOperations.transform([ids["shelf2"]!], by: .rotation(.pi / 2), in: tx, viewID: nil) }
        let sb = Self.box(s.model, ids["shelf2"])
        #expect(Self.approx(sb.max.x - sb.min.x, 18 * Self.inch, 1e-6), "a quarter turn swaps width and depth")
    }

    @Test func profileAndOpeningCutThePanel() throws {
        let (s, ids) = Self.bookcase()
        let id = try #require(ids["left"])
        let before = abs(FurniturePartMeshes.meshParts(s.model[id]!, s.model, detail: .fine).reduce(0) { $0 + $1.mesh.signedVolume })
        _ = s.perform("Opening") { tx in try FurniturePartOperations.addOpening(id, PanelOpening(s0: 4 * Self.inch, s1: 8 * Self.inch, t0: 10 * Self.inch, t1: 20 * Self.inch), in: tx) }
        #expect(s.lastError == nil)
        let after = abs(FurniturePartMeshes.meshParts(s.model[id]!, s.model, detail: .fine).reduce(0) { $0 + $1.mesh.signedVolume })
        #expect(Self.approx(before - after, 4 * 10 * 0.75 * pow(Self.inch, 3), 1e-7), "\(before) \(after)")
        // Edit Profile: a notch at the top front.
        let L = 18 * Self.inch, H = 30 * Self.inch
        _ = s.perform("Profile") { tx in
            try FurniturePartOperations.setProfile(id, [Vec2(0, 0), Vec2(L, 0), Vec2(L, H), Vec2(3 * Self.inch, H), Vec2(3 * Self.inch, H - 3 * Self.inch), Vec2(0, H - 3 * Self.inch)], in: tx)
        }
        #expect(s.lastError == nil)
        let notched = abs(FurniturePartMeshes.meshParts(s.model[id]!, s.model, detail: .fine).reduce(0) { $0 + $1.mesh.signedVolume })
        #expect(notched < after - 3 * 3 * 0.7 * pow(Self.inch, 3))
        _ = s.perform("Bad") { tx in try FurniturePartOperations.setProfile(id, [Vec2(0, 0), Vec2(L, H), Vec2(L, 0), Vec2(0, H)], in: tx) }
        #expect(s.lastError?.message.contains("cross") == true)
    }

    @Test func attachTopRunsSidesToTheUndersideOfATop() throws {
        let (s, ids) = Self.bookcase()
        let top = try #require(ids["top"]), left = try #require(ids["left"])
        // A top 2" above the sides, then the side attached to it.
        _ = s.perform("Raise Top") { tx in tx.update(top) { $0.furnitureShelf?.bounds["z"] = .plane("Top", offset: 2 * Self.inch) } }
        _ = s.perform("Attach") { tx in try FurniturePartOperations.attach([left], to: top, in: tx) }
        #expect(s.lastError == nil)
        #expect(Self.approx(Self.box(s.model, left).max.z, 32 * Self.inch - 0.75 * Self.inch))
        Self.set(s, "Height", 40)
        #expect(Self.approx(Self.box(s.model, left).max.z, 42 * Self.inch - 0.75 * Self.inch), "the attached side follows the top")
        _ = s.perform("Detach") { tx in FurniturePartOperations.detach([left], in: tx) }
        #expect(s.model[left]?.furniturePanel?.attachedTopID == nil)
    }

    // MARK: Backs, dividers, plinth

    @Test func backFitsInsideOrOverTheCarcass() throws {
        let (s, _) = Self.bookcase()
        var inside: ElementID?, overlay: ElementID?
        _ = s.perform("Back") { tx in inside = try FurniturePartOperations.createBack(atFront: Vec2(0, 15 * Self.inch), fit: .inside, in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let bi = Self.box(s.model, inside)
        let t = 0.75 * Self.inch, bt = 0.25 * Self.inch
        #expect(Self.approx(bi.min.x, -18 * Self.inch + t) && Self.approx(bi.max.x, 18 * Self.inch - t))
        #expect(Self.approx(bi.max.y, 9 * Self.inch) && Self.approx(bi.min.y, 9 * Self.inch - bt), "flush with the back, the hardboard type")
        #expect(Self.approx(bi.min.z, t) && Self.approx(bi.max.z, 30 * Self.inch - t))
        #expect(s.model[inside]?.furniturePanel?.back?.fit == .inside && s.model[inside]?.furniturePanel?.role == .back)
        _ = s.perform("Overlay") { tx in overlay = try FurniturePartOperations.createBack(atFront: Vec2(0, 15 * Self.inch), fit: .fullOverlay, in: tx) }
        let bo = Self.box(s.model, overlay)
        #expect(Self.approx(bo.min.x, -18 * Self.inch) && Self.approx(bo.max.x, 18 * Self.inch) && Self.approx(bo.min.y, 9 * Self.inch) && Self.approx(bo.max.z, 30 * Self.inch))
        Self.setWidth(s, 40)
        #expect(Self.approx(Self.box(s.model, overlay).max.x, 20 * Self.inch))
    }

    @Test func dividersSplitABayIntoEqualSpacesAndStayEqual() throws {
        let (s, _) = Self.bookcase()
        var ids: [ElementID] = []
        _ = s.perform("Dividers") { tx in ids = try FurniturePartOperations.createDividers(atFront: Vec2(0, 5 * Self.inch), vertical: true, count: 2, in: tx) }
        #expect(s.lastError == nil && ids.count == 2, "\(s.lastError?.message ?? "")")
        let t = 0.75 * Self.inch
        func centers() -> [Double] { ids.map { let b = Self.box(s.model, $0); return (b.min.x + b.max.x) / 2 } }
        let inside = (lo: -18 * Self.inch + t, hi: 18 * Self.inch - t)
        var c = centers()
        #expect(Self.approx(c[0], inside.lo + (inside.hi - inside.lo) / 3) && Self.approx(c[1], inside.lo + (inside.hi - inside.lo) * 2 / 3))
        // The bay is between the bottom and the first shelf.
        let b = Self.box(s.model, ids[0])
        #expect(Self.approx(b.min.z, t) && Self.approx(b.max.z, 10 * Self.inch - t))
        Self.setWidth(s, 48)
        c = centers()
        let wide = (lo: -24 * Self.inch + t, hi: 24 * Self.inch - t)
        #expect(Self.approx(c[0], wide.lo + (wide.hi - wide.lo) / 3) && Self.approx(c[1], wide.lo + (wide.hi - wide.lo) * 2 / 3))
        // A horizontal divider across the bay.
        var h: [ElementID] = []
        _ = s.perform("Horizontal") { tx in h = try FurniturePartOperations.createDividers(atFront: Vec2(-20 * Self.inch, 25 * Self.inch), vertical: false, count: 1, in: tx) }
        #expect(s.lastError == nil && h.count == 1)
        let hb = Self.box(s.model, h[0])
        #expect(Self.approx((hb.min.z + hb.max.z) / 2, (20 * Self.inch + 30 * Self.inch - t) / 2), "midway between shelf 2 and the top")
    }

    @Test func plinthRunsUnderTheBottomSetBack() throws {
        let (s, ids) = Self.bookcase()
        // Raise the bottom 4" so there's a kick space.
        _ = s.perform("Raise") { tx in tx.update(ids["bottom"]!) { $0.furnitureShelf?.bounds["z"] = .plane("Bottom", offset: 4 * Self.inch) } }
        var k: ElementID?
        _ = s.perform("Plinth") { tx in k = try FurniturePartOperations.createPlinth(under: ids["bottom"]!, setback: 3 * Self.inch, in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let b = Self.box(s.model, k)
        #expect(Self.approx(b.min.z, 0) && Self.approx(b.max.z, 4 * Self.inch - 0.75 * Self.inch))
        #expect(Self.approx(b.min.y, -9 * Self.inch + 3 * Self.inch) && Self.approx(b.max.y, -9 * Self.inch + 3 * Self.inch + 0.75 * Self.inch), "outside face 3\" back from the front")
        #expect(s.model[k]?.furniturePanel?.role == .plinth && s.model[k]?.mark == "KK1")
    }

    // MARK: Legs, rails, slats

    @Test func legsAtCornersOfATopFollowItsSize() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank(name: "Table"))
        var top: ElementID?, legs: [ElementID] = []
        _ = s.perform("Top") { tx in
            let m = tx.model
            let l = Self.position(m, "Left"), r = Self.position(m, "Right"), f = Self.position(m, "Front"), b = Self.position(m, "Back")
            top = try FurniturePartOperations.createShelf(boundary: [Vec2(l, f), Vec2(r, f), Vec2(r, b), Vec2(l, b)], plane: "Top", offset: 0, role: .top, in: tx)
        }
        _ = s.perform("At Corners") { tx in legs = try FurniturePartOperations.legsAtCorners(of: top!, inset: 1 * Self.inch, in: tx) }
        #expect(s.lastError == nil && legs.count == 4, "\(s.lastError?.message ?? "")")
        let tt = FurniturePartTypes.values(of: s.model[top!]!, s.model).thickness
        let lw = FurniturePartTypes.values(of: s.model[legs[0]]!, s.model).width
        let all = legs.map { Self.box(s.model, $0) }.reduce(Box3.empty) { $0.union($1) }
        #expect(Self.approx(all.min.x, -18 * Self.inch + 1 * Self.inch) && Self.approx(all.max.x, 18 * Self.inch - 1 * Self.inch))
        #expect(Self.approx(all.max.z, 30 * Self.inch - tt) && Self.approx(all.min.z, 0), "from Bottom to the underside of the top")
        #expect(Self.approx(Self.box(s.model, legs[0]).max.x - Self.box(s.model, legs[0]).min.x, lw))
        Self.setWidth(s, 60)
        Self.set(s, "Height", 29)
        let after = legs.map { Self.box(s.model, $0) }.reduce(Box3.empty) { $0.union($1) }
        #expect(Self.approx(after.max.x, 30 * Self.inch - 1 * Self.inch) && Self.approx(after.max.z, 29 * Self.inch - tt))
        #expect(s.model[legs[0]]?.mark == "L1" && s.model[legs[3]]?.mark == "L4")
        // Other shapes build a solid: round tapered, turned, hairpin, sled, caster.
        for name in ["Round Tapered 2\"", "Turned 2 1/2\"", "Hairpin 3/8\" Rod", "Sled 1\" Steel", "Caster 2\"", "Square Tapered 1 3/4\""] {
            let t = try #require(s.model.types(for: .furnitureLegs).first { $0.name == name })
            _ = s.perform("Type") { tx in tx.update(legs[0]) { $0.typeID = t.id } }
            let parts = FurniturePartMeshes.meshParts(s.model[legs[0]]!, s.model, detail: .fine)
            let vol = parts.reduce(0) { $0 + abs($1.mesh.signedVolume) }
            let bb = parts.reduce(Box3.empty) { $0.union($1.mesh.bounds) }
            #expect(vol > 1e-6 && Self.approx(bb.max.z, 29 * Self.inch - tt, 1e-4), "\(name): \(vol) \(bb)")
        }
    }

    @Test func railsJustifyLikeBeamsAndSlatsLayOutLikeABeamSystem() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank(name: "Bench"))
        var apron: ElementID?, slats: ElementID?
        _ = s.perform("Apron") { tx in
            apron = try FurniturePartOperations.createRail(start: Vec2(-17 * Self.inch, -8 * Self.inch), end: Vec2(17 * Self.inch, -8 * Self.inch), w: -1 * Self.inch, wPlane: "Top", in: tx)
        }
        #expect(s.lastError == nil)
        let tv = FurniturePartTypes.values(of: s.model[apron!]!, s.model)
        var b = Self.box(s.model, apron)
        #expect(Self.approx(b.max.z, 29 * Self.inch) && Self.approx(b.min.z, 29 * Self.inch - tv.depth), "Top justification hangs it below its line")
        _ = s.perform("Center") { tx in tx.update(apron!) { $0.furnitureRail?.justification = .center } }
        b = Self.box(s.model, apron)
        #expect(Self.approx((b.min.z + b.max.z) / 2, 29 * Self.inch))
        Self.set(s, "Height", 20)
        #expect(Self.approx((Self.box(s.model, apron).min.z + Self.box(s.model, apron).max.z) / 2, 19 * Self.inch), "the rail follows Top")
        // Slats: 2 1/2" slats at 4" filling a 16" x 34" seat.
        _ = s.perform("Slats") { tx in
            slats = try FurniturePartOperations.createSlats(in: Rect2(min: Vec2(-17 * Self.inch, -8 * Self.inch), max: Vec2(17 * Self.inch, 8 * Self.inch)), alongX: true,
                                                            rule: .fixedDistance, spacing: 4 * Self.inch, number: 0, z: 0, zPlane: "Top", in: tx)
        }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let e = try #require(s.model[slats!])
        let layout = try #require(e.furnitureRail?.slats)
        // Extent is 16" - 2.5" = 13.5": floor(13.5 / 4) + 1 = 4 slats, centred.
        #expect(layout.offsets.count == 4 && FurniturePartMeshes.count(e) == 4)
        let parts = FurniturePartMeshes.meshParts(e, s.model, detail: .fine)
        #expect(parts.count == 4)
        let bb = parts.reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        #expect(Self.approx(bb.max.z, 20 * Self.inch) && bb.min.y >= -8 * Self.inch - 1e-9 && bb.max.y <= 8 * Self.inch + 1e-9)
        _ = s.perform("Fixed Number") { tx in tx.update(slats!) { $0.furnitureRail?.slats?.rule = .fixedNumber; $0.furnitureRail?.slats?.number = 7 } }
        #expect(FurniturePartMeshes.meshParts(s.model[slats!]!, s.model, detail: .fine).count == 7)
        #expect(s.model[slats!]?.mark == "SL1")
    }

    // MARK: Edge profiles

    @Test func edgeProfilesCutTheirHostAlongAnEdge() throws {
        let (s, ids) = Self.bookcase()
        let shelf = try #require(ids["shelf2"])
        func volume() -> Double { abs(FurniturePartMeshes.meshParts(s.model[shelf]!, s.model, detail: .fine).reduce(0) { $0 + $1.mesh.signedVolume }) }
        let v0 = volume()
        let frontTop = PartEdge(axis: .x, firstAtMax: false, secondAtMax: true)
        var ep: ElementID?
        _ = s.perform("Round-Over") { tx in ep = try FurniturePartOperations.createEdgeProfile(on: shelf, edge: frontTop, in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let r = 0.25 * Self.inch
        let L = 36 * Self.inch - 1.5 * Self.inch
        let removed = (r * r - .pi * r * r / 4) * L
        #expect(Self.approx(v0 - volume(), removed, removed * 0.08), "\(v0 - volume()) vs \(removed)")
        #expect(s.model[ep]?.mark == "EP1" && s.model[ep]?.hostID == shelf)
        // A groove (reveal) along the back of the top face.
        var g: ElementID?
        _ = s.perform("Groove") { tx in
            g = try FurniturePartOperations.createEdgeProfile(on: shelf, edge: PartEdge(axis: .x, firstAtMax: true, secondAtMax: true), groove: true, offset: 0.5 * Self.inch, in: tx)
        }
        #expect(s.model[g]?.furnitureEdgeProfile?.isGroove == true && s.model[g]?.mark == "G1")
        // The profile follows the host when Width changes.
        Self.setWidth(s, 48)
        let L2 = 48 * Self.inch - 1.5 * Self.inch
        let v1 = abs(FurniturePartMeshes.meshParts(s.model[shelf]!, s.model, detail: .fine).reduce(0) { $0 + $1.mesh.signedVolume })
        let full = L2 * 18 * Self.inch * 0.75 * Self.inch
        #expect(v1 < full - (r * r - .pi * r * r / 4) * L2 * 0.9)
        // Picking: the edge nearest a click in the front elevation is the front top edge.
        let front = s.model.views.first { $0.name == "Front" }!.view!
        let o = front.planeOrigin!, rv = front.rightVector!, fw = front.viewDirection!.normalized
        let e = FurniturePartOperations.nearestEdge(of: s.model[shelf]!, s.model, pick: Vec2(0, 20 * Self.inch), tolerance: 0.002) { p in
            (Vec2((p.xy - o.xy).dot(rv), p.z), (p.xy - o.xy).dot(fw))
        }
        #expect(e == frontTop)
    }

    // MARK: Forms

    @Test func formsAndCushionsBuildSolidsAndVoidsCutParts() throws {
        let (s, ids) = Self.bookcase()
        var ext: ElementID?, cushion: ElementID?, void: ElementID?
        _ = s.perform("Forms") { tx in
            ext = try FurniturePartOperations.createForm(FurnitureFormData(kind: .extrusion, profile: [Vec2(-0.1, -0.1), Vec2(0.1, -0.1), Vec2(0, 0.1)], w0: 0.8, w1: 0.9), in: tx)
            var c = FurnitureFormData(kind: .cushion, profile: [], w0: 0.8, w1: 0.9)
            c.cushion = CushionSpec(center: Vec2(0, 0), width: 0.5, depth: 0.4, height: 0.1)
            cushion = try FurniturePartOperations.createForm(c, in: tx)
            void = try FurniturePartOperations.createForm(FurnitureFormData(kind: .extrusion, isVoid: true, profile: [Vec2(-0.05, -0.3), Vec2(0.05, -0.3), Vec2(0.05, 0.3), Vec2(-0.05, 0.3)],
                                                                          w0: 9.5 * Self.inch, w1: 10.5 * Self.inch), in: tx)
        }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let ev = abs(FurniturePartMeshes.meshParts(s.model[ext!]!, s.model, detail: .fine).reduce(0) { $0 + $1.mesh.signedVolume })
        #expect(Self.approx(ev, 0.2 * 0.2 / 2 * 0.1, 1e-6))
        let cparts = FurniturePartMeshes.meshParts(s.model[cushion!]!, s.model, detail: .fine)
        #expect(cparts.count >= 3, "body, crown and piping")
        #expect(s.model[cushion!]?.furnitureForm?.materialID == s.model.elements(.materials).first { $0.name == "Fabric" }?.id)
        #expect(FurniturePartMeshes.meshParts(s.model[void!]!, s.model, detail: .fine).isEmpty && !ElementMeshes.hasModelGeometry(s.model[void!]!))
        // The void cuts the shelf at 10".
        let shelf = s.model[ids["shelf1"]!]!
        let cut = abs(FurniturePartMeshes.meshParts(shelf, s.model, detail: .fine).reduce(0) { $0 + $1.mesh.signedVolume })
        let full = (36 - 1.5) * 18 * 0.75 * pow(Self.inch, 3)
        #expect(cut < full - 0.1 * 18 * Self.inch * 0.5 * Self.inch * 0.9, "\(cut) \(full)")
        #expect(s.model[ext!]?.mark == "F1")
    }

    // MARK: Quantities and graphics

    @Test func quantitiesGiveTheNominalSize() throws {
        let (s, ids) = Self.bookcase()
        let q = QuantityEngine.quantities(for: s.model[ids["left"]!]!, in: s.model)
        #expect(Self.approx(q.length, 30 * Self.inch) && Self.approx(q.width, 18 * Self.inch) && Self.approx(q.thickness, 0.75 * Self.inch))
        #expect(Self.approx(q.volume, 30 * 18 * 0.75 * pow(Self.inch, 3), 1e-8))
        let sh = QuantityEngine.quantities(for: s.model[ids["shelf1"]!]!, in: s.model)
        #expect(Self.approx(sh.length, 34.5 * Self.inch) && Self.approx(sh.width, 18 * Self.inch))
        #expect(FurniturePartMeshes.sizeText(s.model[ids["shelf1"]!]!, s.model) == "18\" x 34 1/2\"")
        let size = Parameters.value(ParameterID("furniture.part.size"), of: s.model[ids["left"]!]!, s.model)?.textValue
        #expect(size == "18\" x 30\"")
        #expect(["P1", "P2"].contains(s.model[ids["left"]!]!.mark) && s.model[ids["bottom"]!]!.mark == "BT1" && s.model[ids["top"]!]!.mark == "T1" && s.model[ids["shelf2"]!]!.mark == "S2")
    }

    @Test func propertiesSetConstraintsLikeWalls() throws {
        let (s, ids) = Self.bookcase()
        let id = ids["left"]!
        let top = FurniturePlanes.all(s.model).first { $0.name == "Top" }!.id
        // Top Constraint none: Unconnected Height applies.
        _ = s.perform("Unconnected") { tx in try Parameters.set(ParameterID("furniture.part.topConstraint"), to: .ref(nil), on: id, in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        _ = s.perform("Height") { tx in try Parameters.set(ParameterID("furniture.part.unconnectedHeight"), to: .double(24 * Self.inch), on: id, in: tx) }
        #expect(Self.approx(Self.box(s.model, id).max.z, 24 * Self.inch))
        Self.set(s, "Height", 40)
        #expect(Self.approx(Self.box(s.model, id).max.z, 24 * Self.inch), "unconnected: no longer follows Top")
        _ = s.perform("Top") { tx in
            try Parameters.set(ParameterID("furniture.part.topConstraint"), to: .ref(top), on: id, in: tx)
            try Parameters.set(ParameterID("furniture.part.topOffset"), to: .double(-1 * Self.inch), on: id, in: tx)
        }
        #expect(Self.approx(Self.box(s.model, id).max.z, 39 * Self.inch))
        // A plane that runs the wrong way is refused.
        let left = FurniturePlanes.all(s.model).first { $0.name == "Left" }!.id
        _ = s.perform("Wrong") { tx in try Parameters.set(ParameterID("furniture.part.baseConstraint"), to: .ref(left), on: id, in: tx) }
        #expect(s.lastError != nil)
        // Type properties: thickness changes the part.
        let tid = s.model[id]!.typeID!
        _ = s.perform("Type") { tx in try Parameters.set(FurniturePartTypes.thickness, to: .double(1 * Self.inch), on: tid, in: tx) }
        let b = Self.box(s.model, id)
        #expect(Self.approx(b.max.x - b.min.x, 1 * Self.inch))
        let names = BuiltInCatalog.type(for: s.model[tid]!.typeData!).map(\.name)
        #expect(names.starts(with: ["Thickness", "Core Material", "Face Material", "Edge Band Material", "Edge Band Thickness", "Default Edge Banding", "Grain"]))
    }

    @Test func plansCutTheSidesAndElevationsShowHiddenLinesAndGrain() throws {
        var (s, _) = Self.bookcase(height: 60)
        let ply = s.model.types(for: .furniturePanels).first { $0.name == "1/4\" Plywood" }!.id
        _ = s.perform("Back") { tx in _ = try FurniturePartOperations.createBack(atFront: Vec2(0, 15 * Self.inch), fit: .inside, typeID: ply, in: tx) }
        let m = s.model
        let plan = m.views.first { $0.view?.kind == .floorPlan }!
        let pg = ViewGraphicsBuilder(model: m, view: plan).build()
        let cut = pg.items.filter { $0.layer == .cut && $0.category == .furniturePanels }
        #expect(cut.count >= 3, "the sides and the back are cut at 4'-0\"")
        #expect(cut.contains { $0.primitives.contains { if case .fill = $0 { return true }; return false } }, "with the material's cut pattern")
        let proj = pg.items.filter { $0.layer == .model && $0.category == .furnitureShelves }
        #expect(!proj.isEmpty, "the shelves below are seen")
        let front = m.views.first { $0.name == "Front" }!
        let fg = ViewGraphicsBuilder(model: m, view: front).build()
        let dashed = fg.items.flatMap(\.primitives).filter { if case .polyline(_, _, let st) = $0 { return st.pattern == .hidden }; return false }
        #expect(!dashed.isEmpty, "hidden lines at Fine")
        // The back faces the front view: its grain arrow is drawn.
        let backID = m.elements(.furniturePanels).first { $0.furniturePanel?.role == .back }!.id
        #expect(fg.items.filter { $0.elementID == backID }.count >= 2)
        // A section through the middle cuts the shelves with a fill.
        _ = s.perform("Section") { tx in
            var v = ViewData(kind: .section, scale: 12)
            v.planeOrigin = Vec3(0, 0, 0); v.viewDirection = Vec2(1, 0); v.farClip = 1
            tx.create(.views, name: "Section 1", data: .view(v))
        }
        let sec = s.model.views.first { $0.name == "Section 1" }!
        let sg = ViewGraphicsBuilder(model: s.model, view: sec).build()
        #expect(sg.items.contains { $0.layer == .cut && $0.category == .furnitureShelves && $0.primitives.contains { if case .fill = $0 { return true }; return false } })
        s = DocumentSession(model: s.model)
    }

    // MARK: Compile and flex

    @Test func bookcaseCompilesToSolidsOnThePlanesAndFlexesInAProject() throws {
        let (s, ids) = Self.bookcase()
        _ = s.perform("Dividers") { tx in _ = try FurniturePartOperations.createDividers(atFront: Vec2(0, 5 * Self.inch), vertical: true, count: 1, in: tx) }
        _ = s.perform("Edge") { tx in _ = try FurniturePartOperations.createEdgeProfile(on: ids["top"]!, edge: PartEdge(axis: .x, firstAtMax: false, secondAtMax: true), in: tx) }
        let m = s.model
        let f = FurnitureCompiler.family(from: m)
        // Seven parts (3 panels incl. the divider + 4 shelves) as solids; the right side's outside face is on Right.
        #expect(f.solids.filter { !$0.isVoid }.count == 7, "\(f.solids.map(\.name))")
        let right = f.solids.first { $0.name == m[ids["right"]!]!.mark }!
        guard case .rectangle(_, let xMax, _, _) = right.profile else { Issue.record("not a box"); return }
        #expect(xMax == .plane("Right"))
        #expect(right.zMax == .plane("Top") && right.materialParameter != nil)
        #expect(f.parameters.contains { $0.name == "3/4 in Plywood Material" }, "\(f.parameters.map(\.name))")
        #expect(f.nestedInstances.count == 1, "the edge profile")
        #expect(FamilyEvaluator.flexTest(f, units: .imperial).isEmpty, "\(FamilyEvaluator.flexTest(f, units: .imperial).prefix(5))")
        // Flex: a wider type moves the sides, shelves stretch between them, the divider stays centred.
        var wide = f
        wide.types[0].values["Width"] = .double(48 * Self.inch)
        let ev = FamilyEvaluator.evaluate(wide, typeName: wide.types[0].name, units: .imperial)
        #expect(ev.errors.isEmpty, "\(ev.errors)")
        let b = ev.bounds
        #expect(Self.approx(b.max.x, 24 * Self.inch, 1e-6) && Self.approx(b.min.x, -24 * Self.inch, 1e-6))
        let shelf = ev.solids.first { $0.name == m[ids["shelf1"]!]!.mark }!
        #expect(Self.approx(shelf.bounds.max.x, 24 * Self.inch - 0.75 * Self.inch, 1e-6))
        let divider = ev.solids.first { $0.name.hasPrefix("DV") }!
        #expect(Self.approx((divider.bounds.min.x + divider.bounds.max.x) / 2, 0, 1e-6))
        // Taller: the top and sides follow.
        var tall = f
        tall.types[0].values["Height"] = .double(40 * Self.inch)
        let tv = FamilyEvaluator.evaluate(tall, typeName: tall.types[0].name, units: .imperial)
        #expect(Self.approx(tv.bounds.max.z, 40 * Self.inch, 1e-6))
        // Load into a project: an instance there has the geometry, with the project's material.
        let project = DocumentSession(model: ProjectTemplates.make(.empty, units: .imperial).0)
        var fid: ElementID?
        _ = project.perform("Load") { tx in fid = FurnitureLoading.load(f, from: m, replacing: nil, in: tx) }
        #expect(project.lastError == nil)
        let type = try #require(project.model.elements(.elementTypes).first { $0.typeData?.familyID == fid })
        let mat = type.typeData?.params[Parameters.familyParamID("3/4 in Plywood Material")]?.refValue
        #expect(project.model[mat]?.name == "Plywood")
        var inst: ElementID?
        _ = project.perform("Place") { tx in
            inst = tx.create(.furniture, data: .component(ComponentData(location: .zero)), typeID: type.id, levelID: project.model.levels.first?.id)
        }
        let parts = ElementMeshes.parts(project.model[inst!]!, project.model)
        #expect(parts.count >= 7)
        let pb = parts.reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        #expect(Self.approx(pb.max.x - pb.min.x, 36 * Self.inch, 1e-5) && Self.approx(pb.max.z - pb.min.z, 30 * Self.inch, 1e-5))
    }

    // MARK: Tools

    static func click(_ tool: some InteractiveTool, _ p: Vec2) {
        let i = ToolInput(point: p, rawPoint: p)
        tool.pointerMoved(i)
        tool.pointerDown(i)
        tool.pointerUp(i)
    }
    static func view(_ m: BIMModel, _ name: String) -> ElementID { m.views.first { $0.name == name || ($0.view?.kind == .floorPlan && name == "Plan") }!.id }

    @Test func panelToolDrawsChainsRectanglesAndFlipsWithSpace() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        let ctx = ToolContext(session: s, viewID: Self.view(s.model, "Plan"))
        let tool = FurniturePanelTool(ctx: ctx)
        #expect(tool.options.map(\.id).starts(with: ["mode", "basePlane", "baseOffset", "topPlane", "topOffset", "location", "chain"]))
        let i = Self.inch
        Self.click(tool, Vec2(-18 * i, -9 * i)); Self.click(tool, Vec2(-18 * i, 9 * i)); Self.click(tool, Vec2(18 * i, 9 * i))
        #expect(s.model.elements(.furniturePanels).count == 2, "a chain of two panels")
        #expect(tool.escape() == .stayInTool && tool.escape() == .exitTool)
        // Space flips: the outside face goes to the right of the drawing direction.
        tool.spaceBar()
        Self.click(tool, Vec2(18 * i, -9 * i)); Self.click(tool, Vec2(-18 * i, -9 * i))
        let last = s.model.elements(.furniturePanels).max { $0.id < $1.id }!
        #expect(last.furniturePanel?.flipped == true)
        let b = Self.box(s.model, last.id)
        #expect(Self.approx(b.min.y, -9 * i - 0.75 * i), "flipped: the panel lies outside the line (toward the front)")
        // Rectangle in the Front elevation: four panels across the depth.
        let front = ToolContext(session: s, viewID: Self.view(s.model, "Front"))
        let rt = FurniturePanelTool(ctx: front, mode: .rectangle)
        #expect(rt.map?.plane == .xz && rt.extent.basePlane == "Front" && rt.extent.topPlane == "Back")
        Self.click(rt, Vec2(-10 * i, 2 * i)); Self.click(rt, Vec2(10 * i, 20 * i))
        let rect = s.model.elements(.furniturePanels).filter { $0.furniturePanel?.plane == .xz }
        #expect(rect.count == 4)
        // In the Back elevation (u runs toward -x) a line still lands where it's drawn.
        let back = ToolContext(session: s, viewID: Self.view(s.model, "Back"))
        let bt = FurniturePanelTool(ctx: back)
        #expect(bt.map?.mirrored == true)
        Self.click(bt, Vec2(-5 * i, 25 * i)); Self.click(bt, Vec2(5 * i, 25 * i))
        let drawn = s.model.elements(.furniturePanels).max { $0.id < $1.id }!.furniturePanel!
        #expect(Self.approx(drawn.start.x, 5 * i) && Self.approx(drawn.end.x, -5 * i), "the Back view's u is -x")
    }

    @Test func shelfToolPicksPanelsAndFinishesLikeAFloor() throws {
        let (s, ids) = Self.bookcase()
        let plan = Self.view(s.model, "Plan")
        let ctx = ToolContext(session: s, viewID: plan)
        ctx.pixel = 0.001
        let tool = SketchTool.furniture(ctx, .shelf(.shelf), commandID: .furnitureShelf)
        #expect(tool.drawMode == .pickWalls && tool.isSketchMode)
        #expect(tool.options.first?.value.textValue == "Pick Panels")
        #expect(tool.options.first.map { if case .choice(let c) = $0.kind { return c.contains("Pick Panels") && !c.contains("Pick Walls") }; return false } == true)
        tool.setOption("fm4.offset", .double(15 * Self.inch))
        // Click inside the carcass: the sides' inside faces and the front and back planes.
        Self.click(tool, Vec2(0, 0))
        #expect(tool.curves.count == 4)
        #expect(tool.finish())
        let shelves = s.model.elements(.furnitureShelves)
        let shelf = shelves.max { $0.id < $1.id }!
        let b = Self.box(s.model, shelf.id)
        #expect(Self.approx(b.min.x, -18 * Self.inch + 0.75 * Self.inch) && Self.approx(b.max.z, 15 * Self.inch))
        // Picking the two sides one by one and the planes: lines meet at the corners.
        let t2 = SketchTool.furniture(ctx, .shelf(.shelf), commandID: .furnitureShelf)
        Self.click(t2, Vec2(-18 * Self.inch + 0.3 * Self.inch, 0))
        #expect(t2.curves.count == 1)
        _ = ids
    }

    @Test func legRailAndEdgeToolsPlaceParts() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank(name: "Table"))
        let plan = Self.view(s.model, "Plan")
        let ctx = ToolContext(session: s, viewID: plan)
        ctx.pixel = 0.001
        var top: ElementID?
        _ = s.perform("Top") { tx in
            top = try FurniturePartOperations.createShelf(boundary: Polygon2.rectangle(Rect2(min: Vec2(-18 * Self.inch, -9 * Self.inch), max: Vec2(18 * Self.inch, 9 * Self.inch))).points,
                                                          plane: "Top", offset: 0, role: .top, in: tx)
        }
        let corners = FurnitureLegTool(ctx: ctx, atCorners: true)
        Self.click(corners, Vec2(0, 0))
        #expect(s.model.elements(.furnitureLegs).count == 4)
        let leg = FurnitureLegTool(ctx: ctx)
        leg.spaceBar()
        #expect(Self.approx(leg.rotation, .pi / 2))
        Self.click(leg, Vec2(0, 0))
        #expect(s.model.elements(.furnitureLegs).count == 5)
        let rail = FurnitureRailTool(ctx: ctx)
        #expect(rail.plane == "Top")
        Self.click(rail, Vec2(-16 * Self.inch, -8 * Self.inch)); Self.click(rail, Vec2(16 * Self.inch, -8 * Self.inch))
        #expect(s.model.elements(.furnitureRails).count == 1)
        // Edge Profile in the Front elevation: the top's front top edge.
        let fctx = ToolContext(session: s, viewID: Self.view(s.model, "Front"))
        fctx.pixel = 0.001
        let edge = FurnitureEdgeProfileTool(ctx: fctx, groove: false)
        let tt = FurniturePartTypes.values(of: s.model[top!]!, s.model).thickness
        Self.click(edge, Vec2(0, 30 * Self.inch))
        let ep = try #require(s.model.elements(.furnitureEdgeProfiles).first?.furnitureEdgeProfile)
        #expect(ep.edge == PartEdge(axis: .x, firstAtMax: false, secondAtMax: true), "\(ep.edge) (top \(tt))")
    }

    @Test func backAndDividerToolsPickTheBayInTheFrontElevation() throws {
        let (s, _) = Self.bookcase()
        let ctx = ToolContext(session: s, viewID: Self.view(s.model, "Front"))
        let back = FurnitureBackTool(ctx: ctx)
        Self.click(back, Vec2(0, 15 * Self.inch))
        #expect(s.model.elements(.furniturePanels).contains { $0.furniturePanel?.role == .back })
        let div = FurnitureDividerTool(ctx: ctx)
        div.setOption("count", .int(2))
        Self.click(div, Vec2(0, 25 * Self.inch))
        #expect(s.model.elements(.furniturePanels).filter { $0.furniturePanel?.role == .divider }.count == 2)
        // The plan has no bays to pick.
        let pctx = ToolContext(session: s, viewID: Self.view(s.model, "Plan"))
        #expect(FurnitureBackTool(ctx: pctx).prompt.contains("Front or Back"))
    }

    @Test func formToolsSketchExtrusionsRevolvesAndSweeps() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        let plan = ToolContext(session: s, viewID: Self.view(s.model, "Plan"))
        let ext = SketchTool.furniture(plan, .form(.extrusion, isVoid: false), commandID: .furnitureExtrusion)
        ext.setOption("mode", .text("Rectangle"))
        Self.click(ext, Vec2(-0.1, -0.1)); Self.click(ext, Vec2(0.1, 0.1))
        #expect(ext.finish())
        let f = try #require(s.model.elements(.furnitureForms).first?.furnitureForm)
        #expect(f.kind == .extrusion && Self.approx(f.w1 - f.w0, 12 * Self.inch))
        // Revolve in the Front elevation: a profile and a vertical axis line.
        let front = ToolContext(session: s, viewID: Self.view(s.model, "Front"))
        let rev = SketchTool.furniture(front, .form(.revolve, isVoid: false), commandID: .furnitureRevolve)
        rev.setOption("mode", .text("Rectangle"))
        Self.click(rev, Vec2(0.02, 0)); Self.click(rev, Vec2(0.05, 0.3))
        rev.setOption("mode", .text("Line"))
        Self.click(rev, Vec2(0, 0)); Self.click(rev, Vec2(0, 0.3))
        _ = rev.escape()
        #expect(rev.finish(), "\(rev.curves.count) curves")
        let r = try #require(s.model.elements(.furnitureForms).first { $0.furnitureForm?.kind == .revolve })
        let vol = FurniturePartMeshes.meshParts(r, s.model, detail: .fine).reduce(0) { $0 + abs($1.mesh.signedVolume) }
        #expect(Self.approx(vol, .pi * (0.05 * 0.05 - 0.02 * 0.02) * 0.3, 0.0004), "\(vol)")
        // Sweep in plan: a path and a profile.
        let sw = SketchTool.furniture(plan, .form(.sweep, isVoid: false), commandID: .furnitureSweep)
        Self.click(sw, Vec2(-0.3, 0.3)); Self.click(sw, Vec2(0.3, 0.3))
        _ = sw.escape()
        sw.setOption("mode", .text("Rectangle"))
        Self.click(sw, Vec2(0.5, 0.5)); Self.click(sw, Vec2(0.52, 0.53))
        #expect(sw.finish())
        let sweep = try #require(s.model.elements(.furnitureForms).first { $0.furnitureForm?.kind == .sweep })
        #expect(!FurniturePartMeshes.meshParts(sweep, s.model, detail: .fine).isEmpty)
        // Cushion: two corners.
        let cu = FurnitureCushionTool(ctx: plan)
        Self.click(cu, Vec2(-0.3, -0.2)); Self.click(cu, Vec2(0.3, 0.2))
        let c = try #require(s.model.elements(.furnitureForms).first { $0.furnitureForm?.kind == .cushion }?.furnitureForm?.cushion)
        #expect(Self.approx(c.width, 0.6) && Self.approx(c.depth, 0.4))
    }

    @Test func gripsAndCommandsBehaveLikeTheirRevitCounterparts() throws {
        let (s, ids) = Self.bookcase()
        let plan = Self.view(s.model, "Plan"), front = Self.view(s.model, "Front")
        let left = s.model[ids["left"]!]!
        let pg = GripService.grips(for: left, s.model, viewKind: .floorPlan, viewID: plan)
        #expect(pg.map(\.kind) == [.start, .end])
        let fg = GripService.grips(for: left, s.model, viewKind: .elevation, viewID: front)
        #expect(fg.filter { $0.kind == .sectionDepth }.count == 2, "height arrows in the elevation")
        let topArrow = fg.first { $0.kind == .sectionDepth && $0.isOn }!
        _ = s.perform("Drag") { tx in GripService.apply(topArrow, to: Vec2(topArrow.position.x, 24 * Self.inch), in: tx) }
        #expect(Self.approx(Self.box(s.model, left.id).max.z, 24 * Self.inch))
        // The flip arrows sit outside the outside face, and flip the panel.
        let c = GripService.controls(for: s.model[left.id]!, s.model, view: s.model[plan], pixel: 0.001)
        #expect(c.count == 1 && c[0].kind == .flipWall && c[0].position.x < -18 * Self.inch)
        _ = s.perform("Flip") { tx in GripService.toggle(c[0], in: tx) }
        #expect(s.model[left.id]?.furniturePanel?.flipped == true)
        // Commands: aliases, groups, and the Furniture-only gate.
        #expect(CommandCatalog.info(.furniturePanel).aliases == ["PA"] && CommandCatalog.info(.furnitureShelf).aliases == ["SH"])
        for (id, a) in [(CommandID.furnitureBack, "BK"), (.furnitureDivider, "DV"), (.furnitureLeg, "LG"), (.furnitureRail, "RL"), (.furniturePlinth, "KK")] {
            #expect(CommandCatalog.info(id).aliases == [a])
        }
        let all = CommandCatalog.all.flatMap(\.aliases)
        #expect(Set(all).count == all.count, "aliases are unique")
    }
}
