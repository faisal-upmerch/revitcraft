import SwiftUI
import ArcusDomain

// F1415: Work Plane ▸ Set. (FES: the view tabs are the shell's view tab pills, FamilyEditorPills.swift.)

/// Work Plane ▸ Set: the named reference plane new sketches, lines and text start from, or the view's own plane.
struct FamilyWorkPlaneDialog: View {
    @Bindable var model: FamilyEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var choice: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Work Plane").font(.title3.weight(.semibold))
            Text("Current: " + (model.workPlane ?? "the view's own plane")).foregroundStyle(.secondary)
            Picker("Name", selection: $choice) {
                Text("None (the view's own plane)").tag("")
                ForEach(FamilyEditing.workPlanes(model.family), id: \.name) { p in
                    Text("Reference Plane: \(p.name) — \(p.plane.label)").tag(p.name)
                }
            }
            Text("Sketches, model lines and model text start from the work plane in views parallel to it; other views use their own plane.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") {
                    model.workPlane = choice.isEmpty ? nil : choice
                    if var s = model.sketch, s.vertices.isEmpty, s.stage == 0 { s.offset = model.workOffset(s.frame); model.sketch = s }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear { choice = model.workPlane ?? "" }
    }
}
