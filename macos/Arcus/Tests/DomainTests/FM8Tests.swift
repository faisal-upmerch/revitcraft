import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

@Suite("FM8 audit") @MainActor
struct FM8AuditTests {
    static let inch = 0.0254

    static func carcass() -> BIMModel {
        let s = DocumentSession(model: FurnitureTemplates.blank(name: "Box"))
        _ = s.perform("Rectangle") { tx in
            let r = Rect2(min: Vec2(-15 * inch, -8 * inch), max: Vec2(15 * inch, 8 * inch))
            _ = try FurniturePartOperations.createPanelRectangle(r, extent: PartExtent(topPlane: nil, height: 24 * inch), in: tx)
        }
        return s.model
    }

    @Test func audit() throws {
        let samples: [(String, BIMModel)] = [("bookcase", FurnitureSamples.bookcaseModel()!), ("table", FurnitureSamples.tableModel()!),
                                             ("cabinet", FurnitureSamples.baseCabinetModel()!), ("carcass", Self.carcass())]
        for (name, m) in samples {
            let t0 = Date()
            let f = FurnitureCompiler.family(from: m)
            print("== \(name): compile \(Date().timeIntervalSince(t0))s solids \(f.solids.count) voids \(f.solids.filter(\.isVoid).count) nested \(f.nestedFamilies.count)/\(f.nestedInstances.count) planLines \(f.planLines.count) modelLines \(f.modelLines.count) planes \(f.referencePlanes.count) dims \(f.dimensions.count)")
            print("   params", f.parameters.map { "\($0.name)[\($0.group.rawValue)\($0.isInstance ? ",inst" : "")]" })
            print("   types", f.types.map(\.name))
            for d in DetailLevel.allCases {
                print("   \(d): solids \(f.solids.filter { $0.visibleAt.contains(d) && !$0.isVoid }.count) lines \(f.planLines.filter { $0.visibleAt.contains(d) }.count) nested \(f.nestedInstances.filter { $0.visibleAt.contains(d) }.count)")
            }
            print("   flex", FamilyEvaluator.flexTest(f, units: .imperial).prefix(5))
            for t in f.types {
                let ev = FamilyEvaluator.evaluate(f, typeName: t.name, units: .imperial)
                print("   type \(t.name): errors \(ev.errors.prefix(3)) bounds \(ev.bounds)")
            }
            for w in [30.0, 72.0] {
                var g = f
                g.types[0].values["Width"] = .double(w * Self.inch)
                let ev = FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
                let dv = ev.solids.filter { $0.name.hasPrefix("DV") && !$0.isVoid }.map { ($0.bounds.min.x + $0.bounds.max.x) / 2 / Self.inch }
                print("   outside:", ev.solids.filter { !$0.isVoid && ($0.bounds.max.x > w / 2 * Self.inch + 1e-4 || $0.bounds.min.x < -w / 2 * Self.inch - 1e-4) }.map { "\($0.name) \($0.bounds.min.x / Self.inch)..\($0.bounds.max.x / Self.inch)" })
                print("   flex W=\(w): errors \(ev.errors.prefix(2)) bounds x \(ev.bounds.min.x / Self.inch)..\(ev.bounds.max.x / Self.inch) dividers \(dv) voids \(ev.solids.filter(\.isVoid).map(\.name).prefix(4))")
            }
            for h in [24.0, 34.5, 50.0, 70.0, 90.0] {
                var g = f
                g.types[0].values["Height"] = .double(h * Self.inch)
                let ev = FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
                let hz = ev.solids.filter { $0.name.hasPrefix(FurnitureHardware.concealedHinge) && $0.name.contains("Plate") }.map { ($0.bounds.min.z / Self.inch * 10).rounded() / 10 }
                print("   flex H=\(h): errors \(ev.errors.prefix(2)) hinge z \(hz.sorted())")
            }
            let source = FurnitureCompiler.source(of: f)
            print("   source bytes \(f.furnitureSource?.count ?? 0) roundtrip \(source?.allElements.count ?? -1)/\(m.allElements.count)")
            // Load and place.
            let project = DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0)
            var fid: ElementID?
            _ = project.perform("Load") { tx in fid = FurnitureLoading.load(f, from: m, replacing: nil, in: tx) }
            let type = try #require(project.model.elements(.elementTypes).first { $0.typeData?.familyID == fid })
            print("   project type params", type.typeData!.params.map { "\($0.key.key)=\($0.value)" }.sorted())
            var inst: ElementID?
            let level = project.model.levels.first?.id
            _ = project.perform("Place") { tx in
                inst = tx.create(type.typeData!.instanceCategory, data: .component(ComponentData(location: .zero)), typeID: type.id, levelID: level)
            }
            for d in DetailLevel.allCases {
                let parts = ElementMeshes.parts(project.model[inst!]!, project.model, detail: d)
                let tris = parts.reduce(0) { $0 + $1.mesh.indices.count / 3 }
                print("   3D \(d): parts \(parts.count) tris \(tris) mats \(Set(parts.compactMap { $0.materialID.flatMap { project.model[$0]?.name } }))")
            }
            let plan = project.model.views.first { $0.view?.kind == .floorPlan && $0.levelID == level }!
            for d in DetailLevel.allCases {
                var pm = project.model
                var v = plan
                v.view?.detailLevel = d
                pm.put(v)
                let g = ViewGraphicsBuilder(model: pm, view: v).build()
                let items = g.items.filter { $0.elementID == inst }
                print("   plan \(d): items \(items.count) prims \(items.reduce(0) { $0 + $1.primitives.count }) layers \(items.map(\.layer))")
            }
        }
    }
}
