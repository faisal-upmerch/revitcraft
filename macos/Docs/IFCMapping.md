# IFC mapping

`ArcusIFC` writes **IFC2X3 Coordination View 2.0** and **IFC4 Reference View 1.2** (ADD2 TC1
entity names). It reads IFC2X3 and IFC4 files, and reads IFC4x1/IFC4x3 files with the IFC4
subset. Model units are meters. Export and import are pure functions over value-type models and
run off the main actor.

- Export: `IFCExporter.export(model, options:progress:isCancelled:)` returns `(files, report)`.
- Import: `IFCImporter.importFile(data, fileName:into:options:progress:isCancelled:)` writes into
  a caller-provided `TransactionContext` (one undoable step). The importer never commits. If it
  throws, it has not touched the transaction: all parsing and analysis finishes before the first
  element is created.

## File header

| Item | IFC2X3 | IFC4 |
|---|---|---|
| `FILE_DESCRIPTION` | `('ViewDefinition [CoordinationView_V2.0]'),'2;1'` | `('ViewDefinition [ReferenceView_V1.2]'),'2;1'` |
| `FILE_NAME` | name, UTC timestamp (`IFCExportOptions.timeStamp`, default now), author, organization, `Arcus IFC <version>`, `Arcus <version>` | same |
| `FILE_SCHEMA` | `('IFC2X3')` | `('IFC4')` |

Strings are 7-bit Part 21: `'` is doubled, `\` is doubled, and every non-ASCII character is
written as `\X2\hhhh\X0\` (or `\X4\` for characters beyond the BMP). Reals always contain a
decimal point and have at most 9 decimals. Entity numbering follows a fixed order: context, then
spatial structure, then elements sorted by element id, then relationships. Identical input gives
identical bytes. Goldens for both schemas live in `Arcus/Tests/IFCTests/Fixtures`.

## Context and spatial structure

| Arcus | IFC |
|---|---|
| Units | `IfcSIUnit` METRE, SQUARE_METRE, CUBIC_METRE, RADIAN in `IfcUnitAssignment` |
| Representation contexts | `IfcGeometricRepresentationContext` ('Model', 3D, precision 1e-5, TrueNorth from `ProjectInfo.trueNorthAngle`) with sub-contexts `Body` (MODEL_VIEW) and `Axis` (GRAPH_VIEW). There is no FootPrint context. |
| Project info | `IfcProject`: Name = project number (or name), LongName = project name, Phase = status. The GUID comes from the Project Information element. |
| Site | `IfcSite`: Name = site name, RefLatitude/RefLongitude as compound angles when set, RefElevation = elevation above sea level. The GUID is derived: `deterministic("<project>/site")`. |
| Building | `IfcBuilding`: Name = building name (default "Building"). The address becomes `IfcPostalAddress` address lines. |
| Levels with *Building Story* on | `IfcBuildingStorey` with Elevation = level elevation minus the coordinate-base z. The GUID is the level's `ifcGUID`. If no level is a storey, every level is exported. If the model has no levels, a synthetic "Level 0" is created and reported. |
| Aggregation | `IfcRelAggregates` project→site→building→storeys, and storey→spaces |
| Containment | `IfcRelContainedInSpatialStructure` per storey (by `levelID`; inserts use their host's level). Elements on non-storey levels go to the nearest storey below. Elements without a level go to the first storey, with a warning. IFC4 terrain is contained in the site. |
| Owner history | One `IfcPersonAndOrganization` + `IfcApplication` (`Arcus`, version) and `IfcOwnerHistory` (ADDED, creation date = timestamp) |

## Coordinate bases

| `IFCCoordinateBase` | Origin written as IFC (0,0,0) | Extra |
|---|---|---|
| `internalOrigin` | Arcus internal origin | none |
| `projectBasePoint` (default) | `ProjectInfo.projectBasePoint` | none |
| `sharedCoordinates` | `ProjectInfo.surveyPoint` | IFC4: `IfcMapConversion` (Eastings, Northings, OrthogonalHeight from the survey values; X-axis abscissa/ordinate from −trueNorthAngle; Scale 1) targeting an `IfcProjectedCRS` named "Arcus Shared Coordinates", because Arcus does not record an EPSG code. IFC2X3 has no map conversion, so the survey values go into the `Arcus_SharedCoordinates` property set on `IfcSite` and a warning is reported. |

All geometry, placements and storey elevations are shifted by the chosen base point. Rotation
is expressed through TrueNorth / map conversion only, never by rotating geometry. The importer
reads geometry in file coordinates and does not undo a map conversion.

## Export: element mapping

| Arcus category / data | IFC2X3 | IFC4 | Placement | Body |
|---|---|---|---|---|
| Walls | `IfcWallStandardCase` when straight, no profile edit, no slant and no top/base attachment; otherwise `IfcWall` | `IfcWall` (NOTDEFINED) | Wall start, x along the wall, z = wall base | 2X3 standard case: `Axis` IfcPolyline plus `SweptSolid` extrusion of the joined footprint, with openings through voids. Otherwise `Brep`. IFC4: `Axis` plus `Tessellation` with openings already cut. |
| Floors | `IfcSlab` FLOOR (BASESLAB on the lowest storey) | same | Storey | 2X3: `SweptSolid` for flat slabs, `Brep` for sloped ones. IFC4: tessellated per layer. |
| Building pads | `IfcSlab` BASESLAB | same | Storey | as floors |
| Ceilings | `IfcCovering` CEILING | same | Storey | as floors |
| Roofs | `IfcRoof` (FLAT_ROOF / HIP_ROOF / GABLE_ROOF from edge slopes) | same | Storey | **One body per roof.** Roofs are *not* decomposed into `IfcSlab` ROOF parts. |
| Doors | `IfcDoor` (OverallHeight/Width = family Height/Width) + `IfcOpeningElement` + `IfcRelVoidsElement` + `IfcRelFillsElement` | `IfcDoor` DOOR (same relationships) | Host centre line at the sill, x along the wall | Brep / Tessellation |
| Windows | `IfcWindow` (same pattern) | `IfcWindow` WINDOW | as doors | as doors |
| Openings | `IfcOpeningElement` | `IfcOpeningElement` OPENING | Relative to the wall placement | `SweptSolid` box (`IfcRectangleProfileDef`, opening width × wall thickness + 20 mm) in both schemas. Every hosted insert of an exported wall gets an opening, even when the insert itself is filtered out. |
| Rooms (enclosed) | `IfcSpace` (Name = number, LongName = name, INTERNAL) | `IfcSpace` SPACE | Storey, at the room base | Room boundary extruded to room height: 2X3 `SweptSolid` (with voids), IFC4 `Tessellation` |
| Columns, structural columns | `IfcColumn` | `IfcColumn` COLUMN | Column location and rotation | Brep / Tessellation |
| Structural framing | `IfcBeam` | `IfcBeam` BEAM | Storey | Brep / Tessellation |
| Rebar sets, area and path reinforcement | `IfcReinforcingBar` (NominalDiameter, CrossSectionArea, BarLength = the longest bar; BarRole MAIN, EDGE for path) | `IfcReinforcingBar` (PredefinedType MAIN / EDGE) | Storey of the host | Brep / Tessellation of every bar (octagonal rods) |
| Fabric areas and sheets | `IfcReinforcingMesh` (wire diameters, areas and spacings; sheets also MeshLength/Width) | `IfcReinforcingMesh` NOTDEFINED | Storey of the host | Brep / Tessellation of every wire |
| Stairs | `IfcStair` (STRAIGHT_RUN / QUARTER_TURN / HALF_TURN) | same | Storey | Brep / Tessellation |
| Railings | `IfcRailing` (HANDRAIL if the type name contains "Handrail", else GUARDRAIL) | same | Storey | Brep / Tessellation |
| Furniture, casework | `IfcFurnishingElement` | `IfcFurniture` | Component location and rotation (mirroring is baked into the mesh) | Brep / Tessellation |
| Plumbing fixtures | `IfcFlowTerminal` (**decision:** CV2.0 has no sanitary terminal occurrence) | `IfcSanitaryTerminal` | Component | Brep / Tessellation |
| Lighting fixtures | `IfcFlowTerminal` (**decision:** CV2.0 has no light fixture occurrence) | `IfcLightFixture` NOTDEFINED | Component | Brep / Tessellation |
| Planting | `IfcBuildingElementProxy` (IFC2X3 has no geographic element) | `IfcGeographicElement` NOTDEFINED | Component | Brep / Tessellation |
| Generic models, specialty equipment, parking, electrical fixtures, mechanical equipment, entourage, site, any other model geometry | `IfcBuildingElementProxy` | `IfcBuildingElementProxy` NOTDEFINED | Component or storey | Brep / Tessellation |
| Topography | Body of `IfcSite` (SurfaceModel) | `IfcGeographicElement` TERRAIN, contained in `IfcSite` | Site | Surface model / Tessellation |
| Topography: toposolid / sub-division | Body of `IfcSite` (closed layer solids) | `IfcGeographicElement` TERRAIN, contained in `IfcSite`; one closed tessellated item per structure layer | Site | Brep / Tessellation |
| IFC reference geometry | Re-exported as the class recorded at import when it is valid in the target schema. Known IFC4-only classes map to their IFC2X3 equivalents (e.g. IfcPipeSegment → IfcFlowSegment, IfcPump → IfcFlowMovingDevice). Anything else becomes `IfcBuildingElementProxy`, with a warning. Retained property sets are written back. | same (IfcWallStandardCase → IfcWall, IfcFurnishingElement → IfcFurniture) | Storey | Stored mesh |
| Model groups | `IfcGroup` + `IfcRelAssignsToGroup` (exported members only) | same | none | none |

Bodies come from the same meshes the 3D view shows (`GeometryCache.shared.parts`, fine detail).
Each mesh part becomes one representation item, styled with its material. Vertices are welded
on a 1 µm grid and degenerate triangles are dropped. IFC2X3 uses `IfcFacetedBrep` when every
part is closed and `IfcFaceBasedSurfaceModel` otherwise. IFC4 `IfcTriangulatedFaceSet.Closed` is
set from an edge-manifold check.

**Not exported** (listed in `IFCExportReport.skipped` with a reason): views, sheets, schedules,
annotation and detail elements, grids and reference planes, room separation and area lines,
areas, unenclosed rooms, imported CAD, elements of secondary design options, elements outside
the chosen phase (created later, or demolished by then), and elements hidden in the chosen view
(`visibleInViewID`, evaluated with `VisibilityResolver`).

**Split by storey** writes `"<base> - <Level>.ifc"` per storey. Each file has the full
project/site/building context and one storey. Terrain goes into the lowest storey's file.

## Types

| Instance category | IFC2X3 type | IFC4 type |
|---|---|---|
| Walls | `IfcWallType` | `IfcWallType` |
| Floors, pads | `IfcSlabType` | `IfcSlabType` |
| Ceilings | `IfcCoveringType` CEILING | `IfcCoveringType` CEILING |
| Roofs | none (no IfcRoofType in 2X3) | `IfcRoofType` |
| Doors | `IfcDoorStyle` | `IfcDoorType` DOOR |
| Windows | `IfcWindowStyle` | `IfcWindowType` WINDOW |
| Columns | `IfcColumnType` COLUMN | `IfcColumnType` COLUMN |
| Beams | `IfcBeamType` BEAM | `IfcBeamType` BEAM |
| Stairs | none | `IfcStairType` |
| Railings | `IfcRailingType` | `IfcRailingType` |
| Furniture, casework | `IfcFurnitureType` | `IfcFurnitureType` |
| Plumbing fixtures | `IfcSanitaryTerminalType` | `IfcSanitaryTerminalType` |
| Lighting fixtures | `IfcLightFixtureType` | `IfcLightFixtureType` |
| Planting | `IfcBuildingElementProxyType` | `IfcGeographicElementType` |
| Generic | `IfcBuildingElementProxyType` | `IfcBuildingElementProxyType` |

Types are linked with `IfcRelDefinesByType`. In IFC4 they are also declared on the project with
`IfcRelDeclares`. A type's Name is the type name and its ElementType is the family name. Type
parameters go in the `Arcus_TypeParameters` property set (`HasPropertySets`). A type's GlobalId
is the type element's `ifcGUID`.

## Materials and styles

- One `IfcMaterial` per Arcus material that an exported element uses. IFC4 adds Description
  and Category (the material class).
- Compound types (walls, floors, pads, roofs, ceilings) produce an `IfcMaterialLayerSet` with
  the type name, with layers ordered exterior→interior or top→bottom. IFC4 layers carry Name =
  material, Description = Arcus layer function, and Category = LoadBearing / Insulation /
  Finish / Substrate / Membrane. IFC2X3 omits zero-thickness (membrane) layers because
  `IfcPositiveLengthMeasure` forbids them. The layer set is associated with the type.
- Walls: `IfcMaterialLayerSetUsage` AXIS2. OffsetFromReferenceLine is the signed offset of the
  exterior face from the location line. DirectionSense is NEGATIVE, because the exterior is on
  the +y side of the wall axis, or POSITIVE for flipped walls.
- Flat floors and pads: `IfcMaterialLayerSetUsage` AXIS3 NEGATIVE, offset = top of slab above
  the storey. Roofs, ceilings and sloped floors use the layer set directly.
- Other elements: one `IfcMaterial`, or several collected in an `IfcMaterialList` (IFC2X3) or
  `IfcMaterialConstituentSet` (IFC4).
- Colours: `IfcSurfaceStyle` (BOTH) with `IfcSurfaceStyleRendering` (material colour and
  transparency), attached with `IfcStyledItem`. IFC2X3 goes through an
  `IfcPresentationStyleAssignment`. Elements without a material use the category colour.

## Property sets and quantities

| Element | Common property set | Properties |
|---|---|---|
| Wall | `Pset_WallCommon` | Reference (type name), IsExternal (type Function = Exterior), LoadBearing (Structural), FireRating (type Fire Rating, if set) |
| Slab | `Pset_SlabCommon` | Reference, LoadBearing |
| Covering | `Pset_CoveringCommon` | Reference |
| Roof | `Pset_RoofCommon` | Reference, IsExternal = TRUE |
| Door / Window | `Pset_DoorCommon` / `Pset_WindowCommon` | Reference, IsExternal (from the host wall), FireRating |
| Space | `Pset_SpaceCommon` | Reference (room number), IsExternal = FALSE |
| Column | `Pset_ColumnCommon` | Reference, LoadBearing (TRUE for structural columns) |
| Beam | `Pset_BeamCommon` | Reference, LoadBearing = TRUE |
| Stair / Railing | `Pset_StairCommon` / `Pset_RailingCommon` | Reference (Height for railings) |
| Proxy | `Pset_BuildingElementProxyCommon` | Reference |

Every exported element also gets **`Arcus_Parameters`**: every instance parameter with a
value, formatted as Arcus displays it (`IfcLabel`, or `IfcText` for long or multi-line values).
Duplicate names get a `(2)` suffix. Values are text, so units appear as formatted (e.g.
"3000 mm").

Base quantities come from `QuantityEngine` (option `includeBaseQuantities`). The quantity set is
named `Qto_<Class>BaseQuantities` in IFC4 and `BaseQuantities` in IFC2X3:

| Element | Quantities |
|---|---|
| Wall | Length, Width, Height, NetSideArea, NetVolume |
| Slab | Width (thickness), Perimeter, NetArea, NetVolume |
| Covering | Width, NetArea |
| Roof | NetArea |
| Door / Window | Width, Height, Area |
| Space | Height, NetPerimeter, NetFloorArea, NetVolume |
| Column / Beam / Stair | Length, NetVolume |
| Railing | Length |

Classification (option `includeClassification`): `Element.classification` becomes an
`IfcClassification` (Name = system) plus an `IfcClassificationReference` (code, title), linked
with `IfcRelAssociatesClassification`. Types are classified the same way.

## GUID policy

- Every exported element, type and level uses its own `ifcGUID`.
- Every derived entity gets `IFCGUID.deterministic(seed)`, so re-exports are stable:

| Entity | Seed |
|---|---|
| IfcSite / IfcBuilding | `<projectGUID>/site`, `<projectGUID>/building` |
| Opening, voids, fills | `<insertGUID>/opening`, `/voids`, `/fills` |
| Property set and its relation | `<ownerGUID>/pset/<name>` and `.../rel` |
| Element quantities | `<elementGUID>/qto` and `/qto/rel` |
| Containment / space aggregation | `<storeyGUID>/contains`, `<storeyGUID>/aggregates/spaces` |
| Type relation | `<typeGUID>/definesByType` |
| Material / classification relations | `<projectGUID>/associatesMaterial/<key>`, `<projectGUID>/classification/<system|code|title>` |
| Group assignment | `<groupGUID>/assigns` |

- Import keeps the file's GlobalIds: created elements, levels and references take the IFC
  GlobalId as their `ifcGUID`. If a GlobalId is invalid, already used in the model, or repeated
  in the file, the element gets a deterministic replacement and the report warns. So
  export → import → export keeps product GUIDs (tested for both schemas).

## Import: entity mapping

Units come from `IfcUnitAssignment`: SI prefixes (MILLI, CENTI, …) and conversion-based units
(FOOT, INCH, or any `IfcMeasureWithUnit` factor). Lengths are scaled to meters. Plane-angle units
are used for parametric trims. Placements follow `IfcLocalPlacement` chains through
`PlacementRelTo` (with a cycle and depth guard), using `IfcAxis2Placement3D`/`2D`.
`IfcGridPlacement` is not supported and is reported.

| IFC | Arcus (`mapToNative = true`) | Conditions (otherwise reference) |
|---|---|---|
| `IfcBuildingStorey` | Existing level within `targetLevelMatchTolerance` of the storey's placement elevation; otherwise a new level (unique name, storey GUID) plus a floor plan view | none |
| `IfcWall`, `IfcWallStandardCase`, `IfcWallElementedCase` | Wall (centre line, unconnected height, base offset from the level). Flipped if the layer set usage is POSITIVE. LoadBearing is read from `Pset_WallCommon`. | Straight `Axis` (or a box-shaped body when there is no axis). Every body vertex lies on one of the two faces, except at the ends (join caps) or inside openings of the wall. Thickness 10 mm – 5 m. |
| Wall type | Reuse an Arcus wall type with the IFC type name and the same thickness. Otherwise reuse any wall type with identical layers. Otherwise create one named after the IFC type or layer set, or **"Imported <mm> mm"** with one structure layer. | Layers come from the layer set when their thicknesses add up to the wall thickness. Function comes from the IFC4 Description or Category, else the thickest layer is structure. |
| `IfcSlab` FLOOR / BASESLAB (or NOTDEFINED, unless the type says otherwise) | Floor: sketch from the top-face outline (holes kept), offset = top above the level, type found or created by thickness and layers as for walls | Body must be a vertical prism (top and bottom face areas equal within 2%, clean outline loops) |
| `IfcSpace` | Room: Name = LongName (or Name), Number = Name when LongName is set. Placement point = centroid of the largest bottom triangle (inside the footprint). Limit offset = body height. | none |
| `IfcDoor`, `IfcWindow` (+ StandardCase) | Door or window hosted in the native wall whose opening it fills. Family comes from the ObjectType prefix ("Family: Type") if loaded, else "Door - Single Flush" / "Window - Casement". Type is the family type with matching Width/Height, or **"Imported <W> x <H>"**. Location and sill come from the opening (or body) projected on the wall. Hand/facing flip come from the placement axes. | Fills an opening (`IfcRelFillsElement` + `IfcRelVoidsElement`) of a wall that became native, and OverallWidth/Height (or body extents) are plausible |
| `IfcColumn` (+ StandardCase) | Column: rectangular (width × depth, rotation) or round (diameter) prism. Type matched by size (swapped width/depth changes rotation by 90°), else "Imported …". | Vertical prism with a rectangle or circle outline |
| `IfcBeam` (+ StandardCase) | Beam: horizontal box, top-justified, type matched or created by width × depth | Body is an axis-aligned horizontal box |
| Everything else, and every mapping failure | Immutable `.ifcReference` element: world-space mesh in `ReferenceGeometryData`, `ifcType` = IFC class, `properties` = GlobalId, IfcClass, Name, ObjectType, Description, Tag, TypeName and every property/quantity flattened as `"Pset.Prop" = value` (length/area/volume measures converted to meters). The level comes from containment. `Element.source` records the format, file, GlobalId, class and the same attributes. | none |

The following apply to every created element:

- Mark comes from `Arcus_Parameters.Mark`, else from the IFC Tag.
- Comments come from `Arcus_Parameters.Comments`.
- Classification comes from `IfcRelAssociatesClassification`.
- Materials are matched by name, or created with the element's surface colour.

With `mapToNative = false`, every product becomes a reference element.

### Supported geometry on import

- `IfcExtrudedAreaSolid` with `IfcRectangleProfileDef`, `IfcRectangleHollowProfileDef`,
  `IfcCircleProfileDef`, `IfcCircleHollowProfileDef`, `IfcIShapeProfileDef`,
  `IfcArbitraryClosedProfileDef` and `IfcArbitraryProfileDefWithVoids`. Curves can be
  `IfcPolyline`, `IfcIndexedPolyCurve` (line and arc segments), `IfcCompositeCurve` (polylines,
  trimmed lines, trimmed circles) or `IfcCircle`.
- `IfcFacetedBrep` (+ WithVoids: outer shell only), `IfcClosedShell` / `IfcOpenShell`, faces with
  inner bounds.
- `IfcTriangulatedFaceSet` (with PnIndex; the IFC4 and IFC4x3 attribute orders are both
  detected) and `IfcPolygonalFaceSet` (faces with voids).
- `IfcShellBasedSurfaceModel` and `IfcFaceBasedSurfaceModel`.
- `IfcMappedItem`: origin, then `IfcCartesianTransformationOperator3D` (uniform or
  non-uniform, and 2D).
- `IfcCsgSolid` / `IfcBlock`.
- `IfcBooleanResult` / `IfcBooleanClippingResult`: **first operand only**, with a warning.

The `Body` representation is used when present. Otherwise the first non-annotation
representation is used, with `Box` as the last resort.

### Robustness

- The parser is single-pass and linear in time and memory. A 50 MB synthetic file with 61k
  entities and 10k tessellated products parses in about 4 s and imports in about 6 s in a debug
  build.
- Limits (`IFCImportOptions.limits`): entity count, list nesting depth, string length and file
  size.
- Malformed, truncated or hostile input throws `IFCError` with a line number and never crashes.
  Placement cycles, recursive mapped items, dangling references, out-of-range indices and
  non-finite or absurd values are skipped with warnings.
- The report counts every entity (`entityCount`), native elements by category, references by
  IFC class, and `unsupported` items by class: geometry types that couldn't be evaluated,
  rooted non-product objects, and unfilled openings in native walls.

## Known limitations

- No boolean kernel. Openings in reference geometry show only if the source tessellation
  already has them. Openings without a door or window in native walls are not recreated
  (counted as unsupported).
- Advanced B-reps, NURBS, swept disk solids, revolved and tapered solids, and most parametric
  profiles are not evaluated.
- Roofs export as a single `IfcRoof` body and import as reference geometry, not native roofs.
  Stairs, railings, furniture, fixtures and terrain also import as reference geometry.
- Curved (arc) walls import as reference geometry. IFC2X3 exports them as `IfcWall` with a
  faceted B-rep and a tessellated axis.
- Wall location lines always import as *Wall Centerline*. Wall joins are recomputed by Arcus
  from the axis endpoints.
- IFC2X3 exports shared coordinates through a property set, not a map conversion. The importer
  does not apply `IfcMapConversion`.
- `IfcGridPlacement` is not evaluated.
- Parameter values in `Arcus_Parameters` are formatted text, not typed measures.
- Some Arcus meshes are not edge-manifold: walls whose opening reaches the wall base, roofs and
  stairs. They export as `IfcFaceBasedSurfaceModel` (IFC2X3) or with `Closed = .F.` (IFC4).

## Manual validation with buildingSMART

Arcus never uploads files anywhere. To check an export against the official schema and rules:

1. In Arcus, export with the schema you need (IFC4 Reference View is recommended) and save the
   file locally.
2. Open the buildingSMART validation service in a browser
   (https://validate.buildingsmart.org, which needs a free buildingSMART account) and upload
   the `.ifc` file **yourself**.
3. Check the report sections:
   - **Syntax**: Part 21 syntax. Arcus's writer should always pass.
   - **Schema**: entity and attribute conformance to IFC2X3 / IFC4.
   - **Normative rules / implementer agreements**: GUID uniqueness, spatial containment, units
     and so on.
   - **Industry practices**: warnings only.
4. Report failures together with the file and the Arcus version. For regressions, add a failing
   case to `Arcus/Tests/IFCTests` (the goldens are in `Fixtures/golden-*.ifc`; regenerate them
   with `ARCUS_REGENERATE_IFC_GOLDENS=1 swift test --filter GoldenTests` only for intentional
   changes, and review the diff).

For viewer spot checks, open the file in any free IFC viewer and compare storeys, element counts,
property sets and the coloured geometry against the Arcus model.
