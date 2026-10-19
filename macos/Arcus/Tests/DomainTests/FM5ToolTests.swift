import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// FM5: the Openings tools driven as the canvas drives them: Bay with Tag on Placement, Bay Separator, Bay Divide, Door
/// (Space flips the hinge), Drawer with Number, Hardware, Pick New Host, and the hinge flip control and Space on a
/// selected door.
@Suite("FM5 Openings tools") @MainActor
struct FM5ToolTests {
    static let inch = 0.0254

    static func click(_ tool: some InteractiveTool, _ p: Vec2) {
        let i = ToolInput(point: p, rawPoint: p)
        tool.pointerMoved(i)
        tool.pointerDown(i)
        tool.pointerUp(i)
    }

    /// The base cabinet's carcass only (no bays yet), and its Front elevation's context.
    static func carcass() throws -> (DocumentSession, ToolContext, FurnitureSketchMap) {
        let s = DocumentSession(model: FurnitureTemplates.blank(category: .casework, name: "Base"))
        var ids: [String: ElementID] = [:]
        _ = s.perform("Carcass") { tx in ids = try FurnitureSamples.baseCabinet(in: tx) }
        _ = s.perform("Interior") { tx in try FurnitureSamples.baseCabinetInterior(in: tx, ids) }
        let front = try #require(s.model.views.first { $0.view?.kind == .elevation && $0.name == "Front" })
        let ctx = ToolContext(session: s, viewID: front.id)
        ctx.pixel = 0.001
        return (s, ctx, try #require(FurnitureSketchMap.of(front.view)))
    }

    @Test func bayToolPlacesTaggedBaysLikeRooms() throws {
        let (s, ctx, map) = try Self.carcass()
        let tool = FurnitureBayTool(ctx: ctx)
        #expect(tool.options.map(\.id) == ["tag"] && tool.prompt.contains("bounded by parts"))
        let p = map.toView(Vec2(-18 * Self.inch, 20 * Self.inch))
        tool.pointerMoved(ToolInput(point: p, rawPoint: p))
        #expect(!tool.preview.primitives.isEmpty && tool.preview.highlight.count >= 3, "the region and the parts round it")
        Self.click(tool, p)
        let bay = try #require(s.model.elements(.furnitureBays).first)
        #expect(bay.name == "Bay 1")
        let tag = try #require(s.model.elements(.tags).first { $0.tag?.taggedID == bay.id })
        #expect(tag.ownerViewID == ctx.viewID && s.model[tag.typeID]?.typeData?.familyName == "Bay Tag")
        // Clicking it again is refused, with the reason.
        Self.click(tool, p)
        #expect(s.model.elements(.furnitureBays).count == 1 && s.lastError?.message.contains("already") == true)
        // Plans have no front bays, but take top-access ones; Left/Right elevations take none.
        let plan = ToolContext(session: s, viewID: try #require(s.model.views.first { $0.view?.kind == .floorPlan }).id)
        #expect(FurnitureBayTool(ctx: plan).prompt.contains("top-access"))
    }

    @Test func doorDrawerAndFlapToolsPlaceInBays() throws {
        let (s, ctx, map) = try Self.carcass()
        let bay = FurnitureBayTool(ctx: ctx)
        bay.tagOnPlacement = false
        let i = Self.inch
        for x in [-18.0, 0, 18] { Self.click(bay, map.toView(Vec2(x * i, 20 * i))) }
        #expect(s.model.elements(.furnitureBays).count == 3)
        // Door: Space flips the hinge before placing.
        let door = FurnitureFrontTool(ctx: ctx, kind: .door)
        #expect(door.options.map(\.id) == ["hinge", "tag"])
        door.pointerMoved(ToolInput(point: map.toView(Vec2(18 * i, 20 * i)), rawPoint: map.toView(Vec2(18 * i, 20 * i))))
        #expect(!door.preview.primitives.isEmpty)
        door.spaceBar()
        door.tagOnPlacement = true
        Self.click(door, map.toView(Vec2(18 * i, 20 * i)))
        let d = try #require(s.model.elements(.furnitureFronts).first)
        #expect(d.furnitureFront?.hingeFlipped == true && s.model.elements(.tags).contains { $0.tag?.taggedID == d.id })
        // Drawer: Number 3 stacks three drawers (EQ) in the middle bay.
        let drawer = FurnitureFrontTool(ctx: ctx, kind: .drawer)
        drawer.setOption("count", .int(3))
        Self.click(drawer, map.toView(Vec2(0, 20 * i)))
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        #expect(s.model.elements(.furnitureFronts).filter { $0.furnitureFront?.kind == .drawer }.count == 3)
        // Flap in the left bay (lift-up by default).
        Self.click(FurnitureFrontTool(ctx: ctx, kind: .flap), map.toView(Vec2(-18 * i, 20 * i)))
        let flap = try #require(s.model.elements(.furnitureFronts).first { $0.furnitureFront?.kind == .flap })
        #expect(FurnitureFronts.geometry(flap, s.model)?.leaves.first?.hinge == .top)
        #expect(FurnitureFronts.hardware(flap, s.model).contains { $0.slot.hasPrefix("stay") })
        // Pick New Host: the flap moves to... a full bay is refused.
        let pick = FurniturePickBayTool(ctx: ctx, purpose: .newHost([flap.id]))
        Self.click(pick, map.toView(Vec2(18 * i, 20 * i)))
        #expect(s.lastError?.message.contains("already") == true)
    }

    @Test func bayDivideToolAndSeparator() throws {
        let (s, ctx, map) = try Self.carcass()
        let i = Self.inch
        let bay = FurnitureBayTool(ctx: ctx)
        Self.click(bay, map.toView(Vec2(0, 20 * i)))
        let divide = FurnitureBayDivideTool(ctx: ctx)
        divide.setOption("direction", .text("Rows"))
        divide.setOption("count", .int(4))
        divide.pointerMoved(ToolInput(point: map.toView(Vec2(0, 20 * i)), rawPoint: map.toView(Vec2(0, 20 * i))))
        #expect(divide.preview.primitives.count == 4, "the outline and three lines")
        Self.click(divide, map.toView(Vec2(0, 20 * i)))
        let parent = try #require(s.model.elements(.furnitureBays).first { $0.furnitureBay?.parentID == nil && $0.furnitureBay?.division != nil })
        #expect(FurnitureBays.cellIDs(of: parent.id, s.model).count == 4)
        // A separator across the left bay makes two bays there.
        let sep = FurnitureBaySeparatorTool(ctx: ctx)
        Self.click(sep, map.toView(Vec2(-26 * i, 18 * i))); Self.click(sep, map.toView(Vec2(-9.5 * i, 18.2 * i)))
        #expect(s.model.elements(.furnitureBaySeparators).count == 1)
        Self.click(bay, map.toView(Vec2(-18 * i, 10 * i))); Self.click(bay, map.toView(Vec2(-18 * i, 25 * i)))
        let lower = try #require(s.model.elements(.furnitureBays).first { $0.furnitureBay?.opening.map { abs($0.z1 - 18 * i) < 1e-6 } == true })
        #expect(lower.furnitureBay?.opening?.sharedHigh == true)
        // Separator grips: the end stays square to the piece.
        let g = GripService.grips(for: s.model.elements(.furnitureBaySeparators)[0], s.model, viewKind: .elevation, viewID: ctx.viewID)
        #expect(g.count == 2)
    }

    @Test func hardwareToolAndDoorControls() throws {
        let (s, ctx, map) = try Self.carcass()
        let i = Self.inch
        Self.click(FurnitureBayTool(ctx: ctx), map.toView(Vec2(-18 * i, 20 * i)))
        Self.click(FurnitureFrontTool(ctx: ctx, kind: .door), map.toView(Vec2(-18 * i, 20 * i)))
        let door = try #require(s.model.elements(.furnitureFronts).first)
        // A knob placed by hand on the door's face stays where it's put.
        let knob = try #require(FurnitureHardware.type(FurnitureHardware.knob, "1 1/4\"", s.model))
        ctx.currentTypes[.furnitureHardware] = knob
        let hw = FurnitureHardwareTool(ctx: ctx)
        Self.click(hw, map.toView(Vec2(-20 * i, 10 * i)))
        let placed = try #require(s.model.elements(.furnitureHardware).first { $0.params[FurnitureHardware.slotParam] == nil })
        let g = try #require(FurnitureFronts.geometry(door, s.model))
        #expect(placed.typeID == knob && abs((placed.component?.location.y ?? 0) - g.outerFace) < 1e-9)
        // The door's flip control under it in the Front elevation flips the hinge, as a door's hand.
        let view = s.model[ctx.viewID]
        let controls = GripService.controls(for: door, s.model, view: view, pixel: 0.001)
        let flip = try #require(controls.first { $0.kind == .flipHand })
        _ = s.perform("Flip") { tx in GripService.toggle(flip, in: tx) }
        #expect(s.model[door.id]?.furnitureFront?.hingeFlipped == true)
    }
}
