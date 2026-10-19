import Foundation
import ArcusGeometry

// FM5: the built-in Furniture Hardware families (Docs/FurnitureMode.md §2 "Component" and §3 "Hardware"). They are
// ordinary loadable families in the Furniture Hardware category, written here as data like the component library:
// hinges, drawer slides, handles, flap stays, glides, casters, shelf pins and connectors. Their types carry the cost
// (USD, editable in Edit Type ▸ Identity Data), manufacturer, model and the drill pattern (cup diameter, depth and
// offset, screw spacing…) that machining reads. Fronts place them automatically (FurnitureFronts); users place them
// with Component or Hardware.
//
// Each family is drawn in a local frame tied to how it mounts: for hinges, a runs from the hinge edge into the opening,
// b along the edge and c behind the front's back face; for handles a runs along the handle, b across it and c out of
// the face. Yes/No instance parameters pick the orientation (Top Edge, Bottom Edge, Back Edge; Vertical, On Lid), so a
// hinge on a lift-up flap is the same type as on a door, as in a Revit family with visibility parameters.

/// What a hardware type is, for placement, schedules and machining.
public enum HardwareKind: String, Codable, Sendable, CaseIterable {
    case hinge = "Hinge", slide = "Drawer Slide", handle = "Handle", stay = "Flap Stay", glide = "Glide", caster = "Caster"
    case shelfPin = "Shelf Pin", camLock = "Cam Lock", dowel = "Dowel", screw = "Screw"
}

public enum FurnitureHardware {
    static let inch = 0.0254
    static func mm(_ v: Double) -> Double { v / 1000 }

    /// Type parameter: the hardware kind (text), set on every hardware type.
    public static let kindParam = ParameterID("furniture.hardware.kind")
    /// Instance parameters of owned hardware: the front that owns it (ownerPartID) and its slot ("hinge.0", "handle.1").
    public static let ownerParam = ParameterID("furniture.hardware.owner")
    public static let slotParam = ParameterID("furniture.hardware.slot")

    public static let finishMaterial = "Finish Material"

    // MARK: Family names

    public static let concealedHinge = "Concealed Hinge - Frameless"
    public static let faceFrameHinge = "Concealed Hinge - Face Frame"
    public static let buttHinge = "Butt Hinge"
    public static let pianoHinge = "Piano Hinge"
    public static let sideMountSlide = "Drawer Slide - Side Mount"
    public static let undermountSlide = "Drawer Slide - Undermount"
    public static let barPull = "Bar Pull"
    public static let knob = "Knob"
    public static let cupPull = "Cup Pull"
    public static let edgePull = "Edge Pull"
    public static let flapStay = "Flap Stay"
    public static let glide = "Adjustable Glide"
    public static let caster = "Caster"
    public static let shelfPin = "Shelf Pin"
    public static let camLock = "Cam Lock and Bolt"
    public static let dowel = "Dowel"
    public static let confirmat = "Confirmat Screw"

    public static let kinds: [String: HardwareKind] = [
        concealedHinge: .hinge, faceFrameHinge: .hinge, buttHinge: .hinge, pianoHinge: .hinge,
        sideMountSlide: .slide, undermountSlide: .slide,
        barPull: .handle, knob: .handle, cupPull: .handle, edgePull: .handle,
        flapStay: .stay, glide: .glide, caster: .caster, shelfPin: .shelfPin, camLock: .camLock, dowel: .dowel, confirmat: .screw,
    ]

    /// Standard drawer slide lengths (12" to 24").
    public static let slideLengths: [Double] = [12, 14, 16, 18, 20, 22, 24]

    // MARK: Reading a type

    /// A hardware type's values (family type parameters and identity data) with defaults.
    public struct Values: Sendable {
        public var td: TypeData?
        public init(_ td: TypeData?) { self.td = td }
        func d(_ name: String, _ fallback: Double) -> Double { td?.params[Parameters.familyParamID(name)]?.doubleValue ?? fallback }
        public var kind: HardwareKind? {
            if let t = td?.params[FurnitureHardware.kindParam]?.textValue, let k = HardwareKind(rawValue: t) { return k }
            return td.flatMap { FurnitureHardware.kinds[$0.familyName] }
        }
        public var familyName: String { td?.familyName ?? "" }
        public var cost: Double { td?.params[ParameterID("type.cost")]?.doubleValue ?? 0 }
        // Hinges
        public var cupDiameter: Double { d("Cup Diameter", mm(35)) }
        public var cupDepth: Double { d("Cup Depth", mm(13)) }
        public var cupOffset: Double { d("Cup Offset", mm(22.5)) }
        public var cupScrewSpacing: Double { d("Cup Screw Spacing", mm(45)) }
        public var plateSetback: Double { d("Plate Setback", mm(37)) }
        public var plateHoleSpacing: Double { d("Plate Hole Spacing", mm(32)) }
        public var screwHoleDiameter: Double { d("Screw Hole Diameter", mm(5)) }
        public var screwHoleDepth: Double { d("Screw Hole Depth", mm(13)) }
        public var isConcealed: Bool { familyName == FurnitureHardware.concealedHinge || familyName == FurnitureHardware.faceFrameHinge || has("Cup Diameter") } // COMPA: any cup hinge
        public var isPiano: Bool { familyName == FurnitureHardware.pianoHinge || flag("Continuous") } // COMPA
        // Slides
        public var slideLength: Double { d("Slide Length", 18 * inch) }
        public var sideClearance: Double { d("Side Clearance", 0.5 * inch) }
        public var bottomClearance: Double { d("Bottom Clearance", 0.5 * inch) }
        public var topClearance: Double { d("Top Clearance", 0.5 * inch) }
        public var rearClearance: Double { d("Rear Clearance", 0.5 * inch) }
        public var slideHeight: Double { d("Slide Height", mm(45)) }
        public var firstHole: Double { d("First Hole", mm(37)) }
        public var holeSpacing: Double { d("Hole Spacing", mm(128)) }
        public var isUndermount: Bool { familyName == FurnitureHardware.undermountSlide || flag("Undermount") || slideMount == .undermount } // COMPA
        /// COMP: how the slide mounts (its "Slide Mounting" type value; FM5's undermount family, else a side pair).
        public var slideMount: ComponentSlideMount {
            if let t = td?.params[Parameters.familyParamID(ComponentSlideMount.parameter)]?.textValue, let m = ComponentSlideMount(rawValue: t) { return m }
            return familyName == FurnitureHardware.undermountSlide || flag("Undermount") ? .undermount : .sidePair
        }
        // Handles
        public var handleHoleSpacing: Double { isKnob ? 0 : d("Hole Spacing", mm(128)) }
        public var handleHoleDiameter: Double { d("Hole Diameter", mm(5)) }
        public var handleLength: Double { d("Length", mm(160)) }
        public var isEdgePull: Bool { familyName == FurnitureHardware.edgePull || flag("Edge Mounted") } // COMPA
        /// A one-screw handle: FM5's Knob, or (COMPA) any handle whose Hole Spacing is 0.
        public var isKnob: Bool { familyName == FurnitureHardware.knob || (has("Hole Spacing") && d("Hole Spacing", 1) < 1e-9) }
        // COMPA: Component Library families are recognised by their parameters as well as by FM5 family name.
        func has(_ name: String) -> Bool { td?.params[Parameters.familyParamID(name)] != nil }
        func flag(_ name: String) -> Bool { td?.params[Parameters.familyParamID(name)]?.boolValue == true }
    }

    public static func values(of e: Element, _ m: BIMModel) -> Values { Values(m.typeData(of: e)) }

    // MARK: Library

    /// One type of a hardware family: its values, cost and catalogue data.
    public struct TypeSpec: Sendable {
        public var name: String
        public var values: [String: ParamValue]
        public var cost: Double
        public var model: String
        public var description: String
    }

    /// A hardware family with its types.
    public struct FamilySpec: Sendable {
        public var family: FamilyDefinition
        public var kind: HardwareKind
        public var types: [TypeSpec]
    }

    /// Every built-in hardware family, with its types.
    public static var library: [FamilySpec] {
        [concealed(faceFrame: false), concealed(faceFrame: true), butt(), piano(), slide(undermount: false), slide(undermount: true),
         bar(), knobFamily(), cup(), edge(), stay(), glideFamily(), casterFamily(), pin(), cam(), dowelFamily(), screwFamily()]
    }

    /// Loads the built-in hardware families where missing, with their identity data (cost, manufacturer, model) and
    /// finish material; idempotent.
    public static func ensureLibrary(in tx: TransactionContext) {
        guard tx.model.isFurniture else { return }
        let steel = tx.model.elements(.materials).first { $0.name == "Steel" }?.id
        let brass = tx.model.elements(.materials).first { $0.name == "Brass" }?.id
        let wood = tx.model.elements(.materials).first { $0.name == "Solid Maple" }?.id
        for spec in library where tx.model.family(named: spec.family.name) == nil {
            let fid = FamilyProjectLoader.load(spec.family, replacing: nil, in: tx)
            for t in tx.model.elements(.elementTypes) where t.typeData?.familyID == fid {
                guard let ts = spec.types.first(where: { $0.name == t.name }) else { continue }
                let finish = spec.kind == .dowel ? wood : (spec.family.name == knob && ts.name.contains("Brass") ? brass : steel)
                tx.update(t.id) { e in
                    e.typeData?.params[kindParam] = .text(spec.kind.rawValue)
                    e.typeData?.params[ParameterID("type.cost")] = .double(ts.cost)
                    e.typeData?.params[ParameterID("type.manufacturer")] = .text("Generic")
                    e.typeData?.params[ParameterID("type.model")] = .text(ts.model)
                    e.typeData?.params[ParameterID("type.description")] = .text(ts.description)
                    if let finish { e.typeData?.params[Parameters.familyParamID(finishMaterial)] = .ref(finish) }
                }
            }
        }
    }

    /// The hardware types of a kind (all families), Type Selector order.
    public static func types(_ kind: HardwareKind, _ m: BIMModel) -> [Element] {
        m.types(for: .furnitureHardware).filter { Values($0.typeData).kind == kind }
    }

    /// A hardware type by family and type name.
    public static func type(_ family: String, _ name: String, _ m: BIMModel) -> ElementID? {
        let types = m.types(for: .furnitureHardware).filter { $0.typeData?.familyName == family }
        if let t = types.first(where: { $0.name == name }) { return t.id }
        // COMP: an upgraded family renamed its types ("128 mm" → "Bar Pull - 128 mm CC"): either name finds the type.
        guard let d = ComponentCatalog.current.definition(named: family) else { return nil }
        if let new = d.renamedTypes[name], let t = types.first(where: { $0.name == new }) { return t.id }
        if let old = d.renamedTypes.first(where: { $0.value == name })?.key, let t = types.first(where: { $0.name == old }) { return t.id }
        return nil
    }

    /// The slide type of `family` whose length is the longest standard length that fits `depth` (less the rear
    /// clearance); nil when even the shortest doesn't fit.
    public static func slide(family: String, fitting depth: Double, _ m: BIMModel) -> ElementID? {
        let list = m.types(for: .furnitureHardware).filter { $0.typeData?.familyName == family }
            .map { ($0.id, Values($0.typeData)) }
            .filter { $0.1.slideLength + $0.1.rearClearance <= depth + 1e-6 }
        return list.max { $0.1.slideLength < $1.1.slideLength }?.0
    }

    // MARK: Builder

    /// How a family's local frame (a, b, c) maps to family X, Y, Z: an axis and a sign per local axis.
    struct Frame: Sendable {
        var a: (FamilyAxis, Double), b: (FamilyAxis, Double), c: (FamilyAxis, Double)
        /// The Yes/No parameter that shows this frame's solids (nil = always).
        var visibility: String?
        static func make(_ a: (FamilyAxis, Double), _ b: (FamilyAxis, Double), _ c: (FamilyAxis, Double), _ v: String?) -> Frame { Frame(a: a, b: b, c: c, visibility: v) }
    }

    /// Hinges: on a side edge (a: +X into the opening, b: +Z along the edge, c: +Y behind the front), the top edge of a
    /// lift-up flap, the bottom edge of a drop-down flap, or the back edge of a lid.
    static let hingeFrames: [Frame] = [
        .make((.x, 1), (.z, 1), (.y, 1), "Side Edge"), .make((.z, -1), (.x, 1), (.y, 1), "Top Edge"),
        .make((.z, 1), (.x, 1), (.y, 1), "Bottom Edge"), .make((.y, -1), (.x, 1), (.z, -1), "Back Edge"),
    ]
    /// Handles: across a front (a: +X, c: -Y toward the viewer), standing up (a: +Z), or on a lid's top face.
    static let handleFrames: [Frame] = [
        .make((.x, 1), (.z, 1), (.y, -1), "Horizontal"), .make((.z, 1), (.x, 1), (.y, -1), "Upright"), .make((.x, 1), (.y, 1), (.z, 1), "On Lid"),
    ]
    /// Connectors: along X (into a side), or vertical.
    static let axisFrames: [Frame] = [.make((.x, 1), (.y, 1), (.z, 1), "Along X"), .make((.z, 1), (.x, 1), (.y, 1), "Vertical")]
    static let fixed: [Frame] = [.make((.x, 1), (.y, 1), (.z, 1), nil)]

    /// Writes a hardware family: parameters, frames and solids.
    struct Builder {
        var f: FamilyDefinition
        var types: [TypeSpec] = []
        var frames: [Frame]

        init(_ name: String, _ description: String, frames: [Frame]) {
            f = FamilyDefinition(name: name, template: .furnitureHardware)
            f.description = description
            f.manufacturer = "Generic"
            f.parameters = [FamilyParameter(name: FurnitureHardware.finishMaterial, type: .elementRef(.materials), group: .materials)]
            self.frames = frames
        }

        mutating func length(_ name: String, instance: Bool = false, group: ParameterGroup = .dimensions) {
            f.parameters.append(FamilyParameter(name: name, type: .length, isInstance: instance, group: group))
        }
        mutating func flag(_ name: String, formula: String? = nil) {
            f.parameters.append(FamilyParameter(name: name, type: .bool, isInstance: formula == nil, group: .constraints, formula: formula))
        }

        /// A range along one local axis written along its family axis (a negative sign mirrors it).
        static func range(_ lo: String, _ hi: String, sign: Double) -> (FamilyBound, FamilyBound) {
            sign > 0 ? (.expr(lo), .expr(hi)) : (.expr("-(\(hi))"), .expr("-(\(lo))"))
        }

        /// A box from local ranges, once per frame.
        mutating func box(_ name: String, a: (String, String), b: (String, String), c: (String, String), material: Bool = true) {
            for fr in frames {
                var r: [FamilyAxis: (FamilyBound, FamilyBound)] = [:]
                r[fr.a.0] = Self.range(a.0, a.1, sign: fr.a.1)
                r[fr.b.0] = Self.range(b.0, b.1, sign: fr.b.1)
                r[fr.c.0] = Self.range(c.0, c.1, sign: fr.c.1)
                guard let x = r[.x], let y = r[.y], let z = r[.z] else { continue }
                var s = FamilySolid(name: frames.count > 1 ? "\(name) (\(fr.visibility ?? ""))" : name,
                                    profile: .rectangle(xMin: x.0, xMax: x.1, yMin: y.0, yMax: y.1), zMin: z.0, zMax: z.1,
                                    materialParameter: material ? FurnitureHardware.finishMaterial : nil)
                s.visibilityParameter = fr.visibility
                s.visibleAt = [.medium, .fine]
                f.solids.append(s)
            }
        }

        /// A cylinder along local axis `along` (0 = a, 1 = b, 2 = c), centred at `center` on the other two local axes
        /// (in a, b, c order), once per frame.
        mutating func cylinder(_ name: String, along: Int, center: (String, String), radius: String, range: (String, String), material: Bool = true) {
            for fr in frames {
                let axes = [fr.a, fr.b, fr.c]
                let others = [0, 1, 2].filter { $0 != along }
                let (w, ws) = axes[along]
                let plane = FamilySketchPlane.normal(w)
                // The centre's family coordinates on the plane's u and v axes.
                var centre: [FamilyAxis: String] = [:]
                for (k, idx) in others.enumerated() {
                    let (ax, sg) = axes[idx]
                    let e = k == 0 ? center.0 : center.1
                    centre[ax] = sg > 0 ? e : "-(\(e))"
                }
                let z = Self.range(range.0, range.1, sign: ws)
                var s = FamilySolid(name: frames.count > 1 ? "\(name) (\(fr.visibility ?? ""))" : name,
                                    profile: .circle(center: FamilyPoint(.expr(centre[plane.axes.u] ?? "0"), .expr(centre[plane.axes.v] ?? "0")), radius: radius),
                                    zMin: z.0, zMax: z.1, materialParameter: material ? FurnitureHardware.finishMaterial : nil)
                if plane != .xy { s.workPlane = plane }
                s.visibilityParameter = fr.visibility
                s.visibleAt = [.medium, .fine]
                f.solids.append(s)
            }
        }

        mutating func type(_ name: String, _ values: [String: Double], flags: [String: Bool] = [:], cost: Double, model: String, _ description: String) {
            var v: [String: ParamValue] = [:]
            for (k, x) in values { v[k] = .double(x) }
            for (k, b) in flags { v[k] = .bool(b) }
            f.types.append(FamilyTypeDefinition(name: name, values: v))
            types.append(TypeSpec(name: name, values: v, cost: cost, model: model, description: description))
        }

        func spec(_ kind: HardwareKind) -> FamilySpec { FamilySpec(family: f, kind: kind, types: types) }
    }

    static func n(_ v: Double) -> String { "\(LX.num(v)) m" }

    /// The orientation flags of hinges, with the Side Edge formula that shows the side-edge solids.
    static func hingeFlags(_ b: inout Builder) {
        b.flag("Top Edge"); b.flag("Bottom Edge"); b.flag("Back Edge")
        b.flag("Side Edge", formula: "not(or(Top Edge, Bottom Edge, Back Edge))")
    }
    static let hingeFlagDefaults: [String: Bool] = ["Top Edge": false, "Bottom Edge": false, "Back Edge": false]

    static func handleFlags(_ b: inout Builder) {
        b.flag("Vertical"); b.flag("On Lid")
        b.flag("Horizontal", formula: "and(not(Vertical), not(On Lid))")
        b.flag("Upright", formula: "and(Vertical, not(On Lid))")
    }
    static let handleFlagDefaults: [String: Bool] = ["Vertical": false, "On Lid": false]

    // MARK: Hinges

    static func concealed(faceFrame: Bool) -> FamilySpec {
        var b = Builder(faceFrame ? faceFrameHinge : concealedHinge,
                        faceFrame ? "35 mm cup hinge with a compact plate for face-frame cabinets." : "35 mm concealed cup hinge with a clip-on mounting plate for frameless cabinets.",
                        frames: hingeFrames)
        for p in ["Cup Diameter", "Cup Depth", "Cup Offset", "Cup Screw Spacing", "Plate Setback", "Plate Hole Spacing", "Screw Hole Diameter", "Screw Hole Depth"] { b.length(p, group: .construction) }
        b.length("Side Offset", instance: true, group: .constraints)
        b.length("Front Edge", instance: true, group: .constraints)
        hingeFlags(&b)
        // The cup in the back of the front, its flange, the arm and the plate on the carcass.
        b.cylinder("Cup", along: 2, center: ("Cup Offset", "0 m"), radius: "Cup Diameter / 2", range: ("-Cup Depth", n(0.0015)))
        b.box("Flange", a: ("Cup Offset - Cup Diameter / 2", "Cup Offset + Cup Diameter / 2"), b: (n(-0.024), n(0.024)), c: ("0 m", n(0.0015)))
        if faceFrame {
            b.box("Arm", a: ("min(Side Offset, Cup Offset)", "max(Side Offset + 0.006 m, Cup Offset + 0.006 m)"), b: (n(-0.007), n(0.007)), c: (n(0.0015), "Front Edge + 0.012 m"))
            b.box("Plate", a: ("Side Offset", "Side Offset + 0.006 m"), b: (n(-0.018), n(0.018)), c: ("Front Edge", "Front Edge + 0.03 m"))
        } else {
            b.box("Arm", a: ("min(Side Offset, Cup Offset)", "max(Side Offset + 0.012 m, Cup Offset + 0.006 m)"), b: (n(-0.007), n(0.007)), c: (n(0.0015), "Front Edge + Plate Setback + 0.01 m"))
            b.box("Plate", a: ("Side Offset", "Side Offset + 0.01 m"), b: (n(-0.021), n(0.021)), c: ("Front Edge + Plate Setback - 0.02 m", "Front Edge + Plate Setback + 0.02 m"))
        }
        let common: [String: Double] = ["Cup Diameter": mm(35), "Cup Depth": mm(13), "Cup Screw Spacing": mm(45), "Plate Setback": mm(37), "Plate Hole Spacing": mm(32),
                                        "Screw Hole Diameter": mm(5), "Screw Hole Depth": mm(13), "Side Offset": mm(17.5), "Front Edge": 0]
        func with(_ cup: Double) -> [String: Double] { var c = common; c["Cup Offset"] = cup; return c }
        if faceFrame {
            b.type("1/2\" Overlay", with(mm(21.5)), flags: hingeFlagDefaults, cost: 4.25, model: "CHF-35-12", "Face-frame hinge, 1/2\" overlay, 110°")
            b.type("Inset", with(mm(22.5)), flags: hingeFlagDefaults, cost: 4.75, model: "CHF-35-IN", "Face-frame hinge, inset, 105°")
        } else {
            b.type("Full Overlay 110°", with(mm(22.5)), flags: hingeFlagDefaults, cost: 3.50, model: "CH-35-FO110", "Frameless hinge, full overlay, 110°, soft close")
            b.type("Half Overlay 110°", with(mm(22.5)), flags: hingeFlagDefaults, cost: 3.50, model: "CH-35-HO110", "Frameless hinge, half overlay (cranked), 110°")
            b.type("Inset 110°", with(mm(22.5)), flags: hingeFlagDefaults, cost: 3.75, model: "CH-35-IN110", "Frameless hinge, inset (cranked), 110°")
            b.type("Full Overlay 170°", with(mm(22.5)), flags: hingeFlagDefaults, cost: 6.25, model: "CH-35-FO170", "Frameless hinge, full overlay, 170° wide angle")
        }
        return b.spec(.hinge)
    }

    static func butt() -> FamilySpec {
        var b = Builder(buttHinge, "Butt hinge mortised into the front's edge and the carcass.", frames: hingeFrames)
        for p in ["Leaf Height", "Leaf Width", "Leaf Thickness", "Pin Diameter", "Screw Hole Diameter", "Screw Hole Depth"] { b.length(p, group: .construction) }
        b.length("Front Thickness", instance: true, group: .constraints)
        hingeFlags(&b)
        b.cylinder("Knuckle", along: 1, center: ("0 m", "-Front Thickness"), radius: "Pin Diameter / 2 + Leaf Thickness", range: ("-Leaf Height / 2", "Leaf Height / 2"))
        b.box("Front Leaf", a: ("0 m", "Leaf Thickness"), b: ("-Leaf Height / 2", "Leaf Height / 2"), c: ("-Front Thickness", "-Front Thickness + Leaf Width"))
        b.box("Carcass Leaf", a: ("-Leaf Thickness", "0 m"), b: ("-Leaf Height / 2", "Leaf Height / 2"), c: ("-Front Thickness", "-Front Thickness + Leaf Width"))
        for (h, cost) in [(2.0, 2.40), (2.5, 2.80), (3.0, 3.30)] {
            b.type("\(FurnitureSizeText.inches(h * inch))", ["Leaf Height": h * inch, "Leaf Width": 0.75 * inch, "Leaf Thickness": 0.07 * inch, "Pin Diameter": 0.19 * inch,
                                                               "Screw Hole Diameter": mm(3), "Screw Hole Depth": mm(12), "Front Thickness": 0.75 * inch],
                   flags: hingeFlagDefaults, cost: cost, model: "BH-\(Int(h * 10))", "Steel butt hinge, \(FurnitureSizeText.inches(h * inch)) x 1 1/2\" open")
        }
        return b.spec(.hinge)
    }

    static func piano() -> FamilySpec {
        var b = Builder(pianoHinge, "Continuous (piano) hinge along the whole edge.", frames: hingeFrames)
        for p in ["Leaf Width", "Leaf Thickness", "Pin Diameter", "Screw Hole Diameter", "Screw Hole Depth", "Screw Spacing"] { b.length(p, group: .construction) }
        b.length("Length", instance: true, group: .dimensions)
        b.length("Front Thickness", instance: true, group: .constraints)
        hingeFlags(&b)
        b.cylinder("Knuckle", along: 1, center: ("0 m", "-Front Thickness"), radius: "Pin Diameter / 2 + Leaf Thickness", range: ("-Length / 2", "Length / 2"))
        b.box("Front Leaf", a: ("0 m", "Leaf Thickness"), b: ("-Length / 2", "Length / 2"), c: ("-Front Thickness", "-Front Thickness + Leaf Width"))
        b.box("Carcass Leaf", a: ("-Leaf Thickness", "0 m"), b: ("-Length / 2", "Length / 2"), c: ("-Front Thickness", "-Front Thickness + Leaf Width"))
        b.type("1 1/2\" Open", ["Leaf Width": 0.75 * inch, "Leaf Thickness": 0.04 * inch, "Pin Diameter": 0.12 * inch, "Screw Hole Diameter": mm(3), "Screw Hole Depth": mm(10),
                                "Screw Spacing": 4 * inch, "Length": 30 * inch, "Front Thickness": 0.75 * inch],
               flags: hingeFlagDefaults, cost: 9.00, model: "PH-150", "Continuous steel hinge, 1 1/2\" open width, cut to length")
        return b.spec(.hinge)
    }

    // MARK: Slides

    static func slide(undermount: Bool) -> FamilySpec {
        var b = Builder(undermount ? undermountSlide : sideMountSlide,
                        undermount ? "Concealed undermount slide pair, full extension, soft close." : "Ball-bearing side-mount slide pair, full extension.",
                        frames: fixed)
        for p in ["Slide Length", "Slide Height", "Slide Thickness", "Slide Inset", "Side Clearance", "Bottom Clearance", "Top Clearance", "Rear Clearance",
                  "Front Setback", "First Hole", "Hole Spacing", "Screw Hole Diameter", "Screw Hole Depth"] { b.length(p, group: .construction) }
        b.length("Opening Width", instance: true, group: .dimensions)
        b.length("Mount Height", instance: true, group: .constraints)
        // The pair: one slide on each side of the opening, Opening Width apart (the origin is the left side's inside face
        // at the carcass front, at the bottom of the opening).
        let y = ("Front Setback", "Front Setback + Slide Length"), z = ("Mount Height - Slide Height / 2", "Mount Height + Slide Height / 2")
        b.box("Left Slide", a: ("Slide Inset", "Slide Inset + Slide Thickness"), b: y, c: z)
        b.box("Right Slide", a: ("Opening Width - Slide Inset - Slide Thickness", "Opening Width - Slide Inset"), b: y, c: z)
        for (k, l) in slideLengths.enumerated() {
            var v: [String: Double] = ["Slide Length": l * inch, "Rear Clearance": 0.5 * inch, "First Hole": mm(37), "Screw Hole Diameter": mm(4), "Screw Hole Depth": mm(12),
                                       "Opening Width": 15 * inch, "Mount Height": 1.5 * inch]
            if undermount {
                v["Slide Height"] = 0.75 * inch; v["Slide Thickness"] = 1 * inch; v["Slide Inset"] = 0.3125 * inch; v["Side Clearance"] = 0.3125 * inch
                v["Bottom Clearance"] = 0.5625 * inch; v["Top Clearance"] = 0.25 * inch; v["Front Setback"] = 0.25 * inch; v["Hole Spacing"] = mm(224)
            } else {
                v["Slide Height"] = mm(45); v["Slide Thickness"] = mm(12.7); v["Slide Inset"] = 0; v["Side Clearance"] = 0.5 * inch
                v["Bottom Clearance"] = 0.375 * inch; v["Top Clearance"] = 0.5 * inch; v["Front Setback"] = mm(2); v["Hole Spacing"] = mm(128)
            }
            let base = undermount ? 22.0 : 8.0, step = undermount ? 2.5 : 1.25
            b.type("\(Int(l))\"", v, cost: base + step * Double(k), model: (undermount ? "UMS-" : "SMS-") + "\(Int(l))",
                   (undermount ? "Undermount slide pair, " : "Side-mount slide pair, ") + "\(Int(l))\", full extension")
        }
        return b.spec(.slide)
    }

    // MARK: Handles

    static func bar() -> FamilySpec {
        var b = Builder(barPull, "Bar pull on two posts.", frames: handleFrames)
        for p in ["Hole Spacing", "Length", "Bar Diameter", "Projection", "Post Diameter", "Hole Diameter"] { b.length(p, group: .construction) }
        handleFlags(&b)
        b.cylinder("Bar", along: 0, center: ("0 m", "Projection - Bar Diameter / 2"), radius: "Bar Diameter / 2", range: ("-Length / 2", "Length / 2"))
        for s in ["-", ""] {
            b.cylinder("Post", along: 2, center: ("\(s)Hole Spacing / 2", "0 m"), radius: "Post Diameter / 2", range: ("0 m", "Projection - Bar Diameter / 2"))
        }
        for (cc, cost) in [(96.0, 4.50), (128, 5.25), (160, 6.25), (192, 7.50)] {
            b.type("\(Int(cc)) mm", ["Hole Spacing": mm(cc), "Length": mm(cc + 36), "Bar Diameter": mm(12), "Projection": mm(34), "Post Diameter": mm(10), "Hole Diameter": mm(5)],
                   flags: handleFlagDefaults, cost: cost, model: "BP-\(Int(cc))", "Bar pull, \(Int(cc)) mm centres, satin nickel")
        }
        return b.spec(.handle)
    }

    static func knobFamily() -> FamilySpec {
        var b = Builder(knob, "Round knob on one screw.", frames: handleFrames)
        for p in ["Diameter", "Projection", "Hole Diameter"] { b.length(p, group: .construction) }
        handleFlags(&b)
        b.cylinder("Stem", along: 2, center: ("0 m", "0 m"), radius: "Diameter * 0.3", range: ("0 m", "Projection * 0.6"))
        b.cylinder("Head", along: 2, center: ("0 m", "0 m"), radius: "Diameter / 2", range: ("Projection * 0.6", "Projection"))
        b.type("1 1/4\"", ["Diameter": 1.25 * inch, "Projection": 1 * inch, "Hole Diameter": mm(5)], flags: handleFlagDefaults, cost: 3.00, model: "KN-125", "Round knob, 1 1/4\", satin nickel")
        b.type("1 1/2\" Brass", ["Diameter": 1.5 * inch, "Projection": 1.125 * inch, "Hole Diameter": mm(5)], flags: handleFlagDefaults, cost: 4.75, model: "KN-150B", "Round knob, 1 1/2\", brass")
        return b.spec(.handle)
    }

    static func cup() -> FamilySpec {
        var b = Builder(cupPull, "Cup (bin) pull on two screws.", frames: handleFrames)
        for p in ["Hole Spacing", "Width", "Height", "Projection", "Hole Diameter"] { b.length(p, group: .construction) }
        handleFlags(&b)
        b.box("Plate", a: ("-Width / 2", "Width / 2"), b: ("-Height / 2", "Height / 2"), c: ("0 m", n(0.004)))
        b.box("Cup", a: ("-Width / 2 + 0.004 m", "Width / 2 - 0.004 m"), b: ("-Height / 2", "-Height / 6"), c: ("0 m", "Projection"))
        for (cc, cost) in [(64.0, 5.50), (96, 6.50)] {
            b.type("\(Int(cc)) mm", ["Hole Spacing": mm(cc), "Width": mm(cc + 22), "Height": mm(36), "Projection": mm(18), "Hole Diameter": mm(4)],
                   flags: handleFlagDefaults, cost: cost, model: "CP-\(Int(cc))", "Cup pull, \(Int(cc)) mm centres")
        }
        return b.spec(.handle)
    }

    static func edge() -> FamilySpec {
        var b = Builder(edgePull, "Edge pull over the front's top edge.", frames: handleFrames)
        for p in ["Length", "Lip", "Hole Spacing", "Hole Diameter"] { b.length(p, group: .construction) }
        b.length("Front Thickness", instance: true, group: .constraints)
        handleFlags(&b)
        b.box("Top Plate", a: ("-Length / 2", "Length / 2"), b: ("0 m", n(0.0025)), c: ("-Front Thickness", n(0.006)))
        b.box("Lip", a: ("-Length / 2", "Length / 2"), b: ("-Lip", n(0.0025)), c: (n(0.0035), n(0.006)))
        for (l, cost) in [(2.0, 6.00), (4.0, 8.50)] {
            b.type("\(Int(l))\"", ["Length": l * inch, "Lip": 0.75 * inch, "Hole Spacing": l * inch * 0.6, "Hole Diameter": mm(3), "Front Thickness": 0.75 * inch],
                   flags: handleFlagDefaults, cost: cost, model: "EP-\(Int(l))", "Edge pull, \(Int(l))\", screwed to the top edge")
        }
        return b.spec(.handle)
    }

    // MARK: Stays, glides, casters

    static func stay() -> FamilySpec {
        var b = Builder(flapStay, "Flap stay: lift-up mechanism or drop-down lid stay on the carcass side.", frames: fixed)
        for p in ["Body Length", "Body Height", "Body Width", "Arm Length", "Screw Hole Diameter", "Screw Hole Depth", "Screw Spacing"] { b.length(p, group: .construction) }
        b.flag("Drop Down")
        b.flag("Lift Up", formula: "not(Drop Down)")
        let saved = b.frames
        b.frames = [.make((.x, 1), (.y, 1), (.z, 1), "Lift Up")]
        b.box("Mechanism", a: ("0 m", "Body Width"), b: (n(0.015), "0.015 m + Body Length"), c: ("-Body Height", "0 m"))
        b.box("Arm", a: ("Body Width", "Body Width + 0.008 m"), b: (n(0.004), "Arm Length"), c: (n(-0.05), n(-0.035)))
        b.frames = [.make((.x, 1), (.y, 1), (.z, 1), "Drop Down")]
        b.box("Stay Arm", a: ("0 m", n(0.004)), b: (n(0.01), "0.01 m + Arm Length"), c: ("0 m", n(0.012)))
        b.box("Bracket", a: ("0 m", "Body Width"), b: ("0.01 m + Arm Length - 0.03 m", "0.01 m + Arm Length"), c: ("0 m", n(0.025)))
        b.frames = saved
        b.type("Lift-Up Stay", ["Body Length": mm(150), "Body Height": mm(110), "Body Width": mm(32), "Arm Length": mm(90), "Screw Hole Diameter": mm(5),
                                "Screw Hole Depth": mm(13), "Screw Spacing": mm(32)],
               flags: ["Drop Down": false], cost: 14.00, model: "FS-LU", "Lift-up flap stay, holds open at any angle")
        b.type("Drop-Down Stay", ["Body Length": mm(40), "Body Height": mm(25), "Body Width": mm(16), "Arm Length": mm(250), "Screw Hole Diameter": mm(4),
                                  "Screw Hole Depth": mm(12), "Screw Spacing": mm(24)],
               flags: ["Drop Down": true], cost: 7.50, model: "FS-DD", "Drop-down lid stay with soft close")
        return b.spec(.stay)
    }

    static func glideFamily() -> FamilySpec {
        var b = Builder(glide, "Adjustable leveling glide under the carcass.", frames: fixed)
        for p in ["Diameter", "Height", "Insert Diameter", "Hole Diameter", "Hole Depth"] { b.length(p, group: .construction) }
        b.cylinder("Pad", along: 2, center: ("0 m", "0 m"), radius: "Diameter / 2", range: ("-Height", "-Height + 0.005 m"))
        b.cylinder("Stem", along: 2, center: ("0 m", "0 m"), radius: n(0.004), range: ("-Height + 0.005 m", "0 m"))
        b.cylinder("Insert", along: 2, center: ("0 m", "0 m"), radius: "Insert Diameter / 2", range: ("0 m", "Hole Depth"))
        b.type("1\" Leveler", ["Diameter": 1 * inch, "Height": 0.75 * inch, "Insert Diameter": mm(10), "Hole Diameter": mm(10), "Hole Depth": mm(13)],
               cost: 1.25, model: "GL-100", "Leveling glide, 5/16\" thread, T-nut insert")
        b.type("1 1/2\" Leveler", ["Diameter": 1.5 * inch, "Height": 1 * inch, "Insert Diameter": mm(12), "Hole Diameter": mm(12), "Hole Depth": mm(16)],
               cost: 1.75, model: "GL-150", "Leveling glide, 3/8\" thread, T-nut insert")
        return b.spec(.glide)
    }

    static func casterFamily() -> FamilySpec {
        var b = Builder(caster, "Swivel plate caster under the carcass.", frames: fixed)
        for p in ["Wheel Diameter", "Wheel Width", "Plate Size", "Height", "Screw Hole Diameter", "Screw Spacing"] { b.length(p, group: .construction) }
        b.box("Plate", a: ("-Plate Size / 2", "Plate Size / 2"), b: ("-Plate Size / 2", "Plate Size / 2"), c: (n(-0.004), "0 m"))
        b.box("Fork", a: ("-Wheel Width / 2 - 0.003 m", "Wheel Width / 2 + 0.003 m"), b: ("-Wheel Diameter * 0.35", "Wheel Diameter * 0.35"), c: ("-Height + Wheel Diameter / 2", n(-0.004)))
        b.cylinder("Wheel", along: 0, center: ("0 m", "-Height + Wheel Diameter / 2"), radius: "Wheel Diameter / 2", range: ("-Wheel Width / 2", "Wheel Width / 2"))
        for (d, cost) in [(2.0, 5.50), (3.0, 7.50)] {
            b.type("\(Int(d))\" Swivel", ["Wheel Diameter": d * inch, "Wheel Width": 0.875 * inch, "Plate Size": 2.5 * inch, "Height": (d + 0.6) * inch,
                                          "Screw Hole Diameter": mm(4), "Screw Spacing": 1.75 * inch],
                   cost: cost, model: "CS-\(Int(d))S", "Swivel plate caster, \(Int(d))\" rubber wheel")
        }
        return b.spec(.caster)
    }

    // MARK: Pins and connectors

    static func pin() -> FamilySpec {
        var b = Builder(shelfPin, "Spoon shelf pin in a 5 mm hole.", frames: fixed)
        for p in ["Diameter", "Length", "Spoon Length"] { b.length(p, group: .construction) }
        b.cylinder("Pin", along: 0, center: ("0 m", "0 m"), radius: "Diameter / 2", range: ("-Length", "0 m"))
        b.box("Spoon", a: ("0 m", "Spoon Length"), b: ("-Diameter * 0.7", "Diameter * 0.7"), c: (n(-0.0015), "0 m"))
        b.type("5 mm Spoon", ["Diameter": mm(5), "Length": mm(8), "Spoon Length": mm(12)], cost: 0.08, model: "SP-5", "Nickel spoon shelf pin, 5 mm")
        b.type("1/4\" Spoon", ["Diameter": 0.25 * inch, "Length": 0.375 * inch, "Spoon Length": 0.5 * inch], cost: 0.09, model: "SP-14", "Nickel spoon shelf pin, 1/4\"")
        return b.spec(.shelfPin)
    }

    static func cam() -> FamilySpec {
        var b = Builder(camLock, "Cam lock in the shelf's face and its bolt in the side.", frames: fixed)
        for p in ["Cam Diameter", "Cam Depth", "Cam Distance", "Bolt Diameter", "Bolt Length", "Bolt Hole Diameter", "Bolt Hole Depth"] { b.length(p, group: .construction) }
        b.cylinder("Cam", along: 2, center: ("Cam Distance", "0 m"), radius: "Cam Diameter / 2", range: ("-Cam Depth", "0 m"))
        b.cylinder("Bolt", along: 0, center: ("0 m", "-Cam Depth / 2"), radius: "Bolt Diameter / 2", range: ("Cam Distance - Bolt Length", "Cam Distance"))
        b.type("15 mm", ["Cam Diameter": mm(15), "Cam Depth": mm(12.5), "Cam Distance": mm(24), "Bolt Diameter": mm(7), "Bolt Length": mm(34),
                         "Bolt Hole Diameter": mm(5), "Bolt Hole Depth": mm(11)],
               cost: 0.45, model: "CL-15", "Cam lock 15 mm with connecting bolt, for 16-19 mm panels")
        return b.spec(.camLock)
    }

    static func dowelFamily() -> FamilySpec {
        var b = Builder(dowel, "Fluted wood dowel.", frames: axisFrames)
        for p in ["Diameter", "Length"] { b.length(p, group: .construction) }
        b.flag("Vertical")
        b.flag("Along X", formula: "not(Vertical)")
        b.cylinder("Dowel", along: 0, center: ("0 m", "0 m"), radius: "Diameter / 2", range: ("-Length / 2", "Length / 2"))
        for (d, l, cost) in [(6.0, 30.0, 0.03), (8, 30, 0.04), (8, 40, 0.05), (10, 40, 0.06)] {
            b.type("\(Int(d)) x \(Int(l)) mm", ["Diameter": mm(d), "Length": mm(l)], flags: ["Vertical": false], cost: cost, model: "DW-\(Int(d))\(Int(l))",
                   "Fluted beech dowel, \(Int(d)) x \(Int(l)) mm")
        }
        return b.spec(.dowel)
    }

    static func screwFamily() -> FamilySpec {
        var b = Builder(confirmat, "Confirmat (one-piece connector) screw.", frames: axisFrames)
        for p in ["Diameter", "Length", "Head Diameter", "Pilot Diameter"] { b.length(p, group: .construction) }
        b.flag("Vertical")
        b.flag("Along X", formula: "not(Vertical)")
        b.cylinder("Shank", along: 0, center: ("0 m", "0 m"), radius: "Diameter / 2", range: ("0 m", "Length"))
        b.cylinder("Head", along: 0, center: ("0 m", "0 m"), radius: "Head Diameter / 2", range: (n(-0.001), n(0.005)))
        b.type("7 x 50 mm", ["Diameter": mm(7), "Length": mm(50), "Head Diameter": mm(10), "Pilot Diameter": mm(5)], flags: ["Vertical": false], cost: 0.10, model: "CF-750",
               "Confirmat screw 7 x 50 mm, stepped drill")
        return b.spec(.screw)
    }
}
