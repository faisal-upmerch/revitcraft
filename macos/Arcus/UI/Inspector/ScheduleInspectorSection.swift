import SwiftUI
import ArcusDomain
import ArcusApplication

/// BL-SCHED: the schedule's Fields / Filter / Sorting/Grouping / Formatting / Appearance rows in the Properties
/// palette, each with Edit… opening Schedule Properties on that tab. Shown when the palette shows one schedule.
struct ScheduleInspectorSection: View {
    let state: DocumentState
    let targets: [Element]

    var body: some View {
        if targets.count == 1, let s = targets.first, let def = s.schedule {
            VStack(alignment: .leading, spacing: 0) {
                Text("Other").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 4)
                row("Fields", summary(fields: def), .fields, s.id)
                row("Filter", def.filters.isEmpty ? "None" : "\(def.filters.count) rule\(def.filters.count == 1 ? "" : "s")", .filter, s.id)
                row("Sorting/Grouping", sortSummary(def), .sorting, s.id)
                row("Formatting", "\(def.fields.filter(\.hidden).count) hidden", .formatting, s.id)
                row("Appearance", def.appearance.gridLines ? "Grid lines" : "No grid lines", .appearance, s.id)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Schedule properties")
        }
    }

    func summary(fields def: ScheduleDefinition) -> String { "\(def.fields.count) field\(def.fields.count == 1 ? "" : "s")" }

    func sortSummary(_ def: ScheduleDefinition) -> String {
        guard let first = def.sorting.first, let f = def.field(first.fieldID) else { return "None" }
        return (first.header || first.footer || first.blankLine ? "Grouped by " : "By ") + f.heading
    }

    func row(_ name: String, _ value: String, _ tab: ScheduleTab, _ id: ElementID) -> some View {
        HStack(spacing: 6) {
            Text(name).font(Tokens.label).frame(width: Tokens.inspectorLabelWidth, alignment: .leading).lineLimit(1)
            Text(value).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Button("Edit…") { state.presented = .schedulePropertiesTab(id, tab: tab.rawValue, fieldID: nil) }
                .controlSize(.small)
                .accessibilityLabel("Edit \(name)")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: Tokens.inspectorRowHeight)
    }
}
