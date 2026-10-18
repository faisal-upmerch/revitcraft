import SwiftUI
import AppKit
import ArcusDomain

/// Settings sections for the canvas (BL-CANVAS: ARCUS-027/080/085/026): selection, pre-selection and alert colours,
/// temporary dimension text, tooltip assistance and double-click actions. Every change redraws open canvases.
struct CanvasSettingsSections: View {
    @AppStorage(CanvasSettings.tempDimSizeKey) private var tempDimSize = 11.0
    @AppStorage(CanvasSettings.tempDimBackgroundKey) private var tempDimBackground = CanvasSettings.TextBackground.transparent.rawValue
    @AppStorage(CanvasSettings.tooltipKey) private var tooltip = CanvasSettings.TooltipAssistance.normal.rawValue
    @AppStorage(CanvasSettings.familyDoubleClickKey) private var familyClick = CanvasSettings.FamilyDoubleClick.editType.rawValue
    @AppStorage(CanvasSettings.sketchDoubleClickKey) private var sketchClick = CanvasSettings.SketchDoubleClick.editSketch.rawValue
    @AppStorage(CanvasSettings.groupDoubleClickKey) private var groupClick = CanvasSettings.GroupDoubleClick.editGroup.rawValue
    @AppStorage(CanvasSettings.viewportDoubleClickKey) private var viewportClick = CanvasSettings.ViewportDoubleClick.activate.rawValue
    @Environment(\.colorScheme) private var scheme
    /// Bumped when a colour changes so the pickers re-read the stored colours.
    @State private var colorRevision = 0

    var body: some View {
        Section("Colors") {
            let _ = colorRevision
            ForEach(CanvasSettings.ColorRole.allCases) { role in
                HStack {
                    ColorPicker(role.rawValue, selection: colorBinding(role), supportsOpacity: false)
                    Button("Default") { CanvasSettings.setCustomColor(role, nil); colorRevision += 1 }
                        .controlSize(.small)
                        .disabled(CanvasSettings.customColor(role) == nil)
                }
            }
            Text("Selection and pre-selection colour elements you select and hover on the canvas; alert marks elements named by errors, such as sketch lines that don't close. The defaults adapt to light and dark canvases.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Temporary Dimensions") {
            Slider(value: $tempDimSize, in: 8...16, step: 1) { Text("Text size: \(Int(tempDimSize)) pt") }
            Picker("Text background", selection: $tempDimBackground) {
                ForEach(CanvasSettings.TextBackground.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
        }
        Section("Tooltips") {
            Picker("Tooltip assistance", selection: $tooltip) {
                ForEach(CanvasSettings.TooltipAssistance.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            Text("None hides canvas tooltips. Minimal shows snaps only. Normal adds the next step of the tool and, after a second's rest, the name of the element under the pointer. High shows them sooner, with the element's Mark and level.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Double-click") {
            Picker("Family instances", selection: $familyClick) { ForEach(CanvasSettings.FamilyDoubleClick.allCases) { Text($0.rawValue).tag($0.rawValue) } }
            Picker("Sketch-based elements", selection: $sketchClick) { ForEach(CanvasSettings.SketchDoubleClick.allCases) { Text($0.rawValue).tag($0.rawValue) } }
            Picker("Groups", selection: $groupClick) { ForEach(CanvasSettings.GroupDoubleClick.allCases) { Text($0.rawValue).tag($0.rawValue) } }
            Picker("Views on sheets", selection: $viewportClick) { ForEach(CanvasSettings.ViewportDoubleClick.allCases) { Text($0.rawValue).tag($0.rawValue) } }
        }
        .onChange(of: tempDimSize) { _, _ in CanvasSettings.changed() }
        .onChange(of: tempDimBackground) { _, _ in CanvasSettings.changed() }
        .onChange(of: tooltip) { _, _ in CanvasSettings.changed() }
    }

    func colorBinding(_ role: CanvasSettings.ColorRole) -> Binding<Color> {
        Binding(get: { CanvasSettings.color(role, dark: scheme == .dark).color },
                set: { c in CanvasSettings.setCustomColor(role, RGBColor.from(NSColor(c))); colorRevision += 1 })
    }
}
