import Foundation
import ArcusGeometry

/// Built-in parameters for curtain walls, curtain panel types, wall openings and shafts (WP3).
extension BuiltInCatalog {
    private static func wp3Err(_ s: String) -> ParameterError { ParameterError(s) }
    private static func wp3Finite(_ v: ParamValue, _ name: String) throws(ParameterError) -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw wp3Err("“\(name)” needs a number.") }
        return d
    }
    private static func wp3Positive(_ v: ParamValue, _ name: String) throws(ParameterError) -> Double {
        let d = try wp3Finite(v, name)
        guard d > Tolerance.length else { throw wp3Err("“\(name)” must be greater than zero.") }
        return d
    }
    private static func wp3Bool(_ v: ParamValue) throws(ParameterError) -> Bool {
        guard let b = v.boolValue else { throw wp3Err("Type Yes or No.") }
        return b
    }
    private static func wp3Text(_ v: ParamValue) -> String { v.textValue ?? v.description }

    // MARK: Curtain wall types

    private static func curtainRule(_ vertical: Bool, _ key: String, _ name: String, _ type: ParamType,
                                    get: @escaping @Sendable (CurtainGridRule) -> ParamValue,
                                    set: @escaping @Sendable (inout CurtainGridRule, ParamValue) throws(ParameterError) -> Void,
                                    tooltip: String = "") -> P {
        let prefix = vertical ? "Vertical Grid" : "Horizontal Grid"
        return P("curtain.\(vertical ? "v" : "h").\(key)", "\(prefix): \(name)", type, .construction, tooltip: tooltip,
                 get: { e, _ in (e.typeData?.curtain).map { get(vertical ? $0.vertical : $0.horizontal) } },
                 set: { e, v, _ in
                     guard var c = e.typeData?.curtain else { throw wp3Err("Not a curtain wall type.") }
                     if vertical { try set(&c.vertical, v) } else { try set(&c.horizontal, v) }
                     e.typeData?.curtain = c
                 })
    }
    private static func curtainRuleParams(_ vertical: Bool) -> [P] {
        [
            curtainRule(vertical, "layout", "Layout", .choice(CurtainGridLayout.allCases.map(\.rawValue)),
                        get: { .text($0.layout.rawValue) },
                        set: { r, v throws(ParameterError) in
                            guard let l = CurtainGridLayout(rawValue: wp3Text(v)) else { throw wp3Err("Unknown grid layout.") }
                            r.layout = l
                        }),
            curtainRule(vertical, "spacing", "Spacing", .length, get: { .double($0.spacing) },
                        set: { r, v throws(ParameterError) in
                            let d = try wp3Finite(v, "Spacing")
                            guard d >= 0.05 else { throw wp3Err("Grid spacing must be at least 50 mm.") }
                            r.spacing = d
                        }, tooltip: "Distance between grid lines (Fixed Distance) or the largest allowed panel size (Maximum Spacing)."),
            curtainRule(vertical, "count", "Number", .integer, get: { .int($0.count) },
                        set: { r, v throws(ParameterError) in
                            guard let n = v.intValue, (0...500).contains(n) else { throw wp3Err("The number of grid lines must be between 0 and 500.") }
                            r.count = n
                        }, tooltip: "Number of interior grid lines for the Fixed Number layout."),
            curtainRule(vertical, "justification", "Justification", .choice(CurtainGridJustification.allCases.map(\.rawValue)),
                        get: { .text($0.justification.rawValue) },
                        set: { r, v throws(ParameterError) in
                            guard let j = CurtainGridJustification(rawValue: wp3Text(v)) else { throw wp3Err("Unknown justification.") }
                            r.justification = j
                        }, tooltip: "Where Fixed Distance grids start measuring; the leftover panel falls at the other end (or both ends for Center)."),
        ]
    }
    private static func curtainSpecParam(_ key: String, _ name: String, _ type: ParamType, _ group: ParameterGroup = .construction,
                                         get: @escaping @Sendable (CurtainSpec) -> ParamValue,
                                         set: @escaping @Sendable (inout CurtainSpec, ParamValue, ParameterContext) throws(ParameterError) -> Void,
                                         tooltip: String = "") -> P {
        P(key, name, type, group, tooltip: tooltip,
          get: { e, _ in (e.typeData?.curtain).map(get) },
          set: { e, v, ctx in
              guard var c = e.typeData?.curtain else { throw wp3Err("Not a curtain wall type.") }
              try set(&c, v, ctx)
              e.typeData?.curtain = c
          })
    }

    static let curtainTypeParams: [P] = curtainRuleParams(true) + curtainRuleParams(false) + [
        curtainSpecParam("curtain.panel", "Curtain Panel", .elementRef(.curtainPanels), get: { .ref($0.panelTypeID) },
                         set: { c, v, ctx throws(ParameterError) in
                             if let id = v.refValue, ctx.model[id]?.typeData?.instanceCategory != .curtainPanels { throw wp3Err("Choose a curtain panel type.") }
                             c.panelTypeID = v.refValue
                         }, tooltip: "Panel type used for every panel that has not been swapped."),
        curtainSpecParam("curtain.mullions.vertical", "Vertical Mullions: Interior", .bool, get: { .bool($0.verticalMullions) },
                         set: { c, v, _ throws(ParameterError) in c.verticalMullions = try wp3Bool(v) }),
        curtainSpecParam("curtain.mullions.horizontal", "Horizontal Mullions: Interior", .bool, get: { .bool($0.horizontalMullions) },
                         set: { c, v, _ throws(ParameterError) in c.horizontalMullions = try wp3Bool(v) }),
        curtainSpecParam("curtain.mullions.border", "Border Mullions", .bool, get: { .bool($0.borderMullions) },
                         set: { c, v, _ throws(ParameterError) in c.borderMullions = try wp3Bool(v) }),
        curtainSpecParam("curtain.mullion.width", "Mullion Width", .length, get: { .double($0.mullion.width) },
                         set: { c, v, _ throws(ParameterError) in
                             let d = try wp3Positive(v, "Mullion Width")
                             guard d <= 1 else { throw wp3Err("Mullions can be at most 1 m wide.") }
                             c.mullion.width = d
                         }, tooltip: "Face width of rectangular mullions, seen in elevation."),
        curtainSpecParam("curtain.mullion.depth", "Mullion Depth", .length, get: { .double($0.mullion.depth) },
                         set: { c, v, _ throws(ParameterError) in
                             let d = try wp3Positive(v, "Mullion Depth")
                             guard d <= 2 else { throw wp3Err("Mullions can be at most 2 m deep.") }
                             c.mullion.depth = d
                         }, tooltip: "Depth of rectangular mullions through the wall; also the wall's thickness in plan."),
        curtainSpecParam("curtain.mullion.material", "Mullion Material", .elementRef(.materials), .materials, get: { .ref($0.mullionMaterialID) },
                         set: { c, v, ctx throws(ParameterError) in
                             if let id = v.refValue, ctx.model[id]?.material == nil { throw wp3Err("Not a material.") }
                             c.mullionMaterialID = v.refValue
                         }),
    ]

    // MARK: Curtain panel types

    static let curtainPanelKindParam = P("panel.kind", "Panel", .choice(CurtainPanelKind.allCases.map(\.rawValue)), .construction,
                                         tooltip: "Glazed and solid panels are filled; empty panels leave the grid cell open.",
                                         get: { e, _ in .text(e.typeData?.params[.curtainPanelKind]?.textValue ?? CurtainPanelKind.glazed.rawValue) },
                                         set: { e, v, _ in
                                             guard let k = CurtainPanelKind(rawValue: wp3Text(v)) else { throw wp3Err("Unknown panel kind.") }
                                             e.typeData?.params[.curtainPanelKind] = .text(k.rawValue)
                                         })
    static let curtainPanelThicknessParam = P("panel.thickness", "Thickness", .length, .construction,
                                              get: { e, _ in .double(e.typeData?.params[.curtainPanelThickness]?.doubleValue ?? CurtainWallGeometry.defaultPanelThickness) },
                                              set: { e, v, _ in
                                                  let d = try wp3Positive(v, "Thickness")
                                                  guard d <= 0.5 else { throw wp3Err("Panels can be at most 500 mm thick.") }
                                                  e.typeData?.params[.curtainPanelThickness] = .double(d)
                                              })

    // MARK: Curtain wall instances

    static let curtainPanelCount = P("curtain.panelCount", "Panels", .integer, .dimensions,
                                     get: { e, ctx in CurtainWallGeometry.layout(e, ctx.model).map { l in .int(l.panels.filter { $0.kind != .empty }.count) } })
    static let curtainMullionLength = P("curtain.mullionLength", "Mullion Length", .length, .dimensions,
                                        get: { e, ctx in CurtainWallGeometry.layout(e, ctx.model).map { .double($0.mullionLength) } })

    /// Instance parameters of a curtain wall (walls whose curtain data is set by the regenerator).
    static func curtainWallInstanceParams() -> [P] {
        [familyName, typeName, familyAndType, wallLocationLine, levelParam, wallBaseOffset, wallBaseAttached, wallTopConstraint,
         wallUnconnectedHeight, wallTopOffset, wallTopAttached, wallRoomBounding, quantityLength, quantityArea, curtainPanelCount,
         curtainMullionLength, mark, comments, phaseCreated, phaseDemolished, ifcGUID, classificationCode, elementIDParam, designOption]
    }

    // MARK: Wall openings

    static let wallOpeningWidth = P("opening.width", "Width", .length, .dimensions,
                                    get: { e, _ in e.opening?.wallOpening.map { .double($0.width) } },
                                    set: { e, v, _ in
                                        guard var w = e.opening?.wallOpening else { return }
                                        let d = try wp3Positive(v, "Width")
                                        let s = min(w.start, w.end)
                                        w.start = s; w.end = s + d
                                        e.data = .opening(.wall(w))
                                    })
    static let wallOpeningHeight = P("opening.height", "Height", .length, .dimensions,
                                     get: { e, _ in e.opening?.wallOpening.map { .double($0.height) } },
                                     set: { e, v, _ in
                                         guard var w = e.opening?.wallOpening else { return }
                                         let d = try wp3Positive(v, "Height")
                                         let b = min(w.bottom, w.top)
                                         w.bottom = b; w.top = b + d
                                         e.data = .opening(.wall(w))
                                     })
    static let wallOpeningSill = P("opening.bottom", "Bottom Offset", .length, .constraints, tooltip: "Height of the opening's bottom above the base of its wall.",
                                   get: { e, _ in e.opening?.wallOpening.map { .double(min($0.bottom, $0.top)) } },
                                   set: { e, v, _ in
                                       guard var w = e.opening?.wallOpening else { return }
                                       let b = try wp3Finite(v, "Bottom Offset")
                                       let h = w.height
                                       w.bottom = b; w.top = b + h
                                       e.data = .opening(.wall(w))
                                   })
    static let wallOpeningHost = P("opening.host", "Host", .text, .constraints,
                                   get: { e, ctx in .text(ctx.model[e.hostID].map { "\($0.category.singularName): \(ctx.model.type(of: $0)?.name ?? "") \($0.id)" } ?? "<None>") })

    // MARK: Shafts

    private static func shaftParam(_ key: String, _ name: String, _ type: ParamType, locked: (@Sendable (Element, ParameterContext) -> String?)? = nil,
                                   get: @escaping @Sendable (ShaftOpeningData) -> ParamValue,
                                   set: @escaping @Sendable (inout ShaftOpeningData, ParamValue, ParameterContext) throws(ParameterError) -> Void) -> P {
        P(key, name, type, .constraints,
          get: { e, _ in e.opening?.shaft.map(get) },
          set: { e, v, ctx in
              guard var s = e.opening?.shaft else { return }
              try set(&s, v, ctx)
              e.data = .opening(.shaft(s))
          }, locked: locked)
    }
    static let shaftParams: [P] = [
        shaftParam("shaft.baseOffset", "Base Offset", .length, get: { .double($0.baseOffset) },
                   set: { s, v, _ throws(ParameterError) in s.baseOffset = try wp3Finite(v, "Base Offset") }),
        shaftParam("shaft.topConstraint", "Top Constraint", .elementRef(.levels), get: { .ref($0.topLevelID) },
                   set: { s, v, ctx throws(ParameterError) in
                       if let id = v.refValue, ctx.model[id]?.level == nil { throw wp3Err("The chosen element is not a level.") }
                       s.topLevelID = v.refValue
                   }),
        shaftParam("shaft.topOffset", "Top Offset", .length,
                   locked: { e, _ in e.opening?.shaft?.topLevelID == nil ? "Top Offset applies only when the shaft has a Top Constraint level." : nil },
                   get: { .double($0.topOffset) },
                   set: { s, v, _ throws(ParameterError) in s.topOffset = try wp3Finite(v, "Top Offset") }),
        shaftParam("shaft.unconnectedHeight", "Unconnected Height", .length,
                   locked: { e, _ in e.opening?.shaft?.topLevelID != nil ? "The height comes from the Top Constraint level." : nil },
                   get: { .double($0.unconnectedHeight) },
                   set: { s, v, _ throws(ParameterError) in s.unconnectedHeight = try wp3Positive(v, "Unconnected Height") }),
    ]

    /// Instance parameters of wall openings and shafts.
    static func openingInstanceParams(_ e: Element) -> [P] {
        switch e.opening {
        case .wall?:
            return [wallOpeningHost, wallOpeningWidth, wallOpeningHeight, wallOpeningSill, mark, comments, phaseCreated, phaseDemolished]
        case .shaft?:
            return [levelParam] + shaftParams + [mark, comments, phaseCreated, phaseDemolished]
        case nil:
            return []
        }
    }

    // MARK: Probes for the catalog tables

    static var wp3TypeProbes: [TypeData] {
        var cw = TypeData(instanceCategory: .walls, familyName: "")
        cw.curtain = CurtainSpec()
        return [cw, TypeData(instanceCategory: .curtainPanels, familyName: "")]
    }
    static var wp3InstanceProbes: [Element] {
        var w = WallData(location: .line(Segment2(.zero, .unitX)))
        w.curtain = CurtainInstanceData()
        let sketch = Sketch(rect: Rect2(min: .zero, max: Vec2(1, 1)))
        return [Element(id: ElementID(0), category: .walls, data: .wall(w)),
                Element(id: ElementID(0), category: .wallOpenings, data: .opening(.wall(WallOpeningData(start: 0, end: 1, bottom: 0, top: 1)))),
                Element(id: ElementID(0), category: .shaftOpenings, data: .opening(.shaft(ShaftOpeningData(boundary: sketch))))]
    }
}
