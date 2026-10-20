import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusOutput
import ArcusCAD

// MCP: output tools: render_view (PNG), export_pdf, export_dwg. The same exporters File ▸ Export uses.

/// The package thumbnail: the default 3D view, framed.
enum Thumbnail {
    @MainActor static func png(_ m: BIMModel) -> Data? {
        guard let v = m.views.first(where: { $0.view?.kind == .threeD }) else { return nil }
        let g = ViewGraphicsBuilder(model: m, view: ArcusToolbox.framed(v, m)).build()
        return RasterExporter.render(g, pixelWidth: 512).flatMap { RasterExporter.encode($0, as: .png) }
    }
}

extension ArcusToolbox {
    /// A 3D view still on the template's default camera, re-aimed at the model (render only; the document is unchanged).
    static func framed(_ v: Element, _ m: BIMModel) -> Element {
        guard var vd = v.view, vd.kind == .threeD, vd.camera == nil || vd.camera == Camera3D.defaultIsometric else { return v }
        vd.camera = fitCamera(m, box: vd.sectionBoxActive ? vd.sectionBox : nil)
        var e = v
        e.view = vd
        return e
    }

    /// Graphics and paper of a view or sheet.
    func graphics(_ e: Element, _ m: BIMModel) -> (ViewGraphics, Vec2?) {
        if let s = e.sheet { return (SheetGraphicsBuilder(model: m, sheet: e).build(), s.paper.landscapeSize) }
        return (ViewGraphicsBuilder(model: m, view: Self.framed(e, m)).build(), nil)
    }

    func outputFolder() -> URL {
        host.documentURL?.deletingLastPathComponent() ?? FileManager.default.temporaryDirectory.appendingPathComponent("Arcus MCP", isDirectory: true)
    }

    func renderView(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let e = try c.view(c.args["view"], allowSheets: true)
        let width = min(max(c.args.int("width") ?? 1600, 200), 8000)
        let (g, paper) = graphics(e, m)
        guard !g.items.isEmpty else { throw ToolError("“\(e.name)” shows nothing yet. Add elements, or check the view's level and crop.") }
        guard let img = RasterExporter.render(g, paper: paper, pixelWidth: width), let png = RasterExporter.encode(img, as: .png) else {
            throw ToolError("“\(e.name)” could not be rendered.")
        }
        let title = e.sheet.map { "\($0.number) - \(e.name)" } ?? e.name
        let url = c.args.string("path").map(Self.url)
            ?? outputFolder().appendingPathComponent("\(host.documentName.isEmpty ? "Arcus" : host.documentName) - \(DWGExporter.fileName(title).dropLast(4)).png")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
        } catch { throw ToolError("Could not write \(url.path): \(error.localizedDescription)") }
        var images: [JSONValue] = []
        if c.args.bool("inline", default: true) {
            var data = png
            if data.count > 1_200_000, let small = RasterExporter.render(g, paper: paper, pixelWidth: 1000), let d = RasterExporter.encode(small, as: .png) { data = d }
            images.append(["type": "image", "data": .string(data.base64EncodedString()), "mimeType": "image/png"])
        }
        return ToolOutput(["path": .string(url.path), "view": .string(title), "pixels": [.int(img.width), .int(img.height)], "items": .int(g.items.count)], images: images)
    }

    func sheetsArg(_ c: ToolContext, _ key: String, _ m: BIMModel) throws(ToolError) -> [Element] {
        guard let list = c.args.array(key) else { return m.sheets }
        var out: [Element] = []
        for v in list {
            let s = v.stringValue ?? v.intValue.map(String.init) ?? ""
            guard let e = m.sheets.first(where: { $0.sheet?.number.caseInsensitiveCompare(s) == .orderedSame || $0.name.caseInsensitiveCompare(s) == .orderedSame || String($0.id.raw) == s }) else {
                throw ToolError("No sheet “\(s)”. Sheets: \(m.sheets.map { "\($0.sheet?.number ?? "") \($0.name)" }.joined(separator: ", ")).")
            }
            out.append(e)
        }
        return out
    }

    func exportPDF(_ c: ToolContext) async throws -> ToolOutput {
        let m = try c.model()
        // AITOOLS: sheet sets, views, separate files, naming, colors; never overwrites unless asked.
        var items: [PDFExportItem] = []
        var labels: [String] = []
        if let list = c.args.array("views") {
            for (k, v) in list.enumerated() { let e = try c.view(v, what: "views[\(k)]"); items.append(.view(e.id)); labels.append(e.name) }
        } else {
            var sheets = try sheetsArg(c, "sheets", m)
            if let setName = c.args.string("sheet_set") {
                guard let set = m.viewSheetSets.first(where: { $0.name.caseInsensitiveCompare(setName) == .orderedSame }) else {
                    throw ToolError("No sheet set “\(setName)”. Sets: \(m.viewSheetSets.map(\.name).joined(separator: ", ")). create_sheet_set makes one.")
                }
                sheets = set.members.compactMap { m[$0] }.filter { $0.sheet != nil }
            }
            sheets.sort { ($0.sheet?.number ?? "").localizedStandardCompare($1.sheet?.number ?? "") == .orderedAscending }
            guard !sheets.isEmpty else { throw ToolError("The document has no sheets. create_sheet first.") }
            items = sheets.map { PDFExportItem(elementID: $0.id, kind: .sheet) }
            labels = sheets.map { "\($0.sheet?.number ?? "") \($0.name)" }
        }
        let combined = c.args.bool("combined", default: true)
        var url = Self.url(try c.args.requireString("path"))
        let folder: URL
        if combined {
            if url.pathExtension.lowercased() != "pdf" { url = url.appendingPathExtension("pdf") }
            url = Self.destination(url, overwrite: c.args.bool("overwrite", default: false))
            folder = url.deletingLastPathComponent()
        } else { folder = url.pathExtension.lowercased() == "pdf" ? url.deletingLastPathComponent() : url }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var job = PDFExportJob(items: items, outputDirectory: folder)
        job.combined = combined
        job.combinedFileName = url.lastPathComponent
        job.overwrite = c.args.bool("overwrite", default: false) ? .replace : .uniquify
        switch c.args.string("naming")?.lowercased() {
        case nil, "sheet_number_and_name": job.naming = .sheetNumberAndName
        case "view_name": job.naming = .viewName
        default: job.naming = .custom(c.args.string("naming")!)
        }
        switch c.args.string("colors")?.lowercased() {
        case "black_lines": job.colors = .blackLines
        case "grayscale": job.colors = .grayscale
        default: job.colors = .color
        }
        if let p = c.args.string("paper") { job.viewPaper = try Self.paper(p, imperial: m.units.system == .imperial) }
        let r: PDFExportResult
        do { r = try await PDFExporter.export(m, job: job) } catch { throw ToolError("PDF export failed: \(error.localizedDescription)") }
        return ToolOutput(["path": .string(r.files.first?.path ?? url.path), "files": .array(r.files.map { .string($0.path) }), "pages": .int(r.pageCount),
                           "sheets": .array(labels.map { .string($0) })])
    }

    func exportDWG(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let folder = Self.url(try c.args.requireString("folder"))
        var items: [Element] = []
        for (k, v) in try c.args.requireArray("views").enumerated() { items.append(try c.view(v, what: "views[\(k)]", allowSheets: true)) }
        let wantDWG = (c.args.string("format") ?? "dwg").lowercased() == "dwg"
        let helper = dwgHelper
        var note: String?
        if wantDWG && helper == nil { note = DWGExporter.unavailableReason(helpers: .none).map { $0 + " Wrote DXF instead." } }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch { throw ToolError("Can't create \(folder.path).") }
        let units: CADUnits = m.units.system == .metric && !m.isFurniture ? .millimeters : .inches
        var files: [JSONValue] = []
        for e in items {
            let (g, _) = graphics(e, m)
            let dxf = DXFWriter.write(g, units: units, layers: .aia, model: m)
            let title = e.sheet.map { "\($0.number) - \(e.name)" } ?? e.name
            let base = String(DWGExporter.fileName(title).dropLast(4))
            if wantDWG, let helper {
                let url = folder.appendingPathComponent(base + ".dwg")
                do {
                    let s = try DWGExporter.write(dxf: dxf, to: url, helper: helper)
                    files.append(["path": .string(url.path), "entities": .int(s.entities)])
                } catch { throw ToolError("DWG export of “\(title)” failed: \(error.localizedDescription)") }
            } else {
                let url = folder.appendingPathComponent(base + ".dxf")
                do { try dxf.write(to: url, options: .atomic) } catch { throw ToolError("Could not write \(url.path).") }
                files.append(["path": .string(url.path), "bytes": .int(dxf.count)])
            }
        }
        var o: [String: JSONValue] = ["files": .array(files)]
        if let note { o["note"] = .string(note) }
        return ToolOutput(.object(o))
    }
}
