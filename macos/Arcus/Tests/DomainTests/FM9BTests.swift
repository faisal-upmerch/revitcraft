import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// FM9B (simple Furniture Library pieces, part A): every piece builds with the Furniture mode operations, is listed
/// under its rooms with the right category, has one or two size types and a Material, flexes (every type and Width,
/// Depth and Height moving the whole piece in the document and in its compiled family), passes Check Parts with no
/// errors, and compiles and loads into a project at its size.
@Suite("FM9B simple library pieces") @MainActor
struct FM9BTests {
    static let inch = 0.0254
    nonisolated static let specs = FurnitureLibrary.simpleASpecs
    nonisolated static let names = specs.map(\.name)
    static func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

    static func spec(_ name: String) throws -> SA.Piece { try #require(specs.first { $0.name == name }) }

    /// Every part's box, by element.
    static func boxes(_ m: BIMModel) -> [(Element, Box3)] {
        Category.furnitureParts.flatMap { m.elements($0) }.filter { !$0.isType }.compactMap { e in
            let b = ElementMeshes.parts(e, m, detail: .fine).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
            return b.isEmpty ? nil : (e, b)
        }
    }

    @Test func theListIsComplete() {
        #expect(Set(Self.names).count == Self.names.count, "names are unique")
        #expect(FurnitureLibrary.simpleA.count == Self.specs.count)
        let rooms = Set(Self.specs.flatMap(\.rooms))
        #expect(rooms.isSubset(of: ["Living Room", "Bedroom", "Dining Room", "Kitchen", "Home Office", "Bathroom", "Outdoor & Balcony",
                                    "Kids' Room & Nursery", "Decorative & Accent", "Multipurpose & Space-Saving", "Storage & Utility"]), "\(rooms)")
        for s in Self.specs { #expect((1...2).contains(s.sizes.count) && s.libraryPiece.detail == .simple, "\(s.name)") }
    }

    @Test(arguments: names) func buildsFlexesChecksAndCompiles(_ name: String) throws {
        let spec = try Self.spec(name)
        let m = try spec.build()
        let setup = try #require(m.furnitureSetup)
        #expect(setup.category == spec.category && setup.family.name == name)
        #expect(setup.family.types.map(\.name) == spec.sizes.map(\.name))
        #expect(m[setup.family.types[0].values["Material"]?.refValue]?.name == spec.material, "\(name): Material")
        let parts = Self.boxes(m)
        #expect(parts.count >= 3, "\(name): \(parts.count) parts")

        // Flex in the document: each type moves the planes, and every part stays within Width x Depth x Height.
        #expect(FurnitureParameters.flex(m).isEmpty, "\(name): \(FurnitureParameters.flex(m).prefix(3))")
        for size in spec.sizes {
            let tx = TransactionContext(model: m, name: "Type")
            try FurnitureParameters.setCurrentType(size.name, in: tx)
            let t = try tx.commit().model
            let all = Self.boxes(t).reduce(Box3.empty) { $0.union($1.1) }
            let tol = 1e-4
            #expect(Self.approx(all.max.x - all.min.x, size.w * Self.inch, tol) && Self.approx(all.max.y - all.min.y, size.d * Self.inch, tol)
                    && Self.approx(all.max.z - all.min.z, size.h * Self.inch, tol),
                    "\(name) \(size.name): parts span \(all.max.x - all.min.x) x \(all.max.y - all.min.y) x \(all.max.z - all.min.z)")
        }

        // Check Parts: no errors (warnings and notes are the shop's to review).
        let errors = FurnitureCheckParts.check(m).filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(name): \(errors.prefix(3).map(\.message))")

        // The compiled family: the Flex Test passes and Width, Depth and Height move the whole piece.
        let f = FurnitureCompiler.family(from: m)
        let flex = FamilyEvaluator.flexTest(f, units: .imperial)
        #expect(flex.isEmpty, "\(name): \(flex.prefix(3))")
        for t in f.types {
            let ev0 = FamilyEvaluator.evaluate(f, typeName: t.name, units: .imperial)
            #expect(ev0.errors.isEmpty, "\(name) \(t.name): \(ev0.errors.prefix(2))")
            for (param, axis) in [("Width", 0), ("Depth", 1), ("Height", 2)] {
                for scale in [0.85, 1.25] {
                    var g = f
                    guard let i = g.types.firstIndex(where: { $0.name == t.name }) else { continue }
                    let base = g.types[i].values[param]?.doubleValue ?? 0
                    g.types[i].values[param] = .double(base * scale)
                    let ev = FamilyEvaluator.evaluate(g, typeName: t.name, units: .imperial)
                    let b = ev.bounds, b0 = ev0.bounds
                    let size = [b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z][axis]
                    let size0 = [b0.max.x - b0.min.x, b0.max.y - b0.min.y, b0.max.z - b0.min.z][axis]
                    #expect(ev.errors.isEmpty && Self.approx(size - size0, base * (scale - 1), 1e-4), "\(name) \(t.name) \(param) x\(scale): \(size0) → \(size)")
                }
            }
        }

        // Load into a project and place it: it stands at its size, in its category.
        let project = DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0)
        var fid: ElementID?
        _ = project.perform("Load") { tx in fid = FurnitureLoading.load(f, from: m, replacing: nil, in: tx) }
        #expect(project.lastError == nil)
        let type = try #require(project.model.elements(.elementTypes).first { $0.typeData?.familyID == fid && $0.name == spec.sizes[0].name })
        #expect(type.typeData?.instanceCategory == (spec.category == .casework ? .casework : .furniture))
        var inst: ElementID?
        _ = project.perform("Place") { tx in
            inst = tx.create(type.typeData!.instanceCategory, data: .component(ComponentData(location: .zero)), typeID: type.id, levelID: project.model.levels.first?.id)
        }
        let placed = try #require(inst.flatMap { project.model[$0] })
        for d in [DetailLevel.coarse, .medium, .fine] {
            let b = ElementMeshes.parts(placed, project.model, detail: d).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
            #expect(!b.isEmpty, "\(name): nothing at \(d)")
            if d == .coarse {
                #expect(Self.approx(b.max.x - b.min.x, spec.sizes[0].w * Self.inch, 1e-4) && Self.approx(b.max.z - b.min.z, spec.sizes[0].h * Self.inch, 1e-4),
                        "\(name): placed \(b.max.x - b.min.x) x \(b.max.z - b.min.z)")
            }
        }
    }
}
