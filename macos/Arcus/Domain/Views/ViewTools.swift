import Foundation
import ArcusGeometry

/// Selection Box: a 3D section box fitted around selected elements.
public enum SelectionBox {
    /// Default clearance around the selection (meters), so faces on the box are not clipped flush.
    public static let defaultMargin = 0.3

    /// The 3D bounds of the selected model elements (group members included), expanded by `margin`; nil when the
    /// selection has no 3D extent (annotations, views, datums only).
    public static func box(for ids: [ElementID], _ model: BIMModel, margin: Double = defaultMargin) -> Box3? {
        var b = Box3.empty
        var seen = Set<ElementID>()
        func add(_ id: ElementID) {
            guard seen.insert(id).inserted, let e = model[id] else { return }
            if let g = e.group { for m in g.members { add(m) }; return }
            guard e.category.isModel, e.ownerViewID == nil else { return }
            let eb = ElementMeshes.bounds(e, model)
            if !eb.isEmpty { b.include(eb) }
        }
        for id in ids { add(id) }
        guard !b.isEmpty else { return nil }
        // Flat elements (a floor seen edge-on, a model line) still get a usable box.
        return b.expanded(by: max(margin, 0))
    }

    /// Turns the section box on for a 3D view, fitted to `box`, and frames the camera on it keeping its direction.
    public static func apply(_ box: Box3, to v: inout ViewData) {
        v.sectionBox = box
        v.sectionBoxActive = true
        v.camera = framed(v.camera ?? .defaultIsometric, on: box)
    }

    /// A camera looking at the box centre from the same direction, far enough away to see all of it.
    public static func framed(_ cam: Camera3D, on box: Box3) -> Camera3D {
        var c = cam
        var dir = cam.target - cam.eye
        if dir.length < 1e-9 { dir = Camera3D.defaultIsometric.target - Camera3D.defaultIsometric.eye }
        let f = dir.normalized
        let radius = max(box.diagonal / 2, 0.5)
        let distance: Double
        if cam.isPerspective {
            distance = radius / sin(max(cam.fieldOfView, 0.1) / 2) * 1.05
        } else {
            distance = radius * 3
            c.orthoHeight = radius * 2.2
        }
        c.target = box.center
        c.eye = box.center - f * distance
        return c
    }
}

/// Perspective camera views placed from a plan (eye and target clicked in plan, heights above the plan's level).
public enum CameraViews {
    public static let defaultEyeHeight = 1.75
    public static let defaultTargetHeight = 1.75
    public static let defaultFieldOfView = 50 * Double.pi / 180

    /// "3D View 1", "3D View 2", … unique among 3D views.
    public static func nextName(_ model: BIMModel) -> String {
        let names = Set(model.views.filter { $0.view?.kind == .threeD }.map(\.name))
        var n = 1
        while names.contains("3D View \(n)") { n += 1 }
        return "3D View \(n)"
    }

    /// View data for a perspective 3D view with the eye at `eye` and looking at `target` (plan points).
    public static func viewData(eye: Vec2, target: Vec2, levelElevation z: Double, eyeHeight: Double = defaultEyeHeight,
                                targetHeight: Double = defaultTargetHeight, phaseID: ElementID?) -> ViewData {
        var v = ViewData(kind: .threeD)
        v.camera = Camera3D(eye: Vec3(eye, z: z + eyeHeight), target: Vec3(target, z: z + targetHeight), up: .unitZ,
                            isPerspective: true, fieldOfView: defaultFieldOfView)
        v.phaseID = phaseID
        v.visualStyle = .shaded
        v.cropActive = true // W2-CAM: cameras show their frame
        return v
    }

    /// Creates the camera view in a transaction; returns its id.
    @discardableResult
    public static func create(eye: Vec2, target: Vec2, levelID: ElementID?, in tx: TransactionContext,
                              eyeHeight: Double = defaultEyeHeight, targetHeight: Double = defaultTargetHeight) throws -> ElementID {
        guard eye.distance(to: target) > Tolerance.shortCurve else { throw TransactionError("Pick a target away from the camera.") }
        let data = viewData(eye: eye, target: target, levelElevation: tx.model.elevation(ofLevel: levelID), eyeHeight: eyeHeight,
                            targetHeight: targetHeight, phaseID: tx.model.latestPhase?.id)
        return tx.create(.views, name: nextName(tx.model), data: .view(data), levelID: levelID)
    }
}

/// Renaming a level offers to rename the views named after it.
public enum LevelRename {
    public struct Rename: Hashable, Sendable {
        public var levelID: ElementID
        public var oldName: String
        public var newName: String
    }

    /// Level renames committed by a transaction.
    public static func renamedLevels(in record: TransactionRecord) -> [Rename] {
        record.changes.compactMap { c in
            guard let b = c.before, let a = c.after, b.level != nil, a.level != nil, b.name != a.name else { return nil }
            return Rename(levelID: c.id, oldName: b.name, newName: a.name)
        }
    }

    /// Views of the level whose names follow the level's old name ("Level 1", or "Level 1 (Ceiling Plan)"), with the
    /// name each would take. Views whose new name is already used in their Project Browser group are left out.
    public static func correspondingViews(_ r: Rename, _ model: BIMModel) -> [(viewID: ElementID, newName: String)] {
        var out: [(ElementID, String)] = []
        var taken: [String: Set<String>] = [:]
        for v in model.views { if let k = v.view?.kind { taken[k.navigatorGroup, default: []].insert(v.name) } }
        for v in model.views where v.levelID == r.levelID {
            guard let k = v.view?.kind, k.isPlan else { continue }
            let newName: String
            if v.name == r.oldName { newName = r.newName }
            else if v.name.hasPrefix(r.oldName + " (") { newName = r.newName + v.name.dropFirst(r.oldName.count) }
            else { continue }
            guard !(taken[k.navigatorGroup]?.contains(newName) ?? false) else { continue }
            taken[k.navigatorGroup, default: []].insert(newName)
            out.append((v.id, newName))
        }
        return out
    }
}

extension VisibilityGraphics {
    /// Sets (or, with an empty override, clears) the view-specific graphics of elements ("Override Graphics in View").
    public mutating func setElementOverride(_ o: GraphicOverride, for ids: [ElementID]) {
        for id in ids { elementOverrides[id] = o.isEmpty ? nil : o }
    }

    /// The override shared by all the elements, or the first element's when they differ.
    public func commonElementOverride(_ ids: [ElementID]) -> GraphicOverride {
        ids.first.flatMap { elementOverrides[$0] } ?? GraphicOverride()
    }
}
