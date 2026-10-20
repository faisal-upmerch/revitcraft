import SwiftUI
import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// FM3D: the Options Bar's Placement Plane while a Furniture tool runs in a 3D view (Revit's Placement Plane): the
/// plane the tool draws on, a menu of the piece's planes that suit the tool, and Pick a Face or Plane to set the work
/// plane to what's clicked next. Picking tools say they follow the face under the pointer.
struct FM3DPlacementOption: View {
    let state: DocumentState
    var body: some View {
        let _ = state.toolRevision
        if let tool = state.activeTool, let ctx = (tool as? BaseTool)?.ctx, let p = ctx.furniture3D, let tools = state.active3DTools {
            let need = FurniturePlacements.need(tool.commandID)
            let follows = need == .face && (tool as? any FurnitureTool3D)?.fm3dPicks == true
            HStack(spacing: 5) {
                Text("Placement Plane").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
                Menu {
                    ForEach(Self.planes(need, state.model), id: \.self) { w in
                        Button(WorkPlanes.name(w, state.model)) { Self.set(w, state) }
                    }
                    Divider()
                    Button("Pick a Face or Plane…") { tools.fm3d.pickingPlane = true; state.show("Click a face or a reference plane to draw on.") }
                } label: {
                    Text(follows ? "Face under the pointer" : Self.title(p, state.model)).font(.system(size: 11))
                }
                .menuStyle(.borderlessButton).controlSize(.small).fixedSize()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Placement plane")
            .help("The plane the tool draws on in 3D. Pick a face or a reference plane, or choose a named plane.")
        }
    }

    /// The plane's name: the work plane set on the view, else the piece's plane it lies on, else the view it's drawn in.
    static func title(_ p: FurniturePlacement3D, _ m: BIMModel) -> String {
        if let r = p.reference { return WorkPlanes.name(r, m) }
        if let b = p.planeBinding(m), abs(b.offset) < 1e-7 { return "Reference Plane : \(b.name)" }
        return m[p.hostViewID]?.name ?? "Work Plane"
    }

    /// The levels and named planes a tool with `need` can draw on.
    static func planes(_ need: FurniturePlacementNeed?, _ m: BIMModel) -> [WorkPlaneRef] {
        WorkPlanes.candidates(m).filter { w in
            guard let f = WorkPlanes.frame(w, m) else { return false }
            let n = f.normal
            switch need {
            case .plan?: return abs(n.z) > 0.999
            case .front?: return abs(abs(n.y) - 1) < 1e-6
            case .vertical?: return abs(n.z) < 1e-6
            default: return true
            }
        }
    }

    @MainActor static func set(_ w: WorkPlaneRef, _ state: DocumentState) {
        guard let v = state.activeViewID else { return }
        WorkPlanes.set(w, on: v, in: state.session)
        CommandRouter(state: state).fm3dWorkPlaneChanged()
    }
}
