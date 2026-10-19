import Foundation
import ArcusGeometry

// Shared fabrication data for Furniture mode (Docs/FurnitureMode.md §3 "Joints" and "Fabrication outputs").
// Machining (drills, grooves, pockets) and derived parts (drawer boxes and other pieces that aren't drawn as elements)
// are computed from the model, never stored. Each batch adds its producer in its own file:
// FurnitureMachining+FM5.swift (fronts, hardware) and FurnitureMachining+FM6.swift (joints, shelf pins). FM7 reads
// `FurnitureMachining.entries` and `FurnitureMachining.derivedParts` for the Part List, nesting and CNC export.

/// Where a machining operation comes from.
public enum MachiningSource: Hashable, Sendable {
    /// A joint between two parts (dowels, cam locks, pocket screws, dados, rabbets, mortises).
    case joint(ElementID)
    /// A hardware family instance (hinge cups, slide screws, handle holes).
    case hardware(ElementID)
    /// A door, drawer or flap front.
    case front(ElementID)
    /// Adjustable shelf pin rows on a part.
    case shelfPins(ElementID)
}

/// One machining operation, in model coordinates (meters, like the rest of the model). `axis` is the unit direction
/// into the material from the face being machined.
public enum MachiningOp: Hashable, Sendable {
    case drill(center: Vec3, axis: Vec3, diameter: Double, depth: Double)
    case groove(start: Vec3, end: Vec3, axis: Vec3, width: Double, depth: Double)
    case pocket(outline: [Vec3], axis: Vec3, depth: Double)
}

/// A machining operation on one part.
public struct MachiningEntry: Hashable, Sendable {
    /// The part (panel, shelf, rail, leg, or a derived part's `sourceID`) being machined.
    public var partID: ElementID
    public var op: MachiningOp
    public var source: MachiningSource
    /// What it is, for drawings and CNC layer comments ("Dowel 8 mm", "Hinge cup 35 mm").
    public var label: String

    public init(partID: ElementID, op: MachiningOp, source: MachiningSource, label: String) {
        self.partID = partID; self.op = op; self.source = source; self.label = label
    }
}

/// A piece that goes on the cut list without being an element of its own (drawer box sides, fronts and bottoms).
public struct DerivedPart: Hashable, Sendable {
    /// Stable within one model state: e.g. "<front id>/drawer-side-left".
    public var key: String
    /// The element it belongs to (the drawer front, the joint).
    public var sourceID: ElementID
    public var name: String
    public var materialID: ElementID?
    public var length: Double
    public var width: Double
    public var thickness: Double
    public var grain: GrainDirection
    public var banding: EdgeBanding?
    public var quantity: Int

    public init(key: String, sourceID: ElementID, name: String, materialID: ElementID?, length: Double, width: Double,
                thickness: Double, grain: GrainDirection, banding: EdgeBanding? = nil, quantity: Int = 1) {
        self.key = key; self.sourceID = sourceID; self.name = name; self.materialID = materialID
        self.length = length; self.width = width; self.thickness = thickness; self.grain = grain
        self.banding = banding; self.quantity = quantity
    }
}

public enum FurnitureMachining {
    /// Every machining operation in a Furniture document.
    public static func entries(_ m: BIMModel) -> [MachiningEntry] {
        guard m.projectInfo.documentKind == .furniture else { return [] }
        return fm5Machining(m) + fm6Machining(m)
    }

    /// Every derived part in a Furniture document.
    public static func derivedParts(_ m: BIMModel) -> [DerivedPart] {
        guard m.projectInfo.documentKind == .furniture else { return [] }
        return fm5DerivedParts(m) + fm6DerivedParts(m)
    }
}
