import Foundation
import ArcusGeometry

// F34: Structure ▸ Reinforcement (rebar sets, area, path and fabric reinforcement, couplers), beam systems, the
// structural symbols of Annotate ▸ Symbol and Manage ▸ Structural Settings. Behaviour follows RevitCraft
// (crates/rc-core/src/rebar.rs and edit.rs). Lengths are meters; plan points are model XY. Wall-hosted reinforcement
// keeps its points in wall face coordinates: x along the wall from its start, y up from its base.

/// Structure ▸ Rebar: a set of straight bars in a floor or foundation slab at its bottom cover (host = `hostID`,
/// bar type = `typeID`).
public struct RebarData: Hashable, Codable, Sendable {
    public var start: Vec2
    public var end: Vec2
    /// Bars in the set (Layout Rule: Fixed Number), `spacing` apart to the left of start → end.
    public var count: Int
    public var spacing: Double
    public init(start: Vec2, end: Vec2, count: Int = 1, spacing: Double = 0.3) {
        self.start = start; self.end = end; self.count = max(1, count); self.spacing = spacing
    }
}

/// One layer of an area reinforcement.
public struct RebarLayer: Hashable, Codable, Sendable {
    public var on: Bool
    public var barTypeID: ElementID?
    public var spacing: Double
    public init(on: Bool = true, barTypeID: ElementID?, spacing: Double) { self.on = on; self.barTypeID = barTypeID; self.spacing = spacing }
}

/// Structure ▸ Area: bars in four layers (top major, top minor, bottom major, bottom minor) over a sketched area.
public struct AreaReinforcementData: Hashable, Codable, Sendable {
    /// Counter-clockwise boundary in host coordinates.
    public var boundary: [Vec2]
    /// Major direction (the first sketched edge by default).
    public var major: Vec2
    /// Top major, top minor, bottom major, bottom minor.
    public var layers: [RebarLayer]
    public init(boundary: [Vec2], major: Vec2, layers: [RebarLayer]) { self.boundary = boundary; self.major = major; self.layers = layers }
}

/// Structure ▸ Path: bars `spacing` apart along a sketched path, each `length` long, running into the host.
public struct PathReinforcementData: Hashable, Codable, Sendable {
    public var path: [Vec2]
    public var barTypeID: ElementID?
    public var spacing: Double
    public var length: Double
    /// Face: Top (else Bottom).
    public var top: Bool
    /// The bars run to the other side of the path.
    public var flip: Bool
    public init(path: [Vec2], barTypeID: ElementID?, spacing: Double, length: Double, top: Bool = true, flip: Bool = false) {
        self.path = path; self.barTypeID = barTypeID; self.spacing = spacing; self.length = length; self.top = top; self.flip = flip
    }
}

/// Structure ▸ Fabric Area: welded wire fabric sheets tiled over a sketched area along `major`, lapped at their edges.
public struct FabricAreaData: Hashable, Codable, Sendable {
    public var boundary: [Vec2]
    public var major: Vec2
    public var fabricTypeID: ElementID?
    public var top: Bool
    public var majorLap: Double
    public var minorLap: Double
    public init(boundary: [Vec2], major: Vec2, fabricTypeID: ElementID?, top: Bool = true, majorLap: Double = 0.2, minorLap: Double = 0.2) {
        self.boundary = boundary; self.major = major; self.fabricTypeID = fabricTypeID; self.top = top; self.majorLap = majorLap; self.minorLap = minorLap
    }
}

/// Structure ▸ Fabric Sheet: one sheet centred at `center`, its length along `angle` (radians); type = `typeID`.
public struct FabricSheetData: Hashable, Codable, Sendable {
    public var center: Vec2
    public var angle: Double
    public var top: Bool
    public init(center: Vec2, angle: Double = 0, top: Bool = true) { self.center = center; self.angle = angle; self.top = top }
}

/// Structure ▸ Rebar Coupler: couplers on one end of every bar of the host rebar set (`hostID`), joining
/// `otherRebarID`'s bars when placed between two sets.
public struct RebarCouplerData: Hashable, Codable, Sendable {
    public var atEnd: Bool
    public var otherRebarID: ElementID?
    public init(atEnd: Bool, otherRebarID: ElementID? = nil) { self.atEnd = atEnd; self.otherRebarID = otherRebarID }
}

/// Structure ▸ Beam System: beams of `beamTypeID` along `direction`, `spacing` apart across the boundary. Its beams
/// are hosted by it (`hostID`) and rebuilt whenever it changes.
public struct BeamSystemData: Hashable, Codable, Sendable {
    public var boundary: [Vec2]
    public var direction: Vec2
    public var spacing: Double
    public var beamTypeID: ElementID?
    /// Height of the beams' top above the level.
    public var elevation: Double
    public init(boundary: [Vec2], direction: Vec2, spacing: Double, beamTypeID: ElementID?, elevation: Double = 0) {
        self.boundary = boundary; self.direction = direction; self.spacing = spacing; self.beamTypeID = beamTypeID; self.elevation = elevation
    }
}

/// What a structural symbol shows (Annotate ▸ Symbol and Tag ▸ Multi-Rebar).
public enum StructuralSymbolKind: String, Codable, Sendable, CaseIterable {
    case beamSystem = "Beam System Symbol"
    case areaReinforcement = "Area Reinforcement Symbol"
    case pathReinforcement = "Path Reinforcement Symbol"
    case rebar = "Rebar Symbol"
    case fabric = "Fabric Reinforcement Symbol"
    case multiRebarAligned = "Aligned Multi-Rebar Annotation"
    case multiRebarLinear = "Linear Multi-Rebar Annotation"

    /// Whether `e` is an element this symbol annotates.
    public func fits(_ e: Element) -> Bool {
        switch (self, e.data) {
        case (.beamSystem, .beamSystem): true
        case (.beamSystem, .beam): e.category == .structuralFraming && e.beam?.curve.asSegment != nil
        case (.areaReinforcement, .areaReinforcement): true
        case (.pathReinforcement, .pathReinforcement): true
        case (.rebar, .rebar), (.multiRebarAligned, .rebar), (.multiRebarLinear, .rebar): true
        case (.fabric, .fabricArea), (.fabric, .fabricSheet): true
        default: false
        }
    }
}

/// A view-specific symbol of a host element (`hostID`), drawn at `position` in view coordinates.
public struct StructuralSymbolData: Hashable, Codable, Sendable {
    public var kind: StructuralSymbolKind
    public var position: Vec2
    public init(kind: StructuralSymbolKind, position: Vec2) { self.kind = kind; self.position = position }
}

/// A load case of Structural Settings: its name and nature.
public struct StructuralLoadCase: Hashable, Codable, Sendable {
    public var name: String
    public var nature: String
    public init(name: String, nature: String) { self.name = name; self.nature = nature }
    public static let natures = ["Dead", "Live", "Wind", "Snow", "Roof Live", "Accidental", "Temperature", "Seismic"]
}

/// A load combination of Structural Settings: its name and formula.
public struct StructuralLoadCombination: Hashable, Codable, Sendable {
    public var name: String
    public var formula: String
    public init(name: String, formula: String) { self.name = name; self.formula = formula }
}

/// Manage ▸ Structural Settings and Structure ▸ Cover (one element per project).
public struct StructuralSettingsData: Hashable, Codable, Sendable {
    /// Symbolic cutback distances on paper (meters): brace, beam/truss, column.
    public var braceCutback: Double
    public var beamCutback: Double
    public var columnCutback: Double
    /// Brace symbols in plan: parallel line (else line with angle), and the parallel line offset on paper.
    public var braceParallel: Bool
    public var braceOffset: Double
    /// Show brace above.
    public var kickerSymbol: Bool
    public var loadCases: [StructuralLoadCase]
    public var loadCombinations: [StructuralLoadCombination]
    /// Rebar Cover Settings: the concrete cover to the bars (0 = the default 40 mm / 1 1/2").
    public var rebarCover: Double

    public init() {
        braceCutback = 0.00238; beamCutback = 0.00238; columnCutback = 0.00238
        braceParallel = true; braceOffset = 0.00238; kickerSymbol = true
        loadCases = [("DL1", "Dead"), ("LL1", "Live"), ("WIND1", "Wind"), ("SNOW1", "Snow"), ("LR1", "Roof Live"), ("ACC1", "Accidental"),
                     ("TEMP1", "Temperature"), ("SEIS1", "Seismic")].map { StructuralLoadCase(name: $0.0, nature: $0.1) }
        loadCombinations = []
        rebarCover = 0
    }
}

// MARK: - Typed accessors

extension Element {
    public var rebar: RebarData? {
        get { if case .rebar(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .rebar(v) } }
    }
    public var areaReinforcement: AreaReinforcementData? {
        get { if case .areaReinforcement(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .areaReinforcement(v) } }
    }
    public var pathReinforcement: PathReinforcementData? {
        get { if case .pathReinforcement(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .pathReinforcement(v) } }
    }
    public var fabricArea: FabricAreaData? {
        get { if case .fabricArea(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .fabricArea(v) } }
    }
    public var fabricSheet: FabricSheetData? {
        get { if case .fabricSheet(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .fabricSheet(v) } }
    }
    public var rebarCoupler: RebarCouplerData? {
        get { if case .rebarCoupler(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .rebarCoupler(v) } }
    }
    public var beamSystem: BeamSystemData? {
        get { if case .beamSystem(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .beamSystem(v) } }
    }
    public var structuralSymbol: StructuralSymbolData? {
        get { if case .structuralSymbol(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .structuralSymbol(v) } }
    }
    public var structuralSettings: StructuralSettingsData? {
        get { if case .structuralSettings(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .structuralSettings(v) } }
    }
}

extension Category {
    /// F34: structural model categories shown in structural-discipline views as well.
    public static let f34Structural: [Category] = [.structuralRebar, .areaReinforcement, .pathReinforcement, .fabricAreas, .fabricReinforcement, .rebarCouplers, .beamSystems]
    /// F34: reinforcement categories (hosted by floors, foundation slabs and walls).
    public var isReinforcement: Bool { [.structuralRebar, .areaReinforcement, .pathReinforcement, .fabricAreas, .fabricReinforcement, .rebarCouplers].contains(self) }
}

extension BIMModel {
    /// The project's Structural Settings (defaults when none were saved).
    public var structuralSettings: StructuralSettingsData { elements(.structuralSettings).first?.structuralSettings ?? StructuralSettingsData() }
}

/// F34: plan transforms (Move, Rotate, Mirror, Copy, Array) of reinforcement, beam systems and structural symbols.
/// Wall-hosted reinforcement keeps face coordinates and moves only with its wall; couplers follow their rebar set.
enum ReinforcementTransform {
    static func apply(_ t: Transform2, to e: inout Element) -> Bool {
        let mirror = t.isMirroring
        func dir(_ d: Vec2) -> Vec2 { t.applyVector(d).normalized }
        func loop(_ pts: [Vec2]) -> [Vec2] { let q = pts.map(t.apply); return mirror ? q.reversed() : q }
        switch e.data {
        case .rebar(var r):
            // A reflection turns the set's left side to the right; swapping the ends puts every bar on its mirror image.
            (r.start, r.end) = mirror ? (t.apply(r.end), t.apply(r.start)) : (t.apply(r.start), t.apply(r.end))
            e.data = .rebar(r)
        case .areaReinforcement(var a):
            a.boundary = loop(a.boundary); a.major = dir(a.major)
            e.data = .areaReinforcement(a)
        case .pathReinforcement(var p):
            p.path = p.path.map(t.apply) // the bars still run into the host (pathSide)
            e.data = .pathReinforcement(p)
        case .fabricArea(var f):
            f.boundary = loop(f.boundary); f.major = dir(f.major)
            e.data = .fabricArea(f)
        case .fabricSheet(var f):
            f.center = t.apply(f.center); f.angle = dir(.fromAngle(f.angle)).angle
            e.data = .fabricSheet(f)
        case .beamSystem(var b):
            b.boundary = loop(b.boundary); b.direction = dir(b.direction)
            e.data = .beamSystem(b)
        case .structuralSymbol(var s):
            s.position = t.apply(s.position)
            e.data = .structuralSymbol(s)
        case .rebarCoupler:
            return true
        default:
            return false
        }
        return true
    }
}
