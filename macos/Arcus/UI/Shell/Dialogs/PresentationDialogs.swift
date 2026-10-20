import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusDomain
import ArcusApplication

// F810: View ▸ Sheet Composition ▸ Title Block and Guide Grid, View ▸ Presentation ▸ Render and Render Gallery, with
// the settings RevitCraft has (crates/rc-app/src/dialogs/manage.rs title_block/guide_grid, dialogs/mod.rs
// render_dialog, dialogs/insert.rs gallery_dialog).

enum F810Dialog: Equatable {
    case titleBlock(ElementID), guideGrid(ElementID), render(ElementID), renderGallery
}

struct F810DialogHost: View {
    let state: DocumentState
    let dialog: F810Dialog
    var body: some View {
        switch dialog {
        case .titleBlock(let s): SelectTitleBlockDialog(state: state, sheetID: s)
        case .guideGrid(let s): GuideGridDialog(state: state, sheetID: s)
        case .render(let v): RenderingDialog(state: state, viewID: v)
        case .renderGallery: RenderGalleryDialog(state: state)
        }
    }
}

// MARK: - Title Block

/// Select Title Block: the title block types (with their paper) and None; OK changes the sheet's title block and size.
struct SelectTitleBlockDialog: View {
    let state: DocumentState
    let sheetID: ElementID
    /// nil selects "None"; the outer optional is "not chosen yet" (the sheet's current title block).
    @State private var choice: ElementID??

    var body: some View {
        let m = state.model
        let current = m[sheetID]?.sheet?.titleBlockTypeID
        let selected = choice ?? current
        let types = SheetTitleBlocks.types(m)
        DialogFrame(title: "Select Title Block", icon: "doc.richtext", tint: .blue, subtitle: "The title block sets the sheet size.", state: state) {
            let sheet = sheetID, type = selected
            state.session.perform("Title Block") { tx in try SheetTitleBlocks.setTitleBlock(type, on: sheet, in: tx) }
            state.presented = nil
        } content: {
            DialogListBox(count: types.count + 1, rowHeight: 42, minRows: 2, maxRows: 7) {
                List {
                    ForEach(types, id: \.id) { t in row(t.name, detail: paper(t.id, m), family: t.typeData?.familyName ?? "", id: t.id, selected: selected) }
                    row("None", detail: "", family: "Plain border", id: nil, selected: selected)
                }
            }
        }
    }

    func paper(_ id: ElementID, _ m: BIMModel) -> String {
        SheetTitleBlocks.paper(forTitleBlockType: id, m).map { "\($0.rawValue) · \(Int(($0.landscapeSize.x * 1000).rounded())) × \(Int(($0.landscapeSize.y * 1000).rounded())) mm" } ?? ""
    }

    func row(_ title: String, detail: String, family: String, id: ElementID?, selected: ElementID?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: id == selected ? "checkmark.circle.fill" : "circle").foregroundStyle(id == selected ? Color.accentColor : Color.secondary.opacity(0.5)).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(family).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(detail).foregroundStyle(.secondary).monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture { choice = .some(id) }
        .accessibilityAddTraits(id == selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Guide Grid

/// Assign Guide Grid: show a guide grid on this sheet and its spacing (5–200 mm on paper).
struct GuideGridDialog: View {
    let state: DocumentState
    let sheetID: ElementID
    @State private var show = false
    @State private var spacingMM = 25.0
    @State private var loaded = false

    var body: some View {
        DialogFrame(title: "Assign Guide Grid", icon: "grid", tint: .blue, size: .small, subtitle: "Viewports snap to the guide grid when moved.", state: state) {
            let spacing: Double? = show ? max(GuideGrids.spacingRange.lowerBound, min(GuideGrids.spacingRange.upperBound, spacingMM / 1000)) : nil
            let sheet = sheetID
            state.session.perform("Guide Grid") { tx in tx.update(sheet) { $0.sheet?.guideGridSpacing = spacing } }
            state.presented = nil
        } content: {
            DialogSection {
                Toggle("Show guide grid on this sheet", isOn: $show)
                DialogRow("Guide spacing") {
                    HStack(spacing: 6) {
                        TextField("", value: $spacingMM, format: .number.precision(.fractionLength(0...2))).labelsHidden().frame(width: 80).disabled(!show)
                        Stepper("", value: $spacingMM, in: 5...200, step: 5).labelsHidden().disabled(!show)
                        Text("mm on paper").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let g = state.model[sheetID]?.sheet?.guideGridSpacing
            show = g != nil
            spacingMM = (g ?? 0.025) * 1000
        }
    }
}

// MARK: - Rendering

/// Rendering: quality, output resolution, lighting and background; Render shows the image, which can be saved to the
/// project (Render Gallery) or exported as PNG.
struct RenderingDialog: View {
    let state: DocumentState
    let viewID: ElementID
    @State private var s = RenderEngine.Settings()
    @State private var image: CGImage?
    @State private var saved = false

    var host: Viewport3DHost? { state.canvases[viewID] as? Viewport3DHost }

    var body: some View {
        let size = RenderEngine.size(s, aspect: host.map(RenderEngine.aspect) ?? 0.625)
        DialogFrameWithActions(title: "Rendering", icon: "camera.aperture", tint: .orange, size: .wide, subtitle: "\(state.model[viewID]?.name ?? "The 3D view") with realistic materials, sun and sky.",
                               okTitle: "Done", showCancel: false, labelWidth: 90, state: state) {
            state.presented = nil
        } content: {
            HStack(alignment: .top, spacing: DialogStyle.sectionSpacing) {
                VStack(alignment: .leading, spacing: DialogStyle.sectionSpacing) {
                    DialogSection("Quality") {
                        DialogRow("Setting") { Picker("", selection: $s.quality) { ForEach(RenderEngine.Quality.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden() }
                    }
                    DialogSection("Output", footnote: "\(size.width) × \(size.height) pixels") {
                        DialogRow("Resolution") { PillSegmented(selection: $s.printer, [(false, "Screen"), (true, "Printer")]) } // PILLS
                        DialogRow("DPI") { Picker("", selection: $s.dpi) { ForEach(RenderEngine.dpiChoices, id: \.self) { Text("\($0) DPI").tag($0) } }.labelsHidden().disabled(!s.printer) }
                    }
                    DialogSection("Lighting", footnote: sunText) {
                        DialogRow("Scheme") { Picker("", selection: $s.sun) { Text("Sun and shadows").tag(true); Text("Sun, no shadows").tag(false) }.labelsHidden() }
                    }
                    DialogSection("Background") {
                        DialogRow("Style") { PillSegmented(selection: $s.sky, [(true, "Sky"), (false, "Plain")]) } // PILLS
                    }
                }
                .frame(width: 320)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Image").font(DialogStyle.sectionTitle).foregroundStyle(.secondary).padding(.leading, 4)
                    Group {
                        if let image {
                            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            DialogEmptyState(icon: "camera.aperture", title: host == nil ? "Open the 3D view to render it" : "Not rendered yet",
                                             message: host == nil ? "" : "Choose Render to make the image.", actionTitle: host == nil ? nil : "Render", action: host == nil ? nil : { render() })
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 360)
                    .background(DialogColors.sectionFill, in: RoundedRectangle(cornerRadius: Tokens.radiusSection))
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
                }
            }
        } actions: {
            Button("Render") { render() }.disabled(host == nil)
            Button("Save to Project") { save() }.disabled(image == nil || saved)
            Button("Export…") { export() }.disabled(image == nil)
        }
        .onChange(of: s) { _, _ in saved = false }
    }

    var sunText: String {
        guard let sun = state.model[viewID]?.view?.displayOptions.sun else { return "" }
        return "Sun Setting: \(sun.mode.rawValue), azimuth \(Int(sun.azimuth.rounded()))°, altitude \(Int(sun.altitude.rounded()))° (the view's Sun Settings)."
    }

    func render() {
        guard let host else { state.show("Open the 3D view to render it.", error: true); return }
        guard let img = RenderEngine.render(host, s) else { state.show("The view could not be rendered.", error: true); return }
        image = img
        saved = false
    }

    func save() {
        guard let image, let png = RenderEngine.png(image) else { return }
        let base = state.model[viewID]?.name ?? "Rendering"
        let r = RenderingData(png: png, width: image.width, height: image.height, viewID: viewID, quality: s.quality.rawValue, sunLighting: s.sun, skyBackground: s.sky)
        var name = ""
        state.session.perform("Save Rendering to Project") { tx in
            name = Renderings.nextName(for: base, tx.model)
            try Renderings.save(r, name: name, tx)
        }
        if state.session.lastError == nil {
            saved = true
            state.show("Saved “\(name)” to the project. View ▸ Render Gallery lists it.")
        }
    }

    func export() {
        guard let image else { return }
        RenderGalleryDialog.exportPNG(image: image, png: nil, name: state.model[viewID]?.name ?? "Rendering", state: state)
    }
}

// MARK: - Render Gallery

/// Render Gallery: the renderings saved in the project, to export as PNG or delete.
struct RenderGalleryDialog: View {
    let state: DocumentState

    var body: some View {
        let renders = Renderings.all(state.model)
        DialogFrame(title: "Render Gallery", icon: "photo.stack", tint: .orange, size: renders.isEmpty ? .medium : .large, subtitle: "Renderings saved in this project.",
                    okTitle: "Done", showCancel: false, scrolls: !renders.isEmpty, state: state) {
            state.presented = nil
        } content: {
            if renders.isEmpty {
                DialogSection(rows: false) {
                    DialogEmptyState(icon: "photo.stack", title: "No renderings yet", message: "Use View ▸ Render (RR) in a 3D view, then Save to Project.").padding(24)
                }
            } else {
                DialogSection {
                    ForEach(renders, id: \.id) { e in row(e) }
                }
            }
        }
    }

    @ViewBuilder func row(_ e: Element) -> some View {
        if let r = e.rendering {
            HStack(alignment: .top, spacing: 12) {
                if let img = NSImage(data: r.png) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 180, height: 120)
                        .background(Color.secondary.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.name).font(.headline)
                    Text("Still Image · \(r.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    Text("\(r.width) × \(r.height) pixels · \(r.quality)\(r.viewID.flatMap { state.model[$0]?.name }.map { " · \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Export as PNG…") { Self.exportPNG(image: nil, png: r.png, name: e.name, state: state) }
                        Button("Delete", role: .destructive) { state.session.delete([e.id]) }
                    }
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
        }
    }

    /// Saves a rendering as a PNG file chosen in a save panel.
    static func exportPNG(image: CGImage?, png: Data?, name: String, state: DocumentState) {
        guard let data = png ?? image.flatMap(RenderEngine.png) else { state.show("The rendering couldn't be encoded.", error: true); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(name).png"
        let done: (NSApplication.ModalResponse) -> Void = { r in
            guard r == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic); state.show("Exported \(url.lastPathComponent).") }
            catch { state.show("Export failed: \(error.localizedDescription)", error: true) }
        }
        if let w = NSApp.keyWindow ?? state.window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }
}
