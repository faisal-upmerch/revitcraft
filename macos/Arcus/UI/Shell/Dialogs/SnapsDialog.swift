import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication

/// Snaps: object snap types, the angle increment, snap distance and the master switch. One-shot overrides
/// (SE, SM, SI, SN, SC, SP, ST, SQ, SO) are listed with their keys.
struct SnapsDialog: View {
    @Bindable var state: DocumentState
    static let overrideKeys: [SnapKind: String] = [.endpoint: "SE", .midpoint: "SM", .intersection: "SI", .nearest: "SN", .center: "SC",
                                                   .perpendicular: "SP", .tangent: "ST", .quadrant: "SQ"]
    var body: some View {
        DialogFrame(title: "Snaps", subtitle: "Settings apply to every view. Type a two-letter override during a tool to use one snap for the next pick; SO turns snapping off for it.",
                    okTitle: "Done", showCancel: false, state: state) { state.presented = nil } content: {
            Toggle("Snaps On", isOn: $state.snapSettings.snapsOn).toggleStyle(.switch)
            GroupBox("Object Snaps") {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                    ForEach(SnapKind.allCases.filter { ![.angle, .parallel, .extension].contains($0) }, id: \.self) { k in
                        Toggle(isOn: Binding(get: { state.snapSettings.enabled.contains(k) },
                                             set: { on in if on { state.snapSettings.enabled.insert(k) } else { state.snapSettings.enabled.remove(k) } })) {
                            HStack(spacing: 4) {
                                Text(k.rawValue)
                                if let key = Self.overrideKeys[k] { Text(key).font(.caption.monospaced()).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                .disabled(!state.snapSettings.snapsOn)
                .padding(4)
                HStack {
                    Button("Check All") { state.snapSettings.enabled = Set(SnapKind.allCases) }
                    Button("Check None") { state.snapSettings.enabled = [.angle] }
                }
                .controlSize(.small)
            }
            GroupBox("Angular and Distance") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Angle snaps", isOn: Binding(get: { state.snapSettings.enabled.contains(.angle) },
                                                        set: { on in if on { state.snapSettings.enabled.insert(.angle) } else { state.snapSettings.enabled.remove(.angle) } }))
                    Toggle("Extensions of lines (dashed alignment guides)", isOn: Binding(get: { state.snapSettings.enabled.contains(.extension) },
                                                        set: { on in if on { state.snapSettings.enabled.insert(.extension) } else { state.snapSettings.enabled.remove(.extension) } }))
                    Toggle("Parallel and perpendicular to nearby or recently hovered lines", isOn: Binding(get: { state.snapSettings.enabled.contains(.parallel) },
                                                        set: { on in if on { state.snapSettings.enabled.insert(.parallel) } else { state.snapSettings.enabled.remove(.parallel) } }))
                    Picker("Angle increment", selection: $state.snapSettings.angleIncrement) {
                        Text("Adaptive (45° to 1° as you zoom)").tag(0.0) // I2: RevitCraft's increments
                        ForEach([90.0, 45, 30, 15, 10, 5, 1], id: \.self) { Text("\(Int($0))°").tag($0) }
                    }
                    .frame(maxWidth: 240)
                    Slider(value: $state.snapSettings.pixelRadius, in: 4...24, step: 1) { Text("Snap distance: \(Int(state.snapSettings.pixelRadius)) pt") }
                    Text("Hold ⇧ while drawing to constrain to horizontal or vertical.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(4)
            }
        }
        .frame(minWidth: 480, idealWidth: 480)
    }
}
