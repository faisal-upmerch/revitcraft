import SwiftUI
import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// Options Bar control shown while a tool runs in a 3D view: the level whose plane the tool draws on (W2-3D).
struct WorkPlaneOption3D: View {
    let state: DocumentState
    var body: some View {
        let _ = state.toolRevision
        if (state.activeTool as? BaseTool)?.ctx.furniture3D != nil {
            FM3DPlacementOption(state: state) // FM3D: Furniture tools' Placement Plane
        } else if let tools = state.active3DTools, state.activeTool != nil {
            let levels = WorkPlane3D.levels(in: state.model)
            let current = (state.activeTool as? BaseTool)?.ctx.levelID ?? tools.workPlaneLevel
            let sketch = (state.activeTool as? BaseTool)?.ctx.sketchPlane // S3D2: drawing on a reference plane or face
            HStack(spacing: 5) {
                Text("Work Plane").font(.system(size: 11)).foregroundStyle(.secondary)
                if let sketch { Text(WorkPlanes.name(sketch.reference, state.model)).font(.system(size: 11)) }
                Picker("", selection: Binding(get: { sketch == nil ? current ?? ElementID(0) : ElementID(0) }, set: { if $0 != ElementID(0) { tools.setWorkPlane($0) } })) {
                    if sketch != nil { Text("Level…").tag(ElementID(0)) }
                    ForEach(levels, id: \.id) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().controlSize(.small).fixedSize()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Work plane level")
            .help("The level this tool draws on in 3D. Points are picked on the level's plane; doors and windows follow the wall under the pointer.")
        }
    }
}

extension Viewport3DHost {
    /// Letters the viewport does not use for the camera arrive here: two-letter shortcuts (WA, DR, MV …) start tools, as
    /// in plan views (W2-3D).
    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty, let first = chars.first, first.isLetter else {
            super.keyDown(with: event); return
        }
        guard !TextInputFocus.isEditingText(in: window) else { TextInputFocus.focusInlineEditor(in: window); return } // BL-KEYS
        state.feedAlias(first) // BL-KEYS: the same alias buffer as the 2D canvas (KeyboardSession.swift)
    }
}
