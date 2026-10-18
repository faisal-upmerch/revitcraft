import SwiftUI
import AppKit

/// BL-PROPS: a vertical split whose divider position is remembered per user (Properties above the Project Browser).
struct PersistentVSplit<Top: View, Bottom: View>: View {
    /// UserDefaults key of the top pane's share of the height.
    let key: String
    var defaultFraction: Double = 0.5
    var minTop: CGFloat = 200
    var minBottom: CGFloat = 160
    @ViewBuilder let top: Top
    @ViewBuilder let bottom: Bottom
    @AppStorage private var fraction: Double
    @State private var dragStart: Double?
    @State private var hovering = false

    init(key: String, defaultFraction: Double = 0.5, minTop: CGFloat = 200, minBottom: CGFloat = 160,
         @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.key = key; self.defaultFraction = defaultFraction; self.minTop = minTop; self.minBottom = minBottom
        self.top = top(); self.bottom = bottom()
        _fraction = AppStorage(wrappedValue: defaultFraction, key)
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let usable = max(1, h - Self.handle)
            let topH = clampTop(CGFloat(fraction) * usable, in: usable)
            VStack(spacing: 0) {
                top.frame(height: topH)
                divider(usable: usable)
                bottom.frame(maxHeight: .infinity)
            }
        }
    }

    static var handle: CGFloat { 7 }

    func clampTop(_ v: CGFloat, in usable: CGFloat) -> CGFloat {
        guard usable > minTop + minBottom else { return usable * 0.5 }
        return min(max(v, minTop), usable - minBottom)
    }

    func divider(usable: CGFloat) -> some View {
        ZStack {
            Color.clear
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
            Capsule().fill(Color.primary.opacity(hovering || dragStart != nil ? 0.3 : 0)).frame(width: 36, height: 3)
        }
        .frame(height: Self.handle)
        .contentShape(Rectangle())
        .onHover { h in
            hovering = h
            if h { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { g in
            if dragStart == nil { dragStart = fraction }
            let start = CGFloat(dragStart ?? fraction) * usable
            fraction = Double(clampTop(start + g.translation.height, in: usable) / usable)
        }.onEnded { _ in dragStart = nil })
        .onTapGesture(count: 2) { fraction = defaultFraction }
        .accessibilityElement()
        .accessibilityLabel("Split between Properties and Project Browser")
        .accessibilityValue("\(Int(fraction * 100)) percent")
        .accessibilityAdjustableAction { d in
            fraction = min(0.85, max(0.15, fraction + (d == .increment ? 0.05 : -0.05)))
        }
    }
}
