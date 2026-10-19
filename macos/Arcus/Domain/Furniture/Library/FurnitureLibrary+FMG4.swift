import Foundation

// FMG4: optional parts in library pieces: a Yes/No family parameter that shows a part by type (Visible associated
// with it, as Associate Family Parameter does).

extension LibraryBuilder {
    /// Shows the parts `ids` by the Yes/No type parameter `name` (added when missing, Yes in every type).
    public func optional(_ ids: [ElementID], by name: String) throws {
        try commit()
        let exists = tx.model.furnitureSetup?.family.parameter(named: name) != nil
        try FurnitureAssociations.associate(ids, FurnitureAssociations.visible, with: name,
                                            adding: exists ? nil : FamilyParameter(name: name, type: .bool, group: .construction), in: tx)
    }
}
