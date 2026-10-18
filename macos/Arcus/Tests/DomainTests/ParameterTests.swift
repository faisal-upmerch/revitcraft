import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Parameters: parse and format")
struct ParameterFormatTests {
    static let metric = ProjectTemplates.make(.empty, units: UnitsSettings(decimalSeparatorOverride: ".")).0
    static let imperial: BIMModel = {
        var u = UnitsSettings.imperial
        u.decimalSeparatorOverride = "."
        return ProjectTemplates.make(.empty, units: u).0
    }()

    @Test(arguments: [(0.9, "900 mm"), (1.25, "1250 mm"), (0.0004, "0 mm"), (-3.2, "-3200 mm"), (12.3456, "12346 mm")])
    func metricLengthFormat(_ v: Double, _ text: String) {
        #expect(Parameters.format(.double(v), type: .length, model: Self.metric) == text)
    }

    @Test(arguments: [0.001, 0.9, 1.25, 12.345, -3.2, 100.0])
    func metricLengthRoundTrip(_ v: Double) throws {
        let m = Self.metric
        let parsed = try Parameters.parse(Parameters.format(.double(v), type: .length, model: m), type: .length, model: m)
        #expect(Fx.approx(parsed.doubleValue!, v, 1e-9))
    }

    @Test(arguments: [("900", 0.9), ("1.2 m", 1.2), ("3 m + 500", 3.5), ("=2*450", 0.9), ("12 cm", 0.12), (" 75 mm ", 0.075)])
    func metricLengthParsing(_ text: String, _ v: Double) throws {
        #expect(Fx.approx(try Parameters.parse(text, type: .length, model: Self.metric).doubleValue!, v, 1e-12))
    }

    @Test(arguments: [(0.3048, "1' - 0\""), (1.0668, "3' - 6\""), (0.0254 * 13.0625, "1' - 1 1/16\""), (0.0127, "0' - 0 1/2\"")])
    func imperialLengthFormat(_ v: Double, _ text: String) {
        #expect(Parameters.format(.double(v), type: .length, model: Self.imperial) == text)
    }

    @Test(arguments: [0.3048, 1.0668, 0.0254 * 13.0625, 0.0254 * 120, 0.0254 / 16])
    func imperialLengthRoundTrip(_ v: Double) throws {
        let m = Self.imperial
        let parsed = try Parameters.parse(Parameters.format(.double(v), type: .length, model: m), type: .length, model: m)
        #expect(Fx.approx(parsed.doubleValue!, v, 1e-9))
    }

    @Test(arguments: [("3' 6\"", 1.0668), ("3'-6\"", 1.0668), ("3 6", 1.0668), ("6\"", 0.1524), ("2", 0.6096), ("1' 1 1/16\"", 0.0254 * 13.0625)])
    func imperialLengthParsing(_ text: String, _ v: Double) throws {
        #expect(Fx.approx(try Parameters.parse(text, type: .length, model: Self.imperial).doubleValue!, v, 1e-9))
    }

    @Test func otherUnitKindsFormat() {
        let m = Self.metric
        #expect(Parameters.format(.double(12.5), type: .area, model: m) == "12.50 m²")
        #expect(Parameters.format(.double(3), type: .volume, model: m) == "3.00 m³")
        #expect(Parameters.format(.double(.pi / 4), type: .angle, model: m) == "45.00°")
        #expect(Parameters.format(.double(0.25), type: .percentage, model: m) == "25.00%")
        #expect(Parameters.format(.int(7), type: .integer, model: m) == "7")
        #expect(Parameters.format(.bool(true), type: .bool, model: m) == "Yes")
        #expect(Parameters.format(nil, type: .length, model: m) == "")
        #expect(Parameters.format(.double(1), type: .area, model: Self.imperial) == "10.76 SF")
    }

    @Test func elementRefFormatAndParse() throws {
        let (m, ids) = Fx.archMetric
        #expect(Parameters.format(.ref(nil), type: .elementRef(.levels), model: m) == "Unconnected")
        #expect(Parameters.format(.ref(nil), type: .elementRef(.materials), model: m) == "<None>")
        #expect(Parameters.format(.ref(ElementID(987_654_321)), type: .elementRef(.levels), model: m) == "<Missing>")
        let wt = ids.wallTypes[Fx.generic]!
        let text = Parameters.format(.ref(wt), type: .elementRef(.elementTypes), model: m)
        #expect(text == "Basic Wall: Generic - 200mm")
        #expect(try Parameters.parse(text, type: .elementRef(.elementTypes), model: m) == .ref(wt))
        #expect(try Parameters.parse("Level 2", type: .elementRef(.levels), model: m) == .ref(ids.levels[1]))
        #expect(try Parameters.parse("Unconnected", type: .elementRef(.levels), model: m) == .ref(nil))
        #expect(try Parameters.parse("A101", type: .elementRef(.sheets), model: m) == .ref(m.sheets[0].id))
        #expect(throws: ParameterError.self) { try Parameters.parse("Level 9", type: .elementRef(.levels), model: m) }
    }

    @Test(arguments: [("yes", true), ("Y", true), ("on", true), ("1", true), ("No", false), ("off", false), ("0", false), ("FALSE", false)])
    func boolParsing(_ text: String, _ v: Bool) throws {
        #expect(try Parameters.parse(text, type: .bool, model: Self.metric) == .bool(v))
    }

    @Test(arguments: ["maybe", "", "2"])
    func invalidBoolRejected(_ text: String) {
        #expect(throws: ParameterError.self) { try Parameters.parse(text, type: .bool, model: Self.metric) }
    }

    @Test func choiceAndTextParsing() throws {
        let t = ParamType.choice(["Exterior", "Interior"])
        #expect(try Parameters.parse("interior", type: t, model: Self.metric) == .text("Interior"))
        #expect(throws: ParameterError.self) { try Parameters.parse("Roof", type: t, model: Self.metric) }
        #expect(try Parameters.parse("  keep spaces ", type: .text, model: Self.metric) == .text("  keep spaces "))
        #expect(try Parameters.parse("7", type: .integer, model: Self.metric) == .int(7))
        #expect(throws: ParameterError.self) { try Parameters.parse("abc", type: .length, model: Self.metric) }
        #expect(throws: ParameterError.self) { try Parameters.parse("3,5", type: .length, model: Self.metric) }
    }

    @Test func paramValueConversions() {
        #expect(ParamValue.text("2.5").doubleValue == 2.5)
        #expect(ParamValue.double(2.6).intValue == 3)
        #expect(ParamValue.double(.nan).intValue == nil)
        #expect(ParamValue.text("Yes").boolValue == true)
        #expect(ParamValue.text("perhaps").boolValue == nil)
        #expect(ParamValue.ref(nil).description == "<None>")
        #expect(ParamValue.bool(false).description == "No")
    }
}

@Suite("Parameters: reading and writing")
struct ParameterEditTests {
    func wallAndDoor() throws -> (BIMModel, ProjectTemplates.Ids, ElementID, ElementID) {
        var (m, ids) = Fx.template()
        var w: ElementID!, d: ElementID!
        try Fx.commit(&m) { tx in
            w = Fx.wall(tx, ids, .zero, Vec2(8, 0))
            d = Fx.door(tx, ids, host: w, at: Vec2(3, 0))
        }
        return (m, ids, w, d)
    }

    @Test(arguments: ["q.area", "q.volume", "q.length", "elementID", "ifcGUID", "familyName", "typeName", "wall.topAttached"])
    func readOnlyWallParametersRejectWrites(_ key: String) throws {
        let (m, _, w, _) = try wallAndDoor()
        let tx = TransactionContext(model: m, name: "RO")
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID(key), to: .double(1), on: w, in: tx) }
        #expect(!Parameters.isEditable(ParameterID(key), on: m[w]!, m))
        #expect(!tx.hasChanges)
    }

    @Test(arguments: ["insert.fromRoom", "insert.toRoom", "insert.host", "family:Rough Width", "family:Rough Height"])
    func readOnlyDoorParametersRejectWrites(_ key: String) throws {
        let (m, _, _, d) = try wallAndDoor()
        let tx = TransactionContext(model: m, name: "RO")
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID(key), to: .text("x"), on: d, in: tx) }
        #expect(!Parameters.isEditable(ParameterID(key), on: m[d]!, m))
    }

    @Test func formulaDrivenFamilyParameterValue() throws {
        let (m, _, _, d) = try wallAndDoor()
        #expect(Fx.approx(Parameters.value(Parameters.familyParamID("Rough Width"), of: m[d]!, m)!.doubleValue!, 1.0))
        #expect(Fx.approx(Parameters.value(Parameters.familyParamID("Rough Height"), of: m[d]!, m)!.doubleValue!, 2.15))
        #expect(Parameters.entryNamed("Rough Width", m[d]!, m)?.isReadOnly == true)
    }

    @Test func lockedUnconnectedHeightUnlocksWhenTopConstraintCleared() throws {
        var (m, _, w, _) = try wallAndDoor()
        let unconnected = ParameterID("wall.unconnectedHeight")
        #expect(!Parameters.isEditable(unconnected, on: m[w]!, m))
        #expect(Fx.approx(Parameters.value(unconnected, of: m[w]!, m)!.doubleValue!, 4.0), "reports the constrained height")
        do {
            let tx = TransactionContext(model: m, name: "Locked")
            #expect(throws: ParameterError.self) { try Parameters.set(unconnected, to: .double(3), on: w, in: tx) }
        }
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("wall.topConstraint"), to: .ref(nil), on: w, in: tx) }
        #expect(m[w]!.wall!.topLevelID == nil)
        #expect(Fx.approx(m[w]!.wall!.unconnectedHeight, 4.0), "switching to Unconnected keeps the height")
        #expect(Parameters.isEditable(unconnected, on: m[w]!, m))
        #expect(!Parameters.isEditable(ParameterID("wall.topOffset"), on: m[w]!, m))
        try Fx.commit(&m) { tx in try Parameters.set(unconnected, to: .double(3), on: w, in: tx) }
        #expect(Fx.approx(WallGeometry.frame(m[w]!, m)!.height, 3))
    }

    @Test(arguments: [("wall.unconnectedHeight", ParamValue.double(0)), ("wall.slant", .double(1.2)), ("wall.locationLine", .text("Middle")),
                      ("wall.topConstraint", .ref(ElementID(1))), ("level", .ref(nil)), ("wall.roomBounding", .text("perhaps")),
                      ("wall.baseOffset", .double(.infinity))])
    func invalidWallValuesAreRejected(_ key: String, _ value: ParamValue) throws {
        var (m, _, w, _) = try wallAndDoor()
        if key == "wall.unconnectedHeight" {
            try Fx.commit(&m) { tx in tx.update(w) { $0.wall?.topLevelID = nil } }
        }
        let tx = TransactionContext(model: m, name: "Bad")
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID(key), to: value, on: w, in: tx) }
    }

    @Test func phaseOrderIsEnforced() throws {
        var (m, ids, w, _) = try wallAndDoor()
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("phaseCreated"), to: .ref(ids.phases[0]), on: w, in: tx) }
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("phaseDemolished"), to: .ref(ids.phases[0]), on: w, in: tx) }
        #expect(m[w]!.phaseDemolished == ids.phases[0], "created and demolished in the same phase is allowed")
        let tx = TransactionContext(model: m, name: "Bad phase")
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID("phaseCreated"), to: .ref(ids.phases[1]), on: w, in: tx) }
        // Demolished before created.
        var (m2, _, w2, _) = try wallAndDoor()
        try Fx.commit(&m2) { tx in try Parameters.set(ParameterID("phaseCreated"), to: .ref(ids.phases[1]), on: w2, in: tx) }
        let tx2 = TransactionContext(model: m2, name: "Bad phase")
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID("phaseDemolished"), to: .ref(ids.phases[0]), on: w2, in: tx2) }
    }

    @Test func familyAndTypeChangeValidatesCategory() throws {
        var (m, ids, w, _) = try wallAndDoor()
        let brick = ids.wallTypes[Fx.brick]!
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("familyAndType"), to: .ref(brick), on: w, in: tx) }
        #expect(m[w]!.typeID == brick)
        #expect(Fx.approx(WallGeometry.frame(m[w]!, m)!.thickness, 0.38))
        let tx = TransactionContext(model: m, name: "Bad type")
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID("familyAndType"), to: .ref(ids.familyTypes[Fx.doorType]!), on: w, in: tx) }
    }

    @Test func typeParametersAreWrittenToTheType() throws {
        // Template family types are shared by every test; only system (wall) types are edited here so the process-wide
        // family evaluation cache never sees two different edits of the same template type.
        var (m, ids, w, _) = try wallAndDoor()
        var w2: ElementID!
        try Fx.commit(&m) { tx in w2 = Fx.wall(tx, ids, Vec2(0, 5), Vec2(8, 5)) }
        try Fx.commit(&m) { tx in
            try Parameters.set(ParameterID("type.mark"), to: .text("W9"), on: w, in: tx)
            try Parameters.set(ParameterID("type.fireRating"), to: .text("60 min"), on: w, in: tx)
        }
        #expect(m[w]!.params[ParameterID("type.mark")] == nil, "not stored on the instance")
        #expect(Parameters.value(ParameterID("type.mark"), of: m[w2]!, m) == .text("W9"))
        #expect(Parameters.value(ParameterID("type.fireRating"), of: m[w2]!, m) == .text("60 min"))
        #expect(m[ids.wallTypes[Fx.generic]!]!.typeData!.params[ParameterID("type.fireRating")] == .text("60 min"))
    }

    @Test func instanceMarkAndCommentsStayOnInstance() throws {
        var (m, _, w, d) = try wallAndDoor()
        try Fx.commit(&m) { tx in
            try Parameters.set(.mark, to: .text("D-01"), on: d, in: tx)
            try Parameters.set(.comments, to: .text("Keep"), on: w, in: tx)
        }
        #expect(m[d]!.mark == "D-01")
        #expect(m[w]!.comments == "Keep")
        #expect(Parameters.id(named: "Mark", for: m[d]!, m) == .mark)
        #expect(Parameters.descriptor(named: "Comments", for: m[w]!, m)?.id == .comments)
        // Clearing a text parameter removes the stored value.
        try Fx.commit(&m) { tx in try Parameters.set(.mark, to: .text(""), on: d, in: tx) }
        #expect(m[d]!.params[.mark] == nil)
    }

    @Test func projectParametersBindToCategories() throws {
        var (m, ids, w, d) = try wallAndDoor()
        let acoustic = ParameterDefinition(name: "Acoustic Rating", type: .integer, categories: [.walls])
        let cost = ParameterDefinition(name: "Unit Cost", type: .currency, isInstance: false, categories: [.walls])
        let derived = ParameterDefinition(name: "Derived", type: .number, categories: [.walls], formula: "1 + 1")
        try Fx.commit(&m) { tx in tx.setProjectParameters([acoustic, cost, derived]) }
        #expect(Parameters.allEntries(m[w]!, m).contains { $0.id == acoustic.id && !$0.isType })
        #expect(Parameters.allEntries(m[w]!, m).contains { $0.id == cost.id && $0.isType })
        #expect(!Parameters.allEntries(m[d]!, m).contains { $0.id == acoustic.id })
        try Fx.commit(&m) { tx in
            try Parameters.set(acoustic.id, to: .int(52), on: w, in: tx)
            try Parameters.set(cost.id, to: .double(125), on: w, in: tx)
        }
        #expect(Parameters.value(acoustic.id, of: m[w]!, m) == .int(52))
        #expect(m[ids.wallTypes[Fx.generic]!]!.typeData!.params[cost.id] == .double(125))
        #expect(Parameters.value(cost.id, of: m[w]!, m) == .double(125))
        let tx = TransactionContext(model: m, name: "Bad")
        #expect(throws: ParameterError.self) { try Parameters.set(acoustic.id, to: .text("loud"), on: w, in: tx) }
        #expect(throws: ParameterError.self) { try Parameters.set(derived.id, to: .double(3), on: w, in: tx) }
        #expect(!Parameters.isEditable(derived.id, on: m[w]!, m))
    }

    @Test func projectParameterChangesUndoWithTheRecord() throws {
        var (m, _) = Fx.template()
        let before = m
        let p = ParameterDefinition(name: "Zone", type: .text, categories: [.rooms])
        let (rec, _) = try Fx.commit(&m) { tx in tx.setProjectParameters([p]) }
        #expect(m.projectParameters == [p])
        #expect(!rec.isEmpty)
        #expect(m.applying(rec.inverse).projectParameters == before.projectParameters)
    }

    @Test func emptyNamesAreRejectedForLevelsAndViews() throws {
        let (m, ids) = Fx.template()
        // The inspector's entry for a level's Name refuses empty names …
        let level = m[ids.levels[1]]!
        let entry = Parameters.allEntries(level, m).first { $0.id == ParameterID("name") }!
        #expect(!entry.isReadOnly)
        // … and so does Parameters.set, which resolves the element's own built-in definition.
        let tx = TransactionContext(model: m, name: "Rename")
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID("name"), to: .text(""), on: ids.levels[1], in: tx) }
        let tx2 = TransactionContext(model: m, name: "Rename view")
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID("name"), to: .text("   "), on: ids.planViews[ids.levels[0]]!, in: tx2) }
    }

    @Test func isEditableAgreesWithEntriesOnTemplateElements() throws {
        let (m, _, w, d) = try wallAndDoor()
        for e in [m[w]!, m[d]!, m.levels[0], m.views[0], m.sheets[0]] {
            for entry in Parameters.allEntries(e, m) where Parameters.allEntries(e, m).first(where: { $0.id == entry.id })?.name == entry.name {
                #expect(Parameters.isEditable(entry.id, on: e, m) == !entry.isReadOnly, "\(e.category) \(entry.name)")
            }
        }
    }
}

extension Parameters {
    static func entryNamed(_ name: String, _ e: Element, _ m: BIMModel) -> ParameterEntry? { allEntries(e, m).first { $0.name == name } }
}

@Suite("Formulas and families")
struct FormulaTests {
    @Test(arguments: [("900 x 2100", 1.0, 2.15), ("820 x 2040", 0.92, 2.09), ("1000 x 2100", 1.1, 2.15)])
    func doorFamilyFormulas(_ type: String, _ roughW: Double, _ roughH: Double) {
        let values = FamilyEvaluator.parameterValues(StarterLibrary.singleDoor(), typeName: type).values
        #expect(Fx.approx(values["Rough Width"]!.quantityValue!, roughW, 1e-12))
        #expect(Fx.approx(values["Rough Height"]!.quantityValue!, roughH, 1e-12))
    }

    @Test func evaluatedDoorHasOpeningAndSolids() {
        let ev = FamilyEvaluator.evaluate(StarterLibrary.singleDoor(), typeName: "900 x 2100")
        #expect(ev.errors.isEmpty)
        #expect(ev.solids.count == 4)
        let o = ev.opening!
        #expect(Fx.approx(o.xMax - o.xMin, 1.0, 1e-12) && Fx.approx(o.zMax - o.zMin, 2.15, 1e-12))
        #expect(Fx.approx(ev.bounds.size.x, 1.0, 1e-12))
    }

    @Test func instanceOverridesApplyToInstanceParametersOnly() {
        var fam = StarterLibrary.genericBox()
        if let i = fam.parameters.firstIndex(where: { $0.name == "Width" }) { fam.parameters[i].isInstance = true }
        let typeW = fam.types[0].values["Width"]?.doubleValue ?? 0
        let over = FamilyEvaluator.parameterValues(fam, typeName: fam.types[0].name, instance: ["Width": .double(typeW + 1)]).values
        #expect(Fx.approx(over["Width"]!.quantityValue!, typeW + 1, 1e-12))
        let ignored = FamilyEvaluator.parameterValues(StarterLibrary.genericBox(), typeName: fam.types[0].name, instance: ["Width": .double(typeW + 1)]).values
        #expect(Fx.approx(ignored["Width"]!.quantityValue!, typeW, 1e-12), "type parameters ignore instance values")
    }

    /// Every starter family evaluates cleanly across its flex range (geometry offsets carry units, e.g. "Width / 2 - 0.05 m").
    @Test(arguments: StarterLibrary.all.map(\.name))
    func starterFamiliesPassFlexTest(_ name: String) {
        let fam = StarterLibrary.all.first { $0.name == name }!
        #expect(FamilyEvaluator.flexTest(fam) == [])
    }

    @Test func deskLegsHaveTheirDesignedSize() throws {
        let ev = FamilyEvaluator.evaluate(StarterLibrary.desk(), typeName: "1500 x 750")
        let leg = try #require(ev.solids.first { $0.name == "Leg 1" })
        #expect(Fx.approx(leg.profile.bounds.width, 0.05, 1e-9))
        #expect(Fx.approx(leg.zMax, 0.74 - 0.03, 1e-9))
        #expect(ev.errors.isEmpty)
    }

    @Test func circularFamilyFormulasAreReportedNotFatal() {
        var fam = StarterLibrary.genericBox()
        fam.parameters += [
            FamilyParameter(name: "Alpha", type: .length, formula: "Beta + 1 mm"),
            FamilyParameter(name: "Beta", type: .length, formula: "Alpha * 2"),
            FamilyParameter(name: "Gamma", type: .length, formula: "Alpha + Width"),
        ]
        let (values, errors) = FamilyEvaluator.parameterValues(fam, typeName: fam.types[0].name)
        #expect(errors.contains { $0.contains("Alpha") && $0.contains("Circular") })
        #expect(errors.contains { $0.contains("Gamma") && $0.contains("Depends on") })
        #expect(values["Alpha"] == .quantity(0, .length), "failed formulas fall back to the type default")
        let problems = FamilyEvaluator.flexTest(fam)
        #expect(problems.contains { $0.hasPrefix("Circular formula chain") && $0.contains("Alpha") && $0.contains("Beta") })
        #expect(FamilyEvaluator.evaluate(fam, typeName: fam.types[0].name).errors.count >= 3)
    }

    @Test func unparsableFormulaIsReportedByFlexTest() {
        var fam = StarterLibrary.genericBox()
        fam.parameters.append(FamilyParameter(name: "Broken", type: .length, formula: "Width + (2"))
        #expect(FamilyEvaluator.flexTest(fam).contains { $0.contains("Broken") && $0.contains("cannot be parsed") })
        var empty = fam
        empty.types = []
        #expect(FamilyEvaluator.flexTest(empty).contains("The family has no types."))
    }

    @Test func formulaSystemOrdersDependencies() throws {
        let r = FormulaSystem.evaluateAll(formulas: ["x": "y + 1", "y": "2 * z", "z": "3"], inputs: [:])
        #expect(try r["x"]!.get() == .number(7))
        let ordered = FormulaSystem.evaluateAllOrdered(formulas: ["x": "y + 1", "y": "2 * z", "z": "3"], inputs: [:]).map(\.name)
        #expect(ordered == ["z", "y", "x"])
    }

    @Test func formulaSystemReportsCyclesAndDependents() {
        let r = FormulaSystem.evaluateAll(formulas: ["a": "b + 1", "b": "a + 1", "c": "a * 2", "s": "s + 1"], inputs: [:])
        for name in ["a", "b"] {
            guard case .failure(let e) = r[name]! else { Issue.record("\(name) should fail"); continue }
            #expect(e.message.contains("Circular reference"))
        }
        guard case .failure(let c) = r["c"]!, case .failure(let s) = r["s"]! else { Issue.record("c and s should fail"); return }
        #expect(c.message.contains("Depends on 'a'"))
        #expect(s.message.contains("refers to itself"))
        let deps = FormulaSystem.dependencyOrder(formulas: ["a": ["b"], "b": ["a"], "c": ["a"]])
        #expect(deps.cycles == [["a", "b"]])
        #expect(deps.order == ["c"])
    }

    @Test func formulaSystemChecksExpectedKinds() throws {
        let inputs: [String: FormulaValue] = ["W": .quantity(2, .length), "H": .quantity(3, .length)]
        let r = FormulaSystem.evaluateAll(formulas: ["Area": "W * H", "Bad": "W * H", "Zero": "0", "N": "W / 1 m + 0.5"], inputs: inputs,
                                          expected: ["Area": .area, "Bad": .length, "Zero": .length, "N": .integer])
        #expect(try r["Area"]!.get() == .quantity(6, .area))
        guard case .failure(let e) = r["Bad"]! else { Issue.record("dimension mismatch not reported"); return }
        #expect(e.message.contains("Expected"))
        #expect(try r["Zero"]!.get() == .quantity(0, .length))
        #expect(try r["N"]!.get() == .quantity(3, .none), "integers round half away from zero")
    }

    @Test func formulaParserRejectsUnknownNamesAndSyntax() {
        #expect(throws: FormulaError.self) { try Formula("Width + Depth", knownNames: ["Width"]) }
        #expect(throws: FormulaError.self) { try Formula("(1 + 2", knownNames: []) }
        #expect(throws: FormulaError.self) { try Formula(String(repeating: "1+", count: 3000) + "1", knownNames: []) }
    }

    @Test func formulaFunctionsAndConditionals() throws {
        func eval(_ s: String, _ vars: [String: FormulaValue] = [:]) throws -> FormulaValue {
            try Formula(s, knownNames: Set(vars.keys)).evaluate { vars[$0] }
        }
        #expect(try eval("if(W > 1 m, 10, 20)", ["W": .quantity(1.5, .length)]) == .number(10))
        #expect(try eval("and(1 < 2, not(2 < 1))") == .bool(true))
        #expect(try eval("max(1, 5, 3) + min(4, 2)") == .number(7))
        #expect(try eval("sqrt(A)", ["A": .quantity(4, .area)]) == .quantity(2, .length))
        #expect(try eval("round(1.4) + roundup(1.1) + rounddown(1.9)") == .number(4))
    }
}
