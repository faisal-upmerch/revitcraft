import SwiftUI
import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// F12: schedule tool dialogs (RevitCraft rc-app dialogs/schedule_tools.rs `SchedTool::Combine`, `Shading`,
// `Borders`, `Font`, `Split`).

struct CombineParametersDialog: View {
    let state: DocumentState
    let scheduleID: ElementID
    @State private var available: [ParameterEntry] = []
    @State private var parts: [ScheduleCombinedPart] = []
    @State private var pick: ParameterID?
    @State private var partSel: String?
    @State private var heading = ""
    var body: some View {
        DialogFrame(title: "Combine Parameters", subtitle: "One column made of several parameters: each value with its prefix and suffix, then the separator before the next.",
                    okDisabled: parts.isEmpty, state: state) {
            let p = parts, h = heading
            state.session.editSchedule(scheduleID, "Combine Parameters") { ScheduleFormattingEdits.combine(p, heading: h, &$0) }
            state.presented = nil
        } content: {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text("Schedulable fields").font(.caption.weight(.semibold))
                    List(available, id: \.id, selection: $pick) { e in Text(e.name).tag(e.id) }.frame(width: 220, height: 240)
                }
                VStack {
                    Spacer()
                    Button("Add →") { if let id = pick, let e = available.first(where: { $0.id == id }) { parts.append(ScheduleCombinedPart(parameterID: e.id, name: e.name)) } }.disabled(pick == nil)
                    Button("← Remove") { parts.removeAll { $0.id == partSel } }.disabled(partSel == nil)
                    Spacer()
                }
                VStack(alignment: .leading) {
                    Text("Combined parameters").font(.caption.weight(.semibold))
                    List(selection: $partSel) {
                        ForEach($parts) { $p in
                            HStack {
                                TextField("Prefix", text: $p.prefix).frame(width: 60)
                                Text(p.name).frame(width: 110, alignment: .leading).lineLimit(1)
                                TextField("Suffix", text: $p.suffix).frame(width: 60)
                                TextField("Separator", text: $p.separator).frame(width: 60)
                            }.tag(p.id)
                        }
                        .onMove { parts.move(fromOffsets: $0, toOffset: $1) }
                    }.frame(width: 380, height: 240)
                }
            }
            FormRow(label: "Column heading") { TextField(parts.map(\.name).joined(separator: " / "), text: $heading).textFieldStyle(.roundedBorder) }
        }
        .frame(minWidth: 740)
        .onAppear {
            let m = state.model
            guard let def = m[scheduleID]?.schedule else { return }
            let sample = m.elements(def.categories).first(where: { !$0.isType })
            var seen = Set<ParameterID>()
            available = (sample.map { Parameters.allEntries($0, m) } ?? []).filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
        }
    }
}

struct ScheduleShadingDialog: View {
    let state: DocumentState
    let scheduleID: ElementID
    let keys: [ScheduleCellKey]
    @State private var color = Color.white
    var body: some View {
        DialogFrame(title: "Shading", subtitle: "Background colour of the selected cells.", state: state) {
            let rgb = RGBColor(nsColor: NSColor(color))
            state.session.editSchedule(scheduleID, "Shading") { ScheduleFormattingEdits.style(keys, &$0) { $0.shading = rgb } }
            state.presented = nil
        } content: {
            ColorPicker("Color", selection: $color, supportsOpacity: false)
        }
        .onAppear {
            if let k = keys.first, let s = state.model[scheduleID]?.schedule?.formatting.style(k).shading { color = Color(nsColor: s.nsColor) }
        }
    }
}

struct ScheduleBordersDialog: View {
    let state: DocumentState
    let scheduleID: ElementID
    let keys: [ScheduleCellKey]
    @State private var edges: [ScheduleBorder] = [.thin, .thin, .thin, .thin]
    static let names = ["Top", "Right", "Bottom", "Left"]
    var body: some View {
        DialogFrame(title: "Edit Borders", subtitle: "Line weight of each edge of the selected cells.", state: state) {
            let e = edges
            state.session.editSchedule(scheduleID, "Borders") { ScheduleFormattingEdits.style(keys, &$0) { s in
                if Set(e).count == 1 { s.border = e[0]; s.edges = nil } else { s.border = nil; s.edges = e }
            } }
            state.presented = nil
        } content: {
            HStack {
                Text("All edges")
                ForEach(ScheduleBorder.allCases, id: \.self) { b in Button(b.title) { edges = [b, b, b, b] } }
            }
            Form {
                ForEach(0..<4, id: \.self) { i in
                    Picker(Self.names[i], selection: $edges[i]) { ForEach(ScheduleBorder.allCases, id: \.self) { Text($0.title).tag($0) } }
                }
            }
        }
        .frame(minWidth: 460)
        .onAppear {
            if let k = keys.first, let st = state.model[scheduleID]?.schedule?.formatting.style(k) {
                edges = st.edges ?? st.border.map { [$0, $0, $0, $0] } ?? edges
            }
        }
    }
}

struct ScheduleFontDialog: View {
    let state: DocumentState
    let scheduleID: ElementID
    let keys: [ScheduleCellKey]
    @State private var font = ScheduleFont()
    @State private var sizeMM = 2.2
    @State private var color = Color.black
    var families: [String] { ["Helvetica"] + NSFontManager.shared.availableFontFamilies.filter { $0 != "Helvetica" && !$0.hasPrefix(".") } }
    var body: some View {
        DialogFrame(title: "Edit Font", subtitle: "Font of the selected cells. Sheets and PDFs print it in Arcus's drawing font at this size and style.", state: state) {
            var f = font
            f.size = sizeMM / 1000
            f.color = RGBColor(nsColor: NSColor(color))
            let ff = f
            state.session.editSchedule(scheduleID, "Font") { ScheduleFormattingEdits.style(keys, &$0) { $0.font = ff } }
            state.presented = nil
        } content: {
            Form {
                Picker("Font", selection: $font.family) { ForEach(families, id: \.self) { Text($0).tag($0) } }
                TextField("Size (mm on paper)", value: $sizeMM, format: .number.precision(.fractionLength(0...2)))
                Toggle("Bold", isOn: $font.bold)
                Toggle("Italic", isOn: $font.italic)
                Toggle("Underline", isOn: $font.underline)
                ColorPicker("Font color", selection: $color, supportsOpacity: false)
            }
        }
        .frame(minWidth: 440)
        .onAppear {
            let def = state.model[scheduleID]?.schedule
            let ap = def?.appearance ?? ScheduleAppearance()
            if let k = keys.first, let f = def?.formatting.style(k).font { font = f }
            else if case .title? = keys.first { font = ScheduleFont(size: ap.titleTextHeight, bold: ap.boldTitle) }
            else if case .heading? = keys.first { font = ScheduleFont(size: ap.headerTextHeight, bold: ap.boldHeaders) }
            else { font = ScheduleFont(size: ap.bodyTextHeight) }
            sizeMM = font.size * 1000
            color = Color(nsColor: font.color.nsColor)
        }
    }
}

/// Split & Place: the schedule split into segments of equal height, placed side by side on a sheet.
struct SplitAndPlaceDialog: View {
    let state: DocumentState
    let scheduleID: ElementID
    @State private var sheet: UInt64 = 0
    @State private var segments = 2
    var body: some View {
        let m = state.model
        let rows = m[scheduleID].map { ScheduleEngine.compute($0, m).rows.count } ?? 0
        DialogFrame(title: "Split Schedule and Place", subtitle: "\(rows) rows, split into segments of equal height. Later segments repeat the headings.", okDisabled: sheet == 0, state: state) {
            let sid = ElementID(sheet), n = segments
            if state.f11Perform("Split & Place", { tx in try ScheduleSplit.place(scheduleID, onSheet: sid, segments: n, in: tx) }) {
                state.presented = nil
                state.open(sid)
            }
        } content: {
            Picker("Place on sheet", selection: $sheet) { ForEach(m.sheets, id: \.id) { s in Text("\(s.sheet?.number ?? "") - \(s.name)").tag(s.id.raw) } }
            Stepper("Number of segments: \(segments)", value: $segments, in: 2...max(2, min(20, rows)))
        }
        .frame(minWidth: 420)
        .onAppear { sheet = (m.sheet(containing: scheduleID) ?? m.sheets.first)?.id.raw ?? 0 }
    }
}

extension RGBColor {
    /// An sRGB colour from a colour well's colour.
    fileprivate init(nsColor c: NSColor) {
        let s = c.usingColorSpace(.sRGB) ?? .black
        self.init(Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent))
    }
}
