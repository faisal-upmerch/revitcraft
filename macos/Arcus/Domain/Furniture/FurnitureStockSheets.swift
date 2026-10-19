import Foundation

// FM7: Manage ▸ Stock Sheets (Docs/FurnitureMode.md §3 "Nesting"): the sheet sizes parts are nested on, per material
// and thickness, with the kerf, edge trim, grain and rotation rules. Stored with the document on the furniture setup
// (`FurnitureSetupData.stockSheets`, nil = the defaults below), undoable like any other edit.

/// One stock size. A size with no material (or no thickness) is used for every material (or thickness) that has no
/// size of its own.
public struct StockSheetSize: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// The material it applies to (nil = any material).
    public var materialID: ElementID?
    /// The thickness it applies to (nil = any thickness).
    public var thickness: Double?
    /// Along the sheet's grain (x on nesting views).
    public var length: Double
    public var width: Double
    /// The sheet's grain: along its length, its width, or none (MDF, melamine).
    public var grain: GrainDirection
    /// Cost of one sheet (nil = the material's cost).
    public var cost: Double?

    public init(id: String = UUID().uuidString, name: String, materialID: ElementID? = nil, thickness: Double? = nil, length: Double, width: Double,
                grain: GrainDirection = .length, cost: Double? = nil) {
        self.id = id; self.name = name; self.materialID = materialID; self.thickness = thickness
        self.length = length; self.width = width; self.grain = grain; self.cost = cost
    }
}

/// How sheet goods are charged in costs.
public enum SheetCostBasis: String, Codable, Sendable, CaseIterable {
    /// Each part pays its share of the sheet by area.
    case area = "By Area"
    /// Every sheet the nesting uses is paid in full.
    case sheets = "By Sheets Used"
}

/// The document's Stock Sheets settings.
public struct FurnitureStockSheets: Hashable, Codable, Sendable {
    public var sizes: [StockSheetSize]
    public var kerf: Double
    public var edgeTrim: Double
    /// Parts without grain may turn 90° on the sheet.
    public var allowRotation: Bool
    public var method: NestingMethod
    public var costBasis: SheetCostBasis

    static let inch = 0.0254

    public init(sizes: [StockSheetSize], kerf: Double = 0.125 * 0.0254, edgeTrim: Double = 0.25 * 0.0254, allowRotation: Bool = true,
                method: NestingMethod = .best, costBasis: SheetCostBasis = .area) {
        self.sizes = sizes; self.kerf = kerf; self.edgeTrim = edgeTrim; self.allowRotation = allowRotation; self.method = method; self.costBasis = costBasis
    }

    /// 4' x 8' for everything, and 5' x 5' Baltic Birch.
    public static func defaults(_ m: BIMModel) -> FurnitureStockSheets {
        var sizes = [StockSheetSize(id: "default-4x8", name: "4' x 8'", length: 96 * inch, width: 48 * inch)]
        if let bb = m.elements(.materials).first(where: { $0.name == FurnitureFabrication.balticBirch }) {
            sizes.append(StockSheetSize(id: "default-5x5", name: "5' x 5' Baltic Birch", materialID: bb.id, length: 60 * inch, width: 60 * inch))
        }
        return FurnitureStockSheets(sizes: sizes)
    }

    /// The size parts of `material` and `thickness` are nested on: the most specific match (material and thickness,
    /// then material, then thickness, then any), else the first size, else 4' x 8'.
    public func size(material: ElementID?, thickness: Double) -> StockSheetSize {
        func t(_ s: StockSheetSize) -> Bool { s.thickness.map { abs($0 - thickness) < 0.0002 } ?? false }
        let ranked: [(StockSheetSize) -> Bool] = [
            { $0.materialID != nil && $0.materialID == material && t($0) },
            { $0.materialID != nil && $0.materialID == material && $0.thickness == nil },
            { $0.materialID == nil && t($0) },
            { $0.materialID == nil && $0.thickness == nil },
        ]
        for r in ranked { if let s = sizes.first(where: r) { return s } }
        return sizes.first ?? StockSheetSize(id: "default-4x8", name: "4' x 8'", length: 96 * Self.inch, width: 48 * Self.inch)
    }

    /// The engine's stock for a size.
    public func stock(_ s: StockSheetSize) -> NestStock {
        NestStock(length: s.length, width: s.width, grain: s.grain, kerf: kerf, trim: edgeTrim, allowRotation: allowRotation)
    }
}

extension BIMModel {
    /// FM7: the document's Stock Sheets (the defaults when never edited).
    public var stockSheets: FurnitureStockSheets { furnitureSetup?.stockSheets ?? FurnitureStockSheets.defaults(self) }
}
