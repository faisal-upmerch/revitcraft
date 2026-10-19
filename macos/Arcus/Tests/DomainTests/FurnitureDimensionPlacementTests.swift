import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

/// The template's labelled dimensions stay outside the piece when it grows or shrinks.
@Suite("Furniture dimensions follow the piece") @MainActor
struct FurnitureDimensionPlacementTests {
    static let inch = 0.0254

    @Test func heightDimensionStaysRightOfAWiderPiece() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        func heightDim() throws -> DimensionData {
            try #require(s.model.elements(.dimensions).compactMap(\.dimension).first { $0.labelParameter == "Height" })
        }
        let gap0 = try heightDim().linePoint.x - 18 * Self.inch
        _ = s.perform("Width") { tx in try FurnitureParameters.setValue("Width", .double(60 * Self.inch), in: tx) }
        #expect(s.lastError == nil)
        let gap1 = try heightDim().linePoint.x - 30 * Self.inch
        #expect(abs(gap1 - gap0) < 1e-6, "same gap outside the Right plane: \(gap0) vs \(gap1)")
        // The Width dimension below the plan stays below when Depth grows.
        let width0 = try #require(s.model.elements(.dimensions).compactMap(\.dimension).first { $0.labelParameter == "Width" && $0.linePoint.y < 0 })
        _ = s.perform("Depth") { tx in try FurnitureParameters.setValue("Depth", .double(30 * Self.inch), in: tx) }
        let width1 = try #require(s.model.elements(.dimensions).compactMap(\.dimension).first { $0.labelParameter == "Width" && $0.linePoint.y < -15 * Self.inch })
        #expect(abs((width1.linePoint.y + 15 * Self.inch) - (width0.linePoint.y + 9 * Self.inch)) < 1e-6)
    }
}
