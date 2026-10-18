import SwiftUI
import AppKit
import ArcusDomain

// W4-FAMED: the form editor lives in Properties; forms are added from the ribbon (`FamilyEditorModel.addForm`) or sketched
// on the canvas (`addExtrusion`).

/// Editor for one form: its shape, heights, material, subcategory and visibility settings. Rows stack vertically so the
/// editor fits the 300 pt inspector.
struct FamilySolidEditor: View {
    let model: FamilyEditorModel
    let solid: FamilySolid

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            shape
            properties
            visibility
        }
    }

    func set(_ change: @escaping (inout FamilySolid) -> Void) { model.updateSolid(solid.id, "Edit Form", change) }
    func setProfile(_ p: FamilySolid.Profile) { set { $0.profile = p } }

    /// F1415: extrusions sketched on an elevation plane name their extents by that plane's axes.
    var plane: FamilySketchPlane { solid.workPlane ?? .xy }
    var depthLabel: String { plane == .xy ? "Z extent" : "\(plane.axes.w.rawValue) extent (depth)" }

    @ViewBuilder
    var shape: some View {
        if plane != .xy, solid.profile.isExtrusion {
            InspectorRow(label: "Work plane") { Text("Sketched on \(plane.label)").foregroundStyle(.secondary) }
        }
        switch solid.profile {
        case .rectangle(let x0, let x1, let y0, let y1):
            InspectorRow(label: "\(plane.axes.u.rawValue) extent") {
                HStack {
                    FamilyBoundField(model: model, label: "from", bound: x0) { setProfile(.rectangle(xMin: $0, xMax: x1, yMin: y0, yMax: y1)) }
                    FamilyBoundField(model: model, label: "to", bound: x1) { setProfile(.rectangle(xMin: x0, xMax: $0, yMin: y0, yMax: y1)) }
                }
            }
            InspectorRow(label: "\(plane.axes.v.rawValue) extent") {
                HStack {
                    FamilyBoundField(model: model, label: "from", bound: y0) { setProfile(.rectangle(xMin: x0, xMax: x1, yMin: $0, yMax: y1)) }
                    FamilyBoundField(model: model, label: "to", bound: y1) { setProfile(.rectangle(xMin: x0, xMax: x1, yMin: y0, yMax: $0)) }
                }
            }
            heights(label: depthLabel, bottom: "from", top: "to")
            Button("Convert to Polygon") {
                setProfile(.polygon([FamilyPoint(x0, y0), FamilyPoint(x1, y0), FamilyPoint(x1, y1), FamilyPoint(x0, y1)]))
            }
        case .polygon(let pts):
            FamilyPointListEditor(model: model, title: plane == .xy ? "Profile (plan)" : "Profile (\(plane.axes.u.rawValue.lowercased()), \(plane.axes.v.rawValue.lowercased()))", points: pts) { setProfile(.polygon($0)) }
            heights(label: depthLabel, bottom: "from", top: "to")
        case .circle(let c, let r):
            InspectorRow(label: "Center") { FamilyPointField(model: model, point: c, labels: ("x", "y")) { setProfile(.circle(center: $0, radius: r)) } }
            InspectorRow(label: "Radius") { ValueField(text: r) { setProfile(.circle(center: c, radius: $0)) }.font(.caption.monospaced()) }
            heights(label: depthLabel, bottom: "from", top: "to")
        case .sweep(let sw) where sw.isSweptBlend: // F1415
            FamilyPointListEditor(model: model, title: "Path (plan, at the base height)", points: sw.path, minimum: 2) { p in var n = sw; n.path = p; setProfile(.sweep(n)) }
            FamilyPointListEditor(model: model, title: "Profile 1, at the path's start (across, up)", points: sw.profile, labels: ("across", "up")) { p in
                var n = sw; n.profile = p; setProfile(.sweep(n))
            }
            FamilyPointListEditor(model: model, title: "Profile 2, at the path's end (across, up)", points: sw.endProfile ?? [], labels: ("across", "up")) { p in
                var n = sw; n.endProfile = p; setProfile(.sweep(n))
            }
            InspectorRow(label: "Path height") { FamilyBoundField(model: model, label: "", bound: solid.zMin) { b in set { $0.zMin = b } } }
            Button("Make a Sweep (one profile)") { var n = sw; n.endProfile = nil; setProfile(.sweep(n)) }
        case .sweep(let sw):
            FamilyPointListEditor(model: model, title: "Path (plan, at the base height)", points: sw.path, minimum: 2) { p in var n = sw; n.path = p; setProfile(.sweep(n)) }
            let profiles = model.family.nestedFamilies.filter { $0.template == .profile || $0.profileLoop.count >= 3 }
            InspectorRow(label: "Profile", help: "Use a profile family loaded into this family, or sketch a profile.") {
                Picker("", selection: Binding(get: { sw.profileFamily ?? "" }, set: { v in
                    var n = sw
                    n.profileFamily = v.isEmpty ? nil : v
                    n.profileFamilyType = nil
                    setProfile(.sweep(n))
                })) {
                    Text("Sketched below").tag("")
                    ForEach(profiles, id: \.name) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
            }
            if let pfName = sw.profileFamily, let pf = model.family.nestedFamily(named: pfName) {
                InspectorRow(label: "Profile type") {
                    Picker("", selection: Binding(get: { sw.profileFamilyType ?? pf.types.first?.name ?? "" }, set: { v in
                        var n = sw; n.profileFamilyType = v; setProfile(.sweep(n))
                    })) { ForEach(pf.types) { Text($0.name).tag($0.name) } }
                    .labelsHidden()
                }
            } else {
                FamilyPointListEditor(model: model, title: "Profile (across the path, up)", points: sw.profile, labels: ("across", "up")) { p in
                    var n = sw; n.profile = p; setProfile(.sweep(n))
                }
            }
            InspectorRow(label: "Path height") { FamilyBoundField(model: model, label: "", bound: solid.zMin) { b in set { $0.zMin = b } } }
            if sw.profileFamily == nil, sw.profile.count >= 3 {
                Button("Make a Swept Blend") { var n = sw; n.endProfile = sw.profile; setProfile(.sweep(n)) } // F1415
                    .help("Adds a second profile at the path's end; the form blends from the first to it.")
            }
        case .blend(let bl):
            FamilyPointListEditor(model: model, title: "Base loop (plan)", points: bl.bottom) { p in setProfile(.blend(FamilyBlend(bottom: p, top: bl.top))) }
            FamilyPointListEditor(model: model, title: "Top loop (plan)", points: bl.top) { p in setProfile(.blend(FamilyBlend(bottom: bl.bottom, top: p))) }
            heights(label: "Heights", bottom: "base", top: "top")
        case .revolve(let rv):
            FamilyPointListEditor(model: model, title: "Profile (radius, height above base)", points: rv.profile, labels: ("r", "h")) { p in
                var n = rv; n.profile = p; setProfile(.revolve(n))
            }
            InspectorRow(label: "Axis") { FamilyPointField(model: model, point: rv.axis, labels: ("x", "y")) { a in var n = rv; n.axis = a; setProfile(.revolve(n)) } }
            InspectorRow(label: "Angles °") {
                HStack {
                    Text("start").font(.caption).foregroundStyle(.secondary)
                    ValueField(text: rv.startDegrees) { v in var n = rv; n.startDegrees = v; setProfile(.revolve(n)) }.font(.caption.monospaced())
                    Text("end").font(.caption).foregroundStyle(.secondary)
                    ValueField(text: rv.endDegrees) { v in var n = rv; n.endDegrees = v; setProfile(.revolve(n)) }.font(.caption.monospaced())
                }
            }
            InspectorRow(label: "Base height") { FamilyBoundField(model: model, label: "", bound: solid.zMin) { b in set { $0.zMin = b } } }
        }
    }

    func heights(label: String, bottom: String, top: String) -> some View {
        InspectorRow(label: label) {
            HStack {
                FamilyBoundField(model: model, label: bottom, bound: solid.zMin) { b in set { $0.zMin = b } }
                FamilyBoundField(model: model, label: top, bound: solid.zMax) { b in set { $0.zMax = b } }
            }
        }
    }

    var properties: some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorRow(label: "Material") {
                Picker("", selection: Binding(get: { solid.materialParameter ?? "" }, set: { v in set { $0.materialParameter = v.isEmpty ? nil : v } })) {
                    Text("By Category").tag("")
                    ForEach(model.materialParameters) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
                .disabled(solid.isVoid)
            }
            InspectorRow(label: "Subcategory") {
                Picker("", selection: Binding(get: { solid.subcategory }, set: { v in set { $0.subcategory = v } })) {
                    ForEach(FamilySubcategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
        }
    }

    var visibility: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Visibility").font(Tokens.groupHeader).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                toggle("3D", \.visibleIn3D)
                toggle("Plan", \.visibleInPlan)
                toggle("Front/Back", \.visibleInFrontBack)
                toggle("Left/Right", \.visibleInLeftRight)
            }
            FamilyVisibilityControls(model: model, visibleAt: solid.visibleAt, parameter: solid.visibilityParameter,
                                     setLevels: { l in set { $0.visibleAt = l } }, setParameter: { p in set { $0.visibilityParameter = p } })
        }
        .disabled(solid.isVoid)
    }

    func toggle(_ title: String, _ key: WritableKeyPath<FamilySolid, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { solid[keyPath: key] }, set: { v in set { $0[keyPath: key] = v } }))
            .toggleStyle(.checkbox).font(.caption)
    }
}
