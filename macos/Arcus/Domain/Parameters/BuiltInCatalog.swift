import Foundation
import ArcusGeometry
import ArcusCalc

/// The catalog of built-in parameters per element kind.
enum BuiltInCatalog {
    typealias P = BuiltInParameter

    // MARK: Helpers

    private static func err(_ s: String) -> ParameterError { ParameterError(s) }

    private static func positive(_ v: ParamValue, _ name: String) throws(ParameterError) -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw err("“\(name)” needs a number.") }
        guard d > Tolerance.length else { throw err("“\(name)” must be greater than zero.") }
        return d
    }
    private static func finite(_ v: ParamValue, _ name: String) throws(ParameterError) -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw err("“\(name)” needs a number.") }
        return d
    }
    private static func bool(_ v: ParamValue) throws(ParameterError) -> Bool {
        guard let b = v.boolValue else { throw err("Type Yes or No.") }
        return b
    }
    private static func levelRef(_ v: ParamValue, _ ctx: ParameterContext, allowNone: Bool) throws(ParameterError) -> ElementID? {
        guard let id = v.refValue else {
            if allowNone { return nil }
            throw err("A level is required.")
        }
        guard ctx.model[id]?.level != nil else { throw err("The chosen element is not a level.") }
        return id
    }
    private static func text(_ v: ParamValue) -> String { v.textValue ?? v.description }

    // MARK: Common

    static let mark = P("mark", "Mark", .text, .identity, tooltip: "A unique identifier for the element, used in tags and schedules.",
                        get: { e, _ in .text(e.mark) }, set: { e, v, _ in e.mark = text(v) })
    static let comments = P("comments", "Comments", .multilineText, .identity,
                            get: { e, _ in .text(e.comments) }, set: { e, v, _ in e.comments = text(v) })
    static let phaseCreated = P("phaseCreated", "Phase Created", .elementRef(.phases), .phasing,
                                get: { e, _ in .ref(e.phaseCreated) },
                                set: { e, v, ctx in
                                    if let d = e.phaseDemolished, let v = v.refValue, (ctx.model.phaseOrder(v) ?? 0) > (ctx.model.phaseOrder(d) ?? .max) {
                                        throw err("An element can't be created after it is demolished.")
                                    }
                                    e.phaseCreated = v.refValue
                                })
    static let phaseDemolished = P("phaseDemolished", "Phase Demolished", .elementRef(.phases), .phasing,
                                   get: { e, _ in .ref(e.phaseDemolished) },
                                   set: { e, v, ctx in
                                       if let d = v.refValue, let c = e.phaseCreated, (ctx.model.phaseOrder(d) ?? 0) < (ctx.model.phaseOrder(c) ?? 0) {
                                           throw err("An element can't be demolished before it is created.")
                                       }
                                       e.phaseDemolished = v.refValue
                                   })
    static let familyName = P("familyName", "Family", .text, .identity,
                              get: { e, ctx in .text(ctx.model.typeData(of: e)?.familyName ?? e.category.singularName) })
    static let typeName = P("typeName", "Type", .text, .identity, get: { e, ctx in .text(ctx.model.type(of: e)?.name ?? "") })
    static let familyAndType = P("familyAndType", "Family and Type", .elementRef(.elementTypes), .identity,
                                 get: { e, _ in .ref(e.typeID) },
                                 set: { e, v, ctx in
                                     guard let t = v.refValue, let td = ctx.model[t]?.typeData else { throw err("Choose a type.") }
                                     guard td.instanceCategory == e.category else { throw err("That type belongs to \(td.instanceCategory.displayName).") }
                                     e.typeID = t
                                 })
    static let ifcGUID = P("ifcGUID", "IFC GUID", .text, .ifc, tooltip: "IFC GlobalId, preserved across IFC round trips.",
                           get: { e, _ in .text(e.ifcGUID.value) })
    static let elementIDParam = P("elementID", "Element ID", .integer, .identity, get: { e, _ in .int(Int(e.id.raw)) })
    static let designOption = P("designOption", "Design Option", .text, .identity,
                                get: { e, ctx in .text(ctx.model[e.designOptionID].map { "\($0.designOption?.setName ?? ""): \($0.name)" } ?? "Main Model") })
    static let levelParam = P("level", "Level", .elementRef(.levels), .constraints,
                              get: { e, _ in .ref(e.levelID) },
                              set: { e, v, ctx in e.levelID = try levelRef(v, ctx, allowNone: false) })
    static let name = P("name", "Name", .text, .identity,
                        get: { e, _ in .text(e.name) },
                        set: { e, v, _ in
                            let s = text(v).trimmingCharacters(in: .whitespaces)
                            guard !s.isEmpty else { throw err("The name can't be empty.") }
                            e.name = s
                        })
    static let classificationCode = P("classification", "Classification Code", .text, .ifc,
                                      get: { e, _ in .text(e.classification?.code ?? "") },
                                      set: { e, v, _ in
                                          let s = text(v)
                                          e.classification = s.isEmpty ? nil : Classification(system: e.classification?.system ?? "Uniclass 2015", code: s, title: e.classification?.title ?? "")
                                      })

    static func q(_ key: String, _ name: String, _ type: ParamType, _ group: ParameterGroup = .dimensions,
                  _ f: @escaping @Sendable (ElementQuantities) -> Double?) -> P {
        P(key, name, type, group, get: { e, ctx in ctx.quantities(e).value(f) })
    }

    // MARK: Walls

    static let wallLocationLine = P("wall.locationLine", "Location Line", .choice(WallLocationLine.allCases.map(\.rawValue)), .constraints,
                                    get: { e, _ in .text(e.wall?.locationLine.rawValue ?? "") },
                                    set: { e, v, _ in
                                        guard let l = WallLocationLine(rawValue: text(v)) else { throw err("Unknown location line.") }
                                        e.wall?.locationLine = l
                                    })
    static let wallBaseOffset = P("wall.baseOffset", "Base Offset", .length, .constraints,
                                  get: { e, _ in e.wall.map { .double($0.baseOffset) } },
                                  set: { e, v, _ in e.wall?.baseOffset = try finite(v, "Base Offset") })
    static let wallTopConstraint = P("wall.topConstraint", "Top Constraint", .elementRef(.levels), .constraints,
                                     tooltip: "Level the top of the wall is attached to, or Unconnected.",
                                     get: { e, _ in .ref(e.wall?.topLevelID) },
                                     set: { e, v, ctx in
                                         let id = try levelRef(v, ctx, allowNone: true)
                                         if id == nil, let w = e.wall, let t = w.topLevelID {
                                             // Keep the current height when switching to unconnected.
                                             let base = ctx.model.elevation(ofLevel: e.levelID) + w.baseOffset
                                             e.wall?.unconnectedHeight = max(0.1, ctx.model.elevation(ofLevel: t) + w.topOffset - base)
                                         }
                                         e.wall?.topLevelID = id
                                     })
    static let wallUnconnectedHeight = P("wall.unconnectedHeight", "Unconnected Height", .length, .constraints,
                                         get: { e, ctx in
                                             guard let w = e.wall else { return nil }
                                             if w.topLevelID != nil { return .double(ctx.quantities(e).height ?? w.unconnectedHeight) }
                                             return .double(w.unconnectedHeight)
                                         },
                                         set: { e, v, _ in e.wall?.unconnectedHeight = try positive(v, "Unconnected Height") },
                                         locked: { e, _ in e.wall?.topLevelID != nil ? "The height comes from the Top Constraint level. Set Top Constraint to Unconnected to edit it." : nil })
    static let wallTopOffset = P("wall.topOffset", "Top Offset", .length, .constraints,
                                 get: { e, _ in e.wall.map { .double($0.topOffset) } },
                                 set: { e, v, _ in e.wall?.topOffset = try finite(v, "Top Offset") },
                                 locked: { e, _ in e.wall?.topLevelID == nil ? "Top Offset applies only when the wall has a Top Constraint level." : nil })
    static let wallRoomBounding = P("wall.roomBounding", "Room Bounding", .bool, .constraints,
                                    get: { e, _ in e.wall.map { .bool($0.roomBounding) } },
                                    set: { e, v, _ in e.wall?.roomBounding = try bool(v) })
    static let wallStructural = P("wall.structural", "Structural", .bool, .structural,
                                  get: { e, _ in e.wall.map { .bool($0.structural) } },
                                  set: { e, v, _ in e.wall?.structural = try bool(v) })
    static let wallSlant = P("wall.slant", "Angle From Vertical", .angle, .crossSection, // BL-PROPS: group
                             get: { e, _ in e.wall.map { .double($0.slantAngle) } },
                             set: { e, v, _ in
                                 let a = try finite(v, "Angle From Vertical")
                                 guard abs(a) <= Angle.radians(60) + Tolerance.angle else { throw err("Walls can slant at most 60° from vertical.") }
                                 e.wall?.slantAngle = a
                             })
    static let wallTopAttached = P("wall.topAttached", "Top is Attached", .bool, .constraints,
                                   get: { e, _ in e.wall.map { .bool(!$0.attachedTopIDs.isEmpty) } })
    static let wallBaseAttached = P("wall.baseAttached", "Base is Attached", .bool, .constraints,
                                    get: { e, _ in e.wall.map { .bool(!$0.attachedBaseIDs.isEmpty) } })

    // MARK: Inserts & components

    static let sillHeight = P("insert.sillHeight", "Sill Height", .length, .constraints,
                              get: { e, _ in e.insert.map { .double($0.sillHeight) } },
                              set: { e, v, _ in e.insert?.sillHeight = try finite(v, "Sill Height") })
    static let headHeight = P("insert.headHeight", "Head Height", .length, .other, // BL-PROPS: group
                              get: { e, ctx in
                                  guard let i = e.insert else { return nil }
                                  return .double(i.sillHeight + (InsertGeometry.openingSize(e, ctx.model)?.height ?? 0))
                              },
                              set: { e, v, ctx in
                                  let h = try finite(v, "Head Height")
                                  let oh = InsertGeometry.openingSize(e, ctx.model)?.height ?? 0
                                  e.insert?.sillHeight = h - oh
                              })
    static let hostName = P("insert.host", "Host", .text, .constraints,
                            get: { e, ctx in .text(ctx.model[e.hostID].map { "\($0.category.singularName): \(ctx.model.type(of: $0)?.name ?? "") \($0.id)" } ?? "<None>") })
    static let fromRoom = P("insert.fromRoom", "From Room", .text, .other,
                            get: { e, ctx in .text(RoomQueries.roomsAround(insert: e, ctx.model).from.map { "\($0.room?.number ?? "") \($0.name)" } ?? "") })
    static let toRoom = P("insert.toRoom", "To Room", .text, .other,
                          get: { e, ctx in .text(RoomQueries.roomsAround(insert: e, ctx.model).to.map { "\($0.room?.number ?? "") \($0.name)" } ?? "") })
    static let componentOffset = P("component.offset", "Elevation from Level", .length, .constraints,
                                   get: { e, _ in e.component.map { .double($0.offset) } },
                                   set: { e, v, _ in e.component?.offset = try finite(v, "Elevation from Level") })
    static let componentRotation = P("component.rotation", "Rotation", .angle, .constraints,
                                     get: { e, _ in e.component.map { .double(Angle.normalize($0.rotation)) } },
                                     set: { e, v, _ in e.component?.rotation = try finite(v, "Rotation") })
    static let componentRoom = P("component.room", "Room", .text, .other,
                                 get: { e, ctx in .text(RoomQueries.room(containing: e, ctx.model).map { "\($0.room?.number ?? "") \($0.name)" } ?? "") })

    // MARK: Columns & beams

    static let columnBaseOffset = P("column.baseOffset", "Base Offset", .length, .constraints,
                                    get: { e, _ in e.column.map { .double($0.baseOffset) } },
                                    set: { e, v, _ in e.column?.baseOffset = try finite(v, "Base Offset") })
    static let columnTopLevel = P("column.topLevel", "Top Level", .elementRef(.levels), .constraints,
                                  get: { e, _ in .ref(e.column?.topLevelID) },
                                  set: { e, v, ctx in e.column?.topLevelID = try levelRef(v, ctx, allowNone: true) })
    static let columnTopOffset = P("column.topOffset", "Top Offset", .length, .constraints,
                                   get: { e, _ in e.column.map { .double($0.topOffset) } },
                                   set: { e, v, _ in e.column?.topOffset = try finite(v, "Top Offset") })
    static let columnHeight = P("column.height", "Unconnected Height", .length, .constraints,
                                get: { e, _ in e.column.map { .double($0.unconnectedHeight) } },
                                set: { e, v, _ in e.column?.unconnectedHeight = try positive(v, "Unconnected Height") },
                                locked: { e, _ in e.column?.topLevelID != nil ? "The height comes from the Top Level." : nil })
    static let columnRotation = P("column.rotation", "Rotation", .angle, .constraints,
                                  get: { e, _ in e.column.map { .double(Angle.normalize($0.rotation)) } },
                                  set: { e, v, _ in e.column?.rotation = try finite(v, "Rotation") })
    static let columnRoomBounding = P("column.roomBounding", "Room Bounding", .bool, .constraints,
                                      get: { e, _ in e.column.map { .bool($0.roomBounding) } },
                                      set: { e, v, _ in e.column?.roomBounding = try bool(v) })
    static let beamStartOffset = P("beam.startOffset", "Start Level Offset", .length, .constraints,
                                   get: { e, _ in e.beam.map { .double($0.startOffset) } },
                                   set: { e, v, _ in e.beam?.startOffset = try finite(v, "Start Level Offset") })
    static let beamEndOffset = P("beam.endOffset", "End Level Offset", .length, .constraints,
                                 get: { e, _ in e.beam.map { .double($0.endOffset) } },
                                 set: { e, v, _ in e.beam?.endOffset = try finite(v, "End Level Offset") })
    static let beamZJust = P("beam.zJustification", "Z Justification", .choice(BeamZJustification.allCases.map(\.rawValue)), .constraints,
                             get: { e, _ in .text(e.beam?.zJustification.rawValue ?? "") },
                             set: { e, v, _ in
                                 guard let j = BeamZJustification(rawValue: text(v)) else { throw err("Unknown justification.") }
                                 e.beam?.zJustification = j
                             })

    // MARK: Slabs, roofs

    static let slabOffset = P("slab.offset", "Height Offset From Level", .length, .constraints,
                              get: { e, _ in e.slab.map { .double($0.offset) } },
                              set: { e, v, _ in e.slab?.offset = try finite(v, "Height Offset From Level") })
    static let slabRoomBounding = P("slab.roomBounding", "Room Bounding", .bool, .constraints,
                                    get: { e, _ in e.slab.map { .bool($0.roomBounding) } },
                                    set: { e, v, _ in e.slab?.roomBounding = try bool(v) })
    static let slabStructural = P("slab.structural", "Structural", .bool, .structural,
                                  get: { e, _ in e.slab.map { .bool($0.structural) } },
                                  set: { e, v, _ in e.slab?.structural = try bool(v) })
    static let slabSlope = P("slab.slope", "Slope", .slope, .dimensions,
                             get: { e, _ in .double(e.slab?.slopeArrow?.slope ?? 0) },
                             set: { e, v, _ in
                                 let s = try finite(v, "Slope")
                                 guard abs(s) < 10 else { throw err("That slope is too steep for a floor.") }
                                 guard var arrow = e.slab?.slopeArrow else { throw err("Add a slope arrow in Edit Boundary to slope this floor.") }
                                 arrow.slope = s
                                 e.slab?.slopeArrow = arrow
                             })
    static let roofBaseOffset = P("roof.baseOffset", "Base Offset From Level", .length, .constraints,
                                  get: { e, _ in e.roof.map { .double($0.baseOffset) } },
                                  set: { e, v, _ in e.roof?.baseOffset = try finite(v, "Base Offset From Level") })
    static let roofSlope = P("roof.slope", "Slope", .slope, .dimensions, tooltip: "Applies to every slope-defining edge.",
                             get: { e, _ in
                                 guard let a = e.roof?.edgeSlopes.compactMap({ $0 }).first else { return .double(0) }
                                 return .double(tan(a))
                             },
                             set: { e, v, _ in
                                 let s = try finite(v, "Slope")
                                 guard s > 0, s < 20 else { throw err("Roof slope must be between 0 and 20 (rise/run).") }
                                 let a = atan(s)
                                 let current = e.roof?.edgeSlopes ?? []; e.roof?.edgeSlopes = current.map { $0 == nil ? nil : a }
                             })
    static let roofFascia = P("roof.fascia", "Fascia", .bool, .construction,
                              get: { e, _ in e.roof.map { .bool($0.fascia) } }, set: { e, v, _ in e.roof?.fascia = try bool(v) })
    static let roofGutter = P("roof.gutter", "Gutter", .bool, .construction,
                              get: { e, _ in e.roof.map { .bool($0.gutter) } }, set: { e, v, _ in e.roof?.gutter = try bool(v) })

    // MARK: Stairs & railings

    static let stairBaseOffset = P("stair.baseOffset", "Base Offset", .length, .constraints,
                                   get: { e, _ in e.stair.map { .double($0.baseOffset) } },
                                   set: { e, v, _ in e.stair?.baseOffset = try finite(v, "Base Offset") })
    static let stairTopLevel = P("stair.topLevel", "Top Level", .elementRef(.levels), .constraints,
                                 get: { e, _ in .ref(e.stair?.topLevelID) },
                                 set: { e, v, ctx in e.stair?.topLevelID = try levelRef(v, ctx, allowNone: true) })
    static let stairTopOffset = P("stair.topOffset", "Top Offset", .length, .constraints,
                                  get: { e, _ in e.stair.map { .double($0.topOffset) } },
                                  set: { e, v, _ in e.stair?.topOffset = try finite(v, "Top Offset") })
    static let stairHeight = P("stair.height", "Desired Stair Height", .length, .constraints,
                               get: { e, ctx in ctx.quantities(e).height.map { .double($0) } },
                               set: { e, v, _ in e.stair?.unconnectedHeight = try positive(v, "Desired Stair Height") },
                               locked: { e, _ in e.stair?.topLevelID != nil ? "The height comes from the Top Level." : nil })
    static let stairWidth = P("stair.width", "Actual Run Width", .length, .dimensions,
                              get: { e, _ in e.stair.map { .double($0.width) } },
                              set: { e, v, _ in
                                  let w = try positive(v, "Actual Run Width")
                                  guard w >= 0.6 else { throw err("A stair run must be at least 600 mm wide.") }
                                  e.stair?.width = w
                              })
    static let stairShape = P("stair.shape", "Shape", .choice(StairShape.allCases.map(\.rawValue)), .construction,
                              get: { e, _ in .text(e.stair?.shape.rawValue ?? "") },
                              set: { e, v, _ in
                                  guard let s = StairShape(rawValue: text(v)) else { throw err("Unknown stair shape.") }
                                  e.stair?.shape = s
                              })
    static let stairTurnsLeft = P("stair.turnsLeft", "Turns Left", .bool, .construction,
                                  get: { e, _ in e.stair.map { .bool($0.turnsLeft) } },
                                  set: { e, v, _ in e.stair?.turnsLeft = try bool(v) })
    static let stairDesiredRisers = P("stair.desiredRisers", "Desired Number of Risers", .integer, .dimensions,
                                      get: { e, ctx in .int(e.stair?.desiredRiserCount ?? StairGeometry.layout(e, ctx.model)?.riserCount ?? 0) },
                                      set: { e, v, _ in
                                          guard let n = v.intValue, n >= 2, n <= 60 else { throw err("Risers must be between 2 and 60.") }
                                          e.stair?.desiredRiserCount = n
                                      })
    static let stairActualRisers = P("stair.actualRisers", "Actual Number of Risers", .integer, .dimensions,
                                     get: { e, ctx in StairGeometry.layout(e, ctx.model).map { .int($0.riserCount) } })
    static let stairRiserHeight = P("stair.actualRiserHeight", "Actual Riser Height", .length, .dimensions,
                                    get: { e, ctx in StairGeometry.layout(e, ctx.model).map { .double($0.riserHeight) } })
    static let stairTreadDepth = P("stair.actualTreadDepth", "Actual Tread Depth", .length, .dimensions,
                                   get: { e, ctx in StairGeometry.layout(e, ctx.model).map { .double($0.treadDepth) } })
    static let railingBaseOffset = P("railing.baseOffset", "Base Offset", .length, .constraints,
                                     get: { e, _ in e.railing.map { .double($0.baseOffset) } },
                                     set: { e, v, _ in e.railing?.baseOffset = try finite(v, "Base Offset") })

    // MARK: Rooms

    static let roomNumber = P("room.number", "Number", .text, .identity,
                              get: { e, _ in .text(e.room?.number ?? "") },
                              set: { e, v, _ in e.room?.number = text(v) })
    static let roomName = P("name", "Name", .text, .identity,
                            get: { e, _ in .text(e.name) }, set: { e, v, _ in e.name = text(v) })
    static let roomUpperLimit = P("room.upperLimit", "Upper Limit", .elementRef(.levels), .constraints,
                                  get: { e, _ in .ref(e.room?.upperLimitLevelID ?? e.levelID) },
                                  set: { e, v, ctx in e.room?.upperLimitLevelID = try levelRef(v, ctx, allowNone: true) })
    static let roomLimitOffset = P("room.limitOffset", "Limit Offset", .length, .constraints,
                                   get: { e, _ in e.room.map { .double($0.limitOffset) } },
                                   set: { e, v, _ in e.room?.limitOffset = try finite(v, "Limit Offset") })
    static let roomBaseOffset = P("room.baseOffset", "Base Offset", .length, .constraints,
                                  get: { e, _ in e.room.map { .double($0.baseOffset) } },
                                  set: { e, v, _ in e.room?.baseOffset = try finite(v, "Base Offset") })
    static func roomText(_ key: String, _ name: String, _ group: ParameterGroup = .identity) -> P {
        let id = ParameterID(key)
        return P(key, name, .text, group, get: { e, _ in .text(e.params[id]?.textValue ?? "") },
                 set: { e, v, _ in let s = text(v); e.params[id] = s.isEmpty ? nil : .text(s) })
    }

    // MARK: Levels & grids

    static let levelElevation = P("level.elevation", "Elevation", .length, .constraints,
                                  get: { e, _ in e.level.map { .double($0.elevation) } },
                                  set: { e, v, _ in e.level?.elevation = try finite(v, "Elevation") })
    static let levelStorey = P("level.storey", "Building Story", .bool, .identity,
                               get: { e, _ in e.level.map { .bool($0.isBuildingStorey) } },
                               set: { e, v, _ in e.level?.isBuildingStorey = try bool(v) })
    static let levelStructural = P("level.structural", "Structural", .bool, .structural,
                                   get: { e, _ in e.level.map { .bool($0.isStructural) } },
                                   set: { e, v, _ in e.level?.isStructural = try bool(v) })
    static let levelComputation = P("level.computationHeight", "Computation Height", .length, .dimensions,
                                    get: { e, _ in e.level.map { .double($0.computationHeight) } },
                                    set: { e, v, _ in e.level?.computationHeight = try finite(v, "Computation Height") })
    static let gridBubbleStart = P("grid.bubbleStart", "Bubble at Start", .bool, .graphics,
                                   get: { e, _ in e.grid.map { .bool($0.bubbleAtStart) } },
                                   set: { e, v, _ in e.grid?.bubbleAtStart = try bool(v) })
    static let gridBubbleEnd = P("grid.bubbleEnd", "Bubble at End", .bool, .graphics,
                                 get: { e, _ in e.grid.map { .bool($0.bubbleAtEnd) } },
                                 set: { e, v, _ in e.grid?.bubbleAtEnd = try bool(v) })

    // MARK: Views

    static let viewScale = P("view.scale", "View Scale", .integer, .graphics, tooltip: "Scale denominator (100 = 1:100).",
                             get: { e, _ in e.view.map { .int($0.scale) } },
                             set: { e, v, _ in
                                 guard let s = v.intValue, s >= 1, s <= 20_000 else { throw err("Scale must be between 1 and 20000.") }
                                 e.view?.scale = s
                             }, locked: templateLock(.scale)) // BL-VG
    static let viewDetail = P("view.detailLevel", "Detail Level", .choice(DetailLevel.allCases.map(\.rawValue)), .graphics,
                              get: { e, _ in .text(e.view?.detailLevel.rawValue ?? "") },
                              set: { e, v, _ in
                                  guard let d = DetailLevel(rawValue: text(v)) else { throw err("Unknown detail level.") }
                                  e.view?.detailLevel = d
                              }, locked: templateLock(.detailLevel)) // BL-VG
    static let viewStyle = P("view.visualStyle", "Visual Style", .choice(VisualStyle.allCases.map(\.rawValue)), .graphics,
                             get: { e, _ in .text(e.view?.visualStyle.rawValue ?? "") },
                             set: { e, v, _ in
                                 guard let d = VisualStyle(rawValue: text(v)) else { throw err("Unknown visual style.") }
                                 e.view?.visualStyle = d
                             }, locked: templateLock(.visualStyle)) // BL-VG
    static let viewDiscipline = P("view.discipline", "Discipline", .choice(Discipline.allCases.map(\.rawValue)), .graphics,
                                  get: { e, _ in .text(e.view?.discipline.rawValue ?? "") },
                                  set: { e, v, _ in
                                      guard let d = Discipline(rawValue: text(v)) else { throw err("Unknown discipline.") }
                                      e.view?.discipline = d
                                  }, locked: templateLock(.discipline)) // BL-VG
    static let viewCrop = P("view.cropActive", "Crop View", .bool, .extents,
                            get: { e, _ in e.view.map { .bool($0.cropActive) } },
                            set: { e, v, _ in e.view?.cropActive = try bool(v) })
    static let viewCropVisible = P("view.cropVisible", "Crop Region Visible", .bool, .extents,
                                   get: { e, _ in e.view.map { .bool($0.cropVisible) } },
                                   set: { e, v, _ in e.view?.cropVisible = try bool(v) })
    static let viewAnnotationCrop = P("view.annotationCrop", "Annotation Crop", .bool, .extents,
                                      get: { e, _ in e.view.map { .bool($0.annotationCropActive) } },
                                      set: { e, v, _ in e.view?.annotationCropActive = try bool(v) })
    static let viewTitleOnSheet = P("view.titleOnSheet", "Title on Sheet", .text, .identity,
                                    get: { e, _ in .text(e.view?.titleOnSheet ?? "") },
                                    set: { e, v, _ in e.view?.titleOnSheet = text(v) })
    static let viewPhase = P("view.phase", "Phase", .elementRef(.phases), .phasing,
                             get: { e, ctx in .ref(e.view?.phaseID ?? ctx.model.latestPhase?.id) },
                             set: { e, v, _ in e.view?.phaseID = v.refValue })
    static let viewPhaseFilter = P("view.phaseFilter", "Phase Filter", .choice(PhaseFilter.allCases.map(\.rawValue)), .phasing,
                                   get: { e, _ in .text(e.view?.phaseFilter.rawValue ?? "") },
                                   set: { e, v, _ in
                                       guard let f = PhaseFilter(rawValue: text(v)) else { throw err("Unknown phase filter.") }
                                       e.view?.phaseFilter = f
                                   }, locked: templateLock(.phaseFilter)) // BL-VG
    static let viewTemplate = P("view.template", "View Template", .elementRef(.viewTemplates), .identity,
                                get: { e, _ in .ref(e.view?.templateID) },
                                set: { e, v, ctx in
                                    if let t = v.refValue {
                                        guard let td = ctx.model[t]?.viewTemplate else { throw err("Not a view template.") }
                                        guard td.appliesTo == e.view?.kind || (td.appliesTo.isPlan && e.view?.kind.isPlan == true) else {
                                            throw err("This template is for \(td.appliesTo.rawValue) views.")
                                        }
                                        if var d = e.view { ViewTemplates.apply(td, to: &d); e.view = d } // BL-VG: the view takes the template's settings
                                    }
                                    e.view?.templateID = v.refValue
                                })
    static let viewUnderlay = P("view.underlay", "Underlay", .elementRef(.levels), .graphics,
                                get: { e, _ in .ref(e.view?.underlayLevelID) },
                                set: { e, v, ctx in e.view?.underlayLevelID = try levelRef(v, ctx, allowNone: true) })
    static let viewCut = P("view.cutPlane", "Cut Plane Offset", .length, .extents,
                           get: { e, _ in e.view.map { .double($0.viewRange.cutOffset) } },
                           set: { e, v, ctx in
                               let d = try finite(v, "Cut Plane Offset")
                               guard let r = e.view?.viewRange, !r.isAssociatedLevelOnly || (d <= r.topOffset + Tolerance.length && d >= r.bottomOffset - Tolerance.length) else { // BL-BROWSER
                                   throw err("The cut plane must lie between the bottom and top of the view range.")
                               }
                               e.view?.viewRange.cutOffset = d
                               try checkViewRange(e, ctx) // BL-BROWSER
                           }, locked: templateLock(.viewRange)) // BL-VG
    static let viewTop = P("view.topPlane", "Top Offset", .length, .extents,
                           get: { e, _ in e.view.map { .double($0.viewRange.topOffset) } },
                           set: { e, v, ctx in
                               let d = try finite(v, "Top Offset")
                               guard let r = e.view?.viewRange, !r.isAssociatedLevelOnly || d >= r.cutOffset - Tolerance.length else { throw err("The top must be at or above the cut plane.") } // BL-BROWSER
                               e.view?.viewRange.topOffset = d
                               try checkViewRange(e, ctx) // BL-BROWSER
                           }, locked: templateLock(.viewRange)) // BL-VG
    static let viewBottom = P("view.bottomPlane", "Bottom Offset", .length, .extents,
                              get: { e, _ in e.view.map { .double($0.viewRange.bottomOffset) } },
                              set: { e, v, ctx in
                                  let d = try finite(v, "Bottom Offset")
                                  guard let r = e.view?.viewRange, !r.isAssociatedLevelOnly || d <= r.cutOffset + Tolerance.length else { throw err("The bottom must be at or below the cut plane.") } // BL-BROWSER
                                  e.view?.viewRange.bottomOffset = d
                                  if r.isAssociatedLevelOnly, d < r.depthOffset { e.view?.viewRange.depthOffset = d } // BL-BROWSER
                                  try checkViewRange(e, ctx) // BL-BROWSER
                              }, locked: templateLock(.viewRange)) // BL-VG
    static let viewDepth = P("view.depthPlane", "View Depth Offset", .length, .extents,
                             get: { e, _ in e.view.map { .double($0.viewRange.depthOffset) } },
                             set: { e, v, ctx in
                                 let d = try finite(v, "View Depth Offset")
                                 guard let r = e.view?.viewRange, !r.isAssociatedLevelOnly || d <= r.bottomOffset + Tolerance.length else { throw err("View depth must be at or below the bottom.") } // BL-BROWSER
                                 e.view?.viewRange.depthOffset = d
                                 try checkViewRange(e, ctx) // BL-BROWSER
                             }, locked: templateLock(.viewRange)) // BL-VG
    static let viewFarClip = P("view.farClip", "Far Clip Offset", .length, .extents,
                               get: { e, _ in e.view.map { .double($0.farClip) } },
                               set: { e, v, _ in e.view?.farClip = try positive(v, "Far Clip Offset") })
    static let viewSectionBox = P("view.sectionBox", "Section Box", .bool, .extents,
                                  get: { e, _ in e.view.map { .bool($0.sectionBoxActive) } },
                                  set: { e, v, _ in e.view?.sectionBoxActive = try bool(v) })
    static let viewSheetNumber = P("view.sheetNumber", "Sheet Number", .text, .identity,
                                   get: { e, ctx in .text(ctx.model.sheet(containing: e.id)?.sheet?.number ?? "") })
    static let viewSheetName = P("view.sheetName", "Sheet Name", .text, .identity,
                                 get: { e, ctx in .text(ctx.model.sheet(containing: e.id)?.name ?? "") })
    static let viewDetailNumber = P("view.detailNumber", "Detail Number", .text, .identity,
                                    get: { e, ctx in .text(ctx.model.viewports(showing: e.id).first?.viewport?.detailNumber ?? "") })
    static let viewAssociatedLevel = P("view.associatedLevel", "Associated Level", .text, .identity,
                                       get: { e, ctx in .text(ctx.model[e.levelID]?.name ?? "") })
    static let viewKind = P("view.kind", "View Type", .text, .identity, get: { e, _ in .text(e.view?.kind.rawValue ?? "") })

    /// Locks a view parameter only while the view's template controls that setting. // BL-VG
    static func templateLock(_ setting: ViewTemplates.Setting) -> @Sendable (Element, ParameterContext) -> String? {
        { e, ctx in
            guard let t = e.view?.templateID, let tpl = ctx.model[t] else { return nil }
            if let td = tpl.viewTemplate, !ViewTemplates.controls(td, setting) { return nil }
            return "Controlled by the view template “\(tpl.name)”. Remove the template, or stop the template controlling \(setting.rawValue), to edit."
        }
    }

    // MARK: Sheets & viewports

    static let sheetNumber = P("sheet.number", "Sheet Number", .text, .identity,
                               get: { e, _ in .text(e.sheet?.number ?? "") },
                               set: { e, v, ctx in
                                   let n = text(v).trimmingCharacters(in: .whitespaces)
                                   guard !n.isEmpty else { throw err("Sheet numbers can't be empty.") }
                                   if ctx.model.sheets.contains(where: { $0.id != e.id && $0.sheet?.number == n }) {
                                       throw err("Sheet number “\(n)” is already in use.")
                                   }
                                   e.sheet?.number = n
                               })
    static let sheetName = P("name", "Sheet Name", .text, .identity,
                             get: { e, _ in .text(e.name) }, set: { e, v, _ in e.name = text(v) })
    static func sheetText(_ key: String, _ name: String, _ kp: any WritableKeyPath<SheetData, String> & Sendable) -> P {
        P(key, name, .text, .identity, get: { e, _ in .text(e.sheet?[keyPath: kp] ?? "") },
          set: { e, v, _ in e.sheet?[keyPath: kp] = text(v) })
    }
    static let sheetPaper = P("sheet.paper", "Paper Size", .choice(PaperSize.allCases.map(\.rawValue)), .graphics,
                              get: { e, _ in .text(e.sheet?.paper.rawValue ?? "") },
                              set: { e, v, _ in
                                  guard let p = PaperSize(rawValue: text(v)) else { throw err("Unknown paper size.") }
                                  e.sheet?.paper = p
                              })
    static let sheetInList = P("sheet.appearsInList", "Appears In Sheet List", .bool, .identity,
                               get: { e, _ in e.sheet.map { .bool($0.appearsInSheetList) } },
                               set: { e, v, _ in e.sheet?.appearsInSheetList = try bool(v) })
    static let sheetCurrentRevision = P("sheet.currentRevision", "Current Revision", .text, .identity,
                                        get: { e, ctx in .text(RevisionQueries.current(onSheet: e, ctx.model).map { RevisionQueries.label($0, ctx.model) } ?? "") })
    static let sheetCurrentRevisionDate = P("sheet.currentRevisionDate", "Current Revision Date", .text, .identity,
                                            get: { e, ctx in .text(RevisionQueries.current(onSheet: e, ctx.model)?.revisionData?.date ?? "") })
    static let sheetCurrentRevisionDescription = P("sheet.currentRevisionDescription", "Current Revision Description", .text, .identity,
                                                   get: { e, ctx in .text(RevisionQueries.current(onSheet: e, ctx.model)?.revisionData?.description ?? "") })
    static let viewportDetailNumber = P("viewport.detailNumber", "Detail Number", .text, .identity,
                                        get: { e, _ in .text(e.viewport?.detailNumber ?? "") },
                                        set: { e, v, ctx in
                                            let n = text(v)
                                            if ctx.model.owned(byView: e.ownerViewID ?? e.id).contains(where: { $0.id != e.id && $0.viewport?.detailNumber == n }) {
                                                throw err("Detail number “\(n)” is already used on this sheet.")
                                            }
                                            e.viewport?.detailNumber = n
                                        })
    static let viewportShowTitle = P("viewport.showTitle", "Show Title", .bool, .graphics,
                                     get: { e, _ in e.viewport.map { .bool($0.showTitle) } },
                                     set: { e, v, _ in e.viewport?.showTitle = try bool(v) })

    // MARK: Revisions

    static let revSequence = P("revision.sequence", "Sequence", .integer, .identity, get: { e, _ in e.revisionData.map { .int($0.sequence) } })
    static let revNumber = P("revision.number", "Revision Number", .text, .identity, get: { e, ctx in .text(RevisionQueries.label(e, ctx.model)) })
    static func revText(_ key: String, _ name: String, _ kp: any WritableKeyPath<RevisionData, String> & Sendable) -> P {
        P(key, name, .text, .identity, get: { e, _ in .text(e.revisionData?[keyPath: kp] ?? "") },
          set: { e, v, _ in
              if e.revisionData?.issued == true { throw err("Issued revisions are locked. Clear “Issued” to edit.") }
              e.revisionData?[keyPath: kp] = text(v)
          })
    }
    static let revIssued = P("revision.issued", "Issued", .bool, .identity,
                             get: { e, _ in e.revisionData.map { .bool($0.issued) } },
                             set: { e, v, _ in e.revisionData?.issued = try bool(v) })
    static let revVisibility = P("revision.visibility", "Show", .choice(RevisionVisibility.allCases.map(\.rawValue)), .graphics,
                                 get: { e, _ in .text(e.revisionData?.visibility.rawValue ?? "") },
                                 set: { e, v, _ in
                                     guard let r = RevisionVisibility(rawValue: text(v)) else { throw err("Unknown option.") }
                                     e.revisionData?.visibility = r
                                 })
    static let cloudRevision = P("revisionCloud.revision", "Revision", .elementRef(.revisions), .identity,
                                 get: { e, _ in .ref(e.revisionCloud?.revisionID) },
                                 set: { e, v, ctx in
                                     if let r = v.refValue, ctx.model[r]?.revisionData?.issued == true {
                                         throw err("That revision is issued; clouds can't be added to it.")
                                     }
                                     e.revisionCloud?.revisionID = v.refValue
                                 })

    // MARK: Annotations

    static let dimLocked = P("dimension.locked", "Locked", .bool, .constraints,
                             get: { e, _ in e.dimension.map { .bool($0.locked) } }, set: { e, v, _ in e.dimension?.locked = try bool(v) })
    static let dimEquality = P("dimension.equality", "Equality", .bool, .constraints,
                               get: { e, _ in e.dimension.map { .bool($0.equality) } }, set: { e, v, _ in e.dimension?.equality = try bool(v) })
    static let dimValue = P("dimension.value", "Value", .length, .dimensions,
                            get: { e, ctx in AnnotationGeometry.measure(e, ctx.model).first.map { .double($0) } }) // W2-ANNOT: in its view
    static let dimPrefix = P("dimension.prefix", "Prefix", .text, .text,
                             get: { e, _ in .text(e.dimension?.prefix ?? "") }, set: { e, v, _ in e.dimension?.prefix = text(v) })
    static let dimSuffix = P("dimension.suffix", "Suffix", .text, .text,
                             get: { e, _ in .text(e.dimension?.suffix ?? "") }, set: { e, v, _ in e.dimension?.suffix = text(v) })
    static let dimOverride = P("dimension.override", "Replace With Text", .text, .text,
                               get: { e, _ in .text(e.dimension?.textOverride ?? "") },
                               set: { e, v, _ in let s = text(v); e.dimension?.textOverride = s.isEmpty ? nil : s })
    static let textContent = P("text.content", "Text", .multilineText, .text,
                               get: { e, _ in .text(e.textNote?.text ?? "") }, set: { e, v, _ in e.textNote?.text = text(v) })
    static let textWidth = P("text.width", "Width", .length, .text,
                             get: { e, _ in e.textNote.map { .double($0.width) } }, set: { e, v, _ in e.textNote?.width = max(0, try finite(v, "Width")) })
    static let tagLeader = P("tag.leader", "Leader Line", .bool, .graphics,
                             get: { e, _ in e.tag.map { .bool($0.hasLeader) } }, set: { e, v, _ in e.tag?.hasLeader = try bool(v) })
    static let tagOrientation = P("tag.orientation", "Orientation", .choice(TagOrientation.allCases.map(\.rawValue)), .graphics,
                                  get: { e, _ in .text(e.tag?.orientation.rawValue ?? "") },
                                  set: { e, v, _ in
                                      guard let o = TagOrientation(rawValue: text(v)) else { throw err("Unknown orientation.") }
                                      e.tag?.orientation = o
                                  })
    static let spotValue = P("spot.elevation", "Elevation", .length, .dimensions, get: { e, _ in e.spot.map { .double($0.elevation) } })
    static let regionMasking = P("region.masking", "Masking", .bool, .graphics,
                                 get: { e, _ in e.filledRegion.map { .bool($0.isMasking) } }, set: { e, v, _ in e.filledRegion?.isMasking = try bool(v) })

    // MARK: Links

    static let linkOpacity = P("link.opacity", "Opacity", .percentage, .graphics,
                               get: { e, _ in e.link.map { .double($0.opacity) } },
                               set: { e, v, _ in
                                   let d = try finite(v, "Opacity")
                                   guard d >= 0.05, d <= 1 else { throw err("Opacity must be between 5% and 100%.") }
                                   e.link?.opacity = d
                               })
    static let linkBehind = P("link.drawBehind", "Draw Behind Model", .bool, .graphics,
                              get: { e, _ in e.link.map { .bool($0.drawBehindModel) } }, set: { e, v, _ in e.link?.drawBehindModel = try bool(v) })
    static let linkSource = P("link.source", "Source File", .text, .identity, get: { e, _ in .text(e.link?.sourcePath ?? "") })
    static let linkMode = P("link.mode", "Reference Type", .text, .identity, get: { e, _ in .text(e.link.map { $0.isLinked ? "Link" : "Import" } ?? "") })
    static let linkFormat = P("link.format", "Format", .text, .identity, get: { e, _ in .text(e.link?.format.rawValue ?? "") })
    static let linkElevation = P("link.elevationOffset", "Offset From Level", .length, .constraints,
                                 get: { e, _ in e.link.map { .double($0.elevationOffset) } },
                                 set: { e, v, _ in e.link?.elevationOffset = try finite(v, "Offset From Level") })

    // MARK: Materials

    static let materialClass = P("material.class", "Class", .choice(MaterialClass.allCases.map(\.rawValue)), .identity,
                                 get: { e, _ in .text(e.material?.materialClass.rawValue ?? "") },
                                 set: { e, v, _ in
                                     guard let c = MaterialClass(rawValue: text(v)) else { throw err("Unknown material class.") }
                                     e.material?.materialClass = c
                                 })
    static let materialColor = P("material.color", "Color", .text, .graphics, tooltip: "Hex color such as #C8B9A6.",
                                 get: { e, _ in .text(e.material?.color.hexString ?? "") },
                                 set: { e, v, _ in
                                     var s = text(v).trimmingCharacters(in: .whitespaces)
                                     if s.hasPrefix("#") { s.removeFirst() }
                                     guard s.count == 6, let n = UInt32(s, radix: 16) else { throw err("Use a hex color like #C8B9A6.") }
                                     e.material?.color = RGBColor(hex: n)
                                 })
    static let materialTransparency = P("material.transparency", "Transparency", .percentage, .graphics,
                                        get: { e, _ in e.material.map { .double($0.transparency) } },
                                        set: { e, v, _ in
                                            let d = try finite(v, "Transparency")
                                            guard d >= 0, d <= 1 else { throw err("Transparency must be 0–100%.") }
                                            e.material?.transparency = d
                                        })
    static func materialText(_ key: String, _ name: String, _ kp: any WritableKeyPath<MaterialData, String> & Sendable) -> P {
        P(key, name, .text, .identity, get: { e, _ in .text(e.material?[keyPath: kp] ?? "") }, set: { e, v, _ in e.material?[keyPath: kp] = text(v) })
    }
    static let materialCost = P("material.cost", "Cost", .currency, .identity,
                                get: { e, _ in e.material.map { .double($0.cost) } }, set: { e, v, _ in e.material?.cost = try finite(v, "Cost") })

    // MARK: Type parameters

    static func typeText(_ key: String, _ name: String, _ group: ParameterGroup = .identity) -> P {
        let id = ParameterID(key)
        return P(key, name, .text, group, get: { e, _ in .text(e.typeData?.params[id]?.textValue ?? "") },
                 set: { e, v, _ in let s = text(v); e.typeData?.params[id] = s.isEmpty ? nil : .text(s) })
    }
    static let typeMark = typeText("type.mark", "Type Mark")
    static let typeDescription = typeText("type.description", "Description")
    static let typeManufacturer = typeText("type.manufacturer", "Manufacturer")
    static let typeModel = typeText("type.model", "Model")
    static let typeComments = typeText("type.comments", "Type Comments")
    static let typeURL = P("type.url", "URL", .url, .identity,
                           get: { e, _ in .text(e.typeData?.params[ParameterID("type.url")]?.textValue ?? "") },
                           set: { e, v, _ in
                               let s = text(v)
                               if !s.isEmpty, URL(string: s) == nil { throw err("That is not a valid URL.") }
                               e.typeData?.params[ParameterID("type.url")] = s.isEmpty ? nil : .text(s)
                           })
    static let typeAssemblyCode = typeText("type.assemblyCode", "Assembly Code")
    static let typeKeynote = typeText("type.keynote", "Keynote")
    static let typeFireRating = typeText("type.fireRating", "Fire Rating")
    static let typeCost = P("type.cost", "Cost", .currency, .identity,
                            get: { e, _ in .double(e.typeData?.params[ParameterID("type.cost")]?.doubleValue ?? 0) },
                            set: { e, v, _ in e.typeData?.params[ParameterID("type.cost")] = .double(try finite(v, "Cost")) })
    static let typeFunction = P("type.function", "Function", .choice(["Exterior", "Interior", "Retaining", "Foundation", "Soffit", "Core-shaft"]), .construction,
                                get: { e, _ in .text(e.typeData?.params[ParameterID("type.function")]?.textValue ?? "Interior") },
                                set: { e, v, _ in e.typeData?.params[ParameterID("type.function")] = .text(text(v)) })
    static let assemblyThickness = P("type.width", "Width", .length, .construction,
                                     get: { e, _ in e.typeData?.assembly.map { .double($0.totalThickness) } })
    static let assemblyThicknessDefault = P("type.thickness", "Default Thickness", .length, .construction,
                                            get: { e, _ in e.typeData?.assembly.map { .double($0.totalThickness) } })
    static func typeLength(_ key: String, _ name: String, _ group: ParameterGroup = .dimensions, min: Double = Tolerance.length) -> P {
        let id = ParameterID(key)
        return P(key, name, .length, group, get: { e, _ in e.typeData?.params[id] },
                 set: { e, v, _ in
                     let d = try finite(v, name)
                     guard d >= min else { throw err("“\(name)” is too small.") }
                     e.typeData?.params[id] = .double(d)
                 })
    }
    static func typeInt(_ key: String, _ name: String, _ range: ClosedRange<Int>) -> P {
        let id = ParameterID(key)
        return P(key, name, .integer, .dimensions, get: { e, _ in e.typeData?.params[id] },
                 set: { e, v, _ in
                     guard let n = v.intValue, range.contains(n) else { throw err("“\(name)” must be between \(range.lowerBound) and \(range.upperBound).") }
                     e.typeData?.params[id] = .int(n)
                 })
    }
    static let stairMaxRiser = typeLength("stair.maxRiser", "Maximum Riser Height", .construction, min: 0.1)
    static let stairMinTread = typeLength("stair.minTread", "Minimum Tread Depth", .construction, min: 0.18)
    static let stairTreadThickness = typeLength("stair.treadThickness", "Tread Thickness", .construction, min: 0.01)
    static let stairWaist = typeLength("stair.waist", "Structural Depth", .construction, min: 0.05)
    static let railingHeight = typeLength("railing.height", "Railing Height", .construction, min: 0.3)
    static let railingBalusterSpacing = typeLength("railing.balusterSpacing", "Baluster Spacing", .construction, min: 0.05)
    static let railingBalusterSize = typeLength("railing.balusterSize", "Baluster Size", .construction, min: 0.005)
    static let railingRailSize = typeLength("railing.railSize", "Top Rail Size", .construction, min: 0.01)
    static let columnWidth = typeLength("column.width", "Width (b)")
    static let columnDepth = typeLength("column.depth", "Depth (h)")
    static let columnDiameter = typeLength("column.diameter", "Diameter")
    static let beamWidth = typeLength("beam.width", "Width (b)")
    static let beamDepth = typeLength("beam.depth", "Depth (h)")
    static let materialParam = P("type.material", "Material", .elementRef(.materials), .materials,
                                 get: { e, _ in e.typeData?.params[ParameterID("type.material")] ?? .ref(nil) },
                                 set: { e, v, ctx in
                                     if let r = v.refValue, ctx.model[r]?.material == nil { throw err("Not a material.") }
                                     e.typeData?.params[ParameterID("type.material")] = .ref(v.refValue)
                                 })

    // MARK: Catalog

    static let quantityLength = q("q.length", "Length", .length) { $0.length }
    static let quantityArea = q("q.area", "Area", .area) { $0.area }
    static let quantityVolume = q("q.volume", "Volume", .volume) { $0.volume }
    static let quantityPerimeter = q("q.perimeter", "Perimeter", .length) { $0.perimeter }
    static let quantityHeight = q("q.height", "Height", .length) { $0.height }
    static let quantityWidth = q("q.width", "Width", .length) { $0.width }
    static let quantityThickness = q("q.thickness", "Thickness", .length) { $0.thickness }
    static let quantityElevTop = q("q.elevationTop", "Elevation at Top", .length) { $0.elevationTop }
    static let quantityElevBottom = q("q.elevationBottom", "Elevation at Bottom", .length) { $0.elevationBottom }
    static let quantityUnbounded = q("q.unboundedHeight", "Unbounded Height", .length) { $0.height }
    static let quantityCount = q("q.count", "Count", .integer, .other) { _ in 1 }

    static func instance(for e: Element) -> [P] { baseInstance(for: e) + HostedProfileParameters.extra(for: e) + ReinforcementParameters.extra(for: e) } // W2-DWG, F34

    static func baseInstance(for e: Element) -> [P] {
        let identity = [mark, comments]
        let typed = [familyName, typeName, familyAndType]
        let phasing = [phaseCreated, phaseDemolished]
        let ifc = [ifcGUID, classificationCode, elementIDParam]
        switch e.data {
        case .wall where e.wall?.curtain != nil: // WP3
            return curtainWallInstanceParams()
        case .wall:
            return typed + [wallLocationLine, wallBaseConstraint, wallBaseOffset, wallBaseAttached, wallTopConstraint, wallUnconnectedHeight,
                            wallTopOffset, wallTopAttached, wallRoomBounding, wallStructural, wallSlant,
                            quantityLength, quantityArea, quantityVolume] + identity + phasing + ifc + [designOption] // BL-PROPS: wallBaseConstraint
        case .insert:
            return typed + [levelParam, sillHeight, headHeight, hostName, fromRoom, toRoom] + identity + phasing + ifc + [designOption]
        case .component:
            return typed + [levelParam, componentOffset, componentRotation, componentRoom] + identity + phasing + ifc + [designOption]
        case .column:
            return typed + [levelParam, columnBaseOffset, columnTopLevel, columnTopOffset, columnHeight, columnRotation, columnRoomBounding,
                            quantityVolume] + (e.column?.topLocation != nil ? F2Parameters.column : []) + identity + phasing + ifc // F2: Column Style of slanted columns
        case .beam:
            return typed + [levelParam, beamStartOffset, beamEndOffset, beamZJust, quantityLength, quantityVolume] + identity + phasing + ifc
        case .slab:
            return typed + [levelParam, slabOffset, slabRoomBounding, slabStructural, slabSlope, quantityPerimeter, quantityArea,
                            quantityVolume, quantityThickness, quantityElevTop, quantityElevBottom] + identity + phasing + ifc
        case .roof:
            return typed + [levelParam, roofBaseOffset] + (e.roof?.extrusion != nil ? roofExtrusionParameters : [roofSlope, roofFascia, roofGutter])
                + [quantityArea, quantityVolume, quantityThickness, quantityElevTop] + identity + phasing + ifc
        case .stair:
            return typed + [levelParam, stairBaseOffset, stairTopLevel, stairTopOffset, stairHeight] + F2Parameters.stair + [stairShape, stairTurnsLeft, // F2: Multistory Top Level
                            stairWidth, stairDesiredRisers, stairActualRisers, stairRiserHeight, stairTreadDepth] + identity + phasing + ifc
        case .railing:
            return typed + [levelParam, railingBaseOffset, quantityLength] + identity + phasing + ifc
        case .ramp:
            return typed + [levelParam] + rampInstanceParameters + [quantityLength, quantityArea, quantityVolume] + identity + phasing + ifc
        case .room:
            return [levelParam, roomUpperLimit, roomLimitOffset, roomBaseOffset, quantityArea, quantityPerimeter, quantityVolume,
                    quantityUnbounded, roomNumber, roomName, roomText("room.department", "Department"), roomText("room.occupancy", "Occupancy"),
                    roomText("room.occupant", "Occupant"), roomText("room.baseFinish", "Base Finish", .materials),
                    roomText("room.ceilingFinish", "Ceiling Finish", .materials), roomText("room.wallFinish", "Wall Finish", .materials),
                    roomText("room.floorFinish", "Floor Finish", .materials), comments] + phasing + ifc
        case .modelLine:
            return (e.category == .detailLines ? [lineStyleParam] : []) + [quantityLength, comments] // W2-ANNOT: line style
        case .topography:
            return [quantityArea, quantityElevTop, quantityElevBottom, mark, comments] + phasing + ifc
        case .level:
            return [name, levelElevation, levelComputation, levelStorey, levelStructural, ifcGUID, datumScopeBox]
        case .grid:
            return [name, gridBubbleStart, gridBubbleEnd, datumScopeBox]
        case .referencePlane:
            return [name, datumScopeBox]
        case .scopeBox: // WP6a
            return scopeBoxParameters
        case .view:
            var list: [P] = [viewKind, name, viewTitleOnSheet, viewTemplate, viewScale, viewDetail, viewStyle, viewDiscipline]
            if e.view?.kind.isPlan == true {
                list += [viewAssociatedLevel, viewUnderlay, viewCut, viewTop, viewBottom, viewDepth]
            }
            if e.view?.kind.isVerticalCut == true { list += [viewFarClip] }
            if e.view?.kind == .threeD { list += [viewSectionBox] }
            list += viewWP6aParameters(e) // WP6a: scope box, camera heights
            if e.view?.kind.isModelView == true { list += [viewCrop, viewCropVisible, viewAnnotationCrop, viewPhase, viewPhaseFilter] }
            list += colorFillViewParameters(e)
            return list + [viewSheetNumber, viewSheetName, viewDetailNumber] + viewReferenceParameters(e) // BL-BROWSER
        case .sheet:
            return [sheetNumber, sheetName, sheetText("sheet.issueDate", "Sheet Issue Date", \.issueDate),
                    sheetText("sheet.drawnBy", "Drawn By", \.drawnBy), sheetText("sheet.checkedBy", "Checked By", \.checkedBy),
                    sheetText("sheet.designedBy", "Designed By", \.designedBy), sheetText("sheet.approvedBy", "Approved By", \.approvedBy),
                    sheetPaper, sheetInList, sheetCurrentRevision, sheetCurrentRevisionDate, sheetCurrentRevisionDescription] + sheetBrowserParameters // BL-BROWSER
        case .viewport:
            return [viewportDetailNumber, viewportShowTitle]
        case .schedule:
            return [name]
        case .revision:
            return [revSequence, revNumber, revText("revision.date", "Revision Date", \.date), revText("revision.description", "Revision Description", \.description),
                    revText("revision.issuedTo", "Issued To", \.issuedTo), revText("revision.issuedBy", "Issued By", \.issuedBy), revIssued, revVisibility]
        case .revisionCloud:
            return [cloudRevision, comments]
        case .dimension:
            return [dimValue, dimLocked, dimEquality, dimPrefix, dimSuffix, dimOverride] + dimensionStyleParameters(e) + annotDimensionParams(e) // W2-ANNOT
        case .textNote:
            return [textContent, textWidth] + annotTextInstanceParams() // W2-ANNOT
        case .tag:
            return [tagLeader, tagOrientation] + annotTagParams(e) // W2-ANNOT
        case .spot:
            return [spotValue]
        case .filledRegion:
            return [regionMasking, quantityArea, comments]
        case .link:
            return [linkFormat, linkMode, linkSource, linkElevation, linkOpacity, linkBehind]
        case .material:
            return [name, materialClass, materialColor, materialTransparency] + materialHatchParams + [materialText("material.description", "Description", \.description), // W4-HATCH
                    materialText("material.manufacturer", "Manufacturer", \.manufacturer), materialText("material.model", "Model", \.model),
                    materialCost, materialText("material.keynote", "Keynote", \.keynote), materialText("material.mark", "Mark", \.mark)]
        case .phase, .designOption, .viewTemplate, .filter, .lineStyle, .fillPattern, .areaScheme, .family:
            return [name]
        case .group:
            return [name, comments]
        case .detailComponent:
            return typed + annotDetailParams(e) + [comments] // W2-ANNOT
        case .referenceGeometry:
            return [ifcGUID, comments]
        case .modelText: // F1
            return ModelTextParameters.instance + identity + phasing + ifc
        case .wallReveal: // F1
            return WallRevealParameters.instance + identity + phasing
        case .opening: // WP3
            return openingInstanceParams(e)
        case .linkedModel, .pointCloud, .markup, .decal: // F67
            return F67Parameters.instance(for: e)
        case .mass: // F5
            return MassParameters.instance + [name] + identity + phasing + ifc
        case .furniturePanel, .furnitureShelf, .furnitureLeg, .furnitureRail, .furnitureEdgeProfile, .furnitureForm: // FM4
            return FurniturePartParameters.instance(for: e) + FurnitureJointParameters.part(e) // FM6: Cut Size
        case .furnitureJoint: // FM6
            return FurnitureJointParameters.instance(for: e)
        default:
            return []
        }
    }

    static func type(for td: TypeData) -> [P] {
        let identity = [typeMark, typeDescription, typeManufacturer, typeModel, typeURL, typeCost, typeAssemblyCode, typeKeynote, typeComments]
        switch td.instanceCategory {
        case .walls where td.curtain != nil: return curtainTypeParams + [typeFunction, typeFireRating] + identity // WP3
        case .curtainPanels: return [curtainPanelKindParam, curtainPanelThicknessParam, materialParam] + identity // WP3
        case .walls: return [assemblyThickness, typeFunction, typeFireRating] + typeCoarseFillParams + identity // W4-HATCH
        case .floors, .ceilings, .roofs, .buildingPads: return [assemblyThicknessDefault, typeFunction] + typeCoarseFillParams + identity // W4-HATCH
        case .filledRegions: return regionTypeParams + identity // W4-HATCH
        case .topography: return [assemblyThicknessDefault] + identity // BL-SITE: toposolid types
        case .stairs: return [stairMaxRiser, stairMinTread, stairTreadThickness, stairWaist, materialParam] + identity
        case .railings: return [railingHeight, railingBalusterSpacing, railingBalusterSize, railingRailSize, materialParam] + identity
        case .ramps: return rampTypeParameters + [materialParam] + identity
        case .doors, .windows: return [typeFireRating] + identity
        case .textNotes: return annotTextTypeParams // W2-ANNOT
        case .dimensions: return annotDimensionTypeParams // W2-ANNOT
        case .columns, .structuralColumns:
            return td.familyID == nil ? [columnWidth, columnDepth, columnDiameter, materialParam] + identity : identity
        case .structuralFraming:
            return td.familyID == nil ? [beamWidth, beamDepth, materialParam] + identity : identity
        case .structuralRebar, .fabricReinforcement: return ReinforcementParameters.typeParameters(td) + [materialParam] + identity // F34
        case let c where c.isFurniturePart: return FurniturePartParameters.type(for: td) + identity // FM4
        default: return identity
        }
    }

    static let typeParameterIDs: Set<ParameterID> = {
        var s: Set<ParameterID> = []
        for c in Category.allCases {
            for p in type(for: TypeData(instanceCategory: c, familyName: "")) { s.insert(p.id) }
        }
        for td in wp3TypeProbes { for p in type(for: td) { s.insert(p.id) } } // WP3
        for p in FurniturePartParameters.allType { s.insert(p.id) } // FM4: tops and grooves
        return s
    }()
    static func isTypeParameter(_ id: ParameterID) -> Bool { typeParameterIDs.contains(id) }

    static let byID: [ParameterID: P] = {
        var d: [ParameterID: P] = [levelParam.id: levelParam] // BL-PROPS: generic "Level" (walls call it Base Constraint)
        let probes: [ElementData] = [
            .wall(WallData(location: .line(Segment2(.zero, .unitX)))), .insert(InsertData(location: .zero)), .component(ComponentData(location: .zero)),
            .column(ColumnData(location: .zero)), .beam(BeamData(curve: .line(Segment2(.zero, .unitX)))), .slab(SlabData(boundary: Sketch(loops: []))),
            .roof(RoofData(footprint: Sketch(loops: []), edgeSlopes: [])), .stair(StairData(origin: .zero, direction: 0)), .railing(RailingData(path: [])),
            .roof(extrusionProbe), .ramp(RampData(path: [])),
            .room(RoomData(point: .zero, number: "")), .modelLine(ModelLineData(curve: .line(Segment2(.zero, .unitX)))), .topography(TopographyData(points: [])),
            .level(LevelData(elevation: 0)), .grid(GridData(curve: .line(Segment2(.zero, .unitX)))), .view(ViewData(kind: .floorPlan)),
            .view(ViewData(kind: .section)), .view(ViewData(kind: .threeD)), .sheet(SheetData(number: "")), .viewport(ViewportData(viewID: ElementID(0), center: .zero, detailNumber: "")),
            .revision(RevisionData(sequence: 0, date: "", description: "")), .revisionCloud(RevisionCloudData(outline: Polygon2([]), revisionID: nil)),
            .dimension(DimensionData(kind: .aligned, references: [], linePoint: .zero)), .textNote(TextNoteData(position: .zero, text: "")),
            .tag(TagData(taggedID: ElementID(0), head: .zero)), .spot(SpotData(kind: .elevation, point: .zero, elevation: 0, leaderHead: .zero)),
            .filledRegion(FilledRegionData(boundary: Sketch(loops: []))),
            .link(LinkData(format: .dxf, isLinked: false, sourcePath: "", sourceName: "", contentKey: "")),
            .material(MaterialData(materialClass: .generic, color: .white)),
        ] + wp6aProbes + F67Parameters.probes // F67
            + [.topography(TopographyData(points: [], solid: ToposolidData())), .topography(TopographyData(points: [], boundary: [], solid: ToposolidData()))] // BL-SITE
        for data in probes {
            let e = Element(id: ElementID(0), category: .genericModels, data: data)
            for p in instance(for: e) where d[p.id] == nil { d[p.id] = p }
        }
        for c in Category.allCases {
            for fam in [nil, ElementID(1)] as [ElementID?] {
                for p in type(for: TypeData(instanceCategory: c, familyID: fam, familyName: "")) where d[p.id] == nil { d[p.id] = p }
            }
        }
        for p in [quantityCount, quantityHeight, quantityWidth] where d[p.id] == nil { d[p.id] = p }
        for td in wp3TypeProbes { for p in type(for: td) where d[p.id] == nil { d[p.id] = p } } // WP3
        for e in wp3InstanceProbes { for p in instance(for: e) where d[p.id] == nil { d[p.id] = p } } // WP3
        for e in annotProbeElements { for p in instance(for: e) where d[p.id] == nil { d[p.id] = p } } // W2-ANNOT
        for e in ReinforcementParameters.probes { for p in instance(for: e) where d[p.id] == nil { d[p.id] = p } } // F34
        for p in F1Parameters.all where d[p.id] == nil { d[p.id] = p } // F1
        for p in MassParameters.instance where d[p.id] == nil { d[p.id] = p } // F5
        for p in F2Parameters.all where d[p.id] == nil { d[p.id] = p } // F2
        for p in FurniturePartParameters.allInstance + FurniturePartParameters.allType where d[p.id] == nil { d[p.id] = p } // FM4
        for p in FurnitureJointParameters.all where d[p.id] == nil { d[p.id] = p } // FM6
        return d
    }()

    /// Display order of built-in parameters (declaration order across the catalogs).
    static let order: [ParameterID: Int] = {
        var o: [ParameterID: Int] = [:]
        var i = 0
        let probes: [ElementData] = [
            .wall(WallData(location: .line(Segment2(.zero, .unitX)))), .insert(InsertData(location: .zero)), .component(ComponentData(location: .zero)),
            .column(ColumnData(location: .zero)), .slab(SlabData(boundary: Sketch(loops: []))), .roof(RoofData(footprint: Sketch(loops: []), edgeSlopes: [])),
            .stair(StairData(origin: .zero, direction: 0)), .roof(extrusionProbe), .ramp(RampData(path: [])), .room(RoomData(point: .zero, number: "")), .view(ViewData(kind: .floorPlan)),
            .view(ViewData(kind: .threeD)), .sheet(SheetData(number: "")), .revision(RevisionData(sequence: 0, date: "", description: "")),
            .material(MaterialData(materialClass: .generic, color: .white)),
        ]
        for data in probes {
            for p in instance(for: Element(id: ElementID(0), category: .genericModels, data: data)) where o[p.id] == nil { o[p.id] = i; i += 1 }
        }
        for c in Category.allCases {
            for p in type(for: TypeData(instanceCategory: c, familyName: "")) where o[p.id] == nil { o[p.id] = i; i += 1 }
        }
        for e in wp3InstanceProbes { for p in instance(for: e) where o[p.id] == nil { o[p.id] = i; i += 1 } } // WP3
        for td in wp3TypeProbes { for p in type(for: td) where o[p.id] == nil { o[p.id] = i; i += 1 } } // WP3
        for e in annotProbeElements { for p in instance(for: e) where o[p.id] == nil { o[p.id] = i; i += 1 } } // W2-ANNOT
        for e in ReinforcementParameters.probes { for p in instance(for: e) where o[p.id] == nil { o[p.id] = i; i += 1 } } // F34
        for p in F1Parameters.all where o[p.id] == nil { o[p.id] = i; i += 1 } // F1
        for p in F2Parameters.all where o[p.id] == nil { o[p.id] = i; i += 1 } // F2
        for p in FurniturePartParameters.allInstance + FurniturePartParameters.allType where o[p.id] == nil { o[p.id] = i; i += 1 } // FM4
        for p in FurnitureJointParameters.all where o[p.id] == nil { o[p.id] = i; i += 1 } // FM6
        return o
    }()
}

// MARK: - WP6a: scope boxes and cameras

extension BuiltInCatalog {
    /// Probe elements so `byID` knows the WP6a parameters.
    static var wp6aProbes: [ElementData] {
        var cam = ViewData(kind: .threeD)
        cam.camera = Camera3D(eye: .zero, target: .unitX, isPerspective: true)
        cam.walkthrough = WalkthroughData(path: [.zero, .unitX]) // F810: walkthrough frames
        return [.referencePlane(ReferencePlaneData(line: Segment2(.zero, .unitX))), .view(cam),
                .scopeBox(ScopeBoxData(center: .zero, halfSize: Vec2(1, 1), bottomElevation: 0, topElevation: 1))]
    }

    private static func scopeBoxRef(_ v: ParamValue, _ ctx: ParameterContext) throws(ParameterError) -> ElementID? {
        guard let id = v.refValue else { return nil }
        guard ctx.model[id]?.scopeBox != nil else { throw ParameterError("The chosen element is not a scope box.") }
        return id
    }

    static let datumScopeBox = P("datum.scopeBox", "Scope Box", .elementRef(.scopeBoxes), .extents,
                                 tooltip: "Limits the datum to the scope box: it appears only in views that intersect the box, trimmed to it.",
                                 get: { e, _ in .ref(e.datumScopeBoxID) },
                                 set: { e, v, ctx in
                                     let id = try scopeBoxRef(v, ctx)
                                     switch e.data {
                                     case .level(var l): l.scopeBoxID = id; e.data = .level(l)
                                     case .grid(var g): g.scopeBoxID = id; e.data = .grid(g)
                                     case .referencePlane(var r): r.scopeBoxID = id; e.data = .referencePlane(r)
                                     default: throw ParameterError("Only levels, grids and reference planes use scope boxes.")
                                     }
                                 })

    static let viewScopeBox = P("view.scopeBox", "Scope Box", .elementRef(.scopeBoxes), .extents,
                                tooltip: "Crops the plan to the scope box and keeps the crop following it.",
                                get: { e, _ in e.view.map { .ref($0.scopeBoxID) } },
                                set: { e, v, ctx in
                                    let id = try scopeBoxRef(v, ctx)
                                    guard var d = e.view else { return }
                                    // Removing the box keeps its last extent as an ordinary crop.
                                    if let old = ScopeBoxes.box(d.scopeBoxID, ctx.model) { d.cropRegion = old.bounds }
                                    d.scopeBoxID = id
                                    if let b = ScopeBoxes.box(id, ctx.model) { d.cropRegion = b.bounds; d.cropActive = true }
                                    e.view = d
                                })

    private static func scopeLength(_ key: String, _ name: String, _ group: ParameterGroup, _ get: @escaping @Sendable (ScopeBoxData) -> Double,
                                    _ set: @escaping @Sendable (inout ScopeBoxData, Double) throws(ParameterError) -> Void) -> P {
        P(key, name, .length, group, get: { e, _ in e.scopeBox.map { .double(get($0)) } },
          set: { e, v, _ in
              guard var b = e.scopeBox, let d = v.doubleValue, d.isFinite else { throw ParameterError("“\(name)” needs a length.") }
              try set(&b, d)
              e.scopeBox = b
          })
    }

    static let scopeBoxParameters: [P] = [
        name,
        scopeLength("scopeBox.width", "Width", .dimensions, { $0.width }) { b, d throws(ParameterError) in
            guard d > Tolerance.shortCurve else { throw ParameterError("The width must be greater than zero.") }
            b.halfSize.x = d / 2
        },
        scopeLength("scopeBox.depth", "Depth", .dimensions, { $0.depth }) { b, d throws(ParameterError) in
            guard d > Tolerance.shortCurve else { throw ParameterError("The depth must be greater than zero.") }
            b.halfSize.y = d / 2
        },
        scopeLength("scopeBox.bottom", "Bottom Elevation", .extents, { $0.bottomElevation }) { b, d throws(ParameterError) in
            guard d < b.topElevation else { throw ParameterError("The bottom must be below the top.") }
            b.bottomElevation = d
        },
        scopeLength("scopeBox.top", "Top Elevation", .extents, { $0.topElevation }) { b, d throws(ParameterError) in
            guard d > b.bottomElevation else { throw ParameterError("The top must be above the bottom.") }
            b.topElevation = d
        },
    ]

    private static func cameraHeight(_ key: String, _ name: String, target: Bool) -> P {
        P(key, name, .length, .extents, tooltip: "Height above the level the camera was placed from.",
          get: { e, ctx in
              guard let c = e.view?.camera, c.isPerspective else { return nil }
              return .double((target ? c.target.z : c.eye.z) - ctx.model.elevation(ofLevel: e.levelID))
          },
          set: { e, v, ctx in
              guard var d = e.view, var c = d.camera, c.isPerspective else { throw ParameterError("Only perspective views have a camera height.") }
              guard let h = v.doubleValue, h.isFinite else { throw ParameterError("“\(name)” needs a length.") }
              let z = ctx.model.elevation(ofLevel: e.levelID) + h
              if target { c.target = Vec3(c.target.x, c.target.y, z) } else { c.eye = Vec3(c.eye.x, c.eye.y, z) }
              guard (c.target - c.eye).length > Tolerance.shortCurve else { throw ParameterError("The eye and target can't coincide.") }
              d.camera = c
              e.view = d
          })
    }
    static let cameraEyeHeight = cameraHeight("view.eyeHeight", "Eye Height", target: false)
    static let cameraTargetHeight = cameraHeight("view.targetHeight", "Target Height", target: true)

    static func viewWP6aParameters(_ e: Element) -> [P] {
        guard let d = e.view else { return [] }
        if d.kind.isPlan { return [viewScopeBox] }
        if let camera = cameraViewParameters(e) { return camera } // W2-CAM
        if d.kind == .threeD, d.camera?.isPerspective == true { return [cameraEyeHeight, cameraTargetHeight] }
        return []
    }
}

// MARK: - WP6b: colour fill and area plans

extension BuiltInCatalog {
    static let viewColorScheme = P("view.colorScheme", "Color Scheme", .elementRef(.colorSchemes), .graphics,
                                   tooltip: "Colours rooms (areas in area plans) by a parameter value or range.",
                                   get: { e, _ in .ref(e.view?.colorSchemeID) },
                                   set: { e, v, ctx in
                                       if let id = v.refValue {
                                           guard let s = ctx.model[id]?.colorScheme else { throw err("Not a color scheme.") }
                                           guard let vd = e.view, s.category == ColorFill.category(for: vd), vd.kind.isPlan || s.category == .rooms else {
                                               throw err("This scheme colours \(s.category.displayName.lowercased()); choose one for \(e.view.map { ColorFill.category(for: $0).displayName.lowercased() } ?? "this view").")
                                           }
                                       }
                                       e.view?.colorSchemeID = v.refValue
                                   })
    static let viewAreaScheme = P("view.areaScheme", "Area Scheme", .elementRef(.areaSchemes), .identity,
                                  get: { e, _ in .ref(e.view?.areaSchemeID) })

    static let dimChainStyle = P("dimension.chainStyle", "Dimension String Type", .choice(DimensionChainStyle.allCases.map(\.rawValue)), .graphics,
                                 get: { e, _ in .text((e.dimension?.chainStyle ?? .continuous).rawValue) },
                                 set: { e, v, _ in
                                     guard let c = DimensionChainStyle(rawValue: text(v)) else { throw err("Unknown dimension string type.") }
                                     e.dimension?.chainStyle = c == .continuous ? nil : c
                                 })

    /// Baseline/ordinate layout for linear and aligned dimensions.
    static func dimensionStyleParameters(_ e: Element) -> [P] {
        guard let k = e.dimension?.kind, k == .aligned || k == .linear else { return [] }
        return [dimChainStyle]
    }

    /// Colour scheme (plans and sections) and area scheme (area plans) view parameters.
    static func colorFillViewParameters(_ e: Element) -> [P] {
        guard let k = e.view?.kind else { return [] }
        var list: [P] = []
        if k == .areaPlan { list.append(viewAreaScheme) }
        if k.isPlan || k == .section || k == .detail { list.append(viewColorScheme) }
        return list
    }
}
// MARK: - WP4: ramps and extruded roofs

extension BuiltInCatalog {
    private static func wp4Number(_ v: ParamValue, _ name: String) throws(ParameterError) -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw ParameterError("“\(name)” needs a number.") }
        return d
    }
    private static func wp4Level(_ v: ParamValue, _ ctx: ParameterContext) throws(ParameterError) -> ElementID? {
        guard let id = v.refValue else { return nil }
        guard ctx.model[id]?.level != nil else { throw ParameterError("The chosen element is not a level.") }
        return id
    }

    static let extrusionProbe: RoofData = {
        var r = RoofData(footprint: Sketch(loops: []), edgeSlopes: [])
        r.extrusion = RoofExtrusion(origin: .zero, direction: .unitX, profile: [], start: 0, end: 1)
        return r
    }()

    static let rampBaseOffset = P("ramp.baseOffset", "Base Offset", .length, .constraints,
                                  get: { e, _ in e.ramp.map { .double($0.baseOffset) } },
                                  set: { e, v, _ in e.ramp?.baseOffset = try wp4Number(v, "Base Offset") })
    static let rampTopLevel = P("ramp.topLevel", "Top Level", .elementRef(.levels), .constraints,
                                get: { e, _ in .ref(e.ramp?.topLevelID) },
                                set: { e, v, ctx in e.ramp?.topLevelID = try wp4Level(v, ctx) })
    static let rampTopOffset = P("ramp.topOffset", "Top Offset", .length, .constraints,
                                 get: { e, _ in e.ramp.map { .double($0.topOffset) } },
                                 set: { e, v, _ in e.ramp?.topOffset = try wp4Number(v, "Top Offset") })
    static let rampHeight = P("ramp.height", "Unconnected Height", .length, .constraints,
                              get: { e, _ in e.ramp.map { .double($0.unconnectedHeight) } },
                              set: { e, v, _ in
                                  let h = try wp4Number(v, "Unconnected Height")
                                  guard h > 0.005 else { throw ParameterError("“Unconnected Height” must be greater than zero.") }
                                  e.ramp?.unconnectedHeight = h
                              },
                              locked: { e, _ in e.ramp?.topLevelID != nil ? "The height comes from the Top Level." : nil })
    static let rampWidth = P("ramp.width", "Width", .length, .dimensions,
                             get: { e, _ in e.ramp.map { .double($0.width) } },
                             set: { e, v, _ in
                                 let w = try wp4Number(v, "Width")
                                 guard w >= RampGeometry.minimumWidth else { throw ParameterError("A ramp must be at least 600 mm wide.") }
                                 e.ramp?.width = w
                             })
    static let rampActualSlope = P("ramp.actualSlope", "Actual Slope", .slope, .dimensions, tooltip: "Rise over the horizontal length of the sloped runs.",
                                   get: { e, ctx in RampGeometry.layout(e, ctx.model).map { .double($0.slope) } })
    static let rampRequiredLength = P("ramp.requiredLength", "Required Run Length", .length, .dimensions,
                                      tooltip: "Sloped run needed to reach the top at the type's maximum slope.",
                                      get: { e, ctx in RampGeometry.layout(e, ctx.model).map { .double($0.requiredLength) } })
    static let rampInstanceParameters: [P] = [rampBaseOffset, rampTopLevel, rampTopOffset, rampHeight, rampWidth, rampActualSlope, rampRequiredLength]

    static let rampMaxSlope = P("ramp.maxSlope", "Maximum Slope", .slope, .construction, tooltip: "Steepest allowed slope (rise/run). Steeper ramps are reported in Model Health.",
                                get: { e, _ in e.typeData?.params[RampGeometry.maxSlopeParam] ?? .double(RampGeometry.defaultMaxSlope) },
                                set: { e, v, _ in
                                    let s = try wp4Number(v, "Maximum Slope")
                                    guard s > 0.001, s <= 1 else { throw ParameterError("The maximum slope must be between 0.001 and 1 (rise/run).") }
                                    e.typeData?.params[RampGeometry.maxSlopeParam] = .double(s)
                                })
    static let rampMaxRun = typeLength("ramp.maxRunLength", "Maximum Incline Length", .construction, min: 1)
    static let rampLanding = typeLength("ramp.landingLength", "Landing Length", .construction, min: 0.3)
    static let rampThickness = typeLength("ramp.thickness", "Thickness", .construction, min: 0.02)
    static let rampShape = P("ramp.shape", "Shape", .choice(RampShape.allCases.map(\.rawValue)), .construction,
                             get: { e, _ in e.typeData?.params[RampGeometry.shapeParam] ?? .text(RampShape.solid.rawValue) },
                             set: { e, v, _ in
                                 guard let s = RampShape(rawValue: v.textValue ?? "") else { throw ParameterError("Choose Solid or Thin.") }
                                 e.typeData?.params[RampGeometry.shapeParam] = .text(s.rawValue)
                             })
    static let rampTypeParameters: [P] = [rampShape, rampThickness, rampMaxSlope, rampMaxRun, rampLanding]

    static let roofExtrusionStart = P("roof.extrusionStart", "Extrusion Start", .length, .constraints,
                                      tooltip: "Start of the extrusion, measured from the work plane.",
                                      get: { e, _ in e.roof?.extrusion.map { .double($0.start) } },
                                      set: { e, v, _ in
                                          let d = try wp4Number(v, "Extrusion Start")
                                          guard var x = e.roof?.extrusion else { return }
                                          guard abs(x.end - d) > 0.01 else { throw ParameterError("Extrusion Start and End must differ.") }
                                          x.start = d; e.roof?.extrusion = x
                                      })
    static let roofExtrusionEnd = P("roof.extrusionEnd", "Extrusion End", .length, .constraints,
                                    tooltip: "End of the extrusion, measured from the work plane.",
                                    get: { e, _ in e.roof?.extrusion.map { .double($0.end) } },
                                    set: { e, v, _ in
                                        let d = try wp4Number(v, "Extrusion End")
                                        guard var x = e.roof?.extrusion else { return }
                                        guard abs(x.start - d) > 0.01 else { throw ParameterError("Extrusion Start and End must differ.") }
                                        x.end = d; e.roof?.extrusion = x
                                    })
    static let roofExtrusionParameters: [P] = [roofExtrusionStart, roofExtrusionEnd]
}

