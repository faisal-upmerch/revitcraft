import CoreGraphics
import Foundation
import ArcusGeometry
import ArcusDomain
import Synchronization

/// Vector PDF export of sheets and views.
///
/// - Every page is drawn by `GraphicsRenderer` into a `CGPDFContext`: lines, arcs and hatches stay vector, text stays
///   real (searchable) CoreText text. Nothing is rasterized (`rasterPages` is always 0).
/// - Sheets print at their paper size (`PaperSize.landscapeSize`); views without a sheet go on `viewPaper` with 10 mm
///   margins, either fitted or at their own scale.
/// - Output is written to a temporary directory on the destination volume and moved into place only after every page
///   has rendered. Replacing an existing file is an atomic `rename(2)`; if any move fails, already-moved files are
///   rolled back (originals restored from hard-link backups). Cancellation or failure deletes all partial output and
///   leaves existing files untouched.
/// - Bookmarks and internal links use CoreGraphics' outline and named-destination support.
///   Links only resolve inside one file: in individual-file mode a marker whose target is in another file is not linked.
/// - Metadata: Title (project name), Creator (`job.creator`); Producer is set by Quartz. No user name is written.
public enum PDFExporter {
    /// PDF points per meter.
    public static let pointsPerMeter = 72.0 / 0.0254
    /// Margin around views printed without a sheet.
    public static let viewMargin = 0.010

    // MARK: Public API

    /// Runs off the main actor. Writes to a temporary directory then moves files into place atomically; on cancellation
    /// or failure deletes partial output and leaves existing files untouched. `graphics` supplies display lists (callers may
    /// pass cached builds); by default they are built on demand.
    @concurrent
    public static func export(_ model: BIMModel, job: PDFExportJob, graphics: (@Sendable (Element) -> ViewGraphics?)? = nil,
                              progress: @Sendable (Double, String) -> Void = { _, _ in },
                              isCancelled: @Sendable () -> Bool = { false }) async throws -> PDFExportResult {
        let start = Date()
        func cancelled() -> Bool { isCancelled() || Task.isCancelled }
        try validate(model, job)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: job.outputDirectory, withIntermediateDirectories: true)
        } catch {
            throw PDFExportError("Can't create the folder “\(job.outputDirectory.path)”: \(error.localizedDescription)")
        }

        var planned = plan(model, job)
        var skipped: [URL] = []
        let existing = planned.map(\.url).filter { fm.fileExists(atPath: $0.path) }
        switch job.overwrite {
        case .fail:
            if !existing.isEmpty {
                let names = existing.map(\.lastPathComponent).joined(separator: ", ")
                throw PDFExportError(existing.count == 1 ? "“\(names)” already exists." : "\(existing.count) files already exist: \(names).", conflicts: existing)
            }
        case .skip:
            skipped = existing
            planned.removeAll { existing.contains($0.url) }
        case .uniquify:
            var taken = Set(planned.map { $0.url.lastPathComponent.lowercased() })
            for i in planned.indices where fm.fileExists(atPath: planned[i].url.path) {
                planned[i].url = uniqueURL(planned[i].url, taken: &taken)
            }
        case .replace:
            break
        }
        if planned.isEmpty {
            return PDFExportResult(files: [], pageCount: 0, vectorPages: 0, rasterPages: 0, skippedExisting: skipped,
                                   warnings: [], elapsed: Date().timeIntervalSince(start))
        }

        let staging = try stagingDirectory(for: job.outputDirectory)
        defer { try? fm.removeItem(at: staging) }
        let cache = GraphicsCache(model: model, supplied: graphics)
        let totalPages = planned.reduce(0) { $0 + $1.items.count }
        var pagesDone = 0
        var warnings: [String] = []
        var placements: [(tmp: URL, dest: URL)] = []
        for (i, file) in planned.enumerated() {
            if cancelled() { throw CancellationError() }
            let tmp = staging.appendingPathComponent("page-set-\(i).pdf")
            var writer = PageSetWriter(model: model, job: job, items: file.items, cache: cache)
            try writer.write(to: tmp, fileTitle: file.url.deletingPathExtension().lastPathComponent) { title in
                if cancelled() { return false }
                pagesDone += 1
                progress(Double(pagesDone) / Double(totalPages), title)
                return true
            }
            warnings += writer.warnings
            placements.append((tmp, file.url))
        }
        if cancelled() { throw CancellationError() }
        try commit(placements, backups: staging)
        return PDFExportResult(files: placements.map(\.dest), pageCount: pagesDone, vectorPages: pagesDone, rasterPages: 0,
                               skippedExisting: skipped, warnings: warnings, elapsed: Date().timeIntervalSince(start))
    }

    /// Existing files at the planned destinations (before overwrite-policy handling), for the UI to ask before exporting.
    public static func conflicts(_ model: BIMModel, job: PDFExportJob) -> [URL] {
        plan(model, job).map(\.url).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// File name (with ".pdf") for an item. Sanitized: no "/", ":", "\" or control characters, no leading dot,
    /// at most 200 characters and 240 UTF-8 bytes.
    public static func fileName(for item: PDFExportItem, model: BIMModel, naming: PDFNaming) -> String {
        let e = model[item.elementID]
        let name = e?.name ?? "Missing \(item.elementID)"
        let base: String
        switch naming {
        case .sheetNumberAndName:
            if let s = e?.sheet { base = s.number.isEmpty ? name : "\(s.number) - \(name)" } else { base = "\(viewKindLabel(e)) - \(name)" }
        case .viewName:
            base = name
        case .custom(let template):
            let sheet = e?.sheet != nil ? e : model.sheet(containing: item.elementID)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = Calendar(identifier: .gregorian)
            f.dateFormat = "yyyy-MM-dd"
            let tokens: [(String, String)] = [
                ("{Project Number}", model.projectInfo.projectNumber), ("{Project Name}", model.projectInfo.projectName),
                ("{Sheet Number}", sheet?.sheet?.number ?? ""), ("{Sheet Name}", sheet?.name ?? ""),
                ("{View Name}", name), ("{Date}", f.string(from: Date())),
            ]
            var s = template
            for (k, v) in tokens { s = s.replacingOccurrences(of: k, with: v) }
            base = s
        }
        return sanitize(base) + ".pdf"
    }

    /// Bookmark / progress title of an item's page ("A101 – Ground Floor Plan", "Floor Plan: Level 1").
    public static func pageTitle(for item: PDFExportItem, model: BIMModel) -> String {
        guard let e = model[item.elementID] else { return "Missing \(item.elementID)" }
        if let s = e.sheet { return s.number.isEmpty ? e.name : "\(s.number) – \(e.name)" }
        return "\(viewKindLabel(e)): \(e.name)"
    }

    // MARK: Planning

    struct PlannedFile { var url: URL; var items: [PDFExportItem] }

    static func plan(_ model: BIMModel, _ job: PDFExportJob) -> [PlannedFile] {
        let dir = job.outputDirectory
        if job.combined {
            var base = job.combinedFileName
            if base.lowercased().hasSuffix(".pdf") { base = String(base.dropLast(4)) }
            return [PlannedFile(url: dir.appendingPathComponent(sanitize(base) + ".pdf"), items: job.items)]
        }
        var taken = Set<String>()
        return job.items.map { item in
            var url = dir.appendingPathComponent(fileName(for: item, model: model, naming: job.naming))
            if taken.contains(url.lastPathComponent.lowercased()) { url = uniqueURL(url, taken: &taken, checkDisk: false) }
            taken.insert(url.lastPathComponent.lowercased())
            return PlannedFile(url: url, items: [item])
        }
    }

    static func validate(_ model: BIMModel, _ job: PDFExportJob) throws {
        guard !job.items.isEmpty else { throw PDFExportError("Nothing to export: choose at least one sheet or view.") }
        var problems: [String] = []
        for item in job.items {
            guard let e = model[item.elementID] else { problems.append("\(item.elementID) no longer exists"); continue }
            switch item.kind {
            case .sheet where e.sheet == nil: problems.append("“\(e.name)” is not a sheet")
            case .view where e.view == nil && e.schedule == nil: problems.append("“\(e.name)” is not a view")
            default: break
            }
        }
        if !problems.isEmpty { throw PDFExportError("Can't export: " + problems.joined(separator: "; ") + ".") }
    }

    static func viewKindLabel(_ e: Element?) -> String {
        if let v = e?.view { return v.kind.rawValue }
        if e?.schedule != nil { return "Schedule" }
        return "View"
    }

    static func sanitize(_ s: String) -> String {
        var out = ""
        var lastSpace = false
        for ch in s {
            let isControl = ch.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }
            var c = ch
            if isControl || ch.isWhitespace { c = " " }
            if ch == "/" || ch == ":" || ch == "\\" { c = "-" }
            if c == " " {
                if lastSpace { continue }
                lastSpace = true
            } else { lastSpace = false }
            out.append(c)
        }
        out = out.trimmingCharacters(in: .whitespaces)
        while out.hasPrefix(".") { out.removeFirst() }
        out = out.trimmingCharacters(in: .whitespaces)
        if out.isEmpty { out = "Untitled" }
        while out.count > 196 || out.utf8.count > 236 { out.removeLast() }
        out = out.trimmingCharacters(in: .whitespaces)
        return out.isEmpty ? "Untitled" : out
    }

    static func uniqueURL(_ url: URL, taken: inout Set<String>, checkDisk: Bool = true) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        var n = 2
        while true {
            let candidate = dir.appendingPathComponent("\(base) (\(n)).pdf")
            let key = candidate.lastPathComponent.lowercased()
            if !taken.contains(key) && !(checkDisk && FileManager.default.fileExists(atPath: candidate.path)) {
                taken.insert(key)
                return candidate
            }
            n += 1
        }
    }

    // MARK: Files

    static func stagingDirectory(for output: URL) throws -> URL {
        let fm = FileManager.default
        if let d = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: output, create: true) { return d }
        let d = output.appendingPathComponent(".arcus-export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Moves staged files into place. Replacement is an atomic rename; on failure every move is rolled back.
    static func commit(_ placements: [(tmp: URL, dest: URL)], backups: URL) throws {
        let fm = FileManager.default
        var done: [(dest: URL, backup: URL?)] = []
        do {
            for (i, p) in placements.enumerated() {
                var backup: URL?
                if fm.fileExists(atPath: p.dest.path) {
                    let b = backups.appendingPathComponent("backup-\(i).pdf")
                    do { try fm.linkItem(at: p.dest, to: b) } catch { try fm.copyItem(at: p.dest, to: b) }
                    backup = b
                }
                if rename(p.tmp.path, p.dest.path) != 0 {
                    let err = errno
                    guard err == EXDEV else { throw PDFExportError("Can't write “\(p.dest.lastPathComponent)”: \(String(cString: strerror(err))).") }
                    // Staging landed on another volume: copy next to the destination, then rename atomically.
                    let near = p.dest.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
                    try fm.copyItem(at: p.tmp, to: near)
                    if rename(near.path, p.dest.path) != 0 {
                        let e2 = errno
                        try? fm.removeItem(at: near)
                        throw PDFExportError("Can't write “\(p.dest.lastPathComponent)”: \(String(cString: strerror(e2))).")
                    }
                }
                done.append((p.dest, backup))
            }
        } catch {
            for d in done.reversed() {
                if let b = d.backup { _ = rename(b.path, d.dest.path) } else { _ = unlink(d.dest.path) }
            }
            throw error
        }
    }
}

// MARK: - Graphics cache

/// Memoizes view display lists for one export (a view is built once even when its sheet's layout is queried twice).
final class GraphicsCache: Sendable {
    let model: BIMModel
    let supplied: (@Sendable (Element) -> ViewGraphics?)?
    private let store = Mutex<[ElementID: ViewGraphics]>([:])

    init(model: BIMModel, supplied: (@Sendable (Element) -> ViewGraphics?)?) {
        self.model = model
        self.supplied = supplied
    }

    func graphics(_ v: Element) -> ViewGraphics {
        if let g = store.withLock({ $0[v.id] }) { return g }
        let g = supplied?(v) ?? ViewGraphicsBuilder(model: model, view: v).build()
        store.withLock { $0[v.id] = g }
        return g
    }

    var provider: @Sendable (Element) -> ViewGraphics? { { [self] v in self.graphics(v) } }
}

// MARK: - Page set writer

/// Writes one PDF file containing a sequence of pages.
struct PageSetWriter {
    let model: BIMModel
    let job: PDFExportJob
    let items: [PDFExportItem]
    let cache: GraphicsCache
    var warnings: [String] = []
    /// View → 1-based page number in this file (sheet placement wins over a standalone view page).
    var viewPages: [ElementID: Int] = [:]

    static let k = PDFExporter.pointsPerMeter

    init(model: BIMModel, job: PDFExportJob, items: [PDFExportItem], cache: GraphicsCache) {
        self.model = model; self.job = job; self.items = items; self.cache = cache
        for (i, item) in items.enumerated() where item.kind == .sheet {
            for vp in model.owned(byView: item.elementID) {
                if let v = vp.viewport?.viewID, viewPages[v] == nil { viewPages[v] = i + 1 }
            }
        }
        for (i, item) in items.enumerated() where item.kind == .view && viewPages[item.elementID] == nil {
            viewPages[item.elementID] = i + 1
        }
    }

    static func destinationName(_ view: ElementID) -> CFString { "arcus-view-\(view.raw)" as CFString }

    func pageSize(_ item: PDFExportItem) -> CGSize {
        let paper: Vec2
        if item.kind == .sheet {
            paper = (model[item.elementID]?.sheet?.paper ?? .a1).landscapeSize
        } else {
            let p = job.viewPaper.landscapeSize
            paper = job.viewLandscape ? p : Vec2(p.y, p.x)
        }
        return CGSize(width: paper.x * PageSetWriter.k, height: paper.y * PageSetWriter.k)
    }

    /// Renders every page. `pageDone` is called after each page with its title and returns false to cancel.
    mutating func write(to url: URL, fileTitle: String, pageDone: (String) -> Bool) throws {
        var firstBox = CGRect(origin: .zero, size: pageSize(items[0]))
        let projectName = model.projectInfo.projectName
        let aux: [CFString: Any] = [
            kCGPDFContextTitle: projectName.isEmpty ? fileTitle : projectName,
            kCGPDFContextCreator: job.creator,
        ]
        guard let ctx = CGContext(url as CFURL, mediaBox: &firstBox, aux as CFDictionary) else {
            throw PDFExportError("Can't create a PDF at “\(url.lastPathComponent)”.")
        }
        var outline: [[String: Any]] = []
        var closed = false
        defer { if !closed { ctx.closePDF() } }
        for (i, item) in items.enumerated() {
            var box = CGRect(origin: .zero, size: pageSize(item))
            let boxData = withUnsafeBytes(of: &box) { Data($0) }
            ctx.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            let title = PDFExporter.pageTitle(for: item, model: model)
            if let e = model[item.elementID] {
                if item.kind == .sheet { drawSheet(e, page: i + 1, in: ctx) } else { drawView(e, page: i + 1, size: box.size, in: ctx) }
            }
            ctx.endPDFPage()
            outline.append([kCGPDFOutlineTitle as String: title, kCGPDFOutlineDestination as String: i + 1])
            if !pageDone(title) {
                ctx.closePDF()
                closed = true
                throw CancellationError()
            }
        }
        if job.bookmarks {
            CGPDFContextSetOutline(ctx, [kCGPDFOutlineChildren as String: outline] as CFDictionary)
        }
        ctx.closePDF()
        closed = true
    }

    // MARK: Sheets

    func drawSheet(_ sheet: Element, page: Int, in ctx: CGContext) {
        let k = PageSetWriter.k
        let builder = SheetGraphicsBuilder(model: model, sheet: sheet, includeGuides: !job.hideCropBoundaries, viewGraphics: cache.provider)
        var g = builder.build()
        let layouts = builder.layouts()
        if !job.hideCropBoundaries {
            let st = GStroke(weight: 1, color: RGBColor(0.2, 0.2, 0.2), pattern: .dash)
            for (l, graphics) in layouts where graphics != nil {
                g.items.append(GItem(elementID: nil, category: .viewports, layer: .overlay,
                                     primitives: [.polyline(l.box.corners, closed: true, st)], selectable: false))
            }
        }
        let toPage = CGAffineTransform(scaleX: CGFloat(k), y: CGFloat(k))
        GraphicsRenderer.draw(g, in: ctx, viewToDevice: toPage, pointsPerPaperMeter: k, options: .pdf(showOverlays: !job.hideCropBoundaries))
        for (l, graphics) in layouts {
            if viewPages[l.viewID] == page {
                ctx.addDestination(PageSetWriter.destinationName(l.viewID), at: CGPoint(x: l.box.min.x * k, y: l.box.max.y * k))
            }
            guard job.internalLinks, let graphics else { continue }
            for item in graphics.items where item.layer != .overlay {
                guard let target = item.targetViewID, target != l.viewID, viewPages[target] != nil, !item.bounds.isEmpty else { continue }
                let r = Rect2(points: item.bounds.corners.map(l.transform.apply)).intersection(l.box)
                guard !r.isEmpty, r.width > 0, r.height > 0 else { continue }
                ctx.setDestination(PageSetWriter.destinationName(target),
                                   for: CGRect(x: r.min.x * k, y: r.min.y * k, width: r.width * k, height: r.height * k))
            }
        }
    }

    // MARK: Views

    mutating func drawView(_ v: Element, page: Int, size: CGSize, in ctx: CGContext) {
        let k = PageSetWriter.k
        let m = PDFExporter.viewMargin * k
        let printable = CGRect(x: m, y: m, width: size.width - 2 * m, height: size.height - 2 * m)
        let options = RenderOptions.pdf(showOverlays: !job.hideCropBoundaries)
        if viewPages[v.id] == page {
            ctx.addDestination(PageSetWriter.destinationName(v.id), at: CGPoint(x: 0, y: size.height))
        }
        if v.schedule != nil {
            let table = ScheduleEngine.compute(v, model)
            let paperH = Double(size.height) / k
            let prims = ScheduleLayout.primitives(table, topLeft: Vec2(PDFExporter.viewMargin, paperH - PDFExporter.viewMargin))
            let g = ViewGraphics(viewID: v.id, scale: 1, items: [GItem(elementID: v.id, category: .schedules, layer: .annotation, primitives: prims)],
                                 extents: Rect2(min: .zero, max: Vec2(Double(size.width) / k, paperH)), crop: nil, modelRevision: model.revision)
            if table.totalWidth * k > Double(printable.width) + 0.5 {
                warnings.append("Schedule “\(v.name)” is wider than the \(job.viewPaper.rawValue) printable area and was clipped.")
            }
            GraphicsRenderer.draw(g, in: ctx, viewToDevice: CGAffineTransform(scaleX: CGFloat(k), y: CGFloat(k)), pointsPerPaperMeter: k,
                                  options: options, clip: printable)
            return
        }
        let g = cache.graphics(v)
        guard g.items.contains(where: { $0.layer != .overlay }) else {
            warnings.append("View “\(v.name)” is empty.")
            return
        }
        let n = Double(max(g.scale, 1))
        // Content region as placed on sheets (crop, else model extents), plus room for nearby annotation.
        let region = SheetGraphicsBuilder.viewRegion(g).expanded(by: 0.015 * n)
        let paperW = region.width / n, paperH = region.height / n
        let pw = Double(printable.width) / k, ph = Double(printable.height) / k
        var f = 1.0
        switch job.zoom {
        case .fit:
            f = min(pw / max(paperW, 1e-6), ph / max(paperH, 1e-6))
            if !f.isFinite || f <= 0 { f = 1 }
        case .actual:
            if paperW > pw + 1e-6 || paperH > ph + 1e-6 {
                warnings.append("View “\(v.name)” at \(ViewScales.label(g.scale, imperial: model.units.system == .imperial)) is larger than the \(job.viewPaper.rawValue) printable area and was clipped.")
            }
        }
        let s = CGFloat(k * f / n)
        let t = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -CGFloat(region.center.x), y: -CGFloat(region.center.y))
        GraphicsRenderer.draw(g, in: ctx, viewToDevice: t, pointsPerPaperMeter: k * f, options: options, clip: printable)
        guard job.internalLinks else { return }
        for item in g.items where item.layer != .overlay {
            guard let target = item.targetViewID, target != v.id, viewPages[target] != nil, !item.bounds.isEmpty else { continue }
            let pts = item.bounds.corners.map { CGPoint(x: $0.x, y: $0.y).applying(t) }
            let r = CGRect(x: pts.map(\.x).min()!, y: pts.map(\.y).min()!, width: 0, height: 0)
                .union(CGRect(x: pts.map(\.x).max()!, y: pts.map(\.y).max()!, width: 0, height: 0))
                .intersection(printable)
            guard !r.isNull, r.width > 0, r.height > 0 else { continue }
            ctx.setDestination(PageSetWriter.destinationName(target), for: r)
        }
    }
}
