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
        DialogFrame(title: "Snaps", icon: "dot.squareshape.split.2x2", tint: .blue, size: .medium, subtitle: "Every view. During a tool, a two-letter key overrides the next pick; SO turns snapping off for it.",
                    okTitle: "Done", showCancel: false, labelWidth: 130, state: state) { state.presented = nil } content: {
            DialogSection {
                HStack { Text("Snaps"); Spacer(); Toggle("", isOn: $state.snapSettings.snapsOn).toggleStyle(.switch).labelsHidden() }
            }
            DialogSection("Object snaps", rows: false) {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
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
                .padding(12)
            } accessory: {
                HStack(spacing: 4) {
                    Button("Check All") { state.snapSettings.enabled = Set(SnapKind.allCases) }
                    Button("Check None") { state.snapSettings.enabled = [.angle] }
                }
            }
            DialogSection("Angular and distance", footnote: "Hold ⇧ while drawing to constrain to horizontal or vertical.") {
                    Toggle("Angle snaps", isOn: Binding(get: { state.snapSettings.enabled.contains(.angle) },
                                                        set: { on in if on { state.snapSettings.enabled.insert(.angle) } else { state.snapSettings.enabled.remove(.angle) } }))
                    Toggle("Extensions of lines (dashed alignment guides)", isOn: Binding(get: { state.snapSettings.enabled.contains(.extension) },
                                                        set: { on in if on { state.snapSettings.enabled.insert(.extension) } else { state.snapSettings.enabled.remove(.extension) } }))
                    Toggle("Parallel and perpendicular to nearby or recently hovered lines", isOn: Binding(get: { state.snapSettings.enabled.contains(.parallel) },
                                                        set: { on in if on { state.snapSettings.enabled.insert(.parallel) } else { state.snapSettings.enabled.remove(.parallel) } }))
                    DialogRow("Angle increment") {
                        Picker("", selection: $state.snapSettings.angleIncrement) {
                            Text("Adaptive (45° to 1° as you zoom)").tag(0.0) // I2: RevitCraft's increments
                            ForEach([90.0, 45, 30, 15, 10, 5, 1], id: \.self) { Text("\(Int($0))°").tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                    DialogRow("Snap distance") {
                        HStack { Slider(value: $state.snapSettings.pixelRadius, in: 4...24, step: 1).labelsHidden(); Text("\(Int(state.snapSettings.pixelRadius)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing) }
                    }
            }
        }
    }
}
