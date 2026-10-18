import Foundation
import Synchronization
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

/// Shared fixtures for the Domain/Application test suites.
///
/// Every fixture model gets its own element-id range. Derived-data caches (`RoomBoundaryCache`,
/// `FamilyEvalCache`) are process-wide and keyed by element ids and revisions, so two tests that build
/// different geometry with the same ids could otherwise read each other's cached results when run in parallel.
enum Fx {
    static let doorType = "Door - Single Flush: 900 x 2100"
    static let windowType = "Window - Casement: 1200 x 1500"
    static let generic = "Generic - 200mm"
    static let brick = "Exterior - Brick on CMU"

    static let archMetric = ProjectTemplates.make(.architectural, units: .metric)
    private static let idRange = Atomic<UInt64>(0)

    /// A fresh template model whose new elements get ids no other test uses.
    static func template(_ kind: ProjectTemplateKind = .architectural, units: UnitsSettings = .metric) -> (BIMModel, ProjectTemplates.Ids) {
        let (m, ids) = (kind == .architectural && units == .metric) ? archMetric : ProjectTemplates.make(kind, units: units)
        return (isolated(m), ids)
    }

    /// Copies a model into a unique id range (new elements created on the copy don't collide with other tests).
    static func isolated(_ m: BIMModel) -> BIMModel {
        let k = idRange.add(1, ordering: .relaxed).newValue
        return BIMModel(elements: m.allElements, nextID: m.nextID + k * 100_000, referenceDrawings: m.referenceDrawings,
                        projectParameters: m.projectParameters, viewSheetSets: m.viewSheetSets, revision: m.revision)
    }

    /// Runs `body` in a transaction on `m` and installs the committed model.
    @discardableResult
    static func commit(_ m: inout BIMModel, _ name: String = "Test", _ body: (TransactionContext) throws -> Void) throws -> (record: TransactionRecord, warnings: [ModelWarning]) {
        let tx = TransactionContext(model: m, name: name)
        try body(tx)
        let r = try tx.commit()
        m = r.model
        return (r.record, r.warnings)
    }

    @discardableResult
    static func wall(_ tx: TransactionContext, _ ids: ProjectTemplates.Ids, _ a: Vec2, _ b: Vec2, type: String = generic,
                     level: Int = 0, top: Int? = 1, _ configure: ((inout WallData) -> Void)? = nil) -> ElementID {
        var w = WallData(location: .line(Segment2(a, b)), topLevelID: top.map { ids.levels[$0] })
        configure?(&w)
        return tx.create(.walls, data: .wall(w), typeID: ids.wallTypes[type], levelID: ids.levels[level])
    }

    @discardableResult
    static func door(_ tx: TransactionContext, _ ids: ProjectTemplates.Ids, host: ElementID, at p: Vec2, type: String = doorType, mark: String = "") -> ElementID {
        tx.create(.doors, data: .insert(InsertData(location: p)), typeID: ids.familyTypes[type], levelID: ids.levels[0], hostID: host) { e in
            e.mark = mark
        }
    }

    @discardableResult
    static func window(_ tx: TransactionContext, _ ids: ProjectTemplates.Ids, host: ElementID, at p: Vec2, sill: Double = 0.9, type: String = windowType) -> ElementID {
        tx.create(.windows, data: .insert(InsertData(location: p, sillHeight: sill)), typeID: ids.familyTypes[type], levelID: ids.levels[0], hostID: host)
    }

    /// Four centerline walls around the rectangle (0,0)–(w,h) on Level 1 up to Level 2, in order south, east, north, west (CCW).
    static func boxWalls(_ tx: TransactionContext, _ ids: ProjectTemplates.Ids, w: Double = 10, h: Double = 8, origin: Vec2 = .zero,
                         type: String = generic, level: Int = 0, top: Int? = 1) -> [ElementID] {
        let p = [Vec2(0, 0), Vec2(w, 0), Vec2(w, h), Vec2(0, h)].map { $0 + origin }
        return (0..<4).map { wall(tx, ids, p[$0], p[($0 + 1) % 4], type: type, level: level, top: top) }
    }

    struct Box {
        var model: BIMModel
        let ids: ProjectTemplates.Ids
        let walls: [ElementID]
        var l1: ElementID { ids.levels[0] }
        var l2: ElementID { ids.levels[1] }
        var plan: Element { model[ids.planViews[ids.levels[0]]]! }
    }

    /// A committed 10 × 8 box of 200 mm walls (Level 1 → Level 2), plus anything `extra` adds in the same transaction.
    static func box(w: Double = 10, h: Double = 8, type: String = generic,
                    _ extra: (TransactionContext, ProjectTemplates.Ids, [ElementID]) throws -> Void = { _, _, _ in }) throws -> Box {
        var (m, ids) = template()
        var walls: [ElementID] = []
        try commit(&m, "Box") { tx in
            walls = boxWalls(tx, ids, w: w, h: h, type: type)
            try extra(tx, ids, walls)
        }
        return Box(model: m, ids: ids, walls: walls)
    }

    static func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool { abs(a - b) <= tol }
    static func approx(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6) -> Bool { a.distance(to: b) <= tol }
}
