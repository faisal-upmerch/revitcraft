import Foundation
import ArcusGeometry

/// F1: instance parameters of Wall: Reveal (its host, orientation, position, side and groove size).
enum WallRevealParameters {
    typealias P = BuiltInParameter

    private static func edit(_ e: inout Element, _ f: (inout WallRevealData) -> Void) {
        guard var r = e.wallReveal else { return }
        f(&r)
        e.data = .wallReveal(r)
    }
    private static func positive(_ v: ParamValue, _ name: String) throws(ParameterError) -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw ParameterError("“\(name)” needs a number.") }
        guard d > Tolerance.length else { throw ParameterError("\(name) must be greater than zero.") }
        return d
    }

    static let host = P("reveal.host", "Host", .text, .constraints,
                        get: { e, ctx in .text(ctx.model[e.hostID].map { "\($0.category.singularName): \(ctx.model.type(of: $0)?.name ?? "") \($0.id)" } ?? "<None>") })
    static let orientation = P("reveal.orientation", "Orientation", .choice(WallRevealData.Orientation.allCases.map(\.rawValue)), .constraints,
                               get: { e, _ in e.wallReveal.map { .text($0.orientation.rawValue) } },
                               set: { e, v, _ in
                                   guard let o = WallRevealData.Orientation(rawValue: v.textValue ?? v.description) else { throw ParameterError("Choose Horizontal or Vertical.") }
                                   edit(&e) { $0.orientation = o }
                               })
    static let offset = P("reveal.offset", "Offset", .length, .constraints,
                          tooltip: "Horizontal reveals: height of the groove's centre above the wall base. Vertical reveals: distance of its centre from the wall's start.",
                          get: { e, _ in e.wallReveal.map { .double($0.offset) } },
                          set: { e, v, _ in
                              guard let d = v.doubleValue, d.isFinite else { throw ParameterError("“Offset” needs a number.") }
                              edit(&e) { $0.offset = d }
                          })
    static let side = P("reveal.side", "Side", .choice(WallSweep.Side.allCases.map(\.rawValue)), .constraints,
                        get: { e, _ in e.wallReveal.map { .text($0.side.rawValue) } },
                        set: { e, v, _ in
                            guard let s = WallSweep.Side(rawValue: v.textValue ?? v.description) else { throw ParameterError("Choose Exterior or Interior.") }
                            edit(&e) { $0.side = s }
                        })
    static let width = P("reveal.width", "Width", .length, .dimensions, tooltip: "Size of the groove across its run.",
                         get: { e, _ in e.wallReveal.map { .double($0.width) } },
                         set: { e, v, _ in let d = try positive(v, "Width"); edit(&e) { $0.width = d } })
    static let depth = P("reveal.depth", "Depth", .length, .dimensions, tooltip: "How deep the groove cuts into the wall face.",
                         get: { e, _ in e.wallReveal.map { .double($0.depth) } },
                         set: { e, v, _ in let d = try positive(v, "Depth"); edit(&e) { $0.depth = d } })

    static let instance: [P] = [host, orientation, offset, side, width, depth]
}

/// F1: every built-in parameter this batch adds (registered with the catalog's id table and display order).
enum F1Parameters {
    static var all: [BuiltInParameter] { ModelTextParameters.instance + WallRevealParameters.instance }
}
