import SwiftUI
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-BROWSER: Sheet Title (number and name), Place View (type-prefixed, searchable, multi-select, cursor placement)
// and View Range (level selectors, offsets, diagram, Apply) dialogs.

/// Renames a sheet: its number and its name, validated together.
struct SheetTitleDialog: View {
    let state: DocumentState
    let sheetID: ElementID
    @State private var number = ""
    @State private var name = ""
    @FocusState private var focus: Field?
    enum Field { case number, name }

    var problem: String? { BrowserNaming.sheetTitleProblem(sheetID, number: number, name: name, in: state.model) }

    var body: some View {
        DialogFrame(title: "Sheet Title", icon: "doc.richtext", tint: .blue, size: .small, subtitle: "Number and name of the sheet.", okDisabled: problem != nil,
                    disabledReason: problem, labelWidth: 70, state: state) {
            guard problem == nil else { return }
            let n = BrowserNaming.normalized(number), nm = BrowserNaming.normalized(name), id = sheetID
            state.session.perform("Rename Sheet") { tx in tx.update(id) { $0.sheet?.number = n; $0.name = nm } }
            state.presented = nil
            state.updateWindowSubtitle()
        } content: {
            DialogSection {
                DialogRow("Number") {
                    TextField("A101", text: $number).labelsHidden().frame(width: 120).focused($focus, equals: .number)
                }
                DialogRow("Name") {
                    TextField("Name", text: $name).labelsHidden().focused($focus, equals: .name)
                }
            }
        }
        .onAppear {
            number = state.model[sheetID]?.sheet?.number ?? ""
            name = state.model[sheetID]?.name ?? ""
            focus = .name
        }
    }
}

/// Views: type-prefixed names ("Floor Plan: Level 1"), search, multi-select. Views already on a sheet are not
/// listed. "Add View to Sheet" attaches the viewports to the cursor; a click places them, Esc cancels.
struct PlaceViewDialog: View {
    let state: DocumentState
    let sheetID: ElementID
    @State private var search = ""
    @State private var chosen: Set<ElementID> = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        let m = state.model
        let candidates = PlaceViewCandidates.list(forSheet: sheetID, m, search: search)
        let hidden = m.views.filter { $0.view != nil && $0.view?.kind != .legend && !m.viewports(showing: $0.id).isEmpty }.count
        ArcusDialog(icon: "rectangle.on.rectangle", tint: .blue, title: "Views", subtitle: "Choose views, then place them with the pointer. You can also drag views from the Project Browser.",
                    okTitle: "Add View to Sheet", okDisabled: chosen.isEmpty, disabledReason: "Choose a view", onCancel: { state.presented = nil }, onOK: { place(chosen) }) {
            TextField("Search", text: $search).textFieldStyle(.roundedBorder).focused($searchFocused).accessibilityLabel("Search views")
            DialogSection(footnote: hidden > 0 ? "\(hidden) view\(hidden == 1 ? " is" : "s are") already on a sheet and not listed. Legends and schedules can go on several sheets." : nil, boxed: false) {
                DialogListBox(count: candidates.count, rowHeight: 28, minRows: 6, maxRows: 10, isEmpty: candidates.isEmpty) {
                    List(candidates, selection: $chosen) { c in
                        Label(c.title, systemImage: c.symbol).tag(c.id)
                    }
                    .contextMenu(forSelectionType: ElementID.self) { _ in } primaryAction: { ids in place(ids) }
                } empty: {
                    DialogEmptyState(icon: "rectangle.on.rectangle", title: search.isEmpty ? "No views to place" : "No matches", message: search.isEmpty ? "Every view is already on a sheet." : "")
                }
            }
        } leading: {
            if !chosen.isEmpty { Text("\(chosen.count) selected").font(.callout).foregroundStyle(.secondary) }
        }
        .onAppear { searchFocused = true }
    }

    /// Closes the dialog and attaches the chosen views (in list order) to the cursor.
    func place(_ ids: Set<ElementID>) {
        guard !ids.isEmpty else { return }
        let ordered = PlaceViewCandidates.list(forSheet: sheetID, state.model).map(\.id).filter(ids.contains)
        state.presented = nil
        let sheet = sheetID
        DispatchQueue.main.async { state.beginViewportPlacement(ordered, onSheet: sheet) }
    }
}

/// View Range: Top, Cut plane and Bottom of the primary range and the View Depth, each measured from a level
/// (Associated Level, Level Above/Below, Unlimited or a named level) plus an offset; a diagram; Apply keeps it open.
struct ViewRangeDialog: View {
    let state: DocumentState
    let viewID: ElementID
    @State private var levels: [ViewRange.Plane: ViewRangeLevel] = [:]
    @State private var offsets: [ViewRange.Plane: String] = [:]
    @State private var showDiagram = false
    @State private var problem: String?

    var m: BIMModel { state.model }
    var view: Element? { m[viewID] }
    var viewLevel: ElementID? { view?.levelID }
    var templateLock: String? {
        guard let t = view?.view?.templateID, let tmpl = m[t], tmpl.viewTemplate?.viewRange != nil else { return nil }
        return "The view template “\(tmpl.name)” controls this view's range. Remove the template in Properties to edit it here."
    }

    var body: some View {
        ArcusDialog(icon: "square.3.layers.3d.middle.filled", tint: .blue, title: "View Range", subtitle: view.map(ViewTitles.qualified) ?? "", size: showDiagram ? .large : .medium,
                    onCancel: { state.presented = nil }, onOK: { if templateLock != nil || apply() { state.presented = nil } }) {
            if let t = templateLock { DialogNotice(.info, t) }
            HStack(alignment: .top, spacing: DialogStyle.sectionSpacing) {
                VStack(alignment: .leading, spacing: DialogStyle.sectionSpacing) {
                    DialogSection("Primary range") { row(.top); row(.cut); row(.bottom) }
                    DialogSection("View depth") { row(.depth) }
                }
                .disabled(templateLock != nil)
                if showDiagram {
                    ViewRangeDiagram(model: m, viewLevel: viewLevel, range: draft ?? view?.view?.viewRange ?? .floorPlanDefault)
                        .frame(width: 200, height: 250)
                        .accessibilityLabel("View range diagram")
                }
            }
            if let problem { DialogNotice(.error, problem) }
        } leading: {
            Button(showDiagram ? "Hide Diagram" : "Show Diagram") { showDiagram.toggle() }
                .help("Show or hide the view range diagram")
        } trailing: {
            Button("Apply") { _ = apply() }.disabled(templateLock != nil).dialogButton()
        }
        .onAppear(perform: load)
        .onChange(of: levels) { _, _ in problem = draftProblem }
        .onChange(of: offsets) { _, _ in problem = draftProblem }
    }

    @ViewBuilder func row(_ p: ViewRange.Plane) -> some View {
        let choice = levels[p] ?? .associated
        HStack(spacing: 8) {
            Text(p.rawValue).frame(width: 70, alignment: .leading)
            Picker("", selection: Binding(get: { choice }, set: { levels[p] = $0 })) {
                ForEach(ViewRange.choices(for: p, m), id: \.self) { c in Text(c.title(m)).tag(c) }
            }
            .labelsHidden().frame(width: 170)
            .disabled(p == .cut)
            .accessibilityLabel("\(p.rawValue) level")
            Text("Offset").foregroundStyle(.secondary)
            TextField("", text: Binding(get: { offsets[p] ?? "" }, set: { offsets[p] = $0 }))
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 100)
                .disabled(choice == .unlimited)
                .accessibilityLabel("\(p.rawValue) offset")
        }
    }

    func load() {
        guard let r = view?.view?.viewRange else { return }
        for p in ViewRange.Plane.allCases {
            levels[p] = r.level(p, viewLevel: viewLevel)
            offsets[p] = Parameters.format(.double(r.offset(p)), type: .length, model: m)
        }
    }

    /// The range as edited, or nil while an offset doesn't parse.
    var draft: ViewRange? {
        guard var r = view?.view?.viewRange else { return nil }
        for p in ViewRange.Plane.allCases {
            let level = levels[p] ?? .associated
            let text = offsets[p] ?? "0"
            let d: Double
            if level == .unlimited { d = r.offset(p) }
            else { guard let v = try? Parameters.parse(text, type: .length, model: m).doubleValue, v.isFinite else { return nil }; d = v }
            r.set(p, level: level, offset: d)
        }
        return r
    }

    var draftProblem: String? {
        guard let r = draft else { return "Enter each offset as a length (for example 1200 mm)." }
        return r.problem(viewLevel: viewLevel, in: m)
    }

    /// Validates and applies; returns false (with the reason shown) when the range is invalid.
    func apply() -> Bool {
        if let p = draftProblem { problem = p; NSSound.beep(); return false }
        guard let r = draft else { return false }
        problem = nil
        guard r != view?.view?.viewRange else { return true }
        state.session.perform("Change View Range") { tx in tx.update(viewID) { $0.view?.viewRange = r } }
        if let e = state.session.lastError { problem = e.message; return false }
        return true
    }
}

/// Elevation diagram of a view range: nearby levels, the primary range (shaded) and the four planes.
struct ViewRangeDiagram: View {
    let model: BIMModel
    let viewLevel: ElementID?
    let range: ViewRange

    var body: some View {
        Canvas { ctx, size in
            let planes = ViewRange.Plane.allCases.map { ($0, range.z($0, viewLevel: viewLevel, in: model)) }
            let base = model.elevation(ofLevel: viewLevel)
            let nearLevels = model.levels.filter { abs(($0.level?.elevation ?? 0) - base) < 12 }
            let finite = planes.map(\.1).filter { abs($0) < ViewRange.unlimitedExtent * 0.5 } + nearLevels.map { $0.level?.elevation ?? 0 }
            let lo = (finite.min() ?? base) - 0.8, hi = (finite.max() ?? base + 3) + 0.8
            func y(_ z: Double) -> CGFloat {
                let c = min(max(z, lo - 0.4), hi + 0.4)
                return size.height - 14 - CGFloat((c - lo) / max(hi - lo, 0.1)) * (size.height - 28)
            }
            let left: CGFloat = 8, right = size.width - 8
            let top = planes[0].1, bottom = planes[2].1
            ctx.fill(Path(CGRect(x: left + 30, y: y(top), width: right - left - 60, height: max(y(bottom) - y(top), 1))), with: .color(.accentColor.opacity(0.12)))
            for l in nearLevels {
                let yy = y(l.level?.elevation ?? 0)
                var p = Path(); p.move(to: CGPoint(x: left, y: yy)); p.addLine(to: CGPoint(x: right, y: yy))
                ctx.stroke(p, with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ctx.draw(Text(l.name).font(.system(size: 9)).foregroundStyle(.secondary), at: CGPoint(x: right - 2, y: yy - 7), anchor: .trailing)
            }
            let colors: [ViewRange.Plane: Color] = [.top: .green, .cut: .orange, .bottom: .blue, .depth: .purple]
            for (plane, z) in planes {
                let yy = y(z)
                var p = Path(); p.move(to: CGPoint(x: left + 22, y: yy)); p.addLine(to: CGPoint(x: right - 22, y: yy))
                ctx.stroke(p, with: .color(colors[plane] ?? .primary), lineWidth: plane == .cut ? 2 : 1.5)
                let unlimited = abs(z) >= ViewRange.unlimitedExtent * 0.5
                ctx.draw(Text(plane.rawValue + (unlimited ? " (unlimited)" : "")).font(.system(size: 9, weight: .medium)).foregroundStyle(colors[plane] ?? .primary),
                         at: CGPoint(x: left + 24, y: yy + (plane == .depth ? 7 : -7)), anchor: .leading)
            }
        }
        .background(RoundedRectangle(cornerRadius: Tokens.radiusSection).fill(DialogColors.sectionFill))
        .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
    }
}
