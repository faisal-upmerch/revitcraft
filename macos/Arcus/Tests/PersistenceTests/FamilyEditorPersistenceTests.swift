import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusPersistence

/// Family Editor ▸ Save As… / Load Family / Reload Family through `.arcusfamily` and `.arcus` packages (ARCUS-088).
@Suite("Family editor persistence")
struct FamilyEditorPersistenceTests {
    /// A New Family (Furniture) with an added plane driven by a labeled "Top Thickness" dimension and a second type.
    static func authored() -> FamilyDefinition {
        var f = StarterLibrary.genericBox()
        f.template = .furniture
        f.name = "Bench"
        f.types = [FamilyTypeDefinition(name: "1200", values: ["Width": .double(1.2), "Depth": .double(0.4), "Height": .double(0.45),
                                                               "Top Thickness": .double(0.04)])]
        f.addTemplateOriginConstraints()
        f.parameters.append(FamilyParameter(name: "Top Thickness", type: .length))
        f.parameters.append(FamilyParameter(name: "Seat Area", type: .area, formula: "Width * Depth"))
        f.referencePlanes.append(FamilyReferencePlane(name: "Underside", axis: .z, offset: "0.4"))
        var d = FamilyDimension(planeA: "Underside", planeB: "Top", labelParameter: "Top Thickness")
        d.fixLabelDirection(FamilyEvaluator.evaluate(f, typeName: "1200").planes)
        f.dimensions.append(d)
        f.solids = [FamilySolid(name: "Seat", profile: .rectangle(xMin: .plane("Left"), xMax: .plane("Right"), yMin: .plane("Front"), yMax: .plane("Back")),
                                zMin: .plane("Underside"), zMax: .plane("Top"), materialParameter: "Material")]
        f.types.append(FamilyTypeDefinition(name: "1800", values: f.types[0].values.merging(["Width": .double(1.8)]) { $1 }))
        return f
    }

    static func commit(_ m: inout BIMModel, _ body: (TransactionContext) throws -> Void) throws {
        let tx = TransactionContext(model: m, name: "Test")
        try body(tx)
        m = try tx.commit().model
    }

    static func bounds(_ id: ElementID, _ m: BIMModel) -> Box3 {
        guard let e = m[id] else { return .empty }
        return ComponentGeometry.meshParts(e, m).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
    }

    @Test func savedFamilyReopensAndProjectKeepsLoadedFamily() throws {
        let tmp = TempDir()
        let fam = Self.authored()
        #expect(FamilyEvaluator.flexTest(fam) == [])
        let famURL = tmp.file("Bench.arcusfamily")
        try FamilyPackage.write(fam, thumbnailPNG: nil, to: famURL, appVersion: "1", build: "1")
        let (read, _, manifest) = try FamilyPackage.read(from: famURL)
        #expect(read == fam)
        #expect(read.dimensions.last?.direction == 1)
        #expect(manifest.elementCount == 2 && manifest.minimumReaderVersion == 2)

        // Load Family from disk, place, save the project, reopen: the family, its types and the instance geometry survive.
        var (m, ids) = ProjectTemplates.make(.architectural, units: .metric)
        var inst = ElementID(0)
        try Self.commit(&m) { tx in
            let fid = FamilyProjectLoader.load(read, replacing: nil, in: tx)
            let tid = try #require(tx.model.elements(.elementTypes).first { $0.typeData?.familyID == fid && $0.name == "1800" }?.id)
            inst = tx.create(.furniture, data: .component(ComponentData(location: Vec2(2, 3))), typeID: tid, levelID: ids.levels[0])
        }
        let before = Self.bounds(inst, m)
        #expect(abs(before.max.x - before.min.x - 1.8) < 1e-9 && abs(before.max.z - before.min.z - 0.04) < 1e-9)
        let projURL = tmp.file("Bench Project.arcus")
        try ArcusPackage.write(m, to: projURL, info: Sample.info)
        let (reopened, _) = try ArcusPackage.read(from: projURL)
        #expect(reopened.family(named: "Bench")?.family == fam)
        #expect(Set(reopened.elements(.elementTypes).filter { $0.typeData?.familyName == "Bench" }.map(\.name)) == ["1200", "1800"])
        let after = Self.bounds(inst, reopened)
        #expect(after.min.distance(to: before.min) < 1e-9 && after.max.distance(to: before.max) < 1e-9)
    }

    @Test func reloadingAResavedFamilyUpdatesTheReopenedProject() throws {
        let tmp = TempDir()
        let famURL = tmp.file("Bench.arcusfamily")
        try FamilyPackage.write(Self.authored(), thumbnailPNG: nil, to: famURL, appVersion: "1", build: "1")
        var (m, ids) = ProjectTemplates.make(.architectural, units: .metric)
        var inst = ElementID(0), fid = ElementID(0)
        try Self.commit(&m) { tx in
            fid = FamilyProjectLoader.load(try FamilyPackage.read(from: famURL).0, replacing: nil, in: tx)
            let tid = try #require(tx.model.elements(.elementTypes).first { $0.typeData?.familyID == fid && $0.name == "1200" }?.id)
            inst = tx.create(.furniture, data: .component(ComponentData(location: .zero)), typeID: tid, levelID: ids.levels[0])
        }
        let projURL = tmp.file("P.arcus")
        try ArcusPackage.write(m, to: projURL, info: Sample.info)

        // Edit in the Family Editor and Save As… over the same file, then Reload Family ▸ Use Family Values.
        var edited = try FamilyPackage.read(from: famURL).0
        edited.types[0].values["Top Thickness"] = .double(0.06)
        edited.types[0].values["Height"] = .double(0.5)
        let firstID = try FamilyPackage.readManifest(famURL).documentID
        try FamilyPackage.write(edited, thumbnailPNG: nil, to: famURL, appVersion: "1", build: "2")
        #expect(try FamilyPackage.readManifest(famURL).documentID == firstID)
        var (project, _) = try ArcusPackage.read(from: projURL)
        try Self.commit(&project) { tx in FamilyProjectLoader.load(try FamilyPackage.read(from: famURL).0, replacing: fid, mode: .overwriteValues, in: tx) }
        let b = Self.bounds(inst, project)
        #expect(abs(b.min.z - 0.44) < 1e-9 && abs(b.max.z - 0.5) < 1e-9)
    }
}
