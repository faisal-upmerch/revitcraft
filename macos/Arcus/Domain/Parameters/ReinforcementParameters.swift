import Foundation
import ArcusGeometry

// F34: Properties of reinforcement, beam systems, structural symbols and bar / fabric types (names as RevitCraft and
// mainstream BIM tools show them). Quantities (bar count, bar and total length) also feed schedules and IFC.

enum ReinforcementParameters {
    typealias P = BuiltInParameter
    typealias C = BuiltInCatalog

    private static func err(_ s: String) -> ParameterError { ParameterError(s) }
    private static func length(_ v: ParamValue, _ name: String, min lo: Double) throws(ParameterError) -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw err("“\(name)” needs a length.") }
        guard d >= lo else { throw err("“\(name)” is too small.") }
        return d
    }
    private static func flag(_ v: ParamValue) throws(ParameterError) -> Bool {
        guard let b = v.boolValue else { throw err("Type Yes or No.") }
        return b
    }
    /// A bar type chosen by name ("15M", "#5").
    private static func barType(_ v: ParamValue, _ ctx: ParameterContext) throws(ParameterError) -> ElementID {
        if let id = v.refValue, ctx.model[id]?.typeData?.instanceCategory == .structuralRebar { return id }
        let name = (v.textValue ?? v.description).trimmingCharacters(in: .whitespaces)
        let types = Reinforcement.barTypes(ctx.model)
        guard let t = types.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw err("Choose a bar type: \(types.map(\.name).joined(separator: ", ")).")
        }
        return t.id
    }
    private static func hostName(_ e: Element, _ ctx: ParameterContext) -> ParamValue {
        guard let h = ctx.model[e.hostID] else { return .text("") }
        return .text(h.mark.isEmpty ? "\(h.category.singularName) \(h.id)" : "\(h.category.singularName) \(h.mark)")
    }
    private static func totalLength(_ e: Element, _ ctx: ParameterContext) -> ParamValue {
        .double(Reinforcement.bars(e, ctx.model).reduce(0) { $0 + $1.length })
    }

    static let host = P("rebar.host", "Host", .text, .constraints, get: { e, ctx in hostName(e, ctx) })
    static let face = P("rebar.face", "Face", .choice(["Top", "Bottom"]), .construction,
                        tooltip: "Top (exterior face of a wall) or Bottom (interior face).",
                        get: { e, _ in (e.pathReinforcement?.top ?? e.fabricArea?.top ?? e.fabricSheet?.top).map { .text($0 ? "Top" : "Bottom") } },
                        set: { e, v, _ in
                            let top = (v.textValue ?? v.description) != "Bottom"
                            if e.pathReinforcement != nil { e.pathReinforcement?.top = top }
                            if e.fabricArea != nil { e.fabricArea?.top = top }
                            if e.fabricSheet != nil { e.fabricSheet?.top = top }
                        })
    static let barCount = P("rebar.quantity", "Quantity", .integer, .structural, tooltip: "Bars in the set (Layout Rule: Fixed Number).",
                            get: { e, ctx in
                                if let r = e.rebar { return .int(r.count) }
                                let n = Reinforcement.bars(e, ctx.model).count
                                return n > 0 ? .int(n) : nil
                            },
                            set: { e, v, _ in
                                guard e.rebar != nil else { throw err("The quantity follows from the spacing.") }
                                guard let n = v.intValue ?? v.doubleValue.map({ Int($0.rounded()) }), (1...500).contains(n) else { throw err("Type 1 to 500 bars.") }
                                e.rebar?.count = n
                            },
                            locked: { e, _ in e.rebar == nil ? "The quantity follows from the boundary and spacing." : nil })
    static let rebarSpacing = P("rebar.spacing", "Spacing", .length, .structural,
                                get: { e, _ in (e.rebar?.spacing ?? e.pathReinforcement?.spacing).map { .double($0) } },
                                set: { e, v, _ in
                                    let s = try length(v, "Spacing", min: 0.025)
                                    if e.rebar != nil { e.rebar?.spacing = s }
                                    if e.pathReinforcement != nil { e.pathReinforcement?.spacing = s }
                                })
    static let barLength = P("rebar.barLength", "Bar Length", .length, .structural,
                             get: { e, ctx in
                                 if let r = e.rebar { return .double(r.start.distance(to: r.end)) }
                                 if let r = e.pathReinforcement { return .double(r.length) }
                                 return Reinforcement.bars(e, ctx.model).map(\.length).max().map { .double($0) }
                             },
                             set: { e, v, _ in
                                 let l = try length(v, "Bar Length", min: 0.05)
                                 if let r = e.rebar { e.rebar?.end = r.start + (r.end - r.start).normalized * l; return }
                                 guard e.pathReinforcement != nil else { throw err("The bar lengths follow from the boundary.") }
                                 e.pathReinforcement?.length = l
                             },
                             locked: { e, _ in e.rebar == nil && e.pathReinforcement == nil ? "The bar lengths follow from the boundary." : nil })
    static let totalBarLength = P("rebar.totalLength", "Total Bar Length", .length, .structural, get: { e, ctx in totalLength(e, ctx) })
    static let barTypeName = P("rebar.barType", "Bar Type", .text, .structural, tooltip: "A bar type name, such as 15M or #5.",
                               get: { e, ctx in .text(Reinforcement.barName(ctx.model, e.pathReinforcement?.barTypeID)) },
                               set: { e, v, ctx in e.pathReinforcement?.barTypeID = try barType(v, ctx) })
    static let pathFlip = P("rebar.flip", "Flip", .bool, .construction, tooltip: "The bars run to the other side of the path.",
                            get: { e, _ in e.pathReinforcement.map { .bool($0.flip) } },
                            set: { e, v, _ in e.pathReinforcement?.flip = try flag(v) })

    /// The four layers of an area reinforcement: Top/Bottom Major/Minor Direction, Bar Type and Spacing.
    static let layerNames = ["Top Major", "Top Minor", "Bottom Major", "Bottom Minor"]
    static let areaLayers: [P] = layerNames.enumerated().flatMap { k, name -> [P] in
        let key = name.lowercased().replacingOccurrences(of: " ", with: "")
        return [
            P("area.\(key).on", "\(name) Direction", .bool, .construction,
              get: { e, _ in e.areaReinforcement.map { .bool($0.layers[k].on) } },
              set: { e, v, _ in e.areaReinforcement?.layers[k].on = try flag(v) }),
            P("area.\(key).barType", "\(name) Bar Type", .text, .construction, tooltip: "A bar type name, such as 15M or #5.",
              get: { e, ctx in e.areaReinforcement.map { .text(Reinforcement.barName(ctx.model, $0.layers[k].barTypeID)) } },
              set: { e, v, ctx in e.areaReinforcement?.layers[k].barTypeID = try barType(v, ctx) }),
            P("area.\(key).spacing", "\(name) Spacing", .length, .construction,
              get: { e, _ in e.areaReinforcement.map { .double($0.layers[k].spacing) } },
              set: { e, v, _ in e.areaReinforcement?.layers[k].spacing = try length(v, "\(name) Spacing", min: 0.025) }),
        ]
    }

    static let majorLap = P("fabric.majorLapInstance", "Major Lap Splice Length", .length, .construction,
                            get: { e, _ in e.fabricArea.map { .double($0.majorLap) } },
                            set: { e, v, _ in e.fabricArea?.majorLap = try length(v, "Major Lap Splice Length", min: 0) })
    static let minorLap = P("fabric.minorLapInstance", "Minor Lap Splice Length", .length, .construction,
                            get: { e, _ in e.fabricArea.map { .double($0.minorLap) } },
                            set: { e, v, _ in e.fabricArea?.minorLap = try length(v, "Minor Lap Splice Length", min: 0) })
    static let sheetCount = P("fabric.sheets", "Sheets", .integer, .structural, get: { e, ctx in .int(Reinforcement.fabricAreaSheets(e, ctx.model).count) })
    static let sheetRotation = P("fabric.rotation", "Rotation", .angle, .constraints,
                                 get: { e, _ in e.fabricSheet.map { .double($0.angle) } },
                                 set: { e, v, _ in guard let a = v.doubleValue, a.isFinite else { throw err("Type an angle.") }; e.fabricSheet?.angle = a })
    static let couplerEnd = P("coupler.end", "Bar End", .choice(["Start", "End"]), .constraints,
                              get: { e, _ in e.rebarCoupler.map { .text($0.atEnd ? "End" : "Start") } })
    static let couplerCount = P("coupler.count", "Quantity", .integer, .structural, get: { e, ctx in .int(Reinforcement.couplerPoints(e, ctx.model).count) })

    static let systemSpacing = P("beamSystem.spacing", "Fixed Distance", .length, .construction, tooltip: "Distance between the beams of the system.",
                                 get: { e, _ in e.beamSystem.map { .double($0.spacing) } },
                                 set: { e, v, _ in e.beamSystem?.spacing = try length(v, "Fixed Distance", min: 0.1) })
    static let systemElevation = P("beamSystem.elevation", "Elevation", .length, .constraints, tooltip: "Height of the beams' top above the level.",
                                   get: { e, _ in e.beamSystem.map { .double($0.elevation) } },
                                   set: { e, v, _ in guard let d = v.doubleValue, d.isFinite else { throw err("Type a length.") }; e.beamSystem?.elevation = d })
    static let systemDirection = P("beamSystem.direction", "Beam Direction", .angle, .construction, tooltip: "Plan angle of the beams.",
                                   get: { e, _ in e.beamSystem.map { .double(Angle.normalize($0.direction.angle)) } },
                                   set: { e, v, _ in guard let a = v.doubleValue, a.isFinite else { throw err("Type an angle.") }; e.beamSystem?.direction = .fromAngle(a) })
    static let systemBeamType = P("beamSystem.beamType", "Beam Type", .text, .construction, tooltip: "The name of a Structural Framing type.",
                                  get: { e, ctx in .text(ctx.model[e.beamSystem?.beamTypeID]?.name ?? "") },
                                  set: { e, v, ctx in
                                      let name = (v.textValue ?? v.description).trimmingCharacters(in: .whitespaces)
                                      let types = ctx.model.types(for: .structuralFraming)
                                      guard let t = types.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                                          throw err("Choose a beam type: \(types.map(\.name).joined(separator: ", ")).")
                                      }
                                      e.beamSystem?.beamTypeID = t.id
                                  })
    static let systemBeams = P("beamSystem.count", "Beams", .integer, .structural, get: { e, ctx in .int(ctx.model.hosted(by: e.id).filter { $0.beam != nil }.count) })
    static let symbolKind = P("structuralSymbol.kind", "Symbol", .text, .identity, get: { e, _ in e.structuralSymbol.map { .text($0.kind.rawValue) } })
    static let structuralUsage = P("structural.usage", "Structural Usage", .choice(["Beam", "Vertical Bracing", "Horizontal Bracing", "Other"]), .structural,
                                   get: { e, _ in .text(e.params[ParameterID("structural.usage")]?.textValue ?? "Beam") },
                                   set: { e, v, _ in e.params[ParameterID("structural.usage")] = .text(v.textValue ?? v.description) })

    static let barDiameter = P(Reinforcement.barDiameterParameter.key, "Bar Diameter", .length, .structural,
                               get: { e, _ in e.typeData?.params[Reinforcement.barDiameterParameter] },
                               set: { e, v, _ in e.typeData?.params[Reinforcement.barDiameterParameter] = .double(try length(v, "Bar Diameter", min: 0.002)) })
    static let fabricTypeParameters: [P] = [
        (Reinforcement.fabricLengthParameter, "Overall Length"), (Reinforcement.fabricWidthParameter, "Overall Width"),
        (Reinforcement.fabricMajorSpacingParameter, "Major Spacing"), (Reinforcement.fabricMinorSpacingParameter, "Minor Spacing"),
        (Reinforcement.fabricWireParameter, "Wire Diameter"), (Reinforcement.fabricMajorLapParameter, "Default Major Lap Splice Length"),
        (Reinforcement.fabricMinorLapParameter, "Default Minor Lap Splice Length"),
    ].map { id, name in
        P(id.key, name, .length, .structural, get: { e, _ in e.typeData?.params[id] },
          set: { e, v, _ in e.typeData?.params[id] = .double(try length(v, name, min: 0.001)) })
    }

    /// Instance parameters this batch adds to an element (after the catalog's own).
    static func extra(for e: Element) -> [P] {
        let identity = [C.mark, C.comments]
        let typed = [C.familyName, C.typeName, C.familyAndType]
        let ifc = [C.ifcGUID, C.elementIDParam]
        switch e.data {
        case .rebar: return typed + [host, barCount, rebarSpacing, barLength, totalBarLength] + identity + [C.phaseCreated, C.phaseDemolished] + ifc
        case .areaReinforcement: return [host] + areaLayers + [barCount, totalBarLength] + identity + [C.phaseCreated, C.phaseDemolished] + ifc
        case .pathReinforcement: return [host, face, barTypeName, rebarSpacing, barLength, pathFlip, barCount, totalBarLength] + identity + [C.phaseCreated, C.phaseDemolished] + ifc
        case .fabricArea: return [host, face, majorLap, minorLap, sheetCount, totalBarLength] + identity + [C.phaseCreated, C.phaseDemolished] + ifc
        case .fabricSheet: return typed + [host, face, sheetRotation, totalBarLength] + identity + [C.phaseCreated, C.phaseDemolished] + ifc
        case .rebarCoupler: return [host, couplerEnd, couplerCount] + identity + ifc
        case .beamSystem: return [C.levelParam, systemElevation, systemBeamType, systemSpacing, systemDirection, systemBeams] + identity
        case .structuralSymbol: return [symbolKind, C.comments]
        case .beam: return [structuralUsage]
        default: return []
        }
    }

    /// Type parameters of bar and fabric sheet types.
    static func typeParameters(_ td: TypeData) -> [P] {
        switch td.instanceCategory {
        case .structuralRebar: [barDiameter]
        case .fabricReinforcement: fabricTypeParameters
        default: []
        }
    }

    /// Probe elements for the catalog's id index and display order.
    static let probes: [Element] = [
        .rebar(RebarData(start: .zero, end: .unitX)),
        .areaReinforcement(AreaReinforcementData(boundary: [], major: .unitX, layers: Array(repeating: RebarLayer(barTypeID: nil, spacing: 0.3), count: 4))),
        .pathReinforcement(PathReinforcementData(path: [], barTypeID: nil, spacing: 0.3, length: 1.8)),
        .fabricArea(FabricAreaData(boundary: [], major: .unitX, fabricTypeID: nil)), .fabricSheet(FabricSheetData(center: .zero)),
        .rebarCoupler(RebarCouplerData(atEnd: true)), .beamSystem(BeamSystemData(boundary: [], direction: .unitX, spacing: 1.8, beamTypeID: nil)),
        .structuralSymbol(StructuralSymbolData(kind: .rebar, position: .zero)), .beam(BeamData(curve: .line(Segment2(.zero, .unitX)))),
    ].map { Element(id: ElementID(0), category: .genericModels, data: $0) }
}
