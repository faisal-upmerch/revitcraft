import Foundation

/// Known IFC class names (proper case) and the attribute tails used to re-export reference products.
enum IFCClassTable {
    /// Product classes of IFC2X3 and IFC4 (proper case). Used to restore casing from upper-case STEP names.
    static let productNames: [String] = """
    IfcActuator IfcAirTerminal IfcAirTerminalBox IfcAirToAirHeatRecovery IfcAlarm IfcAnnotation IfcAudioVisualAppliance IfcBeam \
    IfcBeamStandardCase IfcBoiler IfcBuilding IfcBuildingElementPart IfcBuildingElementProxy IfcBuildingStorey IfcBurner \
    IfcCableCarrierFitting IfcCableCarrierSegment IfcCableFitting IfcCableSegment IfcChiller IfcChimney IfcCivilElement IfcCoil \
    IfcColumn IfcColumnStandardCase IfcCommunicationsAppliance IfcCompressor IfcCondenser IfcController IfcCooledBeam IfcCoolingTower \
    IfcCovering IfcCurtainWall IfcDamper IfcDiscreteAccessory IfcDistributionChamberElement IfcDistributionControlElement \
    IfcDistributionElement IfcDistributionFlowElement IfcDistributionPort IfcDoor IfcDoorStandardCase IfcDuctFitting IfcDuctSegment \
    IfcDuctSilencer IfcElectricAppliance IfcElectricDistributionBoard IfcElectricDistributionPoint IfcElectricFlowStorageDevice \
    IfcElectricGenerator IfcElectricMotor IfcElectricTimeControl IfcElementAssembly IfcEnergyConversionDevice IfcEngine \
    IfcEquipmentElement IfcEvaporativeCooler IfcEvaporator IfcFan IfcFastener IfcFilter IfcFireSuppressionTerminal IfcFlowController \
    IfcFlowFitting IfcFlowInstrument IfcFlowMeter IfcFlowMovingDevice IfcFlowSegment IfcFlowStorageDevice IfcFlowTerminal \
    IfcFlowTreatmentDevice IfcFooting IfcFurnishingElement IfcFurniture IfcGeographicElement IfcGrid IfcHeatExchanger IfcHumidifier \
    IfcInterceptor IfcJunctionBox IfcLamp IfcLightFixture IfcMechanicalFastener IfcMedicalDevice IfcMember IfcMemberStandardCase \
    IfcMotorConnection IfcOpeningElement IfcOpeningStandardCase IfcOutlet IfcPile IfcPipeFitting IfcPipeSegment IfcPlate \
    IfcPlateStandardCase IfcProjectionElement IfcProtectiveDevice IfcProtectiveDeviceTrippingUnit IfcProxy IfcPump IfcRailing IfcRamp \
    IfcRampFlight IfcReinforcingBar IfcReinforcingMesh IfcRoof IfcSanitaryTerminal IfcSensor IfcShadingDevice IfcSite IfcSlab \
    IfcSlabElementedCase IfcSlabStandardCase IfcSolarDevice IfcSpace IfcSpaceHeater IfcStackTerminal IfcStair IfcStairFlight \
    IfcSwitchingDevice IfcSystemFurnitureElement IfcTank IfcTendon IfcTendonAnchor IfcTransformer IfcTransportElement IfcTubeBundle \
    IfcUnitaryControlElement IfcUnitaryEquipment IfcValve IfcVibrationIsolator IfcVirtualElement IfcWall IfcWallElementedCase \
    IfcWallStandardCase IfcWasteTerminal IfcWindow IfcWindowStandardCase IfcProject IfcElementQuantity IfcPropertySet \
    IfcRectangleProfileDef IfcCircleProfileDef IfcArbitraryClosedProfileDef IfcArbitraryProfileDefWithVoids IfcIShapeProfileDef \
    IfcLShapeProfileDef IfcTShapeProfileDef IfcUShapeProfileDef IfcCShapeProfileDef IfcZShapeProfileDef IfcRectangleHollowProfileDef \
    IfcCircleHollowProfileDef IfcEllipseProfileDef IfcDerivedProfileDef IfcCompositeProfileDef IfcAsymmetricIShapeProfileDef \
    IfcRoundedRectangleProfileDef IfcTrapeziumProfileDef IfcCenterLineProfileDef IfcArbitraryOpenProfileDef IfcExtrudedAreaSolid \
    IfcExtrudedAreaSolidTapered IfcRevolvedAreaSolid IfcRevolvedAreaSolidTapered IfcSweptDiskSolid IfcSweptDiskSolidPolygonal \
    IfcSurfaceCurveSweptAreaSolid IfcFixedReferenceSweptAreaSolid IfcAdvancedBrep IfcAdvancedBrepWithVoids IfcFacetedBrep \
    IfcFacetedBrepWithVoids IfcTriangulatedFaceSet IfcPolygonalFaceSet IfcMappedItem IfcBooleanResult IfcBooleanClippingResult \
    IfcHalfSpaceSolid IfcPolygonalBoundedHalfSpace IfcBoxedHalfSpace IfcCsgSolid IfcBlock IfcSphere IfcRightCircularCone \
    IfcRightCircularCylinder IfcRectangularPyramid IfcPolyline IfcIndexedPolyCurve IfcCompositeCurve IfcTrimmedCurve IfcCircle \
    IfcEllipse IfcLine IfcBSplineCurve IfcBSplineCurveWithKnots IfcRationalBSplineCurveWithKnots IfcPolyLoop IfcEdgeLoop IfcFace \
    IfcFaceSurface IfcAdvancedFace IfcShellBasedSurfaceModel IfcFaceBasedSurfaceModel IfcGeometricCurveSet IfcGeometricSet \
    IfcTextLiteral IfcTextLiteralWithExtent IfcAnnotationFillArea IfcBoundingBox IfcSectionedSpine IfcOffsetCurve2D \
    IfcSurfaceOfLinearExtrusion IfcTask IfcStructuralAnalysisModel IfcAsset IfcInventory IfcCostItem IfcActor IfcOccupant \
    IfcZone IfcSystem IfcGridPlacement IfcCartesianPoint
    """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)

    static let properCase: [String: String] = Dictionary(productNames.map { ($0.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })

    /// Proper-case class name for an upper-case STEP type (falls back to the STEP name).
    static func name(for stepType: String) -> String { properCase[stepType.uppercased()] ?? stepType }

    /// Attributes after the 8 common IfcElement attributes (GlobalId … Tag), per schema; nil = class not in that schema.
    struct Tail { var ifc2x3: [STEPValue]?; var ifc4: [STEPValue]? }

    private static let notDefined: [STEPValue] = [.enumeration("NOTDEFINED")]

    static let exportTails: [String: Tail] = {
        var t: [String: Tail] = [:]
        // Present in both schemas with 8 attributes in IFC2X3 and a PredefinedType in IFC4.
        for n in ["IfcWall", "IfcColumn", "IfcBeam", "IfcMember", "IfcPlate", "IfcCurtainWall", "IfcBuildingElementPart", "IfcDiscreteAccessory"] {
            t[n] = Tail(ifc2x3: [], ifc4: notDefined)
        }
        t["IfcWallStandardCase"] = Tail(ifc2x3: [], ifc4: notDefined)
        for n in ["IfcFlowSegment", "IfcFlowFitting", "IfcFlowTerminal", "IfcFlowController", "IfcFlowMovingDevice", "IfcFlowStorageDevice",
                  "IfcFlowTreatmentDevice", "IfcEnergyConversionDevice", "IfcDistributionElement", "IfcDistributionFlowElement", "IfcVirtualElement"] {
            t[n] = Tail(ifc2x3: [], ifc4: [])
        }
        t["IfcFurnishingElement"] = Tail(ifc2x3: [], ifc4: [])
        t["IfcFastener"] = Tail(ifc2x3: [], ifc4: notDefined)
        for n in ["IfcSlab", "IfcCovering", "IfcRailing"] { t[n] = Tail(ifc2x3: [.null], ifc4: notDefined) }
        t["IfcBuildingElementProxy"] = Tail(ifc2x3: [.null], ifc4: notDefined)
        for n in ["IfcRoof", "IfcStair", "IfcRamp", "IfcFooting"] { t[n] = Tail(ifc2x3: notDefined, ifc4: notDefined) }
        t["IfcDoor"] = Tail(ifc2x3: [.null, .null], ifc4: [.null, .null, .null, .null, .null])
        t["IfcWindow"] = Tail(ifc2x3: [.null, .null], ifc4: [.null, .null, .null, .null, .null])
        // IFC4-only classes with a PredefinedType.
        for n in ["IfcFurniture", "IfcSystemFurnitureElement", "IfcSanitaryTerminal", "IfcPipeSegment", "IfcPipeFitting", "IfcDuctSegment",
                  "IfcDuctFitting", "IfcGeographicElement", "IfcShadingDevice", "IfcChimney", "IfcLightFixture", "IfcLamp", "IfcElectricAppliance",
                  "IfcAirTerminal", "IfcValve", "IfcPump", "IfcFan", "IfcTank", "IfcOutlet", "IfcFireSuppressionTerminal", "IfcWasteTerminal",
                  "IfcCableCarrierSegment", "IfcCableSegment", "IfcSpaceHeater", "IfcTransportElement", "IfcSwitchingDevice", "IfcSensor",
                  "IfcActuator", "IfcAlarm", "IfcController", "IfcFlowMeter", "IfcJunctionBox", "IfcUnitaryEquipment", "IfcBoiler", "IfcChiller"] {
            t[n] = Tail(ifc2x3: nil, ifc4: notDefined)
        }
        for n in ["IfcCivilElement", "IfcDistributionControlElement"] { t[n] = Tail(ifc2x3: nil, ifc4: []) }
        return t
    }()

    /// Equivalents used when a recorded class does not exist in the target schema.
    static let fallback2x3: [String: String] = [
        "IfcFurniture": "IfcFurnishingElement", "IfcSystemFurnitureElement": "IfcFurnishingElement",
        "IfcSanitaryTerminal": "IfcFlowTerminal", "IfcWasteTerminal": "IfcFlowTerminal", "IfcAirTerminal": "IfcFlowTerminal",
        "IfcLightFixture": "IfcFlowTerminal", "IfcLamp": "IfcFlowTerminal", "IfcOutlet": "IfcFlowTerminal", "IfcFireSuppressionTerminal": "IfcFlowTerminal",
        "IfcElectricAppliance": "IfcFlowTerminal",
        "IfcPipeSegment": "IfcFlowSegment", "IfcDuctSegment": "IfcFlowSegment", "IfcCableSegment": "IfcFlowSegment", "IfcCableCarrierSegment": "IfcFlowSegment",
        "IfcPipeFitting": "IfcFlowFitting", "IfcDuctFitting": "IfcFlowFitting",
        "IfcValve": "IfcFlowController", "IfcSwitchingDevice": "IfcFlowController",
        "IfcPump": "IfcFlowMovingDevice", "IfcFan": "IfcFlowMovingDevice", "IfcTank": "IfcFlowStorageDevice",
        "IfcBoiler": "IfcEnergyConversionDevice", "IfcChiller": "IfcEnergyConversionDevice", "IfcUnitaryEquipment": "IfcEnergyConversionDevice",
        "IfcSpaceHeater": "IfcEnergyConversionDevice",
    ]
    static let fallback4: [String: String] = ["IfcWallStandardCase": "IfcWall", "IfcFurnishingElement": "IfcFurniture"]

    /// Resolves a recorded class to an exportable class and its attribute tail for a schema (nil = not exportable).
    static func exportable(_ recorded: String, schema: IFCSchema) -> (name: String, tail: [STEPValue])? {
        var n = name(for: recorded)
        switch schema {
        case .ifc2x3:
            if let f = fallback2x3[n] { n = f }
            guard let tail = exportTails[n]?.ifc2x3 else { return nil }
            return (n, tail)
        case .ifc4:
            if let f = fallback4[n] { n = f }
            guard let tail = exportTails[n]?.ifc4 else { return nil }
            return (n, tail)
        }
    }
}
