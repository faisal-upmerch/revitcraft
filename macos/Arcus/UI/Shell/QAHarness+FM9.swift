import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// FM9: screenshots of the Furniture Library (hooked from `screenshots()` with one line, per appearance): every
// essential piece open in Furniture mode in {3D} (light only), Home ▸ Furniture with the bundled library, and in a
// project Insert ▸ Load Furniture and the Component Library's Furniture Library section.
extension QAHarness {
    static func fm9Screenshots(_ suffix: String) async {
        if suffix == "light" {
            for p in FurnitureLibrary.all where p.detail == .high {
                let doc = ArcusDocument(model: p.build(), displayName: p.name)
                NSDocumentController.shared.addDocument(doc)
                doc.makeWindowControllers()
                doc.showWindows()
                await pause(700)
                guard let s = doc.state, let w = s.window else { doc.close(); continue }
                w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
                if let v = view(s, kind: .threeD) {
                    s.open(v.id)
                    CommandRouter(state: s).run(.zoomExtents)
                    await pause(1300)
                    let file = p.name.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "'", with: "")
                    await shot(w, "fm9-piece-\(file)-3d-\(suffix)")
                }
                doc.updateChangeCount(.changeCleared)
                doc.close()
                await pause(300)
            }
        }
        // Home ▸ Furniture: the gallery by room, with search.
        let hub = AppDelegate.makeHubWindow(model: HomeModel(tab: .furniture))
        hub.title = "Home (QA)"
        hub.center()
        hub.orderFront(nil)
        await pause(1500)
        await shot(hub, "fm9-home-furniture-\(suffix)")
        hub.close()
        // A project: Load Furniture and the Component Library's Furniture Library.
        let (model, _) = ProjectTemplates.make(.architectural, units: .imperial, projectName: "Furniture Library")
        let doc = ArcusDocument(model: model, displayName: "Furniture Library")
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        await pause(900)
        if let s = doc.state, let w = s.window {
            w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
            s.presented = .fm8(.loadFurniture)
            await pause(1800)
            if let sheet = w.attachedSheet { await shot(sheet, "fm9-load-furniture-\(suffix)") } else { await shot(w, "fm9-load-furniture-\(suffix)") }
            s.presented = nil
            await pause(500)
            ComponentLibraryView.startInFurniture = true
            s.presented = .componentLibrary([])
            await pause(1800)
            if let sheet = w.attachedSheet { await shot(sheet, "fm9-component-library-furniture-\(suffix)") } else { await shot(w, "fm9-component-library-furniture-\(suffix)") }
            s.presented = nil
            ComponentLibraryView.startInFurniture = false
            await pause(500)
        }
        doc.updateChangeCount(.changeCleared)
        doc.close()
        await pause(500)
    }
}
