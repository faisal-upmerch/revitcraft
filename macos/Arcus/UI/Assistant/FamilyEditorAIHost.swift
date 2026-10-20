import AppKit
import ArcusDomain
import ArcusApplication
import ArcusMCP
import ArcusAssistant

// AICORE: the assistant in a Family Editor window. The family tools belong to the tool layer (AITOOLS adds
// `FamilyEditingHost` and its tools to ArcusMCP); until they are merged this host offers the read-only family summary
// and no editing tools, so the sidebar answers questions about the family and says it can't edit it yet.

@MainActor
final class FamilyEditorAIHost: AIToolHost {
    weak var model: FamilyEditorModel?
    private(set) lazy var undo: any AIUndoControlling = PromptUndoGroup { [weak self] in self?.model?.undo }

    init(model: FamilyEditorModel) { self.model = model }

    var documentKind: AIDocumentKind { .family }
    var documentName: String { model?.family.name ?? "Family" }
    var unitsDescription: String {
        guard let m = model else { return "" }
        return m.units.system == .imperial ? "feet and inches (plain numbers are feet)" : "millimeters (plain numbers are mm)"
    }
    /// The family's content hash: changes whenever an edit changes the family.
    var changeCount: Int { model?.family.hashValue ?? 0 }

    /// Family tools from the tool layer (none until AITOOLS's family tools land).
    var toolSpecs: [ToolSpec] { ArcusToolCatalog.all.filter { $0.name.hasPrefix("family_") } }
    func risk(of tool: String) -> AIToolRisk { AIRiskPolicy.risk(of: ArcusToolCatalog.all.first { $0.name == tool }, name: tool) }

    func call(_ name: String, arguments: [String: JSONValue]) async -> ToolResult {
        .error("Editing families from the assistant isn't available yet. Describe the change and make it in the Family Editor.")
    }

    func contextSummary() async -> String {
        guard let m = model else { return "No family." }
        let f = m.family
        var lines = ["Family “\(f.name)” (\(f.template.category.displayName)), current type “\(m.currentType)”, view \(m.view.rawValue)."]
        lines.append("Types: " + f.types.map(\.name).prefix(20).joined(separator: ", "))
        let params = f.parameters.prefix(40).map { p -> String in
            let v = f.type(named: m.currentType)?.values[p.name].map { "\($0)" } ?? ""
            return "\(p.name) (\(p.isInstance ? "instance" : "type")\(p.formula.map { ", = \($0)" } ?? ""))" + (v.isEmpty ? "" : ": \(v)")
        }
        lines.append("Parameters: " + params.joined(separator: "; "))
        lines.append("Reference planes: " + f.referencePlanes.prefix(30).map(\.name).joined(separator: ", "))
        lines.append("Forms: \(f.solids.count), dimensions: \(f.dimensions.count), nested families: \(f.nestedFamilies.count).")
        if toolSpecs.isEmpty { lines.append("The assistant can't edit families yet: answer questions and explain how to make the change.") }
        return lines.joined(separator: "\n")
    }

    func selection() -> [AISelectionChip] {
        guard let s = model?.selection else { return [] }
        return [AISelectionChip(id: 0, title: String(describing: s), category: "Family item")]
    }
}
