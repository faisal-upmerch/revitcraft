import Foundation
import ArcusGeometry

// F5: Analyze ▸ Spaces & Zones (RevitCraft rc-core edit.rs `add_space`). A space is a room-like region (category
// Spaces, data `.room`) bounded by walls, columns and space separation lines; spaces and rooms share regions without
// conflicting.
public enum SpacePlacement {
    /// The next space number: one more than the highest numeric space number (spaces start at 1).
    public static func nextNumber(_ model: BIMModel) -> Int {
        (model.elements(.spaces).compactMap { Int($0.room?.number ?? "") }.max() ?? 0) + 1
    }

    /// The enclosed region on `level` containing `p`, from walls, columns and space separators.
    public static func region(at p: Vec2, level: ElementID, _ model: BIMModel) -> Profile2? {
        let z = model.elevation(ofLevel: level) + max(model[level]?.level?.computationHeight ?? 0, 0.3)
        let arr = PlanarArrangement(segments: RoomGeometry.boundingSegments(level: level, atZ: z, model, separators: .spaceSeparationLines))
        return arr.face(containing: p)?.profile
    }

    /// Places a space at `p` (RevitCraft refuses points outside an enclosed region and a second space in a region).
    @discardableResult
    public static func place(at p: Vec2, level: ElementID, number: String? = nil, in tx: TransactionContext) throws -> ElementID {
        guard let region = region(at: p, level: level, tx.model) else {
            throw TransactionError("The space is not in a properly enclosed region. Click inside an area bounded by walls or space separators.")
        }
        let placed = RoomBoundaryCache.shared.boundaries(level: level, tx.model)
        for s in tx.model.elements(.spaces) where s.levelID == level {
            if let b = placed[s.id], b.state == .bounded, b.profile?.contains(p) == true, let q = s.room?.point, region.contains(q) {
                throw TransactionError("There is already a space in this region.", elements: [s.id])
            }
        }
        let n = number ?? String(nextNumber(tx.model))
        return tx.create(.spaces, name: "Space", data: .room(RoomData(point: p, number: n)), levelID: level)
    }
}

/// The space tag family (an Arcus original): the space's name over its number, loaded on demand.
public enum SpaceTags {
    public static let familyName = "Space Tag"

    public static func family() -> FamilyDefinition {
        var f = FamilyDefinition(name: familyName, template: .tag)
        f.taggedCategories = [.spaces]
        f.types = [FamilyTypeDefinition(name: "Name and Number", values: [:])]
        f.labels = [
            FamilyLabel(position: FamilyPoint("0", "0.0018"), parameterName: "Name", height: 0.0025, bold: true, sample: "SPACE"),
            FamilyLabel(position: FamilyPoint("0", "-0.0018"), parameterName: "Number", height: 0.0022, sample: "1"),
        ]
        return f
    }

    /// Loads the space tag family when the project has none; returns its first type.
    @discardableResult
    public static func ensure(in tx: TransactionContext) -> ElementID? {
        AnnotationLibrary.load(family(), in: tx).first
    }
}
