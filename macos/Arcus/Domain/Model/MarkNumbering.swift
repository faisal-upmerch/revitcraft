import Foundation

/// Automatic Mark numbering (BL-CANVAS, ARCUS-045). Instances of the categories that are counted one by one —
/// doors, windows, furniture, casework, fixtures and equipment — get the next unused integer Mark of their category
/// when they are created without one (placement, copy, array, mirror, paste). Editing a Mark to a value another
/// element of the same category already has is allowed, with a non-blocking warning.
public enum MarkNumbering {
    /// Categories whose new instances are numbered.
    public static let numberedCategories: Set<Category> = [
        .doors, .windows, .furniture, .casework, .genericModels, .plumbingFixtures, .specialtyEquipment,
        .mechanicalEquipment, .lightingFixtures, .electricalFixtures,
    ]

    /// The next Mark for a category: one more than the highest integer Mark in use (so undoing the last placement
    /// frees its number). Marks that aren't plain integers ("D-01", "101-WC1") are ignored.
    public static func nextMark(for category: Category, in model: BIMModel) -> String {
        var high = 0
        for e in model.elements(category) where !e.isType { if let n = Int(e.mark.trimmingCharacters(in: .whitespaces)), n > high { high = n } }
        return String(high + 1)
    }

    /// Numbers the instances created in `tx` that have no Mark, in creation order, and warns about Marks the
    /// transaction changed to a value already used in the category.
    public static func apply(_ tx: TransactionContext) {
        let ids = tx.touchedIDs
        var created: [ElementID] = []
        var edited: [ElementID] = []
        for id in ids {
            guard let e = tx.model[id], numberedCategories.contains(e.category), !e.isType else { continue }
            if let before = tx.originalElement(id) {
                if before.mark != e.mark, !e.mark.isEmpty { edited.append(id) }
            } else if e.mark.isEmpty {
                created.append(id)
            }
        }
        for id in created.sorted() {
            guard let c = tx.model[id]?.category else { continue }
            let mark = nextMark(for: c, in: tx.model)
            tx.update(id) { $0.mark = mark }
        }
        for id in edited {
            guard let e = tx.model[id] else { continue }
            let others = tx.model.elements(e.category).filter { $0.id != id && !$0.isType && $0.mark == e.mark }.map(\.id)
            guard !others.isEmpty else { continue }
            tx.warn(ModelWarning(.warning, code: "mark.duplicate",
                                 "Elements have duplicate “Mark” values: \(others.count + 1) \(e.category.displayName.lowercased()) use “\(e.mark)”.",
                                 elements: [id] + others))
        }
    }
}
