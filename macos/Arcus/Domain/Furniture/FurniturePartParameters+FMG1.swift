import Foundation

// FMG1: Properties of rails drawn at an angle: y Justification (as a beam's) and the cut at each end (as a slanted
// column's Base and Top Cut Style), so a raked leg can stand flat on the floor with its outer edge on a plane.

extension FurniturePartParameters {
    static let yJust = P("furniture.part.yJustification", "y Justification", .choice(RailYJustification.allCases.map(\.rawValue)), .constraints,
                         tooltip: "Where the rail lies across its line: to its left, centred or to its right.",
                         get: { e, _ in e.furnitureRail.map { .text(($0.yJustification ?? .center).rawValue) } },
                         set: { e, v, _ in
                             guard let j = RailYJustification(rawValue: text(v)) else { throw err("Choose Left, Center or Right.") }
                             e.furnitureRail?.yJustification = j == .center ? nil : j
                         })

    /// The cut at the rail's start (or end).
    static func endCut(_ id: String, _ name: String, atEnd: Bool) -> P {
        P("furniture.part.\(id)", name, .choice(RailEndCut.allCases.map(\.rawValue)), .constraints,
          tooltip: "Drawn at an angle in an elevation: the end cut square to the rail, level or plumb.",
          get: { e, _ in e.furnitureRail.map { .text(((atEnd ? $0.endCut : $0.startCut) ?? .perpendicular).rawValue) } },
          set: { e, v, _ in
              guard let c = RailEndCut(rawValue: text(v)) else { throw err("Choose Perpendicular, Horizontal or Vertical.") }
              let cut = c == .perpendicular ? nil : c
              if atEnd { e.furnitureRail?.endCut = cut } else { e.furnitureRail?.startCut = cut }
          })
    }
    static let startCut = endCut("startCut", "Start Cut", atEnd: false)
    static let endCut = endCut("endCut", "End Cut", atEnd: true)
}
