import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// W4-HATCH: interaction QA for cut and surface patterns (hooked from `interaction()` with one line).
extension QAHarness {
    /// Gives the QA building a brick-on-CMU wall and a concrete floor, screenshots the plan at coarse, medium and
    /// fine detail and a section through it, opens the Fill Patterns dialog, and checks that the display list carries
    /// line-family hatches at fine detail and solid poché at coarse. Everything is undone again afterwards.
    static func hatchInteraction(_ s: DocumentState, _ d: CanvasDriver) async {
        await step("Canvas: cut patterns at coarse/medium/fine, section, Fill Patterns dialog") {
            let before = d.failures.count
            guard let plan = s.activeViewID, let level = s.model.levels.first else { throw QAError("no active plan") }
            let m = s.model
            guard let brick = m.types(for: .walls).first(where: { $0.name == "Exterior - Brick on CMU" })?.id,
                  let slabType = m.types(for: .floors).first?.id,
                  let wall = m.elements(.walls).first?.id else { throw QAError("template types or walls missing") }
            // Cleanup is explicit (reverse edits), never undo: undo counting is fragile across run-loop turns.
            let originalType = m[wall]?.typeID
            let originalDetail = m[plan]?.view?.detailLevel ?? .medium
            var floorID: ElementID?
            s.session.perform("QA hatch: brick wall and concrete floor") { tx in
                tx.update(wall) { $0.typeID = brick }
                floorID = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: Vec2(0.1, 0.1), max: Vec2(11.9, 7.9))))), typeID: slabType, levelID: level.id)
            }
            var sv = ViewData(kind: .section, scale: 20)
            sv.planeOrigin = Vec3(6, 4, 0)
            sv.viewDirection = Vec2(0, 1)
            sv.cropRegion = Rect2(min: Vec2(-7, -1), max: Vec2(7, 5))
            sv.cropActive = true
            sv.farClip = 10
            sv.detailLevel = .fine
            var sectionID: ElementID?
            s.session.perform("QA hatch: section") { tx in sectionID = tx.create(.views, name: "QA Hatch Section", data: .view(sv)) }
            defer {
                s.open(plan)
                s.session.perform("QA hatch: restore") { tx in
                    tx.update(wall) { $0.typeID = originalType }
                    tx.update(plan) { $0.view?.detailLevel = originalDetail }
                }
                s.session.delete([floorID, sectionID].compactMap { $0 })
            }
            var solidAtCoarse = false, hatchedAtFine = false
            for detail in [DetailLevel.coarse, .medium, .fine] {
                s.session.perform("QA hatch: detail \(detail.rawValue)") { tx in tx.update(plan) { $0.view?.detailLevel = detail } }
                await d.settle()
                _ = await d.verify("hatch plan \(detail.rawValue)")
                let fills = s.graphics.graphics(plan)?.items.filter { $0.category == .walls && $0.layer == .cut }.flatMap(\.primitives).compactMap { p -> GFill? in
                    if case .fill(_, let f) = p { return f } else { return nil }
                } ?? []
                if detail == .coarse { solidAtCoarse = !fills.isEmpty && fills.allSatisfy { $0.pattern == .solid } }
                if detail == .fine { hatchedAtFine = fills.contains { $0.hatch != nil && !$0.hatch!.isEmpty } }
            }
            if let sectionID {
                s.open(sectionID)
                await d.settle()
                _ = await d.verify("hatch section fine")
                let sectionHatches = s.graphics.graphics(sectionID)?.items.filter { $0.layer == .cut }.flatMap(\.primitives).filter { p in
                    if case .fill(_, let f) = p { return f.hatch != nil } else { return false }
                }.count ?? 0
                try check(sectionHatches > 0, "the section has no line-family cut hatches")
            }
            s.open(plan)
            await d.settle()
            CommandRouter(state: s).run(.fillPatterns)
            await pause(250)
            try check(s.presented == .additionalSettings(.fillPatterns), "Fill Patterns did not open Additional Settings ▸ Fill Patterns")
            _ = await d.verify("fill patterns dialog")
            s.presented = nil
            await pause(120)
            try check(solidAtCoarse, "coarse plan does not draw solid poché for walls")
            try check(hatchedAtFine, "fine plan has no line-family cut hatches for walls")
            let new = d.failures.dropFirst(before)
            try check(new.isEmpty, new.joined(separator: " || "))
            return "plan at coarse/medium/fine and a 1:20 section screenshotted; solid poché at coarse, line-family hatches at fine; \(s.model.elements(.fillPatterns).count) fill patterns in the project"
        }
    }
}
