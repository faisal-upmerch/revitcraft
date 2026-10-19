import Foundation
import ArcusGeometry
import ArcusCalc

// COMP: compatibility rules and collisions. Each definition's requirements (hinge vs the door's thickness, weight and
// overlay; slide length vs the bay's depth; handle length vs the front's width; lock vs the panel's thickness…) are
// checked while placing (the tool's warnings), when a component is replaced, live at regeneration, and in
// Fabricate ▸ Check Parts together with geometric overlaps between hardware.

public enum ComponentChecks {
    static let inch = 0.0254
    /// Sheet goods weight for a front's estimate (plywood/MDF, kg/m³).
    static let density = 640.0

    // MARK: Expressions

    /// The family's evaluated values for a type and instance values.
    static func evaluated(_ d: ComponentDefinition, typeName: String?, instance: [String: ParamValue] = [:]) -> EvaluatedFamily {
        FamilyEvaluator.evaluate(d.family, typeName: typeName ?? d.defaultType?.name ?? "", instance: instance)
    }

    /// Evaluates an expression against a family's values plus extra lengths (meters); nil when it doesn't parse.
    public static func value(_ expr: String, _ ev: EvaluatedFamily, extra: [String: Double] = [:]) -> Double? {
        let t = expr.trimmingCharacters(in: .whitespaces)
        if let d = Double(t) { return d }
        var values = ev.values
        for (k, v) in extra { values[k] = .quantity(v, .length) }
        guard let f = try? Formula(t, knownNames: Set(values.keys)), let r = try? f.evaluate(units: .metric, { values[$0] }) else { return nil }
        switch r {
        case .quantity(let v, _): return v.isFinite ? v : nil
        case .bool(let b): return b ? 1 : 0
        case .text: return nil
        }
    }

    // MARK: Host measures

    /// What the rules measure on a host.
    public struct HostMeasures: Sendable {
        public var thickness: Double
        public var width: Double
        public var height: Double
        /// The bay's depth (fronts: their bay's; bays: their own; parts: their depth front to back).
        public var depth: Double?
        /// Estimated weight in lb (fronts).
        public var weight: Double?
        public var overlay: String?
    }

    public static func measures(_ host: Element, face: ComponentFace, _ m: BIMModel) -> HostMeasures? {
        guard let f = ComponentPlacement.face(host, face, m) ?? ComponentPlacement.faces(host, m).first else { return nil }
        var out = HostMeasures(thickness: f.thickness, width: f.width, height: f.height, depth: nil, weight: nil, overlay: nil)
        switch host.data {
        case .furnitureFront:
            if let o = m[host.hostID]?.furnitureBay?.opening { out.depth = o.depth }
            if let g = FurnitureFronts.geometry(host, m) {
                let area = g.leaves.reduce(0) { $0 + $1.width * $1.height }
                out.weight = area * g.thickness * density * 2.2046
                out.thickness = g.thickness
            }
            out.overlay = FurnitureFrontTypes.values(of: host, m).overlay.rawValue
        case .furnitureBay(let b):
            out.depth = b.opening?.depth
        default:
            let bb = ElementMeshes.bounds(host, m)
            out.depth = bb.max.y - bb.min.y
        }
        return out
    }

    // MARK: Requirements

    /// The requirement findings for a definition (a type and instance values) on a host.
    public static func requirements(_ d: ComponentDefinition, typeName: String?, instance: [String: ParamValue] = [:], host: Element, kind: ComponentHostKind,
                                    face: ComponentFace? = nil, sharing: Int = 1, _ m: BIMModel) -> [ModelWarning] {
        guard let hm = measures(host, face: face ?? d.placement.faces.first ?? .front, m) else { return [] }
        let ev = evaluated(d, typeName: typeName, instance: instance)
        let extra = ["Host Thickness": hm.thickness, "Host Width": hm.width, "Host Height": hm.height]
        func v(_ e: String?) -> Double? { e.flatMap { value($0, ev, extra: extra) } }
        let size = { (x: Double) in FurnitureSizeText.inches(x) }
        let label = typeName.map { "\(d.name) (\($0))" } ?? d.name
        var out: [ModelWarning] = []
        func warn(_ code: String, _ msg: String, _ fix: String? = nil) {
            out.append(ModelWarning(.warning, code: "comp.\(code)", fix.map { "\(msg) \($0)" } ?? msg, elements: [host.id]))
        }
        for r in d.requirements {
            switch r {
            case .hostThickness(let lo, let hi):
                if let a = v(lo), hm.thickness < a - 1e-4 { warn("thin", "\(label) needs a host at least \(size(a)) thick; this one is \(size(hm.thickness)).") }
                if let b = v(hi), hm.thickness > b + 1e-4 { warn("thick", "\(label) takes a host up to \(size(b)) thick; this one is \(size(hm.thickness)).") }
            case .hostWidth(let lo, let hi):
                if let a = v(lo), hm.width < a - 1e-4 { warn("narrow", "\(label) needs a face at least \(size(a)) wide.") }
                if let b = v(hi), hm.width > b + 1e-4 { warn("wide", "\(label) suits faces up to \(size(b)) wide.") }
            case .hostHeight(let lo, let hi):
                if let a = v(lo), hm.height < a - 1e-4 { warn("short", "\(label) needs a face at least \(size(a)) tall.") }
                if let b = v(hi), hm.height > b + 1e-4 { warn("tall", "\(label) suits faces up to \(size(b)) tall.") }
            case .fitsDepth(let e):
                if let need = v(e), let depth = hm.depth, need > depth + 1e-4 {
                    warn("depth", "\(label) needs \(size(need)) of depth; the bay is \(size(depth)) deep.", "Pick a shorter type.")
                }
            case .fitsWidth(let e):
                if let need = v(e), need > hm.width + 1e-4 { warn("fitWidth", "\(label) is too long for a \(size(hm.width)) wide face.", "Pick a shorter type.") }
            case .fitsHeight(let e):
                if let need = v(e), need > hm.height + 1e-4 { warn("fitHeight", "\(label) is too tall for a \(size(hm.height)) face.") }
            case .maxHostWeight(let e):
                if let cap = v(e), let w = hm.weight, w / Double(max(1, sharing)) > cap + 1e-6 {
                    warn("weight", "\(label): the \(Int(w.rounded())) lb \(kind.rawValue.lowercased()) is too heavy for \(sharing) of them (\(Int(cap)) lb each).",
                         "Add hinges or pick a heavier-duty type.")
                }
            case .overlay(let allowed):
                if let o = hm.overlay, !allowed.contains(o) { warn("overlay", "\(label) isn't made for \(o.lowercased()) fronts.") }
            case .note: break
            }
        }
        return out
    }

    // MARK: Instances and the document

    /// Placed components (COMP instances; FM5's front-owned hardware is checked by its fronts).
    static func placed(_ m: BIMModel) -> [Element] {
        m.elements(.furnitureHardware).filter { !$0.isType && $0.params[ComponentInstanceKeys.face] != nil }.sorted { $0.id < $1.id }
    }

    /// Requirement findings of one instance.
    public static func check(instance e: Element, _ m: BIMModel) -> [ModelWarning] {
        guard let d = ComponentDocument.definition(of: e, m), let host = m[e.hostID], let kind = ComponentPlacement.hostKind(host, m) else { return [] }
        var out: [ModelWarning] = []
        if !ComponentPlacement.accepts(d, kind) {
            out.append(ModelWarning(.warning, code: "comp.host", "\(d.name) isn't made for a \(kind.rawValue.lowercased()).", elements: [e.id, host.id]))
        }
        let sharing = m.hosted(by: host.id).filter { ComponentDocument.definitionID(of: $0, m) == d.id }.count
        out += requirements(d, typeName: m[e.typeID]?.name, instance: Parameters.familyInstanceValues(e), host: host, kind: kind,
                            face: ComponentSettings(e)?.face, sharing: max(1, sharing), m).map { w in
            var x = w; x.elements = [e.id] + w.elements; return x
        }
        return out
    }

    /// Overlapping hardware: two components whose solids intersect (more than 1/32"), at least one placed with the
    /// Component Library.
    public static func collisions(_ m: BIMModel) -> [ModelWarning] {
        let hardware = m.elements(.furnitureHardware).filter { !$0.isType }.sorted { $0.id < $1.id }
        guard hardware.count > 1 else { return [] }
        let tol = inch / 32
        let boxes: [(Element, [Box3])] = hardware.map { e in
            (e, GeometryCache.shared.parts(e, m, detail: .fine).map(\.mesh.bounds).filter { $0.min.x <= $0.max.x })
        }
        var out: [ModelWarning] = []
        for i in 0..<boxes.count {
            for j in (i + 1)..<boxes.count {
                let (a, ba) = boxes[i], (b, bb) = boxes[j]
                guard a.params[ComponentInstanceKeys.face] != nil || b.params[ComponentInstanceKeys.face] != nil else { continue }
                if let g = a.params[ComponentInstanceKeys.group], g == b.params[ComponentInstanceKeys.group] { continue }
                let hit = ba.contains { x in bb.contains { y in overlap(x, y) > tol } }
                if hit {
                    out.append(ModelWarning(.warning, code: "comp.collision", "\(name(a, m)) and \(name(b, m)) overlap. Move one of them, or change its offsets.",
                                            elements: [a.id, b.id]))
                }
            }
        }
        return out
    }

    /// The smallest overlap of two boxes along the three axes (negative when apart).
    static func overlap(_ a: Box3, _ b: Box3) -> Double {
        min(min(a.max.x, b.max.x) - max(a.min.x, b.min.x), min(a.max.y, b.max.y) - max(a.min.y, b.min.y), min(a.max.z, b.max.z) - max(a.min.z, b.min.z))
    }

    static func name(_ e: Element, _ m: BIMModel) -> String {
        let t = m[e.typeID]
        return [t?.typeData?.familyName, t?.name].compactMap { $0 }.joined(separator: " : ")
    }

    /// Every finding: each placed component's rules plus the overlaps (Check Parts).
    public static func check(_ m: BIMModel) -> [ModelWarning] {
        placed(m).flatMap { check(instance: $0, m) } + collisions(m)
    }
}
