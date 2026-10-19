import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication

// W2-ANNOT: Manage ▸ Line Styles (standard and user styles: weight, colour, pattern; new, rename, delete with undo)
// and line style pickers with pattern previews for the Options Bar and Properties.

/// Small images of a line style: its pattern, weight and colour, as the style draws on paper (dashes enlarged a
/// little so short patterns stay readable at menu size).
@MainActor
enum LineStyleSwatch {
    private static var cache: [String: NSImage] = [:]

    static func image(_ s: LineStyleData, width: CGFloat = 46, height: CGFloat = 12) -> NSImage {
        let key = "\(s.weight)-\(s.color.hexString)-\(s.pattern.rawValue)-\(width)"
        if let hit = cache[key] { return hit }
        let img = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let mmToPt: CGFloat = 2.2
            let pen = max(0.8, min(4, CGFloat(LineWeights.paperWidth(s.weight, scale: 100)) * mmToPt * 1.6))
            ctx.setStrokeColor(NSColor(srgbRed: s.color.r, green: s.color.g, blue: s.color.b, alpha: 1).cgColor)
            ctx.setLineWidth(pen)
            ctx.setLineCap(.round)
            let dashes = s.pattern.dashPattern.map { CGFloat($0) * mmToPt }
            ctx.setLineDash(phase: 0, lengths: dashes)
            ctx.move(to: CGPoint(x: 2, y: rect.midY))
            ctx.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
            ctx.strokePath()
            return true
        }
        img.isTemplate = false
        cache[key] = img
        return img
    }
}

/// A menu of line styles with pattern previews. `selection` is the style name (Options Bar) or id (Properties).
struct LineStyleMenu: View {
    let styles: [(name: String, data: LineStyleData)]
    let current: String
    let placeholder: String
    let choose: (String) -> Void

    var body: some View {
        Menu {
            ForEach(styles, id: \.name) { s in
                Button { choose(s.name) } label: {
                    Label { Text(s.name) } icon: { Image(nsImage: LineStyleSwatch.image(s.data)) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let d = styles.first(where: { $0.name == current })?.data { Image(nsImage: LineStyleSwatch.image(d, width: 34)) }
                Text(current.isEmpty ? placeholder : current).font(.system(size: 11))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Line Style")
        .accessibilityValue(current)
    }

    /// The model's styles in display order.
    static func styles(_ model: BIMModel) -> [(name: String, data: LineStyleData)] {
        LineStyles.sorted(model).compactMap { e in e.lineStyle.map { (e.name, $0) } }
    }
}

struct LineStylesDialog: View {
    let state: DocumentState
    @State private var selected: ElementID?
    @State private var renaming: ElementID?
    @State private var newName = ""
    @State private var error: String?

    private func run(_ name: String, _ body: @escaping (TransactionContext) throws -> Void) {
        state.session.perform(name, body)
        if let e = state.session.lastError { error = e.message; state.session.clearError() } else { error = nil }
    }

    var body: some View {
        let _ = state.session.changeCounter
        let styles = LineStyles.sorted(state.model)
        let missing = LineStyles.standard.contains { s in !styles.contains { $0.name == s.name } }
        DialogFrameWithActions(title: "Line Styles", icon: "line.3.horizontal", tint: .indigo, size: .large, subtitle: "Standard styles can be edited; your own can also be renamed and deleted.",
                    okTitle: "Done", showCancel: false, state: state) { state.presented = nil } content: {
            DialogListBox(count: styles.count, rowHeight: 30, minRows: 8, maxRows: 12) {
            Table(styles, selection: $selected) {
                TableColumn("Name") { e in
                    if renaming == e.id {
                        TextField("Name", text: $newName)
                            .onSubmit { let id = e.id, n = newName; run("Rename Line Style") { tx in try LineStyles.rename(id, to: n, in: tx) }; renaming = nil }
                    } else {
                        HStack(spacing: 6) {
                            Image(nsImage: LineStyleSwatch.image(e.lineStyle ?? LineStyleData(weight: 1), width: 34))
                            Text(e.name).foregroundStyle(LineStyles.isStandard(e.name) ? .secondary : .primary)
                        }
                    }
                }
                TableColumn("Weight") { e in
                    Picker("", selection: Binding(get: { e.lineStyle?.weight ?? 1 }, set: { v in run("Line Weight") { tx in try LineStyles.edit(e.id, weight: v, in: tx) } })) {
                        ForEach(1...16, id: \.self) { Text("\($0)").tag($0) }
                    }.labelsHidden()
                }.width(70)
                TableColumn("Color") { e in
                    ColorPicker("", selection: Binding(get: { (e.lineStyle?.color ?? .black).color },
                                                       set: { c in run("Line Color") { tx in try LineStyles.edit(e.id, color: RGBColor.from(NSColor(c)), in: tx) } }))
                        .labelsHidden()
                }.width(56)
                TableColumn("Pattern") { e in
                    Picker("", selection: Binding(get: { e.lineStyle?.pattern ?? .solid }, set: { v in run("Line Pattern") { tx in try LineStyles.edit(e.id, pattern: v, in: tx) } })) {
                        ForEach(LinePatternKind.allCases, id: \.self) { k in
                            Label { Text(k.rawValue) } icon: { Image(nsImage: LineStyleSwatch.image(LineStyleData(weight: 1, pattern: k))) }.tag(k)
                        }
                    }.labelsHidden()
                }.width(150)
                TableColumn("Lines") { e in Text("\(LineStyles.users(of: e.id, state.model).count)").foregroundStyle(.secondary) }.width(44)
            }
            }
            if let error { DialogNotice(.error, error) }
        } actions: {
                Button("New…") {
                    var n = 1
                    while state.model.lineStyle(named: "Line Style \(n)") != nil { n += 1 }
                    let name = "Line Style \(n)"
                    run("New Line Style") { tx in try LineStyles.create(name: name, weight: 2, in: tx) }
                    if let id = state.model.lineStyle(named: name)?.id { selected = id; renaming = id; newName = name }
                }
                Button("Rename") {
                    guard let id = selected, let e = state.model[id] else { return }
                    renaming = id; newName = e.name
                }
                .disabled(selected.map { state.model[$0].map { LineStyles.isStandard($0.name) } ?? true } ?? true)
                Button("Delete") {
                    guard let id = selected else { return }
                    run("Delete Line Style") { tx in try LineStyles.delete(id, in: tx) }
                    selected = nil
                }
                .disabled(selected.map { state.model[$0].map { LineStyles.isStandard($0.name) } ?? true } ?? true)
                .help("Lines drawn with a deleted style change to Thin Lines.")
                if missing {
                    Button("Add Standard Styles") { run("Add Standard Line Styles") { tx in LineStyles.ensureStandard(in: tx) } }
                        .help("Adds the standard styles this project doesn't have yet (<Hidden>, Dashed, Property Line…).")
                }
        }
    }
}
