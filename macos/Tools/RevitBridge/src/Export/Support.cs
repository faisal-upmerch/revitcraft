// Shared export helpers: options, identities, units, curves, meshes, materials, parameters, JSON output.
// UNVERIFIED against a running Revit; see README.md. Public Revit API only.
#nullable enable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using Autodesk.Revit.DB;
using Arcus.Bridge.Schema;

namespace Arcus.Bridge.Export
{
    public sealed class ExportOptions
    {
        public const string SchemaVersion = "1.0";
        public const string BridgeVersion = "0.1.0";
        /// <summary>Export loadable family definitions (opens each family with Document.EditFamily).</summary>
        public bool IncludeFamilyDefinitions { get; set; } = true;
        /// <summary>Write tessellated meshes for elements without a native Arcus equivalent.</summary>
        public bool IncludeMeshes { get; set; } = true;
        /// <summary>Fit family coordinates to parameters by flexing (see FamilyExporter).</summary>
        public bool FlexFamilies { get; set; } = true;
        /// <summary>Largest total number of mesh triangles written.</summary>
        public int MaxMeshTriangles { get; set; } = 3_000_000;

        public static XGenerator Generator(Autodesk.Revit.ApplicationServices.Application app) => new XGenerator
        {
            Name = "Arcus Bridge",
            Version = BridgeVersion,
            Host = "Autodesk Revit " + app.VersionNumber,
            ExportedAt = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture),
        };
    }

    public sealed class ExportLog
    {
        public List<string> Warnings { get; } = new();
        private readonly HashSet<string> seen = new();
        public void Warn(string message) { if (seen.Add(message)) Warnings.Add(message); }
    }

    internal static class Ids
    {
        public static string Of(ElementId id)
        {
#if REVIT2023_OR_EARLIER
            return id.IntegerValue.ToString(CultureInfo.InvariantCulture);
#else
            return id.Value.ToString(CultureInfo.InvariantCulture);
#endif
        }

        public static long Value(ElementId id)
        {
#if REVIT2023_OR_EARLIER
            return id.IntegerValue;
#else
            return id.Value;
#endif
        }

        public static string? OrNull(ElementId? id) => id == null || id == ElementId.InvalidElementId ? null : Of(id);

        public static BuiltInCategory CategoryOf(Element e) => e.Category == null ? BuiltInCategory.INVALID : (BuiltInCategory)(int)Value(e.Category.Id);
        public static BuiltInCategory CategoryOf(Category? c) => c == null ? BuiltInCategory.INVALID : (BuiltInCategory)(int)Value(c.Id);
    }

    /// <summary>Unit conversion (Revit internal feet → meters) and geometry conversion.</summary>
    internal static class U
    {
        public const double Foot = 0.3048;
        public static double M(double feet) => Round(feet * Foot);
        public static double Round(double v) => IsFinite(v) ? Math.Round(v, 9) : 0;
        public static bool IsFinite(double v) => !double.IsNaN(v) && !double.IsInfinity(v); // double.IsFinite is not in .NET Framework 4.8
        public static double[] P2(XYZ p) => new[] { M(p.X), M(p.Y) };
        public static double[] P3(XYZ p) => new[] { M(p.X), M(p.Y), M(p.Z) };
        public static double[] V3(XYZ v) => new[] { Round(v.X), Round(v.Y), Round(v.Z) };

        /// <summary>Plan curves for a Revit curve: lines and arcs map directly; circles become "circle"; others are tessellated.</summary>
        public static List<XCurve> Curves(Curve c)
        {
            var out1 = new List<XCurve>();
            switch (c)
            {
                case Line line when line.IsBound:
                    if (line.GetEndPoint(0).DistanceTo(line.GetEndPoint(1)) > 1e-6)
                        out1.Add(new XCurve { Type = "line", Start = P2(line.GetEndPoint(0)), End = P2(line.GetEndPoint(1)) });
                    break;
                case Arc arc when !arc.IsBound:
                    out1.Add(new XCurve { Type = "circle", Center = P2(arc.Center), Radius = M(arc.Radius) });
                    break;
                case Arc arc:
                    out1.Add(new XCurve { Type = "arc", Start = P2(arc.GetEndPoint(0)), Mid = P2(arc.Evaluate(0.5, true)), End = P2(arc.GetEndPoint(1)) });
                    break;
                default:
                    IList<XYZ> pts = c.Tessellate();
                    for (int i = 0; i + 1 < pts.Count; i++)
                        if (pts[i].DistanceTo(pts[i + 1]) > 1e-6)
                            out1.Add(new XCurve { Type = "line", Start = P2(pts[i]), End = P2(pts[i + 1]) });
                    break;
            }
            return out1;
        }

        public static List<List<XCurve>> Loops(CurveArrArray profile)
        {
            var loops = new List<List<XCurve>>();
            foreach (CurveArray arr in profile)
            {
                var loop = new List<XCurve>();
                foreach (Curve c in arr) loop.AddRange(Curves(c));
                if (loop.Count > 0) loops.Add(loop);
            }
            return loops;
        }

        public static XTransform Placement(Transform t) => new XTransform
        {
            Origin = P3(t.Origin), BasisX = V3(t.BasisX), BasisY = V3(t.BasisY), BasisZ = V3(t.BasisZ),
        };

        /// <summary>Unit tangent at the start of a curve, in plan.</summary>
        public static XYZ StartTangent(Curve c)
        {
            XYZ d = c.ComputeDerivatives(0, true).BasisX;
            var flat = new XYZ(d.X, d.Y, 0);
            return flat.GetLength() > 1e-9 ? flat.Normalize() : XYZ.BasisX;
        }

        public static string? Text(Element e, BuiltInParameter p)
        {
            string? s = e.get_Parameter(p)?.AsString();
            return string.IsNullOrWhiteSpace(s) ? null : s;
        }
        public static double? Length(Element e, BuiltInParameter p)
        {
            Parameter? prm = e.get_Parameter(p);
            return prm != null && prm.HasValue && prm.StorageType == StorageType.Double ? M(prm.AsDouble()) : (double?)null;
        }
        public static bool? Flag(Element e, BuiltInParameter p)
        {
            Parameter? prm = e.get_Parameter(p);
            return prm != null && prm.HasValue && prm.StorageType == StorageType.Integer ? prm.AsInteger() != 0 : (bool?)null;
        }
        public static ElementId? RefId(Element e, BuiltInParameter p)
        {
            Parameter? prm = e.get_Parameter(p);
            if (prm == null || !prm.HasValue || prm.StorageType != StorageType.ElementId) return null;
            ElementId id = prm.AsElementId();
            return id == ElementId.InvalidElementId ? null : id;
        }
    }

    /// <summary>Arcus category keys for Revit categories.</summary>
    internal static class Categories
    {
        public static string Key(BuiltInCategory c) => c switch
        {
            BuiltInCategory.OST_Walls => "walls",
            BuiltInCategory.OST_Doors => "doors",
            BuiltInCategory.OST_Windows => "windows",
            BuiltInCategory.OST_Floors => "floors",
            BuiltInCategory.OST_Ceilings => "ceilings",
            BuiltInCategory.OST_Roofs => "roofs",
            BuiltInCategory.OST_Stairs => "stairs",
            BuiltInCategory.OST_StairsRailing => "railings",
            BuiltInCategory.OST_Columns => "columns",
            BuiltInCategory.OST_StructuralColumns => "structuralColumns",
            BuiltInCategory.OST_StructuralFraming => "structuralFraming",
            BuiltInCategory.OST_Furniture => "furniture",
            BuiltInCategory.OST_FurnitureSystems => "furnitureSystems",
            BuiltInCategory.OST_Casework => "casework",
            BuiltInCategory.OST_GenericModel => "genericModels",
            BuiltInCategory.OST_PlumbingFixtures => "plumbingFixtures",
            BuiltInCategory.OST_SpecialityEquipment => "specialtyEquipment",
            BuiltInCategory.OST_Parking => "parking",
            BuiltInCategory.OST_Topography => "topography",
            _ => "other",
        };

        /// <summary>Family instance categories Arcus places as free-standing native components.</summary>
        public static readonly HashSet<string> Components = new() { "furniture", "furnitureSystems", "casework", "genericModels", "plumbingFixtures", "specialtyEquipment", "parking" };
    }

    /// <summary>Tessellates element geometry into a flat triangle list (meters).</summary>
    internal sealed class MeshBuilder
    {
        public List<double> Positions { get; } = new();
        public List<int> Indices { get; } = new();
        public int Triangles => Indices.Count / 3;
        private readonly int limit;
        public bool Truncated { get; private set; }

        public MeshBuilder(int maxTriangles) { limit = maxTriangles; }

        public static Options GeometryOptions() => new Options { DetailLevel = ViewDetailLevel.Fine, ComputeReferences = false, IncludeNonVisibleObjects = false };

        public void Add(GeometryElement? geometry, Transform? transform = null)
        {
            if (geometry == null) return;
            foreach (GeometryObject o in geometry)
            {
                switch (o)
                {
                    case Solid solid when solid.Faces.Size > 0:
                        foreach (Face f in solid.Faces)
                        {
                            Mesh? m = null;
                            try { m = f.Triangulate(); } catch (Autodesk.Revit.Exceptions.ApplicationException) { }
                            if (m != null) AddMesh(m, transform);
                        }
                        break;
                    case Mesh mesh:
                        AddMesh(mesh, transform);
                        break;
                    case GeometryInstance instance:
                        Add(instance.GetInstanceGeometry(), transform); // already in the parent's coordinates
                        break;
                }
            }
        }

        private void AddMesh(Mesh m, Transform? t)
        {
            if (Triangles + m.NumTriangles > limit) { Truncated = true; return; }
            int b = Positions.Count / 3;
            foreach (XYZ v in m.Vertices)
            {
                XYZ p = t == null ? v : t.OfPoint(v);
                Positions.Add(U.M(p.X)); Positions.Add(U.M(p.Y)); Positions.Add(U.M(p.Z));
            }
            for (int i = 0; i < m.NumTriangles; i++)
            {
                MeshTriangle tri = m.get_Triangle(i);
                Indices.Add(b + (int)tri.get_Index(0)); Indices.Add(b + (int)tri.get_Index(1)); Indices.Add(b + (int)tri.get_Index(2));
            }
        }

        public XMesh? ToMesh() => Triangles == 0 ? null : new XMesh { Positions = Positions, Indices = Indices };
    }

    /// <summary>Materials referenced by the export (id → XMaterial), added on first use.</summary>
    internal sealed class MaterialTable
    {
        private readonly Document doc;
        private readonly Dictionary<string, XMaterial> byId = new();
        public MaterialTable(Document doc) { this.doc = doc; }
        public List<XMaterial> All => byId.Values.ToList();

        /// <summary>Returns the exchange id of a material, exporting it on first use; null for no material.</summary>
        public string? Reference(ElementId? id)
        {
            if (id == null || id == ElementId.InvalidElementId) return null;
            string key = Ids.Of(id);
            if (byId.ContainsKey(key)) return key;
            if (doc.GetElement(id) is not Material m) return null;
            Color c = m.Color;
            byId[key] = new XMaterial
            {
                Id = key,
                UniqueId = m.UniqueId,
                Name = m.Name,
                MaterialClass = string.IsNullOrWhiteSpace(m.MaterialClass) ? null : m.MaterialClass,
                Color = c != null && c.IsValid ? $"#{c.Red:X2}{c.Green:X2}{c.Blue:X2}" : null,
                Transparency = Math.Max(0, Math.Min(100, m.Transparency)) / 100.0,
                Description = U.Text(m, BuiltInParameter.ALL_MODEL_DESCRIPTION),
                Manufacturer = U.Text(m, BuiltInParameter.ALL_MODEL_MANUFACTURER),
                Model = U.Text(m, BuiltInParameter.ALL_MODEL_MODEL),
                Mark = U.Text(m, BuiltInParameter.ALL_MODEL_MARK),
                Keynote = U.Text(m, BuiltInParameter.KEYNOTE_PARAM),
            };
            return key;
        }

        /// <summary>Material of another document (a family opened for export) mapped to this document's material with the same name.</summary>
        public string? ReferenceByName(Material? m)
        {
            if (m == null) return null;
            Material? local = new FilteredElementCollector(doc).OfClass(typeof(Material)).Cast<Material>().FirstOrDefault(x => x.Name == m.Name);
            return local == null ? null : Reference(local.Id);
        }
    }

    /// <summary>Parameter data types and SI conversion.</summary>
    internal static class Params
    {
        public static string DataType(Definition d)
        {
            ForgeTypeId t = d.GetDataType();
            if (t.Equals(SpecTypeId.Length)) return "length";
            if (t.Equals(SpecTypeId.Area)) return "area";
            if (t.Equals(SpecTypeId.Volume)) return "volume";
            if (t.Equals(SpecTypeId.Angle)) return "angle";
            if (t.Equals(SpecTypeId.Slope)) return "slope";
            if (t.Equals(SpecTypeId.Number)) return "number";
            if (t.Equals(SpecTypeId.Int.Integer)) return "integer";
            if (t.Equals(SpecTypeId.Currency)) return "currency";
            if (t.Equals(SpecTypeId.String.Text)) return "text";
            if (t.Equals(SpecTypeId.String.MultilineText)) return "multilineText";
            if (t.Equals(SpecTypeId.String.Url)) return "url";
            if (t.Equals(SpecTypeId.Boolean.YesNo)) return "yesNo";
            if (t.Equals(SpecTypeId.Reference.Material)) return "material";
            if (Category.IsBuiltInCategory(t)) return "familyType";
            return "other";
        }

        /// <summary>Converts a Revit internal value to SI for a parameter data type key.</summary>
        public static double SI(double v, string dataType) => dataType switch
        {
            "length" => U.Round(v * U.Foot),
            "area" => U.Round(v * U.Foot * U.Foot),
            "volume" => U.Round(v * U.Foot * U.Foot * U.Foot),
            _ => U.Round(v), // angles are radians; numbers and slopes are unitless (UNVERIFIED for slope)
        };

        public static string Group(Definition d)
        {
#if REVIT2023_OR_EARLIER
            switch (d.ParameterGroup)
            {
                case BuiltInParameterGroup.PG_CONSTRAINTS: return "constraints";
                case BuiltInParameterGroup.PG_CONSTRUCTION: return "construction";
                case BuiltInParameterGroup.PG_GRAPHICS: return "graphics";
                case BuiltInParameterGroup.PG_MATERIALS: return "materials";
                case BuiltInParameterGroup.PG_GEOMETRY: return "dimensions";
                case BuiltInParameterGroup.PG_STRUCTURAL: return "structural";
                case BuiltInParameterGroup.PG_IDENTITY_DATA: return "identity";
                case BuiltInParameterGroup.PG_PHASING: return "phasing";
                case BuiltInParameterGroup.PG_TEXT: return "text";
                case BuiltInParameterGroup.PG_IFC: return "ifc";
                default: return "other";
            }
#else
            ForgeTypeId g = d.GetGroupTypeId();
            if (g.Equals(GroupTypeId.Constraints)) return "constraints";
            if (g.Equals(GroupTypeId.Construction)) return "construction";
            if (g.Equals(GroupTypeId.Graphics)) return "graphics";
            if (g.Equals(GroupTypeId.Materials)) return "materials";
            if (g.Equals(GroupTypeId.Geometry)) return "dimensions";
            if (g.Equals(GroupTypeId.Structural)) return "structural";
            if (g.Equals(GroupTypeId.IdentityData)) return "identity";
            if (g.Equals(GroupTypeId.Phasing)) return "phasing";
            if (g.Equals(GroupTypeId.Text)) return "text";
            if (g.Equals(GroupTypeId.Ifc)) return "ifc";
            return "other";
#endif
        }

        /// <summary>Value of a project parameter in exchange form (SI number, bool, text or material reference).</summary>
        public static object? Value(Parameter p, MaterialTable materials)
        {
            if (!p.HasValue) return null;
            string dt = DataType(p.Definition);
            switch (p.StorageType)
            {
                case StorageType.Double: return SI(p.AsDouble(), dt);
                case StorageType.Integer: return dt == "yesNo" ? p.AsInteger() != 0 : (object)p.AsInteger();
                case StorageType.String: return p.AsString();
                case StorageType.ElementId:
                    string? m = dt == "material" ? materials.Reference(p.AsElementId()) : null;
                    return m == null ? null : new Dictionary<string, string> { ["materialId"] = m };
                default: return null;
            }
        }
    }

    internal static class JsonOutput
    {
        public static readonly JsonSerializerOptions Options = new()
        {
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            WriteIndented = false,
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        };

        public static void Write(ExchangeDocument document, string path)
        {
            string tmp = path + ".tmp";
            using (FileStream fs = File.Create(tmp)) JsonSerializer.Serialize(fs, document, Options);
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
        }
    }
}
