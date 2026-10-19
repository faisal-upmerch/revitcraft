import SwiftUI
import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusOutput

// F2: the Work Plane dialog, Connect Levels and the Work Plane Viewer (RevitCraft dialogs/mod.rs `work_plane`,
// `connect_levels_dialog`, `work_plane_viewer`).

enum F2Dialog: Equatable {
    /// Work Plane ▸ Set for a view.
    case workPlane(ElementID)
    /// Connect Levels for a stair (nil: the stair being placed).
    case connectLevels(ElementID?)
}

struct F2DialogHost: View {
    let state: DocumentState
    let dialog: F2Dialog
    var body: some View {
        switch dialog {
        case .workPlane(let v): WorkPlaneDialog(state: state, viewID: v)
        case .connectLevels(let s): ConnectLevelsDialog(state: state, stairID: s)
        }
    }
}

/// Work Plane: the current plane, and a new one by name or picked in the view.
struct WorkPlaneDialog: View {
    let state: DocumentState
    let viewID: ElementID
    @State private var choice: WorkPlaneRef?
    @State private var pick = false

    var current: WorkPlaneRef? {
        guard let v = state.model[viewID] else { return nil }
        if let w = WorkPlanes.current(v, state.model) { return w }
        // A 3D view's default is the level its tools draw on.
        if v.view?.kind == .threeD, let l = state.active3DTools?.workPlaneLevel { return .level(l) }
        return nil
    }

    var body: some View {
        let m = state.model
        let planes = WorkPlanes.candidates(m)
        VStack(alignment: .leading, spacing: 10) {
            Text("Work Plane").font(.title3.weight(.semibold))
            GroupBox("Current Work Plane") {
                HStack {
                    Text("Name:").foregroundStyle(.secondary)
                    Text(current.map { WorkPlanes.name($0, m) } ?? (m[viewID]?.view?.kind.isVerticalCut == true ? "View plane" : "<not associated>"))
                    Spacer()
                    Button("Show") { if m[viewID]?.view?.showsWorkPlane != true { WorkPlanes.toggleShown(viewID, in: state.session) } }
                        .help("Shows the work plane grid in this view.")
                }
                .padding(4)
            }
            GroupBox("Specify a new Work Plane") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $pick) {
                        Text("Name").tag(false)
                        Text("Pick a plane").tag(true)
                    }
                    .pickerStyle(.radioGroup).labelsHidden()
                    Picker("Name", selection: Binding(get: { choice ?? current ?? planes.first }, set: { choice = $0 })) {
                        ForEach(planes, id: \.self) { Text(WorkPlanes.name($0, m)).tag(Optional($0)) }
                    }
                    .disabled(pick).frame(width: 320)
                }
                .padding(4)
            }
            HStack {
                Spacer()
                Button("Cancel") { state.presented = nil }.keyboardShortcut(.cancelAction)
                Button("OK") { ok(planes) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    func ok(_ planes: [WorkPlaneRef]) {
        state.presented = nil
        if pick {
            guard let c = CommandRouter(state: state).ctx() else { return }
            let t = WorkPlanePickTool(ctx: c)
            t.targetViewID = viewID // S3D2: a 3D view's own work plane (its tools run in a plan context)
            state.setTool(t)
            return
        }
        guard let w = choice ?? current ?? planes.first else { return }
        WorkPlanes.set(w, on: viewID, in: state.session)
        // In a 3D view a level work plane is also the level its tools draw on.
        if state.model[viewID]?.view?.kind == .threeD, case .level(let l) = w { state.active3DTools?.setWorkPlane(l) }
        state.show("Work plane: \(WorkPlanes.name(w, state.model)).")
    }
}

/// Connect Levels: repeat the stair up to a level above its top (RevitCraft: "Repeat the stair up to:").
struct ConnectLevelsDialog: View {
    let state: DocumentState
    let stairID: ElementID?
    @State private var pick: ElementID??

    /// The stair's top level and current multistory top (the selected stair's, or the stair tool's).
    var stairTop: (top: ElementID?, multistory: ElementID?) {
        if let id = stairID, let s = state.model[id]?.stair { return (s.topLevelID, s.multistoryTopLevelID) }
        if let t = state.activeTool as? StairTool { return (t.topLevelID, t.multistoryTopLevelID) }
        return (nil, nil)
    }

    var body: some View {
        let m = state.model
        let (top, current) = stairTop
        let z = top.flatMap { m[$0]?.level?.elevation }
        let above = z.map { z in m.levels.filter { ($0.level?.elevation ?? -.infinity) > z + Tolerance.length }.sorted { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) } } ?? []
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Levels").font(.title3.weight(.semibold))
            if top == nil {
                Text("Give the stair a Top Level first: a multistory stair repeats from level to level.").foregroundStyle(.secondary)
            } else if above.isEmpty {
                Text("There are no levels above the stair's top level to connect.").foregroundStyle(.secondary)
            } else {
                Text("Repeat the stair up to:")
                List(selection: Binding(get: { pick ?? current }, set: { pick = .some($0) })) {
                    Text("None (single storey)").tag(Optional<ElementID>.none)
                    ForEach(above, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                }
                .listStyle(.bordered)
                .frame(width: 300, height: min(220, CGFloat(above.count + 1) * 24 + 8))
            }
            HStack {
                Spacer()
                Button("Cancel") { state.presented = nil }.keyboardShortcut(.cancelAction)
                Button("OK") { ok() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(top == nil || above.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    func ok() {
        state.presented = nil
        guard let chosen = pick else { return }
        if let id = stairID {
            state.session.perform(chosen == nil ? "Disconnect Levels" : "Connect Levels") { tx in tx.update(id) { $0.stair?.multistoryTopLevelID = chosen } }
            if let e = state.session.lastError { state.show(e.message, error: true); state.session.clearError() }
        } else if let t = state.activeTool as? StairTool {
            t.multistoryTopLevelID = chosen
            state.toolChangedState()
        }
    }
}

// MARK: - Work Plane Viewer

/// Work Plane ▸ Viewer: a small floating window looking straight at the active view's work plane (a level's plan, or
/// a reference plane seen face-on), fitted, following model changes.
@MainActor
enum WorkPlaneViewer {
    private static var panel: NSPanel?

    static func open(_ state: DocumentState, viewID: ElementID, plane: WorkPlaneRef) {
        panel?.close()
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 320), styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "Workplane Viewer – \(WorkPlanes.name(plane, state.model))"
        p.isFloatingPanel = true
        p.hidesOnDeactivate = true
        p.isReleasedWhenClosed = false
        p.contentViewController = NSHostingController(rootView: WorkPlaneViewerView(state: state, plane: plane))
        p.setFrameAutosaveName("ArcusWorkplaneViewer")
        if let w = state.window { p.setFrameTopLeftPoint(NSPoint(x: w.frame.maxX - 440, y: w.frame.maxY - 80)) } else { p.center() }
        panel = p
        p.makeKeyAndOrderFront(nil)
    }
}

struct WorkPlaneViewerView: View {
    let state: DocumentState
    let plane: WorkPlaneRef
    var body: some View {
        let _ = state.session.changeCounter
        let m = state.model
        let graphics = WorkPlanes.viewerView(plane, m).map { ViewGraphicsBuilder(model: m, view: $0).build() }
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            guard let g = graphics, !g.extents.isEmpty else { return }
            let e = g.extents
            let zoom = min((size.width - 20) / max(e.width, 1e-6), (size.height - 20) / max(e.height, 1e-6))
            let cx = (e.min.x + e.max.x) / 2, cy = (e.min.y + e.max.y) / 2
            // View units → points, y up, centred.
            let t = CGAffineTransform(a: zoom, b: 0, c: 0, d: -zoom, tx: size.width / 2 - cx * zoom, ty: size.height / 2 + cy * zoom)
            ctx.withCGContext { cg in
                GraphicsRenderer.drawScreen(g, in: cg, modelToScreen: t, visibleRect: CGRect(origin: .zero, size: size), options: RenderOptions())
            }
        }
        .frame(minWidth: 260, minHeight: 200)
        .overlay {
            if graphics == nil { Text("The work plane has no view to show.").foregroundStyle(.secondary) }
        }
        .accessibilityLabel("Workplane viewer: \(WorkPlanes.name(plane, m))")
    }
}

extension DocumentState {
    /// F2: the active view shows its work plane (Work Plane ▸ Show).
    var f2ShowsWorkPlane: Bool { activeView?.view?.showsWorkPlane ?? false }
}
