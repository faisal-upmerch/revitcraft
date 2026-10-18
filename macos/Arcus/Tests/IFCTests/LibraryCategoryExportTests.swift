import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusIFC

/// Component library categories export with their IFC classes: lights as light fixtures, planting as geographic
/// elements (IFC4), everything else placed from the library as furniture, sanitary terminals or proxies.
@Suite("IFC library categories")
struct LibraryCategoryExportTests {
    struct Placed { var model: BIMModel; var light: ElementID; var tree: ElementID; var car: ElementID; var stall: ElementID; var fan: ElementID }

    static func build() throws -> Placed {
        let b = try TestModel.build()
        let tx = TransactionContext(model: b.model, name: "Library")
        func place(_ name: String, _ p: Vec2) throws -> ElementID {
            let item = try #require(ComponentLibrary.item(named: name))
            let t = try #require(ComponentLibraryLoader.load(item, typeName: item.defaultType(for: .metric).name, in: tx))
            return tx.create(item.category, data: .component(ComponentData(location: p)), typeID: t, levelID: b.ids.levels[0])
        }
        let light = try place("Downlight - Recessed Round", Vec2(3, 3))
        let tree = try place("Tree - Deciduous Round", Vec2(-8, -8))
        let car = try place("Car - Sedan", Vec2(20, -6))
        let stall = try place("Parking Stall - Standard", Vec2(20, -12))
        let fan = try place("Ceiling Fan", Vec2(5, 5))
        let m = try TestModel.fixGUIDs(try tx.commit().model)
        return Placed(model: m, light: light, tree: tree, car: car, stall: stall, fan: fan)
    }

    func entity(_ f: STEPFile, _ m: BIMModel, _ id: ElementID) -> STEPEntity? {
        let g = m[id]!.ifcGUID.value
        return f.order.lazy.compactMap { f[$0] }.first { $0[0].stringValue == g }
    }

    @Test func ifc4() throws {
        let x = try Self.build()
        let f = try TestModel.parse(try TestModel.export(x.model, TestModel.options(.ifc4)).0)
        #expect(entity(f, x.model, x.light)?.type == "IFCLIGHTFIXTURE")
        #expect(entity(f, x.model, x.tree)?.type == "IFCGEOGRAPHICELEMENT")
        #expect(entity(f, x.model, x.car)?.type == "IFCBUILDINGELEMENTPROXY")
        #expect(entity(f, x.model, x.stall)?.type == "IFCBUILDINGELEMENTPROXY")
        #expect(entity(f, x.model, x.fan)?.type == "IFCBUILDINGELEMENTPROXY")
        #expect(f.count("IfcLightFixtureType") == 1 && f.count("IfcGeographicElementType") == 1)
    }

    @Test func ifc2x3() throws {
        let x = try Self.build()
        let f = try TestModel.parse(try TestModel.export(x.model, TestModel.options(.ifc2x3)).0)
        #expect(entity(f, x.model, x.light)?.type == "IFCFLOWTERMINAL")
        #expect(entity(f, x.model, x.tree)?.type == "IFCBUILDINGELEMENTPROXY")
        #expect(f.count("IfcLightFixtureType") == 1 && f.count("IfcGeographicElementType") == 0)
    }
}
