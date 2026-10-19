import AppKit
import SwiftUI
import Testing
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

/// DIALOGS: the dialog design system (Docs/Dialogs.md): size classes, opaque colours, report parsing, readable error
/// text, and that the dialog catalog the render test draws covers every `DialogKind`.
@MainActor
@Suite("Dialog design system")
struct DialogDesignTests {
    @Test("Size classes are 420, 560, 720, 900 and 1120 pt, each with room for its labels")
    func sizes() {
        #expect([DialogSize.small, .medium, .large, .wide, .extraWide].map(\.width) == [420, 560, 720, 900, 1120])
        for s in [DialogSize.small, .medium, .large, .wide, .extraWide] {
            #expect(s.minWidth == s.width && s.maxWidth > s.width)
            #expect(s.labelWidth < s.width / 2)
            #expect(s.maxContentHeight >= 420)
        }
        #expect(DialogStyle.outer == 20)
        #expect(Int(DialogStyle.sectionSpacing) % 8 == 0 && Int(DialogStyle.itemSpacing) % 8 == 0)
    }

    @Test("Dialog surfaces are opaque in light and dark")
    func opaque() {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let ap = NSAppearance(named: name)!
            ap.performAsCurrentDrawingAppearance {
                for c in [NSColor.windowBackgroundColor, NSColor(DialogColors.sectionFill)] {
                    let rgb = c.usingColorSpace(.sRGB)
                    #expect(rgb?.alphaComponent == 1, "\(name.rawValue): \(c)")
                }
            }
        }
    }

    @Test("Report text splits into headings, bullets and paragraphs")
    func reportLines() {
        let lines = DialogReportText.lines("Checked 12 elements.\n\n3 warnings:\n• Wall 412 is not joined.\n- Room 9 is not enclosed.\n\n\nDone")
        #expect(lines == [.paragraph("Checked 12 elements."), .gap, .heading("3 warnings"), .bullet("Wall 412 is not joined."),
                          .bullet("Room 9 is not enclosed."), .gap, .paragraph("Done")])
        let (lead, rest) = ReportDialog.split("Checked 12 elements.\n\n3 warnings:\n• A")
        #expect(lead == "Checked 12 elements." && rest == "3 warnings:\n• A")
        #expect(ReportDialog.split("Warnings:\n• A").lead.isEmpty)
    }

    @Test("Errors read as sentences, not NSError dumps")
    func errorText() {
        let e = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [NSFilePathErrorKey: "/tmp/x.dwfx"])
        let t = DialogErrorText.describe(e)
        #expect(!t.contains("Error Domain") && !t.contains("UserInfo"))
        struct Custom: Error, CustomStringConvertible { var description: String { "The drawing has no layers." } }
        #expect(DialogErrorText.describe(Custom()) == "The drawing has no layers.")
    }

    @Test("Severity order is errors, warnings, info; health warnings map onto it")
    func severities() {
        #expect(DialogSeverity.allCases == [.error, .warning, .info])
        #expect(DialogSeverity(ModelWarning.Severity.error) == .error && DialogSeverity(ModelWarning.Severity.info) == .info)
        let tiles = DialogSummaryTiles.severities([.warning: 3])
        #expect(tiles.map(\.count) == [0, 3, 0])
    }

    @Test("Untitled dialogs get an icon from their title")
    func icons() {
        #expect(DialogIcons.symbol(for: "Export DWG") == "square.and.arrow.up")
        #expect(DialogIcons.symbol(for: "Import IFC") == "square.and.arrow.down")
        #expect(DialogIcons.symbol(for: "Something Else") == "macwindow")
    }

    @Test("The render catalog covers every DialogKind")
    func catalogCoversEveryKind() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../UI/Shell/DocumentState.swift").standardizedFileURL, encoding: .utf8)
        let body = try #require(source.range(of: "enum DialogKind").flatMap { r in source[r.upperBound...].range(of: "var id").map { source[r.upperBound..<$0.lowerBound] } })
        var kinds = Set<String>()
        for line in body.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("case ") else { continue }
            let decl = t.dropFirst(5).components(separatedBy: "//")[0]
            var depth = 0, current = ""
            for ch in decl {
                if ch == "(" { depth += 1 } else if ch == ")" { depth -= 1 }
                if ch == "," && depth == 0 { kinds.insert(current.trimmingCharacters(in: .whitespaces)); current = "" } else { current.append(ch) }
            }
            kinds.insert(current.trimmingCharacters(in: .whitespaces))
        }
        let names = Set(kinds.map { String($0.prefix { $0.isLetter || $0.isNumber }) }.filter { !$0.isEmpty })
        #expect(names.count > 50, "parsed \(names)")
        let s = DialogRenderTests.projectState()
        let f = DialogRenderTests.furnitureState()
        let catalog = QAHarness.dialogCatalog(project: s, furniture: f, fixtures: [:])
        let covered = Set(catalog.map { String(String(describing: $0.kind).prefix { $0.isLetter || $0.isNumber }) })
        let missing = names.subtracting(covered).subtracting(["exportDXF"]) // exportDXF has no dialog (EmptyView)
        #expect(missing.isEmpty, "Add these to QAHarness.dialogCatalog: \(missing.sorted())")
        #expect(catalog.filter(\.reviewed).count == 10)
    }
}
