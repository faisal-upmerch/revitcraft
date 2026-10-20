import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// COMPB: screenshots of Component Library group B in a Furniture document (hooked from `screenshots()` with one line,
// per appearance): Joint Rules with connector components in the Fastener column (system cams for Shelf – Side, metal
// dowels for Side – Top, corner brackets for Shelf – Back), and the sample table on hairpin legs (a Leg type from
// the Component Library) in 3D.
extension QAHarness {
    static func compbScreenshots(_ suffix: String) async {
        AppDelegate.shared?.newFurniture(name: "Group B Components", category: .casework, template: nil)
        await pause(900)
        guard let s = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state, s.mode == .furniture, let w = s.window else { return }
        w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
        var ids: [String: ElementID] = [:]
        s.session.perform("Bookcase") { tx in ids = try FurnitureSamples.bookcase(in: tx) }
        s.session.perform("Fasteners") { tx in
            var r = tx.model.furnitureJointRules
            func set(_ pair: JointPairKind, _ t: JointType, _ family: String) {
                guard let f = FurnitureJointFasteners.options(t).first(where: { $0.family == family }) else { return }
                var rule = r.rule(pair, category: .casework)
                rule.type = t
                rule.parameters = JointParameters(fastener: f.key)
                if let i = r.rules.firstIndex(where: { $0.pair == pair }) { r.rules[i] = rule } else { r.rules.append(rule) }
            }
            set(.sideTop, .dowel, "Metal Dowel")
            set(.shelfSide, .camLock, "Cam and Bolt Connector")
            set(.shelfBack, .butt, "Corner Bracket")
            try FurnitureJointOperations.setRules(r, in: tx)
        }
        s.presented = .fm6(.jointRules)
        await pause(800)
        if let sheet = w.attachedSheet { await shot(sheet, "compb-joint-rules-fasteners-\(suffix)") } else { await shot(w, "compb-joint-rules-fasteners-\(suffix)") }
        s.presented = nil
        await pause(400)
        // A table on hairpin legs from the Component Library (a new document).
        AppDelegate.shared?.newFurniture(name: "Hairpin Table", category: .furniture, template: nil)
        await pause(900)
        guard let t = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state, t.mode == .furniture, let tw = t.window else { return }
        tw.setContentSize(NSSize(width: 1440, height: 900)); tw.center()
        t.session.perform("Table") { tx in ids = try FurnitureSamples.table(in: tx) }
        t.session.perform("Legs and Aprons") { tx in try FurnitureSamples.tableFinish(in: tx, ids) }
        t.session.perform("Hairpin Legs") { tx in
            if let d = ComponentLibrary.component(named: "Hairpin Leg"), let lt = ComponentLegTypes.ensureType(d, typeName: d.defaultType?.name ?? "", in: tx) {
                for l in tx.model.elements(.furnitureLegs) { tx.update(l.id) { $0.typeID = lt } }
            }
        }
        if let v3 = view(t, kind: .threeD) {
            t.open(v3.id)
            await pause(1400)
            await shot(tw, "compb-table-hairpin-legs-3d-\(suffix)")
        }
    }
}
