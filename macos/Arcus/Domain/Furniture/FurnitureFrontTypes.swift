import Foundation
import ArcusGeometry

// FM5: door, drawer and flap types (Type Properties ▸ Edit Type), as door types in Revit: the overlay (full, half,
// inset), single or pair, the reveals, the front's style and edge profile, its materials, the hardware it takes
// (hinge, handle, slide, stay) and, for drawers, the box construction. Types are `TypeData` elements of the Fronts
// category in the families Door, Drawer and Flap; the front's sheet values (thickness, materials, banding) reuse the
// part type parameters so the cut list reads them the same way.

public enum FurnitureFrontTypes {
    static let inch = 0.0254

    // MARK: Type parameters

    public static let overlay = ParameterID("furniture.front.overlay")
    public static let leaves = ParameterID("furniture.front.leaves")
    public static let style = ParameterID("furniture.front.style")
    /// The gap between neighbouring fronts (and round an inset front).
    public static let reveal = ParameterID("furniture.front.reveal")
    /// The gap to the carcass's outside edges (full overlay).
    public static let edgeReveal = ParameterID("furniture.front.edgeReveal")
    public static let edgeProfile = ParameterID("furniture.front.edgeProfile")
    public static let stileWidth = ParameterID("furniture.front.stileWidth")
    public static let railWidth = ParameterID("furniture.front.railWidth")
    public static let panelThickness = ParameterID("furniture.front.panelThickness")
    public static let panelRecess = ParameterID("furniture.front.panelRecess")
    public static let panelMaterial = ParameterID("furniture.front.panelMaterial")
    public static let louverPitch = ParameterID("furniture.front.louverPitch")
    public static let hingeType = ParameterID("furniture.front.hingeType")
    public static let hingeInset = ParameterID("furniture.front.hingeInset")
    public static let handleType = ParameterID("furniture.front.handleType")
    public static let handleOffset = ParameterID("furniture.front.handleOffset")
    public static let slideType = ParameterID("furniture.front.slideType")
    public static let stayType = ParameterID("furniture.front.stayType")
    public static let flapAction = ParameterID("furniture.front.flapAction")
    public static let boxSide = ParameterID("furniture.front.boxSide")
    public static let boxBack = ParameterID("furniture.front.boxBack")
    public static let boxBottom = ParameterID("furniture.front.boxBottom")
    public static let boxMaterial = ParameterID("furniture.front.boxMaterial")
    public static let bottomMaterial = ParameterID("furniture.front.bottomMaterial")
    public static let boxJoint = ParameterID("furniture.front.boxJoint")

    // MARK: Reading a type

    /// A front type's values with defaults.
    public struct Values: Sendable {
        public var td: TypeData?
        public init(_ td: TypeData?) { self.td = td }
        func d(_ id: ParameterID, _ fallback: Double) -> Double { td?.params[id]?.doubleValue ?? fallback }
        func t(_ id: ParameterID) -> String { td?.params[id]?.textValue ?? "" }
        func r(_ id: ParameterID) -> ElementID? { td?.params[id]?.refValue }
        public var kind: FrontKind { FrontKind(rawValue: td?.familyName ?? "") ?? .door }
        public var overlay: FrontOverlay { FrontOverlay(rawValue: t(FurnitureFrontTypes.overlay)) ?? .full }
        public var isPair: Bool { t(FurnitureFrontTypes.leaves) == "Pair" }
        public var style: FrontStyle { FrontStyle(rawValue: t(FurnitureFrontTypes.style)) ?? .slab }
        public var thickness: Double { d(FurniturePartTypes.thickness, 0.75 * inch) }
        public var reveal: Double { d(FurnitureFrontTypes.reveal, 0.125 * inch) }
        public var edgeReveal: Double { d(FurnitureFrontTypes.edgeReveal, 0.0625 * inch) }
        public var edgeProfile: EdgeProfileShape? { EdgeProfileShape(rawValue: t(FurnitureFrontTypes.edgeProfile)) }
        public var stileWidth: Double { d(FurnitureFrontTypes.stileWidth, 2.25 * inch) }
        public var railWidth: Double { d(FurnitureFrontTypes.railWidth, 2.25 * inch) }
        public var panelThickness: Double { d(FurnitureFrontTypes.panelThickness, 0.25 * inch) }
        public var panelRecess: Double { d(FurnitureFrontTypes.panelRecess, 0.25 * inch) }
        public var louverPitch: Double { d(FurnitureFrontTypes.louverPitch, 1.25 * inch) }
        public var coreMaterial: ElementID? { r(FurniturePartTypes.coreMaterial) }
        public var faceMaterial: ElementID? { r(FurniturePartTypes.faceMaterial) }
        public var panelMaterial: ElementID? { r(FurnitureFrontTypes.panelMaterial) ?? coreMaterial }
        public var material: ElementID? { coreMaterial ?? faceMaterial }
        public var banding: EdgeBanding { EdgeBanding(code: t(FurniturePartTypes.banding)) }
        public var grain: GrainDirection { GrainDirection(rawValue: t(FurniturePartTypes.grain)) ?? .length }
        public var hingeType: ElementID? { r(FurnitureFrontTypes.hingeType) }
        public var hingeInset: Double { d(FurnitureFrontTypes.hingeInset, 3 * inch) }
        public var handleType: ElementID? { r(FurnitureFrontTypes.handleType) }
        public var handleOffset: Double { d(FurnitureFrontTypes.handleOffset, 2.5 * inch) }
        public var slideType: ElementID? { r(FurnitureFrontTypes.slideType) }
        public var stayType: ElementID? { r(FurnitureFrontTypes.stayType) }
        public var flapAction: FlapAction { FlapAction(rawValue: t(FurnitureFrontTypes.flapAction)) ?? .liftUp }
        public var boxSide: Double { d(FurnitureFrontTypes.boxSide, 0.5 * inch) }
        public var boxBack: Double { d(FurnitureFrontTypes.boxBack, 0.5 * inch) }
        public var boxBottom: Double { d(FurnitureFrontTypes.boxBottom, 0.25 * inch) }
        public var boxMaterial: ElementID? { r(FurnitureFrontTypes.boxMaterial) }
        public var bottomMaterial: ElementID? { r(FurnitureFrontTypes.bottomMaterial) }
        public var boxJoint: DrawerBoxJoint { DrawerBoxJoint(rawValue: t(FurnitureFrontTypes.boxJoint)) ?? .dovetail }
    }

    public static func values(of e: Element, _ m: BIMModel) -> Values { Values(m.typeData(of: e)) }

    // MARK: Standard types

    struct Spec {
        var family: FrontKind
        var name: String
        var overlay: FrontOverlay
        var style: FrontStyle
        var pair = false
        var core = "Plywood"
        var flap: FlapAction = .liftUp
        var slide = FurnitureHardware.undermountSlide
        var handle = (FurnitureHardware.barPull, "128 mm")
        var profile: EdgeProfileShape? = nil
    }

    static let standard: [Spec] = [
        Spec(family: .door, name: "Slab - Full Overlay", overlay: .full, style: .slab),
        Spec(family: .door, name: "Slab - Full Overlay Pair", overlay: .full, style: .slab, pair: true),
        Spec(family: .door, name: "Slab - Half Overlay", overlay: .half, style: .slab),
        Spec(family: .door, name: "Slab - Inset", overlay: .inset, style: .slab, handle: (FurnitureHardware.knob, "1 1/4\"")),
        Spec(family: .door, name: "Shaker - Full Overlay", overlay: .full, style: .shaker, core: "Solid Maple"),
        Spec(family: .door, name: "Shaker - Full Overlay Pair", overlay: .full, style: .shaker, pair: true, core: "Solid Maple"),
        Spec(family: .door, name: "Shaker - Inset", overlay: .inset, style: .shaker, core: "Solid Maple", handle: (FurnitureHardware.knob, "1 1/4\"")),
        Spec(family: .door, name: "Glass Panel - Full Overlay", overlay: .full, style: .glass, core: "Solid Oak"),
        Spec(family: .door, name: "Louvered - Full Overlay", overlay: .full, style: .louvered, core: "Solid Pine"),
        Spec(family: .drawer, name: "Slab - Full Overlay", overlay: .full, style: .slab),
        Spec(family: .drawer, name: "Slab - Full Overlay Side Mount", overlay: .full, style: .slab, slide: FurnitureHardware.sideMountSlide),
        Spec(family: .drawer, name: "Shaker - Full Overlay", overlay: .full, style: .shaker, core: "Solid Maple"),
        Spec(family: .drawer, name: "Slab - Inset", overlay: .inset, style: .slab, slide: FurnitureHardware.sideMountSlide, handle: (FurnitureHardware.knob, "1 1/4\"")),
        Spec(family: .flap, name: "Slab - Full Overlay Lift-Up", overlay: .full, style: .slab, flap: .liftUp),
        Spec(family: .flap, name: "Slab - Full Overlay Drop-Down", overlay: .full, style: .slab, flap: .dropDown),
    ]

    /// The default type names (the first a tool offers) per family.
    public static let defaultNames: [FrontKind: String] = [.door: "Slab - Full Overlay", .drawer: "Slab - Full Overlay", .flap: "Slab - Full Overlay Lift-Up"]

    /// Creates the hardware families, the standard door, drawer and flap types and the Bay and Front Tags where missing
    /// (idempotent). The template calls it when it's made, the tools before their first front.
    public static func ensureStandard(in tx: TransactionContext) {
        guard tx.model.isFurniture else { return }
        if FurniturePartTypes.firstType(.furniturePanels, tx.model) == nil { FurniturePartTypes.ensureStandard(in: tx) }
        FurnitureHardware.ensureLibrary(in: tx)
        let m = tx.model
        let mat = Dictionary(m.elements(.materials).map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
        let existing = Set(m.types(for: .furnitureFronts).map { "\($0.typeData?.familyName ?? "")|\($0.name)" })
        for s in standard where !existing.contains("\(s.family.rawValue)|\(s.name)") {
            var p: [ParameterID: ParamValue] = [:]
            p[overlay] = .text(s.overlay.rawValue)
            p[leaves] = .text(s.pair ? "Pair" : "Single")
            p[style] = .text(s.style.rawValue)
            p[FurniturePartTypes.thickness] = .double(0.75 * inch)
            p[reveal] = .double(s.overlay == .inset ? 0.0625 * inch : 0.125 * inch)
            p[edgeReveal] = .double(0.0625 * inch)
            p[edgeProfile] = .text(s.profile?.rawValue ?? "Square")
            p[FurniturePartTypes.coreMaterial] = .ref(mat[s.core])
            let slab = s.style == .slab
            p[FurniturePartTypes.edgeMaterial] = .ref(slab ? mat["Edge Banding"] : nil)
            p[FurniturePartTypes.edgeThickness] = .double(slab ? 0.02 * inch : 0)
            p[FurniturePartTypes.banding] = .text(slab ? "L1 L2 W1 W2" : "None")
            p[FurniturePartTypes.grain] = .text(GrainDirection.length.rawValue)
            p[stileWidth] = .double(2.25 * inch)
            p[railWidth] = .double(2.25 * inch)
            p[panelThickness] = .double(s.style == .glass ? 0.125 * inch : 0.25 * inch)
            p[panelRecess] = .double(0.25 * inch)
            p[panelMaterial] = .ref(s.style == .glass ? mat["Glass"] : (s.style == .shaker ? mat["MDF"] : nil))
            p[louverPitch] = .double(1.25 * inch)
            p[handleType] = .ref(FurnitureHardware.type(s.handle.0, s.handle.1, tx.model))
            p[handleOffset] = .double(s.family == .door ? 2.5 * inch : 0)
            p[hingeInset] = .double(3 * inch)
            switch s.family {
            case .door, .flap:
                let hinge = switch s.overlay { case .full: "Full Overlay 110°"; case .half: "Half Overlay 110°"; case .inset: "Inset 110°" }
                p[hingeType] = .ref(FurnitureHardware.type(FurnitureHardware.concealedHinge, hinge, tx.model))
                if s.family == .flap {
                    p[flapAction] = .text(s.flap.rawValue)
                    p[stayType] = .ref(FurnitureHardware.type(FurnitureHardware.flapStay, s.flap == .liftUp ? "Lift-Up Stay" : "Drop-Down Stay", tx.model))
                }
            case .drawer:
                p[slideType] = .ref(FurnitureHardware.type(s.slide, "18\"", tx.model))
                p[boxSide] = .double(0.5 * inch)
                p[boxBack] = .double(0.5 * inch)
                p[boxBottom] = .double(0.25 * inch)
                p[boxMaterial] = .ref(mat["Solid Maple"])
                p[bottomMaterial] = .ref(mat["Plywood"])
                p[boxJoint] = .text(DrawerBoxJoint.dovetail.rawValue)
            }
            tx.create(.elementTypes, name: s.name, data: .type(TypeData(instanceCategory: .furnitureFronts, familyName: s.family.rawValue, params: p)))
        }
        ensureTags(in: tx)
    }

    /// The default front type of a kind.
    public static func firstType(_ kind: FrontKind, _ m: BIMModel) -> ElementID? {
        let list = m.types(for: .furnitureFronts).filter { $0.typeData?.familyName == kind.rawValue }
        return (list.first { $0.name == defaultNames[kind] } ?? list.first)?.id
    }

    // MARK: Tags

    public static let bayTagName = "Bay Tag"
    public static let frontTagName = "Front Tag"

    /// The Bay Tag (name over the opening W x H, as a room tag) and the Front Tag (the Mark in a box, as a door tag).
    static func ensureTags(in tx: TransactionContext) {
        let families = Set(tx.model.elements(.families).map(\.name))
        if !families.contains(bayTagName) {
            var f = FamilyDefinition(name: bayTagName, template: .tag)
            f.taggedCategories = [.furnitureBays]
            f.types = [FamilyTypeDefinition(name: "Name and Opening", values: [:])]
            f.labels = [
                FamilyLabel(position: FamilyPoint("0", "0.0016"), parameterName: "Name", height: 0.0022, bold: true, sample: "Bay 1"),
                FamilyLabel(position: FamilyPoint("0", "-0.0018"), parameterName: "Opening", height: 0.0018, sample: "14 1/2\" x 30\""),
            ]
            let fid = tx.create(.families, name: f.name, data: .family(f))
            tx.create(.elementTypes, name: "Name and Opening", data: .type(TypeData(instanceCategory: .tags, familyID: fid, familyName: f.name)))
        }
        if !families.contains(frontTagName) {
            var f = FamilyDefinition(name: frontTagName, template: .tag)
            f.taggedCategories = [.furnitureFronts]
            f.types = [FamilyTypeDefinition(name: "Mark", values: [:])]
            let w = "0.0045", h = "0.0025"
            f.annotationLines = [
                FamilyLine(shape: .line(FamilyPoint("-\(w)", "-\(h)"), FamilyPoint(w, "-\(h)"))), FamilyLine(shape: .line(FamilyPoint(w, "-\(h)"), FamilyPoint(w, h))),
                FamilyLine(shape: .line(FamilyPoint(w, h), FamilyPoint("-\(w)", h))), FamilyLine(shape: .line(FamilyPoint("-\(w)", h), FamilyPoint("-\(w)", "-\(h)"))),
            ]
            f.fills = [FamilyFill(points: [FamilyPoint("-\(w)", "-\(h)"), FamilyPoint(w, "-\(h)"), FamilyPoint(w, h), FamilyPoint("-\(w)", h)], isMasking: true)]
            f.labels = [FamilyLabel(position: FamilyPoint("0", "0"), parameterName: "Mark", height: 0.0022, bold: true, sample: "D1")]
            let fid = tx.create(.families, name: f.name, data: .family(f))
            tx.create(.elementTypes, name: "Mark", data: .type(TypeData(instanceCategory: .tags, familyID: fid, familyName: f.name)))
        }
    }
}
