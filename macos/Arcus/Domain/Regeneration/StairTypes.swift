import Foundation
import ArcusGeometry

// STAIR: the values of a stair's type and of the run, landing and support types it names (Revit-style Type Properties),
// resolved once per layout. Types from before STAIR have none of the new parameters: they read as a monolithic stair of
// their Structural Depth, without supports, exactly as they used to draw.

/// Parameter ids of stair, run, landing and support types.
public enum StairTypeParam {
    // Stair type: Calculation Rules.
    public static let maxRiser = ParameterID("stair.maxRiser")
    public static let minTread = ParameterID("stair.minTread")
    public static let minRunWidth = ParameterID("stair.minRunWidth")
    public static let calcUse = ParameterID("stair.calcUse")
    public static let calcTarget = ParameterID("stair.calcTarget")
    public static let calcMin = ParameterID("stair.calcMin")
    public static let calcMax = ParameterID("stair.calcMax")
    // Stair type: components and supports.
    public static let runType = ParameterID("stair.runType")
    public static let landingType = ParameterID("stair.landingType")
    public static let rightSupport = ParameterID("stair.rightSupport")
    public static let rightSupportType = ParameterID("stair.rightSupportType")
    public static let rightOffset = ParameterID("stair.rightLateralOffset")
    public static let leftSupport = ParameterID("stair.leftSupport")
    public static let leftSupportType = ParameterID("stair.leftSupportType")
    public static let leftOffset = ParameterID("stair.leftLateralOffset")
    public static let middleSupport = ParameterID("stair.middleSupport")
    public static let middleSupportType = ParameterID("stair.middleSupportType")
    public static let middleSupportCount = ParameterID("stair.middleSupportCount")
    // Stair type: Construction.
    public static let function = ParameterID("stair.function")
    public static let cutMarkType = ParameterID("stair.cutMarkType")
    // Older stair types.
    public static let treadThickness = ParameterID("stair.treadThickness")
    public static let waist = ParameterID("stair.waist")

    // Run types.
    public static let runMonolithic = ParameterID("run.monolithic")
    public static let runDepth = ParameterID("run.structuralDepth")
    public static let runMaterial = ParameterID("run.material")
    public static let runTread = ParameterID("run.tread")
    public static let runTreadThickness = ParameterID("run.treadThickness")
    public static let runTreadMaterial = ParameterID("run.treadMaterial")
    public static let runNosingLength = ParameterID("run.nosingLength")
    public static let runNosingProfile = ParameterID("run.nosingProfile")
    public static let runApplyNosing = ParameterID("run.applyNosing")
    public static let runRiser = ParameterID("run.riser")
    public static let runRiserThickness = ParameterID("run.riserThickness")
    public static let runRiserMaterial = ParameterID("run.riserMaterial")
    public static let runRiserSlanted = ParameterID("run.riserSlanted")
    public static let runRiserConnection = ParameterID("run.riserConnection")

    // Landing types.
    public static let landingMonolithic = ParameterID("landing.monolithic")
    public static let landingThickness = ParameterID("landing.thickness")
    public static let landingMaterial = ParameterID("landing.material")
    public static let landingTread = ParameterID("landing.tread")
    public static let landingTreadThickness = ParameterID("landing.treadThickness")
    public static let landingTreadMaterial = ParameterID("landing.treadMaterial")

    // Support types.
    public static let supportWidth = ParameterID("support.width")
    public static let supportDepth = ParameterID("support.structuralDepth")
    public static let supportLandingDepth = ParameterID("support.landingDepth")
    public static let supportTopOffset = ParameterID("support.topOffset")
    public static let supportMaterial = ParameterID("support.material")
}

/// Everything the stair geometry needs from the type and its run, landing and support types.
public struct StairTypeInfo: Sendable {
    public struct Run: Sendable {
        public var monolithic = true
        public var structuralDepth = 0.15
        public var material: ElementID?
        public var tread = false
        public var treadThickness = 0.04
        public var treadMaterial: ElementID?
        public var nosingLength = 0.0
        public var nosingProfile = StairNosingProfile.none
        public var applyNosing = StairNosingApply.front
        public var riser = false
        public var riserThickness = 0.0125
        public var riserMaterial: ElementID?
        public var riserSlanted = false
        public var connection = StairRiserConnection.riserBehindTread
    }
    public struct Landing: Sendable {
        public var monolithic = true
        public var thickness = 0.15
        public var material: ElementID?
        public var tread = false
        public var treadThickness = 0.04
        public var treadMaterial: ElementID?
    }
    public struct Support: Sendable {
        public var kind = StairSupportKind.none
        public var typeID: ElementID?
        public var lateralOffset = 0.0
        public var width = 0.05
        public var depth = 0.3
        public var landingDepth = 0.3
        public var topOffset = 0.05
        public var material: ElementID?
    }

    public var maxRiser = 0.18
    public var minTread = 0.28
    public var minRunWidth = 0.9
    public var calcUse = true
    public var calcTarget = 0.635
    public var calcMin = 0.61
    public var calcMax = 0.66
    public var run = Run()
    public var landing = Landing()
    public var right = Support()
    public var left = Support()
    public var middle = Support()
    public var middleCount = 0
    public var cutMark = StairCutMarkType.doubleZigzag
    /// Stair type family ("Assembled Stair", "Cast-In-Place Stair", "Precast Stair").
    public var family = "Assembled Stair"
    public var isPrecast: Bool { family == "Precast Stair" }

    /// The info of a stair element's type.
    public static func of(_ e: Element, _ model: BIMModel) -> StairTypeInfo { of(type: model.typeData(of: e), model) }

    public static func of(type td: TypeData?, _ model: BIMModel) -> StairTypeInfo {
        var t = StairTypeInfo()
        guard let td else { return t }
        let p = td.params
        func len(_ id: ParameterID, _ d: Double) -> Double { p[id]?.doubleValue ?? d }
        t.family = td.familyName.isEmpty ? t.family : td.familyName
        t.maxRiser = len(StairTypeParam.maxRiser, t.maxRiser)
        t.minTread = len(StairTypeParam.minTread, t.minTread)
        t.minRunWidth = len(StairTypeParam.minRunWidth, t.minRunWidth)
        t.calcUse = p[StairTypeParam.calcUse]?.boolValue ?? t.calcUse
        t.calcTarget = len(StairTypeParam.calcTarget, t.calcTarget)
        t.calcMin = len(StairTypeParam.calcMin, t.calcMin)
        t.calcMax = len(StairTypeParam.calcMax, t.calcMax)
        t.cutMark = p[StairTypeParam.cutMarkType]?.textValue.flatMap(StairCutMarkType.init(rawValue:)) ?? t.cutMark
        // Older types: one monolithic run and landing of the Structural Depth, in the type's material.
        let legacyMaterial = p[ParameterID("type.material")]?.refValue
        t.run.structuralDepth = len(StairTypeParam.waist, t.run.structuralDepth)
        t.run.material = legacyMaterial
        t.landing.thickness = t.run.structuralDepth
        t.landing.material = legacyMaterial
        if let rt = p[StairTypeParam.runType]?.refValue, let r = model[rt]?.typeData { t.run = run(r.params, fallback: t.run) }
        if let lt = p[StairTypeParam.landingType]?.refValue, let l = model[lt]?.typeData { t.landing = landing(l.params, fallback: t.landing) }
        t.right = support(p, kind: StairTypeParam.rightSupport, type: StairTypeParam.rightSupportType, offset: StairTypeParam.rightOffset, model)
        t.left = support(p, kind: StairTypeParam.leftSupport, type: StairTypeParam.leftSupportType, offset: StairTypeParam.leftOffset, model)
        if p[StairTypeParam.middleSupport]?.boolValue == true {
            var m = support(p, kind: nil, type: StairTypeParam.middleSupportType, offset: nil, model)
            m.kind = .carriageOpen
            t.middle = m
            t.middleCount = max(1, p[StairTypeParam.middleSupportCount]?.intValue ?? 1)
        }
        return t
    }

    static func run(_ p: [ParameterID: ParamValue], fallback f: Run) -> Run {
        var r = f
        r.monolithic = p[StairTypeParam.runMonolithic]?.boolValue ?? f.monolithic
        r.structuralDepth = p[StairTypeParam.runDepth]?.doubleValue ?? f.structuralDepth
        r.material = p[StairTypeParam.runMaterial]?.refValue ?? f.material
        r.tread = p[StairTypeParam.runTread]?.boolValue ?? !r.monolithic
        r.treadThickness = p[StairTypeParam.runTreadThickness]?.doubleValue ?? f.treadThickness
        r.treadMaterial = p[StairTypeParam.runTreadMaterial]?.refValue ?? r.material
        r.nosingLength = p[StairTypeParam.runNosingLength]?.doubleValue ?? f.nosingLength
        r.nosingProfile = p[StairTypeParam.runNosingProfile]?.textValue.flatMap(StairNosingProfile.init(rawValue:)) ?? f.nosingProfile
        r.applyNosing = p[StairTypeParam.runApplyNosing]?.textValue.flatMap(StairNosingApply.init(rawValue:)) ?? f.applyNosing
        r.riser = p[StairTypeParam.runRiser]?.boolValue ?? !r.monolithic
        r.riserThickness = p[StairTypeParam.runRiserThickness]?.doubleValue ?? f.riserThickness
        r.riserMaterial = p[StairTypeParam.runRiserMaterial]?.refValue ?? r.treadMaterial
        r.riserSlanted = p[StairTypeParam.runRiserSlanted]?.boolValue ?? f.riserSlanted
        r.connection = p[StairTypeParam.runRiserConnection]?.textValue.flatMap(StairRiserConnection.init(rawValue:)) ?? f.connection
        if r.nosingProfile == .none { r.nosingLength = 0 }
        return r
    }

    static func landing(_ p: [ParameterID: ParamValue], fallback f: Landing) -> Landing {
        var l = f
        l.monolithic = p[StairTypeParam.landingMonolithic]?.boolValue ?? f.monolithic
        l.thickness = p[StairTypeParam.landingThickness]?.doubleValue ?? f.thickness
        l.material = p[StairTypeParam.landingMaterial]?.refValue ?? f.material
        l.tread = p[StairTypeParam.landingTread]?.boolValue ?? !l.monolithic
        l.treadThickness = p[StairTypeParam.landingTreadThickness]?.doubleValue ?? f.treadThickness
        l.treadMaterial = p[StairTypeParam.landingTreadMaterial]?.refValue ?? l.material
        return l
    }

    static func support(_ p: [ParameterID: ParamValue], kind: ParameterID?, type: ParameterID, offset: ParameterID?, _ model: BIMModel) -> Support {
        var s = Support()
        if let kind { s.kind = p[kind]?.textValue.flatMap(StairSupportKind.init(rawValue:)) ?? .none }
        if let offset { s.lateralOffset = p[offset]?.doubleValue ?? 0 }
        s.typeID = p[type]?.refValue
        if let sp = s.typeID.flatMap({ model[$0]?.typeData?.params }) {
            s.width = sp[StairTypeParam.supportWidth]?.doubleValue ?? s.width
            s.depth = sp[StairTypeParam.supportDepth]?.doubleValue ?? s.depth
            s.landingDepth = sp[StairTypeParam.supportLandingDepth]?.doubleValue ?? s.depth
            s.topOffset = sp[StairTypeParam.supportTopOffset]?.doubleValue ?? s.topOffset
            s.material = sp[StairTypeParam.supportMaterial]?.refValue
        }
        return s
    }

    /// The support info of a support type element (Pick Edges with an explicit type).
    static func support(typeID: ElementID?, kind: StairSupportKind, _ model: BIMModel) -> Support {
        var s = Support()
        s.kind = kind
        s.typeID = typeID
        if let sp = typeID.flatMap({ model[$0]?.typeData?.params }) {
            s.width = sp[StairTypeParam.supportWidth]?.doubleValue ?? s.width
            s.depth = sp[StairTypeParam.supportDepth]?.doubleValue ?? s.depth
            s.landingDepth = sp[StairTypeParam.supportLandingDepth]?.doubleValue ?? s.depth
            s.topOffset = sp[StairTypeParam.supportTopOffset]?.doubleValue ?? s.topOffset
            s.material = sp[StairTypeParam.supportMaterial]?.refValue
        }
        return s
    }

    /// The run, landing and support types a stair type names (dependency inputs of its stairs).
    public static func componentTypeIDs(_ td: TypeData?) -> [ElementID] {
        guard let p = td?.params else { return [] }
        return [StairTypeParam.runType, StairTypeParam.landingType, StairTypeParam.rightSupportType, StairTypeParam.leftSupportType,
                StairTypeParam.middleSupportType].compactMap { p[$0]?.refValue }
    }
}
