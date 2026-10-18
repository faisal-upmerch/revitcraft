import Foundation
import CryptoKit
import Testing
@testable import ArcusDomain
@testable import ArcusPersistence

@Suite("Project templates")
struct ProjectTemplatePackageTests {
    @Test func projectSavedAsTemplateStartsNewProjectsWithTypesAndViewsOnly() throws {
        let tmp = TempDir()
        let project = try Sample.richModel()
        #expect(project.allElements.contains { $0.category.isModel })
        let url = tmp.file("Office Standard.arcus")
        try ArcusPackage.writeTemplate(project, to: url, info: Sample.info)

        let (template, manifest) = try ArcusPackage.read(from: url)
        #expect(manifest.isTemplate == true)
        #expect(!template.allElements.contains { $0.category.isModel })

        let fresh = ProjectTemplates.instantiate(template: template, projectName: "New Clinic")
        #expect(!fresh.allElements.contains { $0.category.isModel })
        #expect(Set(fresh.elements(.elementTypes).map(\.name)) == Set(project.elements(.elementTypes).map(\.name)))
        #expect(Set(fresh.elements(.families).map(\.name)) == Set(project.elements(.families).map(\.name)))
        #expect(Set(fresh.views.map(\.name)) == Set(project.views.map(\.name)))
        #expect(Set(fresh.sheets.map(\.name)) == Set(project.sheets.map(\.name)))
        #expect(fresh.elements(.levels).count == project.elements(.levels).count)
        #expect(fresh.projectInfo.projectName == "New Clinic")
        #expect(fresh.projectInfo.units == project.projectInfo.units)

        // An ordinary save carries no template flag.
        let plain = tmp.file("Plain.arcus")
        try ArcusPackage.write(project, to: plain, info: Sample.info)
        #expect(try ArcusPackage.readManifest(plain).isTemplate == nil)
    }
}

@Suite("Family format 2")
struct FamilyFormatTests {
    static func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    /// Rewrites a package as a format-1 family: no format-2 keys in family.json, schema/min reader 1, valid checksums.
    static func downgrade(_ url: URL) throws {
        let fURL = url.appending(path: "family.json")
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: fURL)) as! [String: Any]
        for k in ["nestedFamilies", "nestedInstances", "isShared"] { obj.removeValue(forKey: k) }
        obj["formatVersion"] = 1
        obj["solids"] = (obj["solids"] as! [[String: Any]]).map { s in
            var s = s
            for k in ["visibleIn3D", "visibleInFrontBack", "visibleInLeftRight"] { s.removeValue(forKey: k) }
            return s
        }
        obj["dimensions"] = (obj["dimensions"] as! [[String: Any]]).map { d in var d = d; d.removeValue(forKey: "isLocked"); return d }
        let json = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        try json.write(to: fURL)
        let mURL = url.appending(path: "manifest.json")
        var m = try JSONSerialization.jsonObject(with: Data(contentsOf: mURL)) as! [String: Any]
        m["schemaVersion"] = 1
        m["minimumReaderVersion"] = 1
        m["checksums"] = ["family.json": sha(json)]
        try JSONSerialization.data(withJSONObject: m).write(to: mURL)
    }

    @Test func formatOneFamilyPackagesStillOpen() throws {
        let tmp = TempDir()
        let url = tmp.file("Old Door.arcusfamily")
        let fam = StarterLibrary.singleDoor()
        try FamilyPackage.write(fam, thumbnailPNG: nil, to: url, appVersion: "1.0", build: "1")
        try Self.downgrade(url)
        let (read, _, manifest) = try FamilyPackage.read(from: url)
        #expect(manifest.schemaVersion == 1)
        var expected = fam
        expected.formatVersion = 1
        #expect(read == expected)
        #expect(read.solids.allSatisfy { $0.visibleIn3D && $0.visibleInFrontBack && $0.visibleInLeftRight })
        #expect(read.nestedFamilies.isEmpty && !read.isShared)
        #expect(FamilyEvaluator.flexTest(read) == [])
    }

    @Test func formatTwoFeaturesRoundTripAndRequireReaderTwo() throws {
        let tmp = TempDir()
        var fam = StarterLibrary.genericBox()
        fam.solids.append(FamilySolid(name: "Rail", profile: .sweep(FamilySweep(path: [FamilyPoint(.plane("Left"), .expr("0")), FamilyPoint(.plane("Right"), .expr("0"))],
                                                                              profile: [], profileFamily: "Handrail - Rectangular")),
                                      zMin: .plane("Top"), zMax: .plane("Top")))
        fam.nestedFamilies = [StarterLibrary.handrailProfile()]
        fam.referencePlanes.append(FamilyReferencePlane(name: "Mid", axis: .x, offset: "0.1"))
        fam.dimensions.append(.equality("Left", "Mid", "Right"))
        #expect(FamilyEvaluator.flexTest(fam) == [])
        let plain = tmp.file("Plain.arcusfamily")
        try FamilyPackage.write(StarterLibrary.genericBox(), thumbnailPNG: nil, to: plain, appVersion: "1", build: "1")
        #expect(try FamilyPackage.readManifest(plain).minimumReaderVersion == 1)

        let url = tmp.file("Rail.arcusfamily")
        try FamilyPackage.write(fam, thumbnailPNG: nil, to: url, appVersion: "1", build: "1")
        let (read, _, manifest) = try FamilyPackage.read(from: url)
        #expect(read == fam)
        #expect(manifest.schemaVersion == FamilyPackage.currentSchemaVersion) // F1415: schema 3
        #expect(manifest.minimumReaderVersion == 2)
    }
}
