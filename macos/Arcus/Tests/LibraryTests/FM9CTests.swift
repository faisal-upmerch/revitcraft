import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// FM9C (Furniture Library, simple pieces part B): every piece of the owner's list for this batch is registered under
/// its rooms and category, builds with the Furniture mode operations, has one or two size types and a Material, passes
/// Flex (the document's and the compiled family's), Check Parts with no errors (every part has a material), flexes
/// Width, Depth and Height as a whole (pieces with fixed-size parts excepted, see `SimpleB.partialFlex`), and loads
/// into a project, where an instance draws.
@Suite("FM9C Furniture Library simple pieces B") @MainActor
struct FM9CTests {
    static let inch = 0.0254
    static func piece(_ name: String) throws -> SimpleB.Piece { try #require(SimpleB.pieces.first { $0.name == name }) }

    /// The bounds of the piece's solids without its hardware (stays, slides and pulls come in fixed sizes).
    static func bounds(_ ev: EvaluatedFamily) -> Box3 {
        let hardware = [FurnitureHardware.concealedHinge, FurnitureHardware.faceFrameHinge, FurnitureHardware.buttHinge, FurnitureHardware.pianoHinge,
                        FurnitureHardware.sideMountSlide, FurnitureHardware.undermountSlide, FurnitureHardware.barPull, FurnitureHardware.knob,
                        FurnitureHardware.cupPull, FurnitureHardware.edgePull, FurnitureHardware.flapStay, FurnitureHardware.glide, FurnitureHardware.caster]
        return ev.solids.filter { s in !s.isVoid && !hardware.contains { s.name.hasPrefix($0) } }.reduce(Box3.empty) { $0.union($1.bounds) }
    }

    /// The owner's list for this batch: name and rooms.
    static let list: [(String, [String])] = [
            ("Shoe Cabinet", ["Entryway & Hallway"]),
            ("Shoe Bench", ["Entryway & Hallway"]),
            ("Entryway Console", ["Entryway & Hallway"]),
            ("Coat Rack", ["Entryway & Hallway"]),
            ("Hall Tree", ["Entryway & Hallway"]),
            ("Umbrella Stand", ["Entryway & Hallway"]),
            ("Wall-Mounted Shelf", ["Entryway & Hallway"]),
            ("Key Organizer", ["Entryway & Hallway"]),
            ("Storage Cubby", ["Entryway & Hallway"]),
            ("Hallway Cabinet", ["Entryway & Hallway"]),
            ("Coat Stand", ["Entryway & Hallway"]),
            ("Crib", ["Kids' Room & Nursery"]),
            ("Toddler Bed", ["Kids' Room & Nursery"]),
            ("Kids' Bed", ["Kids' Room & Nursery"]),
            ("Loft Bed", ["Kids' Room & Nursery"]),
            ("Changing Table", ["Kids' Room & Nursery"]),
            ("Nursery Dresser", ["Kids' Room & Nursery"]),
            ("Toy Chest", ["Kids' Room & Nursery"]),
            ("Toy Storage Organizer", ["Kids' Room & Nursery"]),
            ("Kids' Desk", ["Kids' Room & Nursery"]),
            ("Kids' Chair", ["Kids' Room & Nursery"]),
            ("Kids' Bookshelf", ["Kids' Room & Nursery"]),
            ("Play Table", ["Kids' Room & Nursery"]),
            ("High Chair", ["Kids' Room & Nursery"]),
            ("Nursery Glider", ["Kids' Room & Nursery"]),
            ("Kids' Wardrobe", ["Kids' Room & Nursery"]),
            ("Playroom Storage Unit", ["Kids' Room & Nursery"]),
            ("Outdoor Sofa", ["Outdoor & Balcony"]),
            ("Patio Chair", ["Outdoor & Balcony"]),
            ("Outdoor Dining Table", ["Outdoor & Balcony"]),
            ("Outdoor Dining Chair", ["Outdoor & Balcony"]),
            ("Garden Bench", ["Outdoor & Balcony"]),
            ("Sun Lounger", ["Outdoor & Balcony"]),
            ("Hammock", ["Outdoor & Balcony"]),
            ("Hanging Chair", ["Outdoor & Balcony"]),
            ("Outdoor Coffee Table", ["Outdoor & Balcony"]),
            ("Outdoor Side Table", ["Outdoor & Balcony"]),
            ("Picnic Table", ["Outdoor & Balcony"]),
            ("Patio Storage Box", ["Outdoor & Balcony"]),
            ("Outdoor Bar Table", ["Outdoor & Balcony"]),
            ("Folding Chair", ["Outdoor & Balcony", "Multipurpose & Space-Saving"]),
            ("Folding Table", ["Outdoor & Balcony"]),
            ("Swing Bench", ["Outdoor & Balcony"]),
            ("Adirondack Chair", ["Outdoor & Balcony"]),
            ("Plant Stand", ["Outdoor & Balcony", "Decorative & Accent"]),
            ("Modular Storage System", ["Storage & Utility"]),
            ("Drawer Cabinet", ["Storage & Utility"]),
            ("Storage Bench", ["Storage & Utility"]),
            ("Storage Ottoman", ["Storage & Utility"]),
            ("Utility Rack", ["Storage & Utility"]),
            ("Laundry Cabinet", ["Storage & Utility"]),
            ("Ironing Board Cabinet", ["Storage & Utility"]),
            ("Wardrobe Organizer", ["Storage & Utility"]),
            ("Shoe Organizer", ["Storage & Utility"]),
            ("Trunk", ["Storage & Utility"]),
            ("Cube Organizer", ["Storage & Utility"]),
            ("Wall Cabinet", ["Storage & Utility"]),
            ("Freestanding Closet", ["Storage & Utility"]),
            ("Sofa Bed", ["Multipurpose & Space-Saving"]),
            ("Murphy Bed", ["Multipurpose & Space-Saving"]),
            ("Folding Desk", ["Multipurpose & Space-Saving"]),
            ("Folding Dining Table", ["Multipurpose & Space-Saving"]),
            ("Extendable Dining Table", ["Multipurpose & Space-Saving"]),
            ("Convertible Sofa", ["Multipurpose & Space-Saving"]),
            ("Lift-Top Coffee Table", ["Multipurpose & Space-Saving"]),
            ("Stackable Chair", ["Multipurpose & Space-Saving"]),
            ("Modular Sofa", ["Multipurpose & Space-Saving"]),
            ("Transforming Table", ["Multipurpose & Space-Saving"]),
            ("Wall-Mounted Table", ["Multipurpose & Space-Saving"]),
            ("Ottoman Bed", ["Multipurpose & Space-Saving"]),
            ("Drop-Leaf Table", ["Multipurpose & Space-Saving"]),
            ("Trundle Bed", ["Multipurpose & Space-Saving"]),
            ("Convertible Desk", ["Multipurpose & Space-Saving"]),
            ("Accent Table", ["Decorative & Accent"]),
            ("Pedestal Table", ["Decorative & Accent"]),
            ("Display Shelf", ["Decorative & Accent"]),
            ("Curio Cabinet", ["Decorative & Accent"]),
            ("Decorative Console", ["Decorative & Accent"]),
            ("Folding Screen", ["Decorative & Accent"]),
            ("Fireplace Mantel", ["Decorative & Accent"]),
            ("Decorative Bench", ["Decorative & Accent"]),
            ("Accent Cabinet", ["Decorative & Accent"]),
            ("Ladder Shelf", ["Decorative & Accent"]),
            ("Floating Shelf", ["Decorative & Accent"]),
            ("Display Pedestal", ["Decorative & Accent"]),
            ("Sculpture Stand", ["Decorative & Accent"]),
    ]

    @Test func thePiecesAreRegisteredUnderTheirRooms() throws {
        let names = SimpleB.pieces.map(\.name)
        #expect(names.count == 86)
        for (name, rooms) in Self.list {
            let p = SimpleB.pieces.first { $0.name == name }
            #expect(p?.rooms == rooms, "\(name): \(p?.rooms ?? [])")
        }
        #expect(Set(names).count == names.count, "names are unique")
        #expect(FurnitureLibrary.simpleB.count == names.count)
        for p in FurnitureLibrary.simpleB {
            #expect(p.detail == .simple && !p.rooms.isEmpty, "\(p.name)")
            #expect(p.category == .furniture || p.category == .casework, "\(p.name)")
        }
    }

    @Test(arguments: SimpleB.pieces.map(\.name))
    func pieceBuildsFlexesAndPassesCheckParts(_ name: String) throws {
        let p = try Self.piece(name)
        let m = try p.make()
        let setup = try #require(m.furnitureSetup)
        #expect(setup.family.template == p.category, "\(name): category")
        #expect((1...2).contains(setup.family.types.count), "\(name): \(setup.family.types.count) types")
        #expect(setup.family.types.allSatisfy { $0.values["Material"]?.refValue != nil }, "\(name): Material")
        let parts = Category.furnitureParts.flatMap { m.elements($0) }
        #expect(parts.count >= 3, "\(name): \(parts.count) parts")
        #expect(FurnitureParameters.flex(m).isEmpty, "\(name): \(FurnitureParameters.flex(m).prefix(3))")
        let errors = FurnitureCheckParts.check(m).filter { $0.severity == .error || $0.code == "fm7.material" }
        #expect(errors.isEmpty, "\(name): \(errors.prefix(3).map(\.message))")
        // Every type of the document regenerates cleanly.
        for t in setup.family.types {
            let tx = TransactionContext(model: m, name: "Type")
            try FurnitureParameters.setCurrentType(t.name, in: tx)
            let c = try tx.commit()
            #expect(!c.warnings.contains { $0.severity == .error }, "\(name) \(t.name): \(c.warnings.map(\.message).prefix(2))")
        }

        let f = FurnitureCompiler.family(from: m)
        let flex = FamilyEvaluator.flexTest(f, units: .imperial)
        #expect(flex.isEmpty, "\(name): \(flex.prefix(3))")
        for t in f.types {
            let ev0 = FamilyEvaluator.evaluate(f, typeName: t.name, units: .imperial)
            #expect(ev0.errors.isEmpty && !ev0.solids.isEmpty, "\(name) \(t.name): \(ev0.errors.prefix(2))")
            guard !SimpleB.partialFlex.keys.contains(name) else { continue }
            // Width, Depth and Height flex the whole piece (hardware aside), as FM8's samples do.
            for (param, axis) in [("Width", 0), ("Depth", 1), ("Height", 2)] {
                for scale in [0.85, 1.25] {
                    var g = f
                    guard let i = g.types.firstIndex(where: { $0.name == t.name }), let base = g.types[i].values[param]?.doubleValue else { continue }
                    g.types[i].values[param] = .double(base * scale)
                    let ev = FamilyEvaluator.evaluate(g, typeName: t.name, units: .imperial)
                    #expect(ev.errors.isEmpty, "\(name) \(param) x\(scale): \(ev.errors.prefix(2))")
                    let b = Self.bounds(ev), b0 = Self.bounds(ev0)
                    let size = [b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z][axis]
                    let size0 = [b0.max.x - b0.min.x, b0.max.y - b0.min.y, b0.max.z - b0.min.z][axis]
                    #expect(abs((size - size0) - base * (scale - 1)) < 1e-3, "\(name) \(t.name) \(param) x\(scale): \(size0 / Self.inch) → \(size / Self.inch)")
                }
            }
        }
    }

    @Test(arguments: SimpleB.pieces.map(\.name))
    func pieceLoadsIntoAProject(_ name: String) throws {
        let m = try Self.piece(name).make()
        let f = FurnitureCompiler.family(from: m)
        let project = DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0)
        var fid: ElementID?
        _ = project.perform("Load") { tx in fid = FurnitureLoading.load(f, from: m, replacing: nil, in: tx) }
        #expect(project.lastError == nil, "\(name): \(project.lastError?.message ?? "")")
        let types = project.model.elements(.elementTypes).filter { $0.typeData?.familyID == fid }
        #expect(types.count == f.types.count, "\(name): \(types.count) types loaded")
        let type = try #require(types.first)
        var inst: ElementID?
        _ = project.perform("Place") { tx in
            inst = tx.create(type.typeData!.instanceCategory, data: .component(ComponentData(location: Vec2(2, 3))), typeID: type.id, levelID: project.model.levels.first?.id)
        }
        let e = try #require(project.model[try #require(inst)])
        let meshes = ElementMeshes.parts(e, project.model, detail: .medium)
        #expect(!meshes.isEmpty, "\(name) draws in 3D")
        let box = meshes.reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        #expect(box.max.z - box.min.z > 1 * Self.inch, "\(name): \(box)")
    }
}
