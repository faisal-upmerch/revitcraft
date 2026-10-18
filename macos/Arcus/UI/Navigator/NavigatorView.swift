import SwiftUI
import UniformTypeIdentifiers
import ArcusDomain
import ArcusApplication

/// Project Browser: Views (all), Legends, Schedules/Quantities (all), Sheets (all) with placed views, Families ▸
/// Category ▸ Family ▸ Type, Groups and Links (BL-BROWSER: an AppKit outline, see ProjectBrowserOutline.swift).
struct NavigatorView: View {
    @Bindable var state: DocumentState
    @FocusState private var filterFocused: Bool
    @State private var browser = ProjectBrowserHandle()

    var body: some View {
        let _ = state.session.changeCounter
        let tree = ProjectBrowserTree.build(state.model, filter: state.navigatorFilter)
        VStack(spacing: 0) {
            PanelHeader(title: "Project Browser", symbol: "list.bullet.indent", panel: .navigator, state: state)
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
                TextField("Search", text: $state.navigatorFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .focused($filterFocused)
                    .onExitCommand { state.navigatorFilter = ""; filterFocused = false }
                    .accessibilityLabel("Search the Project Browser")
                if !state.navigatorFilter.isEmpty {
                    Button { state.navigatorFilter = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 8).padding(.bottom, 6)
            ProjectBrowserOutline(state: state, tree: tree, activeViewID: state.activeViewID, openViews: state.openViews,
                                  filtering: !state.navigatorFilter.trimmingCharacters(in: .whitespaces).isEmpty, handle: browser)
                .inlineTextEditing(browser.isRenaming, id: "nav.rename") { browser.focusRenameField() } // BL-BROWSER
        }
        .onReceive(NotificationCenter.default.publisher(for: .projectBrowserSearch)) { n in
            if (n.object as AnyObject?) === state { filterFocused = true }
        }
    }
}

/// Header for dockable panels with detach/close actions.
struct PanelHeader: View {
    let title: String
    let symbol: String
    let panel: DockPanel
    let state: DocumentState
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 11, weight: .semibold))
            Spacer()
            Menu {
                Button("Detach Panel", systemImage: "macwindow.on.rectangle") { PanelWindows.detach(panel, state: state) }
                Button("Dock on the Other Side", systemImage: "arrow.left.arrow.right") {
                    state.workspace = state.workspace == .bimFamiliar ? .macSpacious : .bimFamiliar
                }
                Button("Hide", systemImage: "eye.slash") {
                    if panel == .navigator { state.showNavigator = false } else { state.showProperties = false }
                    state.onWorkspaceChange?()
                }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("\(title) panel options")
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 6)
    }
}

enum DockPanel { case navigator, properties }
