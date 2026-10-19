import AppKit
import Testing
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

/// POLISH: every command's symbol is a real SF Symbol (an unknown name draws nothing, as Railing's "fence" did on
/// Architecture ▸ Circulation), and so is every symbol the ribbons draw themselves (draw modes, the Family Editor).
@MainActor
@Suite("POLISH ribbon symbols")
struct POLISHSymbolTests {
    /// A symbol name the app can draw: an SF Symbol of this system or an image bundled with the app.
    static func resolves(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil || NSImage(named: name) != nil
    }

    @Test("Every command in the catalog has a symbol that draws")
    func everyCommandSymbolResolves() {
        let missing = CommandCatalog.all.filter { !Self.resolves($0.symbol) }.map { "\($0.id.rawValue) (\($0.title)): \($0.symbol)" }
        #expect(missing.isEmpty, "Commands without a drawable symbol:\n\(missing.joined(separator: "\n"))")
    }

    @Test("Every ribbon button of every tab, in both modes, has a symbol that draws")
    func everyRibbonButtonResolves() {
        var missing: [String] = []
        for mode in [DocumentKind.project, .furniture] {
            for tab in RibbonTab.tabs(for: mode) {
                for p in RibbonContent.panels(tab, mode: mode) {
                    for item in p.items {
                        for id in [item.id] + item.variants where !Self.resolves(CommandCatalog.info(id).symbol) {
                            missing.append("\(mode) \(tab.rawValue) ▸ \(p.title) ▸ \(CommandCatalog.info(id).title): \(CommandCatalog.info(id).symbol)")
                        }
                    }
                }
            }
        }
        #expect(missing.isEmpty, "Ribbon buttons without a drawable symbol:\n\(missing.joined(separator: "\n"))")
    }

    @Test("Draw modes, the Family Editor's own buttons and the panel menus have symbols that draw")
    func ribbonOwnSymbolsResolve() {
        let modes = ["Line", "Rectangle", "Arc", "Circle", "Polygon", "Pick Lines", "Pick Walls", "Pick Panels", "Inscribed Polygon", "Circumscribed Polygon",
                     "Tangent Arc", "Fillet Arc", "Start-End-Radius Arc", "Center-ends Arc", "Tangent End Arc", "Spline", "Ellipse", "Partial Ellipse", "Other"]
        let own = modes.map(RibbonContent.drawSymbol) + FamilyPreviewMode.allCases.map(\.symbol)
            + ["cursorarrow", "arrow.up.left.and.down.right.magnifyingglass", "cube.transparent", "squareshape.split.2x2.dotted", "square.and.arrow.down",
               "equal", "ruler.fill", "scribble", "circle.lefthalf.filled", "tag", "eye", "eye.slash", "xmark.rectangle", "trash", "plus.square.on.square",
               "xmark.circle", "plus", "pencil", "minus", "checkmark", "xmark", "line.diagonal", "rectangle", "arrow.up.and.down", "arrow.uturn.backward",
               "arrow.right.square"]
        let missing = own.filter { !Self.resolves($0) }
        #expect(missing.isEmpty, "Ribbon symbols that draw nothing: \(missing)")
    }
}
