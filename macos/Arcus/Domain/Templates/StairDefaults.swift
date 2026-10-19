import Foundation
import ArcusGeometry
import ArcusCalc

/// STAIR: the standard stair content of new projects, as Revit's templates have it: run types (Monolithic Run,
/// Non-Monolithic Run), landing types, support types (Stringer (Closed), Carriage (Open)) and stair types of the three
/// stair families (Cast-In-Place Stair, Assembled Stair, Precast Stair), metric or imperial; and railing settings for
/// stairs on the standard railing types.
public enum StairDefaults {
    typealias T = StairTypeParam
    typealias R = RailingTypeParam

    /// Names of the standard types by unit system.
    struct Names {
        var monolithicRun: String, assembledRun: String, monolithicLanding: String, assembledLanding: String
        var stringer: String, carriage: String, assembledStair: String, precastStair: String
        init(_ imperial: Bool) {
            if imperial {
                monolithicRun = "6\" Structural Depth"; assembledRun = "2\" Tread 1/2\" Riser"
                monolithicLanding = "6\" Thickness"; assembledLanding = "2\" Tread 6\" Thickness"
                stringer = "Stringer - 2\" Width"; carriage = "Carriage - 2\" Width"
                assembledStair = "Assembled - 7\" max riser 11\" tread"; precastStair = "Precast - 7\" max riser"
            } else {
                monolithicRun = "150mm Structural Depth"; assembledRun = "50mm Tread 13mm Riser"
                monolithicLanding = "150mm Thickness"; assembledLanding = "50mm Tread 150mm Thickness"
                stringer = "Stringer - 50mm Width"; carriage = "Carriage - 50mm Width"
                assembledStair = "Assembled - 175 max riser"; precastStair = "Precast - 175 max riser"
            }
        }
    }

    /// Adds the standard run, landing, support and stair types (skipping names the project has), points `stairType`
    /// (the template's monolithic stair type) at the monolithic run and landing, and gives the railing types their
    /// stair settings. Returns the ids of the added types by name.
    @discardableResult
    public static func populate(_ tx: TransactionContext, imperial: Bool, stairType: ElementID?, railingTypes: [ElementID]) -> [String: ElementID] {
        let n = Names(imperial)
        let i = imperial ? 0.0254 : 0
        func len(_ metric: Double, _ inches: Double) -> ParamValue { .double(imperial ? inches * i : metric) }
        func mat(_ name: String) -> ParamValue { .ref(tx.model.material(named: name)?.id) }
        var out: [String: ElementID] = [:]
        func type(_ name: String, _ c: Category, _ family: String, _ params: [ParameterID: ParamValue], system: SystemFamily? = nil) -> ElementID {
            if let e = tx.model.elements(.elementTypes).first(where: { $0.name == name && $0.typeData?.instanceCategory == c }) { return e.id }
            let id = tx.create(.elementTypes, name: name, data: .type(TypeData(instanceCategory: c, systemFamily: system, familyName: family, params: params)))
            out[name] = id
            return id
        }
        let concrete = mat("Concrete, Cast-in-Place"), wood = mat("Oak Flooring"), hardwood = mat("Hardwood"), steel = mat("Steel")
        let monoRun = type(n.monolithicRun, .stairRuns, "Monolithic Run", [
            T.runMonolithic: .bool(true), T.runDepth: len(0.15, 6), T.runMaterial: concrete, T.runTread: .bool(false), T.runRiser: .bool(false),
            T.runTreadThickness: len(0.04, 1.5), T.runNosingLength: len(0, 0), T.runNosingProfile: .text(StairNosingProfile.none.rawValue),
        ])
        let woodRun = type(n.assembledRun, .stairRuns, "Non-Monolithic Run", [
            T.runMonolithic: .bool(false), T.runDepth: len(0.15, 6), T.runMaterial: hardwood,
            T.runTread: .bool(true), T.runTreadThickness: len(0.05, 2), T.runTreadMaterial: wood,
            T.runNosingLength: len(0.025, 1), T.runNosingProfile: .text(StairNosingProfile.square.rawValue),
            T.runApplyNosing: .text(StairNosingApply.front.rawValue),
            T.runRiser: .bool(true), T.runRiserThickness: len(0.013, 0.5), T.runRiserMaterial: hardwood,
            T.runRiserConnection: .text(StairRiserConnection.riserBehindTread.rawValue),
        ])
        let monoLanding = type(n.monolithicLanding, .stairLandings, "Monolithic Landing", [
            T.landingMonolithic: .bool(true), T.landingThickness: len(0.15, 6), T.landingMaterial: concrete, T.landingTread: .bool(false),
        ])
        let woodLanding = type(n.assembledLanding, .stairLandings, "Non-Monolithic Landing", [
            T.landingMonolithic: .bool(false), T.landingThickness: len(0.15, 6), T.landingMaterial: hardwood,
            T.landingTread: .bool(true), T.landingTreadThickness: len(0.05, 2), T.landingTreadMaterial: wood,
        ])
        let stringer = type(n.stringer, .stairSupports, "Stringer (Closed)", [
            T.supportWidth: len(0.05, 2), T.supportDepth: len(0.3, 12), T.supportLandingDepth: len(0.3, 12), T.supportTopOffset: len(0.05, 2),
            T.supportMaterial: hardwood,
        ])
        let carriage = type(n.carriage, .stairSupports, "Carriage (Open)", [
            T.supportWidth: len(0.05, 2), T.supportDepth: len(0.3, 12), T.supportLandingDepth: len(0.3, 12), T.supportTopOffset: len(0, 0),
            T.supportMaterial: steel,
        ])
        let rules: [ParameterID: ParamValue] = [
            T.maxRiser: len(0.175, 7), T.minTread: len(0.28, 11), T.minRunWidth: len(0.9, 36), T.calcUse: .bool(true),
            T.calcTarget: len(0.635, 25), T.calcMin: len(0.61, 24), T.calcMax: len(0.66, 26),
            T.function: .text("Interior"), T.cutMarkType: .text(StairCutMarkType.doubleZigzag.rawValue),
        ]
        var assembled = rules
        assembled[T.runType] = .ref(woodRun); assembled[T.landingType] = .ref(woodLanding)
        for side in [(T.rightSupport, T.rightSupportType, T.rightOffset), (T.leftSupport, T.leftSupportType, T.leftOffset)] {
            assembled[side.0] = .text(StairSupportKind.stringerClosed.rawValue); assembled[side.1] = .ref(stringer); assembled[side.2] = .double(0)
        }
        assembled[T.middleSupport] = .bool(false); assembled[T.middleSupportType] = .ref(carriage)
        _ = type(n.assembledStair, .stairs, "Assembled Stair", assembled, system: .stair)
        var precast = rules
        precast[T.runType] = .ref(monoRun); precast[T.landingType] = .ref(monoLanding)
        _ = type(n.precastStair, .stairs, "Precast Stair", precast, system: .stair)
        if let st = stairType, tx.model[st]?.typeData?.params[T.runType] == nil {
            tx.update(st) { e in
                e.typeData?.familyName = "Cast-In-Place Stair"
                for (k, v) in rules where e.typeData?.params[k] == nil { e.typeData?.params[k] = v }
                e.typeData?.params[T.runType] = .ref(monoRun)
                e.typeData?.params[T.landingType] = .ref(monoLanding)
            }
        }
        for r in railingTypes where tx.model[r]?.typeData?.params[R.balustersPerTread] == nil {
            tx.update(r) { e in
                let guardRail = (e.typeData?.params[R.height]?.doubleValue ?? 1) > 1.0
                e.typeData?.params[R.balustersPerTread] = .int(guardRail ? 2 : 0)
                e.typeData?.params[R.topRailShape] = .text("Circular")
                e.typeData?.params[R.extensionStyle] = .text(RailingExtensionStyle.floor.rawValue)
                e.typeData?.params[R.extensionLength] = len(0.3, 12)
                e.typeData?.params[R.plusTreadDepth] = .bool(true)
                e.typeData?.params[R.treadOffset] = len(0.05, 2)
                if guardRail { e.typeData?.params[R.handrailHeight] = len(0.9, 36); e.typeData?.params[R.handrailSize] = len(0.04, 1.5) }
            }
        }
        return out
    }

    /// Standard stair types a project is missing (Load Standard Types), by the project's unit system. Older stair types
    /// stay as they are.
    @discardableResult
    public static func loadMissing(into tx: TransactionContext) -> Int {
        let before = tx.model.elements(.elementTypes).count
        populate(tx, imperial: tx.model.units.system == .imperial, stairType: nil, railingTypes: [])
        return tx.model.elements(.elementTypes).count - before
    }
}
