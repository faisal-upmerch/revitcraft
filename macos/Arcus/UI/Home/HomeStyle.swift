import SwiftUI
import AppKit

// HOME: metrics and colours of the Home window, on the 8 pt grid; radii nest inside `Tokens.dockCornerRadius`.

extension Tokens {
    /// Start cards, recent tiles and gallery tiles.
    static let cardCornerRadius: CGFloat = 12
    /// Illustrations and thumbnails inside a card or tile (card radius minus its 4 pt inset).
    static let thumbnailCornerRadius: CGFloat = 8
}

enum HomeStyle {
    static let sidebarWidth: CGFloat = 320
    /// Gap between the floating sidebar and the window edges (as the main window's docks).
    static let margin: CGFloat = Tokens.dockMargin
    /// Inner padding of the sidebar and the content pane.
    static let pad: CGFloat = 24
    /// Height kept clear for the traffic lights at the top of the sidebar and the content.
    static let titlebarInset: CGFloat = 44

    static func tint(_ card: HomeCard) -> Color {
        switch card {
        case .architectural: Color(red: 0.20, green: 0.47, blue: 0.86)
        case .furniture: Color(red: 0.82, green: 0.50, blue: 0.20)
        case .family: Color(red: 0.16, green: 0.60, blue: 0.52)
        }
    }

    /// Fill of a card or tile: none at rest, a faint wash on hover, the accent wash when selected.
    static func cardFill(selected: Bool, hovered: Bool, tint: Color) -> some ShapeStyle {
        if selected { return AnyShapeStyle(tint.opacity(0.14)) }
        if hovered { return AnyShapeStyle(Color.primary.opacity(0.05)) }
        return AnyShapeStyle(Color.clear)
    }
}

/// A rounded card surface with hover and selection states (Start cards, gallery and category tiles).
struct HomeCardBackground: ViewModifier {
    var selected: Bool
    var tint: Color
    var radius: CGFloat = Tokens.cardCornerRadius
    /// Draws a resting outline (gallery tiles); Start cards have none.
    var outlined = false
    @State private var hovered = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(HomeStyle.cardFill(selected: selected, hovered: hovered, tint: tint)))
            .overlay(shape.strokeBorder(selected ? tint.opacity(0.85) : Color.primary.opacity(outlined ? (hovered ? 0.16 : 0.09) : 0), lineWidth: selected ? 1.5 : 1))
            .contentShape(shape)
            .onHover { hovered = $0 }
            .arcusAnimation(hovered)
            .arcusAnimation(selected)
    }
}

extension View {
    func homeCard(selected: Bool, tint: Color, radius: CGFloat = Tokens.cardCornerRadius, outlined: Bool = false) -> some View {
        modifier(HomeCardBackground(selected: selected, tint: tint, radius: radius, outlined: outlined))
    }
}

/// Section caption ("Start", "Model", a room name): 11 pt semibold, secondary.
struct HomeSectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A plain sidebar row button (Open…, Open Sample Project) with a hover wash.
struct HomeRowButton: View {
    let title: String
    let symbol: String
    var help: String = ""
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 20).foregroundStyle(.secondary)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Tokens.thumbnailCornerRadius, style: .continuous).fill(Color.primary.opacity(hovered ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}
