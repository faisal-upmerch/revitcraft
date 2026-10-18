import Foundation
import ArcusGeometry

/// F2: instance parameters of multistory stairs and slanted columns (RevitCraft params.rs "Multistory Top Level").
enum F2Parameters {
    typealias P = BuiltInParameter

    static let multistoryTop = P("stair.multistoryTop", "Multistory Top Level", .elementRef(.levels), .constraints,
                                 tooltip: "The stair repeats, level to level, up to this level (Connect Levels). None: a single storey.",
                                 get: { e, _ in .ref(e.stair?.multistoryTopLevelID) },
                                 set: { e, v, ctx in
                                     guard let id = v.refValue else { e.stair?.multistoryTopLevelID = nil; return }
                                     guard let z = ctx.model[id]?.level?.elevation else { throw ParameterError("The chosen element is not a level.") }
                                     guard let t = e.stair?.topLevelID, let tz = ctx.model[t]?.level?.elevation else {
                                         throw ParameterError("Give the stair a Top Level first: a multistory stair repeats from level to level.")
                                     }
                                     guard z > tz + Tolerance.length else { throw ParameterError("Choose a level above the stair's Top Level.") }
                                     e.stair?.multistoryTopLevelID = id
                                 })
    static let columnStyle = P("column.style", "Column Style", .text, .constraints,
                               tooltip: "Vertical, or Slanted - End Point Driven (placed with Slanted Column).",
                               get: { e, _ in e.column.map { .text($0.topLocation == nil ? "Vertical" : "Slanted - End Point Driven") } })

    static let stair: [P] = [multistoryTop]
    static let column: [P] = [columnStyle]
    /// Every built-in parameter this batch adds (registered with the catalog's id table and display order).
    static var all: [P] { stair + column }
}
