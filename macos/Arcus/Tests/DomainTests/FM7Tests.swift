import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

@Suite("FM7 Furniture fabrication") @MainActor
struct FM7Tests {
    static let inch = 0.0254

    @Test func probe() throws {
        let m = try #require(FurnitureSamples.baseCabinetModel())
        for p in FurnitureFabrication.parts(m) {
            print("PART", p.mark, p.name, m[p.materialID]?.name ?? "-", FurnitureSizeText.inches(p.length), FurnitureSizeText.inches(p.width), FurnitureSizeText.inches(p.thickness), p.grain, p.banding.code, p.quantity, FurnitureFabrication.cost(p, m))
        }
        for h in FurnitureFabrication.hardware(m) { print("HW", h.family, h.typeName, h.count, h.unitCost, h.source) }
        for g in FurnitureFabrication.nesting(m) { print("NEST", g.title, g.result.sheets.count, g.result.yield, g.result.oversize.count) }
        let s = try #require(m.elements(.schedules).first { $0.schedule?.kind == .partList })
        let t = ScheduleEngine.compute(s, m)
        print(ScheduleEngine.csv(t))
        for k in [ScheduleKind.hardwareSchedule, .edgeBanding, .costSummary, .materialTakeoff] {
            let s = try #require(m.elements(.schedules).first { $0.schedule?.kind == k })
            print(ScheduleEngine.csv(ScheduleEngine.compute(s, m)))
        }
        print("SHEETS", m.sheets.map { "\($0.sheet!.number) \($0.name) \(m.owned(byView: $0.id).count)" })
    }
}
