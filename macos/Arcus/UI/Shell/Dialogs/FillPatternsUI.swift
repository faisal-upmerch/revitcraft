import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// W4-HATCH: fill pattern previews, the searchable pattern picker (materials, type properties, V/G and element
// overrides) and Manage ▸ Additional Settings ▸ Fill Patterns (new, edit, duplicate, delete, import, add standard).

/// Small images of a fill pattern drawn with the same line generator the canvas and PDF use. Drafting patterns are
/// shown at 2.4 pt per paper millimetre; model patterns are fitted so about three repeats show.
@MainActor
enum FillPatternSwatch {
    private static var cache: [String: NSImage] = [:]

    static func image(_ d: FillPatternData?, width: CGFloat = 64, height: CGFloat = 28, color: RGBColor = .black) -> NSImage {
        let key = "\(d.map { "\($0.hashValue)" } ?? "nil")-\(width)x\(height)-\(color.hexString)"
        if let hit = cache[key] { return hit }
        let img = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let ink = NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1).cgColor
            ctx.setFillColor(NSColor.textBackgroundColor.cgColor)
            ctx.fill(rect)
            guard let d else { return true }
            if d.isSolid { ctx.setFillColor(ink); ctx.fill(rect.insetBy(dx: 1, dy: 1)); return true }
            guard let h = d.hatch, !h.isEmpty else {
                // Older pattern without line families: a label of its kind.
                let s = NSAttributedString(string: d.kind.rawValue, attributes: [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.secondaryLabelColor])
                s.draw(at: CGPoint(x: 3, y: rect.midY - 5))
                return true
            }
            let ptPerMM: Double
            if h.isModel {
                let largest = h.families.map { max($0.spacing, $0.period) }.max() ?? 100
                ptPerMM = Double(width) / (3.2 * largest)
            } else {
                ptPerMM = 2.4
            }
            let preview = HatchPattern(families: h.families, isModel: false)
            let poly = Polygon2([Vec2(1, 1), Vec2(Double(width) - 1, 1), Vec2(Double(width) - 1, Double(height) - 1), Vec2(1, Double(height) - 1)])
            guard let lines = HatchGenerator.generate([poly], preview, scale: Int((ptPerMM * 1000).rounded()), budget: 20_000) else {
                ctx.setFillColor(NSColor.quaternaryLabelColor.cgColor); ctx.fill(rect.insetBy(dx: 1, dy: 1)); return true
            }
            ctx.setStrokeColor(ink); ctx.setFillColor(ink)
            ctx.setLineWidth(0.8); ctx.setLineCap(.round)
            for s in lines.segments { ctx.move(to: CGPoint(x: s.start.x, y: s.start.y)); ctx.addLine(to: CGPoint(x: s.end.x, y: s.end.y)) }
            ctx.strokePath()
            for p in lines.dots { ctx.fillEllipse(in: CGRect(x: p.x - 0.7, y: p.y - 0.7, width: 1.4, height: 1.4)) }
            ctx.setStrokeColor(NSColor.separatorColor.cgColor); ctx.setLineWidth(1); ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
            return true
        }
        cache[key] = img
        return img
    }
}

/// A button showing the chosen pattern's swatch and name; the popover lists the project's patterns with search.
struct FillPatternMenu: View {
    let state: DocumentState
    @Binding var selection: ElementID?
    var noneLabel = "<None>"
    /// Limits the list (e.g. to drafting patterns for cut fills). nil shows every pattern.
    var filter: ((FillPatternData) -> Bool)? = nil
    @State private var showing = false
    @State private var search = ""

    var body: some View {
        let current = selection.flatMap { state.model[$0] }
        Button { showing.toggle() } label: {
            HStack(spacing: 6) {
                if let d = current?.fillPattern { Image(nsImage: FillPatternSwatch.image(d, width: 40, height: 14)) }
                Text(current?.name ?? noneLabel).font(.system(size: 11)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fill Pattern")
        .accessibilityValue(current?.name ?? noneLabel)
        .popover(isPresented: $showing, arrowEdge: .bottom) { list }
    }

    var patterns: [Element] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return FillPatternEdits.sorted(state.model).filter { e in
            guard let d = e.fillPattern else { return false }
            if let filter, !filter(d) { return false }
            return q.isEmpty || e.name.lowercased().contains(q) || (d.description ?? "").lowercased().contains(q) || d.typeName.lowercased() == q
        }
    }

    var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search patterns", text: $search).textFieldStyle(.roundedBorder).accessibilityLabel("Search fill patterns")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    row(nil, name: noneLabel, type: "")
                    ForEach(patterns, id: \.id) { e in row(e.id, name: e.name, type: e.fillPattern?.typeName ?? "", data: e.fillPattern) }
                }
            }
            .frame(width: 320, height: 300)
            HStack {
                Button("Fill Patterns…") { showing = false; state.presented = .additionalSettings(.fillPatterns) }.controlSize(.small)
                Spacer()
                Text("\(patterns.count) patterns").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }

    func row(_ id: ElementID?, name: String, type: String, data: FillPatternData? = nil) -> some View {
        Button { selection = id; showing = false } label: {
            HStack(spacing: 8) {
                Image(nsImage: FillPatternSwatch.image(data, width: 56, height: 20))
                Text(name).font(.system(size: 12)).lineLimit(1)
                Spacer()
                Text(type).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 4).fill(id == selection ? Color.accentColor.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Manage ▸ Additional Settings ▸ Fill Patterns.
struct FillPatternsSettingsView: View {
    let state: DocumentState
    enum Filter: String, CaseIterable, Identifiable { case all = "All", drafting = "Drafting", model = "Model"; var id: String { rawValue } }
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var selected: ElementID?
    @State private var editor: FillPatternEditor.Mode?
    @State private var message: String?
    @State private var isError = false

    var patterns: [Element] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return FillPatternEdits.sorted(state.model).filter { e in
            guard let d = e.fillPattern else { return false }
            switch filter { case .all: break; case .drafting: if d.isModelPattern { return false }; case .model: if !d.isModelPattern { return false } }
            return q.isEmpty || e.name.lowercased().contains(q) || (d.description ?? "").lowercased().contains(q)
        }
    }

    private func run(_ name: String, _ body: @escaping (TransactionContext) throws -> Void) {
        state.session.perform(name, body)
        if let e = state.session.lastError { message = e.message; isError = true; state.session.clearError() } else { message = nil; isError = false }
    }

    var body: some View {
        let _ = state.session.changeCounter
        let list = patterns
        let sel = selected.flatMap { state.model[$0] }
        let missing = FillPatternLibrary.missing(state.model).count
        VStack(alignment: .leading, spacing: 8) {
            Text("Drafting patterns are sized on paper (the same at every scale); model patterns are real-world sizes that scale with the view. Materials, filled regions, Coarse Scale Fills and view overrides pick from this list.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                PillSegmented(selection: $filter, Filter.allCases.map { ($0, $0.rawValue) }).frame(width: 220) // PILLS
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
                Spacer()
                Text("\(list.count) of \(state.model.elements(.fillPatterns).count)").font(.caption).foregroundStyle(.secondary)
            }
            Table(list, selection: $selected) {
                TableColumn("Pattern") { e in
                    HStack(spacing: 8) {
                        Image(nsImage: FillPatternSwatch.image(e.fillPattern, width: 72, height: 24))
                        Text(e.name)
                    }
                }.width(min: 220)
                TableColumn("Type") { e in Text(e.fillPattern?.typeName ?? "") }.width(70)
                TableColumn("Definition") { e in Text(Self.summary(e.fillPattern)).foregroundStyle(.secondary).lineLimit(1) }.width(min: 180)
                TableColumn("Used") { e in Text("\(FillPatternEdits.users(of: e.id, state.model).count)").foregroundStyle(.secondary) }.width(44)
            }
            .contextMenu(forSelectionType: ElementID.self) { ids in
                if let id = ids.first { Button("Edit…") { edit(id) }; Button("Duplicate") { duplicate(id) }; Button("Delete") { delete(id) } }
            } primaryAction: { ids in if let id = ids.first { edit(id) } }
            .frame(minHeight: 300)
            if let message { Text(message).font(.callout).foregroundStyle(isError ? .red : .secondary) }
            HStack {
                Button("New…") { editor = .new }
                Button("Edit…") { if let id = selected { edit(id) } }.disabled(sel?.fillPattern?.isSolid ?? true)
                Button("Duplicate") { if let id = selected { duplicate(id) } }.disabled(sel == nil)
                Button("Delete") { if let id = selected { delete(id) } }.disabled(sel?.fillPattern?.isSolid ?? true)
                    .help("Materials, regions and overrides using a deleted pattern fall back to their category default.")
                Divider().frame(height: 16)
                Button("Import…") { importPatterns() }.help("Import line-family patterns from a text file (Arcus .pat-style format, see Docs/FillPatternFormat.md).")
                Button("Export…") { exportPatterns(list) }.disabled(list.isEmpty).help("Write the listed patterns to a text file.")
                Spacer()
                if missing > 0 {
                    Button("Add Standard Patterns (\(missing))") { run("Add Standard Fill Patterns") { tx in FillPatternLibrary.ensureStandard(in: tx) } }
                        .help("Adds the standard patterns this project doesn't have yet.")
                }
            }
        }
        .sheet(item: $editor) { mode in FillPatternEditor(state: state, mode: mode) { editor = nil }.opaqueDialogBackground() } // DIALOGS
    }

    static func summary(_ d: FillPatternData?) -> String {
        guard let d else { return "" }
        if d.isSolid { return "Solid" }
        guard let fams = d.families, !fams.isEmpty else { return "\(d.kind.rawValue) (procedural)" }
        let n = fams.count
        let spacing = fams.map(\.spacing).min() ?? 0
        let angles = Array(Set(fams.map { Int(Self.normalizeDegreesUI($0.angle).rounded()) })).sorted().map { "\($0)°" }.joined(separator: "/")
        let unit = d.isModelPattern ? "mm" : "mm paper"
        return "\(n) line famil\(n == 1 ? "y" : "ies"), \(angles), \(FillPatternText.formatNumber(spacing)) \(unit)" + (fams.contains { !$0.dashes.isEmpty } ? ", dashed" : "")
    }

    func edit(_ id: ElementID) { if let e = state.model[id], e.fillPattern?.isSolid == false { editor = .edit(id) } }
    func duplicate(_ id: ElementID) {
        run("Duplicate Fill Pattern") { tx in _ = try FillPatternEdits.duplicate(id, in: tx) }
        if let e = state.model.elements(.fillPatterns).max(by: { $0.id < $1.id }) { selected = e.id }
    }
    func delete(_ id: ElementID) {
        let n = FillPatternEdits.users(of: id, state.model).count
        run("Delete Fill Pattern") { tx in try FillPatternEdits.delete(id, in: tx) }
        if !isError { selected = nil; if n > 0 { message = "Deleted; \(n) material\(n == 1 ? "" : "s")/type\(n == 1 ? "" : "s")/view\(n == 1 ? "" : "s") now use the category default."; isError = false } }
    }

    func importPatterns() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.plainText, UTType(filenameExtension: "pat") ?? .plainText, .text]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a fill pattern text file (*Name header lines, then angle, x, y, shift, spacing, dashes… per line family)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let entries = try FillPatternText.parse(text)
            var count = 0
            run("Import Fill Patterns") { tx in count = try FillPatternEdits.importEntries(entries, in: tx).count }
            if !isError { message = "Imported \(count) pattern\(count == 1 ? "" : "s") from \(url.lastPathComponent)."; isError = false }
        } catch {
            message = "Import failed: \(error)"; isError = true
        }
    }

    func exportPatterns(_ list: [Element]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pat") ?? .plainText]
        panel.nameFieldStringValue = "Fill Patterns.pat"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let entries = list.compactMap { e -> FillPatternText.Entry? in
            guard let d = e.fillPattern, let f = d.families, !f.isEmpty else { return nil }
            return FillPatternText.Entry(name: e.name, description: d.description ?? "", isModel: d.isModelPattern, families: f)
        }
        do { try FillPatternText.format(entries).write(to: url, atomically: true, encoding: .utf8); message = "Exported \(entries.count) patterns."; isError = false }
        catch { message = "Export failed: \(error.localizedDescription)"; isError = true }
    }
}

/// New / Edit Fill Pattern: name, type, the line families as text (one per line) with a live preview.
struct FillPatternEditor: View {
    enum Mode: Identifiable, Hashable { case new, edit(ElementID); var id: String { switch self { case .new: "new"; case .edit(let e): "\(e.raw)" } } }
    let state: DocumentState
    let mode: Mode
    let dismiss: () -> Void
    @State private var name = ""
    @State private var isModel = false
    @State private var description = ""
    @State private var text = "45, 0, 0, 0, 3"
    @State private var error: String?

    var parsed: Result<[HatchFamily], FillPatternText.ParseError> {
        do { return .success(try FillPatternText.parse("*preview\n" + text).first?.families ?? []) } catch { return .failure(error) }
    }

    var body: some View {
        let fams = (try? parsed.get()) ?? []
        let preview = FillPatternData(kind: FillPatternText.closestKind(fams), isModelPattern: isModel, spacing: fams.first?.spacing ?? 2)
        ArcusDialog(icon: "square.grid.3x3.fill.square", tint: .indigo, title: mode == .new ? "New Fill Pattern" : "Edit Fill Pattern", subtitle: "Line families drawn as a hatch.",
                    size: .large, labelWidth: 100, okDisabled: fams.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty,
                    disabledReason: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter a name" : "Add at least one valid line family",
                    onCancel: { dismiss() }, onOK: { commit(fams) }) { // DIALOGS
            DialogSection {
                DialogRow("Name") { TextField("", text: $name).labelsHidden().accessibilityLabel("Pattern name") }
                DialogRow("Type") {
                    Picker("", selection: $isModel) { Text("Drafting (paper mm, same at every scale)").tag(false); Text("Model (real-world mm, scales with the view)").tag(true) }
                        .labelsHidden().fixedSize()
                }
                DialogRow("Description") { TextField("Optional", text: $description).labelsHidden() }
            }
            HStack(alignment: .top, spacing: DialogStyle.sectionSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Line families").font(DialogStyle.sectionTitle).foregroundStyle(.secondary).padding(.leading, 4)
                    TextEditor(text: $text).font(.system(size: 12).monospaced()).frame(height: 160)
                        .scrollContentBackground(.hidden).padding(6)
                        .background(DialogColors.sectionFill, in: RoundedRectangle(cornerRadius: Tokens.radiusSection))
                        .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
                        .accessibilityLabel("Line families")
                    DialogCaption("One per line: angle°, origin x, origin y, shift, spacing, dashes… (mm; dash > 0 pen down, < 0 gap, 0 dot)").padding(.horizontal, 4)
                    HStack {
                        Button("Add Line Family") { text += (text.hasSuffix("\n") || text.isEmpty ? "" : "\n") + "135, 0, 0, 0, 3" }.controlSize(.small)
                        Menu("Start From…") {
                            ForEach(isModel ? FillPatternLibrary.model : FillPatternLibrary.drafting) { p in
                                Button(p.name) { text = p.families.map(FillPatternText.formatFamily).joined(separator: "\n") }
                            }
                        }.controlSize(.small).fixedSize()
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview").font(DialogStyle.sectionTitle).foregroundStyle(.secondary).padding(.leading, 4)
                    Image(nsImage: FillPatternSwatch.image(withFamilies(preview, fams), width: 220, height: 160))
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
                        .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
                    if case .failure(let e) = parsed { Label(String(describing: e), systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.red).frame(width: 220, alignment: .leading) }
                    else { DialogCaption("\(fams.count) line famil\(fams.count == 1 ? "y" : "ies")").padding(.horizontal, 4) }
                }
                .frame(width: 220)
            }
            if let error { DialogNotice(.error, error) }
        }
        .onAppear(perform: load)
    }

    func withFamilies(_ d: FillPatternData, _ f: [HatchFamily]) -> FillPatternData { var c = d; c.families = f; return c }

    func load() {
        guard case .edit(let id) = mode, let e = state.model[id], let d = e.fillPattern else { name = ""; return }
        name = e.name; isModel = d.isModelPattern; description = d.description ?? ""
        text = (d.families ?? FillPatternLibrary.named(e.name)?.families ?? []).map(FillPatternText.formatFamily).joined(separator: "\n")
    }

    func commit(_ fams: [HatchFamily]) {
        let n = name, m = isModel, desc = description
        switch mode {
        case .new: state.session.perform("New Fill Pattern") { tx in _ = try FillPatternEdits.create(name: n, isModel: m, families: fams, description: desc, in: tx) }
        case .edit(let id): state.session.perform("Edit Fill Pattern") { tx in try FillPatternEdits.edit(id, name: n, isModel: m, families: fams, description: desc, in: tx) }
        }
        if let e = state.session.lastError { error = e.message; state.session.clearError(); return }
        dismiss()
    }
}

extension FillPatternsSettingsView {
    static func normalizeDegreesUI(_ a: Double) -> Double { var d = a.truncatingRemainder(dividingBy: 180); if d < 0 { d += 180 }; return d }
}

extension FillPatternText {
    static func formatNumber(_ v: Double) -> String { formatFamily(HatchFamily(angle: 0, spacing: v)).split(separator: ",").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "\(v)" }
}
