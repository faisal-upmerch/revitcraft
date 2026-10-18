import Foundation
import ArcusGeometry

// MARK: - Curtain wall type data

/// How a curtain wall type divides its length (vertical grid lines) or height (horizontal grid lines).
public enum CurtainGridLayout: String, Codable, Sendable, CaseIterable {
    case none = "None"
    /// Grid lines every `spacing`; the remainder goes where `justification` says.
    case fixedDistance = "Fixed Distance"
    /// `count` grid lines dividing the wall into equal panels.
    case fixedNumber = "Fixed Number"
    /// As few equal panels as possible, none wider than `spacing`.
    case maximumSpacing = "Maximum Spacing"
}

/// Where the first grid line of a fixed-distance layout is measured from.
public enum CurtainGridJustification: String, Codable, Sendable, CaseIterable {
    case beginning = "Beginning", center = "Center", end = "End"
}

/// One direction's grid rule of a curtain wall type.
public struct CurtainGridRule: Hashable, Codable, Sendable {
    public var layout: CurtainGridLayout
    /// Spacing for fixed-distance and maximum-spacing layouts (meters).
    public var spacing: Double
    /// Number of interior grid lines for the fixed-number layout.
    public var count: Int
    public var justification: CurtainGridJustification

    public init(layout: CurtainGridLayout = .none, spacing: Double = 1.5, count: Int = 3, justification: CurtainGridJustification = .beginning) {
        self.layout = layout; self.spacing = spacing; self.count = count; self.justification = justification
    }

    enum CodingKeys: String, CodingKey { case layout, spacing, count, justification }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = try c.decodeIfPresent(CurtainGridLayout.self, forKey: .layout) ?? .none
        spacing = try c.decodeIfPresent(Double.self, forKey: .spacing) ?? 1.5
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 3
        justification = try c.decodeIfPresent(CurtainGridJustification.self, forKey: .justification) ?? .beginning
    }

    /// Interior grid positions strictly inside (0, length), sorted ascending. Positions closer than 1 mm to an end
    /// are dropped, so a wall whose length is an exact multiple of the spacing gets no sliver panel.
    public func positions(length L: Double) -> [Double] {
        let tol = 0.001
        guard L > 2 * tol else { return [] }
        var out: [Double] = []
        switch layout {
        case .none:
            return []
        case .fixedDistance:
            guard spacing > tol else { return [] }
            let n = Int((L / spacing + 1e-9).rounded(.down))
            guard n <= 10_000 else { return [] }
            switch justification {
            case .beginning:
                for k in 1...max(1, n) { out.append(Double(k) * spacing) }
            case .end:
                for k in 1...max(1, n) { out.append(L - Double(k) * spacing) }
            case .center:
                let start = (L - Double(n) * spacing) / 2
                for k in 0...n { out.append(start + Double(k) * spacing) }
            }
        case .fixedNumber:
            let n = max(0, min(count, 10_000))
            for k in 0..<n { out.append(L * Double(k + 1) / Double(n + 1)) }
        case .maximumSpacing:
            guard spacing > tol else { return [] }
            let panels = Int((L / spacing - 1e-9).rounded(.up))
            guard panels > 1, panels <= 10_001 else { return [] }
            for k in 1..<panels { out.append(L * Double(k) / Double(panels)) }
        }
        return out.filter { $0 > tol && $0 < L - tol }.sorted()
    }
}

/// Rectangular mullion section: `width` is the face width seen in elevation, `depth` runs through the wall.
public struct MullionProfile: Hashable, Codable, Sendable {
    public var width: Double
    public var depth: Double
    public init(width: Double = 0.05, depth: Double = 0.15) { self.width = width; self.depth = depth }
}

/// What a curtain panel is made of.
public enum CurtainPanelKind: String, Codable, Sendable, CaseIterable {
    case glazed = "Glazed", solid = "Solid", empty = "Empty"
}

/// Type-level definition of a curtain wall: grid rules, the default panel type and automatic mullions.
public struct CurtainSpec: Hashable, Codable, Sendable {
    /// Vertical grid lines, spaced along the wall's length.
    public var vertical: CurtainGridRule
    /// Horizontal grid lines, spaced up the wall's height.
    public var horizontal: CurtainGridRule
    /// Default panel type (a type whose instance category is Curtain Panels). nil = glazed.
    public var panelTypeID: ElementID?
    /// Automatic mullions on interior vertical grid lines, interior horizontal grid lines and the four borders.
    public var verticalMullions: Bool
    public var horizontalMullions: Bool
    public var borderMullions: Bool
    public var mullion: MullionProfile
    public var mullionMaterialID: ElementID?

    public init(vertical: CurtainGridRule = CurtainGridRule(), horizontal: CurtainGridRule = CurtainGridRule(), panelTypeID: ElementID? = nil,
                verticalMullions: Bool = false, horizontalMullions: Bool = false, borderMullions: Bool = false,
                mullion: MullionProfile = MullionProfile(), mullionMaterialID: ElementID? = nil) {
        self.vertical = vertical; self.horizontal = horizontal; self.panelTypeID = panelTypeID
        self.verticalMullions = verticalMullions; self.horizontalMullions = horizontalMullions; self.borderMullions = borderMullions
        self.mullion = mullion; self.mullionMaterialID = mullionMaterialID
    }

    enum CodingKeys: String, CodingKey {
        case vertical, horizontal, panelTypeID, verticalMullions, horizontalMullions, borderMullions, mullion, mullionMaterialID
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vertical = try c.decodeIfPresent(CurtainGridRule.self, forKey: .vertical) ?? CurtainGridRule()
        horizontal = try c.decodeIfPresent(CurtainGridRule.self, forKey: .horizontal) ?? CurtainGridRule()
        panelTypeID = try c.decodeIfPresent(ElementID.self, forKey: .panelTypeID)
        verticalMullions = try c.decodeIfPresent(Bool.self, forKey: .verticalMullions) ?? false
        horizontalMullions = try c.decodeIfPresent(Bool.self, forKey: .horizontalMullions) ?? false
        borderMullions = try c.decodeIfPresent(Bool.self, forKey: .borderMullions) ?? false
        mullion = try c.decodeIfPresent(MullionProfile.self, forKey: .mullion) ?? MullionProfile()
        mullionMaterialID = try c.decodeIfPresent(ElementID.self, forKey: .mullionMaterialID)
    }

    /// Nominal thickness of the curtain wall (the deepest of its mullions and panels), used for its plan footprint.
    public var nominalThickness: Double { max(mullion.depth, 0.05) }
}

// MARK: - Curtain wall instance data

/// A panel type chosen for the panel that contains the seed point (station along the wall, height above its base).
/// Seeds are points rather than grid indices so overrides stay with their panel when grid lines are added elsewhere.
public struct CurtainPanelOverride: Hashable, Codable, Sendable {
    public var station: Double
    public var height: Double
    public var typeID: ElementID?
    public init(station: Double, height: Double, typeID: ElementID?) { self.station = station; self.height = height; self.typeID = typeID }
}

/// Adds or removes the mullion on the parts of one grid line whose midpoints fall inside `from…to`.
public struct CurtainMullionOverride: Hashable, Codable, Sendable {
    /// True for a vertical grid line (at a station), false for a horizontal one (at a height above the base).
    public var isVertical: Bool
    public var position: Double
    /// Span along the grid line: heights above the base (vertical) or stations (horizontal).
    public var from: Double
    public var to: Double
    public var present: Bool
    public init(isVertical: Bool, position: Double, from: Double, to: Double, present: Bool) {
        self.isVertical = isVertical; self.position = position; self.from = from; self.to = to; self.present = present
    }
}

/// Per-wall additions to a curtain wall's type layout: manually placed grid lines and panel and mullion overrides.
public struct CurtainInstanceData: Hashable, Codable, Sendable {
    /// Manual vertical grid lines (stations from the wall start, meters).
    public var verticalGrids: [Double]
    /// Manual horizontal grid lines (heights above the wall base, meters).
    public var horizontalGrids: [Double]
    public var panels: [CurtainPanelOverride]
    public var mullions: [CurtainMullionOverride]

    public init(verticalGrids: [Double] = [], horizontalGrids: [Double] = [], panels: [CurtainPanelOverride] = [], mullions: [CurtainMullionOverride] = []) {
        self.verticalGrids = verticalGrids; self.horizontalGrids = horizontalGrids; self.panels = panels; self.mullions = mullions
    }

    enum CodingKeys: String, CodingKey { case verticalGrids, horizontalGrids, panels, mullions }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verticalGrids = try c.decodeIfPresent([Double].self, forKey: .verticalGrids) ?? []
        horizontalGrids = try c.decodeIfPresent([Double].self, forKey: .horizontalGrids) ?? []
        panels = try c.decodeIfPresent([CurtainPanelOverride].self, forKey: .panels) ?? []
        mullions = try c.decodeIfPresent([CurtainMullionOverride].self, forKey: .mullions) ?? []
    }

    public var isEmpty: Bool { verticalGrids.isEmpty && horizontalGrids.isEmpty && panels.isEmpty && mullions.isEmpty }
}

// MARK: - Parameter ids

extension ParameterID {
    /// Curtain panel type parameters.
    public static let curtainPanelKind = ParameterID("panel.kind")
    public static let curtainPanelThickness = ParameterID("panel.thickness")
    public static let curtainPanelMaterial = ParameterID("type.material")
}
