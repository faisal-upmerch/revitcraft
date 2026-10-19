import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication

// HOME: the Home window (Docs/FurnitureMode.md §4): a floating glass sidebar with the app mark, the three Start cards,
// Open… and Open Sample Project; on the right, the selected card's details and Create, or Recent when no card is
// selected.

/// Home: start a project, furniture or family, or open a recent file.
struct ProjectHubView: View {
    @State private var model: HomeModel

    init(initialTab: AppDelegate.HubTab) {
        _model = State(initialValue: HomeModel(tab: initialTab))
    }
    /// Home on an existing model (QA and offscreen renders).
    init(model: HomeModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        HStack(spacing: 0) {
            HomeSidebar(model: model)
                .frame(width: HomeStyle.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(GlassBackdrop(role: .dock, cornerRadius: Tokens.dockCornerRadius))
                .padding(HomeStyle.margin)
            HomeContent(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, idealWidth: 1040, maxWidth: .infinity, minHeight: 600, idealHeight: 660, maxHeight: .infinity)
        .background(HomeBackdrop())
        .ignoresSafeArea()
        .onAppear { model.reload() }
    }
}

/// The window behind the floating sidebar: the window colour with a faint wash of the selected card's tint.
struct HomeBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [Color.primary.opacity(scheme == .dark ? 0.0 : 0.015), Color.primary.opacity(scheme == .dark ? 0.04 : 0.035)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Sidebar

/// The sidebar: mark, Start cards, Open… and Open Sample Project.
struct HomeSidebar: View {
    @Bindable var model: HomeModel
    @FocusState private var cardsFocused: Bool
    @State private var showClaude = false // MCP: Design with Claude

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: HomeStyle.titlebarInset) // the traffic lights
            HStack(spacing: 12) {
                ArcusMark(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Arcus").font(.system(size: 20, weight: .semibold))
                    Text("Architecture, furniture and families").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 24)
            HomeSectionHeader(title: "Start").padding(.horizontal, 8).padding(.bottom, 8)
            VStack(spacing: 4) {
                ForEach(HomeCard.allCases) { card in
                    HomeStartCard(card: card, selected: model.selected == card) {
                        model.selected = card
                        cardsFocused = true
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($cardsFocused)
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                model.moveSelection(by: press.key == .upArrow || press.key == .leftArrow ? -1 : 1)
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Start")
            HomeClaudeCard { showClaude = true }.padding(.top, 12) // MCP: Design with Claude
            Spacer(minLength: 16)
            VStack(spacing: 2) {
                HomeRowButton(title: "Open…", symbol: "folder", help: "Open a project, furniture or family (⌘O)") { model.openPanel() }
                    .keyboardShortcut("o", modifiers: .command)
                HomeRowButton(title: model.openingSample ? "Building Sample…" : "Open Sample Project", symbol: "building.2",
                              help: "Courtyard House: 4 levels, 2 wings, 120 rooms, 16 sheets") { model.openSample() }
                    .disabled(model.openingSample)
            }
            Text("Documents stay on this Mac. No account, no network.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .padding(.horizontal, 8).padding(.top, 16)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .onAppear { cardsFocused = true }
        .sheet(isPresented: $showClaude) { ClaudeSetupView(onDone: { showClaude = false }) } // MCP
    }
}

/// One Start card: illustration, title and one line.
struct HomeStartCard: View {
    let card: HomeCard
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                HomeIllustration(card: card, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    Text(card.line).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeCard(selected: selected, tint: card.tint, radius: Tokens.cardCornerRadius + 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.title)
        .accessibilityValue(card.line)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Shows the options for a new \(card.title.lowercased())")
    }
}

// MARK: - Content

/// The right side: Recent, or the selected card's details with Create.
struct HomeContent: View {
    @Bindable var model: HomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            if let card = model.selected {
                HomeCardHeader(card: card).padding(.horizontal, HomeStyle.pad).padding(.bottom, 16)
                ScrollView {
                    Group {
                        switch card {
                        case .architectural: HomeArchitecturalPane(model: model)
                        case .furniture: HomeFurniturePane(model: model)
                        case .family: HomeFamilyPane(model: model)
                        }
                    }
                    .padding(.horizontal, HomeStyle.pad)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
                createBar(card)
            } else {
                HomeRecentsPane(model: model)
            }
        }
        .id(model.selected)
        .transition(.opacity)
        .arcusAnimation(model.selected)
    }

    /// The titlebar strip: Back to Recent while a card is selected.
    var topBar: some View {
        HStack {
            if model.selected != nil {
                Button { model.selected = nil } label: {
                    Label("Recent", systemImage: "chevron.left").font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Back to Recent (Esc)")
            }
            Spacer()
        }
        .padding(.horizontal, HomeStyle.pad - 4)
        .frame(height: HomeStyle.titlebarInset + HomeStyle.margin)
    }

    func createBar(_ card: HomeCard) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.6)
            HStack(spacing: 16) {
                if let reason = model.createDisabledReason {
                    Text(reason).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.create() } label: {
                    Text(card.createTitle).frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(card.tint)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.createDisabledReason != nil)
                .help("\(card.createTitle) (Return)")
            }
            .padding(.horizontal, HomeStyle.pad)
            .frame(height: 64)
        }
    }
}

/// The selected card's title row: its illustration, title and line.
struct HomeCardHeader: View {
    let card: HomeCard
    var body: some View {
        HStack(spacing: 16) {
            HomeIllustration(card: card, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title).font(.system(size: 22, weight: .semibold))
                Text(card.line).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}
