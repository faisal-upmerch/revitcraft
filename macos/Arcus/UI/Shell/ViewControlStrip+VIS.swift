import SwiftUI
import ArcusDomain
import ArcusApplication

// VIS: the View Control Bar shows the view's state as Revit's does: the detail level and visual style buttons carry
// the current choice's icon (and say it in their tooltip), and their menus tick the current choice.

/// The choices the View Control Bar's menus offer for a view, with the current one ticked.
enum ViewControlChoices {
    static func detailLevels(_ vd: ViewData) -> [(level: DetailLevel, checked: Bool)] {
        DetailLevel.allCases.map { ($0, $0 == vd.detailLevel) }
    }
    /// 3D views offer every style; plans, sections and elevations Wireframe and Hidden Line (anything else reads as
    /// Hidden Line there).
    static func visualStyles(_ vd: ViewData) -> [(style: VisualStyle, checked: Bool)] {
        let styles: [VisualStyle] = vd.kind == .threeD ? VisualStyle.allCases : [.wireframe, .hiddenLine]
        let current = currentStyle(vd)
        return styles.map { ($0, $0 == current) }
    }
    static func currentStyle(_ vd: ViewData) -> VisualStyle {
        vd.kind == .threeD ? vd.visualStyle : (vd.visualStyle == .wireframe ? .wireframe : .hiddenLine)
    }
}

extension ViewControlStrip {
    /// Detail Level: Coarse, Medium or Fine, with the current one's icon and a checkmark on it.
    func detailLevelMenu(_ vd: ViewData) -> some View {
        Menu {
            ForEach(ViewControlChoices.detailLevels(vd), id: \.level) { d, checked in
                Toggle(isOn: Binding(get: { checked }, set: { _ in
                    CommandRouter(state: state).setViewParam(ParameterID("view.detailLevel"), .text(d.rawValue), "Detail Level")
                })) {
                    Label { Text(d.rawValue) } icon: { Image(nsImage: ViewStateIcons.detail(d)) }
                }
            }
        } label: { ViewControlIcon(image: ViewStateIcons.detail(vd.detailLevel)) }
        .menuStyle(.borderlessButton).fixedSize().barMenuItem().pillHighlight(false)
        .help(vd.detailLevel.controlHelp)
        .accessibilityLabel("Detail Level")
        .accessibilityValue(vd.detailLevel.rawValue)
    }

    /// Visual Style: the styles this kind of view offers, with the current one's icon and a checkmark on it.
    func visualStyleMenu(_ vd: ViewData) -> some View {
        let current = ViewControlChoices.currentStyle(vd)
        return Menu {
            ForEach(ViewControlChoices.visualStyles(vd), id: \.style) { s, checked in
                Toggle(isOn: Binding(get: { checked }, set: { _ in
                    CommandRouter(state: state).setViewParam(ParameterID("view.visualStyle"), .text(s.rawValue), "Visual Style")
                })) {
                    Label { Text(s.rawValue) } icon: { Image(nsImage: ViewStateIcons.style(s)) }
                }
            }
        } label: { ViewControlIcon(image: ViewStateIcons.style(current)) }
        .menuStyle(.borderlessButton).fixedSize().barMenuItem().pillHighlight(false)
        .help("Visual Style: \(current.rawValue)")
        .accessibilityLabel("Visual Style")
        .accessibilityValue(current.rawValue)
    }
}
