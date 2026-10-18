import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

/// Family Editor behaviour: dimension constraints (labels, EQ, locks), sweep/blend/revolve forms, voids, nested families,
/// visibility settings and reload modes.
@Suite("Family editor")
struct FamilyEditorTests {
    static func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }

    /// Width-labeled family whose Center plane is sketched off-centre and held midway by an EQ constraint.
    static func eqFamily(originAtLeft: Bool) -> FamilyDefinition {
        var f = FamilyDefinition(name: "EQ Test", template: .genericModel)
        f.parameters = [FamilyParameter(name: "Width", type: .length), FamilyParameter(name: "Height", type: .length)]
        f.types = [FamilyTypeDefinition(name: "900", values: ["Width": .double(0.9), "Height": .double(0.5)])]
        if originAtLeft {
            f.referencePlanes = [FamilyReferencePlane(name: "Left", axis: .x, offset: "0", definesOrigin: true),
                                 FamilyReferencePlane(name: "Center", axis: .x, offset: "0.3"),
                                 FamilyReferencePlane(name: "Right", axis: .x, offset: "0.9")]
        } else {
            f.referencePlanes = [FamilyReferencePlane(name: "Left", axis: .x, offset: "-0.2"),
                                 FamilyReferencePlane(name: "Center", axis: .x, offset: "0", definesOrigin: true),
                                 FamilyReferencePlane(name: "Right", axis: .x, offset: "0.9")]
        }
        f.referencePlanes += [FamilyReferencePlane(name: "Bottom", axis: .z, offset: "0", definesOrigin: true),
                              FamilyReferencePlane(name: "Top", axis: .z, offset: "Height")]
        f.dimensions = [FamilyDimension(planeA: "Left", planeB: "Right", labelParameter: "Width"), .equality("Left", "Center", "Right")]
        f.solids = [FamilySolid(name: "Post", profile: .rectangle(xMin: .plane("Center"), xMax: .expr("0.05"), yMin: .expr("-0.05"), yMax: .expr("0.05")),
                                zMin: .plane("Bottom"), zMax: .plane("Top"))]
        return f
    }

    static func flexed(_ f: FamilyDefinition, _ values: [String: ParamValue]) -> FamilyDefinition {
        var g = f
        for (k, v) in values { g.types[0].values[k] = v }
        return g
    }

    @Test func eqKeepsCentrePlaneAtMidpointWhenWidthFlexes() {
        let f = Self.eqFamily(originAtLeft: true)
        let a = FamilyEvaluator.evaluate(f, typeName: "900")
        #expect(a.errors.isEmpty)
        #expect(Self.approx(a.planes["Right"]!, 0.9))
        #expect(Self.approx(a.planes["Center"]!, 0.45))
        let b = FamilyEvaluator.evaluate(Self.flexed(f, ["Width": .double(1.2)]), typeName: "900")
        #expect(b.errors.isEmpty)
        #expect(Self.approx(b.planes["Left"]!, 0))
        #expect(Self.approx(b.planes["Right"]!, 1.2))
        #expect(Self.approx(b.planes["Center"]!, 0.6))
        #expect(Self.approx(b.dimensionValues[f.dimensions[0].id]!, 1.2))
        // Geometry locked to the centre plane follows it.
        #expect(Self.approx(b.solids[0].profile.bounds.min.x, 0.05))
        #expect(Self.approx(b.solids[0].profile.bounds.max.x, 0.6))
        #expect(FamilyEvaluator.flexTest(f) == [])
    }

    @Test func eqWithFixedCentreGrowsBothSides() {
        let f = Self.flexed(Self.eqFamily(originAtLeft: false), ["Width": .double(1.2)])
        let e = FamilyEvaluator.evaluate(f, typeName: "900")
        #expect(e.errors.isEmpty)
        #expect(Self.approx(e.planes["Left"]!, -0.6))
        #expect(Self.approx(e.planes["Right"]!, 0.6))
        #expect(Self.approx(e.planes["Center"]!, 0))
    }

    @Test func lockedDimensionKeepsSketchedDistance() {
        var f = Self.eqFamily(originAtLeft: true)
        f.referencePlanes.append(FamilyReferencePlane(name: "Trim", axis: .x, offset: "0.95"))
        var lock = FamilyDimension(planeA: "Right", planeB: "Trim")
        lock.isLocked = true
        f.dimensions.append(lock)
        let e = FamilyEvaluator.evaluate(Self.flexed(f, ["Width": .double(1.5)]), typeName: "900")
        #expect(e.errors.isEmpty)
        #expect(Self.approx(e.planes["Trim"]!, 1.55))
    }

    @Test func conflictingDimensionsAreReported() {
        var f = Self.eqFamily(originAtLeft: true)
        f.parameters.append(FamilyParameter(name: "Other", type: .length))
        f.types[0].values["Other"] = .double(0.7)
        f.dimensions.append(FamilyDimension(planeA: "Left", planeB: "Right", labelParameter: "Other"))
        let e = FamilyEvaluator.evaluate(f, typeName: "900")
        #expect(e.conflictingDimensions == [f.dimensions[2].id])
        #expect(e.errors.contains { $0.contains("conflicts") })
        // A redundant but consistent constraint is fine.
        var g = Self.eqFamily(originAtLeft: true)
        g.dimensions.append(FamilyDimension(planeA: "Left", planeB: "Right", labelParameter: "Width"))
        #expect(FamilyEvaluator.evaluate(g, typeName: "900").errors.isEmpty)
    }

    @Test func starterFamiliesAreUnchangedByTheSolver() {
        let door = StarterLibrary.singleDoor()
        let e = FamilyEvaluator.evaluate(door, typeName: "900 x 2100")
        #expect(e.errors.isEmpty)
        #expect(Self.approx(e.planes["Left"]!, -0.45))
        #expect(Self.approx(e.planes["Right"]!, 0.45))
        #expect(Self.approx(e.planes["Top"]!, 2.1))
    }

    // MARK: Forms

    static func formFamily(_ solid: FamilySolid) -> FamilyDefinition {
        var f = FamilyDefinition(name: "Forms", template: .genericModel)
        f.parameters = [FamilyParameter(name: "Length", type: .length)]
        f.types = [FamilyTypeDefinition(name: "T", values: ["Length": .double(1)])]
        f.solids = [solid]
        return f
    }

    @Test func sweepOfSquareProfileHasExpectedVolume() throws {
        let sweep = FamilySweep(path: [FamilyPoint("0", "0"), FamilyPoint("Length", "0")],
                                profile: [FamilyPoint("-0.01", "0"), FamilyPoint("0.01", "0"), FamilyPoint("0.01", "0.02"), FamilyPoint("-0.01", "0.02")])
        let f = Self.formFamily(FamilySolid(name: "Rail", profile: .sweep(sweep), zMin: .expr("0.9"), zMax: .expr("0.9")))
        let e = FamilyEvaluator.evaluate(f, typeName: "T")
        #expect(e.errors.isEmpty)
        let s = try #require(e.solids.first)
        #expect(s.form == .sweep)
        #expect(Self.approx(s.familyMesh.signedVolume, 0.0004, 1e-9))
        #expect(Self.approx(s.zMin, 0.9) && Self.approx(s.zMax, 0.92))
        #expect(Self.approx(s.profile.area, 0.02, 1e-9))
        // An L-shaped path keeps the mitered cross-section: two 1 m legs of a 20 mm square bar.
        var l = sweep
        l.path = [FamilyPoint("0", "0"), FamilyPoint("1", "0"), FamilyPoint("1", "1")]
        let le = FamilyEvaluator.evaluate(Self.formFamily(FamilySolid(name: "L", profile: .sweep(l), zMin: .expr("0"), zMax: .expr("0"))), typeName: "T")
        #expect(Self.approx(le.solids[0].familyMesh.signedVolume, 0.0008, 1e-9))
    }

    @Test func sweepCanUseAnEmbeddedProfileFamily() throws {
        var sweep = FamilySweep(path: [FamilyPoint("0", "0"), FamilyPoint("0", "2")], profile: [])
        sweep.profileFamily = "Handrail - Rectangular"
        var f = Self.formFamily(FamilySolid(name: "Rail", profile: .sweep(sweep), zMin: .expr("0"), zMax: .expr("0")))
        f.nestedFamilies = [StarterLibrary.handrailProfile()]
        let e = FamilyEvaluator.evaluate(f, typeName: "T")
        #expect(e.errors.isEmpty)
        #expect(Self.approx(try #require(e.solids.first).familyMesh.signedVolume, 0.05 * 0.05 * 2, 1e-9))
        f.nestedFamilies = []
        #expect(FamilyEvaluator.evaluate(f, typeName: "T").errors.contains { $0.contains("isn't loaded") })
    }

    @Test func blendBetweenSquaresIsAFrustum() throws {
        func square(_ h: Double) -> [FamilyPoint] {
            [FamilyPoint("\(-h)", "\(-h)"), FamilyPoint("\(h)", "\(-h)"), FamilyPoint("\(h)", "\(h)"), FamilyPoint("\(-h)", "\(h)")]
        }
        let f = Self.formFamily(FamilySolid(name: "Plinth", profile: .blend(FamilyBlend(bottom: square(0.5), top: square(0.25))),
                                            zMin: .expr("0"), zMax: .expr("Length")))
        let e = FamilyEvaluator.evaluate(f, typeName: "T")
        #expect(e.errors.isEmpty)
        let s = try #require(e.solids.first)
        #expect(Self.approx(s.familyMesh.signedVolume, (1 + 0.25 + 0.5) / 3, 1e-9))
        #expect(Self.approx(s.profile.area, 1, 1e-9))
        // Different vertex counts (triangle to square) still make a closed, positive solid.
        let tri = [FamilyPoint("-0.5", "-0.5"), FamilyPoint("0.5", "-0.5"), FamilyPoint("0", "0.5")]
        let g = Self.formFamily(FamilySolid(name: "Morph", profile: .blend(FamilyBlend(bottom: tri, top: square(0.3))), zMin: .expr("0"), zMax: .expr("1")))
        let v = try #require(FamilyEvaluator.evaluate(g, typeName: "T").solids.first).familyMesh.signedVolume
        #expect(v > 0.3 && v < 0.5)
    }

    @Test func revolveMakesACylinderAndAPartialSector() throws {
        let rect = [FamilyPoint("0", "0"), FamilyPoint("0.5", "0"), FamilyPoint("0.5", "Length"), FamilyPoint("0", "Length")]
        let f = Self.formFamily(FamilySolid(name: "Drum", profile: .revolve(FamilyRevolve(profile: rect)), zMin: .expr("0.2"), zMax: .expr("0")))
        let e = FamilyEvaluator.evaluate(f, typeName: "T")
        #expect(e.errors.isEmpty)
        let s = try #require(e.solids.first)
        #expect(abs(s.familyMesh.signedVolume - .pi * 0.25) < 0.01)
        #expect(Self.approx(s.zMin, 0.2) && Self.approx(s.zMax, 1.2))
        let half = Self.formFamily(FamilySolid(name: "Half", profile: .revolve(FamilyRevolve(profile: rect, startDegrees: "90", endDegrees: "270")), zMin: .expr("0"), zMax: .expr("0")))
        let h = try #require(FamilyEvaluator.evaluate(half, typeName: "T").solids.first)
        #expect(abs(h.familyMesh.signedVolume - .pi * 0.125) < 0.01)
        #expect(h.familyMesh.bounds.max.x <= 1e-9)
        let crossing = Self.formFamily(FamilySolid(name: "Bad", profile: .revolve(FamilyRevolve(profile: [FamilyPoint("-0.1", "0"), FamilyPoint("0.5", "0"), FamilyPoint("0.5", "1")])), zMin: .expr("0"), zMax: .expr("0")))
        #expect(FamilyEvaluator.evaluate(crossing, typeName: "T").errors.contains { $0.contains("crosses its axis") })
    }

    @Test func voidExtrusionCutsSolidExtrusion() {
        var f = StarterLibrary.genericBox()
        f.solids.append(FamilySolid(name: "Hole", profile: .rectangle(xMin: .expr("-0.1"), xMax: .expr("0.1"), yMin: .expr("-0.1"), yMax: .expr("0.1")),
                                    zMin: .expr("0.25"), zMax: .expr("0.75"), isVoid: true))
        let e = FamilyEvaluator.evaluate(f, typeName: f.types[0].name)
        #expect(e.errors.isEmpty)
        let volume = e.solids.filter { !$0.isVoid }.reduce(0) { $0 + $1.familyMesh.signedVolume }
        #expect(Self.approx(volume, 1 - 0.04 * 0.5, 1e-9))
        #expect(e.solids.filter { !$0.isVoid }.count == 3)
    }

    // MARK: Nested families

    static func handle() -> FamilyDefinition {
        var h = FamilyDefinition(name: "Handle", template: .genericModel)
        h.parameters = [FamilyParameter(name: "Length", type: .length), FamilyParameter(name: "Finish", type: .elementRef(.materials), group: .materials)]
        h.types = [FamilyTypeDefinition(name: "Standard", values: ["Length": .double(0.2)])]
        h.solids = [FamilySolid(name: "Bar", profile: .rectangle(xMin: .expr("0"), xMax: .expr("Length"), yMin: .expr("0"), yMax: .expr("0.02")),
                                zMin: .expr("0"), zMax: .expr("0.02"), materialParameter: "Finish")]
        h.planLines = [FamilyLine(shape: .line(FamilyPoint("0", "0"), FamilyPoint("Length", "0")))]
        return h
    }

    static func hostWithHandle() -> FamilyDefinition {
        var f = StarterLibrary.genericBox()
        f.parameters.append(FamilyParameter(name: "Handle Finish", type: .elementRef(.materials), group: .materials))
        f.nestedFamilies = [handle()]
        f.nestedInstances = [NestedFamilyInstance(familyName: "Handle", x: .plane("Left"), y: .plane("Front"), z: .expr("Height / 2"),
                                                  bindings: ["Length": "Width / 2", "Finish": "Handle Finish"])]
        return f
    }

    @Test func nestedInstanceFollowsAssociatedHostParameter() throws {
        let f = Self.hostWithHandle()
        let t = f.types[0].name
        let e = FamilyEvaluator.evaluate(f, typeName: t)
        #expect(e.errors.isEmpty)
        let bar = try #require(e.solids.first { $0.name == "Handle: Bar" })
        #expect(Self.approx(bar.profile.bounds.width, 0.5))
        #expect(Self.approx(bar.profile.bounds.min.x, -0.5) && Self.approx(bar.profile.bounds.min.y, -0.5))
        #expect(Self.approx(bar.zMin, 0.5))
        #expect(e.planLines.count == f.planLines.count + 1)

        let wide = FamilyEvaluator.evaluate(Self.flexed(f, ["Width": .double(1.4), "Handle Finish": .ref(ElementID(77))]), typeName: t)
        let wideBar = try #require(wide.solids.first { $0.name == "Handle: Bar" })
        #expect(Self.approx(wideBar.profile.bounds.width, 0.7))
        #expect(Self.approx(wideBar.profile.bounds.min.x, -0.7))
        #expect(wideBar.resolvedMaterial == ElementID(77))
        #expect(FamilyEvaluator.flexTest(f) == [])
    }

    @Test func nestedRotationMirrorAndProblemsAreReported() throws {
        var f = Self.hostWithHandle()
        f.nestedInstances[0].x = .expr("0"); f.nestedInstances[0].y = .expr("0"); f.nestedInstances[0].z = .expr("0")
        f.nestedInstances[0].rotation = "90"
        let e = FamilyEvaluator.evaluate(f, typeName: f.types[0].name)
        let bar = try #require(e.solids.first { $0.name == "Handle: Bar" })
        #expect(Self.approx(bar.profile.bounds.max.y, 0.5) && Self.approx(bar.profile.bounds.min.x, -0.02))
        f.nestedInstances[0].rotation = "0"
        f.nestedInstances[0].mirrored = true
        let m = try #require(FamilyEvaluator.evaluate(f, typeName: f.types[0].name).solids.first { $0.name == "Handle: Bar" })
        #expect(Self.approx(m.profile.bounds.min.x, -0.5) && Self.approx(m.profile.bounds.max.x, 0))

        // A family nested inside itself (directly or through another) is refused, not recursed.
        var loop = Self.handle()
        loop.nestedFamilies = [f]
        loop.nestedInstances = [NestedFamilyInstance(familyName: f.name)]
        var outer = f
        outer.nestedFamilies = [loop]
        outer.nestedInstances = [NestedFamilyInstance(familyName: "Handle")]
        #expect(FamilyEvaluator.evaluate(outer, typeName: outer.types[0].name).errors.contains { $0.contains("contains itself") })

        var missing = f
        missing.nestedInstances[0].bindings["Nope"] = "Width"
        #expect(FamilyEvaluator.evaluate(missing, typeName: f.types[0].name).errors.contains { $0.contains("no parameter “Nope”") })
    }

    // MARK: Visibility

    @Test func visibilitySettingsReachMeshPartsAndViews() throws {
        var (m, ids) = Fx.template()
        var fam = StarterLibrary.genericBox()
        fam.name = "Visibility Box"
        fam.solids[0].visibleIn3D = false
        fam.solids[0].visibleInLeftRight = false
        fam.solids.append(FamilySolid(name: "Coarse Only", profile: .rectangle(xMin: .expr("-0.1"), xMax: .expr("0.1"), yMin: .expr("-0.1"), yMax: .expr("0.1")),
                                      zMin: .expr("1"), zMax: .expr("1.2")))
        fam.solids[1].visibleAt = [.coarse]
        var instance = ElementID(0)
        try Fx.commit(&m) { tx in
            let fid = FamilyProjectLoader.load(fam, replacing: nil, in: tx)
            let tid = try #require(tx.model.elements(.elementTypes).first { $0.typeData?.familyID == fid }?.id)
            instance = tx.create(.genericModels, data: .component(ComponentData(location: Vec2(3, 3), rotation: .pi / 2)), typeID: tid, levelID: ids.levels[0])
        }
        let e = try #require(m[instance])
        let fine = ComponentGeometry.meshParts(e, m, detail: .fine)
        #expect(fine.count == 1)
        let part = try #require(fine.first)
        #expect(!part.isVisibleIn3D)
        // Rotated 90°: the family front (+Y) now faces world −X, so looking along X sees its front.
        #expect(part.isVisible(lookingAlong: Vec2(1, 0)))
        #expect(!part.isVisible(lookingAlong: Vec2(0, 1)))
        #expect(ComponentGeometry.meshParts(e, m, detail: .coarse).count == 2)
    }

    // MARK: Reload

    @Test func reloadKeepsOrOverwritesProjectTypeValues() throws {
        var (m, _) = Fx.template()
        let famElement = try #require(m.family(named: "Door - Single Flush"))
        let typeID = try #require(m.elements(.elementTypes).first { $0.typeData?.familyID == famElement.id && $0.name == "900 x 2100" }?.id)
        let width = Parameters.familyParamID("Width")
        try Fx.commit(&m) { tx in tx.update(typeID) { $0.typeData?.params[width] = .double(0.91) } }

        var edited = try #require(famElement.family)
        let i = try #require(edited.types.firstIndex { $0.name == "900 x 2100" })
        edited.types[i].values["Width"] = .double(0.95)
        edited.types.append(FamilyTypeDefinition(name: "700 x 2100", values: edited.types[i].values.merging(["Width": .double(0.7)]) { $1 }))

        var keep = m
        try Fx.commit(&keep) { tx in FamilyProjectLoader.load(edited, replacing: famElement.id, mode: .keepProjectValues, in: tx) }
        #expect(keep[typeID]?.typeData?.params[width] == .double(0.91))
        #expect(keep.elements(.elementTypes).contains { $0.typeData?.familyID == famElement.id && $0.name == "700 x 2100" })
        #expect(keep[famElement.id]?.family == edited)

        var over = m
        try Fx.commit(&over) { tx in FamilyProjectLoader.load(edited, replacing: famElement.id, mode: .overwriteValues, in: tx) }
        #expect(over[typeID]?.typeData?.params[width] == .double(0.95))
    }

    @Test func sharedNestedFamiliesLoadIntoTheProject() throws {
        var (m, _) = Fx.template()
        var host = Self.hostWithHandle()
        host.name = "Cabinet With Handle"
        host.nestedFamilies[0].isShared = true
        try Fx.commit(&m) { tx in FamilyProjectLoader.load(host, replacing: nil, in: tx) }
        #expect(m.family(named: "Cabinet With Handle") != nil)
        let handle = try #require(m.family(named: "Handle"))
        #expect(m.elements(.elementTypes).contains { $0.typeData?.familyID == handle.id && $0.name == "Standard" })
        var plain = Self.hostWithHandle()
        plain.name = "Box With Private Handle"
        var n = Fx.template().0
        try Fx.commit(&n) { tx in FamilyProjectLoader.load(plain, replacing: nil, in: tx) }
        #expect(n.family(named: "Handle") == nil)
    }

    // MARK: Format

    @Test func formatOneFamiliesDecodeWithDefaults() throws {
        let fam = StarterLibrary.singleDoor()
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fam)) as! [String: Any]
        for k in ["nestedFamilies", "nestedInstances", "isShared"] { obj.removeValue(forKey: k) }
        obj["formatVersion"] = 1
        obj["solids"] = (obj["solids"] as! [[String: Any]]).map { s in
            var s = s
            for k in ["visibleIn3D", "visibleInFrontBack", "visibleInLeftRight"] { s.removeValue(forKey: k) }
            return s
        }
        obj["dimensions"] = (obj["dimensions"] as! [[String: Any]]).map { d in var d = d; d.removeValue(forKey: "isLocked"); return d }
        let old = try JSONDecoder().decode(FamilyDefinition.self, from: JSONSerialization.data(withJSONObject: obj))
        var expected = fam
        expected.formatVersion = 1
        #expect(old == expected)
        #expect(old.minimumReaderVersion == 1)
        var v2 = fam
        v2.solids.append(FamilySolid(name: "S", profile: .sweep(FamilySweep(path: [], profile: [])), zMin: .expr("0"), zMax: .expr("0")))
        #expect(v2.minimumReaderVersion == 2)
    }

    // MARK: Templates

    @Test func templateModelKeepsTypesAndViewsButNoModelElements() throws {
        var b = try Fx.box()
        try Fx.commit(&b.model) { tx in _ = Fx.door(tx, b.ids, host: b.walls[0], at: Vec2(5, 0)) }
        let t = ProjectTemplates.templateModel(from: b.model)
        #expect(!t.allElements.contains { $0.category.isModel })
        #expect(Set(t.elements(.elementTypes).map(\.id)) == Set(b.model.elements(.elementTypes).map(\.id)))
        #expect(Set(t.views.map(\.id)) == Set(b.model.views.map(\.id)))
        #expect(t.elements(.levels).count == b.model.elements(.levels).count)
        let p = ProjectTemplates.instantiate(template: t, projectName: "Library")
        #expect(p.projectInfo.projectName == "Library")
        #expect(p.count == t.count)
        #expect(Set(p.allElements.map(\.ifcGUID)).isDisjoint(with: Set(t.allElements.map(\.ifcGUID))))
    }
}
