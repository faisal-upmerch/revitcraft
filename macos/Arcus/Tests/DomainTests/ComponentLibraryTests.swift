import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

/// The built-in component library: integrity of every family and type, unit-system naming, and lazy loading into
/// projects (a family is added only when one of its types is first used).
@Suite("Component library")
struct ComponentLibraryTests {
    static let items = ComponentLibrary.items

    @Test func libraryIsLargeAndCoversEveryCategory() {
        #expect(Self.items.count >= 150, "families: \(Self.items.count)")
        #expect(ComponentLibrary.typeCount >= 400, "types: \(ComponentLibrary.typeCount)")
        for c in ComponentLibrary.categories {
            #expect(!ComponentLibrary.items(in: [c]).isEmpty, "no items in \(c.displayName)")
        }
        for r in LibraryRegion.allCases where r != .global {
            #expect(Self.items.contains { $0.regions.contains(r) }, "no items tagged \(r.rawValue)")
        }
    }

    @Test func namesAreUnique() {
        var seen = Set(StarterLibrary.all.map(\.name))
        for item in Self.items {
            #expect(!seen.contains(item.name), "duplicate family name \(item.name)")
            seen.insert(item.name)
            let typeNames = item.family.types.map(\.name)
            #expect(Set(typeNames).count == typeNames.count, "duplicate type names in \(item.name)")
            #expect(!typeNames.isEmpty, "\(item.name) has no types")
        }
    }

    @Test func metadataMatchesFamilies() {
        for item in Self.items {
            #expect(item.category.isComponentCategory, "\(item.name): \(item.category) is not placed by the Component tool")
            #expect(item.family.template.category == item.category, "\(item.name): template and category differ")
            #expect(item.types.map(\.name) == item.family.types.map(\.name), "\(item.name): type metadata out of sync")
            #expect(!item.regions.isEmpty && !item.summary.isEmpty && !item.group.isEmpty, "\(item.name): missing metadata")
            for p in item.family.parameters where p.type == .elementRef(.materials) {
                #expect(item.materials[p.name] != nil, "\(item.name): no default for \(p.name)")
            }
            for t in item.types {
                let v = item.family.type(named: t.name)?.values
                #expect(v?["Width"]?.doubleValue == t.width && v?["Depth"]?.doubleValue == t.depth && v?["Height"]?.doubleValue == t.height,
                        "\(item.name): \(t.name) sizes differ from its values")
            }
        }
    }

    @Test func everyTypeEvaluatesToSaneGeometry() {
        for item in Self.items {
            for t in item.family.types {
                let ev = FamilyEvaluator.evaluate(item.family, typeName: t.name)
                #expect(ev.errors.isEmpty, "\(item.name): \(t.name): \(ev.errors.prefix(3))")
                let solids = ev.solids.filter { !$0.isVoid }
                #expect(!solids.isEmpty, "\(item.name): \(t.name) has no solids")
                for s in solids {
                    #expect(!s.familyMesh.isEmpty, "\(item.name): \(t.name): solid \(s.name) has no mesh")
                }
                #expect(!ev.planLines.isEmpty, "\(item.name): \(t.name) has no plan symbol")
                let b = ev.bounds
                let w = t.values["Width"]?.doubleValue ?? 0, d = t.values["Depth"]?.doubleValue ?? 0, h = t.values["Height"]?.doubleValue ?? 0
                #expect(w > 0.004 && d > 0.004 && h > 0.001 && w < 25 && d < 25 && h < 20, "\(item.name): \(t.name) nominal size \(w) x \(d) x \(h)")
                // Extra type lengths (aisles, skews, loft heights…) extend the footprint beyond Width x Depth.
                let extras = item.family.parameters.filter { !$0.isInstance && !$0.isBuiltIn && $0.type == .length }
                    .compactMap { t.values[$0.name]?.doubleValue }.reduce(0, +)
                let reach = max(w, d) * 1.6 + 1.5 + extras
                #expect(b.max.x - b.min.x <= reach && b.max.y - b.min.y <= reach, "\(item.name): \(t.name) geometry spreads beyond its size")
                // Wall- and ceiling-mounted items rise to their mounting height (an instance parameter).
                let mount = item.family.parameters.filter(\.isInstance).compactMap { t.values[$0.name]?.doubleValue }.max() ?? 0
                #expect(b.min.z >= -0.05 && b.max.z <= max(h, 0.2) * 1.3 + 2.2 + mount, "\(item.name): \(t.name) height out of range \(b.min.z)…\(b.max.z)")
                // The plan symbol should sit over the family's footprint.
                var pb = Rect2.empty
                for l in ev.planLines { pb.include(l.curve.bounds) }
                #expect(pb.max.x - pb.min.x <= reach && pb.max.y - pb.min.y <= reach, "\(item.name): \(t.name) plan symbol too large")
            }
        }
    }

    @Test func typeNamesFollowTheirUnitSystem() {
        for item in Self.items {
            for t in item.types {
                let marks = t.name.contains("\"") || t.name.contains("'")
                switch t.system {
                case .imperial: #expect(marks, "\(item.name): imperial type \(t.name) has no feet/inch marks")
                case .metric, .neutral: #expect(!marks, "\(item.name): \(t.system) type \(t.name) uses feet/inch marks")
                }
            }
            let imperial = item.types(for: .imperial), metric = item.types(for: .metric)
            #expect(!imperial.isEmpty && !metric.isEmpty)
            if item.types.contains(where: { $0.system != .metric }) {
                #expect(imperial.allSatisfy { $0.system != .metric }, "\(item.name): metric sizes offered to imperial projects")
            }
            if item.types.contains(where: { $0.system != .imperial }) {
                #expect(metric.allSatisfy { $0.system != .imperial }, "\(item.name): imperial sizes offered to metric projects")
            }
            #expect(item.types.contains(item.defaultType(for: .metric)) && item.types.contains(item.defaultType(for: .imperial)))
        }
        let beds = ComponentLibrary.item(named: "Bed - US Standard")!
        #expect(beds.types.map(\.name).contains("Queen 60\" x 80\""))
        #expect(beds.types(for: .imperial).allSatisfy { $0.system == .imperial })
    }

    @Test func searchAndCategoryFilters() {
        #expect(ComponentLibrary.search("queen").contains { $0.name.hasPrefix("Bed") })
        #expect(ComponentLibrary.search("wc wall").contains { $0.category == .plumbingFixtures })
        let site = ComponentLibrary.items(in: ComponentLibrary.siteCategories)
        #expect(site.allSatisfy { ComponentLibrary.siteCategories.contains($0.category) })
        for c in ComponentLibrary.siteCategories { #expect(site.contains { $0.category == c }) }
        #expect(ComponentLibrary.items(in: []).count == Self.items.count)
        let india = ComponentLibrary.search("", region: .india)
        #expect(india.allSatisfy { $0.regions.contains(.india) || $0.regions.contains(.global) })
        #expect(india.count < Self.items.count)
    }

    @Test func projectsLoadFamiliesLazily() throws {
        var (m, ids) = Fx.template()
        let familiesBefore = m.elements(.families).count
        let typesBefore = m.elements(.elementTypes).count
        for item in Self.items { #expect(ComponentLibraryLoader.loadedFamily(item, m) == nil, "\(item.name) is in a new project") }

        let bed = try #require(ComponentLibrary.item(named: "Bed - European"))
        var first: ElementID?
        try Fx.commit(&m) { tx in first = ComponentLibraryLoader.load(bed, typeName: "1600 x 2000", in: tx) }
        let typeID = try #require(first)
        #expect(m.elements(.families).count == familiesBefore + 1)
        #expect(m.elements(.elementTypes).count == typesBefore + 1)
        let fam = try #require(m.family(named: bed.name)?.family)
        #expect(fam.types.map(\.name) == ["1600 x 2000"], "only the used type is embedded")
        #expect(m[typeID]?.typeData?.instanceCategory == .furniture)
        // Material parameters point at project materials.
        let td = try #require(m[typeID]?.typeData)
        for (param, lm) in bed.materials {
            let ref = td.params[Parameters.familyParamID(param)]?.refValue
            #expect(ref != nil && m[ref!]?.name == lm.name, "\(param) has no material")
        }

        // Same type again: nothing new. Another type: one new type, same family.
        var again: ElementID?
        try Fx.commit(&m) { tx in again = ComponentLibraryLoader.load(bed, typeName: "1600 x 2000", in: tx) }
        #expect(again == typeID)
        #expect(m.elements(.elementTypes).count == typesBefore + 1)
        var second: ElementID?
        try Fx.commit(&m) { tx in second = ComponentLibraryLoader.load(bed, typeName: "900 x 2000", in: tx) }
        #expect(second != nil && second != typeID)
        #expect(m.elements(.families).count == familiesBefore + 1)
        #expect(m.family(named: bed.name)?.family?.types.count == 2)
        #expect(ComponentLibraryLoader.loadedTypeNames(bed, m) == ["1600 x 2000", "900 x 2000"])

        // Place it and check it draws.
        var placed: ElementID?
        try Fx.commit(&m) { tx in
            placed = tx.create(.furniture, data: .component(ComponentData(location: Vec2(2, 3), rotation: 0)), typeID: typeID, levelID: ids.levels[0])
        }
        let e = try #require(m[try #require(placed)])
        #expect(!ComponentGeometry.meshParts(e, m).isEmpty)
        #expect(!ComponentGeometry.planSymbols(e, m).isEmpty)
        let b = ElementMeshes.bounds(e, m)
        #expect(abs((b.max.x - b.min.x) - 1.68) < 0.05, "placed bed width \(b.max.x - b.min.x)")
    }

    @Test func newCategoriesLoadPlaceAndSchedule() throws {
        var (m, ids) = Fx.template()
        for name in ["Tree - Deciduous Round", "Downlight - Recessed Round", "Parking Stall - Standard", "Person - Standing", "Ceiling Fan"] {
            let item = try #require(ComponentLibrary.item(named: name), "missing \(name)")
            let tname = item.defaultType(for: .metric).name
            var tid: ElementID?
            try Fx.commit(&m) { tx in tid = ComponentLibraryLoader.load(item, typeName: tname, in: tx) }
            let t = try #require(tid)
            #expect(m[t]?.typeData?.instanceCategory == item.category)
            var placed: ElementID?
            try Fx.commit(&m) { tx in
                placed = tx.create(item.category, data: .component(ComponentData(location: Vec2(5, 5), rotation: 0)), typeID: t, levelID: ids.levels[0])
            }
            let e = try #require(m[try #require(placed)])
            #expect(!ComponentGeometry.meshParts(e, m).isEmpty, "\(name) has no 3D geometry once placed")
            #expect(item.category.isModel && Category.schedulable.contains(item.category))
        }
    }

    @Test func imperialProjectsGetImperialSizes() throws {
        var (m, _) = Fx.template(units: .imperial)
        let sofa = try #require(ComponentLibrary.item(named: "Sofa - 3 Seat"))
        let t = sofa.defaultType(for: m.units.system)
        #expect(t.system == .imperial && t.name.contains("\""))
        try Fx.commit(&m) { tx in _ = ComponentLibraryLoader.load(sofa, typeName: t.name, in: tx) }
        #expect(ComponentLibraryLoader.loadedTypeNames(sofa, m) == [t.name])
    }
}
