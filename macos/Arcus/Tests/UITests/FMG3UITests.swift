import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusOutput
import ArcusPersistence
@testable import ArcusUI

/// FMG3: fronts on any face and the project gaps on screen. A furniture file dropped on a 3D view loads and is placed
/// where it lands; and offscreen renders to `/tmp/arcus-fmg3/` of the views that show the new behaviour: the island's
/// doors in its Back elevation, the Corner Cabinet's canted door in a section looking at the cant and in plan, the
/// Storage Bed's side drawers in its Left elevation and plan, the chest's lid swing in its Right elevation, the Kitchen
/// Cabinet single and as a pair, and a loaded Kitchen Cabinet's door swings in a project elevation.
@MainActor
@Suite("FMG3 Fronts on any face UI", .serialized)
struct FMG3UITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-fmg3")
    static let inch = 0.0254

    /// A view's drawing as a PNG (cropped to the furniture categories, or everything); the number of items drawn.
    @discardableResult
    static func draw(_ m: BIMModel, _ view: Element, _ name: String, crop: Bool = true) -> Int {
        var g = ViewGraphicsBuilder(model: m, view: view).build()
        if crop {
            let shown = Set(ArcusDomain.Category.furnitureParts + ArcusDomain.Category.furnitureOpenings + [.casework, .furniture])
            let pts = g.items.filter { shown.contains($0.category) }.flatMap { $0.primitives.flatMap(Self.points) }
            if !pts.isEmpty { g.crop = Rect2(points: pts).expanded(by: 0.12) }
            if view.view?.kind.isPlan == true { g.items = g.items.filter { shown.contains($0.category) } } // the pieces only: plan annotations are at paper size
        }
        guard let img = RasterExporter.render(g, pixelWidth: 1400, showOverlays: false), let png = RasterExporter.encode(img, as: .png) else { return 0 }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? png.write(to: out.appendingPathComponent("\(name).png"))
        return g.items.count
    }

    static func points(_ p: GPrimitive) -> [Vec2] {
        switch p {
        case .polyline(let pts, _, _): pts
        case .fill(let polys, _): polys.flatMap(\.points)
        default: []
        }
    }

    static func view(_ m: BIMModel, _ kind: ViewKind, _ name: String? = nil) throws -> Element {
        try #require(m.views.first { $0.view?.kind == kind && (name == nil || $0.name == name) })
    }

    /// Adds a section looking along `dir` from `back` meters in front of the origin.
    static func section(_ m: BIMModel, _ name: String, dir: Vec2, back: Double = 1) throws -> (BIMModel, Element) {
        let tx = TransactionContext(model: m, name: "Section")
        var v = ViewData(kind: .section, scale: 12)
        v.planeOrigin = Vec3(dir.normalized * -back, z: 0)
        v.viewDirection = dir.normalized
        v.farClip = 4
        v.detailLevel = .medium
        let id = tx.create(.views, name: name, data: .view(v))
        let c = try tx.commit().model
        return (c, try #require(c[id]))
    }

    @Test func rendersOfFrontsOnEveryFace() throws {
        let island = try #require(FurnitureSamples.islandModel())
        #expect(Self.draw(island, try Self.view(island, .elevation, "Back"), "island-back-elevation") > 0)
        #expect(Self.draw(island, try Self.view(island, .floorPlan), "island-plan") > 0)

        let corner = try #require(FurnitureLibrary.all.first { $0.name == "Corner Cabinet" }).build()
        let (c2, cant) = try Self.section(corner, "Cant", dir: Vec2(-1, 1))
        #expect(Self.draw(c2, cant, "corner-cabinet-cant-section") > 0)
        #expect(Self.draw(c2, try Self.view(c2, .floorPlan), "corner-cabinet-plan") > 0)
        #expect(Self.draw(c2, try Self.view(c2, .elevation, "Front"), "corner-cabinet-front") > 0)

        let bed = try #require(FurnitureLibrary.all.first { $0.name == "Storage Bed" }).build()
        #expect(Self.draw(bed, try Self.view(bed, .elevation, "Left"), "storage-bed-left") > 0)
        #expect(Self.draw(bed, try Self.view(bed, .floorPlan), "storage-bed-plan") > 0)

        let chest = try #require(FurnitureSamples.chestModel())
        #expect(Self.draw(chest, try Self.view(chest, .elevation, "Right"), "chest-lid-right") > 0)
        #expect(Self.draw(chest, try Self.view(chest, .elevation, "Front"), "chest-lid-front") > 0)

        let kitchen = try #require(FurnitureLibrary.all.first { $0.name == "Kitchen Cabinet" }).build()
        for t in ["B15", "B30"] {
            let tx = TransactionContext(model: kitchen, name: "Type")
            try FurnitureParameters.setCurrentType(t, in: tx)
            let k = try tx.commit().model
            #expect(Self.draw(k, try Self.view(k, .elevation, "Front"), "kitchen-cabinet-\(t.lowercased())-front") > 0)
        }
    }

    @Test func projectElevationShowsLoadedSwings() throws {
        let src = try #require(FurnitureLibrary.all.first { $0.name == "Kitchen Cabinet" }).build()
        let f = FurnitureCompiler.family(from: src)
        let s = DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0)
        var fid: ElementID?
        _ = s.perform("Load") { tx in fid = FurnitureLoading.load(f, from: src, replacing: nil, in: tx) }
        var v: ElementID?
        _ = s.perform("Place") { tx in
            for (k, name) in ["B15", "B30", "B36"].enumerated() {
                guard let t = tx.model.elements(.elementTypes).first(where: { $0.typeData?.familyID == fid && $0.name == name }) else { continue }
                tx.create(.casework, data: .component(ComponentData(location: Vec2(Double(k) * 0.95, 0))), typeID: t.id, levelID: tx.model.levels.first?.id)
            }
            var ev = ViewData(kind: .elevation, scale: 24)
            ev.planeOrigin = Vec3(0, -3, 0); ev.viewDirection = Vec2(0, 1); ev.farClip = 10; ev.detailLevel = .medium
            v = tx.create(.views, name: "Kitchen", data: .view(ev))
        }
        #expect(s.lastError == nil)
        #expect(Self.draw(s.model, try #require(s.model[v]), "project-kitchen-elevation") > 0)
    }

    @Test func droppedFurnitureIsPlacedWhereItLands() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appending(path: "fmg3-drop-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Corner Hutch.arcusfurniture")
        let piece = try #require(FurnitureLibrary.all.first { $0.name == "Corner Cabinet" }).build()
        try FurnitureTemplateSaver.save(piece, name: "Corner Hutch", to: url)
        let state = DocumentState(session: DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0))
        let level = state.model.levels.first?.id
        #expect(Viewport3DToolController.loadAndPlace(url, at: Vec2(2, 3), level: level, in: state))
        let placed = try #require(state.session.selection.single.flatMap { state.model[$0] })
        #expect(placed.category == .casework && placed.component?.location.distance(to: Vec2(2, 3)) ?? 1 < 1e-9 && placed.levelID == level)
        #expect(state.model.family(named: "Corner Hutch")?.family?.furnitureSource != nil)
        // A second drop reuses the loaded family.
        #expect(Viewport3DToolController.loadAndPlace(url, at: Vec2(4, 3), level: level, in: state))
        #expect(state.model.elements(.families).filter { $0.name == "Corner Hutch" }.count == 1)
        #expect(state.model.elements(.casework).count == 2)
    }
}
