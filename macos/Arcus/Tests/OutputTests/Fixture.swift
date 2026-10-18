import CoreGraphics
import Foundation
import PDFKit
import ArcusGeometry
import ArcusDomain
@testable import ArcusOutput

/// A small but complete project: walls, doors, a window, a room, a dimension, a text note, a filled region,
/// a section, three sheets (A1, A1, ARCH D) and a door schedule placed on a sheet.
struct Fixture: Sendable {
    var model: BIMModel
    var ids: ProjectTemplates.Ids
    var level1: ElementID
    var plan: ElementID
    var section: ElementID
    var sheetPlan: ElementID      // A101 Ground Floor Plan (A1)
    var sheetSection: ElementID   // A201 Building Sections (A1)
    var sheetSchedule: ElementID  // A601 Door Schedule (ARCH D)
    var walls: [ElementID]
    var doors: [ElementID]
    var doorSchedule: ElementID
    var dimension: ElementID
    var textNote: ElementID
    var region: ElementID

    static let shared: Fixture = try! make()

    static func make() throws -> Fixture {
        let (m0, ids) = ProjectTemplates.make(.architectural, units: .metric, projectName: "Harbour Library")
        let tx = TransactionContext(model: m0, name: "Fixture")
        tx.update(m0.projectInfoElement!.id) { $0.projectInfo?.projectNumber = "HL-2026" }
        let l1 = ids.levels[0], l2 = ids.levels[1]
        let plan = ids.planViews[l1]!
        let wt = ids.wallTypes["Exterior - Brick on CMU"]!
        let pts = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 8), Vec2(0, 8)]
        var walls: [ElementID] = []
        for i in 0..<4 {
            var w = WallData(location: .line(Segment2(pts[i], pts[(i + 1) % 4])), topLevelID: l2)
            w.locationLine = .wallCenterline
            walls.append(tx.create(.walls, data: .wall(w), typeID: wt, levelID: l1))
        }
        let doorType = ids.familyTypes["Door - Single Flush: 900 x 2100"]!
        let d1 = tx.create(.doors, data: .insert(InsertData(location: Vec2(3, 0))), typeID: doorType, levelID: l1, hostID: walls[0]) { $0.mark = "D-01" }
        let d2 = tx.create(.doors, data: .insert(InsertData(location: Vec2(7, 8))), typeID: doorType, levelID: l1, hostID: walls[2]) { $0.mark = "D-02" }
        let winType = ids.familyTypes["Window - Casement: 1200 x 1500"]!
        tx.create(.windows, data: .insert(InsertData(location: Vec2(10, 4), sillHeight: 0.9)), typeID: winType, levelID: l1, hostID: walls[1])
        tx.create(.rooms, name: "Reading Room", data: .room(RoomData(point: Vec2(5, 4), number: "101")), levelID: l1)
        let dim = tx.create(.dimensions, data: .dimension(DimensionData(kind: .linear, references: [.fixed(Vec2(0, 0)), .fixed(Vec2(10, 0))],
                                                                       linePoint: Vec2(5, -1.5), direction: 0)),
                            typeID: ids.systemTypes["Dimension"], ownerViewID: plan)
        let note = tx.create(.textNotes, data: .textNote(TextNoteData(position: Vec2(1, 7), text: "LIBRARY ENTRANCE")),
                             typeID: ids.systemTypes["Text 2.5mm Arial"], ownerViewID: plan)
        let region = tx.create(.filledRegions, data: .filledRegion(FilledRegionData(boundary: Sketch(rect: Rect2(min: Vec2(1, 1), max: Vec2(3, 3))))),
                               typeID: ids.systemTypes["Region Concrete"], ownerViewID: plan)
        var sv = ViewData(kind: .section, scale: 50)
        sv.planeOrigin = Vec3(5, 4, 0)
        sv.viewDirection = Vec2(0, 1)
        sv.cropRegion = Rect2(min: Vec2(-6, -1), max: Vec2(6, 6))
        sv.cropActive = true
        sv.farClip = 10
        sv.phaseID = ids.phases.last
        let section = tx.create(.views, name: "Section 1", data: .view(sv))

        let tb = ids.titleBlocks["A1 Title Block"]
        let sheetPlan = m0.sheets.first!.id
        tx.update(sheetPlan) { $0.name = "Ground Floor Plan" }
        let sheetSection = tx.create(.sheets, name: "Building Sections", data: .sheet(SheetData(number: "A201", paper: .a1, titleBlockTypeID: tb)))
        let sheetSchedule = tx.create(.sheets, name: "Door Schedule", data: .sheet(SheetData(number: "A601", paper: .archD, titleBlockTypeID: nil)))
        let doorSchedule = m0.schedules.first { $0.name == "Door Schedule" }!.id
        tx.create(.viewports, data: .viewport(ViewportData(viewID: plan, center: Vec2(0.35, 0.32), detailNumber: "1")), ownerViewID: sheetPlan)
        tx.create(.viewports, data: .viewport(ViewportData(viewID: section, center: Vec2(0.35, 0.32), detailNumber: "1")), ownerViewID: sheetSection)
        tx.create(.viewports, data: .viewport(ViewportData(viewID: doorSchedule, center: Vec2(0.3, 0.4), detailNumber: "")), ownerViewID: sheetSchedule)
        let m = try tx.commit().model
        return Fixture(model: m, ids: ids, level1: l1, plan: plan, section: section, sheetPlan: sheetPlan, sheetSection: sheetSection,
                       sheetSchedule: sheetSchedule, walls: walls, doors: [d1, d2], doorSchedule: doorSchedule, dimension: dim, textNote: note, region: region)
    }

    static func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("ArcusOutputTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

// MARK: - Bitmap helper

final class Bitmap {
    let width: Int, height: Int
    let ctx: CGContext

    init(_ w: Int, _ h: Int) {
        width = w; height = h
        ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// RGBA (0…255) at user-space (x, y) with y up.
    func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let row = height - 1 - y
        let o = row * ctx.bytesPerRow + x * 4
        return (Int(p[o]), Int(p[o + 1]), Int(p[o + 2]), Int(p[o + 3]))
    }

    /// 0 = white/transparent, 1 = black.
    func ink(_ x: Int, _ y: Int) -> Double {
        let p = pixel(x, y)
        if p.a == 0 { return 0 }
        return 1 - Double(p.r + p.g + p.b) / (3 * 255)
    }

    var bytes: [UInt8] {
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: p, count: height * ctx.bytesPerRow))
    }
}

func graphics(_ items: [GItem], scale: Int = 100) -> ViewGraphics {
    ViewGraphics(viewID: ElementID(999_999), scale: scale, items: items, extents: .empty, crop: nil, modelRevision: 0)
}

// MARK: - PDF inspection

final class OpCounter {
    var curves = 0, lines = 0, text = 0, xobjects = 0, strokes = 0
}

func operatorCounts(_ page: CGPDFPage) -> OpCounter {
    let counter = OpCounter()
    let table = CGPDFOperatorTableCreate()!
    CGPDFOperatorTableSetCallback(table, "c") { _, info in Unmanaged<OpCounter>.fromOpaque(info!).takeUnretainedValue().curves += 1 }
    CGPDFOperatorTableSetCallback(table, "l") { _, info in Unmanaged<OpCounter>.fromOpaque(info!).takeUnretainedValue().lines += 1 }
    CGPDFOperatorTableSetCallback(table, "Tj") { _, info in Unmanaged<OpCounter>.fromOpaque(info!).takeUnretainedValue().text += 1 }
    CGPDFOperatorTableSetCallback(table, "TJ") { _, info in Unmanaged<OpCounter>.fromOpaque(info!).takeUnretainedValue().text += 1 }
    CGPDFOperatorTableSetCallback(table, "Do") { _, info in Unmanaged<OpCounter>.fromOpaque(info!).takeUnretainedValue().xobjects += 1 }
    CGPDFOperatorTableSetCallback(table, "S") { _, info in Unmanaged<OpCounter>.fromOpaque(info!).takeUnretainedValue().strokes += 1 }
    let stream = CGPDFContentStreamCreateWithPage(page)
    let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(counter).toOpaque())
    CGPDFScannerScan(scanner)
    CGPDFScannerRelease(scanner)
    CGPDFContentStreamRelease(stream)
    CGPDFOperatorTableRelease(table)
    return counter
}

/// Number of image XObjects in a page's resources.
func imageXObjectCount(_ page: CGPDFPage) -> Int {
    guard let dict = page.dictionary else { return 0 }
    var resources: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(dict, "Resources", &resources), let resources else { return 0 }
    var xobjects: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return 0 }
    var images = 0
    CGPDFDictionaryApplyBlock(xobjects, { _, object, _ in
        var stream: CGPDFStreamRef?
        if CGPDFObjectGetValue(object, .stream, &stream), let stream, let sd = CGPDFStreamGetDictionary(stream) {
            var name: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(sd, "Subtype", &name), let name, String(cString: name) == "Image" { images += 1 }
        }
        return true
    }, nil)
    return images
}

func pageSizes(_ url: URL) -> [CGSize] {
    guard let doc = CGPDFDocument(url as CFURL) else { return [] }
    return (0..<doc.numberOfPages).compactMap { doc.page(at: $0 + 1)?.getBoxRect(.mediaBox).size }
}
