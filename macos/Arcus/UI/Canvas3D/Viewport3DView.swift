import AppKit
import Metal
import MetalKit
import QuartzCore
import simd
import ArcusGeometry
import ArcusDomain

/// Real-time Metal coordination viewport for BIM models.
///
/// Draws on demand only (camera, scene, selection or style changes); idle cost is ~0. Scene geometry is batched into
/// a few large private GPU buffers; selection/preselection live in a per-element state buffer so changing them never
/// re-uploads geometry. Picking renders element indices into a small `R32Uint` target around the cursor.
///
/// Encodes with Metal 4 (`MTL4CommandQueue`, argument tables, residency sets) when the GPU supports it and the classic
/// command API otherwise. MSAA and depth attachments are memoryless on Apple GPUs. Optional sun shadows, ambient
/// occlusion and silhouettes; while the camera moves on large displays, MetalFX upscales from a reduced resolution
/// and a full-resolution frame follows as soon as the interaction settles.
@MainActor public final class Viewport3DView: MTKView {
    // MARK: Public state

    public var camera: Camera3D = .defaultIsometric {
        didSet { cameraDidChange() }
    }
    public var visualStyle: VisualStyle = .shaded { didSet { if oldValue != visualStyle { invalidate() } } }
    /// Draws thin darker edges in shaded and consistent-colors styles.
    public var showEdgesInShadedStyles: Bool = true { didSet { invalidate() } }
    public var selection: Set<ElementID> = [] { didSet { if oldValue != selection { statesDirty = true; invalidate(); updateAccessibilityValue() } } }
    public var preselection: ElementID? { didSet { if oldValue != preselection { statesDirty = true; invalidate() } } }
    /// Section box in world coordinates; nil disables clipping.
    public var sectionBox: Box3? { didSet { if oldValue != sectionBox { invalidate() } } }
    /// Shows draggable face handles on the section box.
    public var sectionBoxEditable: Bool = false { didSet { invalidate() } }
    public var reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    public var reduceTransparency: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency { didSet { invalidate() } }
    public var increaseContrast: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast { didSet { invalidate() } }
    public var selectionColor: ArcusDomain.RGBColor = ArcusDomain.RGBColor(hex: 0x2F6FA8) { didSet { invalidate() } }
    public var backgroundTop: ArcusDomain.RGBColor = ArcusDomain.RGBColor(hex: 0xF8F6F2) { didSet { backgroundIsCustom = true; invalidate() } }
    public var backgroundBottom: ArcusDomain.RGBColor = ArcusDomain.RGBColor(hex: 0xDCDBD8) { didSet { backgroundIsCustom = true; invalidate() } }
    /// Camera used by `orient(to: .home)`; nil frames the scene from the southwest.
    public var homeCamera: Camera3D?
    /// Shows the orientation widget (top-right).
    public var showsOrientationWidget: Bool = true { didSet { orientationWidget.isHidden = !showsOrientationWidget } }

    // Graphic display options (View Control Bar).

    /// Directional sun shadows (all styles except Wireframe).
    public var castShadows = false { didSet { if oldValue != castShadows { invalidate() } } }
    /// Screen-space ambient occlusion ("ambient shadows").
    public var ambientOcclusion = false { didSet { if oldValue != ambientOcclusion { invalidate() } } }
    /// Heavy outlines at depth discontinuities.
    public var silhouetteEdges = false { didSet { if oldValue != silhouetteEdges { invalidate() } } }
    /// World direction toward the sun (+Z up), used for shadows and the Realistic style. nil: a key light that
    /// follows the camera (`sunRelativeAngles`).
    public var sunDirection: Vec3? { didSet { if oldValue != sunDirection { invalidate() } } }
    /// Camera-relative light: degrees from behind the viewer toward the left, and altitude.
    public var sunRelativeAngles = SIMD2<Double>(40, 52) { didSet { if oldValue != sunRelativeAngles { invalidate() } } }
    /// Reduced-resolution rendering with MetalFX upscaling while the camera moves.
    public var dynamicResolution: DynamicResolution = .automatic

    public enum DynamicResolution: Sendable { case automatic, always, never }

    /// Command API in use ("Metal 4" or "Metal"), empty without a GPU.
    public var rendererBackend: String { renderer?.backend.rawValue ?? "" }

    /// Compiles the viewport pipelines on a background thread (call at launch so the first 3D view opens instantly).
    public static func prewarmPipelines() { ViewportPipelines.prewarm() }

    public var onSelect: ((ElementID?, NSEvent.ModifierFlags) -> Void)?
    public var onDoubleClick: ((ElementID?) -> Void)?
    public var onHover: ((ElementID?) -> Void)?
    /// Debounced (300 ms after the last change); for saving orientations.
    public var onCameraChanged: ((Camera3D) -> Void)?
    /// Called when a section box face drag ends.
    public var onSectionBoxChanged: ((Box3) -> Void)?
    public var onContextMenu: ((ElementID?, NSEvent) -> NSMenu?)?
    /// Gets left-button and editing-key events first (tools and selection drags on a work plane). // W2-3D
    public weak var pointerHandler: (any Viewport3DPointerHandler)? // W2-3D

    public var statistics: ViewportStatistics {
        var s = stats
        s.triangles = gpuScene?.triangleCount ?? 0
        s.bufferBytes = gpuScene?.bufferBytes ?? 0
        s.elements = gpuScene?.elementCount ?? 0
        s.edges = gpuScene?.edgeCount ?? 0
        s.backend = rendererBackend
        s.renderTargetBytes = renderer?.renderTargetBytes ?? 0
        return s
    }

    /// Bounds of the current scene (empty when nothing is loaded).
    public var sceneBounds: Box3 { gpuScene?.bounds ?? .empty }
    /// Element IDs currently in the scene, in GPU order.
    public var sceneElementIDs: [ElementID] { gpuScene?.elementIDs ?? [] }

    // MARK: Private state

    let renderer: ViewportRenderer?
    private(set) var gpuScene: GPUScene?
    private var states: [UInt8] = []
    private var statesDirty = true
    private var stats = ViewportStatistics()
    private var backgroundIsCustom = false
    let orientationWidget = OrientationWidget(frame: NSRect(x: 0, y: 0, width: 112, height: 128))

    private var animation: (from: Camera3D, to: Camera3D, start: CFTimeInterval, duration: Double)?
    private var cameraNotifyTask: Task<Void, Never>?
    /// Blender-style navigation state (drags, trackpad gestures, fly mode, camera frame). W2-CAM
    let navigation = ViewportNavigation()

    private enum DragMode {
        case none, orbit, pan, sectionHandle(Int)
        var isNone: Bool { if case .none = self { return true }; return false }
    }
    private var dragMode: DragMode = .none
    private var mouseDownPoint: CGPoint = .zero
    private var lastDragPoint: CGPoint = .zero
    private var didDrag = false
    private var mouseDownPick: PickResult?
    var pivot: SIMD3<Double>? // W2-CAM: internal for navigation
    var showPivot = false
    private var handleDragStart: (box: Box3, axisParam: Double)?
    private var hoveredHandle: Int?

    private var hoverInFlight = false
    private var pendingHoverPoint: CGPoint?
    private var zoomPickCache: (point: CGPoint, time: CFTimeInterval, hit: SIMD3<Double>?)?

    /// Last camera input (drag, scroll, gesture, key); drives dynamic resolution.
    private var lastInteraction: CFTimeInterval = 0
    private var settleTask: Task<Void, Never>?
    private var lastFullResolutionGPUms = 0.0
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    // MARK: Init

    public init(frame: CGRect) {
        let device = MTLCreateSystemDefaultDevice()
        renderer = device.flatMap { ViewportRenderer(device: $0) }
        super.init(frame: frame, device: device)
        commonInit()
    }

    /// A viewport on a specific command API (tests and diagnostics).
    init(frame: CGRect, backend: ViewportBackendKind) {
        let device = MTLCreateSystemDefaultDevice()
        renderer = device.flatMap { ViewportRenderer(device: $0, backend: backend) }
        super.init(frame: frame, device: device)
        commonInit()
    }

    public required init(coder: NSCoder) {
        let device = MTLCreateSystemDefaultDevice()
        renderer = device.flatMap { ViewportRenderer(device: $0) }
        super.init(coder: coder)
        self.device = device
        commonInit()
    }

    private func commonInit() {
        // The drawable is single-sampled and has no depth buffer: MSAA color and depth are the renderer's memoryless
        // attachments, resolved into the drawable (or into the post-processing inputs).
        colorPixelFormat = ViewportRenderer.colorFormat
        depthStencilPixelFormat = .invalid
        sampleCount = 1
        clearColor = MTLClearColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        preferredFramesPerSecond = 120
        framebufferOnly = true
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        (layer as? CAMetalLayer)?.maximumDrawableCount = 3
        observeEnvironment()

        orientationWidget.autoresizingMask = [.minXMargin, .minYMargin]
        orientationWidget.basisProvider = { [weak self] in
            guard let self else { return CameraFrame.basis(Camera3D.defaultIsometric) }
            return CameraFrame.basis(self.camera)
        }
        orientationWidget.onOrient = { [weak self] preset in self?.orient(to: preset, animated: true) }
        orientationWidget.onOrientDirection = { [weak self] d in self?.orient(toDirection: Vec3(d.x, d.y, d.z), animated: true) } // BL-SITE
        orientationWidget.onOrbitDrag = { [weak self] dx, dy in
            guard let self else { return }
            self.noteInteraction()
            self.orbit(dx: dx, dy: dy, pivot: self.defaultPivot)
        }
        addSubview(orientationWidget)
        layoutWidget()
        applyAppearanceDefaults()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("3D model view")
        updateAccessibilityValue()
    }

    // MARK: Scene

    /// Replaces the scene. Geometry is re-uploaded only when the scene content changed (revision, element set or
    /// geometry sizes); the camera is kept. Old GPU buffers are released immediately.
    public func setScene(_ scene: Viewport3DScene) {
        guard let renderer else { return }
        if let cur = gpuScene, cur.signature == scene.signature { return }
        let hadScene = gpuScene != nil && !(gpuScene?.bounds.isEmpty ?? true)
        if let old = gpuScene {
            // Free old buffers before allocating new ones (after in-flight frames that read them finish).
            renderer.release(old)
            gpuScene = nil
            renderer.waitIdle()
        }
        let s = renderer.upload(scene)
        gpuScene = s
        stats.lastUploadMilliseconds = s.uploadMilliseconds
        states = Array(repeating: 0, count: s.elementCount)
        statesDirty = true
        if !hadScene && !s.bounds.isEmpty && homeCamera == nil { zoomExtents(animated: false) }
        invalidate()
        updateAccessibilityValue()
    }

    // MARK: Drawing

    func invalidate() {
        needsDisplay = true
        orientationWidget.needsDisplay = true
    }

    var drawablePixelSize: CGSize {
        let s = drawableSize
        if s.width > 0 && s.height > 0 { return s }
        let scale = window?.backingScaleFactor ?? 2
        return CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    private var pointScale: Double {
        let b = bounds.width
        return b > 0 ? Double(drawablePixelSize.width / b) : Double(window?.backingScaleFactor ?? 2)
    }

    private var depthBounds: Box3 {
        var b = gpuScene?.bounds ?? .empty
        if let sb = sectionBox { b.include(sb) }
        return b.isEmpty ? Box3(min: Vec3(-10, -10, -10), max: Vec3(10, 10, 10)) : b
    }

    func cameraFrame(camera: Camera3D? = nil, size: CGSize) -> CameraFrame {
        CameraFrame(camera: navigation.framed(camera ?? self.camera, size: size), aspect: Double(size.width / max(size.height, 1)), // W2-CAM
                    origin: gpuScene?.origin ?? SIMD3(0, 0, 0), depthBounds: depthBounds)
    }

    private func refreshStates() {
        guard statesDirty, let s = gpuScene else { return }
        if states.count != s.elementCount { states = Array(repeating: 0, count: s.elementCount) }
        for i in states.indices { states[i] = 0 }
        for id in selection { if let i = s.indexOf[id] { states[i] |= 1 } }
        if let p = preselection, let i = s.indexOf[p] { states[i] |= 2 }
        statesDirty = false
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight, .accessibilityHighContrastDarkAqua]).map {
            $0 == .darkAqua || $0 == .vibrantDark || $0 == .accessibilityHighContrastDarkAqua
        } ?? false
    }

    /// Uniforms and overlays for a frame of `pixelSize` drawable pixels.
    func frameParams(pixelSize: CGSize, camera cam: Camera3D? = nil, pointScale ps: Double? = nil) -> FrameParams {
        let cf = cameraFrame(camera: cam, size: pixelSize)
        let scale = Float(ps ?? pointScale)
        let dark = isDark
        var u = ViewportUniforms()
        u.viewProj = cf.viewProjectionFloat
        let eyeRel = cf.eye - cf.origin
        u.eye = SIMD4(Float(eyeRel.x), Float(eyeRel.y), Float(eyeRel.z), cf.camera.isPerspective ? 1 : 0)
        u.viewDir = SIMD4(SIMD3<Float>(cf.forward), 0)
        // Key light: above and to the viewer's left, tied to the camera azimuth so both visible sides read differently.
        // Shadows and the Realistic style use the sun instead (world-fixed unless it follows the view).
        let style = visualStyle
        let useSun = (castShadows && style != .wireframe) || style == .realistic
        var light = ShadowMath.cameraKeyLight(forward: cf.forward, right: cf.right, up: cf.up)
        if useSun {
            if let s = sunDirection, simd_length(s.simd) > 1e-9 {
                light = simd_normalize(s.simd)
            } else {
                light = ShadowMath.cameraKeyLight(forward: cf.forward, right: cf.right, up: cf.up,
                                                  azimuthDegrees: sunRelativeAngles.x, altitudeDegrees: sunRelativeAngles.y)
            }
            // Keep a grazing sun above the horizon so shading and shadows stay defined.
            if light.z < 0.02 { light = simd_normalize(SIMD3(light.x, light.y, 0.02)) }
        }
        u.lightDir = SIMD4(SIMD3<Float>(light), 0)
        if cf.camera.isPerspective {
            let ty = tan(cf.camera.fieldOfView / 2), tx = ty * cf.aspect
            u.camRight = SIMD4(SIMD3<Float>(cf.right * tx), 0)
            u.camUp = SIMD4(SIMD3<Float>(cf.up * ty), 0)
        } else {
            u.camRight = SIMD4(SIMD3<Float>(cf.right), 0)
            u.camUp = SIMD4(SIMD3<Float>(cf.up), 0)
        }
        u.backgroundTop = backgroundTop.linear
        u.backgroundBottom = backgroundBottom.linear
        if let sb = sectionBox, !sb.isEmpty {
            let o = cf.origin
            let mn = sb.min.simd - o, mx = sb.max.simd - o
            u.clipPlanes = (SIMD4(1, 0, 0, Float(-mn.x)), SIMD4(-1, 0, 0, Float(mx.x)),
                            SIMD4(0, 1, 0, Float(-mn.y)), SIMD4(0, -1, 0, Float(mx.y)),
                            SIMD4(0, 0, 1, Float(-mn.z)), SIMD4(0, 0, -1, Float(mx.z)))
            u.clipEnabled = 1
        }
        u.selectionColor = selectionColor.linear
        u.preselectColor = selectionColor.mixed(with: .white, amount: 0.35).linear
        u.capColor = (dark ? ArcusDomain.RGBColor(0.24, 0.245, 0.25) : ArcusDomain.RGBColor(0.46, 0.455, 0.45)).linear
        u.faceColor = (dark ? ArcusDomain.RGBColor(hex: 0x2E3033) : ArcusDomain.RGBColor(hex: 0xFCFBF9)).linear
        u.viewport = SIMD2(Float(pixelSize.width), Float(pixelSize.height))
        u.faceAlpha = reduceTransparency ? 0.82 : 0.4
        u.flags = increaseContrast ? 1 : 0
        let contrast: Float = increaseContrast ? 1.45 : 1
        // Line color for styles drawn against the canvas (flips in dark mode); shaded styles always use a darker tint.
        let darkEdge: SIMD4<Float> = dark ? (increaseContrast ? SIMD4(0.95, 0.95, 0.95, 0) : SIMD4(0.72, 0.73, 0.75, 0))
                                          : (increaseContrast ? SIMD4(0, 0, 0, 0) : SIMD4(0.075, 0.08, 0.09, 0))
        let tintEdge = SIMD4<Float>(0.02, 0.02, 0.025, 0)
        switch visualStyle {
        case .wireframe:
            u.style = 0; u.edgeWidth = 1.0 * scale * contrast
            u.edgeColor = increaseContrast ? SIMD4(darkEdge.x, darkEdge.y, darkEdge.z, 0) : SIMD4(darkEdge.x, darkEdge.y, darkEdge.z, 0.3)
        case .hiddenLine:
            u.style = 1; u.edgeWidth = 1.0 * scale * contrast; u.edgeColor = darkEdge
        case .shaded:
            u.style = 2; u.edgeWidth = 0.8 * scale * contrast
            u.edgeColor = SIMD4(tintEdge.x, tintEdge.y, tintEdge.z, increaseContrast ? 0.1 : 0.6)
        case .consistentColors:
            u.style = 3; u.edgeWidth = 0.8 * scale * contrast
            u.edgeColor = SIMD4(tintEdge.x, tintEdge.y, tintEdge.z, increaseContrast ? 0.1 : 0.6)
        case .transparent:
            u.style = 4; u.edgeWidth = 0.9 * scale * contrast
            u.edgeColor = SIMD4(darkEdge.x, darkEdge.y, darkEdge.z, increaseContrast ? 0 : 0.45)
        case .realistic:
            u.style = 5; u.edgeWidth = 0.7 * scale * contrast
            u.edgeColor = SIMD4(tintEdge.x, tintEdge.y, tintEdge.z, increaseContrast ? 0.1 : 0.7)
            u.flags |= ViewportUniforms.flagSky
        }
        if cf.camera.isPerspective {
            u.edgePull = 0.0012
        } else {
            u.edgePull = Float(max(0.002, cf.camera.orthoHeight * 0.0008))
        }
        let overlay = overlayVertices(cf, pixelSize: pixelSize, scale: Double(scale))
        var frame = FrameParams(uniforms: u, style: style, showEdges: showEdgesInShadedStyles, overlay: overlay, shadow: nil)
        applyEffects(&frame, camera: cf, light: light, pointScale: Double(scale), dark: dark)
        return frame
    }

    /// Shadow map request and post-processing parameters for the enabled graphic display options.
    private func applyEffects(_ frame: inout FrameParams, camera cf: CameraFrame, light: SIMD3<Double>, pointScale: Double, dark: Bool) {
        let style = frame.style
        let quality = renderer?.quality ?? ViewportQuality.current()
        if castShadows && style != .wireframe, let scene = gpuScene, !scene.bounds.isEmpty {
            var box = scene.bounds
            if let sb = sectionBox, !sb.isEmpty {
                let i = Box3(min: Vec3(max(box.min.x, sb.min.x), max(box.min.y, sb.min.y), max(box.min.z, sb.min.z)),
                             max: Vec3(min(box.max.x, sb.max.x), min(box.max.y, sb.max.y), min(box.max.z, sb.max.z)))
                if !i.isEmpty { box = i }
            }
            if let m = ShadowMath.lightMatrix(towardLight: light, bounds: box, origin: scene.origin) {
                let size = quality.shadowMapSize
                frame.uniforms.shadowMatrix = m.matrix
                frame.uniforms.flags |= ViewportUniforms.flagShadows
                let texelWorld = max(m.extent.x, m.extent.y) / Double(size)
                frame.uniforms.shadowParams = SIMD4(1 / Float(size), Float(texelWorld * 1.5), Float(0.01 / max(m.extent.z, 1e-3)), 1.25)
                let q = SIMD3<Int32>(Int32((light.x * 2000).rounded()), Int32((light.y * 2000).rounded()), Int32((light.z * 2000).rounded()))
                frame.shadow = ShadowRequest(matrix: m.matrix, key: ShadowKey(sceneSignature: scene.signature, light: q,
                                                                             sectionBox: sectionBox, size: size))
            }
        }
        let occlusionStyles: Set<VisualStyle> = [.hiddenLine, .shaded, .consistentColors, .realistic]
        var p = PostUniforms()
        if cf.camera.isPerspective {
            let ty = tan(cf.camera.fieldOfView / 2)
            p.proj = SIMD4(Float(ty * cf.aspect), Float(ty), Float(cf.depthB), Float(cf.depthA)) // W2-CAM: finite far clip
            p.flags |= PostUniforms.flagPerspective
        } else {
            let h = max(cf.camera.orthoHeight, 1e-4)
            p.proj = SIMD4(Float(h * cf.aspect / 2), Float(h / 2), Float(cf.far), Float(cf.far - cf.near))
        }
        if ambientOcclusion && occlusionStyles.contains(style) {
            p.flags |= PostUniforms.flagAO
            p.ao = SIMD4(1.0, style == .realistic ? 0.9 : 0.8, 0.1, Float(36 * pointScale))
        }
        if silhouetteEdges && style != .wireframe && style != .transparent {
            p.flags |= PostUniforms.flagSilhouettes
            let rel: Float = cf.camera.isPerspective ? 0.02 : 0.003
            p.silhouette = SIMD4(Float(1.25 * pointScale), rel, 0.05, increaseContrast ? 1 : 0.9)
            let ink: SIMD4<Float> = style == .hiddenLine && dark ? SIMD4(0.8, 0.8, 0.82, 1) : SIMD4(0.012, 0.012, 0.015, 1)
            p.silhouetteColor = ink
        }
        frame.post = p
    }

    public override func draw(_ dirtyRect: NSRect) {
        advanceAnimation()
        guard let renderer, let drawable = currentDrawable else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        refreshStates()
        let size = drawableSize
        let params = frameParams(pixelSize: size)
        let scale = renderScale(for: size, frame: params)
        let calls = renderer.drawFrame(scene: gpuScene, frame: params, states: states, drawable: drawable, layer: layer as? CAMetalLayer,
                                       renderScale: scale) { [weak self] ms in
            guard let self else { return }
            self.stats.lastFrameMilliseconds = ms
            if scale >= 1 { self.lastFullResolutionGPUms = ms }
        }
        stats.drawCalls = calls
        stats.renderScale = renderer.lastRenderScale
        stats.framesRendered += 1
        stats.cpuEncodeMilliseconds = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        if renderer.lastRenderScale < 1 { scheduleSettle() }
    }

    // MARK: Interaction and dynamic resolution

    /// True while the camera is being driven (drag, scroll, gesture, key repeat, animation).
    var isInteracting: Bool {
        !dragMode.isNone || animation != nil || CACurrentMediaTime() - lastInteraction < 0.2
    }

    func noteInteraction() {
        lastInteraction = CACurrentMediaTime()
    }

    /// Redraws at full resolution once input stops.
    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let self else { return }
            if self.isInteracting { self.scheduleSettle() } else { self.invalidate() }
        }
    }

    /// Render scale for a frame: below 1 only while interacting on large drawables with costly shading, never with
    /// Reduce Motion (the sharpness change on settle would read as motion).
    func renderScale(for size: CGSize, frame: FrameParams) -> Double {
        guard let renderer, renderer.supportsUpscaling else { return 1 }
        let q = renderer.quality.interactiveScale
        switch dynamicResolution {
        case .never: return 1
        case .always: return q
        case .automatic:
            // Only when full-resolution frames measurably miss a ProMotion budget: on fast GPUs the MetalFX pass costs
            // more than it saves (see the viewport benchmark).
            guard isInteracting, !reduceMotion, Double(size.width * size.height) >= 3_000_000 else { return 1 }
            return lastFullResolutionGPUms > ViewportRenderer.upscaleThresholdMilliseconds ? q : 1
        }
    }

    // MARK: Environment

    private func observeEnvironment() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append((ws, ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                self.increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            }
        }))
        _ = MemoryPressureMonitor.shared
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(forName: MemoryPressureMonitor.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.memoryPressureChanged() }
        }))
        renderer?.quality = ViewportQuality.current(pressure: MemoryPressureMonitor.shared.level)
    }

    isolated deinit {
        for o in observers { o.center.removeObserver(o.token) }
        settleTask?.cancel()
    }

    /// Applies a view's graphic display options; the sun comes from the project location for date/time suns.
    public func apply(_ options: GraphicDisplayOptions, project: ProjectInfoData) {
        castShadows = options.castShadows
        ambientOcclusion = options.ambientShadows
        silhouetteEdges = options.silhouetteEdges
        let sun = options.sun
        sunDirection = sun.worldDirection(latitude: project.latitude, longitude: project.longitude, trueNorthAngle: project.trueNorthAngle)
        if sunDirection == nil { sunRelativeAngles = SIMD2(sun.azimuth, sun.altitude) }
    }

    private func memoryPressureChanged() {
        guard let renderer else { return }
        let level = MemoryPressureMonitor.shared.level
        renderer.quality = ViewportQuality.current(pressure: level)
        if level > .normal { renderer.releaseTransientResources() }
        invalidate()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let renderer else { return }
        if window == nil {
            // Off screen: drop size-dependent targets and let the OS page out the scene until the view returns.
            renderer.waitIdle()
            renderer.releaseTransientResources()
            renderer.setResident(false)
        } else {
            renderer.setResident(true)
            invalidate()
        }
    }

    /// Offscreen render at `size` pixels (default: current drawable size or 1200×800) — works without a window.
    public func snapshot(size: CGSize? = nil) -> CGImage? {
        guard let renderer else { return nil }
        var sz = size ?? drawablePixelSize
        if sz.width < 1 || sz.height < 1 { sz = CGSize(width: 1200, height: 800) }
        refreshStates()
        // Line widths scale like a Retina display of the view's size (2× when the view has no size yet).
        let ps = size == nil ? pointScale : (bounds.width > 0 ? (Double(sz.width) / Double(bounds.width)).clamped(1, 3) : 2)
        let params = frameParams(pixelSize: sz, pointScale: ps)
        return renderer.renderImage(width: Int(sz.width), height: Int(sz.height), scene: gpuScene, frame: params, states: states)
    }

    /// Renders `frames` offscreen frames while orbiting the camera (no readback) and returns per-frame GPU and CPU
    /// encode times in milliseconds. For performance QA.
    public func measureFrameTimes(frames: Int = 120, size: CGSize = CGSize(width: 2560, height: 1600), orbitDegreesPerFrame: Double = 3,
                                  renderScale: Double = 1) -> (gpu: [Double], cpu: [Double]) {
        guard let renderer else { return ([], []) }
        refreshStates()
        let start = camera
        let pivot = defaultPivot
        let result = renderer.benchmark(width: Int(size.width), height: Int(size.height), scene: gpuScene, frames: frames, states: states,
                                        renderScale: renderScale) { i in
            var c = start
            let a = Double(i) * orbitDegreesPerFrame * .pi / 180
            c.eye = Vec3(pivot + rotateVector(start.eye.simd - pivot, axis: SIMD3(0, 0, 1), angle: a))
            c.target = Vec3(pivot + rotateVector(start.target.simd - pivot, axis: SIMD3(0, 0, 1), angle: a))
            c.up = Vec3(rotateVector(start.up.simd, axis: SIMD3(0, 0, 1), angle: a))
            return self.frameParams(pixelSize: size, camera: c, pointScale: 2)
        }
        if let g = result.gpu.last { stats.lastFrameMilliseconds = g }
        stats.drawCalls = renderer.lastDrawCalls
        stats.renderScale = renderer.lastRenderScale
        return result
    }

    // MARK: Layout & appearance

    public override func layout() {
        super.layout()
        layoutWidget()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutWidget()
    }

    private func layoutWidget() {
        let w = orientationWidget.frame.size
        // W4-SHELL: keep clear of a floating inspector (the safe area excludes the docks).
        let safe = safeAreaRect.width > w.width + 16 ? safeAreaRect : bounds
        orientationWidget.setFrameOrigin(NSPoint(x: safe.maxX - w.width - 8, y: safe.maxY - w.height - 8))
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceDefaults()
        invalidate()
    }

    private func applyAppearanceDefaults() {
        guard !backgroundIsCustom else { return }
        let dark = isDark
        let top = dark ? ArcusDomain.RGBColor(hex: 0x3A3C40) : ArcusDomain.RGBColor(hex: 0xF8F6F2)
        let bottom = dark ? ArcusDomain.RGBColor(hex: 0x1F2022) : ArcusDomain.RGBColor(hex: 0xDCDBD8)
        backgroundTop = top; backgroundBottom = bottom
        backgroundIsCustom = false
        orientationWidget.isDark = dark
    }

    public override var isOpaque: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    // MARK: Camera commands

    var viewAspect: Double {
        let s = drawablePixelSize
        return Double(s.width / max(s.height, 1))
    }

    public func zoomExtents(animated: Bool = true) {
        var b = gpuScene?.bounds ?? .empty
        if let sb = sectionBox, !b.isEmpty {
            let i = Box3(min: Vec3(max(b.min.x, sb.min.x), max(b.min.y, sb.min.y), max(b.min.z, sb.min.z)),
                         max: Vec3(min(b.max.x, sb.max.x), min(b.max.y, sb.max.y), min(b.max.z, sb.max.z)))
            if !i.isEmpty { b = i }
        }
        zoom(to: b, animated: animated)
    }

    public func zoom(to box: Box3, animated: Bool = true) {
        guard !box.isEmpty else { return }
        let basis = CameraFrame.basis(camera)
        let c = CameraFit.fit(box, forward: basis.forward, up: basis.up, base: camera, aspect: viewAspect)
        setCamera(c, animated: animated)
    }

    /// Zooms to the bounds of the given elements (e.g. the selection).
    public func zoom(toElements ids: Set<ElementID>, animated: Bool = true) {
        guard let s = gpuScene else { return }
        var b = Box3.empty
        for id in ids { if let i = s.indexOf[id] { b.include(s.elementBounds[i]) } }
        zoom(to: b.expanded(by: 0.25), animated: animated)
    }

    public func orient(to preset: OrientationPreset, animated: Bool = true) {
        let box = sectionBox.map { sb -> Box3 in
            guard let b = gpuScene?.bounds, !b.isEmpty else { return sb }
            let i = Box3(min: Vec3(max(b.min.x, sb.min.x), max(b.min.y, sb.min.y), max(b.min.z, sb.min.z)),
                         max: Vec3(min(b.max.x, sb.max.x), min(b.max.y, sb.max.y), min(b.max.z, sb.max.z)))
            return i.isEmpty ? sb : i
        } ?? (gpuScene?.bounds ?? .empty)
        if preset == .home {
            if let h = homeCamera { setCamera(h, animated: animated); return }
            orient(to: .southWestIso, animated: animated)
            return
        }
        guard let dir = preset.viewFromDirection else { return }
        let fitBox = box.isEmpty ? Box3(min: Vec3(-5, -5, 0), max: Vec3(5, 5, 5)) : box
        var up = preset.up
        if preset == .bottom { up = .unitY }
        let c = CameraFit.fit(fitBox, forward: -dir.simd, up: up.simd, base: camera, aspect: viewAspect)
        setCamera(c, animated: animated)
    }

    /// Switches between perspective and orthographic projection, preserving the apparent framing at the target.
    public func setPerspective(_ perspective: Bool) {
        guard perspective != camera.isPerspective else { return }
        var c = camera
        let dist = simd_length(c.target.simd - c.eye.simd)
        let f = CameraFrame.basis(c).forward
        if perspective {
            let d = c.orthoHeight / 2 / tan(c.fieldOfView / 2)
            c.eye = Vec3(c.target.simd - f * d)
        } else {
            c.orthoHeight = 2 * dist * tan(c.fieldOfView / 2)
        }
        c.isPerspective = perspective
        camera = c
    }

    /// Moves the camera, animated unless Reduce Motion is on or the view is off screen.
    public func setCamera(_ c: Camera3D, animated: Bool) {
        if animated && !reduceMotion && window != nil {
            animation = (camera, c, CACurrentMediaTime(), 0.25)
            isPaused = false
            enableSetNeedsDisplay = false
        } else {
            cancelAnimation()
            camera = c
        }
    }

    func cancelAnimation() {
        guard animation != nil else { return }
        animation = nil
        isPaused = true
        enableSetNeedsDisplay = true
    }

    private func advanceAnimation() {
        guard let a = animation else { return }
        let t = (CACurrentMediaTime() - a.start) / a.duration
        if t >= 1 {
            cancelAnimation()
            camera = a.to
        } else {
            camera = interpolate(a.from, a.to, t: easeOut(t))
        }
    }

    private func cameraDidChange() {
        invalidate()
        pointerHandler?.viewport3DCameraDidChange() // W2-3D
        updateAccessibilityValue()
        cameraNotifyTask?.cancel()
        guard onCameraChanged != nil else { return }
        cameraNotifyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.onCameraChanged?(self.camera)
        }
    }

    var defaultPivot: SIMD3<Double> {
        if let b = gpuScene?.bounds, !b.isEmpty {
            if let sb = sectionBox, sb.intersects(b) {
                return Box3(min: Vec3(max(b.min.x, sb.min.x), max(b.min.y, sb.min.y), max(b.min.z, sb.min.z)),
                            max: Vec3(min(b.max.x, sb.max.x), min(b.max.y, sb.max.y), min(b.max.z, sb.max.z))).center.simd
            }
            return b.center.simd
        }
        return camera.target.simd
    }

    /// Orbits (turntable about world Z, then tilt about the camera right axis) around `pivot`. Angles in points of drag.
    func orbit(dx: Double, dy: Double, pivot: SIMD3<Double>) {
        let k = 0.45 * .pi / 180
        var c = camera
        let yaw = -dx * k
        var eye = pivot + rotateVector(c.eye.simd - pivot, axis: SIMD3(0, 0, 1), angle: yaw)
        var target = pivot + rotateVector(c.target.simd - pivot, axis: SIMD3(0, 0, 1), angle: yaw)
        var up = rotateVector(c.up.simd, axis: SIMD3(0, 0, 1), angle: yaw)
        c.eye = Vec3(eye); c.target = Vec3(target); c.up = Vec3(up)
        // Tilt: dragging down raises the camera (see more from above). Clamp elevation to ±90°.
        let basis = CameraFrame.basis(c)
        let elevation = asin(max(-1, min(1, -basis.forward.z)))
        var pitch = dy * k
        let maxEl = Double.pi / 2
        pitch = max(-maxEl - elevation, min(maxEl - elevation, -pitch))
        let axis = basis.right
        eye = pivot + rotateVector(eye - pivot, axis: axis, angle: -pitch)
        target = pivot + rotateVector(target - pivot, axis: axis, angle: -pitch)
        up = rotateVector(basis.up, axis: axis, angle: -pitch)
        let f = simd_normalize(target - eye)
        if abs(f.z) < 0.9995 {
            // Keep the horizon level away from the poles.
            up = simd_normalize(SIMD3(0, 0, 1) - f * f.z)
        }
        c.eye = Vec3(eye); c.target = Vec3(target); c.up = Vec3(up)
        camera = c
    }

    /// Pans by a view-space delta in points.
    func pan(dx: Double, dy: Double, depthPoint: SIMD3<Double>?) {
        let cf = cameraFrame(size: drawablePixelSize)
        let p = depthPoint ?? camera.target.simd
        let s = cf.worldPerPoint(at: p, viewHeight: Double(bounds.height))
        let delta = cf.right * (-dx * s) + cf.up * (-dy * s)
        var c = camera
        c.eye = Vec3(c.eye.simd + delta); c.target = Vec3(c.target.simd + delta)
        camera = c
    }

    /// Zooms by `factor` (>1 = closer) keeping the point under `point` (view coordinates) fixed.
    func zoom(factor: Double, at point: CGPoint, hit: SIMD3<Double>?) {
        guard factor.isFinite, factor > 0 else { return }
        let size = bounds.size
        let cf = cameraFrame(size: drawablePixelSize)
        var c = camera
        if c.isPerspective {
            let focal = max(dot(c.target.simd - c.eye.simd, cf.forward), 0.05)
            let ray = cf.ray(at: point, size: size)
            let p = hit ?? (ray.origin + ray.direction * (focal / max(dot(ray.direction, cf.forward), 0.1)))
            var t = 1 - 1 / factor
            t = min(t, 0.9)
            let move = (p - c.eye.simd) * t
            let newEye = c.eye.simd + move
            c.eye = Vec3(newEye)
            c.target = Vec3(newEye + cf.forward * max(focal * (1 - t), 0.05))
        } else {
            let nx = Double(point.x / max(size.width, 1)) * 2 - 1
            let ny = Double(point.y / max(size.height, 1)) * 2 - 1
            let h = c.orthoHeight, w = h * cf.aspect
            let newH = min(max(h / factor, 0.05), 1e6)
            let newW = newH * cf.aspect
            let shift = cf.right * (nx * (w - newW) / 2) + cf.up * (ny * (h - newH) / 2)
            c.orthoHeight = newH
            c.eye = Vec3(c.eye.simd + shift); c.target = Vec3(c.target.simd + shift)
        }
        camera = c
    }

    // MARK: Picking

    private func pixel(for point: CGPoint) -> CGPoint {
        let s = drawablePixelSize
        let sx = s.width / max(bounds.width, 1), sy = s.height / max(bounds.height, 1)
        return CGPoint(x: point.x * sx, y: (bounds.height - point.y) * sy)
    }

    /// Synchronous GPU pick at a view point.
    func pickNow(at point: CGPoint) -> PickResult {
        guard let renderer, let s = gpuScene, s.elementCount > 0 else { return PickResult() }
        refreshStates()
        let size = drawablePixelSize
        let u = frameParams(pixelSize: size).uniforms
        var result = PickResult()
        renderer.pick(at: pixel(for: point), viewport: size, scene: s, uniforms: u, style: visualStyle, states: states, wait: true) { result = $0 }
        return result
    }

    /// Element under a view point (nil for background).
    public func element(at point: CGPoint) -> ElementID? {
        guard let i = pickNow(at: point).elementIndex, let s = gpuScene, i >= 0, i < s.elementCount else { return nil }
        return s.elementIDs[i]
    }

    /// World surface point under a view point.
    public func surfacePoint(at point: CGPoint) -> Vec3? { pickNow(at: point).position.map { Vec3($0) } }

    private func elementID(_ r: PickResult?) -> ElementID? {
        guard let i = r?.elementIndex, let s = gpuScene, i >= 0, i < s.elementCount else { return nil }
        return s.elementIDs[i]
    }

    private func hoverPick(at point: CGPoint) {
        guard let renderer, let s = gpuScene, s.elementCount > 0 else { return }
        if hoverInFlight { pendingHoverPoint = point; return }
        hoverInFlight = true
        refreshStates()
        let size = drawablePixelSize
        let u = frameParams(pixelSize: size).uniforms
        let sceneRef = s
        renderer.pick(at: pixel(for: point), viewport: size, scene: s, uniforms: u, style: visualStyle, states: states, wait: false) { [weak self] r in
            guard let self else { return }
            self.hoverInFlight = false
            if let next = self.pendingHoverPoint {
                self.pendingHoverPoint = nil
                self.hoverPick(at: next)
                return
            }
            guard self.gpuScene === sceneRef, self.dragMode.isNone else { return }
            let id = self.elementID(r)
            if id != self.preselection {
                self.preselection = id
                self.onHover?(id)
            }
        }
    }

    // MARK: Section box handles

    private static let handleDirections: [SIMD3<Double>] = [SIMD3(-1, 0, 0), SIMD3(1, 0, 0), SIMD3(0, -1, 0), SIMD3(0, 1, 0), SIMD3(0, 0, -1), SIMD3(0, 0, 1)]

    private func handleCenter(_ i: Int, box: Box3) -> SIMD3<Double> {
        let c = box.center.simd
        let d = Viewport3DView.handleDirections[i]
        let half = (box.max.simd - box.min.simd) / 2
        return c + d * half
    }

    private func handleTip(_ i: Int, box: Box3, frame cf: CameraFrame) -> SIMD3<Double> {
        let p = handleCenter(i, box: box)
        let s = cf.worldPerPoint(at: p, viewHeight: Double(bounds.height))
        return p + Viewport3DView.handleDirections[i] * (s * 22)
    }

    private func handleHit(at point: CGPoint) -> Int? {
        guard sectionBoxEditable, let box = sectionBox, !box.isEmpty else { return nil }
        let cf = cameraFrame(size: drawablePixelSize)
        var best: (Int, Double)?
        for i in 0..<6 {
            for p in [handleCenter(i, box: box), handleTip(i, box: box, frame: cf)] {
                guard let s = cf.project(p, size: bounds.size) else { continue }
                let d = hypot(Double(s.x - point.x), Double(s.y - point.y))
                if d < 10, d < (best?.1 ?? .infinity) { best = (i, d) }
            }
        }
        return best?.0
    }

    /// Parameter along the handle axis closest to the mouse ray.
    private func axisParameter(handle i: Int, box: Box3, point: CGPoint) -> Double? {
        let cf = cameraFrame(size: drawablePixelSize)
        let ray = cf.ray(at: point, size: bounds.size)
        let p0 = handleCenter(i, box: box), d = Viewport3DView.handleDirections[i]
        let w0 = p0 - ray.origin
        let a = dot(d, d), b = dot(d, ray.direction), c = dot(ray.direction, ray.direction)
        let dd = dot(d, w0), e = dot(ray.direction, w0)
        let denom = a * c - b * b
        guard abs(denom) > 1e-9 else { return nil }
        return (b * e - c * dd) / denom
    }

    /// View-space locations (points, bottom-left origin) of the six section box face handles
    /// (−X, +X, −Y, +Y, −Z, +Z); nil entries are behind the camera. Empty when the box is not editable.
    public func sectionBoxHandlePoints() -> [CGPoint?] {
        guard sectionBoxEditable, let box = sectionBox, !box.isEmpty else { return [] }
        let cf = cameraFrame(size: drawablePixelSize)
        return (0..<6).map { cf.project(handleCenter($0, box: box), size: bounds.size) }
    }

    private func overlayVertices(_ cf: CameraFrame, pixelSize: CGSize, scale: Double) -> [OverlayVertex] {
        var v: [OverlayVertex] = []
        let o = cf.origin
        func rel(_ p: SIMD3<Double>) -> SIMD4<Float> { SIMD4(Float(p.x - o.x), Float(p.y - o.y), Float(p.z - o.z), 1) }
        func premul(_ c: ArcusDomain.RGBColor, _ a: Double) -> SIMD4<Float> { let l = c.linear; let af = Float(a); return SIMD4(l.x * af, l.y * af, l.z * af, af) }
        func line(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ color: SIMD4<Float>, _ width: Double) {
            let ra = rel(a), rb = rel(b)
            let w = Float(width * scale)
            let q = [(ra, rb, Float(-1)), (ra, rb, Float(1)), (rb, ra, Float(1)), (ra, rb, Float(-1)), (rb, ra, Float(1)), (rb, ra, Float(-1))]
            for (p, other, side) in q {
                v.append(OverlayVertex(a: p, b: other, color: color, offset: SIMD2(side, 0), width: w, mode: 0))
            }
        }
        func marker(_ p: SIMD3<Double>, _ color: SIMD4<Float>, _ size: Double) {
            let r = rel(p)
            let h = Float(size * scale / 2)
            let corners: [SIMD2<Float>] = [SIMD2(-h, -h), SIMD2(h, -h), SIMD2(h, h), SIMD2(-h, -h), SIMD2(h, h), SIMD2(-h, h)]
            for c in corners { v.append(OverlayVertex(a: r, b: r, color: color, offset: c, width: 0, mode: 1)) }
        }
        let dark = isDark
        if let box = sectionBox, !box.isEmpty {
            let c = box.corners.map(\.simd)
            let edges = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
            let col = premul(dark ? ArcusDomain.RGBColor(hex: 0x8FB8DE) : selectionColor, 0.85)
            for (a, b) in edges { line(c[a], c[b], col, 1.25) }
            if sectionBoxEditable {
                for i in 0..<6 {
                    let p = handleCenter(i, box: box)
                    let tip = handleTip(i, box: box, frame: cf)
                    let hot = hoveredHandle == i || { if case .sectionHandle(let h) = dragMode { return h == i }; return false }()
                    let accent = premul(selectionColor, 1)
                    line(p, tip, accent, hot ? 3 : 2)
                    marker(p, premul(.white, 1), hot ? 13 : 11)
                    marker(p, accent, hot ? 9 : 7)
                    marker(tip, premul(.white, 1), hot ? 9 : 7)
                    marker(tip, accent, hot ? 6 : 4)
                }
            }
        }
        if showPivot, let p = pivot {
            marker(p, premul(.white, 0.9), 9)
            marker(p, premul(selectionColor, 1), 5)
        }
        return v
    }

    // MARK: Mouse

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if navigationMouseDown(event) { return } // W2-CAM: ⌥-drag navigation, fly mode confirm
        if pointerHandler?.viewport3DMouseDown(event, at: convert(event.locationInWindow, from: nil)) == true { return } // W2-3D
        let p = convert(event.locationInWindow, from: nil)
        mouseDownPoint = p; lastDragPoint = p; didDrag = false
        cancelAnimation()
        if let h = handleHit(at: p), let box = sectionBox {
            dragMode = .sectionHandle(h)
            handleDragStart = (box, axisParameter(handle: h, box: box, point: p) ?? 0)
            invalidate()
            return
        }
        mouseDownPick = pickNow(at: p)
        dragMode = event.modifierFlags.contains(.shift) ? .pan : .orbit
        pivot = mouseDownPick?.position ?? defaultPivot
        if event.clickCount == 2 {
            onDoubleClick?(elementID(mouseDownPick))
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        if navigationMouseDragged(event) { return } // W2-CAM
        let p = convert(event.locationInWindow, from: nil)
        if pointerHandler?.viewport3DMouseDragged(event, at: p) == true { return } // W2-3D
        if !didDrag && hypot(p.x - mouseDownPoint.x, p.y - mouseDownPoint.y) < 3 { return }
        if !didDrag, preselection != nil { preselection = nil; onHover?(nil) }
        didDrag = true
        let dx = Double(p.x - lastDragPoint.x), dy = Double(p.y - lastDragPoint.y)
        lastDragPoint = p
        noteInteraction()
        switch dragMode {
        case .orbit:
            showPivot = true
            orbit(dx: dx, dy: dy, pivot: pivot ?? defaultPivot)
        case .pan:
            pan(dx: dx, dy: dy, depthPoint: pivot)
        case .sectionHandle(let h):
            guard let start = handleDragStart, let s = axisParameter(handle: h, box: start.box, point: p) else { return }
            sectionBox = resized(start.box, handle: h, by: s - start.axisParam)
        case .none:
            break
        }
    }

    public override func mouseUp(with event: NSEvent) {
        if navigationMouseUp(event) { return } // W2-CAM
        if pointerHandler?.viewport3DMouseUp(event, at: convert(event.locationInWindow, from: nil)) == true { return } // W2-3D
        defer {
            dragMode = .none; showPivot = false; handleDragStart = nil; mouseDownPick = nil
            invalidate()
        }
        if case .sectionHandle = dragMode {
            if didDrag, let b = sectionBox { onSectionBoxChanged?(b) }
            return
        }
        if !didDrag && event.clickCount < 2 {
            onSelect?(elementID(mouseDownPick), event.modifierFlags)
        }
    }

    private func resized(_ box: Box3, handle h: Int, by delta: Double) -> Box3 {
        var b = box
        let minSize = 0.05
        switch h {
        case 0: b.min.x = min(box.min.x - delta, box.max.x - minSize)
        case 1: b.max.x = max(box.max.x + delta, box.min.x + minSize)
        case 2: b.min.y = min(box.min.y - delta, box.max.y - minSize)
        case 3: b.max.y = max(box.max.y + delta, box.min.y + minSize)
        case 4: b.min.z = min(box.min.z - delta, box.max.z - minSize)
        default: b.max.z = max(box.max.z + delta, box.min.z + minSize)
        }
        return b
    }

    // W2-CAM: middle-button navigation lives in Viewport3DView+Navigation.swift.
    public override func otherMouseDown(with event: NSEvent) { if !navigationOtherMouseDown(event) { super.otherMouseDown(with: event) } }
    public override func otherMouseDragged(with event: NSEvent) { if !navigationOtherMouseDragged(event) { super.otherMouseDragged(with: event) } }
    public override func otherMouseUp(with event: NSEvent) { if !navigationOtherMouseUp(event) { super.otherMouseUp(with: event) } }

    public override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        let id = element(at: p)
        return onContextMenu?(id, event)
    }

    public override func mouseMoved(with event: NSEvent) {
        if navigationMouseMoved(event) { return } // W2-CAM: fly mode mouse-look
        let p = convert(event.locationInWindow, from: nil)
        if pointerHandler?.viewport3DMouseMoved(event, at: p) == true { return } // W2-3D
        let h = handleHit(at: p)
        if h != hoveredHandle { hoveredHandle = h; invalidate() }
        if h != nil {
            if preselection != nil { preselection = nil; onHover?(nil) }
            return
        }
        hoverPick(at: p)
    }

    public override func mouseExited(with event: NSEvent) {
        pendingHoverPoint = nil
        if hoveredHandle != nil { hoveredHandle = nil; invalidate() }
        if preselection != nil { preselection = nil; onHover?(nil) }
    }

    // MARK: Scroll, gestures, keys

    func zoomHit(at p: CGPoint) -> SIMD3<Double>? {
        let now = CACurrentMediaTime()
        if let c = zoomPickCache, hypot(c.point.x - p.x, c.point.y - p.y) < 2, now - c.time < 0.4 {
            zoomPickCache = (p, now, c.hit)
            return c.hit
        }
        let hit = pickNow(at: p).position
        zoomPickCache = (p, now, hit)
        return hit
    }

    // W2-CAM: scroll, pinch and rotate gestures live in Viewport3DView+Navigation.swift.
    public override func scrollWheel(with event: NSEvent) { navigationScroll(event) }
    public override func magnify(with event: NSEvent) { navigationMagnify(event) }
    public override func rotate(with event: NSEvent) { navigationRotate(event) }

    public override func keyDown(with event: NSEvent) {
        if handleNavigationKey(event) { return } // W2-CAM: keypad views, ⇧F fly, fly keys
        if pointerHandler?.viewport3DKeyDown(event) == true { return } // W2-3D
        let step = 15.0 / 0.45
        if (123...126).contains(event.keyCode) { noteInteraction() }
        switch event.keyCode {
        case 123: orbit(dx: -step, dy: 0, pivot: defaultPivot)        // ←
        case 124: orbit(dx: step, dy: 0, pivot: defaultPivot)         // →
        case 125: orbit(dx: 0, dy: step * 0.66, pivot: defaultPivot)  // ↓
        case 126: orbit(dx: 0, dy: -step * 0.66, pivot: defaultPivot) // ↑
        case 53:                                                       // Escape
            if preselection != nil { preselection = nil; onHover?(nil) } else { super.keyDown(with: event) }
        default:
            switch event.charactersIgnoringModifiers {
            case "+", "=": zoom(factor: 1.25, at: CGPoint(x: bounds.midX, y: bounds.midY), hit: nil)
            case "-", "_": zoom(factor: 1 / 1.25, at: CGPoint(x: bounds.midX, y: bounds.midY), hit: nil)
            case "f" where event.modifierFlags.intersection([.command, .control, .option]).isEmpty: zoomExtents()
            case "F" where event.modifierFlags.intersection([.command, .control, .option]).isEmpty: zoomExtents()
            default: super.keyDown(with: event)
            }
        }
    }

    // MARK: Accessibility

    private func updateAccessibilityValue() {
        let n = selection.count
        let sel = n == 0 ? "No elements selected" : n == 1 ? "1 element selected" : "\(n) elements selected"
        let proj = camera.isPerspective ? "Perspective" : "Orthographic"
        let basis = CameraFrame.basis(camera)
        let from = -basis.forward
        var dirs: [String] = []
        if from.y > 0.3 { dirs.append("north") } else if from.y < -0.3 { dirs.append("south") }
        if from.x > 0.3 { dirs.append("east") } else if from.x < -0.3 { dirs.append("west") }
        let facing: String
        if from.z > 0.95 { facing = "looking down from the top" } else if from.z < -0.95 { facing = "looking up from below" }
        else { facing = "viewed from the " + (dirs.isEmpty ? "side" : dirs.joined(separator: "-")) + (from.z > 0.2 ? ", above" : "") }
        let count = gpuScene?.elementCount ?? 0
        setAccessibilityValue("\(proj), \(facing). \(count) elements shown. \(sel). \(visualStyle.rawValue) style.")
    }

    public override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions = OrientationPreset.allCases.map { preset in
            NSAccessibilityCustomAction(name: "Orient to \(preset.title)") { [weak self] in
                self?.orient(to: preset, animated: false); return true
            }
        }
        actions.append(NSAccessibilityCustomAction(name: "Zoom to fit") { [weak self] in self?.zoomExtents(animated: false); return true })
        return actions
    }

    public override func accessibilityChildren() -> [Any]? {
        showsOrientationWidget ? [orientationWidget] : []
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
