import AppKit
import ArcusDomain
import ArcusApplication

/// Standard content commands (W2-TYPES).
extension CommandRouter {
    /// Manage ▸ Load Standard Types: adds the standard types for the project's unit system that it lacks (by name),
    /// with the materials they use. Existing types are left as they are.
    func loadStandardTypes() {
        var added = 0
        session.perform("Load Standard Types") { tx in added = StandardContent.loadMissing(into: tx) }
        let system = model.units.system == .imperial ? "imperial" : "metric"
        state.show(added == 0 ? "The project already has every standard \(system) type." : "Added \(added) standard \(system) types.")
    }
}
