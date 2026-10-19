import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

/// FM9 (the Furniture Library): every essential piece builds with the Furniture mode operations, flexes for each of its
/// types, passes Check Parts without errors, compiles to a family and loads into a project; the kit's recipes do the
/// same; the generator writes files that open as Furniture documents, and the catalog lists a piece under every room.
@Suite("FM9 Furniture Library") @MainActor
struct FM9Tests {
    static let inch = 0.0254

    /// Problems with a library piece: a build error, Check Parts errors, Flex problems, types that don't evaluate or
    /// don't take their size, and a family that doesn't load into a project.
    /// What stands proud of a piece's Width, Depth and Height besides handles (inches): a vanity's backsplash and faucet
    /// stand above its counter (its Height).
    static let above: [String: Double] = ["Bathroom Vanity": 10]

    static func problems(_ name: String, _ m: BIMModel) -> [String] {
        var out: [String] = []
        if let e = LibraryKit.buildError(m) { return ["\(name): build failed: \(e)"] }
        let parts = Category.furnitureParts.reduce(0) { $0 + m.elements($1).count }
        if parts < 4 { out.append("\(name): only \(parts) parts") }
        for w in FurnitureCheckParts.check(m) where w.severity == .error { out.append("\(name): Check Parts: \(w.message)") }
        out += FurnitureParameters.flex(m).map { "\(name): Flex: \($0)" }
        let f = FurnitureCompiler.family(from: m)
        out += FamilyEvaluator.flexTest(f, units: .imperial).prefix(3).map { "\(name): family Flex: \($0)" }
        for t in f.types {
            let ev = FamilyEvaluator.evaluate(f, typeName: t.name, units: .imperial)
            out += ev.errors.prefix(3).map { "\(name) “\(t.name)”: \($0)" }
            let bx = ev.bounds
            for (param, size) in [("Width", bx.max.x - bx.min.x), ("Depth", bx.max.y - bx.min.y), ("Height", bx.max.z - bx.min.z)] {
                guard let v = t.values[param]?.doubleValue else { continue }
                // Handles and pulls stand proud of the front.
                let over = size - v
                let allowed = param == "Depth" ? 1.75 : param == "Height" ? 0.75 + (Self.above[name] ?? 0) : 0.75
                if over < -0.75 * inch || over > allowed * inch { out.append("\(name) “\(t.name)”: \(param) \(v / inch)\" but the piece is \(size / inch)\"") }
            }
        }
        // Loads into a project and places an instance of every type.
        let project = ProjectTemplates.make(.architectural, units: .imperial).0
        let tx = TransactionContext(model: project, name: "Load")
        let fid = FurnitureLoading.load(f, from: m, replacing: nil, in: tx)
        let types = tx.model.elements(.elementTypes).filter { $0.typeData?.familyID == fid }
        if types.count != f.types.count { out.append("\(name): \(types.count) project types for \(f.types.count) family types") }
        for (k, t) in types.enumerated() {
            tx.create(t.typeData!.instanceCategory, data: .component(ComponentData(location: Vec2(Double(k) * 3, 0))), typeID: t.id, levelID: tx.model.levels.first?.id)
        }
        do {
            let p = try tx.commit().model
            for e in p.elements(.furniture) + p.elements(.casework) where ElementMeshes.parts(e, p, detail: .fine).isEmpty {
                out.append("\(name): an instance has no geometry")
            }
        } catch {
            out.append("\(name): loading failed: \(error)")
        }
        return out
    }

    // MARK: Essentials

    @Test func everyEssentialBuildsFlexesChecksAndLoads() throws {
        let essentials = FurnitureLibrary.essentials
        #expect(essentials.count >= 25)
        for p in essentials {
            let m = p.build()
            #expect(m.furnitureSetup?.name == p.name)
            #expect((m.furnitureSetup?.family.types.count ?? 0) >= 2, "\(p.name): \(m.furnitureSetup?.family.types.count ?? 0) types")
            let problems = Self.problems(p.name, m)
            #expect(problems.isEmpty, "\(problems.prefix(8).joined(separator: "\n"))")
        }
    }

    // MARK: Kit recipes

    @Test func kitRecipesBuildFlexAndLoad() throws {
        let pieces: [(String, BIMModel)] = [
            ("carcass", LibraryKit.piece("Kit Cabinet", category: .casework, sizes: [.init("24\"", w: 24, d: 20, h: 30), .init("36\"", w: 36, d: 20, h: 30)]) { b in
                try b.carcass(CarcassSpec(columns: [CarcassColumn(CarcassRow(.door, shelves: 1), CarcassRow(.drawers(1), height: 5)),
                                                CarcassColumn(CarcassRow(.drawers(3)))]))
            }),
            ("table", LibraryKit.piece("Kit Table", sizes: [.init("48\"", w: 48, d: 30, h: 30), .init("60\"", w: 60, d: 36, h: 30)]) { b in
                try b.table(TableSpec(drawer: (width: 18, height: 3.5, type: nil)))
            }),
            ("chair", LibraryKit.piece("Kit Chair", sizes: [.init("Standard", w: 18, d: 20, h: 34)]) { b in
                try b.chair(ChairSpec(seat: .upholstered(material: "Fabric - Oatmeal Linen", thickness: 2), stretchers: (type: "3/4\" x 1 1/2\" Stretcher", height: 6)))
            }),
            ("bed", LibraryKit.piece("Kit Bed", sizes: [.init("Queen", w: 64, d: 86, h: 44), .init("King", w: 80, d: 86, h: 44)]) { b in
                try b.bed(BedSpec(headboard: .upholstered(material: "Fabric - Sage Boucle", thickness: 3, channels: 6)))
            }),
            ("shelving", LibraryKit.piece("Kit Shelving", sizes: [.init("36\"", w: 36, d: 14, h: 72)]) { b in
                try b.shelving(ShelvingSpec(brace: "3/4\" x 3/4\" Cleat"))
            }),
            ("sofa", LibraryKit.piece("Kit Sofa", sizes: [.init("72\"", w: 72, d: 36, h: 34), .init("84\"", w: 84, d: 36, h: 34)]) { b in
                try b.upholstered(UpholsteredSpec(seats: 3, pillows: 2))
            }),
        ]
        for (name, m) in pieces {
            let p = Self.problems(name, m)
            #expect(p.isEmpty, "\(p.prefix(6).joined(separator: "\n"))")
        }
    }
}
