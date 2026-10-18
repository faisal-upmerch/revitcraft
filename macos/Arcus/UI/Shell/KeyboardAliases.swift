import Foundation
import ArcusApplication

/// User-configurable command aliases (typed letter sequences), stored per user as differences from the defaults.
/// The table and its conflict rules are `AliasTable` (Application layer). // BL-KEYS
@MainActor
final class KeyboardAliases {
    static let shared = KeyboardAliases()
    private let key = "commandAliases"
    private(set) var table: AliasTable
    var aliases: [String: CommandID] { table.aliases }

    private init() {
        var a = CommandCatalog.defaultAliases
        if let data = UserDefaults.standard.data(forKey: key), let custom = try? JSONDecoder().decode([String: String].self, from: data) {
            for (k, v) in custom {
                if v.isEmpty { a.removeValue(forKey: k) } else if let id = CommandID(rawValue: v) { a[k] = id }
            }
        }
        table = AliasTable(a)
    }

    func command(for typed: String) -> CommandID? { table.command(for: typed) }

    func aliases(for id: CommandID) -> [String] { table.aliases(for: id) }

    /// Sets the aliases for a command; returns a conflict message if an alias is used by another command.
    @discardableResult
    func set(_ list: [String], for id: CommandID) -> String? {
        if let c = table.set(list, for: id), let other = c.usedBy { return "“\(c.alias)” is already used by \(CommandCatalog.info(other).title)." }
        persist()
        return nil
    }

    /// Replaces the whole table (import, or edits made in the Keyboard Shortcuts dialog). // BL-KEYS
    func replace(_ newTable: AliasTable) {
        table = newTable
        persist()
    }

    func reset() {
        table.restoreDefaults()
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func persist() {
        var diff: [String: String] = [:]
        for (k, v) in table.customizations { diff[k] = v?.rawValue ?? "" }
        if let data = try? JSONEncoder().encode(diff) { UserDefaults.standard.set(data, forKey: key) }
    }
}
