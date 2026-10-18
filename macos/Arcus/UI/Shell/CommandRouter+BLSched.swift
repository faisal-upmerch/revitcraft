import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusCAD
import ArcusOutput

// BL-SCHED: schedule ribbon commands, Link/Import CAD with a format picker, image export and File ▸ New entries.

extension CommandRouter {
    static let blSchedFileCommands: Set<CommandID> = [.linkCAD, .importCAD, .exportImage, .newTitleBlock, .newAnnotationSymbol]

    func blSchedDisabledReason(_ id: CommandID) -> String? {
        if ScheduleCommands.all.contains(id) { return ScheduleCommands.disabledReason(id, state) }
        if id == .exportImage {
            guard let v = state.activeView else { return "Open a view or sheet to export an image." }
            if v.schedule != nil { return "Schedules export to CSV (Export Schedule CSV) or to PDF on a sheet." }
        }
        return nil
    }

    /// Runs a BL-SCHED command; false when the command isn't one of them.
    func performBLSched(_ id: CommandID) -> Bool {
        if ScheduleCommands.all.contains(id) { ScheduleCommands.perform(id, state); return true }
        switch id {
        case .linkCAD, .importCAD: CADFormatPicker(state: state, isLink: id == .linkCAD).run()
        case .exportImage: ImageExportAction(state: state).run()
        case .newTitleBlock: newFamily(.titleBlock, name: "Title Block")
        case .newAnnotationSymbol: newFamily(.genericAnnotation, name: "Annotation Symbol")
        default: return false
        }
        return true
    }

    private func newFamily(_ t: FamilyTemplate, name: String) {
        var f = FamilyTemplates.make(t)
        f.name = name
        FamilyEditorWindowController.open(new: f, state: state)
    }
}

/// Link CAD / Import CAD: one file dialog with a format picker (all CAD formats, DXF, DWG). DWG goes through the
/// configured DWG route (licensed SDK or external converter, see Settings); without one, the truthful "DWG
/// unavailable" dialog explains why.
@MainActor
final class CADFormatPicker: NSObject {
    enum Format: Int, CaseIterable {
        case all, dxf, dwg
        var title: String {
            switch self {
            case .all: "All CAD formats (DWG, DXF)"
            case .dxf: "DXF (*.dxf)"
            case .dwg: "DWG (*.dwg)"
            }
        }
        var extensions: [String] {
            switch self {
            case .all: ["dwg", "dxf"]
            case .dxf: ["dxf"]
            case .dwg: ["dwg"]
            }
        }
    }

    let state: DocumentState
    let isLink: Bool
    private weak var panel: NSOpenPanel?
    private static var running: CADFormatPicker?

    init(state: DocumentState, isLink: Bool) { self.state = state; self.isLink = isLink }

    static func contentTypes(_ f: Format) -> [UTType] { f.extensions.map { UTType(filenameExtension: $0) ?? .data } }

    func run() {
        let panel = NSOpenPanel()
        panel.title = isLink ? "Link CAD" : "Import CAD"
        panel.prompt = isLink ? "Link" : "Import"
        panel.message = isLink ? "Linked drawings reload when the file changes. DWG uses the DWG route set up in Settings."
                               : "An import is a snapshot; the source file is not kept. DWG uses the DWG route set up in Settings."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.contentTypes(.all)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for f in Format.allCases { popup.addItem(withTitle: f.title) }
        popup.target = self
        popup.action = #selector(formatChanged(_:))
        let label = NSTextField(labelWithString: "Files of type:")
        let row = NSStackView(views: [label, popup])
        row.orientation = .horizontal
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        panel.accessoryView = row
        panel.isAccessoryViewDisclosed = true
        self.panel = panel
        Self.running = self
        let finish: (NSApplication.ModalResponse) -> Void = { [self] r in
            Self.running = nil
            guard r == .OK, let url = panel.url else { return }
            open(url)
        }
        if let w = state.window { panel.beginSheetModal(for: w, completionHandler: finish) } else { finish(panel.runModal()) }
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        panel?.allowedContentTypes = Self.contentTypes(Format(rawValue: sender.indexOfSelectedItem) ?? .all)
    }

    func open(_ url: URL) {
        let isDWG = url.pathExtension.lowercased() == "dwg"
        if isDWG && !DWGProviders.current.isAvailable { state.presented = .dwgUnavailable; return }
        state.presented = .importCAD(url, isLink: isLink, isDWG: isDWG)
    }
}

/// File ▸ Export ▸ Image: the active view or sheet as PNG or JPEG, rendered locally (2D with the print renderer,
/// 3D with the viewport's offscreen renderer).
@MainActor
final class ImageExportAction: NSObject {
    let state: DocumentState
    private weak var panel: NSSavePanel?
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private static var running: ImageExportAction?
    static let widths = [1200, 2400, 4800, 9600]

    init(state: DocumentState) { self.state = state }

    func run() {
        guard let v = state.activeView else { return }
        let panel = NSSavePanel()
        panel.title = "Export Image"
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(v.sheet.map { "\($0.number) - " } ?? "")\(v.name).png"
        for f in RasterImageFormat.allCases { formatPopup.addItem(withTitle: f.rawValue) }
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        for w in Self.widths { sizePopup.addItem(withTitle: "\(w) pixels wide") }
        sizePopup.selectItem(at: 1)
        let row = NSStackView(views: [NSTextField(labelWithString: "Format:"), formatPopup, NSTextField(labelWithString: "Size:"), sizePopup])
        row.orientation = .horizontal
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        panel.accessoryView = row
        self.panel = panel
        Self.running = self
        let finish: (NSApplication.ModalResponse) -> Void = { [self] r in
            Self.running = nil
            guard r == .OK, let url = panel.url else { return }
            export(to: url)
        }
        if let w = state.window { panel.beginSheetModal(for: w, completionHandler: finish) } else { finish(panel.runModal()) }
    }

    var format: RasterImageFormat { RasterImageFormat.allCases[max(0, formatPopup.indexOfSelectedItem)] }

    @objc private func formatChanged() {
        guard let panel else { return }
        panel.allowedContentTypes = [format == .png ? .png : .jpeg]
        let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + "." + format.fileExtension
    }

    func export(to url: URL) {
        guard let v = state.activeView else { return }
        let width = Self.widths[max(0, sizePopup.indexOfSelectedItem)]
        let image: CGImage?
        var dpi: Double?
        if v.view?.kind == .threeD {
            let host = state.canvases[v.id] as? Viewport3DHost
            let bounds = host?.viewport.bounds.size ?? CGSize(width: 16, height: 10)
            let aspect = bounds.width > 0 ? bounds.height / bounds.width : 0.625
            image = host?.viewport.snapshot(size: CGSize(width: width, height: Int(Double(width) * aspect)))
        } else if let sheet = v.sheet {
            let g = state.graphics.graphics(v.id) ?? SheetGraphicsBuilder(model: state.model, sheet: v).build()
            let paper = sheet.paper.landscapeSize
            image = RasterExporter.render(g, paper: paper, pixelWidth: width)
            dpi = RasterExporter.dpi(pixelWidth: width, paperWidth: paper.x)
        } else {
            let g = state.graphics.graphics(v.id) ?? ViewGraphicsBuilder(model: state.model, view: v).build()
            image = RasterExporter.render(g, pixelWidth: width)
        }
        guard let image, let data = RasterExporter.encode(image, as: format, dpi: dpi) else {
            state.show("The image couldn't be rendered\(v.view?.kind == .threeD ? " (open the 3D view first)" : "").", error: true)
            return
        }
        do { try data.write(to: url, options: .atomic); state.show("Exported \(url.lastPathComponent) (\(image.width) × \(image.height)).") }
        catch { state.show("Export failed: \(error.localizedDescription)", error: true) }
    }
}
