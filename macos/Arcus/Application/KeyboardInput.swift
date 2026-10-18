import Foundation

// BL-KEYS: typed aliases, key routing, alias tables and the shortcut file format. Pure logic, so it is unit tested; the
// canvas, the 3D view and the Keyboard Shortcuts dialog drive it.

/// The typed-alias buffer (two- or three-letter shortcuts such as `WA`, `ZE`, `EOD`).
///
/// A command runs as soon as the typed letters are a complete alias that no longer alias continues. When a complete
/// alias is also the start of a longer one, it waits: the next key either continues the longer alias or runs the
/// shorter one and starts a new sequence; after `timeout` the pending alias runs on its own. A sequence that cannot
/// match anything is dropped (the key that broke it starts a new sequence when it can). Esc clears the buffer.
public struct AliasMatcher: Sendable, Equatable {
    /// Seconds after the last key before the buffer resolves (runs a complete pending alias, else clears).
    public static let timeout: TimeInterval = 1.5

    /// What the caller should do after a key or a timeout: run these commands (in order) and show `echo`
    /// ("ZE" while typing; nil when the buffer is empty).
    public struct Outcome: Sendable, Equatable {
        public var commands: [CommandID] = []
        public var echo: String?
        public init(commands: [CommandID] = [], echo: String? = nil) { self.commands = commands; self.echo = echo }
    }

    public private(set) var buffer = ""
    private var lastKey: TimeInterval = -.infinity

    public init() {}

    /// Accepts letters and digits (case-insensitive); other characters are ignored.
    public mutating func feed(_ ch: Character, at time: TimeInterval, in table: [String: CommandID]) -> Outcome {
        guard ch.isLetter || ch.isNumber else { return Outcome(echo: echo) }
        var out = Outcome()
        if !buffer.isEmpty, time - lastKey > Self.timeout { out.commands += resolve(table) }
        lastKey = time
        let previous = buffer
        buffer += String(ch).uppercased()
        switch Self.state(of: buffer, in: table) {
        case .complete(let id):
            buffer = ""
            out.commands.append(id)
        case .partial:
            break
        case .dead:
            buffer = ""
            if let id = table[previous] { out.commands.append(id) }
            // The key that broke the sequence may start a new one.
            let single = String(ch).uppercased()
            switch Self.state(of: single, in: table) {
            case .complete(let id): out.commands.append(id)
            case .partial: buffer = single
            case .dead: break
            }
        }
        out.echo = echo
        return out
    }

    /// Call when `timeout` has passed since the last key: runs a complete pending alias, otherwise clears.
    public mutating func flush(at time: TimeInterval, in table: [String: CommandID]) -> Outcome {
        guard !buffer.isEmpty, time - lastKey >= Self.timeout else { return Outcome(echo: echo) }
        return Outcome(commands: resolve(table), echo: nil)
    }

    /// Esc: drops a partly typed alias. Returns true when there was one.
    @discardableResult
    public mutating func cancel() -> Bool {
        defer { buffer = "" }
        return !buffer.isEmpty
    }

    public var echo: String? { buffer.isEmpty ? nil : buffer }

    private mutating func resolve(_ table: [String: CommandID]) -> [CommandID] {
        defer { buffer = "" }
        return table[buffer].map { [$0] } ?? []
    }

    enum State: Equatable { case complete(CommandID), partial, dead }

    /// `complete`: an alias that no longer alias continues; `partial`: the start of at least one alias (possibly also
    /// complete itself); `dead`: nothing starts with it.
    static func state(of typed: String, in table: [String: CommandID]) -> State {
        let longer = table.keys.contains { $0.count > typed.count && $0.hasPrefix(typed) }
        if let id = table[typed], !longer { return .complete(id) }
        return longer ? .partial : .dead
    }
}

/// A key press as the 2D canvas sees it, reduced to what routing needs.
public enum CanvasKey: Sendable, Equatable {
    case escape, returnKey, space(shift: Bool), character(Character), other
}

/// The state that decides what a canvas key does.
public struct CanvasKeyContext: Sendable, Equatable {
    /// A text field, search field, inline editor or dialog text control has keyboard focus (or an inline editor is open).
    public var textEditing = false
    /// ⌘, ⌥ or ⌃ is held (menu shortcuts and the canvas's own modified keys).
    public var modified = false
    public var toolActive = false
    /// A Modify command (Move, Copy, …) is waiting for elements to be selected (pre-selection).
    public var preselectionPending = false
    public var hasSelection = false
    public init(textEditing: Bool = false, modified: Bool = false, toolActive: Bool = false, preselectionPending: Bool = false, hasSelection: Bool = false) {
        self.textEditing = textEditing; self.modified = modified; self.toolActive = toolActive
        self.preselectionPending = preselectionPending; self.hasSelection = hasSelection
    }
}

/// What the canvas does with a key.
public enum CanvasKeyAction: Sendable, Equatable {
    /// A text control owns the keyboard: no alias, tool shortcut, Select All or Finish.
    case ignore
    /// The canvas's own handling (Esc two-stage cancel, Return finishes the tool, numbers start numeric entry, letters
    /// feed the alias buffer, arrows nudge, Tab cycles).
    case standard
    /// Return with a Modify command waiting for its selection: continue to the command's first pick.
    case finishPreselection
    /// Return in Modify: repeat the last creation command.
    case repeatLastCommand
    /// Space with elements selected and no tool: flip the selected doors, windows or walls.
    case flipSelection
    /// Shift+Space while placing a door or window: flip its hand.
    case flipHand
}

/// Canvas key routing, in one testable place. The global rule: while a text control has focus, keys never run
/// aliases, tool shortcuts, Select All or Finish.
public enum CanvasKeyRouter {
    public static func route(_ key: CanvasKey, _ c: CanvasKeyContext) -> CanvasKeyAction {
        if c.textEditing { return .ignore }
        if c.modified { return .standard }
        switch key {
        case .returnKey:
            if c.toolActive { return .standard }
            return c.preselectionPending ? .finishPreselection : .repeatLastCommand
        case .space(let shift):
            if c.toolActive { return shift ? .flipHand : .standard }
            return c.hasSelection ? .flipSelection : .standard
        case .escape, .character, .other:
            return .standard
        }
    }
}

/// The user's alias table: alias → command, with the conflict rules the Keyboard Shortcuts dialog shows.
public struct AliasTable: Sendable, Equatable {
    public private(set) var aliases: [String: CommandID]
    public init(_ aliases: [String: CommandID] = CommandCatalog.defaultAliases) { self.aliases = aliases }

    /// Upper-cases and keeps letters and digits; aliases are 1–5 characters.
    public static func normalize(_ s: String) -> String? {
        let n = s.uppercased().filter { $0.isLetter || $0.isNumber }
        return (1...5).contains(n.count) ? n : nil
    }

    public func aliases(for id: CommandID) -> [String] { aliases.filter { $0.value == id }.map(\.key).sorted() }
    public func command(for typed: String) -> CommandID? { aliases[typed.uppercased()] }

    /// Why an alias would be a problem for `id`: used by another command (a conflict — assigning it moves it), or the
    /// start of / started by other aliases (they still work: the shorter one waits for the next key).
    public struct Conflict: Sendable, Equatable {
        public var alias: String
        public var usedBy: CommandID?
        public var prefixOf: [String]
        public var extends: [String]
    }

    public func conflict(for alias: String, assigningTo id: CommandID) -> Conflict? {
        guard let a = Self.normalize(alias) else { return nil }
        let used = aliases[a].flatMap { $0 == id ? nil : $0 }
        let longer = aliases.keys.filter { $0 != a && $0.hasPrefix(a) }.sorted()
        let shorter = aliases.keys.filter { $0 != a && a.hasPrefix($0) }.sorted()
        if used == nil && longer.isEmpty && shorter.isEmpty { return nil }
        return Conflict(alias: a, usedBy: used, prefixOf: longer, extends: shorter)
    }

    /// Adds an alias to a command. With `reassign`, an alias used by another command moves; otherwise the conflict is
    /// returned and nothing changes.
    @discardableResult
    public mutating func add(_ alias: String, to id: CommandID, reassign: Bool = false) -> Conflict? {
        guard let a = Self.normalize(alias) else { return nil }
        if let other = aliases[a], other != id, !reassign { return conflict(for: a, assigningTo: id) }
        aliases[a] = id
        return nil
    }

    public mutating func remove(_ alias: String) { if let a = Self.normalize(alias) { aliases.removeValue(forKey: a) } }

    /// Replaces a command's aliases. Returns the first conflict (nothing changes) unless `reassign`.
    @discardableResult
    public mutating func set(_ list: [String], for id: CommandID, reassign: Bool = false) -> Conflict? {
        let cleaned = list.compactMap(Self.normalize)
        if !reassign {
            for a in cleaned { if let other = aliases[a], other != id { return conflict(for: a, assigningTo: id) } }
        }
        for (k, v) in aliases where v == id { aliases.removeValue(forKey: k) }
        for a in cleaned { aliases[a] = id }
        return nil
    }

    public mutating func restoreDefaults() { aliases = CommandCatalog.defaultAliases }

    /// Differences from the defaults: changed or added aliases map to a command, removed defaults map to nil.
    public var customizations: [String: CommandID?] {
        let d = CommandCatalog.defaultAliases
        var out: [String: CommandID?] = [:]
        for (k, v) in aliases where d[k] != v { out[k] = .some(v) }
        for k in d.keys where aliases[k] == nil { out[k] = .some(nil) }
        return out
    }
}

/// Arcus's keyboard-shortcut file (`Arcus Keyboard Shortcuts.xml`): an XML document of our own design whose shape
/// follows the common, publicly documented layout of shortcut files in BIM tools — a root element holding one item per
/// command with the command's name, identifier and its shortcuts — so it reads familiarly. It is not an import/export
/// format of any other application.
///
/// ```xml
/// <?xml version="1.0" encoding="UTF-8"?>
/// <Shortcuts application="Arcus" formatVersion="1">
///   <ShortcutItem CommandId="wall" CommandName="Wall" Shortcuts="WA" Paths="Build"/>
///   <ShortcutItem CommandId="zoomExtents" CommandName="Zoom to Fit" Shortcuts="ZE#ZF#ZX" Paths="View"/>
/// </Shortcuts>
/// ```
/// `Shortcuts` lists the typed aliases separated by `#` (spaces are accepted on import); an empty value means the command
/// has none. Menu shortcuts (⌘-keys) are fixed and not part of the file. Unknown command ids are reported and skipped.
public enum ShortcutFile {
    public static let fileName = "Arcus Keyboard Shortcuts.xml"

    public static func export(_ table: AliasTable) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Shortcuts application=\"Arcus\" formatVersion=\"1\">\n"
        for c in CommandCatalog.all {
            let list = table.aliases(for: c.id).joined(separator: "#")
            s += "  <ShortcutItem CommandId=\"\(escape(c.id.rawValue))\" CommandName=\"\(escape(c.title))\" Shortcuts=\"\(escape(list))\" Paths=\"\(escape(c.group.rawValue))\"/>\n"
        }
        return s + "</Shortcuts>\n"
    }

    public struct ImportResult: Sendable, Equatable {
        public var table: AliasTable
        /// Commands whose aliases the file set.
        public var commandsRead = 0
        public var unknownCommands: [String] = []
        /// Aliases the file gave to more than one command (the last one wins).
        public var duplicates: [String] = []
    }

    public enum ImportError: Error, Equatable, CustomStringConvertible {
        case notXML(String), notAShortcutFile
        public var description: String {
            switch self {
            case .notXML(let m): "The file is not valid XML (\(m))."
            case .notAShortcutFile: "The file is not a keyboard shortcut file: it has no <Shortcuts> element with <ShortcutItem> entries."
            }
        }
    }

    /// Reads a shortcut file. Commands listed in the file get exactly the file's aliases; commands not listed keep the
    /// aliases they have in `base`.
    public static func `import`(_ data: Data, base: AliasTable) throws(ImportError) -> ImportResult {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { throw .notXML(parser.parserError?.localizedDescription ?? "parse error") }
        guard reader.sawRoot, !reader.items.isEmpty else { throw .notAShortcutFile }
        var result = ImportResult(table: base)
        var assigned: [String: CommandID] = [:]
        var table = base.aliases
        for item in reader.items {
            guard let id = CommandID(rawValue: item.id) else { result.unknownCommands.append(item.id); continue }
            result.commandsRead += 1
            for (k, v) in table where v == id { table.removeValue(forKey: k) }
            let list = item.shortcuts.split(whereSeparator: { $0 == "#" || $0 == " " || $0 == "," }).compactMap { AliasTable.normalize(String($0)) }
            for a in list {
                if let prior = assigned[a], prior != id { result.duplicates.append(a) }
                assigned[a] = id
                table[a] = id
            }
        }
        result.table = AliasTable(table)
        return result
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private final class Reader: NSObject, XMLParserDelegate {
        struct Item { var id: String; var shortcuts: String }
        var items: [Item] = []
        var sawRoot = false
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == "Shortcuts" { sawRoot = true }
            if name == "ShortcutItem", let id = attributes["CommandId"] { items.append(Item(id: id, shortcuts: attributes["Shortcuts"] ?? "")) }
        }
    }
}
