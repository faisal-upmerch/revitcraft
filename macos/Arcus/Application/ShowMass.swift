import Foundation
import ArcusDomain

// F5: session state of Massing & Site ▸ Show Mass.

extension DocumentSession {
    /// The session-only display modifiers of a view, with Show Mass applied.
    public func temporaryVisibility(for view: ElementID) -> TemporaryVisibility {
        var t = temporaryVisibility[view] ?? TemporaryVisibility()
        t.hideMass = !showMass
        return t
    }
}
