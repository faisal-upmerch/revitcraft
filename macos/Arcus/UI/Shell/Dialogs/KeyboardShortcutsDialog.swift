import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusApplication

/// Keyboard Shortcuts (BL-KEYS): every command with its menu shortcut and typed aliases. Pick a command, type new keys
/// in "Press new keys" and Assign; conflicts with other commands' aliases are shown before anything changes (Assign
/// then moves the alias). Import and Export use Arcus's shortcut file (`ShortcutFile`). Changes apply on OK.
struct KeyboardShortcutsDialog: View {
    let state: DocumentState
    @State private var draft = KeyboardAliases.shared.table
    @State private var filter = ""
    @State private var group: ArcusApplication.CommandGroup?
    @State private var selected: CommandID?
    @State private var newKeys = ""
    @State private var message: String?
    @State private var messageIsError = false
    @FocusState private var keysFocused: Bool

    private var rows: [CommandInfo] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return CommandCatalog.all.filter { c in
            (group == nil || c.group == group) &&
            (q.isEmpty || c.title.lowercased().contains(q) || draft.aliases(for: c.id).contains { $0.lowercased().hasPrefix(q) }
                || (c.shortcut?.lowercased().contains(q) ?? false))
        }
    }

    private var normalizedKeys: String? { AliasTable.normalize(newKeys) }

    var body: some View {
        ArcusDialog(icon: "keyboard", tint: .gray, title: "Keyboard Shortcuts",
                                 subtitle: "Type a command's keys (such as WA) on the canvas; it runs as soon as they match. Menu shortcuts (⌘) are fixed.",
                                 size: .large, height: 600, onCancel: { state.presented = nil }, onOK: { KeyboardAliases.shared.replace(draft); state.presented = nil }) {
            HStack {
                TextField("Search commands or keys", text: $filter).textFieldStyle(.roundedBorder)
                Picker("Show", selection: $group) {
                    Text("All").tag(ArcusApplication.CommandGroup?.none)
                    ForEach(ArcusApplication.CommandGroup.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                .fixedSize()
            }
            Table(rows, selection: $selected) {
                TableColumn("Command") { c in Label(c.title, systemImage: c.symbol) }
                TableColumn("Group") { c in Text(c.group.rawValue).foregroundStyle(.secondary) }.width(80)
                TableColumn("Menu Shortcut") { c in Text(c.shortcut ?? "").font(.body.monospaced()) }.width(90)
                TableColumn("Keys") { c in Text(draft.aliases(for: c.id).joined(separator: "  ")).font(.body.monospaced()) }.width(110)
            }
            .scrollContentBackground(.hidden)
            .background(DialogColors.sectionFill, in: RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
            .frame(minHeight: 260, maxHeight: .infinity)
            DialogSection { assignArea }
            if let message { DialogNotice(messageIsError ? .error : .info, message) }
        } leading: {
            Button("Import…") { importFile() }
            Button("Export…") { exportFile() }
            Button("Restore Defaults") { draft.restoreDefaults(); note("Default keys restored. Choose OK to keep them.") }
        }
        .returnKeyEnabled(!keysFocused)
        .onChange(of: selected) { _, _ in newKeys = ""; message = nil }
    }

    @ViewBuilder private var assignArea: some View {
        if let id = selected {
            let info = CommandCatalog.info(id)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(info.title):").font(.callout.weight(.medium))
                    let current = draft.aliases(for: id)
                    if current.isEmpty { Text("no keys").font(.callout).foregroundStyle(.secondary) }
                    ForEach(current, id: \.self) { a in
                        HStack(spacing: 3) {
                            Text(a).font(.callout.monospaced())
                            Button { draft.remove(a); note("Removed \(a) from \(info.title).") } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Remove \(a)")
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }
                HStack {
                    Text("Press new keys:").font(.callout)
                    TextField("e.g. WA", text: $newKeys)
                        .textFieldStyle(.roundedBorder).font(.body.monospaced()).frame(width: 110)
                        .focused($keysFocused)
                        .onChange(of: newKeys) { _, v in
                            let n = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(5))
                            if n != v { newKeys = n }
                        }
                        .onSubmit { assign(to: id) }
                    Button(conflictUsedBy(id) == nil ? "Assign" : "Reassign") { assign(to: id) }.disabled(normalizedKeys == nil)
                    if let text = conflictText(id) {
                        Label(text, systemImage: conflictUsedBy(id) == nil ? "info.circle" : "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(conflictUsedBy(id) == nil ? Color.secondary : Color.orange)
                            .lineLimit(2)
                    }
                }
            }
        } else {
            Text("Select a command to change its keys.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func conflictUsedBy(_ id: CommandID) -> CommandID? {
        normalizedKeys.flatMap { draft.conflict(for: $0, assigningTo: id)?.usedBy }
    }

    private func conflictText(_ id: CommandID) -> String? {
        guard let k = normalizedKeys, let c = draft.conflict(for: k, assigningTo: id) else { return nil }
        if let other = c.usedBy { return "\(k) is assigned to \(CommandCatalog.info(other).title); Reassign moves it." }
        var parts: [String] = []
        if !c.prefixOf.isEmpty { parts.append("\(k) is the start of \(c.prefixOf.joined(separator: ", ")); it runs after a short pause or the next key.") }
        if !c.extends.isEmpty { parts.append("\(c.extends.joined(separator: ", ")) will wait for the next key.") }
        return parts.joined(separator: " ")
    }

    private func assign(to id: CommandID) {
        guard let k = normalizedKeys else { return }
        let previous = draft.command(for: k)
        draft.add(k, to: id, reassign: true)
        if let p = previous, p != id { note("\(k) moved from \(CommandCatalog.info(p).title) to \(CommandCatalog.info(id).title).") }
        else { note("\(k) runs \(CommandCatalog.info(id).title).") }
        newKeys = ""
    }

    private func note(_ s: String, error: Bool = false) { message = s; messageIsError = error }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.message = "Choose an Arcus keyboard shortcut file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let r = try ShortcutFile.import(try Data(contentsOf: url), base: draft)
            draft = r.table
            var text = "Imported keys for \(r.commandsRead) commands from \(url.lastPathComponent). Choose OK to keep them."
            if !r.unknownCommands.isEmpty { text += " Skipped \(r.unknownCommands.count) unknown command(s)." }
            if !r.duplicates.isEmpty { text += " Keys used twice in the file (the last use won): \(Set(r.duplicates).sorted().joined(separator: ", "))." }
            note(text)
        } catch let e as ShortcutFile.ImportError {
            note(e.description, error: true)
        } catch {
            note("The file could not be read: \(error.localizedDescription)", error: true)
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = ShortcutFile.fileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(ShortcutFile.export(draft).utf8).write(to: url, options: .atomic)
            note("Exported to \(url.lastPathComponent).")
        } catch {
            note("Export failed: \(error.localizedDescription)", error: true)
        }
    }
}
