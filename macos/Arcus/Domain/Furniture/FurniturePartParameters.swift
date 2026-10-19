import Foundation
import ArcusGeometry

// FM4: Properties of furniture parts (instance) and their types (Edit Type), named and grouped as the Revit-style
// Architecture elements they mirror: Base/Top Constraint and offsets like walls, Height Offset like floors, Z
// Justification like beams, Layout Rule like beam systems; nominal Length × Width × Thickness for schedules.

enum FurniturePartParameters {
    typealias P = BuiltInParameter

    static func err(_ s: String) -> ParameterError { ParameterError(s) }
    static func number(_ v: ParamValue, _ name: String) throws(ParameterError) -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw err("“\(name)” needs a number.") }
        return d
    }
    static func text(_ v: ParamValue) -> String { v.textValue ?? v.description }

    /// The plane a bound names, as a reference plane element (for the elementRef pickers).
    static func planeID(_ b: FurnitureBound?, _ m: BIMModel) -> ElementID? {
        guard case .plane(let n, _)? = b else { return nil }
        return FurniturePlanes.names(m).first { $0.value == n }?.key
    }
    static func offset(_ b: FurnitureBound?) -> Double? { if case .plane(_, let o)? = b { return o }; return nil }

    /// Sets a coordinate's constraint plane (nil = none), keeping its offset.
    static func setPlane(_ key: String, _ v: ParamValue, _ e: inout Element, _ ctx: ParameterContext, axis: FamilyAxis, allowNone: Bool) throws(ParameterError) {
        let m = ctx.model
        var b = FurniturePartBounds.bounds(of: e)
        guard let id = v.refValue else {
            guard allowNone else { throw err("Choose a reference plane.") }
            b[key] = nil
            FurniturePartBounds.setBounds(b, of: &e)
            return
        }
        guard let rp = m[id]?.referencePlane, let fp = rp.furniture, let name = FurniturePlanes.names(m)[id], let pos = FurniturePlanes.position(rp) else {
            throw err("Choose one of the piece's reference planes.")
        }
        guard fp.axis == axis else { throw err("“\(name)” doesn't run that way. Choose a plane parallel to this end of the part.") }
        let o = offset(b[key]) ?? 0
        b[key] = .plane(name, offset: o)
        FurniturePartBounds.setBounds(b, of: &e)
        FurniturePartCoordinates.set(key, pos + o, in: &e)
    }

    /// Sets a coordinate's offset from its plane (or its value when it has none).
    static func setOffset(_ key: String, _ v: ParamValue, _ name: String, _ e: inout Element, _ ctx: ParameterContext) throws(ParameterError) {
        let d = try number(v, name)
        var b = FurniturePartBounds.bounds(of: e)
        if case .plane(let n, _)? = b[key], let pos = FurniturePlanes.positionsByName(ctx.model)[n] {
            b[key] = .plane(n, offset: d)
            FurniturePartBounds.setBounds(b, of: &e)
            FurniturePartCoordinates.set(key, pos + d, in: &e)
        } else {
            FurniturePartCoordinates.set(key, d, in: &e)
        }
    }

    static func value(_ key: String, _ e: Element) -> Double? { FurniturePartCoordinates.coordinates(of: e).first { $0.key == key }?.value }

    static func constraint(_ id: String, _ name: String, key: String, axis: @escaping @Sendable (Element) -> FamilyAxis, allowNone: Bool, tooltip: String) -> P {
        P("furniture.part.\(id)", name, .elementRef(.referencePlanes), .constraints, tooltip: tooltip,
          get: { e, ctx in .ref(planeID(FurniturePartBounds.bounds(of: e)[key], ctx.model)) },
          set: { e, v, ctx in try setPlane(key, v, &e, ctx, axis: axis(e), allowNone: allowNone) })
    }

    static func offsetParam(_ id: String, _ name: String, key: String, locked: (@Sendable (Element, ParameterContext) -> String?)? = nil) -> P {
        P("furniture.part.\(id)", name, .length, .constraints,
          get: { e, _ in
              let b = FurniturePartBounds.bounds(of: e)[key]
              if let o = offset(b) { return .double(o) }
              return value(key, e).map { .double($0) }
          },
          set: { e, v, ctx in try setOffset(key, v, name, &e, ctx) }, locked: locked)
    }

    static func wAxis(_ e: Element) -> FamilyAxis {
        if let p = e.furniturePanel { return p.plane.axes.w }
        if let r = e.furnitureRail { return r.plane.axes.w }
        return .z
    }

    // MARK: Panels

    static let panelFunction = P("furniture.part.function", "Function", .choice(["Panel", "Back", "Divider", "Plinth"]), .constraints,
                                 get: { e, _ in e.furniturePanel.map { .text($0.role.rawValue) } },
                                 set: { e, v, _ in
                                     guard let k = FurniturePartKind(rawValue: text(v)), [.panel, .back, .divider, .plinth].contains(k) else { throw err("Choose Panel, Back, Divider or Plinth.") }
                                     e.furniturePanel?.role = k
                                 })
    static let panelLocation = P("furniture.part.locationLine", "Location Line", .choice(PanelLocationLine.allCases.map(\.rawValue)), .constraints,
                                 tooltip: "Where the drawn line lies across the panel's thickness.",
                                 get: { e, _ in e.furniturePanel.map { .text($0.locationLine.rawValue) } },
                                 set: { e, v, _ in
                                     guard let l = PanelLocationLine(rawValue: text(v)) else { throw err("Unknown location line.") }
                                     e.furniturePanel?.locationLine = l
                                 })
    static let baseConstraint = constraint("baseConstraint", "Base Constraint", key: "base", axis: wAxis, allowNone: true,
                                           tooltip: "The reference plane the part starts from (for panels drawn in an elevation: the plane it runs from, across the view).")
    static let baseOffset = offsetParam("baseOffset", "Base Offset", key: "base")
    static let topConstraint = constraint("topConstraint", "Top Constraint", key: "top", axis: wAxis, allowNone: true,
                                          tooltip: "The reference plane the part runs to, or none (Unconnected).")
    static let topOffset = offsetParam("topOffset", "Top Offset", key: "top", locked: { e, _ in FurniturePartBounds.bounds(of: e)["top"] == nil ? "Top Offset applies when the part has a Top Constraint." : nil })
    static let unconnectedHeight = P("furniture.part.unconnectedHeight", "Unconnected Height", .length, .constraints,
                                     get: { e, _ in
                                         if let p = e.furniturePanel { return .double(p.height) }
                                         if let l = e.furnitureLeg { return .double(l.height) }
                                         return nil
                                     },
                                     set: { e, v, _ in
                                         let h = try number(v, "Unconnected Height")
                                         guard h > Tolerance.length else { throw err("Unconnected Height must be greater than zero.") }
                                         if var p = e.furniturePanel { p.top = p.base + h; e.furniturePanel = p }
                                         if var l = e.furnitureLeg { l.top = l.base + h; e.furnitureLeg = l }
                                     },
                                     locked: { e, _ in
                                         if FurniturePartBounds.bounds(of: e)["top"] != nil { return "The height comes from the Top Constraint. Set it to none to edit the height." }
                                         if e.furniturePanel?.attachedTopID != nil || e.furnitureLeg?.attachedTopID != nil { return "The top is attached. Detach it to edit the height." }
                                         return nil
                                     })
    static let topAttached = P("furniture.part.topAttached", "Top is Attached", .bool, .constraints,
                               get: { e, _ in .bool(e.furniturePanel?.attachedTopID != nil || e.furnitureLeg?.attachedTopID != nil) })
    static let baseAttached = P("furniture.part.baseAttached", "Base is Attached", .bool, .constraints,
                                get: { e, _ in .bool(e.furniturePanel?.attachedBaseID != nil) })
    static let banding = P("furniture.part.banding", "Edge Banding", .text, .construction,
                           tooltip: "Banded edges: L1 L2 along the length, W1 W2 along the width (empty = the type's default).",
                           get: { e, ctx in
                               guard let p = e.furniturePanel else { return nil }
                               return .text((p.banding ?? FurniturePartTypes.values(of: e, ctx.model).banding).code)
                           },
                           set: { e, v, _ in
                               let s = text(v).trimmingCharacters(in: .whitespaces)
                               e.furniturePanel?.banding = s.isEmpty ? nil : EdgeBanding(code: s)
                           })
    static let backFit = P("furniture.part.backFit", "Fit", .choice(BackIntent.Fit.allCases.map(\.rawValue)), .construction,
                           tooltip: "Inside the carcass, or over its back edges.",
                           get: { e, _ in e.furniturePanel?.back.map { .text($0.fit.rawValue) } },
                           set: { e, v, _ in
                               guard let f = BackIntent.Fit(rawValue: text(v)) else { throw err("Choose Inside or Full Overlay.") }
                               e.furniturePanel?.back?.fit = f
                           })
    static let backJoint = P("furniture.part.backJoint", "Back Joint", .choice(BackIntent.Joint.allCases.map(\.rawValue)), .construction,
                             tooltip: "How the back is let into the carcass (made by joints).",
                             get: { e, _ in e.furniturePanel?.back.map { .text($0.joint.rawValue) } },
                             set: { e, v, _ in
                                 guard let j = BackIntent.Joint(rawValue: text(v)) else { throw err("Choose Butt, Inset, Rabbet or Dado.") }
                                 e.furniturePanel?.back?.joint = j
                             })
    static let eqCount = P("furniture.part.eq", "Equal Spaces", .integer, .constraints,
                           tooltip: "Dividers: the bay is split into this many equal spaces (EQ).",
                           get: { e, _ in e.furniturePanel?.eq.map { .int($0.count) } })

    // MARK: Quantities

    static let length = BuiltInCatalog.q("furniture.part.length", "Length", .length) { $0.length }
    static let width = BuiltInCatalog.q("furniture.part.width", "Width", .length) { $0.width }
    static let thickness = BuiltInCatalog.q("furniture.part.thickness", "Thickness", .length) { $0.thickness }
    static let area = BuiltInCatalog.q("furniture.part.area", "Area", .area) { $0.area }
    static let volume = BuiltInCatalog.q("furniture.part.volume", "Volume", .volume) { $0.volume }
    static let size = P("furniture.part.size", "Size", .text, .dimensions, tooltip: "Nominal width × length (the Part Tag shows it).",
                        get: { e, ctx in .text(FurniturePartMeshes.sizeText(e, ctx.model)) })
    static let count = P("furniture.part.count", "Count", .integer, .dimensions, get: { e, _ in .int(FurniturePartMeshes.count(e)) })

    // MARK: Shelves

    static let shelfFunction = P("furniture.part.shelfFunction", "Function", .choice(["Shelf", "Top", "Bottom"]), .constraints,
                                 get: { e, _ in e.furnitureShelf.map { .text($0.role.rawValue) } },
                                 set: { e, v, _ in
                                     guard let k = FurniturePartKind(rawValue: text(v)), [.shelf, .top, .bottom].contains(k) else { throw err("Choose Shelf, Top or Bottom.") }
                                     e.furnitureShelf?.role = k
                                 })
    static let elevationConstraint = constraint("elevationConstraint", "Reference Plane", key: "z", axis: { _ in .z }, allowNone: true,
                                                tooltip: "The horizontal plane the Height Offset is measured from.")
    static let heightOffset = offsetParam("heightOffset", "Height Offset", key: "z")
    static let adjustable = P("furniture.part.adjustable", "Adjustable", .bool, .construction,
                              tooltip: "Adjustable shelves sit on shelf pins (rows of holes in the sides); fixed shelves are joined.",
                              get: { e, _ in e.furnitureShelf.map { .bool($0.adjustable) } },
                              set: { e, v, _ in
                                  guard var s = e.furnitureShelf else { return }
                                  s.adjustable = v.boolValue ?? false
                                  s.pins = s.adjustable ? (s.pins ?? ShelfPins()) : nil
                                  e.furnitureShelf = s
                              })
    static let pinSpacing = P("furniture.part.pinSpacing", "Pin Spacing", .length, .construction,
                              get: { e, _ in e.furnitureShelf?.pins.map { .double($0.spacing) } },
                              set: { e, v, _ in
                                  let d = try number(v, "Pin Spacing")
                                  guard d > 0.005 else { throw err("Pin Spacing is too small.") }
                                  e.furnitureShelf?.pins?.spacing = d
                              },
                              locked: { e, _ in e.furnitureShelf?.adjustable == true ? nil : "Make the shelf Adjustable to set its pins." })
    static let frontSetback = P("furniture.part.frontSetback", "Front Setback", .length, .constraints,
                                tooltip: "How far the front edge sits back from where it was sketched.",
                                get: { e, _ in e.furnitureShelf.map { .double($0.frontSetback) } },
                                set: { e, v, _ in
                                    let d = try number(v, "Front Setback")
                                    guard var s = e.furnitureShelf else { return }
                                    let delta = d - s.frontSetback
                                    let minY = s.boundary.map(\.y).min() ?? 0
                                    s.boundary = s.boundary.map { abs($0.y - minY) < 1e-7 ? Vec2($0.x, $0.y + delta) : $0 }
                                    s.frontSetback = d
                                    e.furnitureShelf = s
                                })
    static let perimeter = BuiltInCatalog.q("furniture.part.perimeter", "Perimeter", .length) { $0.perimeter }

    // MARK: Legs

    static let rotation = P("furniture.part.rotation", "Rotation", .angle, .constraints,
                            get: { e, _ in e.furnitureLeg.map { .double($0.rotation) } },
                            set: { e, v, _ in e.furnitureLeg?.rotation = try number(v, "Rotation") })

    // MARK: Rails

    static let zJust = P("furniture.part.zJustification", "Z Justification", .choice(RailJustification.allCases.map(\.rawValue)), .constraints,
                         tooltip: "Where the rail hangs from its line: below it (Top), across it (Center) or above it (Bottom).",
                         get: { e, _ in e.furnitureRail.map { .text($0.justification.rawValue) } },
                         set: { e, v, _ in
                             guard let j = RailJustification(rawValue: text(v)) else { throw err("Choose Top, Center or Bottom.") }
                             e.furnitureRail?.justification = j
                         })
    static let railPlane = constraint("railPlane", "Reference Plane", key: "w", axis: wAxis, allowNone: true,
                                      tooltip: "Drawn in plan: the horizontal plane the rail's height is measured from. Drawn in an elevation: the plane its depth is measured from.")
    static let railOffset = offsetParam("railOffset", "Offset", key: "w")
    static let startExtension = P("furniture.part.startExtension", "Start Extension", .length, .constraints,
                                  get: { e, _ in e.furnitureRail.map { .double($0.startExtension) } },
                                  set: { e, v, _ in e.furnitureRail?.startExtension = try number(v, "Start Extension") })
    static let endExtension = P("furniture.part.endExtension", "End Extension", .length, .constraints,
                                get: { e, _ in e.furnitureRail.map { .double($0.endExtension) } },
                                set: { e, v, _ in e.furnitureRail?.endExtension = try number(v, "End Extension") })
    static let layoutRule = P("furniture.part.layoutRule", "Layout Rule", .choice(SlatLayout.Rule.allCases.map(\.rawValue)), .construction,
                              get: { e, _ in e.furnitureRail?.slats.map { .text($0.rule.rawValue) } },
                              set: { e, v, _ in
                                  guard let r = SlatLayout.Rule(rawValue: text(v)) else { throw err("Choose Fixed Distance, Fixed Number or Maximum Spacing.") }
                                  e.furnitureRail?.slats?.rule = r
                              })
    static let slatSpacing = P("furniture.part.slatSpacing", "Spacing", .length, .construction,
                               get: { e, _ in e.furnitureRail?.slats.map { .double($0.spacing) } },
                               set: { e, v, _ in
                                   let d = try number(v, "Spacing")
                                   guard d > 0.005 else { throw err("Spacing is too small.") }
                                   e.furnitureRail?.slats?.spacing = d
                               },
                               locked: { e, _ in e.furnitureRail?.slats?.rule == .fixedNumber ? "The spacing follows the number of slats (Fixed Number)." : nil })
    static let slatNumber = P("furniture.part.slatNumber", "Number of Slats", .integer, .construction,
                              get: { e, _ in e.furnitureRail?.slats.map { .int($0.offsets.count) } },
                              set: { e, v, _ in
                                  guard let n = v.intValue, n >= 1, n <= 200 else { throw err("Use 1 to 200 slats.") }
                                  e.furnitureRail?.slats?.number = n
                              },
                              locked: { e, _ in e.furnitureRail.flatMap(\.slats).map { $0.rule == .fixedNumber ? nil : "The number follows the spacing (\($0.rule.rawValue))." } ?? nil }) // FMG1: Maximum Spacing
    static let slatExtent = P("furniture.part.slatExtent", "Layout Width", .length, .construction,
                              tooltip: "From the first slat's centre to the last's.",
                              get: { e, _ in e.furnitureRail?.slats.map { .double($0.extent) } },
                              set: { e, v, _ in e.furnitureRail?.slats?.extent = max(0, try number(v, "Layout Width")) })

    // MARK: Edge profiles

    static let profileOffset = P("furniture.part.profileOffset", "Offset", .length, .constraints,
                                 tooltip: "Grooves: distance from the edge across the face.",
                                 get: { e, _ in e.furnitureEdgeProfile.map { .double($0.offset) } },
                                 set: { e, v, _ in e.furnitureEdgeProfile?.offset = try number(v, "Offset") })
    static let startSetback = P("furniture.part.startSetback", "Start Setback", .length, .constraints,
                                get: { e, _ in e.furnitureEdgeProfile.map { .double($0.startSetback) } },
                                set: { e, v, _ in e.furnitureEdgeProfile?.startSetback = max(0, try number(v, "Start Setback")) })
    static let endSetback = P("furniture.part.endSetback", "End Setback", .length, .constraints,
                              get: { e, _ in e.furnitureEdgeProfile.map { .double($0.endSetback) } },
                              set: { e, v, _ in e.furnitureEdgeProfile?.endSetback = max(0, try number(v, "End Setback")) })
    static let host = P("furniture.part.host", "Host", .text, .constraints,
                        get: { e, ctx in ctx.model[e.hostID].map { .text($0.mark.isEmpty ? $0.category.singularName : "\($0.category.singularName) \($0.mark)") } })

    // MARK: Forms

    static let formMaterial = P("furniture.part.formMaterial", "Material", .elementRef(.materials), .materials,
                                get: { e, _ in .ref(e.furnitureForm?.materialID) },
                                set: { e, v, ctx in
                                    if let r = v.refValue, ctx.model[r]?.material == nil { throw err("Not a material.") }
                                    e.furnitureForm?.materialID = v.refValue
                                })
    static let formKind = P("furniture.part.formKind", "Form", .text, .identity,
                            get: { e, _ in e.furnitureForm.map { .text(($0.isVoid ? "Void " : "") + $0.kind.rawValue) } })
    static func formRange(_ id: String, _ name: String, first: Bool) -> P {
        P("furniture.part.\(id)", name, .length, .constraints,
          get: { e, _ in e.furnitureForm.map { .double(first ? $0.w0 : $0.w1) } },
          set: { e, v, _ in
              let d = try number(v, name)
              guard var f = e.furnitureForm else { return }
              if first { f.w0 = d } else { f.w1 = d }
              guard f.kind != .extrusion || abs(f.w1 - f.w0) > Tolerance.length else { throw err("The extrusion needs a depth.") }
              guard f.kind != .blend || f.w1 - f.w0 > Tolerance.length else { throw err("The blend's top must be above its base.") }
              e.furnitureForm = f
          })
    }
    static let extrusionStart = formRange("extrusionStart", "Extrusion Start", first: true)
    static let extrusionEnd = formRange("extrusionEnd", "Extrusion End", first: false)
    static let firstEnd = formRange("firstEnd", "First End", first: true)
    static let secondEnd = formRange("secondEnd", "Second End", first: false)
    static let formBase = formRange("formBase", "Base Elevation", first: true)
    static func visible(_ level: DetailLevel) -> P {
        P("furniture.part.visible.\(level.rawValue)", level.rawValue, .bool, .graphics,
          get: { e, _ in e.furnitureForm.map { .bool($0.visibleAt.contains(level)) } },
          set: { e, v, _ in
              guard var f = e.furnitureForm else { return }
              if v.boolValue == true { f.visibleAt.insert(level) } else { f.visibleAt.remove(level) }
              e.furnitureForm = f
          })
    }
    static func cushion(_ id: String, _ name: String, min lo: Double = 0, get: @escaping @Sendable (CushionSpec) -> Double,
                        set: @escaping @Sendable (inout CushionSpec, Double) -> Void) -> P {
        P("furniture.part.cushion.\(id)", name, .length, .dimensions,
          get: { e, _ in e.furnitureForm?.cushion.map { .double(get($0)) } },
          set: { e, v, _ in
              let d = try number(v, name)
              guard d >= lo else { throw err("“\(name)” is too small.") }
              guard var c = e.furnitureForm?.cushion else { return }
              set(&c, d)
              e.furnitureForm?.cushion = c
          })
    }
    static func cushionFlag(_ id: String, _ name: String, get: @escaping @Sendable (CushionSpec) -> Bool, set: @escaping @Sendable (inout CushionSpec, Bool) -> Void) -> P {
        P("furniture.part.cushion.\(id)", name, .bool, .construction,
          get: { e, _ in e.furnitureForm?.cushion.map { .bool(get($0)) } },
          set: { e, v, _ in
              guard var c = e.furnitureForm?.cushion else { return }
              set(&c, v.boolValue ?? false)
              e.furnitureForm?.cushion = c
          })
    }
    static let cushionParams: [P] = [
        cushion("width", "Width", min: 0.02, get: { $0.width }, set: { $0.width = $1 }),
        cushion("depth", "Depth", min: 0.02, get: { $0.depth }, set: { $0.depth = $1 }),
        cushion("height", "Height", min: 0.005, get: { $0.height }, set: { $0.height = $1 }),
        cushion("crown", "Crown", get: { $0.crown }, set: { $0.crown = $1 }),
        cushion("radius", "Corner Radius", get: { $0.cornerRadius }, set: { $0.cornerRadius = $1 }),
        cushionFlag("topPiping", "Top Piping", get: { $0.topPiping }, set: { $0.topPiping = $1 }),
        cushionFlag("bottomPiping", "Bottom Piping", get: { $0.bottomPiping }, set: { $0.bottomPiping = $1 }),
        cushion("piping", "Piping Diameter", get: { $0.pipingDiameter }, set: { $0.pipingDiameter = $1 }),
    ]

    // MARK: Lists

    static func instance(for e: Element) -> [P] {
        let typed = [BuiltInCatalog.familyName, BuiltInCatalog.typeName, BuiltInCatalog.familyAndType]
        let identity = [BuiltInCatalog.mark, BuiltInCatalog.comments]
        let phasing = [BuiltInCatalog.phaseCreated, BuiltInCatalog.phaseDemolished]
        let quantities = [length, width, thickness, size, area, volume]
        switch e.data {
        case .furniturePanel(let p):
            var list = typed + [panelFunction, panelLocation, baseConstraint, baseOffset, baseAttached, topConstraint, topOffset, unconnectedHeight, topAttached]
            if p.eq != nil { list.append(eqCount) }
            list += [banding] + (p.back != nil ? [backFit, backJoint] : [])
            return list + quantities + identity + phasing
        case .furnitureShelf(let s):
            return typed + [shelfFunction, elevationConstraint, heightOffset, frontSetback, adjustable] + (s.adjustable ? [pinSpacing] : [])
                + quantities + [perimeter] + identity + phasing
        case .furnitureLeg:
            return typed + [baseConstraint, baseOffset, topConstraint, topOffset, unconnectedHeight, topAttached, rotation, length, width, thickness, size, volume] + identity + phasing
        case .furnitureRail(let r):
            return typed + [railPlane, railOffset, zJust, yJust, startExtension, endExtension, startCut, endCut] // FMG1: y Justification, end cuts
                + (r.slats != nil ? [layoutRule, slatSpacing, slatNumber, slatExtent, count] : []) + quantities + identity + phasing
        case .furnitureEdgeProfile:
            return typed + [host, profileOffset, startSetback, endSetback, length] + identity + phasing
        case .furnitureForm(let f):
            var list: [P] = [formKind]
            switch f.kind {
            case .extrusion: list += [extrusionStart, extrusionEnd]
            case .blend: list += [firstEnd, secondEnd]
            case .revolve, .sweep, .sweptBlend, .cushion: list += [formBase]
            }
            if f.kind == .cushion { list += cushionParams }
            if !f.isVoid { list.append(formMaterial) }
            return list + [visible(.coarse), visible(.medium), visible(.fine), volume] + identity + phasing
        default:
            return []
        }
    }

    /// Every instance parameter of every part kind (for the catalog's lookup by id).
    static var allInstance: [P] {
        var panel = PanelData(start: .zero, end: Vec2(1, 0), base: 0, top: 1)
        panel.back = BackIntent(fit: .inside)
        panel.eq = EqualSpacing(low: .value(0), high: .value(1), index: 1, count: 2)
        var shelf = ShelfData(boundary: [.zero, Vec2(1, 0), Vec2(0, 1)], elevation: 0, adjustable: true)
        shelf.pins = ShelfPins()
        var rail = RailData(start: .zero, end: Vec2(1, 0), w: 0)
        rail.slats = SlatLayout(extent: 1)
        var cushion = FurnitureFormData(kind: .cushion, profile: [], w0: 0, w1: 0)
        cushion.cushion = CushionSpec(center: .zero, width: 1, depth: 1, height: 0.1)
        let data: [ElementData] = [.furniturePanel(panel), .furnitureShelf(shelf), .furnitureLeg(LegData(location: .zero, base: 0, top: 1)), .furnitureRail(rail),
                                   .furnitureEdgeProfile(EdgeProfileData(edge: PartEdge(axis: .x, firstAtMax: false, secondAtMax: false))), .furnitureForm(cushion)]
            + FurnitureFormKind.allCases.map { .furnitureForm(FurnitureFormData(kind: $0, profile: [], w0: 0, w1: 1)) }
        return data.flatMap { instance(for: Element(id: ElementID(0), category: .furnitureForms, data: $0)) }
    }

    /// Every type parameter of every part family.
    static var allType: [P] {
        [TypeData(instanceCategory: .furnitureShelves, familyName: "Top"), TypeData(instanceCategory: .furnitureEdgeProfiles, familyName: FurniturePartTypes.grooveFamily)]
            .flatMap(type(for:))
    }

    // MARK: Type parameters

    static func typeNumber(_ id: ParameterID, _ name: String, _ group: ParameterGroup = .dimensions, min: Double = 0) -> P {
        P(id.key, name, .length, group, get: { e, _ in e.typeData?.params[id] },
          set: { e, v, _ in
              let d = try number(v, name)
              guard d >= min else { throw err("“\(name)” is too small.") }
              e.typeData?.params[id] = .double(d)
          })
    }
    static func typeMaterial(_ id: ParameterID, _ name: String) -> P {
        P(id.key, name, .elementRef(.materials), .materials, get: { e, _ in e.typeData?.params[id] ?? .ref(nil) },
          set: { e, v, ctx in
              if let r = v.refValue, ctx.model[r]?.material == nil { throw err("Not a material.") }
              e.typeData?.params[id] = .ref(v.refValue)
          })
    }
    static func typeChoice(_ id: ParameterID, _ name: String, _ options: [String], _ group: ParameterGroup = .construction) -> P {
        P(id.key, name, .choice(options), group, get: { e, _ in e.typeData?.params[id] ?? .text(options.first ?? "") },
          set: { e, v, _ in
              guard options.contains(text(v)) else { throw err("Choose one of: \(options.joined(separator: ", ")).") }
              e.typeData?.params[id] = .text(text(v))
          })
    }
    static let tThickness = typeNumber(FurniturePartTypes.thickness, "Thickness", .construction, min: 0.0005)
    static let tCore = typeMaterial(FurniturePartTypes.coreMaterial, "Core Material")
    static let tFace = typeMaterial(FurniturePartTypes.faceMaterial, "Face Material")
    static let tEdge = typeMaterial(FurniturePartTypes.edgeMaterial, "Edge Band Material")
    static let tEdgeThickness = typeNumber(FurniturePartTypes.edgeThickness, "Edge Band Thickness", .materials)
    static let tBanding = P(FurniturePartTypes.banding.key, "Default Edge Banding", .text, .construction,
                            tooltip: "L1 L2 run along the length, W1 W2 along the width; e.g. “L1 W1”, or None.",
                            get: { e, _ in e.typeData?.params[FurniturePartTypes.banding] },
                            set: { e, v, _ in e.typeData?.params[FurniturePartTypes.banding] = .text(EdgeBanding(code: text(v)).code) })
    static let tGrain = typeChoice(FurniturePartTypes.grain, "Grain", GrainDirection.allCases.map(\.rawValue))
    static let tOverhang = typeNumber(FurniturePartTypes.overhang, "Overhang", .construction)
    static let tTopEdge = typeChoice(FurniturePartTypes.topEdge, "Edge Profile", TopEdge.allCases.map(\.rawValue))
    static let tLegShape = typeChoice(FurniturePartTypes.legShape, "Shape", LegShape.allCases.map(\.rawValue))
    static let tWidth = typeNumber(FurniturePartTypes.width, "Width (b)", min: 0.002)
    static let tDepth = typeNumber(FurniturePartTypes.depth, "Depth (h)", min: 0.002)
    static let tTaper = typeNumber(FurniturePartTypes.taper, "Taper to (foot)")
    static let tRod = typeNumber(FurniturePartTypes.rod, "Rod or Tube Size", min: 0.002)
    static let tRailProfile = typeChoice(FurniturePartTypes.railProfile, "Profile", RailProfile.allCases.map(\.rawValue))
    static let tRailHeight = typeNumber(FurniturePartTypes.depth, "Height (h)", min: 0.002)
    static let tProfileShape = typeChoice(FurniturePartTypes.profileShape, "Profile", EdgeProfileShape.allCases.map(\.rawValue))
    static let tSize = typeNumber(FurniturePartTypes.size, "Size", min: 0.0005)
    static let tGrooveDepth = typeNumber(FurniturePartTypes.grooveDepth, "Depth", min: 0.0005)

    static func type(for td: TypeData) -> [P] {
        switch td.instanceCategory {
        case .furniturePanels: [tThickness, tCore, tFace, tEdge, tEdgeThickness, tBanding, tGrain]
        case .furnitureShelves: [tThickness, tCore, tFace, tEdge, tEdgeThickness, tBanding, tGrain] + (td.familyName == "Top" ? [tOverhang, tTopEdge] : [])
        case .furnitureLegs: [tLegShape, tWidth, tDepth, tTaper, tRod, tCore]
        case .furnitureRails: [tRailProfile, tWidth, tRailHeight, tCore, tGrain]
        case .furnitureEdgeProfiles: [tProfileShape, tSize] + (td.familyName == FurniturePartTypes.grooveFamily || FurniturePartTypes.Values(td).profileShape == .bevel ? [tGrooveDepth] : []) // COMPD: bevels
        default: []
        }
    }
}
