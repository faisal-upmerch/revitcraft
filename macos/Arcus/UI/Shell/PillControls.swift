import AppKit
import SwiftUI

// PILLS: the shared selected / hovered capsule (`PillHighlight`), a segmented control drawn to the pill spec
// (`PillSegmented`), and the rule that content swapped by a state change never cross-fades (`InstantContent`).
// Geometry and fills come from `PillSpec` (DesignTokens.swift).

/// How a selected capsule is filled.
enum PillSelectionStyle {
    /// A neutral wash (ribbon tabs).
    case neutral
    /// A tinted wash with a thin edge in the tint (the active view tab, a contextual tab, an "on" toggle).
    case tint(Color)
    /// A raised segment: a light surface with a soft shadow in light mode, a brighter wash in dark mode.
    case raised
    /// A solid fill in the tint, for content drawn in white (list rows, filter chips).
    case solid(Color)
}

/// The selected or hovered capsule behind a control. Apply it to the padded content (the capsule takes its frame),
/// then pad by `PillSpec.inset` from the container. Hover uses the same shape, so nothing jumps.
struct PillHighlight: ViewModifier {
    var selected: Bool
    var style: PillSelectionStyle = .neutral
    /// Nil: a capsule. Otherwise the corner radius (use `PillSpec.radius(inside:)` for concentric corners).
    var cornerRadius: CGFloat? = nil
    var hoverable = true
    /// A resting outline when not selected (the contextual tab while another tab is chosen).
    var restingEdge: Color? = nil
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = PillShape(radius: cornerRadius)
        content
            .background {
                if selected {
                    fill(shape)
                } else if hovering && hoverable {
                    shape.fill(Color.primary.opacity(PillSpec.hoverOpacity))
                } else if let restingEdge {
                    shape.strokeBorder(restingEdge, lineWidth: 1)
                }
            }
            .contentShape(shape)
            .onHover { h in
                guard hoverable else { return }
                if AccessibilityPrefs.reduceMotion { hovering = h } else { withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
            }
    }

    @ViewBuilder private func fill(_ shape: PillShape) -> some View {
        switch style {
        case .neutral:
            shape.fill(Color.primary.opacity(PillSpec.selectedOpacity + (hovering && hoverable ? 0.03 : 0)))
        case .tint(let c):
            shape.fill(c.opacity(PillSpec.tintOpacity + (hovering && hoverable ? 0.05 : 0)))
                .overlay(shape.strokeBorder(c.opacity(PillSpec.tintEdgeOpacity), lineWidth: 1))
        case .raised:
            if scheme == .dark {
                shape.fill(Color.white.opacity(0.17)).overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
            } else {
                shape.fill(Color.white).shadow(color: .black.opacity(0.14), radius: 1.2, y: 0.6)
                    .overlay(shape.strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5))
            }
        case .solid(let c):
            shape.fill(c)
        }
    }
}

extension View {
    /// The pill spec's selected / hovered capsule behind this (already padded) content.
    func pillHighlight(_ selected: Bool, _ style: PillSelectionStyle = .neutral, cornerRadius: CGFloat? = nil, hoverable: Bool = true,
                       restingEdge: Color? = nil) -> some View {
        modifier(PillHighlight(selected: selected, style: style, cornerRadius: cornerRadius, hoverable: hoverable, restingEdge: restingEdge))
    }
}

/// A capsule, or a continuous rounded rectangle of a given radius.
nonisolated struct PillShape: InsettableShape {
    var radius: CGFloat?
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        guard let radius else { return Capsule(style: .circular).path(in: r) } // continuous capsules draw a flat, notched end on their edge
        return RoundedRectangle(cornerRadius: max(0, radius - inset), style: .continuous).path(in: r)
    }
    func inset(by amount: CGFloat) -> PillShape { var s = self; s.inset += amount; return s }
}

extension View {
    /// A menu in the bottom pill (scale, detail level, visual style, selection filter): a 28 pt capsule with room
    /// either side of its label and arrow; add `pillHighlight` for its hover or "on" state.
    func barMenuItem() -> some View {
        padding(.horizontal, 8).frame(minWidth: PillSpec.shellItemHeight).frame(height: PillSpec.shellItemHeight)
    }
}

// MARK: - Segmented control

/// One choice of a `PillSegmented`.
struct PillOption<Value: Hashable>: Identifiable {
    let value: Value
    var title: String
    var symbol: String? = nil
    /// Tooltip (and the accessibility label of an icon-only segment).
    var help: String? = nil
    var id: Value { value }
}

/// A segmented control drawn to the pill spec: a capsule track, segments `PillSpec.trackInset` inside it, 12 pt side
/// padding, and a raised capsule on the chosen one. Used in the shell, Home, the libraries and dialogs, so every
/// segmented choice in Arcus looks and spaces the same.
struct PillSegmented<Value: Hashable>: View {
    enum Size {
        case small, regular, large
        var track: CGFloat { switch self { case .small: 24; case .regular: 28; case .large: 32 } }
        var font: CGFloat { switch self { case .small: 11; case .regular: 12; case .large: 13 } }
        var symbol: CGFloat { switch self { case .small: 11; case .regular: 12.5; case .large: 13.5 } }
        /// Icon-only segments are square-ish capsules: this much padding each side of the glyph.
        var iconPadding: CGFloat { switch self { case .small: 7; case .regular: 8; case .large: 9 } }
    }

    @Binding var selection: Value
    let options: [PillOption<Value>]
    var size: Size = .regular
    var label: String = ""
    /// Segments share the track's width equally (a tab-like row across a dialog); otherwise each hugs its title.
    var fill = false
    @Environment(\.isEnabled) private var enabled

    init(selection: Binding<Value>, options: [PillOption<Value>], size: Size = .regular, label: String = "", fill: Bool = false) {
        _selection = selection; self.options = options; self.size = size; self.label = label; self.fill = fill
    }

    /// Plain titled segments: `PillSegmented(selection: $x, [(a, "A"), (b, "B")])`.
    init(selection: Binding<Value>, _ titles: [(Value, String)], size: Size = .regular, label: String = "", fill: Bool = false) {
        self.init(selection: selection, options: titles.map { PillOption(value: $0.0, title: $0.1) }, size: size, label: label, fill: fill)
    }

    var body: some View {
        let inner = PillSpec.height(in: size.track, inset: PillSpec.trackInset)
        HStack(spacing: PillSpec.gap) {
            ForEach(options) { o in segment(o, height: inner) }
        }
        .padding(PillSpec.trackInset)
        .frame(height: size.track)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5))
        .fixedSize(horizontal: !fill, vertical: true)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func segment(_ o: PillOption<Value>, height: CGFloat) -> some View {
        let on = o.value == selection
        return Button { selection = o.value } label: {
            HStack(spacing: 5) {
                if let s = o.symbol { Image(systemName: s).font(.system(size: size.symbol, weight: .medium)) }
                if !o.title.isEmpty { Text(o.title).font(.system(size: size.font, weight: .medium)).lineLimit(1) }
            }
            .foregroundStyle(on ? Color.primary : Color.secondary)
            .padding(.horizontal, o.title.isEmpty ? size.iconPadding : PillSpec.padding)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: height)
            .pillHighlight(on, .raised)
        }
        .buttonStyle(.plain)
        .help(o.help ?? "")
        .accessibilityLabel(o.title.isEmpty ? (o.help ?? "") : o.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - No cross-fades

/// Content that a state change swaps (the ribbon's panels, the status prompt, the Options Bar's controls) switches in
/// one frame: an animation in flight around it (a pill sliding in as a tool starts) moves the pill, but never
/// cross-fades the old and the new content over each other.
struct InstantContent<Key: Equatable>: ViewModifier {
    let name: String
    let key: Key
    func body(content: Content) -> some View {
        content.transaction(value: key) { t in t.animation = nil; t.disablesAnimations = true }
    }
}

extension View {
    /// Swaps this content instantly whenever `key` changes, whatever animation the change happens in.
    func instantContent<K: Equatable>(_ name: String, key: K) -> some View { modifier(InstantContent(name: name, key: key)) }
}
