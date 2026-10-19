import Foundation
import ArcusGeometry
import ArcusDomain

// FM3D: how each Furniture tool takes the pointer in a 3D view (drawing on the work plane, or picking what's under the
// pointer), the depth it draws at (its part's height, so the sketch shows where the part goes), and how it takes the
// 3D work plane as its placement plane: a panel or leg stands on it (Base), a shelf or top is set to it (Height Offset
// from), a rail runs on it (Height from / Depth from), slats and cushions sit on it.

extension FurniturePlacement3D {
    /// The tool's binding of the work plane when it lies square to `axis` (the axis the tool's offset runs along).
    @MainActor func binding(along axis: FamilyAxis, _ m: BIMModel) -> (name: String, offset: Double)? {
        guard self.axis == axis else { return nil }
        return planeBinding(m)
    }
}

/// The position of a plane-and-offset option, or the offset alone without a plane.
@MainActor func fm3dPosition(_ plane: String?, _ offset: Double, _ m: BIMModel) -> Double {
    (plane.flatMap { FurniturePlanes.positionsByName(m)[$0] } ?? 0) + offset
}

extension FurniturePanelTool: FurnitureTool3D {
    public var fm3dDepth: Double? { map?.plane == .xy ? extent.resolve(ctx.model).base : nil }
    public var fm3dBusy: Bool { start != nil }
    public func fm3dAdopt(_ p: FurniturePlacement3D) {
        guard map?.plane == .xy, let b = p.binding(along: .z, ctx.model) else { return }
        extent.basePlane = b.name
        extent.baseOffset = b.offset
        // A top constraint at or below the new base: Unconnected, keeping the height.
        let r = extent.resolve(ctx.model)
        if extent.topPlane != nil, r.top - r.base < Tolerance.length { extent.topPlane = nil }
        rebuild()
    }
}

extension FurnitureBackTool: FurnitureTool3D { public var fm3dPicks: Bool { true } }
extension FurnitureDividerTool: FurnitureTool3D { public var fm3dPicks: Bool { true } }
extension FurniturePlinthTool: FurnitureTool3D { public var fm3dPicks: Bool { true } }
extension FurnitureEdgeProfileTool: FurnitureTool3D { public var fm3dPicks: Bool { true } }
extension FurnitureAttachTool: FurnitureTool3D { public var fm3dPicks: Bool { true } }
extension FurnitureBayTool: FurnitureTool3D { public var fm3dPicks: Bool { true } }
extension FurnitureBayDivideTool: FurnitureTool3D { public var fm3dPicks: Bool { true } }
extension FurnitureFrontTool: FurnitureTool3D { public var fm3dPicks: Bool { true } }
extension FurnitureHardwareTool: FurnitureTool3D { public var fm3dPicks: Bool { true } }
extension FurniturePickBayTool: FurnitureTool3D { public var fm3dPicks: Bool { true } }

extension FurnitureBaySeparatorTool: FurnitureTool3D {
    public var fm3dBusy: Bool { start != nil }
}

extension FurniturePanelOpeningTool: FurnitureTool3D {
    /// The panel is picked first; its corners are then drawn on its face.
    public var fm3dPicks: Bool { panelID == nil }
    public var fm3dBusy: Bool { panelID != nil }
}

extension FurnitureLegTool: FurnitureTool3D {
    public var fm3dPicks: Bool { mode == .corners }
    public var fm3dDepth: Double? { mode == .point ? extent.resolve(ctx.model).base : nil }
    public func fm3dAdopt(_ p: FurniturePlacement3D) {
        guard let b = p.binding(along: .z, ctx.model) else { return }
        extent.basePlane = b.name
        extent.baseOffset = mode == .point ? b.offset : 0
        let r = extent.resolve(ctx.model)
        if extent.topPlane != nil, r.top - r.base < Tolerance.length { extent.topPlane = nil }
    }
}

extension FurnitureRailTool: FurnitureTool3D {
    public var fm3dDepth: Double? { fm3dPosition(plane, offset, ctx.model) }
    public var fm3dBusy: Bool { start != nil }
    public func fm3dAdopt(_ p: FurniturePlacement3D) {
        guard let b = p.binding(along: axis, ctx.model) else { return }
        plane = b.name
        offset = b.offset
    }
}

extension FurnitureSlatsTool: FurnitureTool3D {
    public var fm3dDepth: Double? { fm3dPosition(plane, offset, ctx.model) }
    public var fm3dBusy: Bool { start != nil }
    public func fm3dAdopt(_ p: FurniturePlacement3D) {
        guard let b = p.binding(along: .z, ctx.model) else { return }
        plane = b.name
        offset = b.offset
    }
}

extension FurnitureCushionTool: FurnitureTool3D {
    public var fm3dDepth: Double? { fm3dPosition(plane, offset, ctx.model) }
    public var fm3dBusy: Bool { start != nil }
    public func fm3dAdopt(_ p: FurniturePlacement3D) {
        guard let b = p.binding(along: .z, ctx.model) else { return }
        plane = b.name
        offset = b.offset
    }
}

extension SketchTool: FurnitureTool3D {
    var fm3dShelf: Bool { if case .fm4(.shelf) = target { return true }; return false }
    /// Pick Panels picks the panel under the pointer; every other draw mode draws on the plane.
    public var fm3dPicks: Bool { fm3dShelf && drawMode == .pickWalls }
    /// Shelves, tops and bottoms are sketched at their height (Height Offset from), so the sketch shows where they go.
    public var fm3dDepth: Double? {
        // A blend's base and top are sketched at their ends (First End, Second End from the work plane).
        if isBlendSketch, let p = ctx.furniture3D { return p.depth + (fm4.editingTop ? fm4.end : fm4.start) }
        guard fm3dShelf else { return nil }
        if let id = editingID, let s = ctx.model[id]?.furnitureShelf { return s.elevation }
        return fm3dPosition(fm4.plane, fm4.heightOffset, ctx.model)
    }
    public var fm3dBusy: Bool { start != nil || !curves.isEmpty }
    public func fm3dAdopt(_ p: FurniturePlacement3D) {
        guard fm3dShelf, editingID == nil, let b = p.binding(along: .z, ctx.model) else { return }
        fm4.plane = b.name
        fm4.heightOffset = b.offset
        rebuild()
    }
}

extension FurnitureHardwareTool {
    /// In a 3D view, hardware goes on the face under the pointer, where it was clicked.
    func fm3dWorld(_ i: ToolInput) -> Vec3? { ctx.furniture3D != nil ? i.surfacePoint : nil }
}
