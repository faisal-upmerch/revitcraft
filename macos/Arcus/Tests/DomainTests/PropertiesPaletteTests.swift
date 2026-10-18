import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

/// BL-PROPS: Properties palette rows — names, groups and order as BIM users expect, placeholders, hidden rows,
/// "<varies>" only for differing multi-selections, and the "Common (n)" aggregate.
@Suite("Properties palette layout")
@MainActor
struct PropertiesPaletteTests {
    static func names(_ rows: [ParameterEntry], _ g: ParameterGroup) -> [String] { rows.filter { $0.group == g }.map(\.name) }
    static func groupOrder(_ rows: [ParameterEntry]) -> [ParameterGroup] {
        var out: [ParameterGroup] = []
        for r in rows where out.last != r.group { out.append(r.group) }
        return out
    }

    static func fixture() throws -> (m: BIMModel, ids: ProjectTemplates.Ids, walls: [ElementID], door: ElementID, floor: ElementID) {
        var (m, ids) = Fx.template()
        var walls: [ElementID] = [], door = ElementID(0), floor = ElementID(0)
        try Fx.commit(&m) { tx in
            walls = Fx.boxWalls(tx, ids)
            door = Fx.door(tx, ids, host: walls[0], at: Vec2(3, 0))
            floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))))),
                              typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
        }
        return (m, ids, walls, door, floor)
    }

    @Test func wallRowsFollowReferenceNamesGroupsAndOrder() throws {
        let f = try Self.fixture()
        let rows = PaletteLayout.entries(f.m[f.walls[0]]!, f.m)
        #expect(Self.groupOrder(rows) == [.constraints, .crossSection, .structural, .dimensions, .identity, .phasing, .arcus, .ifc])
        #expect(Self.names(rows, .constraints) == ["Location Line", "Base Constraint", "Base Offset", "Base is Attached", "Base Extension Distance",
                                                   "Top Constraint", "Unconnected Height", "Top Offset", "Top is Attached", "Top Extension Distance",
                                                   "Room Bounding", "Related to Mass"])
        #expect(Self.names(rows, .crossSection) == ["Cross-Section", "Angle From Vertical"])
        #expect(Self.names(rows, .structural) == ["Structural", "Structural Usage"])
        #expect(Self.names(rows, .dimensions) == ["Length", "Area", "Volume"])
        #expect(Array(Self.names(rows, .identity).prefix(3)) == ["Image", "Comments", "Mark"])
        #expect(Self.names(rows, .phasing) == ["Phase Created", "Phase Demolished"])
        #expect(Self.names(rows, .arcus).first == "Sweep")
        #expect(Self.names(rows, .arcus).contains("Sweep Material"))
        for hidden in ["Family", "Type", "Family and Type", "Element ID"] { #expect(!rows.contains { $0.name == hidden }, "\(hidden) is hidden") }
        // Placeholders are read-only; Base Constraint is an editable level reference.
        let placeholders = rows.filter { PaletteLayout.isPlaceholder($0.id) }
        #expect(placeholders.count == 6 && placeholders.allSatisfy { $0.isReadOnly })
        let base = try #require(rows.first { $0.name == "Base Constraint" })
        #expect(base.id == ParameterID("level") && base.type == .elementRef(.levels) && !base.isReadOnly)
    }

    @Test func parameterIDsAndSchedulesAreUnchanged() throws {
        let f = try Self.fixture()
        let wall = f.m[f.walls[0]]!
        // Schedules, tags and IFC still see every row (including Family and Type) under the same ids.
        let all = Parameters.instanceEntries(wall, f.m)
        #expect(all.contains { $0.id == ParameterID("familyAndType") } && all.contains { $0.id == ParameterID("elementID") })
        #expect(BuiltInCatalog.byID[ParameterID("level")]?.name == "Level")
        #expect(Parameters.instanceEntries(f.m[f.door]!, f.m).first { $0.id == ParameterID("level") }?.name == "Level")
        // Base Constraint still moves the wall to another level.
        var m = f.m
        try Fx.commit(&m) { tx in
            try Parameters.set(ParameterID("wall.topConstraint"), to: .ref(nil), on: f.walls[0], in: tx)
            try Parameters.set(ParameterID("level"), to: .ref(f.ids.levels[1]), on: f.walls[0], in: tx)
        }
        #expect(m[f.walls[0]]?.levelID == f.ids.levels[1])
    }

    @Test func doorAndFloorGroups() throws {
        let f = try Self.fixture()
        let door = PaletteLayout.entries(f.m[f.door]!, f.m)
        #expect(Array(Self.names(door, .constraints).prefix(2)) == ["Level", "Sill Height"])
        #expect(Self.names(door, .construction).contains("Frame Type"))
        #expect(Array(Self.names(door, .identity).prefix(3)) == ["Image", "Comments", "Mark"])
        #expect(Self.names(door, .other).contains("Head Height"))
        #expect(!Self.names(door, .constraints).contains("Head Height"))
        let order = Self.groupOrder(door)
        #expect(order.firstIndex(of: .identity)! < order.firstIndex(of: .phasing)! && order.last == .other)

        let floor = PaletteLayout.entries(f.m[f.floor]!, f.m)
        #expect(Self.names(floor, .constraints) == ["Level", "Height Offset From Level", "Room Bounding", "Related to Mass"])
        #expect(Self.names(floor, .structural) == ["Structural"])
        #expect(Self.names(floor, .arcus) == ["Slab Edge", "Slab Edge Width", "Slab Edge Depth"])
        #expect(!Self.names(floor, .construction).contains("Slab Edge"))
        let fo = Self.groupOrder(floor)
        #expect(fo.firstIndex(of: .structural)! < fo.firstIndex(of: .dimensions)!)
        #expect(fo.firstIndex(of: .phasing)! < fo.firstIndex(of: .arcus)!)
    }

    @Test func singleElementNeverVaries() throws {
        let f = try Self.fixture()
        // The sweep is off, so its rows have no value — shown blank, not "<varies>".
        let rows = PaletteLayout.aggregate([f.m[f.walls[0]]!], f.m)
        #expect(rows.allSatisfy { !$0.varies })
        #expect(rows.contains { $0.entry.name == "Sweep Height" && $0.entry.value == nil })
    }

    @Test func multiSelectionVariesOnlyWhereValuesDiffer() throws {
        var f = try Self.fixture()
        let two = { [f.m[f.walls[0]]!, f.m[f.walls[1]]!] }
        #expect(PaletteLayout.aggregate(two(), f.m).first { $0.entry.name == "Top Offset" }?.varies == false)
        try Fx.commit(&f.m) { tx in try Parameters.set(ParameterID("wall.topOffset"), to: .double(0.3), on: f.walls[1], in: tx) }
        let rows = PaletteLayout.aggregate(two(), f.m)
        #expect(rows.first { $0.entry.name == "Top Offset" }?.varies == true)
        #expect(rows.first { $0.entry.name == "Location Line" }?.varies == false)
        #expect(rows.first { $0.entry.name == "Sweep Height" }?.varies == false, "unset on both")
    }

    @Test func commonAggregateAcrossCategories() throws {
        let f = try Self.fixture()
        let rows = PaletteLayout.aggregate([f.m[f.walls[0]]!, f.m[f.door]!], f.m)
        let names = rows.map(\.entry.name)
        for n in ["Level", "Comments", "Mark", "Phase Created", "Phase Demolished"] { #expect(names.contains(n), "Common has \(n)") }
        for n in ["Location Line", "Sill Height", "Base Constraint", "Top Constraint"] { #expect(!names.contains(n), "Common lacks \(n)") }
        // Editing Comments under Common applies to both.
        let session = DocumentSession(model: f.m)
        let comments = try #require(rows.first { $0.entry.name == "Comments" })
        session.setParameter(comments.id, value: .text("Check"), on: [f.walls[0], f.door], name: "Comments")
        #expect(session.model[f.walls[0]]?.comments == "Check" && session.model[f.door]?.comments == "Check")
    }

    @Test func typeRowsOrderIdentityAsReference() throws {
        let f = try Self.fixture()
        let t = f.m[f.ids.wallTypes[Fx.brick]!]!
        let rows = PaletteLayout.typeEntries(t, f.m)
        #expect(Self.names(rows, .construction) == ["Width", "Function"])
        #expect(Self.names(rows, .identity) == ["Keynote", "Model", "Manufacturer", "Type Comments", "URL", "Description", "Assembly Code", "Type Mark", "Fire Rating", "Cost"])
        #expect(PaletteLayout.familyLabel(t) == "System Family: Basic Wall")
    }

    @Test func structureRowsAndCoreBoundaries() {
        let l = { (t: Double) in AssemblyLayer(function: .finish1, materialID: nil, thickness: t) }
        var a = CompoundAssembly(layers: [l(0.01), AssemblyLayer(function: .structure, materialID: nil, thickness: 0.2), l(0.02)])
        #expect(a.structureRows == [.layer(0), .coreTop, .layer(1), .coreBottom, .layer(2)])
        // Drag the top boundary above layer 0: the core grows to layers 0–1.
        let grown = a.moving(rows: IndexSet(integer: 1), to: 0)
        #expect(grown.coreStart == 0 && grown.coreEnd == 2 && grown.layers.count == 3)
        // Drag layer 2 into the core.
        let moved = a.moving(rows: IndexSet(integer: 4), to: 3)
        #expect(moved.coreStart == 1 && moved.coreEnd == 3 && moved.layers[2].thickness == 0.02)
        // Boundaries dragged past each other swap roles; an empty core is valid.
        a.coreStart = 1; a.coreEnd = 1
        #expect(a.validate() == nil)
        #expect(a.structureRows == [.layer(0), .coreTop, .coreBottom, .layer(1), .layer(2)])
        let crossed = a.reordered([.layer(0), .coreBottom, .layer(1), .coreTop, .layer(2)])
        #expect(crossed.coreStart == 1 && crossed.coreEnd == 2)
    }

    @Test func typeSearchAndRecentlyUsed() throws {
        let f = try Self.fixture()
        let walls = f.m.types(for: .walls)
        let brick = TypeSelectorModel.sections(types: walls, recent: [], query: "brick").flatMap(\.types)
        #expect(!brick.isEmpty && brick.allSatisfy { f.m[$0]!.name.localizedCaseInsensitiveContains("brick") })
        let anyOrder = TypeSelectorModel.sections(types: walls, recent: [], query: "cmu BRICK").flatMap(\.types)
        #expect(anyOrder.contains(f.ids.wallTypes[Fx.brick]!))
        #expect(TypeSelectorModel.match("Exterior - Brick on CMU", query: "cmu brick")?.count == 2)
        #expect(TypeSelectorModel.match("Generic - 200mm", query: "brick") == nil)
        let generic = f.ids.wallTypes[Fx.generic]!
        let recent = TypeSelectorModel.noteUse(generic, in: TypeSelectorModel.noteUse(f.ids.wallTypes[Fx.brick]!, in: []))
        let sections = TypeSelectorModel.sections(types: walls, recent: recent, query: "")
        #expect(sections.first?.isRecent == true && sections.first?.types.first == generic)
        #expect(sections.dropFirst().allSatisfy { !$0.isRecent })
    }
}
