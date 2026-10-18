import SwiftUI
import ArcusDomain

// F1415: the view tabs over the family canvas (RevitCraft shows the family's open views as tabs) and Work Plane ▸ Set.

/// Tabs of the family's open views: click to switch, × to close, + to open another.
struct FamilyViewTabs: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(model.openViews) { v in tab(v) }
                }
            }
            Menu {
                ForEach(FamilyPreviewMode.allCases) { v in
                    Button(v.viewTitle) { model.view = v }
                }
            } label: { Image(systemName: "plus").font(.system(size: 10, weight: .semibold)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Open a view")
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.bar)
    }

    func tab(_ v: FamilyPreviewMode) -> some View {
        let selected = model.view == v
        return HStack(spacing: 4) {
            Image(systemName: v.symbol).font(.system(size: 9))
            Text(v.tabTitle).font(.system(size: 11, weight: selected ? .semibold : .regular)).lineLimit(1)
            if model.openViews.count > 1 {
                Button { close(v) } label: { Image(systemName: "xmark").font(.system(size: 7, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Close \(v.viewTitle)")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(selected ? Color.primary.opacity(0.10) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { model.view = v }
        .help(v.viewTitle)
    }

    func close(_ v: FamilyPreviewMode) {
        guard model.openViews.count > 1 else { return }
        model.openViews.removeAll { $0 == v }
        if model.view == v, let last = model.openViews.last { model.view = last }
    }
}

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
