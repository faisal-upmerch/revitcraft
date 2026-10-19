import AppKit
import SwiftUI
import ArcusDomain

// COMP: the component preview: 3D (shaded, drag to turn, pinch or the buttons to zoom, Option-drag to pan) or 2D (its
// symbols, or its edges, at a detail level), with Iso, Front, Side, Top and Fit.

struct ComponentPreview: View {
    @Bindable var model: ComponentPanelModel
    let definition: ComponentDefinition
    var height: CGFloat
    @State private var detail: DetailLevel = .medium
    @State private var dragStart: (Double, Double, CGSize)?
    @State private var zoomStart: Double?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let s = max(displayScale, 1)
                let w = Int(geo.size.width * s), h = Int(geo.size.height * s)
                let type = model.selectedType ?? definition.defaultType?.name ?? ""
                let img: CGImage? = model.previewMode == .threeD
                    ? ComponentRenderer.shaded(definition, type: type, values: model.presetValues, yaw: model.yaw, pitch: model.pitch, zoom: model.zoom,
                                               pan: CGSize(width: model.pan.width * s, height: model.pan.height * s), width: w, height: h)
                    : ComponentRenderer.drawing(definition, type: type, view: model.previewView, detail: detail, dark: scheme == .dark, zoom: model.zoom,
                                                pan: CGSize(width: model.pan.width * s, height: model.pan.height * s), width: w, height: h)
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045))
                    if let img { Image(decorative: img, scale: s).resizable().frame(width: geo.size.width, height: geo.size.height) }
                }
                .contentShape(Rectangle())
                .gesture(drag)
                .gesture(MagnifyGesture().onChanged { v in
                    if zoomStart == nil { zoomStart = model.zoom }
                    model.zoom = min(8, max(0.3, (zoomStart ?? 1) * v.magnification))
                }.onEnded { _ in zoomStart = nil })
                .onTapGesture(count: 2) { model.fit() }
                .accessibilityElement()
                .accessibilityLabel("Preview of \(definition.name), \(model.previewMode.rawValue) \(model.previewView.rawValue)")
            }
            .frame(height: height)
            HStack(spacing: 4) {
                Picker("Mode", selection: $model.previewMode) { ForEach(ComponentPreviewMode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer(minLength: 2)
                ForEach(ComponentPreviewView.allCases) { v in
                    Button(v.rawValue) { model.setPreview(v) }
                        .buttonStyle(.borderless).font(.system(size: 10.5, weight: model.previewView == v ? .semibold : .regular))
                        .foregroundStyle(model.previewView == v ? Color.accentColor : Color.secondary)
                }
                Button { model.zoom = max(0.3, model.zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }.buttonStyle(.borderless).help("Zoom Out")
                Button { model.zoom = min(8, model.zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }.buttonStyle(.borderless).help("Zoom In")
                Button { model.fit() } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }.buttonStyle(.borderless).help("Zoom to Fit")
                if model.previewMode == .plan {
                    Picker("Detail Level", selection: $detail) {
                        Text("Coarse").tag(DetailLevel.coarse); Text("Medium").tag(DetailLevel.medium); Text("Fine").tag(DetailLevel.fine)
                    }
                    .labelsHidden().fixedSize().help("Detail Level")
                }
            }
            .controlSize(.small)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2).onChanged { g in
            if dragStart == nil { dragStart = (model.yaw, model.pitch, model.pan) }
            guard let s = dragStart else { return }
            if NSEvent.modifierFlags.contains(.option) || model.previewMode == .plan {
                model.pan = CGSize(width: s.2.width + g.translation.width, height: s.2.height + g.translation.height)
            } else {
                model.yaw = s.0 - Double(g.translation.width) * 0.01
                model.pitch = min(Double.pi / 2 - 0.001, max(-0.3, s.1 + Double(g.translation.height) * 0.01))
            }
        }.onEnded { _ in dragStart = nil }
    }
}

/// The Component Browser: the Components panel at full size in its own window (one per document window).
@MainActor
enum ComponentBrowserWindow {
    private static var windows: [ObjectIdentifier: NSWindow] = [:]

    static func show(_ state: DocumentState) {
        let k = ObjectIdentifier(state)
        if let w = windows[k] { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Component Browser"
        w.subtitle = state.documentName
        w.minSize = NSSize(width: 900, height: 520)
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: ComponentsPanel(state: state, layout: .browser))
        w.setFrameAutosaveName("ArcusComponentBrowser")
        w.center()
        windows[k] = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { _ = windows.removeValue(forKey: k) }
        }
        w.makeKeyAndOrderFront(nil)
    }

    static func isOpen(_ state: DocumentState) -> Bool { windows[ObjectIdentifier(state)] != nil }
    static func close(_ state: DocumentState) { windows[ObjectIdentifier(state)]?.close() }
}
