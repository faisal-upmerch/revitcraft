import Foundation
import ArcusGeometry

// COMPB: connectors from the Component Library in joints. Joint Rules and the Joint tool pick a fastener component for
// a joint (JointParameters.fastener): dowels for Dowel joints; cams, system cams and eccentrics for Cam Lock joints;
// confirmats, cross dowels and barrel nuts (with a furniture bolt) for Confirmat Screw joints; click clips for Biscuit
// joints; and corner blocks, brackets and knock-down fittings along Butt joints. The solver drills each one from its
// type's own parameters (cam diameter and drilling distance, bolt holes, pilot sizes, slot length), counts it in the
// Hardware Schedule under the component's name, and prices it from the component's type.

/// One connector type a joint can use, with the sizes the solver drills.
public struct JointFastener: Sendable, Hashable {
    public enum Style: String, Sendable, Hashable {
        /// Holes in both parts across the joint (dowels).
        case dowel
        /// A cam housing in the other part's face, the bolt in the through part's face and an edge hole between.
        case cam
        /// A stepped hole through the through part into the other part's end (confirmat).
        case screw
        /// A bolt through the through part into the other part's end, and a nut in a cross bore (cross dowels, barrel nuts).
        case boltAndNut
        /// A slot in both parts (click clips).
        case slot
        /// A block or bracket in the inside corner, screwed to both parts (butt joints).
        case bracket
    }

    public var definitionID: String
    public var family: String
    public var typeName: String
    public var style: Style
    public var cost: Double
    /// Dowel and screw diameter, cam housing diameter, cross nut diameter, bracket screw diameter.
    public var diameter: Double
    /// Dowel and screw length, cam housing depth, cross nut length, bracket screw length.
    public var length: Double
    /// Cam drilling distance and cross bore distance from the joint face; bracket screw distance from the corner.
    public var distance: Double
    /// The hole in the through part's face (cam bolt) or the pilot (confirmat), and its depth.
    public var faceHole: Double
    public var faceHoleDepth: Double
    /// The hole in the other part's edge (cam bolt, bolt to the nut).
    public var edgeHole: Double
    public var edgeHoleDepth: Double
    /// Default spacing along the joint and distance from its ends.
    public var spacing: Double
    public var edgeDistance: Double

    /// "<definition id>|<type name>", what JointParameters.fastener stores.
    public var key: String { "\(definitionID)|\(typeName)" }
    /// The type name when it already names the family ("Metal Dowel - 6 x 30 mm"), else "Family : Type" (FM5's
    /// "Dowel : 8 x 30 mm"): what Properties, Joint Rules and the Hardware Schedule show.
    public var name: String {
        let first = family.split(separator: " ").first.map(String.init) ?? family
        return typeName.hasPrefix(first) ? typeName : "\(family) : \(typeName)"
    }
}

public enum FurnitureJointFasteners {
    /// The component families each joint type can use, by family name.
    static let families: [JointType: [String]] = [
        .dowel: [FurnitureHardware.dowel, "Metal Dowel"],
        .camLock: [FurnitureHardware.camLock, "Cam and Bolt Connector", "Eccentric Connector", "Surface Cam Connector"],
        .confirmat: [FurnitureHardware.confirmat, "Cross Dowel", "Barrel Nut"],
        .biscuit: ["Furniture Assembly Clip"],
        .butt: ["Corner Bracket", "L-Bracket", "Angle Bracket", "Knock-Down Fitting"],
    ]

    /// Every fastener a joint type can use, Joint Rules order (family, then its types).
    public static func options(_ t: JointType) -> [JointFastener] { all.filter { families[t]?.contains($0.family) == true } }

    /// The joint types a fastener goes with.
    public static func jointTypes(of f: JointFastener) -> [JointType] { families.filter { $0.value.contains(f.family) }.map(\.key) }

    /// Every fastener (cached on first use).
    public static var all: [JointFastener] { cache.value }

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var stored: [JointFastener]?
        var value: [JointFastener] {
            lock.lock(); defer { lock.unlock() }
            if let s = stored { return s }
            let v = FurnitureJointFasteners.build()
            stored = v
            return v
        }
    }
    private static let cache = Cache()

    /// A fastener by its key (nil for nil or a key no longer in the library).
    public static func fastener(_ key: String?) -> JointFastener? {
        guard let key, !key.isEmpty else { return nil }
        return all.first { $0.key == key }
    }

    /// A fastener by its "Family : Type" name (the Hardware Schedule's line names).
    public static func fastener(named name: String) -> JointFastener? { all.first { $0.name == name } }

    static func build() -> [JointFastener] {
        var out: [JointFastener] = []
        let order = [JointType.dowel, .camLock, .confirmat, .biscuit, .butt]
        for jt in order {
            for fam in families[jt] ?? [] {
                guard let d = ComponentLibrary.component(named: fam) else { continue }
                for t in d.types { if let f = make(d, t, jt) { out.append(f) } }
            }
        }
        return out
    }

    /// A fastener from a component type's values (the parameter names Group B's definitions use).
    static func make(_ d: ComponentDefinition, _ t: ComponentType, _ jt: JointType) -> JointFastener? {
        func v(_ n: String, _ fallback: Double) -> Double { t.values[n]?.doubleValue ?? d.parameter(named: n)?.defaultValue?.doubleValue ?? fallback }
        let mm = 0.001, inch = 0.0254
        var f = JointFastener(definitionID: d.id, family: d.name, typeName: t.name, style: .dowel, cost: t.cost, diameter: 0, length: 0, distance: 0,
                              faceHole: 0, faceHoleDepth: 0, edgeHole: 0, edgeHoleDepth: 0, spacing: 6 * inch, edgeDistance: 1.5 * inch)
        switch (jt, d.name) {
        case (.dowel, _):
            f.style = .dowel; f.diameter = v("Diameter", 8 * mm); f.length = v("Length", 30 * mm)
        case (.camLock, FurnitureHardware.camLock):
            f.style = .cam; f.diameter = v("Cam Diameter", 15 * mm); f.length = v("Cam Depth", 12.5 * mm); f.distance = v("Cam Distance", 24 * mm)
            f.faceHole = v("Bolt Hole Diameter", 5 * mm); f.faceHoleDepth = v("Bolt Hole Depth", 11 * mm)
            f.edgeHole = v("Edge Hole Diameter", 8 * mm); f.edgeHoleDepth = v("Edge Hole Depth", 34 * mm)
            f.spacing = 12 * inch; f.edgeDistance = 37 * mm
        case (.camLock, "Cam and Bolt Connector"):
            f.style = .cam; f.diameter = v("Housing Diameter", 15 * mm); f.length = v("Housing Depth", 12.5 * mm); f.distance = v("Drilling Distance", 24 * mm)
            f.faceHole = v("Bolt Hole Diameter", 5 * mm); f.faceHoleDepth = v("Bolt Hole Depth", 11 * mm)
            f.edgeHole = v("Edge Hole Diameter", 8 * mm); f.edgeHoleDepth = f.distance + 2 * mm
            f.spacing = 12 * inch; f.edgeDistance = 37 * mm
        case (.camLock, "Eccentric Connector"):
            f.style = .cam; f.diameter = v("Body Diameter", 25 * mm); f.length = v("Body Depth", 14 * mm); f.distance = v("Center Distance", 20 * mm)
            f.faceHole = v("Pin Diameter", 6 * mm); f.faceHoleDepth = max(4 * mm, v("Pin Length", 30 * mm) - f.distance)
            f.edgeHole = v("Pin Diameter", 6 * mm) + 1 * mm; f.edgeHoleDepth = f.distance
            f.spacing = 12 * inch; f.edgeDistance = 37 * mm
        case (.camLock, "Surface Cam Connector"):
            // The housing sits in a shallow bore on the face; no edge hole, the bolt goes straight into the through part.
            f.style = .cam; f.diameter = v("Housing Diameter", 20 * mm); f.length = v("Bore Depth", 4 * mm); f.distance = v("Set Back", 9.5 * mm)
            f.faceHole = v("Bolt Diameter", 5 * mm); f.faceHoleDepth = v("Bolt Length", 12 * mm)
            f.spacing = 12 * inch; f.edgeDistance = 50 * mm
        case (.confirmat, FurnitureHardware.confirmat):
            f.style = .screw; f.diameter = v("Diameter", 7 * mm); f.length = v("Length", 50 * mm); f.faceHole = v("Pilot Diameter", 5 * mm)
            f.spacing = 8 * inch; f.edgeDistance = 2 * inch
        case (.confirmat, _):
            // Cross dowel / barrel nut with a furniture bolt of the nut's thread.
            f.style = .boltAndNut; f.diameter = v("Diameter", 10 * mm); f.length = v("Length", 20 * mm); f.distance = v("Bolt Distance", 25 * mm)
            let bolt = (t.values["Thread"]?.textValue ?? "M6").contains("8") ? 8 * mm : 6 * mm
            f.faceHole = bolt + 1 * mm; f.edgeHole = bolt + 1 * mm; f.edgeHoleDepth = f.distance + f.diameter / 2
            f.spacing = 12 * inch; f.edgeDistance = 2 * inch
        case (.biscuit, _):
            f.style = .slot; f.diameter = v("Clip Thickness", 4 * mm); f.length = v("Clip Length", 56 * mm); f.faceHoleDepth = v("Slot Depth", 10 * mm)
            f.spacing = 8 * inch; f.edgeDistance = 2 * inch
        case (.butt, _):
            f.style = .bracket; f.diameter = v("Screw Diameter", 4 * mm); f.length = v("Screw Length", 16 * mm)
            f.distance = max(v("Leg Length", 0), v("Leg A", 0), v("Block Width", 0) / 2) * 0.55
            if f.distance <= 0 { f.distance = 15 * mm }
            f.spacing = 12 * inch; f.edgeDistance = 2 * inch
        default:
            return nil
        }
        return f
    }

    /// The joint's parameters with the fastener's spacing and end distance where the joint leaves them unset.
    static func spacing(_ f: JointFastener, _ p: JointParameters) -> JointParameters {
        var q = p
        if q.spacing == nil { q.spacing = f.spacing }
        if q.edgeDistance == nil { q.edgeDistance = f.edgeDistance }
        return q
    }
}
