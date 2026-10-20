import SwiftUI
import ArcusDomain
import ArcusApplication

// BL-VG: View Control Bar additions — Visual Style in 2D views, Temporary View Properties, template-aware scale lock.

extension ViewControlStrip {
    /// The view's template controls its scale.
    func scaleLocked(_ v: Element?) -> Bool {
        guard let v else { return false }
        return ViewTemplates.controllingTemplate(v, .scale, state.model) != nil
    }

    /// Wireframe (lines only) or Hidden Line (cut and surface patterns) for plans, sections and elevations.
    func visualStyle2D(_ vd: ViewData) -> some View {
        visualStyleMenu(vd) // VIS
    }

    /// Temporary View Properties: apply a template to this view for the session, or restore.
    func temporaryViewPropertiesMenu(_ temp: TemporaryVisibility?) -> some View {
        let active = temp?.temporaryTemplateID != nil
        return Menu {
            if active {
                Text("Using “\(state.model[temp?.temporaryTemplateID]?.name ?? "")”")
                Button("Restore View Properties") { CommandRouter(state: state).run(.temporaryViewProperties) }
            } else {
                Button("Temporarily Apply Template Properties…") { CommandRouter(state: state).run(.temporaryViewProperties) }
            }
            Divider()
            Button("Apply Template Properties to Current View…") { CommandRouter(state: state).run(.viewTemplateApplyProperties) }
            Button("Manage View Templates…") { CommandRouter(state: state).run(.viewTemplatesManage) }
        } label: { Image(systemName: "clock.badge").foregroundStyle(active ? Tokens.selectionColor : .primary) }
        .menuStyle(.borderlessButton).fixedSize()
        .modifier(HoverBackground(active: active, tint: Tokens.selectionColor, radius: 5)) // VIS
        .help(active ? "Temporary View Properties is on" : "Temporary View Properties")
        .accessibilityLabel(active ? "Temporary view properties, active" : "Temporary view properties")
    }
}
