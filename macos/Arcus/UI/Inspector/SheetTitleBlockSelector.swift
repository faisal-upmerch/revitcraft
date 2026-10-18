import SwiftUI
import ArcusDomain
import ArcusApplication

/// BL-BROWSER: the Type Selector of a sheet lists title block types; choosing one changes the title block and the
/// sheet size (undoable).
struct SheetTitleBlockSelector: View {
    let state: DocumentState
    let sheetID: ElementID

    var body: some View {
        let m = state.model
        let current = m[sheetID]?.sheet?.titleBlockTypeID.flatMap { m[$0] }
        let types = SheetTitleBlocks.types(m)
        HStack(spacing: 8) {
            Image(systemName: "doc.richtext").font(.system(size: 15)).foregroundStyle(RibbonContent.sheet).frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(current?.typeData?.familyName ?? "Title Block").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Text(current?.name ?? "None (plain border)").font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                ForEach(Array(Dictionary(grouping: types, by: { $0.typeData?.familyName ?? "" }).sorted { $0.key < $1.key }), id: \.key) { fam, ts in
                    Section(fam) {
                        ForEach(ts, id: \.id) { t in
                            Button { choose(t.id) } label: {
                                let paper = SheetTitleBlocks.paper(forTitleBlockType: t.id, m).map { " (\($0.rawValue))" } ?? ""
                                if t.id == current?.id { Label(t.name + paper, systemImage: "checkmark") } else { Text(t.name + paper) }
                            }
                        }
                    }
                }
                Divider()
                Button { choose(nil) } label: { if current == nil { Label("None (plain border)", systemImage: "checkmark") } else { Text("None (plain border)") } }
            } label: { Image(systemName: "chevron.up.chevron.down") }
            .menuStyle(.button).menuIndicator(.hidden).fixedSize().controlSize(.small)
            .help("Change the title block (and the sheet size)")
            .accessibilityLabel("Title block: \(current?.name ?? "none")")
        }
    }

    func choose(_ typeID: ElementID?) {
        let sheet = sheetID
        state.session.perform("Change Title Block") { tx in try SheetTitleBlocks.setTitleBlock(typeID, on: sheet, in: tx) }
    }
}
