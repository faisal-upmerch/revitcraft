import Foundation
import ArcusGeometry
import ArcusDomain

// F11: Manage ▸ Design Options ▸ Add to Set, Pick to Edit and the active option (RevitCraft rc-core edit.rs
// `add_to_set`; rc-app app.rs `run`: new elements join the active design option).

/// Editing design options: moving main-model elements into options and the option being edited.
public enum DesignOptionEditing {
    /// Option sets and their options (primary first), by set name.
    public static func sets(_ model: BIMModel) -> [(name: String, options: [Element])] {
        let grouped = Dictionary(grouping: model.elements(.designOptions), by: { $0.designOption?.setName ?? "" })
        return grouped.keys.sorted().map { k in
            (k, grouped[k]!.sorted { ($0.designOption?.isPrimary == true ? 0 : 1, $0.id) < ($1.designOption?.isPrimary == true ? 0 : 1, $1.id) })
        }
    }

    /// "Option Set 1: Option 2 (primary)" for the option combo and messages.
    public static func label(_ option: Element) -> String {
        "\(option.designOption?.setName ?? ""): \(option.name)\(option.designOption?.isPrimary == true ? " (primary)" : "")"
    }

    /// Main-model elements of a selection that can go into an option (model elements and what they host).
    static func mainModel(_ ids: [ElementID], _ model: BIMModel) -> [ElementID] {
        let picked = ids.filter { id in
            guard let e = model[id] else { return false }
            return e.category.isModel && e.designOptionID == nil && e.ownerViewID == nil && ElementTransform.isTransformable(e)
        }
        return ElementOperations.dependentsToCarry(Set(picked), model, viewID: nil)
            .filter { model[$0]?.ownerViewID == nil && model[$0]?.designOptionID == nil }.sorted()
    }

    /// Add to Set: the selected main-model elements move into the first chosen option; each further option gets its
    /// own copy. Returns every element now in an option.
    @discardableResult
    public static func addToSet(_ ids: [ElementID], options: [ElementID], in tx: TransactionContext) throws(TransactionError) -> [ElementID] {
        let main = mainModel(ids, tx.model)
        guard !main.isEmpty else { throw TransactionError("Select main model elements to add to the option set.") }
        let opts = options.filter { tx.model[$0]?.designOption != nil }
        guard let first = opts.first else { throw TransactionError("Choose at least one option.") }
        let sets = Set(opts.compactMap { tx.model[$0]?.designOption?.setName })
        guard sets.count == 1 else { throw TransactionError("The options must belong to one option set.") }
        var out: [ElementID] = []
        for o in opts.dropFirst() {
            let copies = ElementOperations.copy(main, by: .identity, in: tx, viewID: nil)
            for id in copies.values.sorted() { tx.update(id) { $0.designOptionID = o }; out.append(id) }
        }
        for id in main { tx.update(id) { $0.designOptionID = first }; out.append(id) }
        return out
    }

    /// The option an element belongs to, for Pick to Edit.
    public static func pickTarget(_ id: ElementID, _ model: BIMModel) -> ElementID? {
        guard let opt = model[id]?.designOptionID, model[opt]?.designOption != nil else { return nil }
        return opt
    }

    /// New model elements created in `tx` join the option being edited (as in RevitCraft's `App::run`).
    public static func assignNewElements(to option: ElementID?, in tx: TransactionContext, createdSince before: BIMModel) {
        guard let option, tx.model[option]?.designOption != nil else { return }
        for id in tx.touchedIDs where before[id] == nil {
            guard let e = tx.model[id], e.category.isModel, e.ownerViewID == nil, e.designOptionID == nil, !e.isType else { continue }
            tx.update(id) { $0.designOptionID = option }
        }
    }
}
