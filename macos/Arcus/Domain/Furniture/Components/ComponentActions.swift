import Foundation
import ArcusGeometry

// COMP: one-click hardware. Select a door, drawer, flap or bay and the contextual tab offers what it can take
// (Add Handle, Hinges, Lock, Soft-Close, Push-to-Open; Slides, Organizer; Hanging Rod, Shoe Rack, Lighting, Sliding
// System). Each action is planned first (which components, how many, where, and anything it changes) and shown for
// confirmation; nothing is added silently. Handles, hinges and slides of fronts use the front's own hardware (as
// Revit's nested shared families swap through the host's parameter); everything else is placed as components.

/// Document-wide hardware rules (Manage ▸ Hardware Rules): hinges per door height.
public enum ComponentRules {
    public static let hingeRuleParam = ParameterID("comp.hingeRule")

    /// The hinge count rule of a document (default: 2 to 40", 3 to 60", 4 to 80", then 5).
    public static func hingeRule(_ m: BIMModel) -> ComponentCountRule {
        guard let t = m.projectInfoElement?.params[hingeRuleParam]?.textValue, let d = t.data(using: .utf8),
              let r = try? JSONDecoder().decode(ComponentCountRule.self, from: d), !r.steps.isEmpty else { return .hinges }
        return r
    }

    public static func setHingeRule(_ r: ComponentCountRule?, in tx: TransactionContext) {
        guard let id = tx.model.projectInfoElement?.id else { return }
        let text = r.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        tx.update(id) { e in
            if let text { e.params[hingeRuleParam] = .text(text) } else { e.params.removeValue(forKey: hingeRuleParam) }
        }
    }

    /// The count rule a definition uses in a document (hinges follow the document's rule).
    public static func countRule(_ d: ComponentDefinition, _ m: BIMModel) -> ComponentCountRule? {
        guard let r = d.placement.count else { return nil }
        return d.category == .hinges ? hingeRule(m) : r
    }
}

/// A one-click hardware action.
public enum ComponentAction: String, CaseIterable, Sendable, Hashable, Identifiable {
    case handle = "Add Handle", hinges = "Add Hinges", lock = "Add Lock", softClose = "Add Soft-Close", pushToOpen = "Add Push-to-Open"
    case slides = "Add Slides", organizer = "Add Organizer"
    case hangingRod = "Add Hanging Rod", shoeRack = "Add Shoe Rack", lighting = "Add Lighting", slidingSystem = "Add Sliding System"

    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .handle: "hand.point.up.left"
        case .hinges: "door.left.hand.open"
        case .lock: "lock"
        case .softClose: "arrow.down.right.and.arrow.up.left"
        case .pushToOpen: "hand.tap"
        case .slides: "archivebox"
        case .organizer: "square.grid.3x2"
        case .hangingRod: "tshirt"
        case .shoeRack: "shoeprints.fill"
        case .lighting: "lightbulb"
        case .slidingSystem: "rectangle.split.2x1"
        }
    }

    /// The search that finds the component and the host faces it goes on.
    var query: String {
        switch self {
        case .handle: "handle"
        case .hinges: "concealed hinge"
        case .lock: "lock"
        case .softClose: "soft close damper"
        case .pushToOpen: "push to open"
        case .slides: "drawer slide"
        case .organizer: "drawer organizer"
        case .hangingRod: "hanging rod"
        case .shoeRack: "shoe rack"
        case .lighting: "led light"
        case .slidingSystem: "sliding door system"
        }
    }
}

/// One component an action places.
public struct ComponentActionItem: Sendable, Hashable {
    public var definition: ComponentDefinition
    public var typeName: String
    public var hostID: ElementID
    public var settings: ComponentSettings
    /// How many instances it makes (hinge sets, pairs).
    public var count: Int
}

/// A change an action makes to a front's own hardware.
public struct ComponentFrontEdit: Sendable, Hashable {
    public var frontID: ElementID
    public var handleTypeID: ElementID?
    public var hingeTypeID: ElementID?
    public var handlePosition: HandlePosition?
}

/// What an action will do, for the confirmation sheet.
public struct ComponentActionPlan: Sendable, Hashable {
    public var action: ComponentAction
    /// One line per change ("2 × Concealed Hinge - Frameless : Full Overlay 110° on D1").
    public var lines: [String]
    public var items: [ComponentActionItem]
    public var frontEdits: [ComponentFrontEdit]
    /// Rule findings and notes ("D1 already has a handle: it will be replaced.").
    public var notes: [String]
    public var isEmpty: Bool { items.isEmpty && frontEdits.isEmpty }
}

public enum ComponentActions {
    /// Actions a selection can take, in ribbon order.
    public static func available(for ids: [ElementID], _ m: BIMModel) -> [ComponentAction] {
        let kinds = Set(ids.compactMap { m[$0].flatMap { ComponentPlacement.hostKind($0, m) } })
        guard !kinds.isEmpty else { return [] }
        var out: [ComponentAction] = []
        func add(_ a: [ComponentAction]) { for x in a where !out.contains(x) { out.append(x) } }
        if kinds.contains(.door) || kinds.contains(.glass) { add([.handle, .hinges, .lock, .softClose, .pushToOpen]) }
        if kinds.contains(.flap) || kinds.contains(.lid) { add([.handle, .hinges, .lock, .pushToOpen]) }
        if kinds.contains(.drawerFront) { add([.handle, .slides, .lock, .softClose, .pushToOpen, .organizer]) }
        if kinds.contains(.bay) { add([.hangingRod, .shoeRack, .lighting, .organizer, .slides, .slidingSystem]) }
        if kinds.contains(.top) || kinds.contains(.shelf) || kinds.contains(.sidePanel) { add([.lighting]) }
        return out
    }

    /// The best component for an action on a host kind (nil = none in the catalog).
    public static func component(_ a: ComponentAction, for kind: ComponentHostKind, in catalog: ComponentCatalog = .current) -> ComponentDefinition? {
        let index = ComponentSearchIndex(catalog.all.filter { ComponentPlacement.accepts($0, kind) })
        return index.search(a.query, limit: 1).first?.definition
    }

    static func label(_ e: Element) -> String { e.mark.isEmpty ? e.category.singularName : e.mark }

    /// The plan of an action on the selection.
    public static func plan(_ a: ComponentAction, for ids: [ElementID], _ m: BIMModel, catalog: ComponentCatalog = .current) -> ComponentActionPlan {
        var plan = ComponentActionPlan(action: a, lines: [], items: [], frontEdits: [], notes: [])
        let hosts = ids.compactMap { m[$0] }.filter { ComponentPlacement.hostKind($0, m) != nil }
        for h in hosts {
            guard let kind = ComponentPlacement.hostKind(h, m) else { continue }
            switch (a, h.data) {
            case (.handle, .furnitureFront(let f)):
                let current = f.handlePosition != .none ? (f.handleTypeID ?? FurnitureFrontTypes.values(of: h, m).handleType) : nil
                guard let t = handleType(for: h, m) else { plan.notes.append("No handle type fits \(label(h))."); continue }
                if let c = current, c == t { plan.notes.append("\(label(h)) already has \(typeLabel(t, m))."); continue }
                if current != nil { plan.notes.append("\(label(h))'s handle is replaced.") }
                let pos = f.handlePosition == .none ? HandlePosition.defaultFor(f.kind) : f.handlePosition
                plan.frontEdits.append(ComponentFrontEdit(frontID: h.id, handleTypeID: t, handlePosition: pos))
                plan.lines.append("1 × \(typeLabel(t, m)) on \(label(h)), \(pos.rawValue.lowercased())")
            case (.hinges, .furnitureFront(let f)) where f.kind != .drawer:
                guard let t = hingeType(for: h, m) else { plan.notes.append("No hinge type suits \(label(h))."); continue }
                let height = ComponentPlacement.face(h, .front, m)?.height ?? 0
                let n = ComponentRules.hingeRule(m).count(forEdge: f.kind == .door ? height : (ComponentPlacement.face(h, .front, m)?.width ?? 0))
                plan.frontEdits.append(ComponentFrontEdit(frontID: h.id, hingeTypeID: t))
                plan.lines.append("\(n) × \(typeLabel(t, m)) on \(label(h)) (by its \(FurnitureSizeText.inches(height)) height)")
            case (.slides, .furnitureFront(let f)) where f.kind == .drawer:
                if let b = FurnitureFronts.drawerBox(h, m), let st = b.slideTypeID {
                    plan.notes.append("\(label(h)) already runs on \(typeLabel(st, m)) (by its bay's depth).")
                } else {
                    plan.notes.append("No slide fits \(label(h))'s bay: it needs at least 12\" of depth.")
                }
            default:
                // Placed components.
                guard let d = component(a, for: kind, in: catalog) else {
                    plan.notes.append("The library has no component for \(a.rawValue.dropFirst(4).lowercased()) on a \(kind.rawValue.lowercased()).")
                    continue
                }
                let face = preferredFace(a, d)
                var s = ComponentSettings(d.placement, face: face)
                if a == .pushToOpen, case .furnitureFront(let f) = h.data {
                    s.alignment = .outside
                    if f.handlePosition != .none {
                        plan.frontEdits.append(ComponentFrontEdit(frontID: h.id, handlePosition: HandlePosition.none))
                        plan.notes.append("\(label(h))'s handle is removed (push to open).")
                    }
                }
                let typeName = bestType(d, host: h, kind: kind, m)
                let count = ComponentPlacement.layout(d, host: h, s, at: nil, m).count
                guard count > 0 else { plan.notes.append("\(label(h)) has no \(face.rawValue.lowercased()) face for \(d.name)."); continue }
                plan.items.append(ComponentActionItem(definition: d, typeName: typeName, hostID: h.id, settings: s, count: count))
                plan.lines.append("\(count) × \(d.name) : \(typeName) on \(label(h))")
                plan.notes += ComponentChecks.requirements(d, typeName: typeName, host: h, kind: kind, face: face, m).map(\.message)
            }
        }
        if plan.isEmpty, plan.notes.isEmpty { plan.notes.append("Select a door, drawer, flap or bay.") }
        return plan
    }

    static func preferredFace(_ a: ComponentAction, _ d: ComponentDefinition) -> ComponentFace {
        let faces = d.placement.faces
        switch a {
        case .hangingRod, .lighting: return faces.contains(.top) ? .top : (faces.first ?? .top)
        case .shoeRack, .organizer: return faces.contains(.bottom) ? .bottom : (faces.first ?? .bottom)
        case .lock, .softClose, .pushToOpen: return faces.contains(.inside) ? .inside : (faces.first ?? .inside)
        default: return faces.first ?? .front
        }
    }

    /// The type that fits the host best: the longest whose rules pass, else the default.
    static func bestType(_ d: ComponentDefinition, host: Element, kind: ComponentHostKind, _ m: BIMModel) -> String {
        let ok = d.types.filter { ComponentChecks.requirements(d, typeName: $0.name, host: host, kind: kind, m).isEmpty }
        let main = d.parameters.first { $0.type == .length && !$0.isInstance }?.name
        let pick = ok.max { a, b in (a.values[main ?? ""]?.doubleValue ?? 0) < (b.values[main ?? ""]?.doubleValue ?? 0) }
        return (pick ?? d.defaultType)?.name ?? ""
    }

    static func typeLabel(_ id: ElementID, _ m: BIMModel) -> String {
        let t = m[id]
        return "\(t?.typeData?.familyName ?? "") : \(t?.name ?? "")"
    }

    /// The handle type for a front: the longest bar pull that leaves 2" on each side, else a knob.
    static func handleType(for front: Element, _ m: BIMModel) -> ElementID? {
        let w = ComponentPlacement.face(front, .front, m)?.width ?? 0
        let bars = m.types(for: .furnitureHardware).filter { $0.typeData?.familyName == FurnitureHardware.barPull }
            .map { ($0.id, FurnitureHardware.Values($0.typeData).handleLength) }.filter { $0.1 <= w - 4 * 0.0254 }
        if let best = bars.max(by: { $0.1 < $1.1 }) { return best.0 }
        return m.types(for: .furnitureHardware).first { $0.typeData?.familyName == FurnitureHardware.knob }?.id
    }

    /// The hinge type for a door or flap by its overlay.
    static func hingeType(for front: Element, _ m: BIMModel) -> ElementID? {
        let overlay = FurnitureFrontTypes.values(of: front, m).overlay
        let name: String = switch overlay { case .full: "Full Overlay 110°"; case .half: "Half Overlay 110°"; case .inset: "Inset 110°" }
        return FurnitureHardware.type(FurnitureHardware.concealedHinge, name, m)
    }

    /// Carries out a confirmed plan; returns the components placed.
    @discardableResult
    public static func apply(_ plan: ComponentActionPlan, in tx: TransactionContext) throws(TransactionError) -> [ElementID] {
        FurnitureHardware.ensureLibrary(in: tx)
        for e in plan.frontEdits {
            tx.update(e.frontID) { x in
                if let t = e.handleTypeID { x.furnitureFront?.handleTypeID = t }
                if let t = e.hingeTypeID { x.furnitureFront?.hingeTypeID = t }
                if let p = e.handlePosition { x.furnitureFront?.handlePosition = p }
            }
        }
        var out: [ElementID] = []
        for it in plan.items {
            out += try ComponentPlacement.place(it.definition, typeName: it.typeName, hostID: it.hostID, settings: it.settings, in: tx)
        }
        return out
    }
}
