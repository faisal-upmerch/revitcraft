import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// W2-LIB: interaction QA for the component library (hooked from `interaction()` with one line).
extension QAHarness {
    /// Opens the library from its command, places a library sofa with the mouse, and checks that only that family was
    /// loaded. The sofa is removed again so later steps see the same model.
    static func libraryInteraction(_ s: DocumentState, _ d: CanvasDriver) async {
        await step("Canvas: component library - open, place a sofa with the mouse") {
            let before = d.failures.count
            let familiesBefore = s.model.elements(.families).count
            CommandRouter(state: s).run(.componentLibrary)
            await pause(250)
            try check(s.presented == .componentLibrary([]), "Component Library… did not open the library")
            guard let item = ComponentLibrary.item(named: "Sofa - 3 Seat") else { throw QAError("library item missing") }
            let t = item.defaultType(for: s.model.units.system)
            s.placeFromLibrary(item, typeName: t.name)
            await pause(250)
            try check(s.presented == nil, "the library stayed open after Place")
            try check(s.activeTool?.commandID == .component, "Place did not start the Component tool (tool: \(s.activeTool?.title ?? "none"))")
            if let c = d.canvas { s.window?.makeFirstResponder(c) }
            let p = Vec2(3, 5)
            d.mouse(.mouseMoved, d.windowPoint(p)); await pause(40)
            await d.verify("library sofa preview")
            d.click(model: p); await pause(60)
            d.escape(); d.escape()
            await d.verify("after placing a library sofa")
            let placed = s.model.elements(.furniture).filter { s.model.type(of: $0)?.typeData?.familyName == item.name }
            try check(placed.count == 1, "expected 1 placed sofa, found \(placed.count)")
            try check(s.model.elements(.families).count == familiesBefore + 1, "expected exactly one family to load")
            try check(s.model.family(named: item.name)?.family?.types.map(\.name) == [t.name], "the project embeds more than the used type")
            s.session.delete(placed.map(\.id))
            try check(s.model.elements(.furniture).isEmpty, "the placed sofa was not deleted (\(s.session.lastError?.message ?? "no error"))")
            let new = d.failures.dropFirst(before)
            try check(new.isEmpty, new.joined(separator: " || "))
            return "placed \(item.name): \(t.name); one family loaded on first use"
        }
    }
}
