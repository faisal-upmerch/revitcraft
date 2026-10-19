import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusPersistence
import ArcusOutput

// HOUSE: `arcus-bench --two-story-house <file.arcus> [--renders <dir>]` builds the Two-Story House sample, saves it with
// the package writer, and (optionally) renders its plans, elevations, sections, 3D views and sheets to PNG plus the
// sheet set to one vector PDF, with the same exporters File ▸ Export uses.
enum TwoStoryHouseExport {
    static func run(to url: URL, renders: URL?) async throws {
        let model = TwoStoryHouse.make()
        let thumb = model.views.first { $0.view?.kind == .threeD && $0.name == "{3D}" }
            .flatMap { RasterExporter.render(ViewGraphicsBuilder(model: model, view: $0).build(), pixelWidth: 512) }
            .flatMap { RasterExporter.encode($0, as: .png) }
        let info = ArcusPackage.WriteInfo(appVersion: "1.0.0", build: "1", thumbnailPNG: thumb)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try ArcusPackage.write(model, to: url, info: info)
        let reopened = try ArcusPackage.read(from: url).model
        print("Saved \(url.path) (\(model.count) elements; reopened \(reopened.count))")
        report(model)
        guard let dir = renders else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func save(_ g: ViewGraphics, paper: Vec2? = nil, width: Int, _ name: String) throws {
            guard let img = RasterExporter.render(g, paper: paper, pixelWidth: width), let data = RasterExporter.encode(img, as: .png) else {
                print("  could not render \(name)"); return
            }
            try data.write(to: dir.appendingPathComponent(name + ".png"))
            print("  \(name).png")
        }
        for v in model.views {
            guard let kind = v.view?.kind, [.floorPlan, .elevation, .section, .threeD].contains(kind) else { continue }
            try save(ViewGraphicsBuilder(model: model, view: v).build(), width: 2400, "View - \(v.name)".replacingOccurrences(of: "/", with: "-"))
        }
        for s in model.sheets.sorted(by: { ($0.sheet?.number ?? "") < ($1.sheet?.number ?? "") }) {
            guard let paper = s.sheet?.paper.landscapeSize else { continue }
            try save(SheetGraphicsBuilder(model: model, sheet: s).build(), paper: paper, width: 3600, "Sheet \(s.sheet?.number ?? "") - \(s.name)")
        }
        var job = PDFExportJob(items: model.sheets.sorted { ($0.sheet?.number ?? "") < ($1.sheet?.number ?? "") }.map { PDFExportItem(elementID: $0.id, kind: .sheet) },
                               outputDirectory: dir)
        job.combinedFileName = "Two-Story House - Sheets.pdf"
        job.overwrite = .replace
        let pdf = try await PDFExporter.export(model, job: job)
        print("  Two-Story House - Sheets.pdf (\(pdf.pageCount) pages)")
    }

    /// Prints the area table and the model health summary.
    static func report(_ model: BIMModel) {
        func sf(_ m2: Double) -> String { String(format: "%.0f SF", m2 / (0.3048 * 0.3048)) }
        print("Rooms:")
        for l in model.levels.sorted(by: { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) }) {
            let bounds = RoomGeometry.boundaries(level: l.id, model)
            let rooms = model.elements(.rooms).filter { $0.levelID == l.id }.sorted { ($0.room?.number ?? "") < ($1.room?.number ?? "") }
            guard !rooms.isEmpty else { continue }
            var total = 0.0
            for r in rooms {
                let a = bounds[r.id]?.area ?? 0
                total += a
                print("  \(l.name)  \(r.room?.number ?? "")  \(r.name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(sf(a))  \(bounds[r.id].map { "\($0.state)" } ?? "-")")
            }
            print("  \(l.name) rooms total \(sf(total))")
        }
        let health = ModelHealth.check(model)
        print("Model health: \(health.count) item(s)")
        for w in health { print("  [\(w.severity)] \(w.code): \(w.message)") }
    }
}
