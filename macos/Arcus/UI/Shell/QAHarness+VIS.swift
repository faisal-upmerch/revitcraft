import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// VIS: screenshots of smooth curves and of the View Control Bar's state (hooked from `screenshots()` with one line, per
// appearance): a Furniture document with round, tapered, turned, caster and hairpin legs and a round-over top in {3D}
// at Coarse, Medium and Fine, Shaded and Hidden Line; the dining table at Fine; and a project with curved walls.
extension QAHarness {
    /// A Furniture document with a leg of every round type in a row and a butcher-block top with round-over edges.
    static func visLegsModel() -> BIMModel? {
        let inch = 0.0254
        let m = FurnitureTemplates.blank(category: .furniture, name: "Round Parts")
        let tx = TransactionContext(model: m, name: "Round Parts")
        FurniturePartTypes.ensureStandard(in: tx)
        let types = ["Round 1 1/2\"", "Round Tapered 2\"", "Turned 2 1/2\"", "Caster 2\"", "Hairpin 3/8\" Rod"]
        for (k, name) in types.enumerated() {
            guard let t = tx.model.types(for: .furnitureLegs).first(where: { $0.name == name })?.id else { continue }
            let height = name.hasPrefix("Caster") ? 3.0 : 16.0
            _ = try? FurniturePartOperations.createLeg(at: Vec2(Double(k) * 7 * inch, 0), extent: PartExtent(topPlane: nil, height: height * inch), typeID: t, in: tx)
        }
        let top = tx.model.types(for: .furnitureShelves).first { $0.name == "1 1/2\" Butcher Block" }?.id
        let x0 = -4 * inch, x1 = 32 * inch, y0 = 6 * inch, y1 = 14 * inch
        _ = try? FurniturePartOperations.createShelf(boundary: [Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)], plane: "Top", offset: 0,
                                                     role: .top, typeID: top, in: tx)
        return try? tx.commit().model
    }

    static func visScreenshots(_ suffix: String) async {
        var curved: BIMModel {
            let (m, ids) = ProjectTemplates.make(.architectural, units: .imperial, projectName: "Curved Walls")
            let tx = TransactionContext(model: m, name: "Curved walls")
            let type = ids.wallTypes.values.sorted().first
            tx.create(.walls, data: .wall(WallData(location: .arc(Arc2(center: .zero, radius: 6, startAngle: 0, sweep: .pi / 2)), unconnectedHeight: 3)),
                      typeID: type, levelID: ids.levels[0])
            tx.create(.walls, data: .wall(WallData(location: .arc(Arc2(center: Vec2(8, 0), radius: 1.5, startAngle: 0, sweep: .pi)), unconnectedHeight: 3)),
                      typeID: type, levelID: ids.levels[0])
            return (try? tx.commit().model) ?? m
        }
        let pieces: [(String, BIMModel?)] = [("round-parts", visLegsModel()), ("dining-table", FurnitureSamples.tableModel()), ("curved-walls", curved)]
        for (label, model) in pieces {
            guard let model else { continue }
            let doc = ArcusDocument(model: model, displayName: label)
            NSDocumentController.shared.addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
            await pause(800)
            guard let s = doc.state, let w = s.window, let v3 = view(s, kind: .threeD) else { doc.close(); continue }
            w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
            s.open(v3.id)
            let levels: [DetailLevel] = label == "round-parts" ? DetailLevel.allCases : [.fine]
            for d in levels {
                for style in [VisualStyle.shaded, .hiddenLine] {
                    s.session.perform("View") { tx in tx.update(v3.id) { e in if var v = e.view { v.detailLevel = d; v.visualStyle = style; e.view = v } } }
                    CommandRouter(state: s).run(.zoomExtents)
                    await pause(1200)
                    await shot(w, "vis-\(label)-\(d.rawValue.lowercased())-\(style == .shaded ? "shaded" : "hidden")-\(suffix)")
                }
            }
            // The View Control Bar with toggles on (shadows, section box, temporary hide).
            s.session.perform("View") { tx in tx.update(v3.id) { e in if var v = e.view { v.displayOptions.castShadows = true; v.sectionBoxActive = true; e.view = v } } }
            var temp = TemporaryVisibility()
            temp.hiddenCategories = [.levels]
            s.session.temporaryVisibility[v3.id] = temp
            await pause(800)
            await shot(w, "vis-\(label)-bar-toggles-on-\(suffix)")
            s.session.temporaryVisibility[v3.id] = nil
            doc.updateChangeCount(.changeCleared)
            doc.close()
            await pause(400)
        }
    }
}
