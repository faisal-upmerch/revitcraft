import Foundation
import ArcusGeometry

// COMP: assembly presets: ready modules inserted into a bay (Drawer Stack, Desk Pedestal, Wardrobe Interior, Pantry
// Pull-Out…). They're built with the same operations the tools use (Bay Divide, Drawer, Door, Shelf, components), so
// everything they make is ordinary parts and components, editable afterwards.

/// One step of an assembly.
public enum ComponentAssemblyStep: Sendable, Hashable {
    /// A stack of drawers (Bay Divide, EQ) in the bay.
    case drawers(Int)
    /// A door (hinged left, or right when flipped).
    case door(flipped: Bool)
    /// Shelves at equal spacing (adjustable on pins, or fixed).
    case shelves(Int, adjustable: Bool)
    /// A fixed shelf this far below the bay's top.
    case shelfBelowTop(Double)
    /// The best component for a search on a face of the bay (or of the first front it made, when `onFront`).
    case component(query: String, face: ComponentFace, alignment: ComponentAlignment, onFront: Bool)
}

public struct ComponentAssembly: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    public var symbol: String
    public var steps: [ComponentAssemblyStep]

    public static let builtIn: [ComponentAssembly] = [
        ComponentAssembly(id: "drawer-stack-3", name: "Drawer Stack (3)", summary: "Three equal drawers with slides and handles.", symbol: "square.stack.3d.up",
                          steps: [.drawers(3)]),
        ComponentAssembly(id: "drawer-stack-4", name: "Drawer Stack (4)", summary: "Four equal drawers with slides and handles.", symbol: "square.stack.3d.up.fill",
                          steps: [.drawers(4)]),
        ComponentAssembly(id: "desk-pedestal", name: "Desk Pedestal", summary: "Three drawers, the top one locking.", symbol: "lock.rectangle.stack",
                          steps: [.drawers(3), .component(query: "lock", face: .inside, alignment: .top, onFront: true)]),
        ComponentAssembly(id: "wardrobe-interior", name: "Wardrobe Interior", summary: "Top shelf, hanging rod and shoe rack.", symbol: "tshirt",
                          steps: [.shelfBelowTop(12 * 0.0254), .component(query: "hanging rod", face: .top, alignment: .center, onFront: false),
                                  .component(query: "shoe rack", face: .bottom, alignment: .center, onFront: false)]),
        ComponentAssembly(id: "pantry-pull-out", name: "Pantry Pull-Out", summary: "A pull-out pantry behind a door.", symbol: "cabinet",
                          steps: [.component(query: "pantry pull out", face: .bottom, alignment: .center, onFront: false), .door(flipped: false)]),
        ComponentAssembly(id: "adjustable-shelves-3", name: "Adjustable Shelves (3)", summary: "Three shelves on pins at equal spacing.", symbol: "books.vertical",
                          steps: [.shelves(3, adjustable: true)]),
        ComponentAssembly(id: "door-and-shelves", name: "Door with Shelves", summary: "Two adjustable shelves behind a door.", symbol: "door.left.hand.closed",
                          steps: [.shelves(2, adjustable: true), .door(flipped: false)]),
        ComponentAssembly(id: "sink-base", name: "Sink Base", summary: "A door and an under-sink organizer.", symbol: "drop",
                          steps: [.component(query: "under sink organizer", face: .bottom, alignment: .center, onFront: false), .door(flipped: false)]),
    ]
}

public enum ComponentAssemblies {
    /// Lines describing what an assembly will add to a bay (for the confirmation), and steps it can't do.
    public static func preview(_ a: ComponentAssembly, bay: ElementID, _ m: BIMModel, catalog: ComponentCatalog = .current) -> (lines: [String], notes: [String]) {
        var lines: [String] = [], notes: [String] = []
        guard let b = m[bay]?.furnitureBay, b.opening != nil else { return ([], ["Pick an enclosed bay."]) }
        if m.hosted(by: bay).contains(where: { $0.furnitureFront != nil }) || !FurnitureBays.cellIDs(of: bay, m).isEmpty {
            notes.append("The bay already has fronts or cells; pick an empty bay.")
        }
        for s in a.steps {
            switch s {
            case .drawers(let n): lines.append("\(n) drawers (Bay Divide, EQ), with slides and handles")
            case .door: lines.append("1 door, with hinges and a handle")
            case .shelves(let n, let adj): lines.append("\(n) \(adj ? "adjustable" : "fixed") shelves at equal spacing")
            case .shelfBelowTop(let d): lines.append("1 fixed shelf \(FurnitureSizeText.inches(d)) below the top")
            case .component(let q, _, _, _):
                if let d = best(q, catalog) { lines.append("1 \(d.name)") }
                else { notes.append("No “\(q)” component in the library: skipped.") }
            }
        }
        return (lines, notes)
    }

    static func best(_ q: String, _ catalog: ComponentCatalog) -> ComponentDefinition? {
        ComponentSearchIndex(catalog.all).search(q, limit: 1).first.flatMap { $0.score >= 10 ? $0.definition : nil }
    }

    /// Inserts an assembly into an empty bay; returns what it made.
    @discardableResult
    public static func insert(_ a: ComponentAssembly, bay bayID: ElementID, in tx: TransactionContext, catalog: ComponentCatalog = .current) throws(TransactionError) -> [ElementID] {
        guard let bay = tx.model[bayID], let bd = bay.furnitureBay, let o = bd.opening else { throw TransactionError("Pick an enclosed bay.") }
        guard !tx.model.hosted(by: bayID).contains(where: { $0.furnitureFront != nil }), FurnitureBays.cellIDs(of: bayID, tx.model).isEmpty else {
            throw TransactionError("\(bay.name) already has fronts or cells.", elements: [bayID], resolution: "Pick an empty bay.")
        }
        FurnitureHardware.ensureLibrary(in: tx)
        var made: [ElementID] = []
        var fronts: [ElementID] = []
        let frame = BayFrame(bd)
        let bottomPlane = FurniturePlanes.positionsByName(tx.model)["Bottom"] ?? 0
        func shelf(at z: Double, adjustable: Bool) throws(TransactionError) {
            guard frame.isIdentity else { throw TransactionError("Shelves go in bays seen from the front.", elements: [bayID]) }
            let loop = [Vec2(o.x0, o.y0), Vec2(o.x1, o.y0), Vec2(o.x1, o.y1), Vec2(o.x0, o.y1)]
            made.append(try FurniturePartOperations.createShelf(boundary: loop, plane: "Bottom", offset: z - bottomPlane, role: .shelf, adjustable: adjustable, in: tx))
        }
        for s in a.steps {
            switch s {
            case .drawers(let n):
                let ids = try FurnitureFronts.createDrawers(in: bayID, count: n, in: tx)
                fronts += ids; made += ids
            case .door(let flipped):
                let ids = try FurnitureFronts.createFront(.door, in: bayID, hingeFlipped: flipped, in: tx)
                fronts += ids; made += ids
            case .shelves(let n, let adj):
                let t = 0.75 * 0.0254
                for k in 1...max(1, n) { try shelf(at: o.z0 + (o.z1 - o.z0) * Double(k) / Double(n + 1) - t / 2, adjustable: adj) }
            case .shelfBelowTop(let d):
                try shelf(at: o.z1 - d, adjustable: false)
            case .component(let q, let face, let align, let onFront):
                guard let d = best(q, catalog) else { continue }
                // The topmost front made (drawer stacks: the top drawer).
                let hostID: ElementID = onFront ? (fronts.max { (tx.model[$0].flatMap { ComponentPlacement.face($0, .front, tx.model)?.origin.z } ?? 0)
                    < (tx.model[$1].flatMap { ComponentPlacement.face($0, .front, tx.model)?.origin.z } ?? 0) } ?? bayID) : bayID
                guard let host = tx.model[hostID], let kind = ComponentPlacement.hostKind(host, tx.model), ComponentPlacement.accepts(d, kind) else { continue }
                var st = ComponentSettings(d.placement, face: d.placement.faces.contains(face) ? face : d.placement.faces.first)
                st.alignment = align
                made += try ComponentPlacement.place(d, hostID: hostID, settings: st, in: tx)
            }
        }
        return made
    }
}
