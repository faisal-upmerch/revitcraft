import SwiftUI
import ArcusDomain
import ArcusApplication

/// BL-BROWSER: the Level tool's "Plan Views" panel on the contextual ribbon: Make Plan View and the plan view types
/// it creates for each new level.
struct LevelPlanViewsPanel: View {
    let state: DocumentState
    let tool: LevelTool

    var body: some View {
        let _ = state.toolRevision
        VStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Make Plan View", isOn: Binding(get: { tool.makePlanViews }, set: { tool.makePlanViews = $0; state.toolChangedState() }))
                    .toggleStyle(.checkbox).font(.system(size: 11))
                    .help("Create plan views for each new level")
                Menu {
                    ForEach(LevelTool.planViewChoices, id: \.self) { k in
                        Toggle(k.navigatorGroup, isOn: Binding(get: { tool.planViewKinds.contains(k) }, set: { on in
                            if on { tool.planViewKinds = LevelTool.planViewChoices.filter { tool.planViewKinds.contains($0) || $0 == k } }
                            else if tool.planViewKinds.count > 1 { tool.planViewKinds.removeAll { $0 == k } }
                            state.toolChangedState()
                        }))
                    }
                } label: {
                    Label("Plan View Types…", systemImage: "square.grid.3x3.topleft.filled").font(.system(size: 11))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(!tool.makePlanViews)
                .help(tool.planViewKinds.map(\.navigatorGroup).joined(separator: ", "))
                .accessibilityLabel("Plan view types: \(tool.planViewKinds.map(\.navigatorGroup).joined(separator: ", "))")
            }
            .frame(height: RibbonMetrics.contentHeight, alignment: .top)
            Text("Plan Views")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Tokens.contextualTint.opacity(0.9))
                .frame(height: RibbonMetrics.titleHeight)
        }
        .padding(.horizontal, 6).padding(.top, 5).padding(.bottom, 3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan Views panel")
    }
}
