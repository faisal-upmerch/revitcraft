import Foundation
import ArcusGeometry

// F2: stacked walls (RevitCraft `WallKind::Stacked`, `SystemType::stack`): a wall type made of basic wall types stacked
// by height. Docs/RevitCraftPort.md §5.

/// One basic wall type in a stacked wall, from the bottom up.
public struct StackedWallPart: Hashable, Codable, Sendable {
    /// The basic wall type of this part (nil = the generic 200 mm wall).
    public var typeID: ElementID?
    /// Height of the part; 0 = variable (it takes whatever height the other parts leave).
    public var height: Double
    /// Offset of the part's location line from the stacked wall's, toward the exterior.
    public var offset: Double
    /// The part is flipped relative to the stacked wall (exterior and interior swap).
    public var flipped: Bool?
    public init(typeID: ElementID?, height: Double, offset: Double = 0, flipped: Bool? = nil) {
        self.typeID = typeID; self.height = height; self.offset = offset; self.flipped = flipped
    }
    public var isVariable: Bool { height <= Tolerance.length }
}

/// The structure of a stacked wall type.
public struct StackedWallSpec: Hashable, Codable, Sendable {
    /// Parts from the bottom up. One part is variable; when none is, the top part is.
    public var parts: [StackedWallPart]
    public init(parts: [StackedWallPart]) { self.parts = parts }

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case noParts, negativeHeight(Int), severalVariable
        public var description: String {
            switch self {
            case .noParts: "A stacked wall needs at least one wall type."
            case .negativeHeight(let i): "The height of part \(i + 1) can't be negative."
            case .severalVariable: "Only one part of a stacked wall can have a variable height."
            }
        }
    }
    public func validate() -> ValidationError? {
        if parts.isEmpty { return .noParts }
        if let i = parts.firstIndex(where: { $0.height < -Tolerance.length }) { return .negativeHeight(i) }
        if parts.filter(\.isVariable).count > 1 { return .severalVariable }
        return nil
    }

    /// The index of the part that takes the remaining height: the variable one, else the top one.
    public var variableIndex: Int { parts.firstIndex(where: \.isVariable) ?? max(0, parts.count - 1) }

    /// The parts' height bands over a wall from `base` to `top`, bottom up: the fixed parts keep their heights, the
    /// variable part takes the rest, and parts above the wall's top are clipped (or left out).
    public func bands(base: Double, top: Double) -> [(index: Int, z0: Double, z1: Double)] {
        let fixed = parts.enumerated().filter { $0.offset != variableIndex }.reduce(0) { $0 + max(0, $1.element.height) }
        let variable = max(0, top - base - fixed)
        var out: [(Int, Double, Double)] = []
        var z = base
        for (i, p) in parts.enumerated() {
            let h = i == variableIndex ? variable : max(0, p.height)
            let z1 = min(top, z + h)
            if z1 - z > Tolerance.length { out.append((i, z, z1)) }
            z = z1
            if z >= top - Tolerance.length { break }
        }
        return out
    }
}
