import SwiftUI
import ArcusDomain
import ArcusApplication

// F34: Manage ▸ Structural Settings and Structure ▸ Cover (Rebar Cover Settings), with the settings RevitCraft has
// (crates/rc-app/src/dialogs/insert.rs structural_dialog, dialogs/mod.rs rebar_cover_dialog).

enum F34Dialog: Equatable {
    case structuralSettings, rebarCover
}

struct F34DialogHost: View {
    let state: DocumentState
    let dialog: F34Dialog
    var body: some View {
        switch dialog {
        case .structuralSettings: StructuralSettingsDialog(state: state)
        case .rebarCover: RebarCoverDialog(state: state)
        }
    }
}

/// Symbolic cutbacks and brace symbols (paper lengths), load cases and load combinations.
struct StructuralSettingsDialog: View {
    let state: DocumentState
    enum Tab: String, CaseIterable { case symbolic = "Symbolic Representation Settings", loadCases = "Load Cases", combinations = "Load Combinations" }
    @State private var tab = Tab.symbolic
    @State private var s = StructuralSettingsData()
    /// Brace, Beam/Truss, Column cutbacks and the parallel line offset, as typed (paper millimeters).
    @State private var texts = ["", "", "", ""]
    /// Editable rows (with stable identities) of the load cases and combinations: (name, nature / formula).
    struct Row: Identifiable { let id = UUID(); var name: String; var value: String }
    @State private var cases: [Row] = []
    @State private var combos: [Row] = []

    static func paper(_ meters: Double) -> String { String(format: "%.2f mm", meters * 1000) }
    static func parsePaper(_ t: String) -> Double? {
        let v = t.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "mm", with: "").trimmingCharacters(in: .whitespaces)
        guard let d = Double(v.replacingOccurrences(of: ",", with: ".")), d >= 0, d < 100 else { return nil }
        return d / 1000
    }

    var body: some View {
        DialogFrame(title: "Structural Settings", subtitle: "Plan symbols of framing, and the load cases and combinations of the project.", state: state) {
            let parsed = texts.map(Self.parsePaper)
            guard parsed.allSatisfy({ $0 != nil }) else {
                state.show("Enter the cutback distances as lengths on paper, such as 2.38 mm.", error: true); return
            }
            var out = s
            (out.braceCutback, out.beamCutback, out.columnCutback, out.braceOffset) = (parsed[0]!, parsed[1]!, parsed[2]!, parsed[3]!)
            out.loadCases = cases.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map { StructuralLoadCase(name: $0.name, nature: $0.value) }
            out.loadCombinations = combos.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map { StructuralLoadCombination(name: $0.name, formula: $0.value) }
            state.session.perform("Structural Settings") { tx in StructuralFraming.setSettings(out, in: tx) }
            state.presented = nil
        } content: {
            Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden()
            Group {
                switch tab {
                case .symbolic: symbolic
                case .loadCases: loadCases
                case .combinations: combinations
                }
            }
            .frame(minHeight: 230, alignment: .top)
        }
        .frame(width: 560)
        .onAppear {
            s = state.model.structuralSettings
            texts = [s.braceCutback, s.beamCutback, s.columnCutback, s.braceOffset].map(Self.paper)
            cases = s.loadCases.map { Row(name: $0.name, value: $0.nature) }
            combos = s.loadCombinations.map { Row(name: $0.name, value: $0.formula) }
        }
    }

    var symbolic: some View {
        VStack(alignment: .leading, spacing: DialogMetrics.spacing) {
            Text("Symbolic Cutback Distance").font(DialogMetrics.sectionHeader)
            ForEach(Array(["Brace:", "Beam/Truss:", "Column:"].enumerated()), id: \.offset) { k, label in
                FormRow(label: label) { TextField("", text: $texts[k]).textFieldStyle(.roundedBorder).frame(width: 110) }
            }
            Text("Brace Symbols").font(DialogMetrics.sectionHeader).padding(.top, 4)
            FormRow(label: "Plan representation:") {
                Picker("", selection: $s.braceParallel) { Text("Parallel Line").tag(true); Text("Line w/Angle").tag(false) }.labelsHidden().frame(width: 150)
            }
            FormRow(label: "Parallel line offset:") { TextField("", text: $texts[3]).textFieldStyle(.roundedBorder).frame(width: 110) }
            FormRow(label: "") { Toggle("Show brace above", isOn: $s.kickerSymbol) }
        }
    }

    var loadCases: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow { Text(""); Text("Name").font(DialogMetrics.sectionHeader); Text("Nature").font(DialogMetrics.sectionHeader) }
                ForEach($cases) { $row in
                    GridRow {
                        Button { cases.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("Remove \(row.name)")
                        TextField("", text: $row.name).textFieldStyle(.roundedBorder).frame(width: 180)
                        Picker("", selection: $row.value) { ForEach(StructuralLoadCase.natures, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 150)
                    }
                }
            }
            Button("Add") { cases.append(Row(name: "LC\(cases.count + 1)", value: "Dead")) }
        }
    }

    var combinations: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow { Text(""); Text("Name").font(DialogMetrics.sectionHeader); Text("Formula").font(DialogMetrics.sectionHeader) }
                ForEach($combos) { $row in
                    GridRow {
                        Button { combos.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("Remove \(row.name)")
                        TextField("", text: $row.name).textFieldStyle(.roundedBorder).frame(width: 160)
                        TextField("", text: $row.value).textFieldStyle(.roundedBorder).frame(width: 240)
                    }
                }
            }
            Button("Add") {
                let f = cases.prefix(2).map { "1.0*\($0.name)" }.joined(separator: " + ")
                combos.append(Row(name: "Combination \(combos.count + 1)", value: f))
            }
        }
    }
}

/// Rebar Cover Settings: the concrete cover to the bars of every reinforcement in the project.
struct RebarCoverDialog: View {
    let state: DocumentState
    @State private var text = ""
    var body: some View {
        DialogFrame(title: "Rebar Cover Settings", subtitle: "The distance from the concrete faces to the bars.", state: state) {
            guard let v = try? Parameters.parse(text, type: .length, model: state.model).doubleValue, v > 0 else {
                state.show("Enter a positive length for the cover.", error: true); return
            }
            var s = state.model.structuralSettings
            s.rebarCover = v
            state.session.perform("Rebar Cover Settings") { tx in StructuralFraming.setSettings(s, in: tx) }
            state.presented = nil
        } content: {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow { Text("Description").font(DialogMetrics.sectionHeader); Text("Setting").font(DialogMetrics.sectionHeader) }
                GridRow {
                    Text("Rebar Cover")
                    TextField("", text: $text).textFieldStyle(.roundedBorder).frame(width: 120)
                }
            }
        }
        .onAppear { text = Parameters.format(.double(Reinforcement.cover(state.model)), type: .length, model: state.model) }
    }
}
