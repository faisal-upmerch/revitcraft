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
        DialogFrame(title: "Select Title Block", subtitle: "The title block sets the sheet size.", state: state) {
            let sheet = sheetID, type = selected
            state.session.perform("Title Block") { tx in try SheetTitleBlocks.setTitleBlock(type, on: sheet, in: tx) }
            state.presented = nil
        } content: {
            List {
                ForEach(SheetTitleBlocks.types(m), id: \.id) { t in row(t.name + paper(t.id, m), family: t.typeData?.familyName ?? "", id: t.id, selected: selected) }
                row("None", family: "Plain border", id: nil, selected: selected)
            }
            .frame(minWidth: 380, minHeight: 240)
        }
    }

    func paper(_ id: ElementID, _ m: BIMModel) -> String {
        SheetTitleBlocks.paper(forTitleBlockType: id, m).map { "  (\($0.rawValue), \(Int(($0.landscapeSize.x * 1000).rounded())) × \(Int(($0.landscapeSize.y * 1000).rounded())) mm)" } ?? ""
    }

    func row(_ title: String, family: String, id: ElementID?, selected: ElementID?) -> some View {
        HStack {
            Image(systemName: id == selected ? "checkmark" : "").frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(family).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
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
        DialogFrame(title: "Assign Guide Grid", subtitle: "Viewports snap to the guide grid when they are moved.", state: state) {
            let spacing: Double? = show ? max(GuideGrids.spacingRange.lowerBound, min(GuideGrids.spacingRange.upperBound, spacingMM / 1000)) : nil
            let sheet = sheetID
            state.session.perform("Guide Grid") { tx in tx.update(sheet) { $0.sheet?.guideGridSpacing = spacing } }
            state.presented = nil
        } content: {
            Toggle("Show guide grid on this sheet", isOn: $show)
            FormRow(label: "Guide Spacing:") {
                TextField("", value: $spacingMM, format: .number.precision(.fractionLength(0...2))).frame(width: 80).disabled(!show)
                Text("mm").foregroundStyle(.secondary)
                Stepper("", value: $spacingMM, in: 5...200, step: 5).labelsHidden().disabled(!show)
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
        DialogFrame(title: "Rendering", subtitle: "Renders \(state.model[viewID]?.name ?? "the 3D view") on this Mac with realistic materials, sun and sky.", okTitle: "Done", showCancel: false, state: state) {
            state.presented = nil
        } content: {
            HStack(alignment: .top, spacing: 18) {
                Form {
                    Section("Quality") {
                        Picker("Setting:", selection: $s.quality) { ForEach(RenderEngine.Quality.allCases) { Text($0.rawValue).tag($0) } }
                    }
                    Section("Output Settings") {
                        Picker("Resolution:", selection: $s.printer) { Text("Screen").tag(false); Text("Printer").tag(true) }.pickerStyle(.radioGroup)
                        Picker("DPI:", selection: $s.dpi) { ForEach(RenderEngine.dpiChoices, id: \.self) { Text("\($0) DPI").tag($0) } }.disabled(!s.printer)
                        Text("Width: \(size.width) pixels    Height: \(size.height) pixels").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Lighting") {
                        Picker("Scheme:", selection: $s.sun) { Text("Exterior: Sun and Sky").tag(true); Text("Exterior: Sky only").tag(false) }
                        Text(sunText).font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Background") {
                        Picker("Style:", selection: $s.sky) { Text("Sky").tag(true); Text("Plain").tag(false) }
                    }
                }
                .formStyle(.grouped)
                .frame(width: 330)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("Render") { render() }.keyboardShortcut("r", modifiers: [])
                        Spacer()
                        Button("Save to Project") { save() }.disabled(image == nil || saved)
                        Button("Export…") { export() }.disabled(image == nil)
                    }
                    Group {
                        if let image {
                            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08))
                                Text(host == nil ? "Open the 3D view to render it." : "Choose Render.").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 420, height: 300)
                }
            }
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
        DialogFrame(title: "Render Gallery", subtitle: "Renderings saved in this project.", okTitle: "Done", showCancel: false, state: state) {
            state.presented = nil
        } content: {
            if renders.isEmpty {
                Text("No renderings yet. Use View ▸ Render (RR) in a 3D view, then Save to Project.")
                    .foregroundStyle(.secondary).frame(minWidth: 520, minHeight: 120)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(renders, id: \.id) { e in row(e) }
                    }
                }
                .frame(minWidth: 620, minHeight: 360)
            }
        }
    }

    @ViewBuilder func row(_ e: Element) -> some View {
        if let r = e.rendering {
            HStack(alignment: .top, spacing: 12) {
                if let img = NSImage(data: r.png) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 180, height: 120).background(Color.secondary.opacity(0.06))
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
                }
            }
            Divider()
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
