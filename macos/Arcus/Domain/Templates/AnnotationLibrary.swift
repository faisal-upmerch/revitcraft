import Foundation
import ArcusGeometry

// W2-ANNOT: tag families added with the Annotate tab (area tags and multi-category tags), loaded into new projects
// and on demand into older ones. All content is original Arcus content.
public enum AnnotationLibrary {
    public static let areaTagName = "Area Tag"
    public static let multiCategoryTagName = "Multi-Category Tag"

    /// Area tag: name over area.
    public static func areaTag() -> FamilyDefinition {
        var f = FamilyDefinition(name: areaTagName, template: .tag)
        f.taggedCategories = [.areas]
        f.types = [FamilyTypeDefinition(name: "Name and Area", values: [:])]
        f.labels = [
            FamilyLabel(position: FamilyPoint("0", "0.0018"), parameterName: "Name", height: 0.0025, bold: true, sample: "AREA"),
            FamilyLabel(position: FamilyPoint("0", "-0.0018"), parameterName: "Area", height: 0.0022, sample: "20.00 m²"),
        ]
        return f
    }

    /// Multi-category tag: the mark of any taggable element in a rounded box.
    public static func multiCategoryTag() -> FamilyDefinition {
        var f = StarterLibrary.tagFamily(multiCategoryTagName, categories: Category.taggable, label: "Mark", shape: "rect", width: "0.011")
        f.types = [FamilyTypeDefinition(name: "Mark", values: [:])]
        return f
    }

    public static var all: [FamilyDefinition] { [areaTag(), multiCategoryTag()] }

    /// True for the multi-category tag family (Tag by Category prefers a category's own tag).
    public static func isMultiCategory(_ type: Element, _ model: BIMModel) -> Bool {
        model[type.typeData?.familyID]?.name == multiCategoryTagName
    }

    /// Loads a family and its types; returns the type ids (existing ones when the family is already loaded).
    @discardableResult
    public static func load(_ fam: FamilyDefinition, in tx: TransactionContext) -> [ElementID] {
        if let existing = tx.model.elements(.families).first(where: { $0.name == fam.name }) {
            return tx.model.elements(.elementTypes).filter { $0.typeData?.familyID == existing.id }.map(\.id)
        }
        let fid = tx.create(.families, name: fam.name, data: .family(fam))
        let cat: Category = fam.template == .tag ? .tags : fam.template.category
        return fam.types.map { t in
            var params: [ParameterID: ParamValue] = [:]
            for (k, v) in t.values { params[Parameters.familyParamID(k)] = v }
            return tx.create(.elementTypes, name: t.name, data: .type(TypeData(instanceCategory: cat, familyID: fid, familyName: fam.name, params: params)))
        }
    }

    /// Loads every annotation library family missing from the model.
    public static func ensureAll(in tx: TransactionContext) {
        for f in all { load(f, in: tx) }
    }
}
