import AppKit
import Metal
import QuartzCore
import os
import ArcusGeometry
import ArcusDomain
import ArcusOutput

/// GPU canvas surface: a `CAMetalLayer`-backed view that draws a `MetalCanvasScene` plus an overlay.
///
/// - Frames are produced only when something changed (`requestRedraw()`, or any property setter below), paced by the
///   view's own display link (`NSView.displayLink(target:selector:)`), so ProMotion displays get up to 120 Hz while
///   interacting and the link pauses itself when idle.
/// - Nothing is drawn while the view is hidden, has no window, is zero-sized or its window is fully occluded.
/// - Colours are sRGB (the layer is tagged sRGB; Core Animation colour-matches to P3/other displays).
/// - The view does not handle events (`hitTest` returns nil) — place it underneath the interactive canvas view.
public final class MetalCanvasView: NSView {
    public static var isSupported: Bool { MetalCanvasContext.isSupported }

    /// nil when Metal is unavailable (the view then stays empty; use the CoreGraphics canvas instead).
    public let renderer: MetalCanvasRenderer?
    private let metalLayer = CAMetalLayer()
    private var link: CADisplayLink?
    private var needsFrame = true
    private var idleTicks = 0
    private var buildGeneration = 0
    private var buildCancel: OSAllocatedUnfairLock<Bool>?
    private var occlusionObserver: (any NSObjectProtocol)?
    /// Render even when the window is fully occluded (off-screen capture in the QA harness). Normal use leaves this false.
    public static var drawsWhenOccluded = false

    /// View units → device points of this view (y up, the transform Canvas2DView passes to GraphicsRenderer).
    public var viewToDevice: CGAffineTransform = .identity { didSet { if viewToDevice != oldValue { requestRedraw() } } }
    /// Device points per paper meter (zoom × view scale for model views).
    public var pointsPerPaperMeter: Double = 1 { didSet { if pointsPerPaperMeter != oldValue { requestRedraw() } } }
    /// Main-pass options. Changing colours/highlight/visibility updates small tables only; geometry is never rebuilt.
    public var options: RenderOptions {
        get { renderer?.options ?? RenderOptions() }
        set {
            renderer?.options = newValue
            updateOpacity()
            requestRedraw()
        }
    }
    /// False keeps the layer transparent (CoreGraphics underlay / sheet paper beneath) while `options.background` still
    /// defines the canvas colour for masks and halftone.
    public var paintsBackground: Bool {
        get { renderer?.paintsBackground ?? true }
        set { renderer?.paintsBackground = newValue; updateOpacity(); requestRedraw() }
    }
    /// Selection / preselection tints (shortcut for `options.highlight`).
    public var highlight: [ElementID: ArcusDomain.RGBColor] {
        get { options.highlight }
        set { if newValue != options.highlight { var o = options; o.highlight = newValue; options = o } }
    }
    /// Options of the overlay pass (background is always ignored there — overlays never clear what is underneath).
    public var overlayOptions: RenderOptions {
        get { renderer?.overlayOptions ?? RenderOptions() }
        set { var o = newValue; o.background = nil; renderer?.overlayOptions = o; requestRedraw() }
    }
    public private(set) var scene: MetalCanvasScene?
    public private(set) var lastFrameStats: CanvasFrameStats?
    /// Called on the main thread after each presented frame (CPU stats; GPU time is not waited for).
    public var onFrame: ((CanvasFrameStats) -> Void)?

    public init(frame: NSRect = .zero, context: MetalCanvasContext? = MetalCanvasContext.shared) {
        renderer = context.flatMap { MetalCanvasRenderer(context: $0) }
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        if let renderer {
            metalLayer.device = renderer.context.device
            MetalCanvasRenderer.attach(metalLayer, to: renderer.context)
        }
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.maximumDrawableCount = 3
        metalLayer.isOpaque = true
        metalLayer.needsDisplayOnBoundsChange = false
        metalLayer.contentsGravity = .topLeft
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        link?.invalidate()
        if let o = occlusionObserver { NotificationCenter.default.removeObserver(o) }
        buildCancel?.withLock { $0 = true }
        if let renderer { MetalCanvasRenderer.detach(metalLayer, from: renderer.context) }
    }

    public override func makeBackingLayer() -> CALayer { metalLayer }

    private func updateOpacity() {
        metalLayer.isOpaque = paintsBackground && (options.background.map { $0.a >= 1 } ?? false)
    }
    public override var wantsUpdateLayer: Bool { true }
    public override func updateLayer() {}
    public override var isOpaque: Bool { metalLayer.isOpaque }
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: Content

    public func setScene(_ s: MetalCanvasScene?) {
        scene = s
        renderer?.setScene(s)
        requestRedraw()
    }

    /// Builds a scene for `g` off the main thread and swaps it in when ready (the previous scene stays visible until
    /// then; superseded builds are cancelled and never published).
    public func setGraphics(_ g: ViewGraphics) {
        guard let context = renderer?.context else { return }
        buildGeneration += 1
        let gen = buildGeneration
        buildCancel?.withLock { $0 = true }
        let cancel = OSAllocatedUnfairLock(initialState: false)
        buildCancel = cancel
        Task { [weak self] in
            let s = await Task.detached(priority: .userInitiated) {
                MetalCanvasScene.build(g, context: context, isCancelled: { cancel.withLock { $0 } })
            }.value
            guard let self, gen == self.buildGeneration, let s else { return }
            self.setScene(s)
        }
    }

    /// Replaces the per-frame overlay primitives (tool previews, drag previews). Pass [] to clear.
    public func setOverlay(primitives: [GPrimitive], scale: Int) {
        renderer?.setOverlay(primitives: primitives, scale: scale)
        requestRedraw()
    }

    /// Overlay from a complete display list.
    public func setOverlay(_ g: ViewGraphics?) {
        renderer?.setOverlay(g)
        requestRedraw()
    }

    /// Schedules a frame on the next display refresh.
    public func requestRedraw() {
        needsFrame = true
        idleTicks = 0
        link?.isPaused = false
    }

    // MARK: Display link & sizing

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        if let o = occlusionObserver { NotificationCenter.default.removeObserver(o); occlusionObserver = nil }
        guard let window else { return }
        let l = displayLink(target: self, selector: #selector(step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)   // ProMotion
        l.add(to: .main, forMode: .common)
        link = l
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                                   object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestRedraw() }
        }
        updateDrawableSize()
        requestRedraw()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
        requestRedraw()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
        // Draw immediately so live resizing never shows a stretched frame.
        needsFrame = true
        renderFrame()
    }

    public override func viewDidHide() { super.viewDidHide(); link?.isPaused = true }
    public override func viewDidUnhide() { super.viewDidUnhide(); requestRedraw() }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        if metalLayer.contentsScale != scale { metalLayer.contentsScale = scale }
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        if size.width >= 1, size.height >= 1, metalLayer.drawableSize != size { metalLayer.drawableSize = size }
    }

    private var isDrawable: Bool {
        guard let window, !isHiddenOrHasHiddenAncestor, bounds.width >= 1, bounds.height >= 1 else { return false }
        return Self.drawsWhenOccluded || window.occlusionState.contains(.visible)
    }

    @objc private func step(_ l: CADisplayLink) {
        guard needsFrame else {
            idleTicks += 1
            if idleTicks > 60 { l.isPaused = true }
            return
        }
        // Occluded or hidden: stop ticking; the occlusion/unhide notifications request the frame again.
        guard isDrawable else { l.isPaused = true; return }
        renderFrame()
    }

    private func renderFrame() {
        guard needsFrame, let renderer, isDrawable else { return }
        updateDrawableSize()
        guard let drawable = metalLayer.nextDrawable() else { return }   // retry on the next tick
        needsFrame = false
        let stats = renderer.encode(to: drawable.texture, viewToDevice: viewToDevice, pointsPerPaperMeter: pointsPerPaperMeter,
                                    pixelsPerPoint: Double(metalLayer.contentsScale), drawable: drawable)
        if let stats {
            lastFrameStats = stats
            onFrame?(stats)
        }
    }
}
