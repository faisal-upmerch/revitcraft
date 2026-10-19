import Foundation

// FM8: a Furniture (or Casework) Schedule's default fields in a project, as Revit users set one up: Family and Type,
// the piece's Width, Depth and Height, its Material, the type's Cost (Identity Data, from the Load into Project
// estimate) and Count, totalled.

public enum FurnitureScheduleFields {
    /// The default fields of a new Furniture or Casework schedule.
    public static func defaults() -> [ScheduleField] {
        func field(_ id: ParameterID, _ heading: String, width: Double = 0.022, align: HorizontalAlign = .right, total: ScheduleTotal = .none) -> ScheduleField {
            var f = ScheduleField(source: .parameter(id), heading: heading, width: width, alignment: align)
            f.total = total
            return f
        }
        var fs = [ScheduleTemplates.field("familyAndType", "Family and Type", width: 0.06), ScheduleTemplates.field("level", "Level", width: 0.03)]
        fs += [field(Parameters.familyParamID("Width"), "Width"), field(Parameters.familyParamID("Depth"), "Depth"), field(Parameters.familyParamID("Height"), "Height"),
               field(Parameters.familyParamID("Material"), "Material", width: 0.04, align: .left), field(ParameterID("type.cost"), "Cost", total: .total)]
        fs.append(ScheduleField(source: .count, heading: "Count", width: 0.015, alignment: .right))
        return fs
    }
}
