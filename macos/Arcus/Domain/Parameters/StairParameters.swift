import Foundation
import ArcusGeometry

/// STAIR: Revit-style Properties and Type Properties of stairs, their run, landing and support types, and the stair
/// railings' placement.
enum StairParameters {
    typealias P = BuiltInParameter

    static func err(_ s: String) -> ParameterError { ParameterError(s) }
    static func number(_ v: ParamValue, _ name: String) throws(ParameterError) -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw err("“\(name)” needs a number.") }
        return d
    }
    static func positive(_ v: ParamValue, _ name: String, min: Double = Tolerance.length) throws(ParameterError) -> Double {
        let d = try number(v, name)
        guard d >= min else { throw err("“\(name)” is too small.") }
        return d
    }
    static func flag(_ v: ParamValue) throws(ParameterError) -> Bool {
        guard let b = v.boolValue else { throw err("Type Yes or No.") }
        return b
    }
    static func text(_ v: ParamValue) -> String { v.textValue ?? v.description }
    static func level(_ v: ParamValue, _ ctx: ParameterContext, allowNone: Bool) throws(ParameterError) -> ElementID? {
        guard let id = v.refValue else {
            if allowNone { return nil }
            throw err("A level is required.")
        }
        guard ctx.model[id]?.level != nil else { throw err("The chosen element is not a level.") }
        return id
    }
    static func layout(_ e: Element, _ ctx: ParameterContext) -> StairLayout? { StairGeometry.layout(e, ctx.model) }

    // MARK: Instance: Constraints

    static let baseLevel = P("stair.baseLevel", "Base Level", .elementRef(.levels), .constraints,
                             get: { e, _ in .ref(e.levelID) },
                             set: { e, v, ctx in e.levelID = try level(v, ctx, allowNone: false) })
    static let baseOffset = P("stair.baseOffset", "Base Offset", .length, .constraints,
                              get: { e, _ in e.stair.map { .double($0.baseOffset) } },
                              set: { e, v, _ in e.stair?.baseOffset = try number(v, "Base Offset") })
    static let topLevel = P("stair.topLevel", "Top Level", .elementRef(.levels), .constraints,
                            get: { e, _ in .ref(e.stair?.topLevelID) },
                            set: { e, v, ctx in e.stair?.topLevelID = try level(v, ctx, allowNone: true) })
    static let topOffset = P("stair.topOffset", "Top Offset", .length, .constraints,
                             get: { e, _ in e.stair.map { .double($0.topOffset) } },
                             set: { e, v, _ in e.stair?.topOffset = try number(v, "Top Offset") })
    static let height = P("stair.height", "Desired Stair Height", .length, .constraints,
                          get: { e, ctx in layout(e, ctx).map { .double($0.topZ - $0.baseZ) } },
                          set: { e, v, _ in e.stair?.unconnectedHeight = try positive(v, "Desired Stair Height", min: 0.1) },
                          locked: { e, _ in e.stair?.topLevelID != nil ? "The height comes from the Top Level." : nil })

    // MARK: Instance: Graphics

    /// The Graphics switches and texts of a stair, by parameter key.
    static func graphicsText(_ s: StairData, _ key: String) -> String? { key == "stair.upText" ? s.upText : s.downText }
    static func setGraphicsText(_ s: inout StairData, _ key: String, _ v: String) { if key == "stair.upText" { s.upText = v } else { s.downText = v } }
    static func graphicsFlag(_ s: StairData, _ key: String) -> Bool? {
        switch key {
        case "stair.upLabel": s.upLabel
        case "stair.upArrow": s.upArrow
        case "stair.downLabel": s.downLabel
        case "stair.downArrow": s.downArrow
        default: s.upArrowInAllViews
        }
    }
    static func setGraphicsFlag(_ s: inout StairData, _ key: String, _ v: Bool) {
        switch key {
        case "stair.upLabel": s.upLabel = v
        case "stair.upArrow": s.upArrow = v
        case "stair.downLabel": s.downLabel = v
        case "stair.downArrow": s.downArrow = v
        default: s.upArrowInAllViews = v
        }
    }
    static func label(_ key: String, _ name: String, _ fallback: String) -> P {
        P(key, name, .text, .graphics,
          get: { e, _ in e.stair.map { .text(graphicsText($0, key) ?? fallback) } },
          set: { e, v, _ in
              guard var s = e.stair else { return }
              setGraphicsText(&s, key, text(v))
              e.stair = s
          })
    }
    static func toggle(_ key: String, _ name: String, _ fallback: Bool, tooltip: String = "") -> P {
        P(key, name, .bool, .graphics, tooltip: tooltip,
          get: { e, _ in e.stair.map { .bool(graphicsFlag($0, key) ?? fallback) } },
          set: { e, v, _ in
              guard var s = e.stair else { return }
              setGraphicsFlag(&s, key, try flag(v))
              e.stair = s
          })
    }
    static let upText = label("stair.upText", "Up Text", "UP")
    static let downText = label("stair.downText", "Down Text", "DN")
    static let upLabel = toggle("stair.upLabel", "Up Label", true)
    static let upArrow = toggle("stair.upArrow", "Up Arrow", true)
    static let downLabel = toggle("stair.downLabel", "Down Label", true)
    static let downArrow = toggle("stair.downArrow", "Down Arrow", true)
    static let upArrowAllViews = toggle("stair.upArrowAllViews", "Show Up Arrow in All Views", false,
                                        tooltip: "Shows the up arrow also on the plan of the level the stair arrives at.")

    // MARK: Instance: Dimensions

    static let desiredRisers = P("stair.desiredRisers", "Desired Number of Risers", .integer, .dimensions,
                                 tooltip: "The risers the stair needs to reach its top; the runs keep the risers they were drawn with.",
                                 get: { e, ctx in layout(e, ctx).map { .int($0.desiredRiserCount) } ?? e.stair?.desiredRiserCount.map { .int($0) } },
                                 set: { e, v, _ in
                                     guard let n = v.intValue, StairGeometry.riserRange.contains(n) else {
                                         throw err("Risers must be between \(StairGeometry.riserRange.lowerBound) and \(StairGeometry.riserRange.upperBound).")
                                     }
                                     e.stair?.desiredRiserCount = n
                                 })
    static let actualRisers = P("stair.actualRisers", "Actual Number of Risers", .integer, .dimensions,
                                get: { e, ctx in layout(e, ctx).map { .int($0.riserCount) } })
    static let actualRiserHeight = P("stair.actualRiserHeight", "Actual Riser Height", .length, .dimensions,
                                     get: { e, ctx in layout(e, ctx).map { .double($0.riserHeight) } })
    static let actualTreadDepth = P("stair.actualTreadDepth", "Actual Tread Depth", .length, .dimensions,
                                    get: { e, ctx in layout(e, ctx).map { .double($0.treadDepth) } },
                                    set: { e, v, _ in e.stair?.treadDepth = try positive(v, "Actual Tread Depth", min: 0.1) })
    static let treadStart = P("stair.treadNumberStart", "Tread/Riser Start Number", .integer, .dimensions,
                              get: { e, _ in e.stair.map { .int($0.treadNumberStart ?? 1) } },
                              set: { e, v, _ in
                                  guard let n = v.intValue, n >= 0 else { throw err("The start number must be 0 or more.") }
                                  e.stair?.treadNumberStart = n
                              })
    static let runWidth = P("stair.width", "Actual Run Width", .length, .dimensions,
                            tooltip: "The clear width of the runs (between their supports).",
                            get: { e, _ in e.stair.map { .double($0.runs?.first?.width ?? $0.width) } },
                            set: { e, v, _ in
                                let w = try positive(v, "Actual Run Width")
                                guard w >= 0.3 else { throw err("A stair run must be at least 300 mm wide.") }
                                guard var s = e.stair else { return }
                                s.width = w
                                s.runs = s.runs?.map { var r = $0; r.width = w; return r }
                                e.stair = s
                            })

    // MARK: Instance: Construction

    static let beginWithRiser = P("stair.beginWithRiser", "Begin with Riser", .bool, .construction,
                                  tooltip: "Off: the stair starts with a tread instead of a riser.",
                                  get: { e, _ in e.stair.map { .bool($0.beginWithRiser ?? true) } },
                                  set: { e, v, _ in e.stair?.beginWithRiser = try flag(v) })
    static let endWithRiser = P("stair.endWithRiser", "End with Riser", .bool, .construction,
                                tooltip: "Off: the stair ends with a tread at the top level instead of a riser.",
                                get: { e, _ in e.stair.map { .bool($0.endWithRiser ?? true) } },
                                set: { e, v, _ in e.stair?.endWithRiser = try flag(v) })
    static let runCount = P("stair.runCount", "Runs", .integer, .construction,
                            get: { e, ctx in layout(e, ctx).map { .int($0.runs.count) } })
    // Older (shape-only) stairs keep their shape and turn until they are edited.
    static let shape = P("stair.shape", "Shape", .choice(StairShape.allCases.map(\.rawValue)), .construction,
                         get: { e, _ in .text(e.stair?.shape.rawValue ?? "") },
                         set: { e, v, _ in
                             guard let s = StairShape(rawValue: text(v)) else { throw err("Unknown stair shape.") }
                             e.stair?.shape = s
                         },
                         locked: { e, _ in e.stair?.isComponentStair == true ? "Edit the stair's runs with Edit Stairs." : nil })
    static let turnsLeft = P("stair.turnsLeft", "Turns Left", .bool, .construction,
                             get: { e, _ in e.stair.map { .bool($0.turnsLeft) } },
                             set: { e, v, _ in e.stair?.turnsLeft = try flag(v) },
                             locked: { e, _ in e.stair?.isComponentStair == true ? "Edit the stair's runs with Edit Stairs." : nil })

    static func instance(_ e: Element) -> [P] {
        var list: [P] = [baseLevel, baseOffset, topLevel, topOffset, height] + F2Parameters.stair
            + [upText, downText, upLabel, upArrow, downLabel, downArrow, upArrowAllViews,
               desiredRisers, actualRisers, actualRiserHeight, actualTreadDepth, treadStart, runWidth,
               beginWithRiser, endWithRiser, runCount]
        if e.stair?.isComponentStair != true { list += [shape, turnsLeft] }
        return list
    }

    // MARK: Types

    static func typeLength(_ id: ParameterID, _ name: String, _ group: ParameterGroup, min: Double = 0, tooltip: String = "") -> P {
        P(id.key, name, .length, group, tooltip: tooltip, get: { e, _ in e.typeData?.params[id] },
          set: { e, v, _ in e.typeData?.params[id] = .double(try positive(v, name, min: min)) })
    }
    static func typeBool(_ id: ParameterID, _ name: String, _ group: ParameterGroup, default d: Bool, tooltip: String = "") -> P {
        P(id.key, name, .bool, group, tooltip: tooltip, get: { e, _ in .bool(e.typeData?.params[id]?.boolValue ?? d) },
          set: { e, v, _ in e.typeData?.params[id] = .bool(try flag(v)) })
    }
    static func typeChoice(_ id: ParameterID, _ name: String, _ group: ParameterGroup, _ options: [String], default d: String) -> P {
        P(id.key, name, .choice(options), group, get: { e, _ in .text(e.typeData?.params[id]?.textValue ?? d) },
          set: { e, v, _ in
              guard options.contains(text(v)) else { throw err("Choose one of: \(options.joined(separator: ", ")).") }
              e.typeData?.params[id] = .text(text(v))
          })
    }
    static func typeRef(_ id: ParameterID, _ name: String, _ group: ParameterGroup, _ c: Category) -> P {
        P(id.key, name, .elementRef(c), group, get: { e, _ in .ref(e.typeData?.params[id]?.refValue) },
          set: { e, v, ctx in
              if let r = v.refValue {
                  let cat = ctx.model[r]?.typeData?.instanceCategory ?? ctx.model[r]?.category
                  guard cat == c else { throw err("Choose a \(c.singularName.lowercased()) type.") }
              }
              e.typeData?.params[id] = .ref(v.refValue)
          })
    }
    static func typeMaterial(_ id: ParameterID, _ name: String) -> P {
        P(id.key, name, .elementRef(.materials), .materials, get: { e, _ in .ref(e.typeData?.params[id]?.refValue) },
          set: { e, v, ctx in
              if let r = v.refValue, ctx.model[r]?.material == nil { throw err("Not a material.") }
              e.typeData?.params[id] = .ref(v.refValue)
          })
    }
    static func typeInteger(_ id: ParameterID, _ name: String, _ group: ParameterGroup, _ range: ClosedRange<Int>, default d: Int) -> P {
        P(id.key, name, .integer, group, get: { e, _ in .int(e.typeData?.params[id]?.intValue ?? d) },
          set: { e, v, _ in
              guard let n = v.intValue, range.contains(n) else { throw err("“\(name)” must be between \(range.lowerBound) and \(range.upperBound).") }
              e.typeData?.params[id] = .int(n)
          })
    }

    typealias T = StairTypeParam
    static let supportKinds = StairSupportKind.allCases.map(\.rawValue)

    // Stair types.
    static let maxRiser = typeLength(T.maxRiser, "Maximum Riser Height", .dimensions, min: 0.05)
    static let minTread = typeLength(T.minTread, "Minimum Tread Depth", .dimensions, min: 0.1)
    static let minRunWidth = typeLength(T.minRunWidth, "Minimum Run Width", .dimensions, min: 0.3)
    static let calcUse = typeBool(T.calcUse, "Use Stair Calculator", .dimensions, default: true,
                                  tooltip: "Checks 2 × Actual Riser Height + Actual Tread Depth against the range below.")
    static let calcTarget = typeLength(T.calcTarget, "Calculation Target (2R + T)", .dimensions, min: 0.3)
    static let calcMin = typeLength(T.calcMin, "Calculation Minimum (2R + T)", .dimensions, min: 0.3)
    static let calcMax = typeLength(T.calcMax, "Calculation Maximum (2R + T)", .dimensions, min: 0.3)
    static let runType = typeRef(T.runType, "Run Type", .construction, .stairRuns)
    static let landingType = typeRef(T.landingType, "Landing Type", .construction, .stairLandings)
    static let function = typeChoice(T.function, "Function", .construction, ["Interior", "Exterior"], default: "Interior")
    static let rightSupport = typeChoice(T.rightSupport, "Right Support", .structural, supportKinds, default: StairSupportKind.none.rawValue)
    static let rightSupportType = typeRef(T.rightSupportType, "Right Support Type", .structural, .stairSupports)
    static let rightOffset = typeLength(T.rightOffset, "Right Lateral Offset", .structural)
    static let leftSupport = typeChoice(T.leftSupport, "Left Support", .structural, supportKinds, default: StairSupportKind.none.rawValue)
    static let leftSupportType = typeRef(T.leftSupportType, "Left Support Type", .structural, .stairSupports)
    static let leftOffset = typeLength(T.leftOffset, "Left Lateral Offset", .structural)
    static let middleSupport = typeBool(T.middleSupport, "Middle Support", .structural, default: false)
    static let middleSupportType = typeRef(T.middleSupportType, "Middle Support Type", .structural, .stairSupports)
    static let middleSupportCount = typeInteger(T.middleSupportCount, "Middle Support Number", .structural, 1...6, default: 1)
    static let cutMarkType = typeChoice(T.cutMarkType, "Cut Mark Type", .graphics, StairCutMarkType.allCases.map(\.rawValue),
                                        default: StairCutMarkType.doubleZigzag.rawValue)
    // Older stair types (one monolithic run of their own).
    static let legacyTreadThickness = typeLength(T.treadThickness, "Tread Thickness", .construction, min: 0.01)
    static let legacyWaist = typeLength(T.waist, "Structural Depth", .construction, min: 0.05)

    static func stairType(_ td: TypeData) -> [P] {
        var list = [maxRiser, minTread, minRunWidth, calcUse, calcTarget, calcMin, calcMax, runType, landingType, function,
                    rightSupport, rightSupportType, rightOffset, leftSupport, leftSupportType, leftOffset,
                    middleSupport, middleSupportType, middleSupportCount, cutMarkType]
        if td.params[T.runType]?.refValue == nil { list += [legacyTreadThickness, legacyWaist] }
        return list
    }

    // Run types.
    static let runDepth = typeLength(T.runDepth, "Structural Depth", .dimensions, min: 0.02)
    static let runMaterial = typeMaterial(T.runMaterial, "Monolithic Material")
    static let runTreadMaterial = typeMaterial(T.runTreadMaterial, "Visible Tread Material")
    static let runRiserMaterial = typeMaterial(T.runRiserMaterial, "Visible Riser Material")
    static let runTread = typeBool(T.runTread, "Tread", .construction, default: true)
    static let runTreadThickness = typeLength(T.runTreadThickness, "Tread Thickness", .construction, min: 0.005)
    static let runNosingLength = typeLength(T.runNosingLength, "Nosing Length", .construction)
    static let runNosingProfile = typeChoice(T.runNosingProfile, "Nosing Profile", .construction, StairNosingProfile.allCases.map(\.rawValue),
                                             default: StairNosingProfile.none.rawValue)
    static let runApplyNosing = typeChoice(T.runApplyNosing, "Apply Nosing Profile", .construction, StairNosingApply.allCases.map(\.rawValue),
                                           default: StairNosingApply.front.rawValue)
    static let runRiser = typeBool(T.runRiser, "Riser", .construction, default: true)
    static let runRiserThickness = typeLength(T.runRiserThickness, "Riser Thickness", .construction, min: 0.002)
    static let runRiserType = P(T.runRiserSlanted.key, "Riser Type", .choice(["Straight", "Slanted"]), .construction,
                                get: { e, _ in .text(e.typeData?.params[T.runRiserSlanted]?.boolValue == true ? "Slanted" : "Straight") },
                                set: { e, v, _ in e.typeData?.params[T.runRiserSlanted] = .bool(text(v) == "Slanted") })
    static let runRiserConnection = typeChoice(T.runRiserConnection, "Riser to Tread Connection", .construction,
                                               StairRiserConnection.allCases.map(\.rawValue), default: StairRiserConnection.riserBehindTread.rawValue)
    static let runTypeList: [P] = [runDepth, runMaterial, runTreadMaterial, runRiserMaterial, runTread, runTreadThickness, runNosingLength,
                                   runNosingProfile, runApplyNosing, runRiser, runRiserThickness, runRiserType, runRiserConnection]

    // Landing types.
    static let landingThickness = typeLength(T.landingThickness, "Thickness", .dimensions, min: 0.02)
    static let landingMaterial = typeMaterial(T.landingMaterial, "Monolithic Material")
    static let landingTread = typeBool(T.landingTread, "Tread", .construction, default: false)
    static let landingTreadThickness = typeLength(T.landingTreadThickness, "Tread Thickness", .construction, min: 0.005)
    static let landingTreadMaterial = typeMaterial(T.landingTreadMaterial, "Visible Tread Material")
    static let landingTypeList: [P] = [landingThickness, landingMaterial, landingTread, landingTreadThickness, landingTreadMaterial]

    // Support types.
    static let supportWidth = typeLength(T.supportWidth, "Width", .dimensions, min: 0.01)
    static let supportDepth = typeLength(T.supportDepth, "Structural Depth on Run", .dimensions, min: 0.02)
    static let supportLandingDepth = typeLength(T.supportLandingDepth, "Structural Depth on Landing", .dimensions, min: 0.02)
    static let supportTopOffset = typeLength(T.supportTopOffset, "Top Offset", .dimensions,
                                             tooltip: "How far a stringer's top edge sits above the nosing line.")
    static let supportMaterial = typeMaterial(T.supportMaterial, "Material")
    static let supportTypeList: [P] = [supportWidth, supportDepth, supportLandingDepth, supportTopOffset, supportMaterial]

    // MARK: Railings

    typealias R = RailingTypeParam
    static let balustersPerTread = typeInteger(R.balustersPerTread, "Balusters per Tread", .construction, 0...6, default: 2)
    static let railTreadOffset = typeLength(R.treadOffset, "Tread Offset", .construction,
                                            tooltip: "On stairs: how far the railing sits in from the run edge.")
    static let topRailShape = typeChoice(R.topRailShape, "Top Rail Shape", .construction, ["Rectangular", "Circular"], default: "Rectangular")
    static let extensionStyle = typeChoice(R.extensionStyle, "Extension Style", .construction, RailingExtensionStyle.allCases.map(\.rawValue),
                                           default: RailingExtensionStyle.floor.rawValue)
    static let extensionLength = typeLength(R.extensionLength, "Extension Length", .construction)
    static let plusTreadDepth = typeBool(R.plusTreadDepth, "Plus Tread Depth", .construction, default: true,
                                         tooltip: "The bottom extension adds one tread depth along the slope.")
    static let postSize = typeLength(R.postSize, "Post Size", .construction, min: 0.01)
    static let handrailHeight = typeLength(R.handrailHeight, "Handrail Height", .construction,
                                           tooltip: "A handrail below the top rail (0: none).")
    static let handrailSize = typeLength(R.handrailSize, "Handrail Size", .construction, min: 0.01)
    static let railingType: [P] = [balustersPerTread, railTreadOffset, topRailShape, extensionStyle, extensionLength, plusTreadDepth,
                                   postSize, handrailHeight, handrailSize]

    static let railingPosition = P("railing.stairPosition", "Position", .choice(StairRailingPosition.allCases.map(\.rawValue)), .constraints,
                                   tooltip: "On a stair: on the treads, or on the stringer.",
                                   get: { e, _ in e.railing.map { .text(($0.stairPosition ?? .treads).rawValue) } },
                                   set: { e, v, _ in
                                       guard let p = StairRailingPosition(rawValue: text(v)) else { throw err("Choose Treads or Stringer.") }
                                       e.railing?.stairPosition = p
                                   })
    static let railingOffsetFromPath = P("railing.offsetFromPath", "Offset from Path", .length, .constraints,
                                         tooltip: "On a stair: how far the railing sits in from the run edge (empty: the type's Tread Offset).",
                                         get: { e, ctx in e.railing.map { .double($0.offsetFromPath ?? RailingTypeInfo.of(e, ctx.model).treadOffset) } },
                                         set: { e, v, _ in e.railing?.offsetFromPath = try number(v, "Offset from Path") })
    static func railingInstance(_ e: Element) -> [P] { e.railing?.followsHost == true ? [railingPosition, railingOffsetFromPath] : [] }

    /// Every parameter of this batch (for the catalog's id table and display order).
    static var all: [P] {
        let probe = Element(id: ElementID(0), category: .stairs, data: .stair(StairData(origin: .zero, direction: 0)))
        return instance(probe) + [shape, turnsLeft] + stairType(TypeData(instanceCategory: .stairs, familyName: "")) + runTypeList
            + landingTypeList + supportTypeList + railingType + [railingPosition, railingOffsetFromPath]
    }
}
