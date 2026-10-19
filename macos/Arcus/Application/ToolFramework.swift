import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

/// Pointer input delivered to tools (all points in view coordinates: plan = model XY, vertical views = (u, z)).
public struct ToolInput: Sendable {
    public var point: Vec2          // snapped (or raw when no snap)
    public var rawPoint: Vec2
    public var snap: SnapResult?
    public var shift = false
    public var command = false
    public var option = false
    public var clickCount = 1
    /// Topmost selectable element under the cursor and all candidates (for Tab cycling).
    public var hit: ElementID?
    public var hitCandidates: [ElementID] = []
    /// F1: in 3D views, the model point under the pointer on the picked element's surface (nil elsewhere).
    public var surfacePoint: Vec3? = nil
    public init(point: Vec2, rawPoint: Vec2, snap: SnapResult? = nil) { self.point = point; self.rawPoint = rawPoint; self.snap = snap }
}

public struct TemporaryDimension: Sendable, Hashable {
    public var from: Vec2
    public var to: Vec2
    public var text: String
    public var isAngle: Bool
    /// True when typing a value will drive this dimension.
    public var isActive: Bool
    /// Rubber-band angles draw as an arc from the horizontal through the start point.
    public var isAngleArc = false
    /// Direction the angle is measured from (the previous segment when chaining); nil = the horizontal.
    public var angleReference: Vec2? = nil
}

public enum ToolCursor: Sendable { case arrow, crosshair, crosshairPlus, move, notAllowed, pick, rotate, copy }

public struct ToolPreview: Sendable {
    public var primitives: [GPrimitive] = []
    public var tempDims: [TemporaryDimension] = []
    /// Dashed alignment guides, drawn like snap guides (e.g. through the grab point of a drag).
    public var guides: [Segment2] = []
    public var highlight: Set<ElementID> = []
    public var cursor: ToolCursor = .crosshair
    /// I3: a light dashed box around what Move/Copy carries (view units), as in RevitCraft.
    public var movedBox: Rect2? = nil
    /// I3: the thin blue rubber band of Move/Copy, from the base point to the pointer.
    public var rubberBand: Segment2? = nil
    /// I3: a wall end being dragged: the wall stays as it is and its new location line (fixed end → pointer) draws as a
    /// thick orange dashed line with a tracking line beyond the pointer, as in RevitCraft.
    public var endDragLine: Segment2? = nil
    public init() {}
}

public enum EscapeResult: Sendable { case stayInTool, exitTool }

/// A typed option shown in the contextual options bar while a tool is active.
public struct ToolOption: Sendable, Identifiable, Hashable {
    public enum Kind: Sendable, Hashable { case length, bool, choice([String]), integer, angle, level }
    public var id: String
    public var label: String
    public var kind: Kind
    public var value: ParamValue
    /// Line style choices carry their styles so the Options Bar can draw pattern previews (W2-ANNOT).
    public var lineStyles: [String: LineStyleData]? = nil
}

/// Everything a tool needs from its host.
@MainActor
public final class ToolContext {
    public let session: DocumentSession
    public var viewID: ElementID
    /// View units per screen point (for tolerances and preview sizes).
    public var pixel: Double = 0.01
    public var snapIndex = SnapIndex()
    public var snapSettings = SnapSettings()
    /// Current type per category (the type selector).
    public var currentTypes: [Category: ElementID] = [:]
    /// Host callbacks.
    public var requestText: ((_ prompt: String, _ initial: String, _ completion: @escaping (String?) -> Void) -> Void)?
    /// Edits text in place on the canvas at a view point (the top-left of the text); hosts without one use `requestText`.
    public var requestTextInPlace: ((_ position: Vec2, _ initial: String, _ completion: @escaping (String?) -> Void) -> Void)?
    /// Asks for text at `position`, in place when the host can.
    public func askText(_ prompt: String, at position: Vec2, initial: String = "", _ completion: @escaping (String?) -> Void) {
        if let inPlace = requestTextInPlace { inPlace(position, initial, completion) } else if let ask = requestText { ask(prompt, initial, completion) } else { completion(nil) }
    }
    public var showMessage: ((String) -> Void)?
    /// Asks a yes/no question (message, confirm button title); nil when the host can't ask (the answer is then no).
    public var requestConfirmation: ((_ message: String, _ confirmTitle: String, _ completion: @escaping (Bool) -> Void) -> Void)?
    public var toolFinished: (() -> Void)?
    /// Presents an error that stops an operation, with action buttons (first = default); calls back with the index. // BL-CANVAS
    public var presentError: ((_ message: String, _ detail: String, _ actions: [String], _ completion: @escaping (Int) -> Void) -> Void)?

    public init(session: DocumentSession, viewID: ElementID) { self.session = session; self.viewID = viewID }

    public var model: BIMModel { session.model }
    public var view: Element? { model[viewID] }
    public var viewData: ViewData? { view?.view }
    public var levelID: ElementID? { view?.levelID ?? model.levels.first?.id }
    public var levelElevation: Double { model.elevation(ofLevel: levelID) }
    public var units: UnitsSettings { model.units }
    public var isPlan: Bool { viewData?.kind.isPlan ?? false }
    public var isVertical: Bool { viewData?.kind.isVerticalCut ?? false }
    public var isSheet: Bool { view?.sheet != nil }
    public var isDrafting: Bool { viewData?.kind == .drafting || viewData?.kind == .legend }
    public var scale: Int { viewData?.scale ?? 100 }
    public func paper(_ meters: Double) -> Double { isSheet ? meters : meters * Double(scale) }

    public func format(_ v: Double, _ kind: UnitKind = .length) -> String { QuantityFormatter.format(v, kind: kind, units: units) }
    public func parse(_ text: String, _ kind: UnitKind = .length) -> Double? { try? QuantityParser.parse(text, kind: kind, units: units) }

    public func type(for c: Category) -> ElementID? {
        if let t = currentTypes[c], model[t]?.typeData != nil { return t }
        return model.types(for: c).first?.id
    }

    /// Snaps a raw point; applies angle snap relative to `from` when no object snap is found.
    /// Elements currently being moved or edited (drag, grip edit, Move): excluded from snapping so they never snap
    /// to their own original geometry.
    public var snapExclusions: Set<ElementID> = []

    /// One-shot snap override typed during a tool (SE, SM, SI, … or SO): applies to the next pick only.
    /// `kinds`: several snap kinds (Snap to Points); `remote`: the usual snaps with a much larger capture radius. // BL-KEYS
    public enum SnapOverride: Equatable, Sendable { case only(SnapKind), off, kinds(Set<SnapKind>), remote }
    public var snapOverride: SnapOverride?

    /// Lines the pointer passed over recently (newest last). Drawing can then snap parallel or perpendicular to them
    /// anywhere in the view, not only near them, as BIM users expect. Cleared when the tool changes.
    public var acquiredLines: [(dir: Vec2, id: ElementID?)] = []
    /// SFE: names for snapped geometry that isn't a model element (the Family Editor's forms, lines and planes), used by
    /// `elementLabel` before the model is consulted.
    public var elementLabelProvider: ((ElementID) -> String?)? // SFE

    func acquireLine(near raw: Vec2, settings: SnapSettings) {
        guard settings.snapsOn, let (seg, id) = snapIndex.nearestSegment(raw, radius: settings.pixelRadius * pixel, visibleOnly: true),
              id.map({ !snapExclusions.contains($0) }) ?? true, seg.length > pixel * 3 else { return }
        let d = (seg.end - seg.start).normalized
        acquiredLines.removeAll { abs($0.dir.x * d.y - $0.dir.y * d.x) < 1e-6 }
        acquiredLines.append((d, id))
        if acquiredLines.count > 4 { acquiredLines.removeFirst() }
    }

    /// Settings in force for the next pick, after any one-shot override.
    public var effectiveSnapSettings: SnapSettings {
        var s = snapSettings
        switch snapOverride {
        case .only(let k)?: s.snapsOn = true; s.enabled = [k]; s.pixelRadius = max(s.pixelRadius, 16)
        case .off?: s.snapsOn = false
        case .kinds(let k)?: s.snapsOn = true; s.enabled = k; s.pixelRadius = max(s.pixelRadius, 16) // BL-KEYS
        case .remote?: s.snapsOn = true; s.pixelRadius = max(s.pixelRadius, 12) * 4 // BL-KEYS
        case nil: break
        }
        return s
    }

    /// `constrainOrtho` (Shift held while drawing): the result lies on the horizontal or vertical line through `from`,
    /// whichever is closer to the pointer; object snaps are projected onto that line.
    public func snap(_ raw: Vec2, from: Vec2? = nil, orthoOnly: Bool = false, constrainOrtho: Bool = false) -> (Vec2, SnapResult?) {
        let settings = effectiveSnapSettings
        if constrainOrtho, let f = from {
            let d = raw - f
            let horizontal = abs(d.x) >= abs(d.y)
            func project(_ p: Vec2) -> Vec2 { horizontal ? Vec2(p.x, f.y) : Vec2(f.x, p.y) }
            if let s = snapIndex.snap(raw, radius: settings.pixelRadius * pixel, from: from, settings: settings, exclude: snapExclusions) {
                let p = project(s.point)
                return (p, SnapResult(point: p, kind: s.kind, elementIDs: s.elementIDs))
            }
            let p = project(raw)
            return (p, SnapResult(point: p, kind: .angle, elementIDs: []))
        }
        acquireLine(near: raw, settings: settings)
        return resolveSnap(raw, from: from, settings: settings, orthoOnly: orthoOnly)
    }

    /// Converts a view point to a plan point for plan views (identity) — vertical views return nil.
    public func planPoint(_ p: Vec2) -> Vec2? { isPlan ? p : nil }

    // Preview helpers
    public var previewStroke: GStroke { GStroke(weight: 1, color: RGBColor(0.18, 0.43, 0.66)) }
    public var previewHeavy: GStroke { GStroke(weight: 3, color: RGBColor(0.18, 0.43, 0.66)) }
    public func line(_ a: Vec2, _ b: Vec2, heavy: Bool = false) -> GPrimitive { .polyline([a, b], closed: false, heavy ? previewHeavy : previewStroke) }
}

/// Protocol for interactive tools (state machines). Implementations never mutate the model directly; they
/// commit through `DocumentSession.perform`, producing undoable transactions.
@MainActor
public protocol InteractiveTool: AnyObject {
    var commandID: CommandID { get }
    var title: String { get }
    /// Status bar instruction for the next step.
    var prompt: String { get }
    var preview: ToolPreview { get }
    /// Label of the value typed numbers will set (e.g. "Length"); nil if numbers are not accepted.
    var numericLabel: String? { get }
    var options: [ToolOption] { get }
    /// True in sketch mode (Finish/Cancel buttons shown).
    var isSketchMode: Bool { get }
    func setOption(_ id: String, _ value: ParamValue)
    func pointerMoved(_ i: ToolInput)
    func pointerDown(_ i: ToolInput)
    func pointerDragged(_ i: ToolInput)
    func pointerUp(_ i: ToolInput)
    /// Applies a typed value. Returns false (with message) when not applicable or invalid.
    func numericInput(_ text: String) -> Bool
    /// First Escape cancels the current step/chain; returns .exitTool when there is nothing left to cancel.
    func escape() -> EscapeResult
    /// Enter / Finish. Returns true if handled.
    func finish() -> Bool
    func cancelSketch()
    /// Space bar (flip/rotate during placement).
    func spaceBar()
    /// The reference point used for perpendicular/angle snapping.
    var snapFrom: Vec2? { get }
    /// The tool's geometry placed so far but not yet in the model (a sketch's lines, a path's segments): it snaps and
    /// offers alignment like drawn lines, as in Revit. Excludes the rubber band.
    var snapCurves: [Curve2] { get }
}

extension InteractiveTool {
    public var numericLabel: String? { nil }
    public var options: [ToolOption] { [] }
    public var isSketchMode: Bool { false }
    public func setOption(_ id: String, _ value: ParamValue) {}
    public func pointerDragged(_ i: ToolInput) {}
    public func pointerUp(_ i: ToolInput) {}
    public func numericInput(_ text: String) -> Bool { false }
    public func finish() -> Bool { false }
    public func cancelSketch() {}
    public func spaceBar() {}
    public var snapFrom: Vec2? { nil }
    public var snapCurves: [Curve2] { [] }
}

/// Common helpers for tools.
@MainActor
open class BaseTool {
    public let ctx: ToolContext
    public var preview = ToolPreview()
    public init(ctx: ToolContext) { self.ctx = ctx }

    public func tempDim(_ a: Vec2, _ b: Vec2, active: Bool = true) -> TemporaryDimension {
        TemporaryDimension(from: a, to: b, text: ctx.format(a.distance(to: b)), isAngle: false, isActive: active)
    }
    public func angleDim(_ a: Vec2, _ b: Vec2, reference: Vec2? = nil) -> TemporaryDimension {
        TemporaryDimension(from: a, to: b, text: String(format: "%.1f°", Angle.degrees(Angle.normalize((b - a).angle))), isAngle: true, isActive: false, isAngleArc: true, angleReference: reference)
    }
    public func message(_ s: String) { ctx.showMessage?(s) }

    /// Distances from the line being drawn to the nearest parallel visible line on each side (informational).
    public func referenceDims(for seg: Segment2, exclude: Set<ElementID> = []) -> [TemporaryDimension] {
        guard seg.length > ctx.pixel * 10 else { return [] }
        let reach = ctx.pixel * 700
        let area = Rect2(points: [seg.start, seg.end]).expanded(by: reach)
        let refs = ctx.snapIndex.visibleLines(in: area, minimumLength: ctx.pixel * 10, exclude: exclude)
            .map { SelectionDimensions.RefLine(seg: $0.seg, ref: GeometryReference($0.id ?? ElementID(0), .location)) }
        return SelectionDimensions.offsets(ElementID(0), GeometryReference(ElementID(0), .location), line: seg, margin: 0, along: 0.6, candidates: refs)
            .filter { $0.value <= reach && $0.value > ctx.pixel * 3 }
            .map { TemporaryDimension(from: $0.from, to: $0.to, text: ctx.format($0.value), isAngle: false, isActive: false) }
    }

    /// Before the first click, on a guide: the distance from the pointer to the nearest parallel visible line.
    public func referenceDims(at p: Vec2, exclude: Set<ElementID> = []) -> [TemporaryDimension] {
        let reach = ctx.pixel * 400
        let refs = ctx.snapIndex.visibleLines(in: Rect2(center: p, halfSize: Vec2(reach, reach)), minimumLength: ctx.pixel * 10, exclude: exclude)
            .map { SelectionDimensions.RefLine(seg: $0.seg, ref: GeometryReference($0.id ?? ElementID(0), .location)) }
        var dims: [SelectionDimension] = []
        for axis in [Vec2.unitX, Vec2.unitY] {
            let line = Segment2(p - axis * ctx.pixel, p + axis * ctx.pixel)
            dims += SelectionDimensions.offsets(ElementID(0), GeometryReference(ElementID(0), .location), line: line, margin: reach, along: 0.5, candidates: refs)
        }
        guard let nearest = dims.filter({ $0.value <= reach && $0.value > ctx.pixel * 3 }).min(by: { $0.value < $1.value }) else { return [] }
        return [TemporaryDimension(from: nearest.from, to: nearest.to, text: ctx.format(nearest.value), isAngle: false, isActive: false)]
    }

    /// Element under the cursor filtered by categories.
    public func hit(_ i: ToolInput, _ cats: Set<Category>) -> Element? {
        for id in [i.hit].compactMap({ $0 }) + i.hitCandidates {
            if let e = ctx.model[id], cats.contains(e.category) { return e }
        }
        return nil
    }
}
