import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusViewport3D

/// Hosts the Metal 3D coordination viewport for a 3D view, keeping its scene in sync with the model.
final class Viewport3DHost: NSView {
    unowned let state: DocumentState
    let viewID: ElementID
    let viewport: Viewport3DView
    private var buildTask: Task<Void, Never>?
    private var changeToken: UUID?
    private var generation = 0
    /// The saved camera last applied from the model; a new one (Selection Box, camera height edits) moves the viewport. WP6a
    private var modelCamera: Camera3D?
    /// Tools, selection drags and nudges on a level work plane. // W2-3D
    private(set) var tools: Viewport3DToolController!

    init(state: DocumentState, viewID: ElementID) {
        self.state = state
        self.viewID = viewID
        viewport = Viewport3DView(frame: .zero)
        super.init(frame: .zero)
        viewport.translatesAutoresizingMaskIntoConstraints = false
        addSubview(viewport)
        NSLayoutConstraint.activate([
            viewport.leadingAnchor.constraint(equalTo: leadingAnchor), viewport.trailingAnchor.constraint(equalTo: trailingAnchor),
            viewport.topAnchor.constraint(equalTo: topAnchor), viewport.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        if let vd = state.model[viewID]?.view {
            viewport.camera = vd.camera ?? .defaultIsometric
            viewport.homeCamera = vd.camera
            modelCamera = vd.camera
            viewport.visualStyle = vd.visualStyle
            viewport.sectionBox = vd.sectionBoxActive ? vd.sectionBox : nil
            viewport.apply(vd.displayOptions, project: state.model.projectInfo)
        }
        viewport.selectionColor = RGBColor.from(Tokens.selection)
        NotificationCenter.default.addObserver(forName: .arcusCanvasSettingsChanged, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.viewport.selectionColor = RGBColor.from(Tokens.selection) } } // BL-CANVAS
        viewport.onSelect = { [weak self] id, flags in
            guard let self else { return }
            self.state.session.selection.click(id, shift: flags.contains(.shift), command: flags.contains(.command))
        }
        viewport.onHover = { [weak self] id in
            guard let self else { return }
            self.state.session.selection.preselection = id
            self.state.hoverDescription = id.flatMap { self.state.model[$0] }.map { e in
                if let t = self.state.model.type(of: e) { return "\(e.category.displayName) : \(t.typeData?.familyName ?? "") : \(t.name)" }
                return e.category.displayName
            } ?? ""
        }
        viewport.onDoubleClick = { [weak self] id in
            guard let self, let id, let e = self.state.model[id] else { return }
            CommandRouter(state: self.state).doubleClick(e)
        }
        viewport.onSectionBoxChanged = { [weak self] box in
            guard let self else { return }
            self.state.session.perform("Adjust Section Box") { tx in tx.update(self.viewID) { $0.view?.sectionBox = box } }
        }
        viewport.onContextMenu = { [weak self] id, _ in
            guard let self else { return nil }
            if let id, !self.state.session.selection.contains(id) { self.state.session.selection.select([id]) }
            return ContextMenuBuilder(state: self.state, viewID: self.viewID, canvas: nil).menu(for: id)
        }
        tools = Viewport3DToolController(state: state, viewID: viewID, viewport: viewport, host: self) // W2-3D
        changeToken = state.session.onChange { [weak self] _ in self?.rebuild() }
        observeSelection()
        rebuild()
        installCameraControls() // W2-CAM
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func observeSelection() {
        withObservationTracking {
            _ = state.session.selection.ids
            _ = state.session.selection.preselection
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.viewport.selection = self.state.session.selection.set
                self.viewport.preselection = self.state.session.selection.preselection
                self.observeSelection()
            }
        }
    }

    func rebuild() {
        guard let view = state.model[viewID], let vd = view.view else { return }
        viewport.visualStyle = vd.visualStyle
        if vd.camera != modelCamera, let c = vd.camera { modelCamera = c; viewport.camera = c; viewport.homeCamera = c } // WP6a
        viewport.apply(vd.displayOptions, project: state.model.projectInfo)
        viewport.sectionBox = vd.sectionBoxActive ? (vd.sectionBox ?? viewport.sceneBounds) : nil
        viewport.sectionBoxEditable = vd.sectionBoxActive
        generation += 1
        let gen = generation
        buildTask?.cancel()
        let model = state.model
        let temp = state.session.temporaryVisibility[viewID] ?? TemporaryVisibility()
        let box = CancelBox()
        let detail = vd.detailLevel
        buildTask = Task { [weak self] in
            let interval = Signpost.begin("3D scene build")
            let scene = await Task.detached(priority: .userInitiated) {
                SceneBuilder.build(model: model, view: view, temporary: temp, detail: detail, isCancelled: { box.cancelled })
            }.value
            guard let self, !Task.isCancelled, gen == self.generation else { box.cancelled = true; Signpost.end(interval, completed: false); return }
            self.viewport.setScene(scene)
            Signpost.end(interval)
        }
    }

    func zoomExtents() { viewport.zoomExtents(animated: !AccessibilityPrefs.reduceMotion) }

    func saveOrientation() {
        let cam = viewport.camera
        let n = state.model.views.filter { $0.view?.kind == .threeD }.count + 1
        var created: ElementID?
        state.session.perform("Save 3D Orientation") { tx in
            var v = state.model[viewID]?.view ?? ViewData(kind: .threeD)
            v.camera = cam
            created = tx.create(.views, name: "3D View \(n)", data: .view(v))
        }
        if let created { state.show("Saved as “\(state.model[created]?.name ?? "")”.") }
    }

    func applyTemporaryChange() { rebuild() }
}
