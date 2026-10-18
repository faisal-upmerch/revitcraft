import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusCAD
import ArcusOutput
import ArcusPersistence

// MARK: - Context menu

@MainActor
final class ContextMenuBuilder: NSObject {
    let state: DocumentState
    let viewID: ElementID
    weak var canvas: Canvas2DView?
    init(state: DocumentState, viewID: ElementID, canvas: Canvas2DView?) { self.state = state; self.viewID = viewID; self.canvas = canvas }

    func item(_ title: String, _ symbol: String, _ cmd: CommandID) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(MenuTarget.perform(_:)), keyEquivalent: "")
        i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        i.representedObject = MenuCommand(state: state, id: cmd)
        i.target = MenuTarget.shared
        let reason = CommandRouter(state: state).disabledReason(cmd)
        i.isEnabled = reason == nil
        if let reason { i.toolTip = reason }
        return i
    }

    /// The canvas context menu: drawing-mode, element or empty-canvas composition (ContextMenus+Keys.swift). // BL-KEYS
    func menu(for hit: ElementID?) -> NSMenu { keysMenu(for: hit) }
}

struct MenuCommand { let state: DocumentState; let id: CommandID }
struct TypeEdit { let state: DocumentState; let typeID: ElementID }

@MainActor
final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    @objc func perform(_ sender: NSMenuItem) {
        guard let c = sender.representedObject as? MenuCommand else { return }
        CommandRouter(state: c.state).run(c.id)
    }
    @objc func editType(_ sender: NSMenuItem) {
        guard let t = sender.representedObject as? TypeEdit else { return }
        t.state.presented = .typeProperties(t.typeID)
    }
}

// MARK: - Links

@MainActor
struct LinkActions {
    let state: DocumentState

    func reload(_ ids: [ElementID]) {
        for id in ids {
            guard let e = state.model[id], let ld = e.link else { continue }
            guard ld.isLinked else { state.show("“\(ld.sourceName)” is an import (snapshot) and has no source to reload.", error: true); continue }
            var stale = false
            var url = ld.bookmark.flatMap { try? URL(resolvingBookmarkData: $0, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) }
            if url == nil || !FileManager.default.fileExists(atPath: url!.path) {
                locate(id, name: ld.sourceName)
                continue
            }
            let access = url!.startAccessingSecurityScopedResource()
            let u = url!
            let session = state.session
            let model = state.model
            state.runBackground("Reloading \(ld.sourceName)") { progress, cancelled in
                let tx = TransactionContext(model: model, name: "Reload Link")
                let report = try CADLinkService.reload(linkElementID: id, from: u, in: tx, progress: { progress($0, "Reading") }, isCancelled: cancelled)
                let changed = tx.touchedIDs.compactMap { tx.model[$0] }
                let drawings = tx.model.referenceDrawings.filter { model.referenceDrawings[$0.key] == nil }
                return (changed, drawings, report)
            } completion: { (r: Result<([Element], [String: ReferenceDrawing], CADImportReport), any Error>) in
                if access { u.stopAccessingSecurityScopedResource() }
                switch r {
                case .success(let (changed, drawings, report)):
                    session.perform("Reload \(ld.sourceName)") { live in
                        for d in drawings.values { live.addReferenceDrawing(d) }
                        for e in changed { live.insertPreservingID(e) }
                    }
                    state.show("Reloaded “\(ld.sourceName)”: \(report.converted) entities.")
                case .failure(let err): state.show("Reload failed: \(err)", error: true)
                }
                url = nil
            }
        }
    }

    func locate(_ id: ElementID, name: String) {
        let panel = NSOpenPanel()
        panel.message = "“\(name)” can't be found. Locate the file to repair the link."
        panel.allowedContentTypes = [UTType(filenameExtension: "dxf") ?? .data, UTType(filenameExtension: "dwg") ?? .data]
        guard let w = state.window else { return }
        panel.beginSheetModal(for: w) { r in
            guard r == .OK, let u = panel.url else { return }
            let bookmark = try? u.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            state.session.perform("Locate Link") { tx in tx.update(id) { $0.link?.bookmark = bookmark; $0.link?.sourcePath = u.path; $0.link?.sourceName = u.lastPathComponent } }
            reload([id])
        }
    }

    func convert(_ ids: [ElementID]) {
        guard let id = ids.first, let v = state.activeViewID else { return }
        let alert = NSAlert()
        alert.messageText = "Convert CAD geometry to Arcus elements"
        alert.informativeText = "Lines and arcs become detail lines in this view, texts become text notes and closed shapes become filled regions. The source file is never modified."
        alert.addButton(withTitle: "Detail Lines")
        alert.addButton(withTitle: "Room Separators")
        alert.addButton(withTitle: "Cancel")
        guard let w = state.window else { return }
        alert.beginSheetModal(for: w) { r in
            let level = state.activeView?.levelID ?? state.model.levels.first?.id
            var count = 0
            state.session.perform("Convert CAD") { tx in
                switch r {
                case .alertFirstButtonReturn:
                    count += try CADConverter.convert(linkElement: id, layers: nil, target: .detailLines(viewID: v), in: tx)
                    count += try CADConverter.convert(linkElement: id, layers: nil, target: .textNotes(viewID: v), in: tx)
                case .alertSecondButtonReturn:
                    guard let level else { return }
                    count += try CADConverter.convert(linkElement: id, layers: nil, target: .modelLines(levelID: level, category: .roomSeparationLines), in: tx)
                default: return
                }
            }
            if count > 0 { state.show("Converted \(count) entities.") }
        }
    }
}

// MARK: - Export

@MainActor
struct ExportActions {
    let state: DocumentState

    func exportDXF() {
        guard let v = state.activeViewID, let g = state.graphics.graphics(v), let view = state.model[v] else { state.show("Open a 2D view to export DXF."); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "dxf") ?? .data]
        panel.nameFieldStringValue = "\(view.name).dxf"
        guard let w = state.window else { return }
        panel.beginSheetModal(for: w) { r in
            guard r == .OK, let url = panel.url else { return }
            let metric = state.model.units.system == .metric
            let data = DXFWriter.write(g, units: metric ? .millimeters : .inches)
            do { try data.write(to: url, options: .atomic); state.show("Exported \(url.lastPathComponent).") }
            catch { state.show("Export failed: \(error.localizedDescription)", error: true) }
        }
    }

    func exportScheduleCSV() {
        guard let v = state.activeViewID, let s = state.model[v], s.schedule != nil else { return }
        let table = ScheduleEngine.compute(s, state.model)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(s.name).csv"
        guard let w = state.window else { return }
        panel.beginSheetModal(for: w) { r in
            guard r == .OK, let url = panel.url else { return }
            do { try ScheduleCSV.export(table).write(to: url, options: .atomic); state.show("Exported \(url.lastPathComponent).") }
            catch { state.show("Export failed: \(error.localizedDescription)", error: true) }
        }
    }

    func printSheets() {
        let m = state.model
        var pages: [Element] = []
        if let a = state.activeView, a.sheet != nil || a.view != nil { pages = [a] }
        guard !pages.isEmpty else { state.show("Open a sheet or view to print."); return }
        let printView = PrintableView(model: m, elements: pages, graphics: state.graphics)
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        if let s = pages.first?.sheet {
            let size = s.paper.landscapeSize
            info.paperSize = NSSize(width: size.x / 0.0254 * 72, height: size.y / 0.0254 * 72)
            info.orientation = .landscape
        }
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        let op = NSPrintOperation(view: printView, printInfo: info)
        op.jobTitle = pages.first?.name ?? "Arcus"
        if let w = state.window { op.runModal(for: w, delegate: nil, didRun: nil, contextInfo: nil) } else { op.run() }
    }
}

/// A print-only view drawing sheets/views as vectors.
final class PrintableView: NSView {
    let model: BIMModel
    let elements: [Element]
    let graphicsCache: [ElementID: ViewGraphics]
    init(model: BIMModel, elements: [Element], graphics: GraphicsStore) {
        self.model = model
        self.elements = elements
        var cache: [ElementID: ViewGraphics] = [:]
        for e in elements { if let g = graphics.graphics(e.id) { cache[e.id] = g } }
        graphicsCache = cache
        let size = elements.first?.sheet?.paper.landscapeSize ?? Vec2(0.42, 0.297)
        super.init(frame: NSRect(x: 0, y: 0, width: size.x / 0.0254 * 72, height: size.y / 0.0254 * 72))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let e = elements.first else { return }
        let g: ViewGraphics
        if let c = graphicsCache[e.id] { g = c }
        else if e.sheet != nil { g = SheetGraphicsBuilder(model: model, sheet: e).build() }
        else { g = ViewGraphicsBuilder(model: model, view: e).build() }
        var opts = RenderOptions.pdf(showOverlays: false)
        opts.printing = true
        let ppm = 72 / 0.0254
        if e.sheet != nil {
            GraphicsRenderer.draw(g, in: ctx, viewToDevice: CGAffineTransform(scaleX: ppm, y: ppm), pointsPerPaperMeter: ppm, options: opts)
        } else {
            let r = g.crop ?? g.extents
            let s = min(bounds.width * 0.9 / max(r.width, 1e-6), bounds.height * 0.9 / max(r.height, 1e-6))
            let t = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: bounds.midX - r.center.x * s, ty: bounds.midY - r.center.y * s)
            GraphicsRenderer.draw(g, in: ctx, viewToDevice: t, pointsPerPaperMeter: s * Double(g.scale), options: opts)
        }
    }
}
