import AppKit
import UniformTypeIdentifiers
import ArcusCalc
import ArcusDomain
import ArcusCAD

// DWG: File ▸ Open… (and Finder's Open With) accept DWG and DXF drawings. A drawing isn't an Arcus project, so opening
// one starts a new project from the Architectural template and shows the Import CAD dialog for it, the same dialog
// Insert ▸ Import CAD uses (DWG through the bundled engines; see BundledDWGEngine.swift).

/// The app's document controller: `.arcus` projects open as documents; CAD drawings open as an import into a new project.
final class ArcusDocumentController: NSDocumentController {
    /// File extensions opened as a CAD import rather than as a document.
    static let cadExtensions: Set<String> = ["dwg", "dxf"]

    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        openPanel.message = "Open an Arcus project, or a DWG or DXF drawing to import into a new project."
        return super.runModalOpenPanel(openPanel, forTypes: (types ?? []) + Self.cadExtensions.sorted())
    }

    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        guard Self.cadExtensions.contains(url.pathExtension.lowercased()) else {
            super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
            return
        }
        let doc = Self.openDrawing(url)
        completionHandler(doc, false, nil)
    }

    /// A new untitled project (units from this Mac's measurement system) with the Import CAD dialog for `url`.
    @discardableResult
    static func openDrawing(_ url: URL) -> NSDocument? {
        let isDWG = url.pathExtension.lowercased() == "dwg"
        let units: UnitsSettings = Locale.current.measurementSystem == .us ? .imperial : .metric
        let name = url.deletingPathExtension().lastPathComponent
        let (model, _) = ProjectTemplates.make(.architectural, units: units, projectName: name)
        let doc = ArcusDocument(model: model, displayName: nil)
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        AppDelegate.shared?.closeHub()
        if let state = doc.state {
            if isDWG && !DWGProviders.current.isAvailable { state.presented = .dwgUnavailable }
            else { state.presented = .importCAD(url, isLink: false, isDWG: isDWG) }
        }
        return doc
    }
}
