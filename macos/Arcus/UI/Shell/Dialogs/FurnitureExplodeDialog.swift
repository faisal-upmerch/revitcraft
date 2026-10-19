import SwiftUI
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// FMG2: View ▸ Explode Parts: the active 3D view's Explode Parts, distance (slider) and Tag Parts. The same values are
// the view's Properties (Graphics). OK applies them in one undo step.

enum FMG2Dialog: Equatable {
    case explodeParts(ElementID)
}

struct FMG2DialogHost: View {
    let state: DocumentState
    let dialog: FMG2Dialog
    var body: some View {
        switch dialog {
        case .explodeParts(let v): ExplodePartsDialog(state: state, viewID: v)
        }
    }
}

struct ExplodePartsDialog: View {
    let state: DocumentState
    let viewID: ElementID
    @State private var on = true
    @State private var inches = FurnitureExplode.defaultDistance / 0.0254
    @State private var tags = true
    @State private var loaded = false

    var body: some View {
        DialogFrame(title: "Explode Parts", subtitle: state.model[viewID]?.name ?? "3D View", state: state, onOK: apply) {
            ExplodePartsOptions(on: $on, inches: $inches, tags: $tags)
        }
        .frame(width: 440)
        .onAppear {
            guard !loaded, let v = state.model[viewID] else { return }
            loaded = true
            on = FurnitureExplode.isExploded(v) || v.params[FurnitureExplode.onParam] == nil
            inches = FurnitureExplode.distance(v) / 0.0254
            tags = FurnitureExplode.showsTags(v)
        }
    }

    func apply() {
        let (v, on, d, tags) = (viewID, on, inches * 0.0254, tags)
        state.session.perform("Explode Parts") { tx in try FurnitureExplode.set(v, on: on, distance: d, tags: tags, in: tx) }
        if let e = state.session.lastError { state.show(e.message, error: true); return }
        state.presented = nil
    }
}

/// The dialog's controls (also rendered on their own by tests and QA).
struct ExplodePartsOptions: View {
    @Binding var on: Bool
    @Binding var inches: Double
    @Binding var tags: Bool

    static var maximumInches: Double { FurnitureExplode.maximumDistance / 0.0254 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FormRow(label: "") { Toggle("Explode Parts", isOn: $on).toggleStyle(.checkbox) }
            FormRow(label: "Distance") {
                Slider(value: $inches, in: 0...Self.maximumInches, step: 0.5) {
                    Text("Distance")
                } minimumValueLabel: { Text("0\"").font(.caption) } maximumValueLabel: { Text("\(Int(Self.maximumInches))\"").font(.caption) }
                    .labelsHidden()
                    .frame(width: 190)
                    .accessibilityValue(FurnitureSizeText.inches(inches * 0.0254))
                Text(FurnitureSizeText.inches(inches * 0.0254)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            .disabled(!on)
            FormRow(label: "") { Toggle("Tag Parts", isOn: $tags).toggleStyle(.checkbox) }.disabled(!on)
            Text("Parts move apart along their joints. The view's sheets, PDF and images show it this way.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
