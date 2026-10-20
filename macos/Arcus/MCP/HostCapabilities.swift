import Foundation
import ArcusCalc
import ArcusDomain
import ArcusApplication

// AITOOLS: what a host can do beyond the document itself: the active view, the Family Editor's family, and running any
// command the app's menus run (Docs/MCP.md §2). File mode keeps its own active view and family; the app's hosts answer
// from the front window.

/// A family being edited (the Family Editor window, or a file-mode .arcusfamily). The family is a value with its own
/// undo stack, not a DocumentSession.
@MainActor
public protocol FamilyEditingHost: AnyObject {
    /// The family as it is now.
    var family: FamilyDefinition { get }
    /// The type the editor shows (formulas and the preview evaluate it).
    var currentType: String { get set }
    /// Units the family's lengths are shown and typed in.
    var units: UnitsSettings { get }
    /// Changes the family as one undo step named `name`. A throwing edit changes nothing.
    func apply(name: String, edit: (inout FamilyDefinition) throws -> Void) throws
    /// Flexes every type; returns one line per problem (empty: every type evaluates and its constraints hold).
    func flexTest() -> [String]
    /// Loads (or reloads) the family into its project. Returns what happened, e.g. "Loaded into House".
    func loadIntoProject() throws -> String
}

extension FamilyEditingHost {
    /// Default flex: each type evaluates and keeps its labelled dimensions (FamilyEvaluator).
    public func flexTest() -> [String] { FamilyEvaluator.flexTest(family, units: units) }
}

/// The result of running a command for the assistant.
public enum CommandOutcome: Sendable, Equatable {
    /// The command ran and finished (it changed the model or the view).
    case done(String)
    /// The command started an interactive tool that waits for the user's clicks.
    case startedTool(String)
    /// The command can't run now; the reason says why.
    case unavailable(String)
}

/// Host features the in-app assistant uses beyond the document. Every member has a file-mode default.
@MainActor
public protocol DocumentUIHost: AnyObject {
    /// The active view (or sheet/schedule) id.
    var activeViewID: ElementID? { get }
    /// Opens (or switches to) a view; false when it can't.
    func activateView(_ id: ElementID) -> Bool
    /// Zooms the active view to elements (nil: zoom to fit).
    func zoom(to ids: [ElementID]?)
    /// Why a command can't run now, or nil.
    func commandDisabledReason(_ id: CommandID) -> String?
    /// Runs a command like its menu item.
    func runCommand(_ id: CommandID) -> CommandOutcome
    /// The family open in the front Family Editor window, when that window is in front.
    var familyHost: (any FamilyEditingHost)? { get }
}

/// File mode's family document: a FamilyDefinition held in the server process.
@MainActor
public final class FileFamilyHost: FamilyEditingHost {
    public private(set) var family: FamilyDefinition
    public var currentType: String
    public let units: UnitsSettings
    public let undoManager = UndoManager()
    /// The project the family loads into (file mode: the open project document, if any).
    public weak var project: DocumentSession?
    public var url: URL?

    public init(family: FamilyDefinition, units: UnitsSettings = .imperial) {
        self.family = family
        self.units = units
        currentType = family.types.first?.name ?? ""
        undoManager.groupsByEvent = false
    }

    public func apply(name: String, edit: (inout FamilyDefinition) throws -> Void) throws {
        var next = family
        try edit(&next)
        guard next != family else { return }
        set(next, name: name)
    }

    private func set(_ f: FamilyDefinition, name: String) {
        let before = family
        family = f
        if family.type(named: currentType) == nil { currentType = family.types.first?.name ?? "" }
        undoManager.registerUndo(withTarget: self) { h in MainActor.assumeIsolated { h.set(before, name: name) } }
        undoManager.setActionName(name)
    }

    public func loadIntoProject() throws -> String {
        guard let project else { throw ToolError("No project is open to load into. In the app, open the family from a project (Edit Family) or a Furniture document.") }
        let fam = family
        let existing = project.model.family(named: fam.name)?.id
        _ = try project.performThrowing(existing == nil ? "Load Family" : "Reload Family") { tx in
            FamilyProjectLoader.load(fam, replacing: existing, mode: .keepProjectValues, in: tx)
        }
        return existing == nil ? "Loaded “\(fam.name)” into the project." : "Reloaded “\(fam.name)” (project type values kept)."
    }
}
