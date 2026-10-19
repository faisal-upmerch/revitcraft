import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// FM3 (Furniture mode foundation): the blank template, parametric planes that follow Family Types, labelled
/// dimensions that set their parameters, compiling to a family that flexes, loading into a project, and the mode's
/// ribbon tabs, command gating and Project Browser.
@Suite("FM3 Furniture document") @MainActor
struct FM3Tests {
    static let inch = 0.0254
    static func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

    static func plane(_ m: BIMModel, _ name: String) -> Element { m.elements(.referencePlanes).first { $0.name == name }! }
    static func position(_ m: BIMModel, _ name: String) -> Double? { FurniturePlanes.position(plane(m, name).referencePlane!) }
    static func length(_ m: BIMModel, _ name: String) -> Double? {
        if case .quantity(let v, _)? = FurnitureParameters.value(name, m) { return v }
        return nil
    }

    // MARK: Template

    @Test func blankTemplateIsAnImperialFurnitureDocument() {
        let m = FurnitureTemplates.blank(category: .furniture, name: "Side Table")
        #expect(m.isFurniture)
        #expect(m.units == .imperial)
        let s = try! #require(m.furnitureSetup)
        #expect(s.name == "Side Table" && s.category == .furniture)
        #expect(s.family.parameters.map(\.name) == ["Width", "Depth", "Height", "Material"])
        #expect(s.family.types.count == 1 && s.currentType == "36\" x 18\" x 30\"")
        #expect(Self.approx(Self.length(m, "Width"), 36 * Self.inch))
        #expect(Self.approx(Self.length(m, "Depth"), 18 * Self.inch))
        #expect(Self.approx(Self.length(m, "Height"), 30 * Self.inch))
        // Ref. Level and the views.
        #expect(m.levels.map(\.name) == ["Ref. Level"])
        let views = Set(m.views.compactMap { v in v.view.map { "\($0.kind.rawValue): \(v.name)" } })
        for v in ["Floor Plan: Ref. Level", "Elevation: Front", "Elevation: Back", "Elevation: Left", "Elevation: Right", "3D View: {3D}"] {
            #expect(views.contains(v), "missing \(v) in \(views)")
        }
        #expect(m.sheets.count == 1)
        let sheet = m.sheets[0]
        #expect(sheet.sheet?.paper == .ansiB && sheet.sheet?.titleBlockTypeID != nil)
        #expect(m.owned(byView: sheet.id).filter { $0.viewport != nil }.count == 4)
        // The eight planes with Revit-style strengths, in their default places.
        let planes = Dictionary(uniqueKeysWithValues: FurniturePlanes.all(m).map { ($0.name, $0.referencePlane!.furniture!) })
        #expect(Set(planes.keys) == ["Center (Left/Right)", "Center (Front/Back)", "Left", "Right", "Front", "Back", "Bottom", "Top"])
        #expect(planes["Left"]?.strength == .left && planes["Top"]?.strength == .top && planes["Center (Front/Back)"]?.strength == .centerFrontBack)
        #expect(planes["Bottom"]?.axis == .z && planes["Bottom"]?.definesOrigin == true)
        #expect(Self.approx(Self.position(m, "Right"), 18 * Self.inch))
        #expect(Self.approx(Self.position(m, "Front"), -9 * Self.inch))
        #expect(Self.approx(Self.position(m, "Top"), 30 * Self.inch))
        // Labelled dimensions and EQ in plan and elevations.
        let dims = m.elements(.dimensions).compactMap(\.dimension)
        #expect(Set(dims.compactMap(\.labelParameter)) == ["Width", "Depth", "Height"])
        #expect(dims.filter(\.equality).count == 4)
        // Materials with costs and units.
        let ply = try! #require(m.elements(.materials).first { $0.name == "Plywood" }?.material)
        #expect(ply.cost == 85 && ply.costUnit == .sheet)
        let names = Set(m.elements(.materials).map(\.name))
        for n in ["MDF", "Particleboard", "Melamine", "Solid Oak", "Solid Walnut", "Solid Maple", "Solid Ash", "Solid Pine", "Laminate", "Veneer",
                  "Glass", "Steel", "Brass", "Fabric", "Leather", "Foam"] { #expect(names.contains(n), "missing \(n)") }
        #expect(m.elements(.materials).first { $0.name == "Solid Walnut" }?.material?.costUnit == .boardFoot)
    }

    @Test func caseworkCategoryIsStored() {
        let m = FurnitureTemplates.blank(category: .casework, name: "Base Cabinet")
        #expect(m.furnitureSetup?.category == .casework)
        #expect(FurnitureShell.modeTitle(m) == "Furniture · Casework")
        #expect(FurnitureShell.modeTitle(ProjectTemplates.make(.empty, units: .imperial).0) == nil)
    }

    // MARK: Parameters move planes

    @Test func changingWidthMovesLeftAndRightAboutTheCenter() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        _ = s.perform("Width") { tx in try FurnitureParameters.setValue("Width", .double(48 * Self.inch), in: tx) }
        #expect(s.lastError == nil)
        #expect(Self.approx(Self.position(s.model, "Left"), -24 * Self.inch))
        #expect(Self.approx(Self.position(s.model, "Right"), 24 * Self.inch))
        #expect(Self.approx(Self.position(s.model, "Center (Left/Right)"), 0))
        // The planes still span the piece.
        let front = Self.plane(s.model, "Front").referencePlane!.line
        #expect(min(front.start.x, front.end.x) < -24 * Self.inch && max(front.start.x, front.end.x) > 24 * Self.inch)
        _ = s.perform("Height") { tx in try FurnitureParameters.setValue("Height", .double(42 * Self.inch), in: tx) }
        #expect(Self.approx(Self.position(s.model, "Top"), 42 * Self.inch))
        // Undo restores the planes with the value.
        s.undoManager.undo()
        #expect(Self.approx(Self.position(s.model, "Top"), 30 * Self.inch))
    }

    @Test func formulaParametersDrivePlanesAndCannotBeSet() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        _ = s.perform("Formula") { tx in
            try FurnitureParameters.edit(tx) { setup in
                setup.family.parameters.append(FamilyParameter(name: "Inset", type: .length, formula: "Width / 12"))
            }
            let id = tx.create(.referencePlanes, name: "Inset Line", data: .referencePlane(
                FurniturePlanes.make(axis: .x, formula: "-Width / 2 + Inset", strength: .weak, origin: false, at: 0, extents: (-1...1, -1...1, 0...1))))
            _ = id
        }
        #expect(s.lastError == nil)
        #expect(Self.approx(Self.position(s.model, "Inset Line"), -18 * Self.inch + 3 * Self.inch))
        _ = s.perform("Set") { tx in try FurnitureParameters.setValue("Inset", .double(0.1), in: tx) }
        #expect(s.lastError?.message.contains("formula") == true)
        _ = s.perform("Width") { tx in try FurnitureParameters.setValue("Width", .double(24 * Self.inch), in: tx) }
        #expect(Self.approx(Self.position(s.model, "Inset Line"), -12 * Self.inch + 2 * Self.inch))
    }

    @Test func typesSwitchTheDrivingValues() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        _ = s.perform("New Type") { tx in
            try FurnitureParameters.edit(tx) { setup in
                FamilyEditing.addType(&setup.family, named: "Large", copying: setup.currentType)
                let i = setup.family.types.firstIndex { $0.name == "Large" }!
                setup.family.types[i].values["Width"] = .double(60 * Self.inch)
            }
            try FurnitureParameters.setCurrentType("Large", in: tx)
        }
        #expect(s.lastError == nil)
        #expect(Self.approx(Self.position(s.model, "Right"), 30 * Self.inch))
        _ = s.perform("Type") { tx in try FurnitureParameters.setCurrentType("36\" x 18\" x 30\"", in: tx) }
        #expect(Self.approx(Self.position(s.model, "Right"), 18 * Self.inch))
    }

    @Test func renamingAParameterUpdatesFormulasAndLabels() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        _ = s.perform("Rename") { tx in
            var setup = tx.model.furnitureSetup!
            setup.family.parameters[0].isBuiltIn = false
            try FurnitureParameters.edit(tx) { $0 = setup }
            try FurnitureParameters.renameParameter("Width", to: "Overall Width", in: tx)
        }
        #expect(s.lastError == nil)
        #expect(Self.plane(s.model, "Right").referencePlane?.furniture?.offsetFormula == "Overall Width / 2")
        #expect(s.model.elements(.dimensions).contains { $0.dimension?.labelParameter == "Overall Width" })
        #expect(!s.model.elements(.dimensions).contains { $0.dimension?.labelParameter == "Width" })
        #expect(Self.approx(Self.position(s.model, "Right"), 18 * Self.inch))
    }

    // MARK: Dimensions drive parameters

    @Test func draggingAPlaneWithALabelledDimensionChangesTheParameter() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        let right = Self.plane(s.model, "Right").id
        _ = s.perform("Drag Right") { tx in
            try ElementOperations.transform([right], by: .translation(Vec2(6 * Self.inch, 0)), in: tx, viewID: nil)
        }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        // Right lands where it was put; Left follows by EQ; Width shows the new distance.
        #expect(Self.approx(Self.position(s.model, "Right"), 24 * Self.inch, 1e-5))
        #expect(Self.approx(Self.position(s.model, "Left"), -24 * Self.inch, 1e-5))
        #expect(Self.approx(Self.length(s.model, "Width"), 48 * Self.inch, 1e-5))
    }

    @Test func typingIntoALabelledDimensionSetsTheParameter() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        let m = s.model
        let plan = m.views.first { $0.view?.kind == .floorPlan }!
        let right = Self.plane(m, "Right").id
        let dims = SelectionDimensions.permanent(for: right, in: m, view: plan, scale: 12)
        let width = try #require(dims.first { $0.labelParameter == "Width" })
        _ = s.perform("Width") { tx in try SelectionDimensions.apply(width, value: 40 * Self.inch, in: tx, viewID: plan.id) }
        #expect(s.lastError == nil)
        #expect(Self.approx(Self.length(s.model, "Width"), 40 * Self.inch))
        #expect(Self.approx(Self.position(s.model, "Right"), 20 * Self.inch))
        // The Height label is editable in the front elevation.
        let front = m.views.first { $0.name == "Front" }!
        let top = Self.plane(m, "Top").id
        let h = try #require(SelectionDimensions.permanent(for: top, in: s.model, view: front, scale: 12).first { $0.labelParameter == "Height" })
        #expect(Self.approx(h.value, 30 * Self.inch, 1e-6))
        _ = s.perform("Height") { tx in try SelectionDimensions.apply(h, value: 34 * Self.inch, in: tx, viewID: front.id) }
        #expect(Self.approx(Self.position(s.model, "Top"), 34 * Self.inch))
    }

    @Test func labelledDimensionsShowTheirParameterAndMeasureHorizontalPlanes() {
        let m = FurnitureTemplates.blank()
        let front = m.views.first { $0.name == "Front" }!
        let height = m.elements(.dimensions).first { $0.dimension?.labelParameter == "Height" }!
        #expect(Self.approx(AnnotationGeometry.measure(height, m).first, 30 * Self.inch))
        let g = ViewGraphicsBuilder(model: m, view: front).build()
        let texts = g.items.flatMap(\.primitives).compactMap { p -> String? in if case .text(let t) = p { return t.string }; return nil }
        #expect(texts.contains { $0.hasPrefix("Height = ") }, "\(texts)")
        #expect(texts.contains("Top") && texts.contains("Left"), "reference planes are drawn in the elevation")
        // Bottom and Top are not drawn in the plan; Left and Front are.
        let plan = m.views.first { $0.view?.kind == .floorPlan }!
        let pg = ViewGraphicsBuilder(model: m, view: plan).build()
        let planIDs = Set(pg.items.compactMap(\.elementID))
        #expect(!planIDs.contains(Self.plane(m, "Top").id) && planIDs.contains(Self.plane(m, "Left").id))
    }

    @Test func newPlanesDrawnInFurnitureGetAnAxis() {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        var id: ElementID?
        _ = s.perform("Plane") { tx in id = tx.create(.referencePlanes, name: "Shelf Line", data: .referencePlane(ReferencePlaneData(line: Segment2(Vec2(-1, 0.1), Vec2(1, 0.1))))) }
        #expect(s.model[id]?.referencePlane?.furniture?.axis == .y)
        #expect(Self.approx(FurnitureBoundResolver(s.model).resolve(.plane("Shelf Line", offset: 0.02)), 0.12))
        #expect(FurnitureBoundResolver(s.model).resolve(.value(0.5)) == 0.5)
        #expect(FurnitureBoundResolver(s.model).bind(18 * Self.inch, axisPlanes: ["Left", "Right"]) == .plane("Right", offset: 0))
    }

    // MARK: Compile, flex and load

    @Test func compiledFamilyFlexesAndKeepsTheSource() throws {
        var m = FurnitureTemplates.blank(name: "Console")
        let tx = TransactionContext(model: m, name: "Line")
        tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(-0.3, 0), Vec2(0.3, 0))))), levelID: m.levels[0].id)
        m = try tx.commit().model
        let f = FurnitureCompiler.family(from: m)
        #expect(f.name == "Console" && f.template == .furniture)
        #expect(f.referencePlanes.count == 8)
        #expect(f.referencePlanes.first { $0.name == "Right" }?.offset == "Width / 2")
        #expect(f.dimensions.contains { $0.labelParameter == "Width" } && f.dimensions.contains(where: \.isEquality))
        #expect(f.parameters.map(\.name) == ["Width", "Depth", "Height", "Material"])
        #expect(f.planLines.count == 1)
        #expect(FamilyEvaluator.flexTest(f, units: .imperial).isEmpty, "\(FamilyEvaluator.flexTest(f, units: .imperial))")
        #expect(FurnitureParameters.flex(m).isEmpty)
        let ev = FamilyEvaluator.evaluate(f, typeName: f.types[0].name, units: .imperial)
        #expect(Self.approx(ev.planes["Right"], 18 * Self.inch) && Self.approx(ev.planes["Top"], 30 * Self.inch))
        // Edit Family: the source reopens as the same Furniture document.
        let back = try #require(FurnitureCompiler.source(of: f))
        #expect(back.isFurniture && back.count == m.count && back.furnitureSetup == m.furnitureSetup)
    }

    @Test func flexReportsPlanesThatCross() {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        _ = s.perform("Break") { tx in
            let right = Self.plane(tx.model, "Right").id
            tx.update(right) { $0.referencePlane?.furniture?.offsetFormula = "-Width" }
        }
        #expect(!FurnitureParameters.flex(s.model).isEmpty)
    }

    @Test func loadingIntoAProjectCreatesTheFamilyTypesAndMaterials() throws {
        let piece = FurnitureTemplates.blank(category: .casework, name: "Vanity")
        let family = FurnitureCompiler.family(from: piece)
        let project = DocumentSession(model: ProjectTemplates.make(.empty, units: .imperial).0)
        var fid: ElementID?
        _ = project.perform("Load Family") { tx in fid = FurnitureLoading.load(family, from: piece, replacing: nil, in: tx) }
        #expect(project.lastError == nil)
        let fam = try #require(project.model[fid]?.family)
        #expect(fam.template == .casework && fam.furnitureSource != nil)
        let type = try #require(project.model.elements(.elementTypes).first { $0.typeData?.familyID == fid })
        #expect(type.typeData?.instanceCategory == .casework)
        // Materials match by name (the project already has Plywood) or are copied in with their costs.
        let mat = type.typeData?.params[Parameters.familyParamID("Material")]?.refValue
        #expect(project.model[mat]?.name == "Plywood")
        let tx = TransactionContext(model: piece, name: "Rename")
        tx.update(piece.elements(.materials).first { $0.name == "Plywood" }!.id) { $0.name = "Baltic Birch" }
        let renamed = try tx.commit().model
        _ = project.perform("Load Other") { tx in
            var f = FurnitureCompiler.family(from: renamed); f.name = "Vanity 2"
            FurnitureLoading.load(f, from: renamed, replacing: nil, in: tx)
        }
        let birch = project.model.elements(.materials).first { $0.name == "Baltic Birch" }
        #expect(birch?.material?.costUnit == .sheet && birch?.material?.cost == 85)
        // Reloading replaces the family instead of adding another.
        _ = project.perform("Reload") { tx in FurnitureLoading.load(family, from: piece, replacing: fid, in: tx) }
        #expect(project.model.elements(.families).filter { $0.name == "Vanity" }.count == 1)
    }

    // MARK: Mode in the shell

    @Test func ribbonTabsAndCommandsDependOnTheMode() {
        #expect(FurnitureShell.ribbonTabs(.furniture) == ["Create", "Insert", "Annotate", "Fabricate", "View", "Manage", "Modify"])
        #expect(FurnitureShell.ribbonTabs(.project).first == "Architecture")
        #expect(FurnitureShell.defaultTab(.furniture) == "Create")
        #expect(FurnitureShell.disabledReason(.wall, kind: .furniture) != nil)
        #expect(FurnitureShell.disabledReason(.level, kind: .furniture)?.contains("Ref. Level") == true)
        #expect(FurnitureShell.disabledReason(.referencePlane, kind: .furniture) == nil)
        #expect(FurnitureShell.disabledReason(.furnitureFamilyTypes, kind: .project) != nil)
        #expect(FurnitureShell.disabledReason(.furnitureFamilyTypes, kind: .furniture) == nil)
        #expect(FurnitureShell.disabledReason(.newFurniture, kind: .project) == nil)
        #expect(CommandCatalog.info(.furnitureFamilyTypes).shortcut == nil && CommandCatalog.info(.furnitureLoadIntoProject).shortcut == nil)
    }

    @Test func projectBrowserTreeDependsOnTheMode() {
        let m = FurnitureTemplates.blank()
        let tree = ProjectBrowserTree.build(m)
        #expect(tree.map(\.title) == ["Views", "Sheets", "Schedules", "Nesting", "Families", "Parts", "Parameters and Types"])
        let views = tree[0].children!.map(\.title)
        #expect(views.starts(with: ["Floor Plans", "Elevations"]) && views.contains("3D Views"), "\(views)")
        let params = ProjectBrowserTree.find("furniture.paramlist", in: tree)?.children?.map(\.title) ?? []
        #expect(Set(params) == ["Width", "Depth", "Height", "Material"])
        #expect(ProjectBrowserTree.find(FurnitureBrowserTree.parameterPrefix + "Width", in: tree)?.subtitle == "3' - 0\"")
        #expect(ProjectBrowserTree.find(FurnitureBrowserTree.typePrefix + "36\" x 18\" x 30\"", in: tree)?.subtitle == "Current")
        // Projects keep their tree.
        let project = ProjectBrowserTree.build(ProjectTemplates.make(.empty, units: .imperial).0)
        #expect(project.first?.title == "Views (all)" && project.contains { $0.title == "Links" })
    }
}
