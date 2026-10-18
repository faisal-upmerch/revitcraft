import SwiftUI
import ArcusViewport3D

/// BL-SITE (ARCUS-029): Settings ▸ 3D Navigation — the mouse scheme (BIM-style by default, Blender-style one click
/// away), orbit pivot, and what the mouse, wheel and trackpad do in every view.
struct NavigationSettingsSection: View {
    @State private var style = Viewport3DNavigationSettings.style
    @State private var orbitSelection = Viewport3DNavigationSettings.orbitAroundSelection

    var body: some View {
        Picker("Middle button", selection: $style) {
            ForEach(Viewport3DNavigationStyle.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.radioGroup)
        .onChange(of: style) { _, v in Viewport3DNavigationSettings.style = v }
        Text(style.summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Toggle("Orbit around the selection (Blender-style)", isOn: $orbitSelection)
            .disabled(style == .revit)
            .onChange(of: orbitSelection) { _, v in Viewport3DNavigationSettings.orbitAroundSelection = v }
        Text("""
        In every view: the wheel zooms at the pointer by the same step in plans, elevations, sections and 3D; double-click the middle button (or double-tap with two fingers) to zoom to fit; pinch to zoom. Plans and elevations pan with the middle button or a two-finger drag.
        In 3D views: ⌥-drag with the left button stands in for the middle button on a trackpad or one-button mouse (⌥⇧ pans, ⌃⌥ dollies). The orientation cube at the top right orients the view: click a face, edge or corner, a compass letter, or the house for Home; drag it to orbit.
        """)
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        .onAppear { style = Viewport3DNavigationSettings.style; orbitSelection = Viewport3DNavigationSettings.orbitAroundSelection }
    }
}
