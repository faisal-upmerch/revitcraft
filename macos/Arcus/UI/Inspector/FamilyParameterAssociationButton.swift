import SwiftUI
import ArcusDomain
import ArcusApplication

// FMG4: the Associate Family Parameter button (a small "=") at the right of a property's value in a Furniture
// document's Properties, as in a Revit-style Family Editor. Highlighted while the property follows a family parameter;
// it opens the Associate Family Parameter dialog.

struct FamilyParameterAssociationButton: View {
    let state: DocumentState
    let entry: ParameterEntry
    let targets: [ElementID]

    /// The selected elements when every one of them can associate this property.
    var elements: [Element]? {
        guard state.model.isFurniture, !entry.isType, !targets.isEmpty else { return nil }
        let es = targets.compactMap { state.model[$0] }
        guard es.count == targets.count, es.allSatisfy({ FurnitureAssociations.compatibleTypes(entry.id, $0) != nil }) else { return nil }
        return es
    }

    var body: some View {
        if let es = elements {
            let current = es.first.flatMap { FurnitureAssociations.association(entry.id, $0) }
            Button {
                state.presented = .fmg4(.associate(elements: es.map(\.id), property: entry.id, name: entry.name))
            } label: {
                Text("=")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .frame(width: 14, height: 14)
                    .foregroundStyle(current == nil ? Color.secondary : Color.white)
                    .background(RoundedRectangle(cornerRadius: 3).fill(current == nil ? Color.clear : Color.accentColor))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(current == nil ? Color.secondary.opacity(0.6) : Color.clear))
            }
            .buttonStyle(.plain)
            .help(current.map { "Associated with the family parameter “\($0)”" } ?? "Associate Family Parameter")
            .accessibilityLabel("Associate family parameter with \(entry.name)")
        }
    }
}
