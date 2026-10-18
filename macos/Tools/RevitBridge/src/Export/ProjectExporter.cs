// Exports a Revit project to Arcus Exchange. UNVERIFIED against a running Revit; see README.md. Public Revit API only.
#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Autodesk.Revit.DB;
using Autodesk.Revit.DB.Architecture;
using Arcus.Bridge.Schema;
using RevitApp = Autodesk.Revit.ApplicationServices.Application;

namespace Arcus.Bridge.Export
{
    internal sealed class ProjectExporter
    {
        private readonly Document doc;
        private readonly ExportOptions options;
        private readonly RevitApp app;
        private readonly ExchangeDocument x = new();
        private readonly MaterialTable materials;
        public ExportLog Log { get; } = new();

        /// <summary>Elements written natively (excluded from the reference-mesh sweep).</summary>
        private readonly HashSet<ElementId> written = new();
        private readonly Dictionary<ElementId, XType> types = new();
        /// <summary>Loadable families used by exported doors, windows and components → symbols used.</summary>
        private readonly Dictionary<ElementId, HashSet<ElementId>> familySymbols = new();
        /// <summary>Walls exported as native basic walls (valid hosts).</summary>
        private readonly HashSet<ElementId> nativeWalls = new();
        /// <summary>Exported components by exchange id (for mesh fallbacks).</summary>
        private readonly Dictionary<string, FamilyInstance> componentElements = new();
        private int meshTriangles;

        public ProjectExporter(Document doc, ExportOptions options, RevitApp app)
        {
            this.doc = doc;
            this.options = options;
            this.app = app;
            materials = new MaterialTable(doc);
        }

        public ExchangeDocument Export()
        {
            x.Format = "arcus-exchange";
            x.SchemaVersion = ExportOptions.SchemaVersion;
            x.DocumentKind = "project";
            x.Generator = ExportOptions.Generator(app);
            string fileName = string.IsNullOrEmpty(doc.PathName) ? doc.Title + ".rvt" : Path.GetFileName(doc.PathName);
            x.Source = new XSource { FileName = fileName, Path = doc.PathName, DocumentId = doc.ProjectInformation?.UniqueId, Application = "Autodesk Revit " + app.VersionNumber };
            x.Units = ExportUnits();
            x.ProjectInfo = ExportProjectInfo();
            x.Levels = Levels();
            x.Grids = Grids();
            x.Walls = Walls();
            x.Floors = Slabs<Floor>(BuiltInParameter.FLOOR_HEIGHTABOVELEVEL_PARAM, "floors");
            x.Ceilings = Slabs<Ceiling>(BuiltInParameter.CEILING_HEIGHTABOVELEVEL_PARAM, "ceilings");
            x.Roofs = Roofs();
            x.Inserts = new List<XInsert>();
            x.Components = new List<XComponent>();
            x.Columns = new List<XColumn>();
            x.Beams = new List<XBeam>();
            x.Meshes = new List<XMeshElement>();
            FamilyInstances();
            x.Stairs = ExportStairs();
            x.Railings = Railings();
            x.Rooms = Rooms();
            x.Families = Families();
            if (options.IncludeMeshes) OtherElementsAsMeshes();
            x.Types = types.Values.ToList();
            x.Materials = materials.All;
            return x;
        }

        // MARK: Helpers

        private IEnumerable<T> All<T>() where T : Element => new FilteredElementCollector(doc).OfClass(typeof(T)).WhereElementIsNotElementType().OfType<T>();

        private XMesh? Tessellate(Element e)
        {
            if (!options.IncludeMeshes) return null;
            var mb = new MeshBuilder(Math.Max(0, options.MaxMeshTriangles - meshTriangles));
            mb.Add(e.get_Geometry(MeshBuilder.GeometryOptions()));
            if (mb.Truncated) Log.Warn("The mesh size limit was reached; some elements were exported without their shape.");
            meshTriangles += mb.Triangles;
            return mb.ToMesh();
        }

        private static string? Mark(Element e) => U.Text(e, BuiltInParameter.ALL_MODEL_MARK);
        private static string? Comments(Element e) => U.Text(e, BuiltInParameter.ALL_MODEL_INSTANCE_COMMENTS);
        private static string? LevelRef(ElementId? id) => Ids.OrNull(id);

        private double LevelElevation(ElementId? id) => id != null && doc.GetElement(id) is Level l ? l.ProjectElevation : 0;

        private XUnits ExportUnits()
        {
            ForgeTypeId unit = doc.GetUnits().GetFormatOptions(SpecTypeId.Length).GetUnitTypeId();
            bool imperial = unit.Equals(UnitTypeId.Feet) || unit.Equals(UnitTypeId.FeetFractionalInches) || unit.Equals(UnitTypeId.Inches)
                            || unit.Equals(UnitTypeId.FractionalInches);
            return new XUnits { System = imperial ? "imperial" : "metric" };
        }

        private XProjectInfo ExportProjectInfo()
        {
            ProjectInfo p = doc.ProjectInformation;
            var info = new XProjectInfo
            {
                Name = p.Name, Number = p.Number, ClientName = p.ClientName, Address = p.Address, Status = p.Status,
                IssueDate = p.IssueDate, Author = p.Author, Organization = OrganizationNameValue(p), BuildingName = p.BuildingName,
            };
            SiteLocation site = doc.SiteLocation;
            if (site != null)
            {
                info.Latitude = U.Round(site.Latitude * 180 / Math.PI);
                info.Longitude = U.Round(site.Longitude * 180 / Math.PI);
                info.Elevation = U.M(site.Elevation);
                info.SiteName = string.IsNullOrWhiteSpace(site.PlaceName) ? null : site.PlaceName;
            }
            // UNVERIFIED sign convention: ProjectPosition.Angle is the rotation from project north to true north.
            ProjectLocation? loc = doc.ActiveProjectLocation;
            if (loc != null) info.TrueNorthAngle = U.Round(loc.GetProjectPosition(XYZ.Zero).Angle);
            info.ProjectBasePoint = U.P3(BasePoint.GetProjectBasePoint(doc).Position);
            info.SurveyPoint = U.P3(BasePoint.GetSurveyPoint(doc).Position);
            return info;
        }

        private static string? OrganizationNameValue(ProjectInfo p) => string.IsNullOrWhiteSpace(p.OrganizationName) ? null : p.OrganizationName;

        // MARK: Datums

        private List<XLevel> Levels() => All<Level>().Select(l =>
        {
            written.Add(l.Id);
            return new XLevel
            {
                Id = Ids.Of(l.Id), UniqueId = l.UniqueId, Name = l.Name, Elevation = U.M(l.ProjectElevation),
                IsBuildingStorey = U.Flag(l, BuiltInParameter.LEVEL_IS_BUILDING_STORY),
                IsStructural = U.Flag(l, BuiltInParameter.LEVEL_IS_STRUCTURAL),
            };
        }).ToList();

        private List<XGrid> Grids()
        {
            var list = new List<XGrid>();
            foreach (Grid g in All<Grid>())
            {
                List<XCurve> cs = U.Curves(g.Curve);
                if (cs.Count == 0) continue;
                written.Add(g.Id);
                list.Add(new XGrid { Id = Ids.Of(g.Id), UniqueId = g.UniqueId, Name = g.Name, Curve = cs[0] });
            }
            return list;
        }

        // MARK: Types

        private static string LayerFunction(MaterialFunctionAssignment f) => f.ToString() switch
        {
            "Structure" => "structure",
            "StructuralDeck" => "structuralDeck",
            "Substrate" => "substrate",
            "Insulation" => "thermal",
            "Finish1" => "finish1",
            "Finish2" => "finish2",
            "Membrane" => "membrane",
            _ => "structure",
        };

        private static string Wrapping(string s) => s switch
        {
            "Exterior" => "exterior",
            "Interior" => "interior",
            "ExteriorAndInterior" => "both",
            _ => "doNotWrap",
        };

        private void Layers(CompoundStructure? cs, XType t)
        {
            if (cs == null) return;
            IList<CompoundStructureLayer> layers = cs.GetLayers();
            t.Layers = new List<XLayer>();
            for (int i = 0; i < layers.Count; i++)
            {
                CompoundStructureLayer l = layers[i];
                t.Layers.Add(new XLayer
                {
                    Function = LayerFunction(l.Function),
                    MaterialId = materials.Reference(l.MaterialId),
                    Thickness = U.M(l.Width),
                    Wraps = cs.ParticipatesInWrapping(i) ? true : (bool?)null,
                    IsVariable = cs.VariableLayerIndex == i ? true : (bool?)null,
                });
            }
            int first = cs.GetFirstCoreLayerIndex(), last = cs.GetLastCoreLayerIndex();
            if (first >= 0 && last >= first) { t.CoreStart = first; t.CoreEnd = last + 1; }
            t.WrappingAtInserts = Wrapping(cs.OpeningWrapping.ToString());
            t.WrappingAtEnds = Wrapping(cs.EndCap.ToString());
        }

        private XType TypeCommon(ElementType et, string category)
        {
            var t = new XType
            {
                Id = Ids.Of(et.Id), UniqueId = et.UniqueId, Name = et.Name, FamilyName = et.FamilyName, Category = category,
                TypeMark = U.Text(et, BuiltInParameter.ALL_MODEL_TYPE_MARK),
                Description = U.Text(et, BuiltInParameter.ALL_MODEL_DESCRIPTION),
                FireRating = U.Text(et, BuiltInParameter.FIRE_RATING),
            };
            types[et.Id] = t;
            return t;
        }

        private string WallTypeId(WallType wt)
        {
            if (types.ContainsKey(wt.Id)) return Ids.Of(wt.Id);
            XType t = TypeCommon(wt, "walls");
            t.Kind = wt.Kind == WallKind.Basic ? "basic" : wt.Kind == WallKind.Curtain ? "curtain" : wt.Kind == WallKind.Stacked ? "stacked" : "other";
            t.Function = wt.Function.ToString();
            t.Thickness = U.M(wt.Width);
            if (wt.Kind == WallKind.Basic) Layers(wt.GetCompoundStructure(), t);
            return t.Id!;
        }

        private string? HostType(ElementId typeId, string category)
        {
            if (typeId == ElementId.InvalidElementId) return null;
            if (types.ContainsKey(typeId)) return Ids.Of(typeId);
            if (doc.GetElement(typeId) is not HostObjAttributes ht) return null;
            XType t = TypeCommon(ht, category);
            Layers(ht.GetCompoundStructure(), t);
            return t.Id;
        }

        /// <summary>Column and beam types: section size from common type parameters, else from the symbol's bounding box.</summary>
        private string SectionType(FamilySymbol s, string category)
        {
            if (types.ContainsKey(s.Id)) return Ids.Of(s.Id);
            XType t = TypeCommon(s, category);
            double? P(params string[] names)
            {
                foreach (string n in names)
                {
                    Parameter? p = s.LookupParameter(n);
                    if (p != null && p.HasValue && p.StorageType == StorageType.Double && p.AsDouble() > 1e-6) return U.M(p.AsDouble());
                }
                return null;
            }
            double? d = P("d", "Diameter", "D");
            double? w = P("b", "Width", "B"), h = P("h", "Depth", "H");
            if (d.HasValue && !w.HasValue) t.Section = new XSection { Shape = "circle", Diameter = d };
            else if (w.HasValue && h.HasValue) t.Section = new XSection { Shape = "rectangle", Width = w, Depth = h };
            else
            {
                Log.Warn($"Type “{s.FamilyName}: {s.Name}” has no recognizable section parameters; Arcus will use a default size.");
            }
            t.MaterialId = materials.Reference(s.get_Parameter(BuiltInParameter.STRUCTURAL_MATERIAL_PARAM)?.AsElementId());
            return t.Id!;
        }

        // MARK: Walls, floors, ceilings, roofs

        private List<XWall> Walls()
        {
            var list = new List<XWall>();
            foreach (Wall w in All<Wall>())
            {
                if (w.IsStackedWallMember) continue; // exported with its stacked parent
                WallType wt = w.WallType;
                var xw = new XWall
                {
                    Id = Ids.Of(w.Id), UniqueId = w.UniqueId, TypeId = WallTypeId(wt), LevelId = LevelRef(w.LevelId),
                    Mark = Mark(w), Comments = Comments(w),
                };
                written.Add(w.Id);
                Curve? c = (w.Location as LocationCurve)?.Curve;
                if (c != null && U.Curves(c) is { Count: 1 } cs) xw.Curve = cs[0];
                if (wt.Kind != WallKind.Basic || xw.Curve == null)
                {
                    xw.Mesh = Tessellate(w);
                    list.Add(xw);
                    continue;
                }
                nativeWalls.Add(w.Id);
                var locationLine = (WallLocationLine)(w.get_Parameter(BuiltInParameter.WALL_KEY_REF_PARAM)?.AsInteger() ?? 0);
                xw.LocationLine = locationLine.ToString() switch
                {
                    "WallCenterline" => "wallCenterline",
                    "CoreCenterline" => "coreCenterline",
                    "FinishFaceExterior" => "finishFaceExterior",
                    "FinishFaceInterior" => "finishFaceInterior",
                    "CoreExterior" => "coreFaceExterior",
                    "CoreInterior" => "coreFaceInterior",
                    _ => "wallCenterline",
                };
                xw.BaseOffset = U.Length(w, BuiltInParameter.WALL_BASE_OFFSET);
                xw.TopLevelId = LevelRef(U.RefId(w, BuiltInParameter.WALL_HEIGHT_TYPE));
                xw.TopOffset = U.Length(w, BuiltInParameter.WALL_TOP_OFFSET);
                xw.UnconnectedHeight = U.Length(w, BuiltInParameter.WALL_USER_HEIGHT_PARAM);
                // Arcus: the exterior is to the left of the curve direction unless flipped. Derived from Wall.Orientation
                // (the exterior-facing normal) so it does not depend on Revit's own "flipped" convention.
                XYZ t = U.StartTangent(c!);
                var left = new XYZ(-t.Y, t.X, 0);
                xw.Flipped = w.Orientation.DotProduct(left) < 0;
                xw.Structural = U.Flag(w, BuiltInParameter.WALL_STRUCTURAL_SIGNIFICANT);
                xw.RoomBounding = U.Flag(w, BuiltInParameter.WALL_ATTR_ROOM_BOUNDING);
                xw.JoinAtStart = WallUtils.IsWallJoinAllowedAtEnd(w, 0);
                xw.JoinAtEnd = WallUtils.IsWallJoinAllowedAtEnd(w, 1);
                list.Add(xw);
            }
            return list;
        }

        /// <summary>Boundary loops of a sketch-based element (floors, ceilings, …) through its dependent Sketch.</summary>
        private List<List<XCurve>>? SketchLoops(Element e)
        {
            foreach (ElementId id in e.GetDependentElements(new ElementClassFilter(typeof(Sketch))))
            {
                if (doc.GetElement(id) is Sketch s && s.Profile != null && s.Profile.Size > 0) return U.Loops(s.Profile);
            }
            return null;
        }

        private List<XSlab> Slabs<T>(BuiltInParameter offset, string category) where T : Element
        {
            var list = new List<XSlab>();
            foreach (T e in All<T>())
            {
                written.Add(e.Id);
                var s = new XSlab
                {
                    Id = Ids.Of(e.Id), UniqueId = e.UniqueId, TypeId = HostType(e.GetTypeId(), category), LevelId = LevelRef(e.LevelId),
                    Boundary = SketchLoops(e), Offset = U.Length(e, offset),
                    Structural = category == "floors" ? U.Flag(e, BuiltInParameter.FLOOR_PARAM_IS_STRUCTURAL) : null,
                    Mark = Mark(e), Comments = Comments(e),
                };
                if (s.Boundary == null) s.Mesh = Tessellate(e);
                list.Add(s);
            }
            return list;
        }

        private List<XRoof> Roofs()
        {
            var list = new List<XRoof>();
            foreach (RoofBase r in new FilteredElementCollector(doc).OfCategory(BuiltInCategory.OST_Roofs).WhereElementIsNotElementType().OfType<RoofBase>())
            {
                written.Add(r.Id);
                var xr = new XRoof { Id = Ids.Of(r.Id), UniqueId = r.UniqueId, TypeId = HostType(r.GetTypeId(), "roofs"), Mark = Mark(r), Comments = Comments(r) };
                ElementId? baseLevel = U.RefId(r, BuiltInParameter.ROOF_BASE_LEVEL_PARAM) ?? r.LevelId;
                xr.LevelId = LevelRef(baseLevel);
                if (r is FootPrintRoof fr)
                {
                    xr.Kind = "footprint";
                    xr.BaseOffset = U.Length(r, BuiltInParameter.ROOF_LEVEL_OFFSET_PARAM);
                    xr.Footprint = new List<List<XCurve>>();
                    foreach (ModelCurveArray arr in fr.GetProfiles())
                    {
                        var loop = new List<XCurve>();
                        foreach (ModelCurve mc in arr)
                        {
                            bool slopes = fr.get_DefinesSlope(mc);
                            // UNVERIFIED: SlopeAngle is documented as the slope of the edge; it is treated as rise/run.
                            double angle = slopes ? Math.Atan(fr.get_SlopeAngle(mc)) : 0;
                            double overhang = U.M(fr.get_Overhang(mc));
                            foreach (XCurve c in U.Curves(mc.GeometryCurve))
                            {
                                c.DefinesSlope = slopes;
                                c.SlopeAngle = slopes ? U.Round(angle) : (double?)null;
                                c.Overhang = overhang;
                                loop.Add(c);
                            }
                        }
                        if (loop.Count > 0) xr.Footprint.Add(loop);
                    }
                }
                else
                {
                    xr.Kind = r is ExtrusionRoof ? "extrusion" : "other";
                    xr.Mesh = Tessellate(r);
                }
                list.Add(xr);
            }
            return list;
        }

        // MARK: Family instances

        private Dictionary<string, object?>? InstanceParameters(FamilyInstance fi)
        {
            var values = new Dictionary<string, object?>();
            foreach (Parameter p in fi.Parameters)
            {
                if (p.IsReadOnly || p.Definition is InternalDefinition { BuiltInParameter: not BuiltInParameter.INVALID }) continue;
                object? v = Params.Value(p, materials);
                if (v != null) values[p.Definition.Name] = v;
            }
            return values.Count == 0 ? null : values;
        }

        private void UseFamily(FamilySymbol s)
        {
            Family f = s.Family;
            if (!familySymbols.TryGetValue(f.Id, out HashSet<ElementId>? set)) familySymbols[f.Id] = set = new HashSet<ElementId>();
            set.Add(s.Id);
        }

        private void FamilyInstances()
        {
            foreach (FamilyInstance fi in All<FamilyInstance>())
            {
                if (fi.SuperComponent != null) continue; // nested: part of its parent's geometry
                string cat = Categories.Key(Ids.CategoryOf(fi));
                FamilySymbol sym = fi.Symbol;
                bool inPlace = sym.Family.IsInPlace;
                string? level = LevelRef(fi.LevelId != ElementId.InvalidElementId ? fi.LevelId : U.RefId(fi, BuiltInParameter.FAMILY_LEVEL_PARAM));
                if (inPlace) continue; // exported by the mesh sweep

                if ((cat == "doors" || cat == "windows") && fi.Host is Wall host && nativeWalls.Contains(host.Id))
                {
                    written.Add(fi.Id);
                    UseFamily(sym);
                    XYZ? p = (fi.Location as LocationPoint)?.Point;
                    x.Inserts!.Add(new XInsert
                    {
                        Id = Ids.Of(fi.Id), UniqueId = fi.UniqueId, Category = cat, TypeId = Ids.Of(sym.Id), HostId = Ids.Of(host.Id), LevelId = level,
                        Location = p == null ? null : U.P3(p), Transform = U.Placement(fi.GetTransform()),
                        Mark = Mark(fi), Comments = Comments(fi), Parameters = InstanceParameters(fi),
                    });
                }
                else if (cat == "columns" || cat == "structuralColumns")
                {
                    written.Add(fi.Id);
                    XYZ? p = (fi.Location as LocationPoint)?.Point;
                    x.Columns!.Add(new XColumn
                    {
                        Id = Ids.Of(fi.Id), UniqueId = fi.UniqueId, Category = cat, TypeId = SectionType(sym, cat),
                        LevelId = LevelRef(U.RefId(fi, BuiltInParameter.FAMILY_BASE_LEVEL_PARAM) ?? fi.LevelId),
                        Location = p == null ? null : U.P2(p), Rotation = U.Round((fi.Location as LocationPoint)?.Rotation ?? 0),
                        Transform = U.Placement(fi.GetTransform()),
                        BaseOffset = U.Length(fi, BuiltInParameter.FAMILY_BASE_LEVEL_OFFSET_PARAM),
                        TopLevelId = LevelRef(U.RefId(fi, BuiltInParameter.FAMILY_TOP_LEVEL_PARAM)),
                        TopOffset = U.Length(fi, BuiltInParameter.FAMILY_TOP_LEVEL_OFFSET_PARAM),
                        Slanted = fi.IsSlantedColumn ? true : (bool?)null,
                        Mark = Mark(fi), Comments = Comments(fi),
                        Mesh = fi.IsSlantedColumn ? Tessellate(fi) : null,
                    });
                }
                else if (cat == "structuralFraming" && fi.Location is LocationCurve lc)
                {
                    written.Add(fi.Id);
                    ElementId? refLevel = U.RefId(fi, BuiltInParameter.INSTANCE_REFERENCE_LEVEL_PARAM) ?? fi.LevelId;
                    double lv = LevelElevation(refLevel);
                    int z = fi.get_Parameter(BuiltInParameter.Z_JUSTIFICATION)?.AsInteger() ?? 0;
                    bool straight = lc.Curve is Line;
                    x.Beams!.Add(new XBeam
                    {
                        Id = Ids.Of(fi.Id), UniqueId = fi.UniqueId, TypeId = SectionType(sym, "structuralFraming"), LevelId = LevelRef(refLevel),
                        Curve = U.Curves(lc.Curve).FirstOrDefault(),
                        StartOffset = U.M(lc.Curve.GetEndPoint(0).Z - lv), EndOffset = U.M(lc.Curve.GetEndPoint(1).Z - lv),
                        ZJustification = z == 1 ? "center" : z == 3 ? "bottom" : "top", // 2 = origin, treated as top (UNVERIFIED values)
                        Mark = Mark(fi), Comments = Comments(fi),
                        Mesh = straight ? null : Tessellate(fi),
                    });
                }
                else if (Categories.Components.Contains(cat) && !(fi.Host is Wall))
                {
                    written.Add(fi.Id);
                    UseFamily(sym);
                    componentElements[Ids.Of(fi.Id)] = fi;
                    x.Components!.Add(new XComponent
                    {
                        Id = Ids.Of(fi.Id), UniqueId = fi.UniqueId, Category = cat, RevitCategory = fi.Category?.Name, TypeId = Ids.Of(sym.Id),
                        LevelId = level, Transform = U.Placement(fi.GetTransform()),
                        HostId = fi.Host == null ? null : Ids.Of(fi.Host.Id),
                        Mark = Mark(fi), Comments = Comments(fi), Parameters = InstanceParameters(fi),
                    });
                }
                // Everything else (curtain panels, MEP, entourage, wall-hosted components…) is exported by the mesh sweep.
            }
        }

        // MARK: Families

        private List<XFamily> Families()
        {
            var list = new List<XFamily>();
            foreach (KeyValuePair<ElementId, HashSet<ElementId>> kv in familySymbols)
            {
                if (doc.GetElement(kv.Key) is not Family family) continue;
                XFamily? xf = null;
                if (options.IncludeFamilyDefinitions && family.IsEditable && !family.IsInPlace)
                {
                    Document? fd = null;
                    try
                    {
                        Document famDoc = doc.EditFamily(family);
                        fd = famDoc;
                        var exporter = new FamilyExporter(famDoc, options, Log, id => materials.ReferenceByName(id == null ? null : famDoc.GetElement(id) as Material));
                        xf = exporter.Export(Ids.Of(family.Id), family.UniqueId, family.Name, includeTypes: false);
                    }
                    catch (Exception ex)
                    {
                        Log.Warn($"Family “{family.Name}” could not be opened for export ({ex.Message}); its instances are exported with their parameters only.");
                    }
                    finally
                    {
                        fd?.Close(false);
                    }
                }
                xf ??= new XFamily
                {
                    Id = Ids.Of(family.Id), UniqueId = family.UniqueId, Name = family.Name,
                    Category = Categories.Key(Ids.CategoryOf(family.FamilyCategory)), RevitCategory = family.FamilyCategory?.Name,
                    DefinitionIncluded = false,
                };
                if (xf.Parameters == null)
                {
                    // No definition: describe the type parameters from a symbol so sizes survive (Arcus generates simple
                    // parametric geometry for doors and windows exported this way).
                    FamilySymbol? first = kv.Value.Select(id => doc.GetElement(id)).OfType<FamilySymbol>().FirstOrDefault();
                    if (first != null) xf.Parameters = SymbolParameters(first);
                }
                // Project types: the project's current values are authoritative.
                xf.Types = new List<XFamilyType>();
                var typeParams = (xf.Parameters ?? new List<XFamilyParameter>()).Where(p => p.IsInstance != true && p.Formula == null && p.Name != null).ToList();
                foreach (ElementId sid in kv.Value)
                {
                    if (doc.GetElement(sid) is not FamilySymbol s) continue;
                    var values = new Dictionary<string, object?>();
                    foreach (XFamilyParameter p in typeParams)
                    {
                        Parameter? prm = s.LookupParameter(p.Name!);
                        object? v = prm == null ? null : Params.Value(prm, materials);
                        if (v != null) values[p.Name!] = v;
                    }
                    xf.Types.Add(new XFamilyType
                    {
                        Id = Ids.Of(s.Id), UniqueId = s.UniqueId, Name = s.Name, Values = values,
                        TypeMark = U.Text(s, BuiltInParameter.ALL_MODEL_TYPE_MARK),
                        Description = U.Text(s, BuiltInParameter.ALL_MODEL_DESCRIPTION),
                        FireRating = U.Text(s, BuiltInParameter.FIRE_RATING),
                    });
                }
                list.Add(xf);
            }
            // Families without an exported definition: give their free-standing instances a mesh fallback.
            var noDefinition = new HashSet<string>(list.Where(f => f.DefinitionIncluded == false).SelectMany(f => f.Types!.Select(t => t.Id!)));
            foreach (XComponent c in x.Components!)
            {
                if (c.TypeId != null && noDefinition.Contains(c.TypeId) && c.Id != null && componentElements.TryGetValue(c.Id, out FamilyInstance? e))
                    c.Mesh = Tessellate(e);
            }
            return list;
        }

        private static List<XFamilyParameter> SymbolParameters(FamilySymbol s)
        {
            var list = new List<XFamilyParameter>();
            foreach (Parameter p in s.Parameters)
            {
                BuiltInParameter bip = (p.Definition as InternalDefinition)?.BuiltInParameter ?? BuiltInParameter.INVALID;
                string? builtIn = bip == BuiltInParameter.FAMILY_WIDTH_PARAM || bip == BuiltInParameter.DOOR_WIDTH || bip == BuiltInParameter.WINDOW_WIDTH ? "width"
                    : bip == BuiltInParameter.FAMILY_HEIGHT_PARAM || bip == BuiltInParameter.DOOR_HEIGHT || bip == BuiltInParameter.WINDOW_HEIGHT ? "height" : null;
                if (bip != BuiltInParameter.INVALID && builtIn == null) continue; // other built-ins (identity data etc.) are not family parameters
                string dt = Params.DataType(p.Definition);
                if (dt == "other" || dt == "familyType" || p.IsReadOnly && builtIn == null) continue;
                list.Add(new XFamilyParameter { Name = p.Definition.Name, DataType = dt, IsInstance = false, Group = Params.Group(p.Definition), BuiltIn = builtIn,
                                                IsBuiltIn = builtIn != null ? true : (bool?)null });
            }
            return list;
        }

        // MARK: Stairs, railings, rooms

        private List<XStair> ExportStairs()
        {
            var list = new List<XStair>();
            foreach (Stairs s in All<Stairs>())
            {
                written.Add(s.Id);
                var xs = new XStair
                {
                    Id = Ids.Of(s.Id), UniqueId = s.UniqueId, LevelId = LevelRef(U.RefId(s, BuiltInParameter.STAIRS_BASE_LEVEL_PARAM)),
                    TopLevelId = LevelRef(U.RefId(s, BuiltInParameter.STAIRS_TOP_LEVEL_PARAM)),
                    BaseOffset = U.Length(s, BuiltInParameter.STAIRS_BASE_OFFSET), TopOffset = U.Length(s, BuiltInParameter.STAIRS_TOP_OFFSET),
                    UnconnectedHeight = U.M(s.Height), RiserCount = s.ActualRisersNumber,
                    RiserHeight = U.M(s.ActualRiserHeight), TreadDepth = U.M(s.ActualTreadDepth),
                    Mark = Mark(s), Comments = Comments(s), Mesh = Tessellate(s),
                };
                if (doc.GetElement(s.GetTypeId()) is StairsType st && !types.ContainsKey(st.Id))
                {
                    XType t = TypeCommon(st, "stairs");
                    t.Stair = new XStairTypeInfo { MaxRiserHeight = U.M(st.MaxRiserHeight), MinTreadDepth = U.M(st.MinTreadDepth) };
                }
                xs.TypeId = Ids.OrNull(s.GetTypeId());
                // Shape from the runs' walk lines (UNVERIFIED: assumes the stairs path is the run centerline).
                var runs = s.GetStairsRuns().Select(id => doc.GetElement(id) as StairsRun).Where(r => r != null).Cast<StairsRun>().ToList();
                var paths = runs.Select(r => r.GetStairsPath().FirstOrDefault()).ToList();
                if (runs.Count >= 1 && runs.Count <= 2 && paths.All(p => p is Line))
                {
                    Line p0 = (Line)paths[0]!;
                    XYZ d0 = new XYZ(p0.Direction.X, p0.Direction.Y, 0).Normalize();
                    xs.Origin = U.P2(p0.GetEndPoint(0));
                    xs.Direction = U.Round(Math.Atan2(d0.Y, d0.X));
                    xs.Width = U.M(runs[0].ActualRunWidth);
                    xs.FirstRunRisers = runs[0].ActualRisersNumber;
                    if (runs.Count == 1) xs.Shape = "straight";
                    else
                    {
                        Line p1 = (Line)paths[1]!;
                        XYZ d1 = new XYZ(p1.Direction.X, p1.Direction.Y, 0).Normalize();
                        double dot = d0.DotProduct(d1), cross = d0.X * d1.Y - d0.Y * d1.X;
                        XYZ between = p1.GetEndPoint(0) - p0.GetEndPoint(0);
                        if (Math.Abs(dot) < 0.05) { xs.Shape = "lShaped"; xs.TurnsLeft = cross > 0; }
                        else if (dot < -0.95) { xs.Shape = "uShaped"; xs.TurnsLeft = d0.X * between.Y - d0.Y * between.X > 0; }
                        else xs.Shape = "other";
                    }
                }
                else xs.Shape = "other";
                list.Add(xs);
            }
            return list;
        }

        private List<XRailing> Railings()
        {
            var list = new List<XRailing>();
            foreach (Railing r in All<Railing>())
            {
                written.Add(r.Id);
                if (doc.GetElement(r.GetTypeId()) is RailingType rt && !types.ContainsKey(rt.Id))
                {
                    XType t = TypeCommon(rt, "railings");
                    t.Railing = new XRailingTypeInfo { Height = U.M(rt.TopRailHeight) };
                }
                var path = new List<XCurve>();
                foreach (Curve c in r.GetPath()) path.AddRange(U.Curves(c));
                list.Add(new XRailing
                {
                    Id = Ids.Of(r.Id), UniqueId = r.UniqueId, TypeId = Ids.OrNull(r.GetTypeId()), LevelId = LevelRef(r.LevelId),
                    HostId = r.HasHost ? Ids.Of(r.HostId) : null, Path = path, Mark = Mark(r), Comments = Comments(r), Mesh = Tessellate(r),
                });
            }
            return list;
        }

        private List<XRoom> Rooms()
        {
            var list = new List<XRoom>();
            var rooms = new FilteredElementCollector(doc).OfCategory(BuiltInCategory.OST_Rooms).WhereElementIsNotElementType().OfType<Room>();
            foreach (Room r in rooms)
            {
                written.Add(r.Id);
                if (r.Area <= 0 || !(r.Location is LocationPoint lp)) continue; // unplaced or not enclosed
                list.Add(new XRoom
                {
                    Id = Ids.Of(r.Id), UniqueId = r.UniqueId, Name = U.Text(r, BuiltInParameter.ROOM_NAME), Number = r.Number,
                    LevelId = LevelRef(r.LevelId), Point = U.P2(lp.Point), UpperLimitLevelId = LevelRef(r.UpperLimit?.Id),
                    LimitOffset = U.M(r.LimitOffset), BaseOffset = U.M(r.BaseOffset),
                    Department = U.Text(r, BuiltInParameter.ROOM_DEPARTMENT), Comments = Comments(r),
                });
            }
            return list;
        }

        // MARK: Everything else

        private static readonly HashSet<BuiltInCategory> NotMeshed = new()
        {
            BuiltInCategory.OST_Rooms, BuiltInCategory.OST_Levels, BuiltInCategory.OST_Grids, BuiltInCategory.OST_Cameras,
            BuiltInCategory.OST_RvtLinks, BuiltInCategory.OST_Lines, BuiltInCategory.OST_SketchLines, BuiltInCategory.OST_RoomSeparationLines,
            BuiltInCategory.OST_IOSModelGroups, BuiltInCategory.OST_Materials, BuiltInCategory.OST_Areas, BuiltInCategory.OST_MEPSpaces,
        };

        private void OtherElementsAsMeshes()
        {
            foreach (Element e in new FilteredElementCollector(doc).WhereElementIsNotElementType())
            {
                if (written.Contains(e.Id) || e.ViewSpecific || e.Category == null || e.Category.CategoryType != CategoryType.Model) continue;
                if (NotMeshed.Contains(Ids.CategoryOf(e)) || e is Group || e is ElementType) continue;
                if (e is FamilyInstance fi && fi.SuperComponent != null) continue;
                XMesh? mesh = Tessellate(e);
                if (mesh == null) continue;
                string reason = e is Wall ? "curtain or stacked wall part" : e is FamilyInstance f2 && f2.Symbol.Family.IsInPlace ? "in-place family" : "no Arcus equivalent";
                x.Meshes!.Add(new XMeshElement
                {
                    Id = Ids.Of(e.Id), UniqueId = e.UniqueId, Category = Categories.Key(Ids.CategoryOf(e)), RevitCategory = e.Category.Name, Name = e.Name,
                    LevelId = LevelRef(e.LevelId), Positions = mesh.Positions, Indices = mesh.Indices, Reason = reason,
                });
            }
        }
    }
}
