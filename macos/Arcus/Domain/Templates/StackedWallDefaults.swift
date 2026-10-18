import Foundation
import ArcusGeometry

/// F2: the starter stacked wall type (as RevitCraft's "Stacked - Concrete Base, Brick Above"): a concrete base of fixed
/// height under a masonry wall of variable height, made from the project's basic wall types.
public enum StackedWallDefaults {
    public static let family = "Stacked Wall"

    /// Creates the starter stacked type unless the project has one; returns its id (nil when there are no basic wall
    /// types to stack).
    @discardableResult
    public static func populate(_ tx: TransactionContext, metric: Bool = true) -> ElementID? {
        let m = tx.model
        if let t = m.types(for: .walls).first(where: { $0.typeData?.stack != nil }) { return t.id }
        let basic = m.types(for: .walls).filter { $0.typeData?.stack == nil && $0.typeData?.curtain == nil }
        guard !basic.isEmpty else { return nil }
        func named(_ words: [String]) -> Element? { basic.first { b in words.allSatisfy { b.name.localizedCaseInsensitiveContains($0) } } }
        func exact(_ n: String) -> Element? { basic.first { $0.name == n } }
        let base = exact("Exterior - Concrete 300mm") ?? named(["Concrete"]) ?? basic.max { WallGeometry.assembly(ofType: $0.typeData).totalThickness < WallGeometry.assembly(ofType: $1.typeData).totalThickness }!
        let above = exact("Exterior - Brick on CMU") ?? named(["Brick"]) ?? named(["Exterior"]) ?? basic.first { $0.id != base.id } ?? base
        var td = TypeData(instanceCategory: .walls, systemFamily: .stackedWall, familyName: family)
        td.stack = StackedWallSpec(parts: [StackedWallPart(typeID: base.id, height: metric ? 0.9 : 0.9144), StackedWallPart(typeID: above.id, height: 0)])
        td.params[ParameterID("type.function")] = .text("Exterior")
        return tx.create(.elementTypes, name: "Exterior - \(above.name.replacingOccurrences(of: "Exterior - ", with: "")) over \(base.name.replacingOccurrences(of: "Exterior - ", with: ""))", data: .type(td))
    }
}
