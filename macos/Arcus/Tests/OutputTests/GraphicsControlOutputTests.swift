import CoreGraphics
import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusOutput

// BL-VG: Visibility/Graphics and Object Styles overrides reach the Core Graphics renderer used for PDF export and print.

@Suite("Graphics control output")
struct GraphicsControlOutputTests {
    /// Ink in a vertical run through the south wall (x = 5 m, y from −0.6 to 0.6 m) of the fixture's plan at 1:100.
    func wallInk(_ model: BIMModel) -> Int {
        let f = Fixture.shared
        let g = ViewGraphicsBuilder(model: model, view: model[f.plan]!).build()
        let b = Bitmap(100, 240)
        let t = CGAffineTransform(a: 200, b: 0, c: 0, d: 200, tx: 50 - 1000, ty: 120)
        GraphicsRenderer.draw(g, in: b.ctx, viewToDevice: t, pointsPerPaperMeter: 20_000, options: RenderOptions())
        return (0..<b.height).filter { b.ink(50, $0) >= 0.3 }.count
    }

    func committing(_ m: BIMModel, _ body: (TransactionContext) -> Void) throws -> BIMModel {
        let tx = TransactionContext(model: m, name: "Test")
        body(tx)
        return try tx.commit().model
    }

    @Test func cutLineWeightOverrideThickensWallsInPrint() throws {
        let f = Fixture.shared
        let base = wallInk(f.model)
        let overridden = try committing(f.model) { tx in
            tx.update(f.plan) { e in var o = GraphicOverride(); o.cutLineWeight = 12; e.view?.visibility.categoryOverrides[.walls] = o }
        }
        let thick = wallInk(overridden)
        #expect(base > 0)
        #expect(thick > base + 20, "weight 12 cut lines (3 mm) add ink outside the wall faces: \(base) → \(thick)")
    }

    @Test func objectStyleCutWeightThickensWallsInPrint() throws {
        let f = Fixture.shared
        let base = wallInk(f.model)
        let styled = try committing(f.model) { tx in
            tx.update(f.model.projectInfoElement!.id) { e in
                var os = ObjectStyleSettings(); os[.walls, nil] = ObjectStyleOverride(cutWeight: 12)
                e.projectInfo?.objectStyles = os
            }
        }
        #expect(wallInk(styled) > base + 20)
    }
}
