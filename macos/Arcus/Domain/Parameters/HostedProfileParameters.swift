import Foundation
import ArcusGeometry

/// W2-DWG: instance parameters for wall sweeps, floor slab edges, roof soffits and toposurface materials.
/// BL-PROPS: the Arcus-only ones sit in the "Arcus Extensions" group, after Phasing.
enum HostedProfileParameters {
    typealias P = BuiltInParameter

    private static func length(_ v: ParamValue, _ name: String, min lo: Double = 0) throws -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw ParameterError("“\(name)” needs a number.") }
        guard d >= lo else { throw ParameterError(lo > 0 ? "“\(name)” must be greater than zero." : "“\(name)” can't be negative.") }
        return d
    }
    private static func flag(_ v: ParamValue) throws -> Bool {
        guard let b = v.boolValue else { throw ParameterError("Type Yes or No.") }
        return b
    }
    private static func material(_ v: ParamValue, _ ctx: ParameterContext) throws -> ElementID? {
        guard let id = v.refValue else { return nil }
        guard ctx.model[id]?.material != nil else { throw ParameterError("The chosen element is not a material.") }
        return id
    }

    // MARK: Wall sweep (the first sweep of the wall)

    private static func sweep(_ e: Element) -> WallSweep? { e.wall?.sweeps?.first }
    private static func editSweep(_ e: inout Element, _ f: (inout WallSweep) -> Void) {
        var list = e.wall?.sweeps ?? []
        if list.isEmpty { list = [WallSweep()] }
        f(&list[0])
        e.wall?.sweeps = list
    }
    static let wallSweep = P("wall.sweep", "Sweep", .bool, .arcus, tooltip: "A horizontal profile (base board, string course, cornice) along one face of the wall.",
                             get: { e, _ in (e.wall?.sweeps ?? []).isEmpty ? nil : .bool(true) }, // nil when off: not exported to IFC
                             set: { e, v, _ in let on = try flag(v); let cur = e.wall?.sweeps ?? []; e.wall?.sweeps = on ? (cur.isEmpty ? [WallSweep()] : cur) : nil })
    static let wallSweepHeight = P("wall.sweepHeight", "Sweep Height", .length, .arcus, tooltip: "Height of the sweep's bottom above the wall base.",
                                   get: { e, _ in sweep(e).map { .double($0.height) } },
                                   set: { e, v, _ in let d = try length(v, "Sweep Height"); editSweep(&e) { $0.height = d } })
    static let wallSweepProjection = P("wall.sweepProjection", "Sweep Projection", .length, .arcus,
                                       get: { e, _ in sweep(e).map { .double($0.projection) } },
                                       set: { e, v, _ in let d = try length(v, "Sweep Projection", min: 0.001); editSweep(&e) { $0.projection = d } })
    static let wallSweepDepth = P("wall.sweepDepth", "Sweep Depth", .length, .arcus, tooltip: "Vertical size of the sweep profile.",
                                  get: { e, _ in sweep(e).map { .double($0.depth) } },
                                  set: { e, v, _ in let d = try length(v, "Sweep Depth", min: 0.001); editSweep(&e) { $0.depth = d } })
    static let wallSweepSide = P("wall.sweepSide", "Sweep Side", .choice(WallSweep.Side.allCases.map(\.rawValue)), .arcus,
                                 get: { e, _ in sweep(e).map { .text($0.side.rawValue) } },
                                 set: { e, v, _ in
                                     guard let s = WallSweep.Side(rawValue: v.textValue ?? v.description) else { throw ParameterError("Choose Exterior or Interior.") }
                                     editSweep(&e) { $0.side = s }
                                 })
    static let wallSweepMaterial = P("wall.sweepMaterial", "Sweep Material", .elementRef(.materials), .arcus,
                                     get: { e, _ in sweep(e).map { .ref($0.materialID) } },
                                     set: { e, v, ctx in let m = try material(v, ctx); editSweep(&e) { $0.materialID = m } })

    // MARK: Slab edge

    static let slabEdge = P("slab.edge", "Slab Edge", .bool, .arcus, tooltip: "A thickened edge (downstand) under the floor along its outer boundary.",
                            get: { e, _ in e.slab?.edgeProfile == nil ? nil : .bool(true) },
                            set: { e, v, _ in let on = try flag(v); let cur = e.slab?.edgeProfile; e.slab?.edgeProfile = on ? (cur ?? SlabEdgeProfile()) : nil })
    static let slabEdgeWidth = P("slab.edgeWidth", "Slab Edge Width", .length, .arcus,
                                 get: { e, _ in e.slab?.edgeProfile.map { .double($0.width) } },
                                 set: { e, v, _ in let d = try length(v, "Slab Edge Width", min: 0.001); var p = e.slab?.edgeProfile ?? SlabEdgeProfile(); p.width = d; e.slab?.edgeProfile = p })
    static let slabEdgeDepth = P("slab.edgeDepth", "Slab Edge Depth", .length, .arcus, tooltip: "Depth below the underside of the floor.",
                                 get: { e, _ in e.slab?.edgeProfile.map { .double($0.depth) } },
                                 set: { e, v, _ in let d = try length(v, "Slab Edge Depth", min: 0.001); var p = e.slab?.edgeProfile ?? SlabEdgeProfile(); p.depth = d; e.slab?.edgeProfile = p })

    // MARK: Roof soffit

    static let roofSoffit = P("roof.soffit", "Soffit", .bool, .arcus, tooltip: "A flat soffit board under the eaves.",
                              get: { e, _ in e.roof?.soffit == nil ? nil : .bool(true) },
                              set: { e, v, _ in
                                  let overhang = e.roof?.overhang ?? 0
                                  let cur = e.roof?.soffit
                                  let on = try flag(v)
                                  e.roof?.soffit = on ? (cur ?? RoofSoffit(depth: overhang > Tolerance.length ? overhang : 0.45)) : nil
                              })
    static let roofSoffitDepth = P("roof.soffitDepth", "Soffit Depth", .length, .arcus, tooltip: "Width of the soffit measured in from the eave line.",
                                   get: { e, _ in e.roof?.soffit.map { .double($0.depth) } },
                                   set: { e, v, _ in let d = try length(v, "Soffit Depth", min: 0.01); var s = e.roof?.soffit ?? RoofSoffit(); s.depth = d; e.roof?.soffit = s })

    // MARK: Toposurface

    static let topoMaterial = P("topo.material", "Material", .elementRef(.materials), .materials,
                                get: { e, _ in e.topography?.materialID.map { .ref($0) } },
                                set: { e, v, ctx in let m = try material(v, ctx); e.topography?.materialID = m })

    /// Parameters appended to `BuiltInCatalog.instance(for:)`.
    static func extra(for e: Element) -> [P] {
        switch e.data {
        case .wall(let w) where w.curtain == nil:
            return [wallSweep, wallSweepHeight, wallSweepProjection, wallSweepDepth, wallSweepSide, wallSweepMaterial]
        case .slab where e.category != .ceilings && e.category != .buildingPads:
            return [slabEdge, slabEdgeWidth, slabEdgeDepth]
        case .roof(let r) where r.extrusion == nil:
            return [roofSoffit, roofSoffitDepth]
        case .topography:
            return [topoMaterial] + ToposolidParameters.extra(for: e) // BL-SITE
        default:
            return []
        }
    }
}
