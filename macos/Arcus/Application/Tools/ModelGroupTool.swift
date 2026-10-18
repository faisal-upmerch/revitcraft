import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// F1: Model Group ▸ Place Model Group (RevitCraft `Cmd::PlaceGroup`, `group_tool` in crates/rc-app/src/canvas_tools.rs and
// `place_group` in crates/rc-core/src/edit.rs): choose a model group type, click to place its origin on the view's level.

/// Model group types: groups sharing a group type name are instances of one type (Edit Group updates them together).
public enum ModelGroups {
    /// The project's model group type names, sorted.
    public static func typeNames(_ model: BIMModel) -> [String] {
        Array(Set(model.elements(.modelGroups).compactMap { $0.group?.groupTypeName })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The instance a new one is copied from: the first of the type.
    public static func source(_ typeName: String, _ model: BIMModel) -> Element? {
        model.elements(.modelGroups).first { $0.group?.groupTypeName == typeName }
    }

    /// The level the group's members stand on, when they share one.
    public static func memberLevel(of group: Element, _ model: BIMModel) -> ElementID? {
        let levels = Set((group.group?.members ?? []).compactMap { model[$0]?.levelID })
        return levels.count == 1 ? levels.first : nil
    }

    /// Places an instance of `typeName` with its origin at `p`. Members on one level move to `level` (RevitCraft keeps the
    /// group's level relative to the placement level); groups spanning levels keep theirs. Returns the new group.
    @discardableResult
    public static func place(_ typeName: String, at p: Vec2, level: ElementID?, viewID: ElementID?, in tx: TransactionContext) throws -> ElementID {
        guard let src = source(typeName, tx.model), let gd = src.group else {
            throw TransactionError("There is no model group named “\(typeName)”.")
        }
        let from = memberLevel(of: src, tx.model)
        let target = from != nil && level != nil && from != level ? level : nil
        let map = ElementOperations.copy(gd.members, by: .translation(p - gd.origin), in: tx, viewID: viewID, targetLevel: target)
        let members = gd.members.compactMap { map[$0] }
        guard !members.isEmpty else { throw TransactionError("The group “\(typeName)” has nothing to place.") }
        let gid = tx.create(.modelGroups, name: typeName, data: .group(GroupData(members: members, origin: p, groupTypeName: typeName)),
                            levelID: target ?? from)
        for id in members { tx.update(id) { $0.groupID = gid } }
        return gid
    }
}

/// Places model groups.
@MainActor
public final class ModelGroupTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.placeModelGroup
    public let title = "Model Group"
    /// The group type being placed (Options Bar).
    public var groupName: String?

    public override init(ctx: ToolContext) {
        super.init(ctx: ctx)
        groupName = ModelGroups.typeNames(ctx.model).first
    }

    public var prompt: String {
        guard groupName != nil else { return "The project has no model groups. Select elements and use Create Group first." }
        return ctx.isPlan ? "Click to place the group origin." : "Model groups are placed in plan views."
    }

    public var options: [ToolOption] {
        [ToolOption(id: "group", label: "Group", kind: .choice(ModelGroups.typeNames(ctx.model)), value: .text(groupName ?? ""))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "group", let n = value.textValue, ModelGroups.typeNames(ctx.model).contains(n) { groupName = n }
    }

    /// Plan curves of the members (wall axes, lines, beams; footprints of the rest), moved to `p`.
    func previewCurves(at p: Vec2) -> [GPrimitive] {
        guard let name = groupName, let src = ModelGroups.source(name, ctx.model), let gd = src.group else { return [] }
        let t = Transform2.translation(p - gd.origin)
        var prims: [GPrimitive] = []
        for id in gd.members {
            guard let e = ctx.model[id] else { continue }
            if let c = ElementOperations.curveOf(e) {
                let moved = c.transformed(t)
                switch moved {
                case .line(let s): prims.append(.polyline([s.start, s.end], closed: false, ctx.previewStroke))
                case .arc(let a): prims.append(.arc(a, ctx.previewStroke))
                }
            } else {
                let b = ElementMeshes.bounds(e, ctx.model)
                if !b.isEmpty { prims.append(.polyline(Rect2(min: b.min.xy, max: b.max.xy).corners.map { t.apply($0) }, closed: true, ctx.previewStroke)) }
            }
        }
        return prims
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard ctx.isPlan else { return }
        preview.primitives = previewCurves(at: i.point)
        let r = ctx.pixel * 6
        preview.primitives.append(.arc(Arc2(center: i.point, radius: r, startAngle: 0, sweep: 2 * .pi), ctx.previewStroke))
    }

    public func pointerDown(_ i: ToolInput) {
        guard let name = groupName else { message("The project has no model groups. Select elements and use Create Group first."); return }
        guard ctx.isPlan else { message("Open a plan view to place a model group."); return }
        var gid: ElementID?
        let level = ctx.levelID, view = ctx.viewID
        ctx.session.perform("Place Group") { tx in gid = try ModelGroups.place(name, at: i.point, level: level, viewID: view, in: tx) }
        if let err = ctx.session.lastError { message(err.message); return }
        // As in RevitCraft, the new group is selected and the tool stays active.
        if let gid { ctx.session.selection.select([gid]) }
    }

    public func escape() -> EscapeResult { .exitTool }
}
