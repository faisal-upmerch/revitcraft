import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// W2-DWG: Massing & Site tools — parking layouts, sub-regions, split surface, contour labels and surface editing.

/// Finds the (non-sub-region) toposurface under a plan point.
@MainActor
enum SitePick {
    static func surface(at p: Vec2, _ model: BIMModel, preferring ids: [ElementID] = []) -> Element? {
        let candidates = model.elements(.topography).filter { $0.topography?.boundary == nil }
        for id in ids { if let e = model[id], e.topography != nil, e.topography?.boundary == nil { return e } }
        return candidates.first { e in
            guard let pts = e.topography?.points, pts.count >= 3 else { return false }
            return SiteEditing.surfaceZ(pts, at: p) != nil
        }
    }

    static func showError(_ ctx: ToolContext, _ fallback: String? = nil) {
        if let e = ctx.session.lastError { ctx.showMessage?(e.message) } else if let fallback { ctx.showMessage?(fallback) }
    }
}

// MARK: - Parking layout

@MainActor
public final class ParkingLayoutTool: BaseTool, InteractiveTool {
    /// The points placed so far snap and align, as in Revit.
    public var snapCurves: [Curve2] { SnapIndex.chain(points) }
    public let commandID = CommandID.parkingLayout
    public let title = "Parking Layout"
    public enum Mode: String, CaseIterable { case rectangle = "Rectangle", polygon = "Sketch", pick = "Pick Boundary" }
    public var mode: Mode = .rectangle
    public var params: ParkingLayout.Parameters
    var points: [Vec2] = []
    var current: Vec2?
    public var isSketchMode: Bool { mode == .polygon }
    /// Called with the stall count after a layout is created (the UI shows it).
    public var onCreated: ((Int) -> Void)?

    public override init(ctx: ToolContext) {
        params = ParkingLayout.Parameters.defaults(for: ctx.model.units.system)
        super.init(ctx: ctx)
    }

    public var prompt: String {
        switch mode {
        case .rectangle: return points.isEmpty ? "Click the first corner of the parking area." : "Click the opposite corner."
        case .polygon: return "Click the corners of the parking area, then Finish (Return)."
        case .pick: return "Click inside a floor, building pad, filled region or closed property lines to fill it with stalls."
        }
    }

    public var options: [ToolOption] {
        [ToolOption(id: "mode", label: "Boundary", kind: .choice(Mode.allCases.map(\.rawValue)), value: .text(mode.rawValue)),
         ToolOption(id: "angle", label: "Angle", kind: .choice(["90°", "60°", "45°"]), value: .text("\(Int(params.angle))°")),
         ToolOption(id: "width", label: "Stall Width", kind: .length, value: .double(params.stallWidth)),
         ToolOption(id: "depth", label: "Stall Depth", kind: .length, value: .double(params.stallDepth)),
         ToolOption(id: "aisle", label: "Aisle", kind: .length, value: .double(params.aisleWidth)),
         ToolOption(id: "stops", label: "Wheel Stops", kind: .bool, value: .bool(params.wheelStops))]
    }

    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "mode": mode = Mode(rawValue: value.textValue ?? "") ?? mode; points = []
        case "angle":
            let a = Double((value.textValue ?? "").filter(\.isNumber)) ?? params.angle
            if [90.0, 60, 45].contains(a) {
                params.angle = a
                params.aisleWidth = ParkingLayout.Parameters.recommendedAisle(for: ctx.model.units.system, angle: a)
            }
        case "width": if let d = value.doubleValue, d > 0.5 { params.stallWidth = d }
        case "depth": if let d = value.doubleValue, d > 1 { params.stallDepth = d }
        case "aisle": if let d = value.doubleValue, d >= 0 { params.aisleWidth = d }
        case "stops": params.wheelStops = value.boolValue ?? params.wheelStops
        default: break
        }
        refreshPreview()
    }

    var boundary: Polygon2? {
        switch mode {
        case .rectangle:
            guard let a = points.first, let b = current, abs(a.x - b.x) > 0.5, abs(a.y - b.y) > 0.5 else { return nil }
            return .rectangle(Rect2(points: [a, b]))
        case .polygon:
            let pts = points + (current.map { [$0] } ?? [])
            return pts.count >= 3 ? Polygon2(pts) : nil
        case .pick: return nil
        }
    }

    func refreshPreview() {
        preview = ToolPreview()
        let pts = points + (current.map { [$0] } ?? [])
        if pts.count >= 2 { preview.primitives.append(.polyline(mode == .rectangle ? (boundary?.points ?? pts) : pts, closed: mode != .polygon || pts.count >= 3, ctx.previewStroke)) }
        if let b = boundary {
            let r = ParkingLayout.generate(boundary: b, params)
            for s in r.stripes + r.wheelStops { preview.primitives.append(ctx.line(s.start, s.end)) }
        }
    }

    public func pointerMoved(_ i: ToolInput) { current = i.point; refreshPreview() }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Open a plan view to lay out parking."); return }
        switch mode {
        case .rectangle:
            if points.isEmpty { points = [i.point]; return }
            current = i.point
            if let b = boundary { create(b) }
            points = []
        case .polygon:
            points.append(i.point)
        case .pick:
            guard let b = pickBoundary(at: i.point) else { message("No closed boundary here. Click inside a floor, building pad, filled region or closed property lines."); return }
            create(b)
        }
        refreshPreview()
    }

    func pickBoundary(at p: Vec2) -> Polygon2? {
        let m = ctx.model
        for e in m.elements(.buildingPads) + m.elements(.floors) + m.elements(.filledRegions) {
            if e.ownerViewID != nil && e.ownerViewID != ctx.viewID { continue }
            let sketch = e.slab?.boundary ?? e.filledRegion?.boundary
            if let s = sketch, case .success(let polys) = s.polygons(), let outer = polys.first, outer.contains(p) { return outer }
        }
        // Closed loops of property lines.
        let curves = m.elements(.propertyLines).compactMap { $0.modelLine?.curve }
        if !curves.isEmpty, let loop = Sketch.orderLoop(curves) {
            let poly = Polygon2(loop.flatMap { Array($0.tessellate(chordTolerance: 0.05).dropLast()) })
            if poly.count >= 3, poly.contains(p) { return poly }
        }
        return nil
    }

    func create(_ b: Polygon2) {
        let r = ParkingLayout.generate(boundary: b, params)
        guard r.stallCount > 0 else { message("No stalls fit in this area with the current stall and aisle sizes."); return }
        let level = ctx.levelID
        let n = ctx.model.elements(.modelGroups).filter { $0.name.hasPrefix("Parking Layout") }.count + 1
        ctx.session.perform("Parking Layout") { tx in
            let stripeStyle = Self.lineStyle("Parking Stripes", weight: 2, color: RGBColor(0.95, 0.85, 0.1), tx)
            let stopStyle = Self.lineStyle("Parking Wheel Stops", weight: 5, color: RGBColor(0.45, 0.45, 0.45), tx)
            var ids: [ElementID] = []
            for s in r.stripes { ids.append(tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(s), styleID: stripeStyle)), levelID: level)) }
            for s in r.wheelStops { ids.append(tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(s), styleID: stopStyle)), levelID: level)) }
            let origin = b.centroid
            let gid = tx.create(.modelGroups, name: "Parking Layout \(n)", data: .group(GroupData(members: ids, origin: origin, groupTypeName: "Parking Layout \(n)")))
            for id in ids { tx.update(id) { $0.groupID = gid } }
            tx.update(gid) { $0.comments = "\(r.stallCount) stalls" }
        }
        if ctx.session.lastError == nil {
            message("Parking layout: \(r.stallCount) stall\(r.stallCount == 1 ? "" : "s") in \(r.rows) row\(r.rows == 1 ? "" : "s").")
            onCreated?(r.stallCount)
        } else { SitePick.showError(ctx) }
    }

    static func lineStyle(_ name: String, weight: Int, color: RGBColor, _ tx: TransactionContext) -> ElementID {
        if let s = tx.model.lineStyle(named: name) { return s.id }
        return tx.create(.lineStyles, name: name, data: .lineStyle(LineStyleData(weight: weight, color: color)))
    }

    public func finish() -> Bool {
        guard mode == .polygon else { return false }
        guard points.count >= 3 else { message("Click at least three corners."); return false }
        current = nil
        create(Polygon2(points))
        points = []
        refreshPreview()
        return true
    }
    public func cancelSketch() { points = []; current = nil; refreshPreview() }
    public func escape() -> EscapeResult {
        if !points.isEmpty { points.removeLast(); refreshPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Sub-region

@MainActor
public final class SubregionTool: BaseTool, InteractiveTool {
    /// The points placed so far snap and align, as in Revit.
    public var snapCurves: [Curve2] { SnapIndex.chain(points) }
    public let commandID = CommandID.subregion
    public let title = "Sub-Region"
    public var isSketchMode: Bool { true }
    var hostID: ElementID?
    var points: [Vec2] = []
    var current: Vec2?

    public init(ctx: ToolContext, hostID: ElementID?) {
        self.hostID = hostID
        super.init(ctx: ctx)
    }
    public var prompt: String {
        hostID == nil ? "Click inside the toposurface to draw the sub-region on, at its first corner." : "Click the corners of the sub-region, then Finish (Return)."
    }
    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        let pts = points + [i.point]
        if pts.count >= 2 { preview.primitives.append(.polyline(pts, closed: pts.count >= 3, ctx.previewHeavy)) }
        if let h = hostID { preview.highlight = [h] }
    }
    public func pointerDown(_ i: ToolInput) {
        if hostID == nil {
            guard let s = SitePick.surface(at: i.point, ctx.model) else { message("Click inside a toposurface."); return }
            hostID = s.id
        }
        points.append(i.point)
        pointerMoved(i)
    }
    public func finish() -> Bool {
        guard let h = hostID, points.count >= 3 else { message("Click at least three corners."); return false }
        let b = Polygon2(points)
        ctx.session.perform("Create Sub-Region") { tx in try SiteOperations.createSubregion(on: h, boundary: b, in: tx) }
        if ctx.session.lastError != nil { SitePick.showError(ctx); return false }
        points = []
        ctx.toolFinished?()
        return true
    }
    public func cancelSketch() { points = []; ctx.toolFinished?() }
    public func escape() -> EscapeResult {
        if !points.isEmpty { points.removeLast(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Split surface

@MainActor
public final class SplitSurfaceTool: BaseTool, InteractiveTool {
    /// The points placed so far snap and align, as in Revit.
    public var snapCurves: [Curve2] { SnapIndex.chain(points) }
    public let commandID = CommandID.splitSurface
    public let title = "Split Surface"
    public var isSketchMode: Bool { true }
    var hostID: ElementID?
    var points: [Vec2] = []

    public init(ctx: ToolContext, hostID: ElementID?) {
        self.hostID = hostID
        super.init(ctx: ctx)
    }
    public var prompt: String {
        hostID == nil ? "Click inside the toposurface to split, at the start of the split line."
            : "Click points of the split line across the surface, then Finish (Return). The line is extended past the surface edges."
    }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        let pts = points + [i.point]
        if pts.count >= 2 { preview.primitives.append(.polyline(pts, closed: false, ctx.previewHeavy)) }
        if let h = hostID { preview.highlight = [h] }
    }
    public func pointerDown(_ i: ToolInput) {
        if hostID == nil {
            guard let s = SitePick.surface(at: i.point, ctx.model) else { message("Click inside a toposurface."); return }
            hostID = s.id
        }
        points.append(i.point)
        pointerMoved(i)
    }
    public func finish() -> Bool {
        guard let h = hostID, points.count >= 2 else { message("Click at least two points of the split line."); return false }
        let path = points
        ctx.session.perform("Split Surface") { tx in try SiteOperations.split(h, along: path, in: tx) }
        if ctx.session.lastError != nil { SitePick.showError(ctx); return false }
        message("The toposurface was split in two.")
        points = []
        ctx.toolFinished?()
        return true
    }
    public func cancelSketch() { points = []; ctx.toolFinished?() }
    public func escape() -> EscapeResult {
        if !points.isEmpty { points.removeLast(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Label contours

@MainActor
public final class LabelContoursTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.labelContours
    public let title = "Label Contours"
    var start: Vec2?
    public var primaryOnly = false
    public var prompt: String { start == nil ? "Click where the labelling line starts, across the contours." : "Click the end of the labelling line." }
    public var options: [ToolOption] { [ToolOption(id: "primary", label: "Primary Contours Only", kind: .bool, value: .bool(primaryOnly))] }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "primary" { primaryOnly = value.boolValue ?? primaryOnly } }
    public var snapFrom: Vec2? { start }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let s = start { preview.primitives.append(ctx.line(s, i.point, heavy: true)) }
    }
    public func pointerDown(_ i: ToolInput) {
        guard let s = start else { start = i.point; return }
        start = nil
        preview = ToolPreview()
        let line = Segment2(s, i.point)
        guard line.length > Tolerance.length else { return }
        let settings = SiteSettings(ctx.model)
        let view = ctx.viewID
        var labels: [SiteEditing.ContourLabel] = []
        for e in ctx.model.elements(.topography) where e.topography?.boundary == nil {
            labels += SiteEditing.contourLabels(e, settings: settings, line: line, primaryOnly: primaryOnly)
        }
        guard !labels.isEmpty else { message("The line doesn't cross any contours."); return }
        let texts = labels.map { (l: $0, text: ctx.format($0.elevation)) }
        ctx.session.perform("Label Contours") { tx in
            for (l, text) in texts {
                var d = TextNoteData(position: l.position, text: text)
                d.rotation = l.rotation
                d.alignment = .center
                tx.create(.textNotes, data: .textNote(d), ownerViewID: view) { $0.comments = "Contour label" }
            }
        }
        if ctx.session.lastError == nil { message("Labelled \(labels.count) contour\(labels.count == 1 ? "" : "s").") } else { SitePick.showError(ctx) }
    }
    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Edit surface (graded regions and toposurfaces)

/// Adds, removes and re-levels survey points of one toposurface. Changes are applied on Finish as one step.
@MainActor
public final class EditSurfaceTool: BaseTool, InteractiveTool {
    public let commandID: CommandID
    public let title = "Edit Surface"
    public var isSketchMode: Bool { true }
    public enum Mode: String, CaseIterable { case add = "Add Point", setElevation = "Set Elevation", delete = "Delete Point", splitLine = "Split Line" } // BL-SITE: split line
    public var mode: Mode = .add
    var splitStart: Vec2? // BL-SITE
    public var elevation: Double
    let surfaceID: ElementID
    var points: [Vec3]

    public init?(ctx: ToolContext, surfaceID: ElementID, commandID: CommandID = .gradedRegion) {
        guard let t = ctx.model[surfaceID]?.topography, t.boundary == nil else { return nil }
        self.surfaceID = surfaceID
        self.commandID = commandID
        points = t.points
        elevation = t.points.map(\.z).reduce(0, +) / Double(max(1, t.points.count))
        super.init(ctx: ctx)
    }
    public var prompt: String {
        switch mode {
        case .add: return "Click to add points at elevation \(ctx.format(elevation)). Finish (Return) applies the changes."
        case .setElevation: return "Click near a point to set it to \(ctx.format(elevation))."
        case .delete: return "Click near a point to delete it."
        case .splitLine: return splitStart == nil ? "Click the start of a split line (points are added along it at the surface's elevations)." : "Click the end of the split line." // BL-SITE
        }
    }
    public var numericLabel: String? { "Elevation" }
    public var options: [ToolOption] {
        [ToolOption(id: "mode", label: "Mode", kind: .choice(Mode.allCases.map(\.rawValue)), value: .text(mode.rawValue)),
         ToolOption(id: "elevation", label: "Elevation", kind: .length, value: .double(elevation))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "mode" { mode = Mode(rawValue: value.textValue ?? "") ?? mode; splitStart = nil } // BL-SITE
        if id == "elevation", let d = value.doubleValue, d.isFinite { elevation = d }
    }
    public func numericInput(_ text: String) -> Bool {
        guard let v = ctx.parse(text) else { return false }
        elevation = v
        return true
    }
    func nearest(_ p: Vec2) -> Int? {
        let reach = max(ctx.pixel * 12, 0.05)
        return points.indices.min { points[$0].xy.distance(to: p) < points[$1].xy.distance(to: p) }.flatMap { points[$0].xy.distance(to: p) <= reach ? $0 : nil }
    }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        preview.highlight = [surfaceID]
        let s = ctx.paper(0.0012)
        for p in points { preview.primitives.append(.polyline(Rect2(center: p.xy, halfSize: Vec2(s, s)).corners, closed: true, ctx.previewStroke)) }
        if mode == .splitLine, let s = splitStart { preview.primitives.append(ctx.line(s, i.point, heavy: true)) } // BL-SITE
        if mode != .add && mode != .splitLine, let k = nearest(i.point) {
            preview.primitives.append(.polyline(Rect2(center: points[k].xy, halfSize: Vec2(s * 2, s * 2)).corners, closed: true, ctx.previewHeavy))
        }
    }
    public func pointerDown(_ i: ToolInput) {
        switch mode {
        case .add: points.append(Vec3(i.point, z: elevation))
        case .setElevation: if let k = nearest(i.point) { points[k].z = elevation } else { message("Click closer to a point.") }
        case .delete:
            guard let k = nearest(i.point) else { message("Click closer to a point."); return }
            guard points.count > 3 else { message("A toposurface needs at least three points."); return }
            points.remove(at: k)
        case .splitLine: // BL-SITE
            guard let s = splitStart else { splitStart = i.point; break }
            points = ToposolidOperations.addSplitLine(points, from: s, to: i.point)
            splitStart = nil
        }
        pointerMoved(i)
    }
    public func finish() -> Bool {
        let pts = points, id = surfaceID
        ctx.session.perform("Edit Surface") { tx in tx.update(id) { $0.topography?.points = pts } }
        ctx.toolFinished?()
        return true
    }
    public func cancelSketch() { ctx.toolFinished?() }
    public func escape() -> EscapeResult {
        if splitStart != nil { splitStart = nil; return .stayInTool } // BL-SITE
        return .exitTool
    }
}
