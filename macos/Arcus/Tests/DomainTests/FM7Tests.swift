import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

@Suite("FM7 Furniture fabrication") @MainActor
struct FM7Tests {
    static let inch = 0.0254
    static func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

    static let cabinet = FurnitureSamples.baseCabinetModel()!
    static let bookcase = FurnitureSamples.bookcaseModel()!

    static func schedule(_ m: BIMModel, _ kind: ScheduleKind) throws -> ScheduleTable {
        let s = try #require(m.elements(.schedules).first { $0.schedule?.kind == kind })
        return ScheduleEngine.compute(s, m)
    }

    static func column(_ t: ScheduleTable, _ heading: String) -> Int? { t.columns.firstIndex { $0.heading == heading } }

    // MARK: Part List

    @Test func partListHasEveryPartAndDerivedPieceAtCutSize() throws {
        let m = Self.cabinet
        let parts = FurnitureFabrication.parts(m)
        // 8 carcass parts, two door slabs, three drawers of front + side (x2) + front + back + bottom.
        #expect(parts.filter { !$0.isDerived }.count == 8)
        #expect(parts.filter(\.isDerived).count == 2 + 3 * 5)
        let side = try #require(parts.first { $0.mark == "P1" })
        let cut = try #require(FurnitureJoints.cutSize(of: side.elementID, in: m))
        #expect(Self.approx(side.length, cut.length) && Self.approx(side.width, cut.width) && Self.approx(side.thickness, cut.thickness))
        #expect(Self.approx(side.length, 34.5 * Self.inch, 1e-4) && Self.approx(side.width, 24 * Self.inch, 1e-4))
        let boxSide = try #require(parts.first { $0.isDerived && $0.name.hasSuffix("Box Side") })
        #expect(boxSide.quantity == 2)
        #expect(Self.approx(boxSide.thickness, 0.5 * Self.inch, 1e-6))
        #expect(m[boxSide.materialID]?.name == "Solid Maple")
        // Derived pieces are marked after their front.
        #expect(parts.filter(\.isDerived).allSatisfy { $0.mark.contains("-") })
    }

    @Test func partListGroupsByMaterialAndThicknessWithTotals() throws {
        let m = Self.cabinet
        let t = try Self.schedule(m, .partList)
        let headers = t.rows.filter { $0.kind == .groupHeader }.map(\.title)
        #expect(headers == ["Hardboard 1/4\"", "Plywood 3/4\"", "Plywood 1/4\"", "Solid Maple 1/2\""])
        #expect(t.rows.filter { $0.kind == .groupFooter }.count == headers.count)
        #expect(t.rows.last?.kind == .grandTotal)
        // Identical parts share a row: the two dividers, with both Marks and Qty 2.
        let mark = try #require(Self.column(t, "Mark")), qty = try #require(Self.column(t, "Qty"))
        let dividers = try #require(t.rows.first { $0.kind == .data && $0.cells[mark].text == "DV1, DV2" })
        #expect(dividers.cells[qty].text == "2")
        // The grand total's Qty is every piece.
        let pieces = FurnitureFabrication.parts(m).reduce(0) { $0 + $1.quantity }
        #expect(t.rows.last?.cells[qty].text == "\(pieces)")
        // Cut sizes read in inches and fractions.
        let length = try #require(Self.column(t, "Cut Length"))
        #expect(t.rows.contains { $0.kind == .data && $0.cells[length].text == "34 1/2\"" })
    }

    @Test func bookcaseShelvesGroupAsOneRow() throws {
        let m = Self.bookcase
        let t = try Self.schedule(m, .partList)
        let mark = try #require(Self.column(t, "Mark")), qty = try #require(Self.column(t, "Qty"))
        let shelves = try #require(t.rows.first { $0.kind == .data && $0.cells[mark].text.hasPrefix("S1") })
        #expect(shelves.cells[mark].text == "S1, S2, S3, S4")
        #expect(shelves.cells[qty].text == "4")
        #expect(shelves.elementIDs.count == 4)
    }

    @Test func costsFollowEachMaterialsCostUnit() throws {
        let m = Self.cabinet
        let parts = FurnitureFabrication.parts(m)
        // Sheet goods: the sheet's cost by area share; banding by linear foot.
        let side = try #require(parts.first { $0.mark == "P1" })
        let ply = try #require(m[side.materialID]?.material)
        let sheet = m.stockSheets.size(material: side.materialID, thickness: side.thickness)
        let share = ply.cost * side.length * side.width / (sheet.length * sheet.width)
        #expect(Self.approx(FurnitureFabrication.materialCost(side, m), share, 1e-9))
        let edge = try #require(m[side.bandingMaterialID]?.material)
        #expect(side.banding.code == "L1")
        #expect(Self.approx(FurnitureFabrication.bandingCost(side, m), edge.cost * side.length / 0.3048, 1e-9))
        // Solid wood by the board foot.
        let boxSide = try #require(parts.first { $0.isDerived && $0.name.hasSuffix("Box Side") })
        let maple = try #require(m[boxSide.materialID]?.material)
        let bf = (boxSide.length / Self.inch) * (boxSide.width / Self.inch) * (boxSide.thickness / Self.inch) / 144 * 2
        #expect(Self.approx(FurnitureFabrication.cost(boxSide, m), maple.cost * bf, 1e-9))
        // The Part List's total cost is the sum of every part's cost.
        let t = try Self.schedule(m, .partList)
        let costCol = try #require(Self.column(t, "Cost"))
        let total = parts.reduce(0) { $0 + FurnitureFabrication.cost($1, m) }
        #expect(t.rows.last?.cells[costCol].text == Parameters.format(.double(total), type: .currency, model: m))
    }

    @Test func costByWholeSheetsUsesTheNesting() throws {
        var m = Self.cabinet
        var s = m.stockSheets
        s.costBasis = .sheets
        let tx = TransactionContext(model: m, name: "Stock Sheets")
        try FurnitureStockSheets.set(s, in: tx)
        m = try tx.commit().model
        let lines = FabricationSchedules.costLines(m)
        let plywood = try #require(lines.first { $0.item == "Plywood" })
        let sheets = FurnitureFabrication.nesting(m).filter { m[$0.materialID]?.name == "Plywood" }.reduce(0) { $0 + $1.result.sheets.count }
        #expect(Self.approx(plywood.cost, Double(sheets) * 85, 1e-9))
        #expect(plywood.basis.contains("\(sheets) sheets used"))
    }

    @Test func costScheduleTotalsThePieceWithLaborAndMarkup() throws {
        var m = Self.cabinet
        let base = FabricationSchedules.pieceCost(m)
        let tx = TransactionContext(model: m, name: "Labor")
        var g = GlobalParameters.all(tx.model)
        for i in g.indices {
            if g[i].name == FabricationSchedules.laborHours { g[i].value = .double(4) }
            if g[i].name == FabricationSchedules.markup { g[i].value = .double(0.25) }
        }
        try GlobalParameters.set(g, in: tx)
        m = try tx.commit().model
        let rate = GlobalParameters.named(FabricationSchedules.laborRate, m)?.value.doubleValue ?? 0
        #expect(Self.approx(FabricationSchedules.pieceCost(m), (base + 4 * rate) * 1.25, 1e-6))
        let t = try Self.schedule(m, .costSummary)
        #expect(t.rows.last?.title.hasPrefix("Piece Cost") == true)
        #expect(t.rows.contains { $0.cells.contains { $0.text == "Markup" } })
    }

    // MARK: Hardware

    @Test func hardwareScheduleCountsPlacedHardwareAndJointFasteners() throws {
        let m = Self.cabinet
        let t = try Self.schedule(m, .hardwareSchedule)
        let fam = try #require(Self.column(t, "Family")), count = try #require(Self.column(t, "Count")), total = try #require(Self.column(t, "Total Cost"))
        func row(_ f: String) -> ScheduleRow? { t.rows.first { $0.kind == .data && $0.cells[fam].text == f } }
        // Two doors with two hinges each, three drawers with a slide pair and a pull each, two door pulls.
        #expect(row(FurnitureHardware.concealedHinge)?.cells[count].text == "4")
        #expect(row(FurnitureHardware.undermountSlide)?.cells[count].text == "3")
        #expect(row(FurnitureHardware.barPull)?.cells[count].text == "5")
        // Joint fasteners map to the Dowel family.
        let joints = Dictionary(FurnitureJoints.hardwareCounts(m).map { ($0.kind, $0.count) }, uniquingKeysWith: +)
        let dowels = joints.filter { $0.key.hasPrefix("Dowel") }.reduce(0) { $0 + $1.value }
        #expect(dowels > 0)
        #expect(row(FurnitureHardware.dowel)?.cells[count].text == "\(dowels)")
        let sum = FurnitureFabrication.hardware(m).reduce(0) { $0 + $1.totalCost }
        #expect(t.rows.last?.cells[total].text == Parameters.format(.double(sum), type: .currency, model: m))
    }

    @Test func jointFastenerNamesMapToHardwareTypes() {
        #expect(FurnitureFabrication.jointHardware("Dowel 5/16\" x 1 3/16\"").type == "8 x 30 mm")
        #expect(FurnitureFabrication.jointHardware("Cam Lock 15 mm").family == FurnitureHardware.camLock)
        #expect(FurnitureFabrication.jointHardware("Shelf Pin 5 mm").type == "5 mm Spoon")
        #expect(FurnitureFabrication.jointHardware("Confirmat Screw 7 x 50 mm").family == FurnitureHardware.confirmat)
        #expect(FurnitureFabrication.jointHardware("Pocket Screw 1 1/4\"").family == nil)
    }

    // MARK: Material Takeoff and banding

    @Test func materialTakeoffHasCostAndSheetCount() throws {
        let m = Self.cabinet
        let t = try Self.schedule(m, .materialTakeoff)
        let name = try #require(Self.column(t, "Material")), sheets = try #require(Self.column(t, "Sheet Count")), unit = try #require(Self.column(t, "Cost Unit"))
        let ply = try #require(t.rows.first { $0.kind == .data && $0.cells[name].text == "Plywood" })
        let id = m.elements(.materials).first { $0.name == "Plywood" }?.id
        #expect(ply.cells[sheets].text == "\(FurnitureFabrication.sheetCount(material: id, m))")
        #expect(ply.cells[unit].text == "Sheet")
        let cost = try #require(Self.column(t, "Cost"))
        #expect(ply.cells[cost].text.hasPrefix("$"))
    }

    @Test func edgeBandingTakeoffIsLinearFeetByMaterial() throws {
        let m = Self.cabinet
        let t = try Self.schedule(m, .edgeBanding)
        let lf = try #require(Self.column(t, "Linear Feet"))
        let total = FurnitureFabrication.banding(m).reduce(0) { $0 + $1.length } / 0.3048
        #expect(t.rows.last?.cells[lf].text == String(format: "%.1f", total))
        #expect(t.rows.filter { $0.kind == .data }.count == 1) // one banding material
    }

    // MARK: Nesting

    /// Deterministic pseudo-random parts.
    static func items(_ n: Int, seed: UInt64 = 7, grain: Bool = true) -> [NestItem] {
        var x = seed
        func r() -> Double { x = x &* 6364136223846793005 &+ 1442695040888963407; return Double(x >> 11) / Double(1 << 53) }
        return (0..<n).map { i in
            let l = (6 + r() * 40) * inch, w = (3 + r() * 20) * inch
            let g: GrainDirection = !grain ? .none : (i % 3 == 0 ? .none : (i % 3 == 1 ? .length : .width))
            return NestItem(key: "p\(i)", label: "P\(i)", length: max(l, w), width: min(l, w), grain: g)
        }
    }

    static func checkLayout(_ r: NestResult, _ items: [NestItem], _ stock: NestStock) {
        let byKey = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0) })
        #expect(r.sheets.reduce(0) { $0 + $1.placements.count } + r.oversize.count == items.count)
        let usable = Rect2(min: Vec2(stock.trim, stock.trim), max: Vec2(stock.length - stock.trim, stock.width - stock.trim))
        for s in r.sheets {
            for (i, p) in s.placements.enumerated() {
                let it = byKey[p.key]!
                // Inside the trimmed sheet, at the part's size.
                #expect(usable.expanded(by: 1e-9).contains(p.rect))
                let (w, h) = p.rotated ? (it.width, it.length) : (it.length, it.width)
                #expect(abs(p.rect.width - w) < 1e-9 && abs(p.rect.height - h) < 1e-9)
                // Grain-locked parts keep their grain along the sheet's.
                if it.grain != .none, stock.grain != .none { #expect(p.rotated == ((it.grain == .length) != (stock.grain == .length))) }
                // No overlaps, and a kerf between neighbours.
                for q in s.placements[(i + 1)...] {
                    let gapX = max(q.rect.min.x - p.rect.max.x, p.rect.min.x - q.rect.max.x)
                    let gapY = max(q.rect.min.y - p.rect.max.y, p.rect.min.y - q.rect.max.y)
                    #expect(max(gapX, gapY) >= stock.kerf - 1e-9, "\(p.key) and \(q.key) closer than the kerf")
                }
            }
            let area = s.placements.reduce(0) { $0 + $1.rect.width * $1.rect.height }
            #expect(abs(s.yield - area / stock.area) < 1e-12)
            // Offcuts never cover parts.
            for o in s.offcuts { for p in s.placements { let i = o.intersection(p.rect); #expect(i.isEmpty || i.width * i.height < 1e-9) } }
        }
    }

    @Test(arguments: [NestingMethod.best, .guillotine, .maxRects])
    func nestingIsValid(_ method: NestingMethod) {
        let stock = NestStock(length: 96 * Self.inch, width: 48 * Self.inch)
        let items = Self.items(80)
        let r = NestingEngine.nest(items, on: stock, method: method)
        Self.checkLayout(r, items, stock)
        #expect(r.oversize.isEmpty)
        #expect(r.method != .best)
        // Deterministic.
        let again = NestingEngine.nest(items, on: stock, method: method)
        #expect(again.sheets.map { $0.placements.map(\.rect) } == r.sheets.map { $0.placements.map(\.rect) })
    }

    @Test func nestingRespectsKerfExactly() {
        // 48" sheet, no trim, 1/8" kerf: two 23 15/16" strips fit across; two 24" strips don't.
        let stock = NestStock(length: 96 * Self.inch, width: 48 * Self.inch, grain: .length, kerf: 0.125 * Self.inch, trim: 0)
        let fit = [NestItem(key: "a", label: "A", length: 90 * Self.inch, width: 23.9375 * Self.inch, grain: .length),
                   NestItem(key: "b", label: "B", length: 90 * Self.inch, width: 23.9375 * Self.inch, grain: .length)]
        #expect(NestingEngine.nest(fit, on: stock).sheets.count == 1)
        let tight = fit.map { var i = $0; i.width = 24 * Self.inch; return i }
        #expect(NestingEngine.nest(tight, on: stock).sheets.count == 2)
    }

    @Test func grainLockedPartsDoNotRotateAndOversizeIsReported() {
        let stock = NestStock(length: 96 * Self.inch, width: 48 * Self.inch, grain: .length)
        // 60" x 10" with grain across its width must stand along the sheet's width: 60" > 48", too large.
        let across = NestItem(key: "x", label: "X", length: 60 * Self.inch, width: 10 * Self.inch, grain: .width)
        let along = NestItem(key: "y", label: "Y", length: 60 * Self.inch, width: 10 * Self.inch, grain: .length)
        let free = NestItem(key: "z", label: "Z", length: 50 * Self.inch, width: 10 * Self.inch, grain: .none)
        let r = NestingEngine.nest([across, along, free], on: stock)
        #expect(r.oversize.map(\.key) == ["x"])
        let y = r.sheets.flatMap(\.placements).first { $0.key == "y" }
        #expect(y?.rotated == false)
        let huge = NestItem(key: "h", label: "H", length: 100 * Self.inch, width: 50 * Self.inch, grain: .none)
        #expect(NestingEngine.nest([huge], on: stock).oversize.count == 1)
    }

    @Test func rotationFollowsTheStockSetting() {
        // A 40" x 20" part without grain fits a 30" x 50" sheet only turned.
        let item = NestItem(key: "a", label: "A", length: 40 * Self.inch, width: 20 * Self.inch, grain: .none)
        var stock = NestStock(length: 30 * Self.inch, width: 50 * Self.inch, grain: .none, kerf: 0, trim: 0, allowRotation: true)
        #expect(NestingEngine.nest([item], on: stock).sheets.first?.placements.first?.rotated == true)
        stock.allowRotation = false
        #expect(NestingEngine.nest([item], on: stock).oversize.count == 1)
    }

    @Test func nestingIsFast() {
        let stock = NestStock(length: 96 * Self.inch, width: 48 * Self.inch)
        let items = Self.items(300, seed: 11)
        let clock = ContinuousClock()
        var r: NestResult?
        let t = clock.measure { r = NestingEngine.nest(items, on: stock, method: .maxRects) }
        Self.checkLayout(r!, items, stock)
        // Debug builds run several times slower than release; the release target is < 200 ms.
        #expect(t < .milliseconds(500), "nesting 300 parts took \(t)")
        let best = clock.measure { r = NestingEngine.nest(items, on: stock, method: .best) }
        Self.checkLayout(r!, items, stock)
        #expect(best < .milliseconds(3000), "best of every method took \(best)")
        print("FM7 nesting 300 parts (debug): maxRects \(t), best \(best)")
    }

    @Test func cabinetNestsItsSheetGoods() {
        let m = Self.cabinet
        let groups = FurnitureFabrication.nesting(m)
        #expect(groups.map(\.title) == ["Hardboard 1/4\"", "Plywood 3/4\"", "Plywood 1/4\""])
        // Solid maple drawer boxes are lumber, not nested.
        #expect(!groups.contains { m[$0.materialID]?.name == "Solid Maple" })
        for g in groups {
            #expect(g.result.oversize.isEmpty)
            #expect(g.result.yield > 0 && g.result.yield <= 1)
        }
    }

    @Test func stockSheetsPickTheMostSpecificSize() throws {
        let m = Self.cabinet
        let ply = try #require(m.elements(.materials).first { $0.name == "Plywood" }?.id)
        let bb = try #require(m.elements(.materials).first { $0.name == FurnitureFabrication.balticBirch }?.id)
        var s = m.stockSheets
        #expect(s.size(material: bb, thickness: 0.75 * Self.inch).name.contains("5' x 5'"))
        #expect(s.size(material: ply, thickness: 0.75 * Self.inch).name == "4' x 8'")
        s.sizes.append(StockSheetSize(name: "Ply 1/2\" 5x10", materialID: ply, thickness: 0.5 * Self.inch, length: 120 * Self.inch, width: 60 * Self.inch))
        #expect(s.size(material: ply, thickness: 0.5 * Self.inch).name == "Ply 1/2\" 5x10")
        #expect(s.size(material: ply, thickness: 0.75 * Self.inch).name == "4' x 8'")
        var bad = s
        bad.sizes[0].length = 0.001
        #expect(bad.problem() != nil)
    }

    @Test func stockSheetsAreStoredAndUndoable() throws {
        let session = DocumentSession(model: Self.cabinet)
        session.undoManager.groupsByEvent = false
        var s = session.model.stockSheets
        s.kerf = 0.25 * Self.inch
        s.method = .guillotine
        session.undoManager.beginUndoGrouping()
        _ = session.perform("Stock Sheets") { tx in try FurnitureStockSheets.set(s, in: tx) }
        session.undoManager.endUndoGrouping()
        #expect(session.lastError == nil)
        #expect(session.model.stockSheets.kerf == 0.25 * Self.inch)
        #expect(FurnitureFabrication.nesting(session.model).allSatisfy { $0.result.method == .guillotine })
        session.undoManager.undo()
        #expect(session.model.furnitureSetup?.stockSheets == nil)
    }

    @Test func nestingViewsAreMadePerGroupAndDrawTheirSheets() throws {
        var m = Self.cabinet
        let tx = TransactionContext(model: m, name: "Nesting")
        let views = FurnitureShopDrawings.updateNesting(in: tx)
        m = try tx.commit().model
        #expect(views.count == 3)
        #expect(FurnitureNestingViews.views(m).count == 3)
        // Placed on F103, and listed in the browser's Nesting folder.
        let f103 = try #require(m.sheets.first { $0.sheet?.number == "F103" })
        #expect(Set(m.owned(byView: f103.id).compactMap { $0.viewport?.viewID }) == Set(views))
        let tree = FurnitureBrowserTree.adapt(ProjectBrowserTree.build(m, filter: ""), m, filter: "")
        let nestingNode = tree.first { $0.id == "nesting" }
        #expect(nestingNode?.children?.count == 3)
        // Running it again makes no new views.
        let tx2 = TransactionContext(model: m, name: "Nesting")
        #expect(FurnitureShopDrawings.updateNesting(in: tx2) == views)
        // The plywood view draws its sheets, a part per placement, hatched offcuts and titles.
        let v = try #require(FurnitureNestingViews.views(m).first { $0.name == "Plywood 3/4\"" })
        let g = ViewGraphicsBuilder(model: m, view: v).build()
        let group = try #require(FurnitureFabrication.nesting(m).first { $0.title == "Plywood 3/4\"" })
        let partItems = g.items.filter { $0.elementID != nil }
        #expect(partItems.count == group.result.sheets.reduce(0) { $0 + $1.placements.count })
        #expect(g.items.contains { $0.primitives.contains { if case .fill(_, let f) = $0 { return f.pattern == .diagonalUp }; return false } })
        let texts = g.items.flatMap(\.primitives).compactMap { if case .text(let t) = $0 { return t.string }; return nil }
        #expect(texts.contains { $0.hasPrefix("Sheet 1 of") && $0.contains("Yield") })
        #expect(texts.contains("P1"))
    }

    // MARK: Shop drawings

    @Test func templateHasTheShopDrawingSet() throws {
        let m = FurnitureTemplates.blank(category: .casework, name: "Box")
        #expect(m.sheets.compactMap { $0.sheet?.number }.sorted() == ["F101", "F102", "F103", "F104"])
        for k in [ScheduleKind.partList, .hardwareSchedule, .materialTakeoff, .edgeBanding, .costSummary] {
            #expect(m.elements(.schedules).contains { $0.schedule?.kind == k }, "\(k)")
        }
        let tb = try #require(m.types(for: .titleBlocks).first { $0.typeData?.familyName == FurnitureShopDrawings.titleBlockName })
        #expect(m.sheets.allSatisfy { $0.sheet?.titleBlockTypeID == tb.id })
        let f101 = try #require(m.sheets.first { $0.sheet?.number == "F101" })
        let onF101: [String] = m.owned(byView: f101.id).compactMap { m[$0.viewport?.viewID]?.name }
        #expect(onF101.contains(FurnitureShopDrawings.sectionName))
        let f102 = try #require(m.sheets.first { $0.sheet?.number == "F102" })
        #expect(Set(m.owned(byView: f102.id).compactMap { m[$0.viewport?.viewID]?.schedule?.kind }) == [.partList, .hardwareSchedule])
        // Title block values.
        let sb = SheetGraphicsBuilder(model: m, sheet: f101)
        #expect(sb.titleBlockValue("Piece Name") == "Box")
        #expect(sb.titleBlockValue("Piece Category") == "Casework")
        #expect(sb.titleBlockValue("Piece Material") == "Plywood")
        #expect(GlobalParameters.named(FabricationSchedules.laborRate, m) != nil)
    }

    @Test func shopDrawingsTagThePartsAndFitTheSheets() throws {
        var m = Self.cabinet
        let tx = TransactionContext(model: m, name: "Shop Drawings")
        FurnitureShopDrawings.update(in: tx)
        m = try tx.commit().model
        let front = try #require(m.views.first { $0.name == "Front" })
        let tagged = Set(m.owned(byView: front.id).compactMap { $0.tag?.taggedID })
        let parts = m.elements(Category.furnitureParts).filter { !$0.isType && $0.furniturePanel?.role != .back && $0.furnitureEdgeProfile == nil && $0.furnitureForm == nil }
        #expect(parts.allSatisfy { tagged.contains($0.id) })
        // Every F101 viewport inside the drawing area, none overlapping.
        let f101 = try #require(m.sheets.first { $0.sheet?.number == "F101" })
        let boxes = SheetGraphicsBuilder(model: m, sheet: f101).layouts().map(\.0.box)
        #expect(boxes.count == 5)
        for (i, a) in boxes.enumerated() {
            #expect(FurnitureShopDrawings.drawingArea.expanded(by: 0.002).contains(a))
            for b in boxes[(i + 1)...] { let x = a.intersection(b); #expect(x.isEmpty || x.width * x.height < 1e-6) }
        }
        // Running it again changes nothing.
        let tx2 = TransactionContext(model: m, name: "Again")
        FurnitureShopDrawings.update(in: tx2)
        #expect((try tx2.commit()).record.changes.isEmpty)
    }

    // MARK: CNC

    @Test func cncProgramsAreInPartCoordinates() throws {
        let m = Self.cabinet
        let progs = FurnitureCNC.programs(m)
        #expect(progs.count == FurnitureFabrication.parts(m).count)
        let side = try #require(progs.first { $0.part.mark == "P1" })
        let outline = try #require(side.faceA.paths.first { $0.layer == "OUTLINE" })
        #expect(outline.closed && outline.points.count == 4)
        #expect(Self.approx(outline.points.map(\.x).max(), side.part.length) && Self.approx(outline.points.map(\.y).max(), side.part.width))
        // The side carries hinge plate screws and the dowels of its joints; every hole inside the part.
        let holes = side.faceA.circles + (side.faceB?.circles ?? [])
        #expect(!holes.isEmpty || side.faceA.paths.contains { $0.layer.hasPrefix("HDRILL_") })
        for c in holes {
            #expect(c.center.x > -1e-6 && c.center.x < side.part.length + 1e-6 && c.center.y > -1e-6 && c.center.y < side.part.width + 1e-6)
            #expect(c.layer.hasPrefix("DRILL_"))
        }
        #expect(FurnitureCNC.drillLayer(diameter: 0.005, depth: 0.013) == "DRILL_0.197_0.512")
        #expect(FurnitureCNC.grooveLayer(depth: 0.25 * Self.inch) == "GROOVE_0.25")
        // Doors carry their hinge cups (35 mm) on one face.
        let door = try #require(progs.first { $0.part.mark == "D1-1" })
        let cups = (door.faceA.circles + (door.faceB?.circles ?? [])).filter { $0.layer.hasPrefix("DRILL_1.378_") }
        #expect(cups.count == 2)
        #expect(side.faceA.paths.contains { $0.layer == "GRAIN" } && side.faceA.labels.first?.text == "P1")
    }

    @Test func nestedSheetProgramsPlaceEveryPart() throws {
        let m = Self.cabinet
        let sheets = FurnitureCNC.sheetPrograms(m)
        let total = FurnitureFabrication.nesting(m).reduce(0) { $0 + $1.result.sheets.count }
        #expect(sheets.count == total)
        for s in sheets {
            let sheet = try #require(s.drawing.paths.first { $0.layer == "SHEET" })
            let bounds = Rect2(points: sheet.points)
            let outlines = s.drawing.paths.filter { $0.layer == "OUTLINE" }
            #expect(outlines.count == s.group.result.sheets[s.index].placements.count)
            for o in outlines { #expect(bounds.expanded(by: 1e-6).contains(Rect2(points: o.points))) }
        }
        let csv = FurnitureCNC.csv(m)
        #expect(csv.hasPrefix("Mark,Part,Material"))
        #expect(csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count == FurnitureFabrication.parts(m).count + 1)
    }

    // MARK: Check Parts

    @Test func checkPartsFindsTheProblems() throws {
        var m = Self.cabinet
        // Clean cabinet: no errors (notes about unbanded edges are fine).
        #expect(!FurnitureCheckParts.check(m).contains { $0.severity == .error })
        let tx = TransactionContext(model: m, name: "Break it")
        // A panel longer than any sheet.
        let ply = FurnitureSamples.type(tx.model, .furniturePanels, "3/4\" Plywood")
        _ = try FurniturePartOperations.createPanel(start: Vec2(-60 * Self.inch, -40 * Self.inch), end: Vec2(60 * Self.inch, -40 * Self.inch), extent: PartExtent(), typeID: ply, in: tx)
        // Doors 3/8" thick: too thin for 13 mm hinge cups.
        if let doorType = tx.model.elements(.furnitureFronts).first.flatMap({ tx.model[$0.typeID] }) {
            tx.update(doorType.id) { $0.typeData?.params[FurniturePartTypes.thickness] = .double(0.375 * Self.inch) }
        }
        // A shelf type without a material.
        if let shelfType = FurnitureSamples.type(tx.model, .furnitureShelves, "3/4\" Plywood Shelf") {
            tx.update(shelfType) { $0.typeData?.params[FurniturePartTypes.coreMaterial] = .ref(nil) }
        }
        m = try tx.commit().model
        let codes = Set(FurnitureCheckParts.check(m).map(\.code))
        #expect(codes.contains("fm7.stock"))
        #expect(codes.contains("fm7.thin"))
        #expect(codes.contains("fm7.material"))
    }

    @Test func checkPartsFindsOverlapsWithoutJoints() throws {
        var m = FurnitureTemplates.blank(category: .casework, name: "Overlap")
        let tx = TransactionContext(model: m, name: "Panels")
        let ply = FurnitureSamples.type(tx.model, .furniturePanels, "3/4\" Plywood")
        let a = try FurniturePartOperations.createPanel(start: Vec2(-0.3, 0), end: Vec2(0.3, 0), extent: PartExtent(), typeID: ply, in: tx)
        let b = try FurniturePartOperations.createPanel(start: Vec2(-0.2, 0.005), end: Vec2(0.2, 0.005), extent: PartExtent(), typeID: ply, in: tx)
        m = try tx.commit().model
        let tx2 = TransactionContext(model: m, name: "Disallow")
        FurnitureJointOperations.disallowJoins([a, b], in: tx2)
        m = try tx2.commit().model
        let overlaps = FurnitureCheckParts.check(m).filter { $0.code == "fm7.overlap" }
        #expect(FurnitureJoints.joint(a, b, m) == nil)
        #expect(overlaps.contains { Set($0.elements) == [a, b] })
    }

    @Test func checkPartsNotesUnbandedVisibleEdges() throws {
        let m = Self.bookcase
        let notes = FurnitureCheckParts.check(m).filter { $0.code == "fm7.banding" }
        // The sides' top ends show above the top (it sits between them) and aren't banded; their banded fronts aren't listed.
        #expect(notes.contains { $0.message.hasPrefix("P1: the top edge") })
        #expect(!notes.contains { $0.message.contains("front edge (L1)") && $0.message.hasPrefix("P1") })
    }
}
