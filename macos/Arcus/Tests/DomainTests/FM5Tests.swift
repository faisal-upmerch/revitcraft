import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// FM5 (Bays, fronts and hardware): bays found between parts and following them, Bay Divide, doors, drawers and flaps
/// placed in bays with their overlay, the hinge count rule, the hardware fronts own, machining and the drawer box, and
/// Load into Project compiling fronts that flex.
@Suite("FM5 Bays, doors, drawers and hardware") @MainActor
struct FM5Tests {
    static let inch = 0.0254
    static func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }
    static func position(_ m: BIMModel, _ name: String) -> Double { FurniturePlanes.positionsByName(m)[name] ?? .nan }

    /// The sample base cabinet in a session (54" x 24" x 34 1/2", three bays: door, three drawers, door).
    static func cabinet() throws -> (DocumentSession, [String: [ElementID]]) {
        let s = DocumentSession(model: FurnitureTemplates.blank(category: .casework, name: "Base"))
        var ids: [String: ElementID] = [:]
        _ = s.perform("Carcass") { tx in ids = try FurnitureSamples.baseCabinet(in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        _ = s.perform("Interior") { tx in try FurnitureSamples.baseCabinetInterior(in: tx, ids) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        var fronts: [String: [ElementID]] = [:]
        _ = s.perform("Fronts") { tx in fronts = try FurnitureSamples.baseCabinetFronts(in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        return (s, fronts)
    }

    static func hardware(of front: ElementID, _ m: BIMModel) -> [Element] {
        m.hosted(by: front).filter { $0.category == .furnitureHardware }
    }

    // MARK: Library

    @Test func templateHasHardwareFamiliesFrontTypesAndTags() throws {
        let m = FurnitureTemplates.blank()
        let hw = m.types(for: .furnitureHardware)
        let families = Set(hw.compactMap { $0.typeData?.familyName })
        for f in [FurnitureHardware.concealedHinge, FurnitureHardware.faceFrameHinge, FurnitureHardware.buttHinge, FurnitureHardware.pianoHinge,
                  FurnitureHardware.sideMountSlide, FurnitureHardware.undermountSlide, FurnitureHardware.barPull, FurnitureHardware.knob,
                  FurnitureHardware.cupPull, FurnitureHardware.edgePull, FurnitureHardware.flapStay, FurnitureHardware.glide, FurnitureHardware.caster,
                  FurnitureHardware.shelfPin, FurnitureHardware.camLock, FurnitureHardware.dowel, FurnitureHardware.confirmat] {
            #expect(families.contains(f), "missing \(f)")
        }
        // Slides in 12"-24", bar pulls 96-192 mm, each with a cost, a kind and a model.
        let slides = hw.filter { $0.typeData?.familyName == FurnitureHardware.sideMountSlide }.map { FurnitureHardware.Values($0.typeData).slideLength / Self.inch }
        #expect(slides.sorted().map { Int($0.rounded()) } == [12, 14, 16, 18, 20, 22, 24])
        let bars = Set(hw.filter { $0.typeData?.familyName == FurnitureHardware.barPull }.map(\.name))
        #expect(bars == ["96 mm", "128 mm", "160 mm", "192 mm"])
        for t in hw {
            let v = FurnitureHardware.Values(t.typeData)
            #expect(v.kind != nil && v.cost > 0, "\(t.name)")
            #expect(t.typeData?.params[ParameterID("type.model")]?.textValue?.isEmpty == false)
        }
        let hinge = try #require(hw.first { $0.typeData?.familyName == FurnitureHardware.concealedHinge && $0.name == "Full Overlay 110°" })
        let hv = FurnitureHardware.Values(hinge.typeData)
        #expect(Self.approx(hv.cupDiameter, 0.035) && Self.approx(hv.cupDepth, 0.013) && Self.approx(hv.cupOffset, 0.0225))
        // Cost is editable in Edit Type (Identity Data), in USD.
        let cost = try #require(Parameters.typeEntries(hinge, m).first { $0.name == "Cost" })
        #expect(!cost.isReadOnly)
        // Door, drawer and flap types, and the tags.
        #expect(m.types(for: .furnitureFronts).contains { $0.typeData?.familyName == "Door" && $0.name == "Shaker - Full Overlay" })
        #expect(m.types(for: .furnitureFronts).contains { $0.typeData?.familyName == "Drawer" })
        #expect(m.types(for: .furnitureFronts).contains { $0.typeData?.familyName == "Flap" && FurnitureFrontTypes.Values($0.typeData).flapAction == .dropDown })
        #expect(m.elements(.families).contains { $0.name == "Bay Tag" && $0.family?.taggedCategories == [.furnitureBays] })
        #expect(m.elements(.families).contains { $0.name == "Front Tag" })
        // Idempotent.
        let tx = TransactionContext(model: m, name: "Again")
        FurnitureFrontTypes.ensureStandard(in: tx)
        #expect(!tx.hasChanges)
    }

    @Test func hardwareFamiliesEvaluateInEveryOrientation() throws {
        for spec in FurnitureHardware.library {
            for t in spec.family.types {
                let ev = FamilyEvaluator.evaluate(spec.family, typeName: t.name, units: UnitsSettings.imperial)
                #expect(ev.errors.isEmpty, "\(spec.family.name) \(t.name): \(ev.errors)")
                let shown = ev.solids.filter { !$0.isVoid && $0.visibleAt.contains(.fine) && !$0.familyMesh.isEmpty }
                #expect(!shown.isEmpty, "\(spec.family.name) \(t.name) shows nothing")
            }
        }
        // A hinge on a lift-up flap's top edge shows its top-edge solids only.
        let hinge = FurnitureHardware.concealed(faceFrame: false)
        let side = FamilyEvaluator.evaluate(hinge.family, typeName: "Full Overlay 110°", units: UnitsSettings.imperial)
        let top = FamilyEvaluator.evaluate(hinge.family, typeName: "Full Overlay 110°", instance: ["Top Edge": .bool(true)], units: UnitsSettings.imperial)
        #expect(side.solids.filter { !$0.familyMesh.isEmpty }.allSatisfy { $0.name.contains("Side Edge") })
        #expect(top.solids.filter { !$0.familyMesh.isEmpty }.allSatisfy { $0.name.contains("Top Edge") })
        // The cup on the side edge sits at the cup offset from the edge, 35 mm across.
        let cup = try #require(side.solids.first { $0.name.hasPrefix("Cup") && !$0.familyMesh.isEmpty })
        let b = cup.familyMesh.bounds
        #expect(Self.approx((b.min.x + b.max.x) / 2, 0.0225, 1e-3) && Self.approx(b.max.x - b.min.x, 0.035, 2e-3), "\(b)")
    }

    // MARK: Bays

    @Test func baysAreFoundBetweenPartsAndFollowThem() throws {
        let (s, ids) = try Self.cabinet()
        let m = s.model
        let t = 0.75 * Self.inch
        let left = try #require(m[ids["leftBay"]?.first]?.furnitureBay?.opening)
        let mid = try #require(m[ids["drawerBay"]?.first]?.furnitureBay?.opening)
        // The dividers sit at the thirds of the 52 1/2" inside (EQ): the end bays are 17 1/8" clear, the middle 16 3/4",
        // from the bottom's top face (4" kick + 3/4") to the top's underside.
        #expect(Self.approx(left.width, 17.125 * Self.inch, 1e-5) && Self.approx(mid.width, 16.75 * Self.inch, 1e-5), "\(left.width / Self.inch)")
        #expect(Self.approx(left.z0, 4.75 * Self.inch) && Self.approx(left.z1, (34.5 - 0.75) * Self.inch))
        #expect(Self.approx(left.x0, Self.position(m, "Left") + t))
        // The back panel bounds the depth.
        #expect(left.back != nil && Self.approx(left.y1, Self.position(m, "Back") - 0.25 * Self.inch, 1e-6))
        #expect(left.left == m.elements(.furniturePanels).first { $0.furniturePanel?.role == .panel && ($0.furniturePanel?.start.x ?? 0) < 0 }?.id)
        #expect(!left.sharedLeft && left.sharedRight, "the divider is shared, the side isn't")
        // Bay Tag text and Properties.
        let bay = try #require(m[ids["leftBay"]?.first])
        #expect(FurnitureBays.sizeText(bay.furnitureBay!) == "17 1/8\" x 29\"")
        #expect(Parameters.value(ParameterID("furniture.bay.opening"), of: bay, m)?.textValue == "17 1/8\" x 29\"")
        #expect(Parameters.descriptor(named: "Opening", for: bay, m) != nil)
        // Width 60": the bays widen (the dividers stay EQ), and the doors with them.
        let doorBefore = try #require(FurnitureFronts.geometry(m[ids["leftDoor"]![0]]!, m)).leaves[0].width
        _ = s.perform("Width") { tx in try FurnitureParameters.setValue("Width", .double(60 * Self.inch), in: tx) }
        #expect(s.lastError == nil)
        let m2 = s.model
        let left2 = try #require(m2[ids["leftBay"]?.first]?.furnitureBay?.opening)
        #expect(Self.approx(left2.width, 19.125 * Self.inch, 1e-5), "\(left2.width / Self.inch)")
        let doorAfter = try #require(FurnitureFronts.geometry(m2[ids["leftDoor"]![0]]!, m2)).leaves[0].width
        #expect(Self.approx(doorAfter - doorBefore, 2 * Self.inch, 1e-5))
        // Moving the bottom up shrinks the bays (as rooms follow walls).
        let bottom = try #require(m2.elements(.furnitureShelves).first { $0.furnitureShelf?.role == .bottom })
        _ = s.perform("Raise Bottom") { tx in tx.update(bottom.id) { $0.furnitureShelf?.elevation += 2 * Self.inch } }
        let left3 = try #require(s.model[ids["leftBay"]?.first]?.furnitureBay?.opening)
        #expect(Self.approx(left3.height, left2.height - 2 * Self.inch, 1e-5))
    }

    @Test func bayNeedsPartsRoundItAndTopBaysArePickedInPlan() throws {
        let (s, _) = try Self.cabinet()
        // A second bay in the same region is refused.
        _ = s.perform("Bay") { tx in try FurnitureBays.createBay(face: .front, at: Vec2(-18 * Self.inch, 20 * Self.inch), in: tx) }
        #expect(s.lastError?.message.contains("already") == true)
        // A box seen from above: four panels round an open top.
        let box = DocumentSession(model: FurnitureTemplates.blank(name: "Box"))
        _ = box.perform("Box") { tx in
            let l = Self.position(tx.model, "Left"), r = Self.position(tx.model, "Right"), f = Self.position(tx.model, "Front"), b = Self.position(tx.model, "Back")
            _ = try FurniturePartOperations.createPanelRectangle(Rect2(min: Vec2(l, f), max: Vec2(r, b)), extent: PartExtent(), in: tx)
        }
        var bay: ElementID?
        _ = box.perform("Bay") { tx in bay = try FurnitureBays.createBay(face: .top, at: .zero, in: tx) }
        #expect(box.lastError == nil, "\(box.lastError?.message ?? "")")
        let o = try #require(box.model[bay]?.furnitureBay?.opening)
        #expect(Self.approx(o.z1, Self.position(box.model, "Top")) && o.width > 0 && o.depth > 0)
        // A lid on it: a flap seen from above, hinged at the back.
        _ = box.perform("Lid") { tx in _ = try FurnitureFronts.createFront(.flap, in: bay!, in: tx) }
        #expect(box.lastError == nil, "\(box.lastError?.message ?? "")")
        let lid = try #require(box.model.elements(.furnitureFronts).first)
        let g = try #require(FurnitureFronts.geometry(lid, box.model))
        #expect(g.face == .top && g.leaves[0].hinge == .back && Self.approx(g.leaves[0].w.0.value, o.z1))
        #expect(FurnitureFronts.hardware(lid, box.model).contains { $0.values["Back Edge"]?.boolValue == true })
    }

    @Test func separatorsSplitBays() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank(name: "Open"))
        var ids: [String: ElementID] = [:]
        _ = s.perform("Carcass") { tx in ids = try FurnitureSamples.baseCabinet(in: tx, width: 30) }
        _ = s.perform("Separator") { tx in
            _ = try FurnitureBays.createSeparator(face: .front, from: Vec2(-1, 20 * Self.inch), to: Vec2(1, 20.1 * Self.inch), in: tx)
        }
        #expect(s.lastError == nil)
        let sep = try #require(s.model.elements(.furnitureBaySeparators).first?.furnitureBaySeparator)
        #expect(sep.start.y == sep.end.y, "snapped horizontal")
        var lower: ElementID?, upper: ElementID?
        _ = s.perform("Bays") { tx in
            lower = try FurnitureBays.createBay(face: .front, at: Vec2(0, 10 * Self.inch), in: tx)
            upper = try FurnitureBays.createBay(face: .front, at: Vec2(0, 30 * Self.inch), in: tx)
        }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let lo = try #require(s.model[lower]?.furnitureBay?.opening), up = try #require(s.model[upper]?.furnitureBay?.opening)
        #expect(Self.approx(lo.z1, 20 * Self.inch) && Self.approx(up.z0, 20 * Self.inch) && lo.sharedHigh && up.sharedLow)
        _ = ids
    }

    // MARK: Bay Divide

    @Test func bayDivideMakesEqualOrSizedCells() throws {
        let (s, ids) = try Self.cabinet()
        let m = s.model
        let mid = try #require(ids["drawerBay"]?.first)
        let cells = FurnitureBays.cellIDs(of: mid, m)
        #expect(cells.count == 3)
        let parent = try #require(m[mid]?.furnitureBay?.opening)
        let hs = cells.compactMap { m[$0]?.furnitureBay?.opening?.height }
        #expect(hs.count == 3 && hs.allSatisfy { Self.approx($0, parent.height / 3, 1e-6) })
        #expect(m[cells[0]]?.name == "Bay 2.1" && m[cells[2]]?.furnitureBay?.number == "2.3")
        // By dimension: a 6" bottom drawer, the rest share what's left.
        _ = s.perform("Divide") { tx in try FurnitureBays.divide(mid, BayDivision(direction: .rows, layout: .fixed, count: 3, sizes: [6 * Self.inch]), in: tx) }
        #expect(s.lastError == nil)
        let c2 = FurnitureBays.cellIDs(of: mid, s.model).compactMap { s.model[$0]?.furnitureBay?.opening?.height }
        #expect(Self.approx(c2[0], 6 * Self.inch) && Self.approx(c2[1], (parent.height - 6 * Self.inch) / 2, 1e-6))
        // Fewer cells: the extra sub-bay and its drawer go.
        _ = s.perform("Two") { tx in try FurnitureBays.divide(mid, BayDivision(direction: .rows, count: 2), in: tx) }
        #expect(FurnitureBays.cellIDs(of: mid, s.model).count == 2)
        #expect(s.model.elements(.furnitureFronts).filter { $0.furnitureFront?.kind == .drawer }.count == 2)
        // Properties: Number of Cells.
        let bay = try #require(s.model[mid])
        _ = s.perform("Cells") { tx in try Parameters.set(ParameterID("furniture.bay.cells"), to: .int(4), on: bay.id, in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        #expect(FurnitureBays.cellIDs(of: mid, s.model).count == 4)
    }

    // MARK: Fronts

    @Test func doorsDrawersAndOverlays() throws {
        let (s, ids) = try Self.cabinet()
        let m = s.model
        let t = 0.75 * Self.inch, r = 0.125 * Self.inch, er = 0.0625 * Self.inch
        let door = try #require(m[ids["leftDoor"]?.first])
        let g = try #require(FurnitureFronts.geometry(door, m))
        let o = g.opening
        // Full overlay: over the side's outside face less the edge reveal, to the divider's middle less half the reveal.
        #expect(Self.approx(g.leaves[0].u.0.value, o.outer0 + er) && Self.approx(g.leaves[0].u.1.value, (o.x1 + o.outer1) / 2 - r / 2))
        #expect(Self.approx(g.leaves[0].w.1.value, o.y0) && Self.approx(g.leaves[0].w.0.value, o.y0 - t), "in front of the carcass")
        #expect(g.leaves[0].hinge == .left)
        #expect(door.mark == "D1" && m[ids["rightDoor"]?.first]?.mark == "D2")
        let right = try #require(FurnitureFronts.geometry(m[ids["rightDoor"]![0]]!, m))
        #expect(right.leaves[0].hinge == .right)
        // Drawers: three, numbered, covering half the shared lines between them.
        let drawers = ids["drawers"] ?? []
        #expect(drawers.count == 3 && m[drawers[0]]?.mark == "DW1")
        let d0 = try #require(FurnitureFronts.geometry(m[drawers[0]]!, m)), d1 = try #require(FurnitureFronts.geometry(m[drawers[1]]!, m))
        #expect(Self.approx(d1.leaves[0].v.0.value - d0.leaves[0].v.1.value, r, 1e-9), "a reveal between drawers")
        // Inset: inside the opening with the reveal round it, flush with the front.
        let inset = try #require(m.types(for: .furnitureFronts).first { $0.typeData?.familyName == "Door" && $0.name == "Slab - Inset" })
        _ = s.perform("Inset") { tx in tx.update(door.id) { $0.typeID = inset.id } }
        let gi = try #require(FurnitureFronts.geometry(s.model[door.id]!, s.model))
        let ri = FurnitureFrontTypes.Values(inset.typeData).reveal
        #expect(Self.approx(gi.leaves[0].u.0.value, o.x0 + ri) && Self.approx(gi.leaves[0].w.0.value, o.y0))
        // A pair: two leaves hinged on the outside edges.
        let pair = try #require(s.model.types(for: .furnitureFronts).first { $0.name == "Slab - Full Overlay Pair" })
        _ = s.perform("Pair") { tx in tx.update(door.id) { $0.typeID = pair.id } }
        let gp = try #require(FurnitureFronts.geometry(s.model[door.id]!, s.model))
        #expect(gp.leaves.count == 2 && gp.leaves[0].hinge == .left && gp.leaves[1].hinge == .right)
        #expect(Self.approx(gp.leaves[1].u.0.value - gp.leaves[0].u.1.value, r))
        // One front per bay.
        _ = s.perform("Another") { tx in _ = try FurnitureFronts.createFront(.door, in: ids["leftBay"]![0], in: tx) }
        #expect(s.lastError?.message.contains("already") == true)
    }

    @Test func frontsHaveSolidsIncludingTheShakerFrame() throws {
        let (s, ids) = try Self.cabinet()
        let door = try #require(ids["leftDoor"]?.first)
        let slab = FurnitureFrontSolids.meshParts(s.model[door]!, s.model, detail: .fine)
        #expect(slab.count == 1)
        let shaker = try #require(s.model.types(for: .furnitureFronts).first { $0.typeData?.familyName == "Door" && $0.name == "Shaker - Full Overlay" })
        _ = s.perform("Shaker") { tx in tx.update(door) { $0.typeID = shaker.id } }
        let parts = FurnitureFrontSolids.solids(s.model[door]!, s.model, PartSolidContext(symbolic: false))
        let names = parts.solids.filter { $0.visibleAt.contains(.fine) }.map(\.name)
        #expect(names.contains { $0.hasSuffix("Left Stile") } && names.contains { $0.hasSuffix("Top Rail") } && names.contains { $0.hasSuffix("Panel") }, "\(names)")
        #expect(FurnitureFrontSolids.meshParts(s.model[door]!, s.model, detail: .fine).count == 5)
        #expect(FurnitureFrontSolids.meshParts(s.model[door]!, s.model, detail: .coarse).count == 1)
        // Glass and louvered.
        for name in ["Glass Panel - Full Overlay", "Louvered - Full Overlay"] {
            let t = try #require(s.model.types(for: .furnitureFronts).first { $0.name == name })
            _ = s.perform(name) { tx in tx.update(door) { $0.typeID = t.id } }
            #expect(FurnitureFrontSolids.meshParts(s.model[door]!, s.model, detail: .fine).count >= 5, "\(name)")
        }
        // A drawer has its box at Medium and Fine.
        let drawer = try #require(ids["drawers"]?.first)
        #expect(FurnitureFrontSolids.meshParts(s.model[drawer]!, s.model, detail: .fine).count == 6)
        #expect(FurnitureFrontSolids.meshParts(s.model[drawer]!, s.model, detail: .coarse).count == 1)
        #expect(ElementMeshes.hasModelGeometry(s.model[drawer]!))
    }

    // MARK: Hardware

    @Test func hingeCountRule() {
        let i = Self.inch
        #expect(FurnitureFronts.hingeCount(edgeLength: 30 * i) == 2)
        #expect(FurnitureFronts.hingeCount(edgeLength: 40 * i) == 2)
        #expect(FurnitureFronts.hingeCount(edgeLength: 41 * i) == 3)
        #expect(FurnitureFronts.hingeCount(edgeLength: 60 * i) == 3)
        #expect(FurnitureFronts.hingeCount(edgeLength: 72 * i) == 4)
        #expect(FurnitureFronts.hingeCount(edgeLength: 90 * i) == 5)
        let p = FurnitureFronts.hingePositions(0, 30 * i, count: 2, inset: 3 * i)
        #expect(Self.approx(p[0], 3 * i) && Self.approx(p[1], 27 * i))
        let q = FurnitureFronts.hingePositions(0, 50 * i, count: 3, inset: 3 * i)
        #expect(Self.approx(q[1], 25 * i))
    }

    @Test func frontsOwnTheirHardware() throws {
        let (s, ids) = try Self.cabinet()
        let m = s.model
        let door = try #require(ids["leftDoor"]?.first)
        let hw = Self.hardware(of: door, m)
        let hinges = hw.filter { FurnitureHardware.values(of: $0, m).kind == .hinge }
        let handles = hw.filter { FurnitureHardware.values(of: $0, m).kind == .handle }
        #expect(hinges.count == 2 && handles.count == 1, "\(hw.map(\.name))")
        #expect(hw.allSatisfy { $0.params[FurnitureHardware.ownerParam]?.refValue == door && $0.hostID == door })
        // The hinges sit on the hinge edge, 3" from the ends.
        let g = try #require(FurnitureFronts.geometry(m[door]!, m))
        let zs = hinges.compactMap { $0.component.map { $0.offset } }.sorted()
        #expect(Self.approx(zs[0], g.leaves[0].v.0.value + 3 * Self.inch) && Self.approx(zs[1], g.leaves[0].v.1.value - 3 * Self.inch))
        #expect(hinges.allSatisfy { Self.approx($0.component?.location.x, g.leaves[0].u.0.value) && $0.component?.mirrored == false })
        // The handle: a vertical bar pull near the top, by the edge away from the hinges.
        let h = try #require(handles.first)
        #expect(h.params[Parameters.familyParamID("Vertical")]?.boolValue == true)
        #expect(Self.approx(h.component?.location.x, g.leaves[0].u.1.value - 2.5 * Self.inch))
        // A drawer: a slide pair of the longest length that fits, and a horizontal handle.
        let drawer = try #require(ids["drawers"]?.first)
        let dh = Self.hardware(of: drawer, m)
        let slides = try #require(dh.first { FurnitureHardware.values(of: $0, m).kind == .slide })
        // 23 3/4" from the carcass front to the back panel: a 22" slide (and its 1/2" rear clearance) fits.
        #expect(m[slides.typeID]?.name == "22\"", "\(m[slides.typeID]?.name ?? "")")
        #expect(dh.first { FurnitureHardware.values(of: $0, m).kind == .handle }?.params[Parameters.familyParamID("Vertical")]?.boolValue == false)
        // Hardware shows in 3D at Medium and Fine, not Coarse.
        #expect(!ElementMeshes.parts(h, m, detail: .fine).isEmpty && ElementMeshes.parts(h, m, detail: .coarse).isEmpty)
        // Flipping the hinge side moves the hinges to the other edge, mirrored.
        _ = s.perform("Flip") { tx in tx.update(door) { $0.furnitureFront?.hingeFlipped.toggle() } }
        let flipped = Self.hardware(of: door, s.model).filter { FurnitureHardware.values(of: $0, s.model).kind == .hinge }
        let g2 = try #require(FurnitureFronts.geometry(s.model[door]!, s.model))
        #expect(flipped.count == 2 && flipped.allSatisfy { Self.approx($0.component?.location.x, g2.leaves[0].u.1.value) && $0.component?.mirrored == true })
        // A taller door gets more hinges.
        _ = s.perform("Height") { tx in try FurnitureParameters.setValue("Height", .double(72 * Self.inch), in: tx) }
        #expect(Self.hardware(of: door, s.model).filter { FurnitureHardware.values(of: $0, s.model).kind == .hinge }.count == 4)
        // Swap the handle from the front's Properties.
        let knob = try #require(FurnitureHardware.type(FurnitureHardware.knob, "1 1/4\"", s.model))
        _ = s.perform("Handle") { tx in try Parameters.set(ParameterID("furniture.front.handle"), to: .ref(knob), on: door, in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        #expect(Self.hardware(of: door, s.model).contains { $0.typeID == knob })
        // Or with the Type Selector on the owned handle: the front adopts it.
        let bar = try #require(FurnitureHardware.type(FurnitureHardware.barPull, "192 mm", s.model))
        let handle = try #require(Self.hardware(of: door, s.model).first { $0.typeID == knob })
        _ = s.perform("Type") { tx in tx.update(handle.id) { $0.typeID = bar } }
        #expect(s.model[door]?.furnitureFront?.handleTypeID == bar && Self.hardware(of: door, s.model).contains { $0.typeID == bar })
        // A handle type that isn't a handle is refused.
        let hingeType = try #require(FurnitureHardware.type(FurnitureHardware.concealedHinge, "Inset 110°", s.model))
        _ = s.perform("Bad") { tx in try Parameters.set(ParameterID("furniture.front.handle"), to: .ref(hingeType), on: door, in: tx) }
        #expect(s.lastError != nil)
        // Deleting the front deletes its hardware.
        let owned = Self.hardware(of: door, s.model).map(\.id)
        _ = s.perform("Delete") { tx in tx.delete(door) }
        #expect(owned.allSatisfy { s.model[$0] == nil })
        // Instances carry Count and their type's Cost for the Hardware Schedule.
        let any = try #require(s.model.elements(.furnitureHardware).first)
        #expect(Parameters.value(ParameterID("furniture.hardware.count"), of: any, s.model)?.intValue == 1)
        #expect((Parameters.value(ParameterID("type.cost"), of: s.model[any.typeID]!, s.model)?.doubleValue ?? 0) > 0)
    }

    @Test func manualHardwareStaysPut() throws {
        let (s, _) = try Self.cabinet()
        let glide = try #require(FurnitureHardware.type(FurnitureHardware.glide, "1\" Leveler", s.model))
        var id: ElementID?
        _ = s.perform("Glide") { tx in id = tx.create(.furnitureHardware, data: .component(ComponentData(location: Vec2(0.3, -0.2))), typeID: glide, levelID: tx.model.levels.first?.id) }
        _ = s.perform("Width") { tx in try FurnitureParameters.setValue("Width", .double(48 * Self.inch), in: tx) }
        #expect(s.model[id] != nil && s.model[id]?.component?.location == Vec2(0.3, -0.2))
    }

    // MARK: Machining and derived parts

    @Test func machiningFromHardware() throws {
        let (s, ids) = try Self.cabinet()
        let m = s.model
        let door = try #require(ids["leftDoor"]?.first)
        let ops = FurnitureMachining.entries(m)
        let cups = ops.filter { $0.partID == door && $0.label.hasPrefix("Hinge cup") }
        #expect(cups.count == 2)
        let g = try #require(FurnitureFronts.geometry(m[door]!, m))
        for c in cups {
            guard case .drill(let center, let axis, let dia, let depth) = c.op else { Issue.record("not a drill"); continue }
            #expect(Self.approx(dia, 0.035) && Self.approx(depth, 0.013))
            #expect(Self.approx(center.x, g.leaves[0].u.0.value + 0.0225) && Self.approx(center.y, g.innerFace) && Self.approx(axis.y, -1))
            if case .hardware(let h) = c.source { #expect(m[h]?.hostID == door) } else { Issue.record("cup source") }
        }
        // Plate screws in the left side's inside face.
        let side = try #require(g.opening.left)
        let plate = ops.filter { $0.partID == side && $0.label == "Hinge plate screw" }
        #expect(plate.count == 4)
        if case .drill(let c, let a, _, _)? = plate.first?.op { #expect(Self.approx(c.x, g.opening.x0) && Self.approx(a.x, -1) && Self.approx(c.y, g.opening.y0 + 0.037)) }
        // Handle holes through the door (128 mm bar pull: two holes).
        let holes = ops.filter { $0.partID == door && $0.label.hasPrefix("Handle hole") }
        #expect(holes.count == 2)
        if case .drill(_, let a, _, let depth)? = holes.first?.op { #expect(Self.approx(a.y, 1) && Self.approx(depth, g.thickness)) }
        // Slide screws in both sides of the drawer bay.
        let drawer = try #require(ids["drawers"]?.first)
        let dg = try #require(FurnitureFronts.geometry(m[drawer]!, m))
        let slideOps = ops.filter { $0.label == "Slide screw" && ($0.partID == dg.opening.left || $0.partID == dg.opening.right) }
        #expect(slideOps.count >= 6 && Set(slideOps.map(\.partID)).count == 2)
    }

    @Test func drawerBoxesAreSizedFromTheBayAndSlides() throws {
        let (s, ids) = try Self.cabinet()
        let m = s.model
        let drawer = try #require(ids["drawers"]?.first)
        let o = try #require(FurnitureFronts.geometry(m[drawer]!, m)?.opening)
        let parts = FurnitureMachining.derivedParts(m).filter { $0.sourceID == drawer }
        let side = try #require(parts.first { $0.name.hasSuffix("Box Side") })
        let bottom = try #require(parts.first { $0.name.hasSuffix("Box Bottom") })
        let box = try #require(FurnitureFronts.drawerBox(m[drawer]!, m))
        // Undermount slides: 5/16" each side; the box is as long as the slide (22" in a 23 3/4" deep bay).
        #expect(Self.approx(box.width, o.width - 2 * 0.3125 * Self.inch) && Self.approx(box.depth, 22 * Self.inch))
        #expect(Self.approx(side.length, 22 * Self.inch) && side.quantity == 2 && Self.approx(side.thickness, 0.5 * Self.inch))
        #expect(Self.approx(bottom.width, box.width - 2 * 0.5 * Self.inch + 2 * 0.25 * Self.inch))
        #expect(parts.contains { $0.name.hasSuffix("Drawer Front") })
        // Side-mount slides need 1/2" a side.
        let sm = try #require(m.types(for: .furnitureFronts).first { $0.name == "Slab - Full Overlay Side Mount" })
        _ = s.perform("Side Mount") { tx in tx.update(drawer) { $0.typeID = sm.id } }
        let b2 = try #require(FurnitureFronts.drawerBox(s.model[drawer]!, s.model))
        #expect(Self.approx(b2.width, o.width - 1 * Self.inch))
        #expect(Self.hardware(of: drawer, s.model).contains { s.model[$0.typeID]?.typeData?.familyName == FurnitureHardware.sideMountSlide })
        // A shaker door is five pieces on the cut list.
        let shaker = try #require(s.model.types(for: .furnitureFronts).first { $0.typeData?.familyName == "Door" && $0.name == "Shaker - Full Overlay" })
        let door = try #require(ids["leftDoor"]?.first)
        _ = s.perform("Shaker") { tx in tx.update(door) { $0.typeID = shaker.id } }
        let dp = FurnitureMachining.derivedParts(s.model).filter { $0.sourceID == door }
        #expect(dp.reduce(0) { $0 + $1.quantity } == 5, "\(dp.map(\.name))")
    }

    // MARK: Compile

    @Test func compiledCabinetFlexesWithItsFronts() throws {
        let (s, ids) = try Self.cabinet()
        let m = s.model
        let f = FurnitureCompiler.family(from: m)
        let doorMark = try #require(m[ids["leftDoor"]?.first]?.mark)
        #expect(f.solids.contains { $0.name == doorMark })
        #expect(f.nestedFamilies.contains { $0.name == FurnitureHardware.concealedHinge } && f.nestedFamilies.contains { $0.name == FurnitureHardware.undermountSlide })
        #expect(f.nestedInstances.filter { $0.familyName == FurnitureHardware.concealedHinge }.count == 4)
        #expect(f.planLines.contains { $0.subcategory == .swing } && f.modelLines.contains { $0.subcategory == .elevationSwing })
        // Fronts at Medium and Fine; the drawer boxes at Fine only.
        #expect(f.solids.filter { $0.name == doorMark }.allSatisfy { $0.visibleAt == [.medium, .fine] })
        #expect(f.solids.filter { $0.name.contains("Box Side") }.allSatisfy { $0.visibleAt == [.fine] })
        // Flex: Width 60" and Height 40" in the family resize the door and the drawers.
        let type = try #require(f.types.first?.name)
        func box(_ ev: EvaluatedFamily, _ name: String) -> Box3? { ev.solids.first { $0.name == name }?.bounds }
        let ev = FamilyEvaluator.evaluate(f, typeName: type, units: m.units)
        #expect(ev.errors.isEmpty, "\(ev.errors)")
        #expect(FamilyEvaluator.flexTest(f, units: m.units).isEmpty, "\(FamilyEvaluator.flexTest(f, units: m.units).prefix(5))")
        var big = f
        big.types[0].values["Width"] = .double(60 * Self.inch)
        big.types[0].values["Height"] = .double(40.5 * Self.inch)
        let ev2 = FamilyEvaluator.evaluate(big, typeName: type, units: m.units)
        #expect(ev2.errors.isEmpty, "\(ev2.errors)")
        let d1 = try #require(box(ev, doorMark)), d2 = try #require(box(ev2, doorMark))
        // The door keeps to the side's outside face (less the 1/16" edge reveal) and the divider's middle (less half the
        // 1/8" reveal) as they move.
        let side = try #require(box(ev2, m[m.elements(.furniturePanels).first { $0.furniturePanel?.role == .panel && ($0.furniturePanel?.start.x ?? 0) < 0 }?.id]?.mark ?? ""))
        let divider = try #require(m.elements(.furniturePanels).filter { $0.furniturePanel?.role == .divider }.compactMap { box(ev2, $0.mark) }.min { $0.min.x < $1.min.x })
        #expect(Self.approx(d2.min.x, side.min.x + 0.0625 * Self.inch, 1e-5) && Self.approx(d2.max.x, (divider.min.x + divider.max.x) / 2 - 0.0625 * Self.inch, 1e-5),
                "door \(d2) side \(side) divider \(divider)")
        #expect(d2.max.x - d2.min.x > d1.max.x - d1.min.x + 2 * Self.inch, "door width \(d1) → \(d2)")
        #expect(Self.approx((d2.max.z - d2.min.z) - (d1.max.z - d1.min.z), 6 * Self.inch, 1e-4), "door height")
        let dw = try #require(m[ids["drawers"]?.first]?.mark)
        let w1 = try #require(box(ev, dw)), w2 = try #require(box(ev2, dw))
        #expect(Self.approx((w2.max.z - w2.min.z) - (w1.max.z - w1.min.z), 2 * Self.inch, 1e-4), "drawer height follows the EQ lines")
        // The hinges follow the door's top and bottom.
        let hinges1 = ev.solids.filter { $0.name.hasPrefix(FurnitureHardware.concealedHinge) && $0.name.contains("Plate") && !$0.familyMesh.isEmpty }
        let hinges2 = ev2.solids.filter { $0.name.hasPrefix(FurnitureHardware.concealedHinge) && $0.name.contains("Plate") && !$0.familyMesh.isEmpty }
        #expect(hinges1.count == 4 && hinges2.count == 4)
        let top1 = hinges1.map { $0.familyMesh.bounds.max.z }.max() ?? 0, top2 = hinges2.map { $0.familyMesh.bounds.max.z }.max() ?? 0
        #expect(Self.approx(top2 - top1, 6 * Self.inch, 1e-4))
    }

    @Test func roundTripsThroughCodable() throws {
        let (s, _) = try Self.cabinet()
        let data = try JSONEncoder().encode(s.model.allElements)
        let back = try JSONDecoder().decode([Element].self, from: data)
        #expect(back.count == s.model.allElements.count)
        #expect(back.contains { $0.furnitureBay?.division != nil } && back.contains { $0.furnitureFront?.kind == .drawer })
    }
}
