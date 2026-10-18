// Exports a family document: parameters (with formulas), types, reference planes, labelled dimensions, geometry and
// plan symbols. UNVERIFIED against a running Revit; see README.md. Public Revit API only.
//
// Parametric coordinates by flexing: the exporter measures every exported coordinate (reference plane positions,
// extrusion profile points and extents, symbolic line points, rectangular openings) for the family's current type,
// then changes each length parameter by a small amount inside a transaction that is always rolled back, regenerates,
// and measures again. The change of each coordinate per unit change of each parameter gives a linear expression such
// as "-Width / 2 - Frame Width". Coefficients are snapped to multiples of 1/8; anything that does not respond
// linearly is written as a plain number. The family document is never modified.
#nullable enable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using Autodesk.Revit.DB;
using Arcus.Bridge.Schema;

namespace Arcus.Bridge.Export
{
    internal sealed class FamilyExporter
    {
        private readonly Document fam;
        private readonly FamilyManager fm;
        private readonly ExportOptions options;
        private readonly ExportLog log;
        private readonly Func<ElementId?, string?> materialRef;

        /// <summary>Measured coordinates (feet) for the base type.</summary>
        private Dictionary<string, double> baseValues = new();
        /// <summary>Coordinate key → (parameter name → d coordinate / d parameter).</summary>
        private readonly Dictionary<string, Dictionary<string, double>> coefficients = new();
        /// <summary>Base values (feet) of the parameters that were flexed.</summary>
        private readonly Dictionary<string, double> flexedValues = new();

        /// <param name="materialRef">Maps a material of the family document to an exchange material id (or null).</param>
        public FamilyExporter(Document familyDocument, ExportOptions options, ExportLog log, Func<ElementId?, string?> materialRef)
        {
            fam = familyDocument;
            fm = familyDocument.FamilyManager;
            this.options = options;
            this.log = log;
            this.materialRef = materialRef;
        }

        public XFamily Export(string id, string? uniqueId, string name, bool includeTypes)
        {
            Family owner = fam.OwnerFamily;
            Category? category = owner.FamilyCategory;
            string key = Categories.Key(Ids.CategoryOf(category));
            var parameters = fm.GetParameters().ToList();
            var xf = new XFamily
            {
                Id = id,
                UniqueId = uniqueId,
                Name = name,
                Category = key,
                RevitCategory = category?.Name,
                HostKind = key == "doors" || key == "windows" ? "wall" : "none",
                DefinitionIncluded = true,
                Parameters = parameters.Select(ToExchange).ToList(),
            };
            if (includeTypes) xf.Types = Types(parameters);

            FamilyType? baseType = fm.CurrentType ?? fm.Types.Cast<FamilyType>().FirstOrDefault();
            var flexable = parameters.Where(p => p.StorageType == StorageType.Double && string.IsNullOrEmpty(p.Formula) && !p.IsReporting
                                                 && Params.DataType(p.Definition) == "length").ToList();
            Measure(baseType, flexable);

            xf.ReferencePlanes = ReferencePlanes();
            xf.Dimensions = Dimensions();
            xf.Geometry = ExportGeometry();
            xf.PlanLines = PlanLines();
            xf.Opening = ExportOpening();
            return xf;
        }

        // MARK: Parameters and types

        private static XFamilyParameter ToExchange(FamilyParameter p)
        {
            Definition def = p.Definition;
            BuiltInParameter bip = (def as InternalDefinition)?.BuiltInParameter ?? BuiltInParameter.INVALID;
            string? builtIn = bip == BuiltInParameter.FAMILY_WIDTH_PARAM || bip == BuiltInParameter.DOOR_WIDTH || bip == BuiltInParameter.WINDOW_WIDTH ? "width"
                : bip == BuiltInParameter.FAMILY_HEIGHT_PARAM || bip == BuiltInParameter.DOOR_HEIGHT || bip == BuiltInParameter.WINDOW_HEIGHT ? "height" : null;
            return new XFamilyParameter
            {
                Name = def.Name,
                DataType = Params.DataType(def),
                IsInstance = p.IsInstance,
                Group = Params.Group(def),
                Formula = string.IsNullOrWhiteSpace(p.Formula) ? null : p.Formula,
                IsBuiltIn = bip != BuiltInParameter.INVALID ? true : (bool?)null,
                IsShared = p.IsShared ? true : (bool?)null,
                IsReporting = p.IsReporting ? true : (bool?)null,
                BuiltIn = builtIn,
            };
        }

        private List<XFamilyType> Types(List<FamilyParameter> parameters)
        {
            var list = new List<XFamilyType>();
            foreach (FamilyType t in fm.Types)
            {
                string tn = string.IsNullOrWhiteSpace(t.Name) ? fam.Title : t.Name;
                var values = new Dictionary<string, object?>();
                foreach (FamilyParameter p in parameters)
                {
                    if (!string.IsNullOrEmpty(p.Formula) || p.IsReporting || !t.HasValue(p)) continue;
                    string dt = Params.DataType(p.Definition);
                    object? v = null;
                    if (p.StorageType == StorageType.Double) { double? d = t.AsDouble(p); if (d.HasValue) v = Params.SI(d.Value, dt); }
                    else if (p.StorageType == StorageType.Integer) { int? i = t.AsInteger(p); if (i.HasValue) v = dt == "yesNo" ? (object)(i.Value != 0) : i.Value; }
                    else if (p.StorageType == StorageType.String) v = t.AsString(p);
                    else if (p.StorageType == StorageType.ElementId && dt == "material")
                    {
                        string? m = materialRef(t.AsElementId(p));
                        if (m != null) v = new Dictionary<string, string> { ["materialId"] = m };
                    }
                    if (v != null) values[p.Definition.Name] = v;
                }
                list.Add(new XFamilyType { Id = "type:" + tn, Name = tn, Values = values });
            }
            return list;
        }

        // MARK: Flexing

        private void Measure(FamilyType? baseType, List<FamilyParameter> flexable)
        {
            baseValues = RunRolledBack("Arcus Bridge: measure", () =>
            {
                if (baseType != null) fm.CurrentType = baseType;
                fam.Regenerate();
                return Collect();
            }) ?? new Dictionary<string, double>();
            if (!options.FlexFamilies || baseType == null) return;
            foreach (FamilyParameter p in flexable)
            {
                string pn = p.Definition.Name;
                double v = baseType.AsDouble(p) ?? 0;
                double delta = Math.Max(0.25, Math.Abs(v) * 0.25); // feet
                Dictionary<string, double>? flexed = RunRolledBack("Arcus Bridge: flex " + pn, () =>
                {
                    fm.CurrentType = baseType;
                    fm.Set(p, v + delta);
                    fam.Regenerate();
                    return Collect();
                });
                if (flexed == null)
                {
                    log.Warn($"Family “{fam.Title}”: parameter “{pn}” could not be flexed; geometry that depends on it is exported at its current size.");
                    continue;
                }
                flexedValues[pn] = v;
                foreach (KeyValuePair<string, double> kv in baseValues)
                {
                    if (!flexed.TryGetValue(kv.Key, out double f)) continue;
                    double c = (f - kv.Value) / delta;
                    if (Math.Abs(c) < 1e-6) continue;
                    if (!coefficients.TryGetValue(kv.Key, out Dictionary<string, double>? map)) coefficients[kv.Key] = map = new Dictionary<string, double>();
                    map[pn] = c;
                }
            }
        }

        /// <summary>Runs <paramref name="work"/> in a transaction that is always rolled back. Returns null on failure.</summary>
        private Dictionary<string, double>? RunRolledBack(string name, Func<Dictionary<string, double>> work)
        {
            using var t = new Transaction(fam, name);
            FailureHandlingOptions fho = t.GetFailureHandlingOptions();
            fho.SetFailuresPreprocessor(new SilentFailures());
            fho.SetClearAfterRollback(true);
            t.SetFailureHandlingOptions(fho);
            try
            {
                t.Start();
                return work();
            }
            catch (Exception)
            {
                return null;
            }
            finally
            {
                if (t.GetStatus() == TransactionStatus.Started) t.RollBack();
            }
        }

        private sealed class SilentFailures : IFailuresPreprocessor
        {
            public FailureProcessingResult PreprocessFailures(FailuresAccessor accessor)
            {
                foreach (FailureMessageAccessor f in accessor.GetFailureMessages())
                {
                    if (f.GetSeverity() == FailureSeverity.Warning) accessor.DeleteWarning(f);
                    else return FailureProcessingResult.ProceedWithRollBack;
                }
                return FailureProcessingResult.Continue;
            }
        }

        /// <summary>Scalar for a measured coordinate: a number (meters) or a linear expression of the flexed parameters.</summary>
        private object S(string key, double fallbackFeet)
        {
            double b = baseValues.TryGetValue(key, out double bv) ? bv : fallbackFeet;
            if (!coefficients.TryGetValue(key, out Dictionary<string, double>? coefs) || coefs.Count == 0) return U.M(b);
            var terms = new List<(string Name, double Coef)>();
            double constant = b;
            foreach (KeyValuePair<string, double> kv in coefs.OrderBy(k => k.Key, StringComparer.Ordinal))
            {
                double snapped = Math.Round(kv.Value * 8) / 8;
                if (Math.Abs(snapped - kv.Value) > 1e-3) return U.M(b); // not a simple linear relation
                if (snapped == 0) continue;
                terms.Add((kv.Key, snapped));
                constant -= snapped * flexedValues[kv.Key];
            }
            return terms.Count == 0 ? U.M(b) : Expression(terms, U.M(constant));
        }

        private static string Expression(List<(string Name, double Coef)> terms, double constantMeters)
        {
            var sb = new StringBuilder();
            foreach ((string name, double coef) in terms)
            {
                string n = Regex.IsMatch(name, "^[A-Za-z_][A-Za-z0-9_ ]*$") ? name : "[" + name + "]";
                double a = Math.Abs(coef);
                string term = Math.Abs(a - 1) < 1e-9 ? n : Math.Abs(a - 0.5) < 1e-9 ? n + " / 2" : Math.Abs(a - 0.25) < 1e-9 ? n + " / 4" : Num(a) + " * " + n;
                if (sb.Length == 0) sb.Append(coef < 0 ? "-" + term : term);
                else sb.Append(coef < 0 ? " - " : " + ").Append(term);
            }
            if (Math.Abs(constantMeters) > 1e-9) sb.Append(constantMeters < 0 ? " - " : " + ").Append(Num(Math.Abs(constantMeters))).Append(" m");
            return sb.ToString();
        }

        private static string Num(double v) => v.ToString("0.#########", CultureInfo.InvariantCulture);

        // MARK: Measurement

        private IEnumerable<T> Elements<T>(Type nativeClass) where T : Element =>
            new FilteredElementCollector(fam).OfClass(nativeClass).OfType<T>();

        /// <summary>Axis index (0 x, 1 y, 2 z) of a direction aligned with a family axis; -1 otherwise.</summary>
        private static int Axis(XYZ n)
        {
            if (Math.Abs(Math.Abs(n.Z) - 1) < 1e-6) return 2;
            if (Math.Abs(Math.Abs(n.Y) - 1) < 1e-6) return 1;
            if (Math.Abs(Math.Abs(n.X) - 1) < 1e-6) return 0;
            return -1;
        }
        private static double C(XYZ p, int axis) => axis == 0 ? p.X : axis == 1 ? p.Y : p.Z;
        /// <summary>Profile coordinates in the plane normal to <paramref name="axis"/>: z → (x, y), y → (x, z), x → (y, z).</summary>
        private static (double U, double V) UV(XYZ p, int axis) => axis == 2 ? (p.X, p.Y) : axis == 1 ? (p.X, p.Z) : (p.Y, p.Z);

        private IEnumerable<SymbolicCurve> PlanSymbols() =>
            Elements<SymbolicCurve>(typeof(CurveElement)).Where(sc => sc.SketchPlane != null && Axis(sc.SketchPlane.GetPlane().Normal) == 2);

        private static void CurveKeys(Dictionary<string, double> m, string k, Curve c, int axis)
        {
            void Put(string suffix, XYZ p) { var (u, v) = UV(p, axis); m[k + suffix + ":u"] = u; m[k + suffix + ":v"] = v; }
            Put(":s", c.GetEndPoint(0));
            Put(":e", c.GetEndPoint(1));
            if (c is Arc arc)
            {
                Put(":m", arc.Evaluate(0.5, true));
                Put(":c", arc.Center);
                m[k + ":r"] = arc.Radius;
            }
        }

        private Dictionary<string, double> Collect()
        {
            var m = new Dictionary<string, double>();
            foreach (ReferencePlane rp in Elements<ReferencePlane>(typeof(ReferencePlane)))
            {
                int axis = Axis(rp.Normal);
                if (axis >= 0) m["rp:" + Ids.Of(rp.Id)] = C(rp.BubbleEnd, axis);
            }
            foreach (Extrusion e in Elements<Extrusion>(typeof(GenericForm)))
            {
                Plane pl = e.Sketch.SketchPlane.GetPlane();
                int axis = Axis(pl.Normal);
                if (axis < 0) continue;
                string k = "ex:" + Ids.Of(e.Id);
                double o = C(pl.Origin, axis), sgn = C(pl.Normal, axis) > 0 ? 1 : -1;
                m[k + ":from"] = o + sgn * e.StartOffset;
                m[k + ":to"] = o + sgn * e.EndOffset;
                int i = 0;
                foreach (CurveArray arr in e.Sketch.Profile)
                {
                    int j = 0;
                    foreach (Curve c in arr) { CurveKeys(m, $"{k}:{i}:{j}", c, axis); j++; }
                    i++;
                }
            }
            foreach (SymbolicCurve sc in PlanSymbols()) CurveKeys(m, "sl:" + Ids.Of(sc.Id), sc.GeometryCurve, 2);
            foreach (Opening op in Elements<Opening>(typeof(Opening)))
            {
                if (!op.IsRectBoundary || op.BoundaryRect == null || op.BoundaryRect.Count != 2) continue;
                XYZ a = op.BoundaryRect[0], b = op.BoundaryRect[1];
                string k = "op:" + Ids.Of(op.Id);
                m[k + ":x0"] = Math.Min(a.X, b.X); m[k + ":x1"] = Math.Max(a.X, b.X);
                m[k + ":z0"] = Math.Min(a.Z, b.Z); m[k + ":z1"] = Math.Max(a.Z, b.Z);
            }
            return m;
        }

        // MARK: Reference planes and dimensions

        private static string PlaneName(ReferencePlane rp) => string.IsNullOrWhiteSpace(rp.Name) ? "Reference Plane " + Ids.Of(rp.Id) : rp.Name;

        private List<XReferencePlane> ReferencePlanes()
        {
            var list = new List<XReferencePlane>();
            foreach (ReferencePlane rp in Elements<ReferencePlane>(typeof(ReferencePlane)))
            {
                int axis = Axis(rp.Normal);
                if (axis < 0)
                {
                    log.Warn($"Family “{fam.Title}”: reference plane “{PlaneName(rp)}” is not aligned with the family axes and was not exported.");
                    continue;
                }
                list.Add(new XReferencePlane
                {
                    Name = PlaneName(rp),
                    Axis = axis == 0 ? "x" : axis == 1 ? "y" : "z",
                    Offset = S("rp:" + Ids.Of(rp.Id), C(rp.BubbleEnd, axis)),
                    Strength = Strength(rp),
                    DefinesOrigin = rp.get_Parameter(BuiltInParameter.DATUM_PLANE_DEFINES_ORIGIN)?.AsInteger() == 1 ? true : (bool?)null,
                });
            }
            return list;
        }

        /// <summary>"Is Reference" value. UNVERIFIED: assumes ELEM_REFERENCE_NAME stores FamilyInstanceReferenceType values.</summary>
        private static string? Strength(ReferencePlane rp)
        {
            Parameter? p = rp.get_Parameter(BuiltInParameter.ELEM_REFERENCE_NAME);
            if (p == null || !p.HasValue || p.StorageType != StorageType.Integer) return null;
            int raw = p.AsInteger();
            if (!Enum.IsDefined(typeof(FamilyInstanceReferenceType), raw)) return null;
            string s = ((FamilyInstanceReferenceType)raw).ToString();
            switch (s)
            {
                case "StrongReference": return "strong";
                case "WeakReference": return "weak";
                case "NotAReference": return "notAReference";
                default: return char.ToLowerInvariant(s[0]) + s.Substring(1); // Left → left, CenterLeftRight → centerLeftRight, …
            }
        }

        private List<XFamilyDimension> Dimensions()
        {
            var list = new List<XFamilyDimension>();
            foreach (Dimension d in Elements<Dimension>(typeof(Dimension)))
            {
                if (d.References == null || d.References.Size != 2) continue;
                var planes = new List<ReferencePlane>();
                foreach (Reference r in d.References) if (fam.GetElement(r.ElementId) is ReferencePlane rp) planes.Add(rp);
                if (planes.Count != 2) continue;
                string? label = null;
                try { label = d.FamilyLabel?.Definition.Name; } catch (Autodesk.Revit.Exceptions.ApplicationException) { }
                list.Add(new XFamilyDimension { PlaneA = PlaneName(planes[0]), PlaneB = PlaneName(planes[1]), Label = label });
            }
            return list;
        }

        // MARK: Geometry

        private string? AssociatedName(Element e, BuiltInParameter bip)
        {
            Parameter? p = e.get_Parameter(bip);
            return p == null ? null : fm.GetAssociatedFamilyParameter(p)?.Definition.Name;
        }

        private static List<string> Levels(FamilyElementVisibility? v)
        {
            var list = new List<string>();
            if (v == null) return list;
            if (v.IsShownInCoarse) list.Add("coarse");
            if (v.IsShownInMedium) list.Add("medium");
            if (v.IsShownInFine) list.Add("fine");
            return list;
        }

        private object[] Pt(string key, XYZ p, int axis)
        {
            var (u, v) = UV(p, axis);
            return new[] { S(key + ":u", u), S(key + ":v", v) };
        }

        private XProfileCurve? ProfileCurve(string k, Curve c, int axis)
        {
            if (c is Line)
                return new XProfileCurve { Type = "line", Start = Pt(k + ":s", c.GetEndPoint(0), axis), End = Pt(k + ":e", c.GetEndPoint(1), axis) };
            if (c is Arc arc && arc.IsBound)
                return new XProfileCurve
                {
                    Type = "arc",
                    Start = Pt(k + ":s", arc.GetEndPoint(0), axis), Mid = Pt(k + ":m", arc.Evaluate(0.5, true), axis), End = Pt(k + ":e", arc.GetEndPoint(1), axis),
                    Center = Pt(k + ":c", arc.Center, axis), Radius = S(k + ":r", arc.Radius),
                };
            if (c is Arc circle)
                return new XProfileCurve { Type = "circle", Center = Pt(k + ":c", circle.Center, axis), Radius = S(k + ":r", circle.Radius) };
            return null;
        }

        private List<XFamilyGeometry> ExportGeometry()
        {
            var list = new List<XFamilyGeometry>();
            Options opt = MeshBuilder.GeometryOptions();
            foreach (GenericForm form in Elements<GenericForm>(typeof(GenericForm)))
            {
                string kind = form is Extrusion ? "extrusion" : form is Blend ? "blend" : form is Revolution ? "revolution"
                    : form is SweptBlend ? "sweptBlend" : form is Sweep ? "sweep" : "form";
                string name = string.IsNullOrWhiteSpace(form.Name) ? $"{kind} {Ids.Of(form.Id)}" : form.Name;
                FamilyElementVisibility? vis = null;
                try { vis = form.GetVisibility(); } catch (Autodesk.Revit.Exceptions.ApplicationException) { }
                string? materialParameter = AssociatedName(form, BuiltInParameter.MATERIAL_ID_PARAM);
                var g = new XFamilyGeometry
                {
                    Name = name,
                    IsVoid = form.IsSolid ? (bool?)null : true,
                    MaterialParameter = materialParameter,
                    MaterialId = materialParameter == null ? materialRef(form.get_Parameter(BuiltInParameter.MATERIAL_ID_PARAM)?.AsElementId()) : null,
                    Subcategory = form.Subcategory?.Name,
                    VisibilityParameter = AssociatedName(form, BuiltInParameter.IS_VISIBLE_PARAM),
                    VisibleAt = vis == null ? null : Levels(vis),
                    VisibleInPlan = vis == null ? (bool?)null : vis.IsShownInTopBottom,
                    SourceKind = kind,
                };
                int axis = form is Extrusion ex0 ? Axis(ex0.Sketch.SketchPlane.GetPlane().Normal) : -1;
                if (form is Extrusion e && axis >= 0)
                {
                    string k = "ex:" + Ids.Of(e.Id);
                    Plane pl = e.Sketch.SketchPlane.GetPlane();
                    double o = C(pl.Origin, axis), sgn = C(pl.Normal, axis) > 0 ? 1 : -1;
                    g.Kind = "extrusion";
                    g.ExtrusionAxis = axis == 0 ? "x" : axis == 1 ? "y" : "z";
                    g.Extent = new List<object> { S(k + ":from", o + sgn * e.StartOffset), S(k + ":to", o + sgn * e.EndOffset) };
                    g.Loops = new List<List<XProfileCurve>>();
                    int i = 0;
                    foreach (CurveArray arr in e.Sketch.Profile)
                    {
                        var loop = new List<XProfileCurve>();
                        int j = 0;
                        foreach (Curve c in arr)
                        {
                            XProfileCurve? pc = ProfileCurve($"{k}:{i}:{j}", c, axis);
                            if (pc != null) loop.Add(pc);
                            else loop.AddRange(Tessellated(c, axis)); // splines/ellipses: tessellated, fixed size
                            j++;
                        }
                        if (loop.Count > 0) g.Loops.Add(loop);
                        i++;
                    }
                    list.Add(g);
                    continue;
                }
                // Blends, revolves, sweeps and non-axis-aligned extrusions: tessellated (Arcus approximates them).
                var mb = new MeshBuilder(200_000);
                mb.Add(form.get_Geometry(opt));
                if (mb.Triangles == 0)
                {
                    log.Warn($"Family “{fam.Title}”: “{name}” ({kind}) has no geometry to export{(form.IsSolid ? "" : " (voids are not tessellated)")}.");
                    continue;
                }
                g.Kind = "mesh";
                g.Positions = mb.Positions;
                g.Indices = mb.Indices;
                list.Add(g);
            }
            // Nested family instances: tessellated. (Free-form elements are GenericForms and handled above.)
            foreach (FamilyInstance nested in Elements<FamilyInstance>(typeof(FamilyInstance)))
            {
                var mb = new MeshBuilder(200_000);
                mb.Add(nested.get_Geometry(opt));
                if (mb.Triangles == 0) continue;
                list.Add(new XFamilyGeometry
                {
                    Kind = "mesh", Name = nested.Symbol?.FamilyName + ": " + nested.Name, SourceKind = "nestedFamily",
                    Positions = mb.Positions, Indices = mb.Indices,
                });
            }
            return list;
        }

        /// <summary>A curve without a line/arc form (spline, ellipse) as straight segments in profile coordinates (meters).</summary>
        private static IEnumerable<XProfileCurve> Tessellated(Curve c, int axis)
        {
            IList<XYZ> pts = c.Tessellate();
            for (int i = 0; i + 1 < pts.Count; i++)
            {
                var (u0, v0) = UV(pts[i], axis);
                var (u1, v1) = UV(pts[i + 1], axis);
                yield return new XProfileCurve { Type = "line", Start = new object[] { U.M(u0), U.M(v0) }, End = new object[] { U.M(u1), U.M(v1) } };
            }
        }

        private List<XFamilyLine> PlanLines()
        {
            var list = new List<XFamilyLine>();
            foreach (SymbolicCurve sc in PlanSymbols())
            {
                FamilyElementVisibility? vis = null;
                try { vis = sc.GetVisibility(); } catch (Autodesk.Revit.Exceptions.ApplicationException) { }
                if (vis != null && !vis.IsShownInTopBottom) continue;
                XProfileCurve? pc = ProfileCurve("sl:" + Ids.Of(sc.Id), sc.GeometryCurve, 2);
                if (pc == null) continue;
                list.Add(new XFamilyLine { Curve = pc, Subcategory = sc.Subcategory?.Name, VisibleAt = vis == null ? null : Levels(vis) });
            }
            return list;
        }

        private XOpening? ExportOpening()
        {
            Opening? op = Elements<Opening>(typeof(Opening)).FirstOrDefault(o => o.IsRectBoundary && o.BoundaryRect != null && o.BoundaryRect.Count == 2);
            if (op == null) return null; // Arcus derives the opening from the Left/Right/Bottom/Top planes or Width/Height.
            string k = "op:" + Ids.Of(op.Id);
            XYZ a = op.BoundaryRect[0], b = op.BoundaryRect[1];
            return new XOpening
            {
                XMin = S(k + ":x0", Math.Min(a.X, b.X)), XMax = S(k + ":x1", Math.Max(a.X, b.X)),
                ZMin = S(k + ":z0", Math.Min(a.Z, b.Z)), ZMax = S(k + ":z1", Math.Max(a.Z, b.Z)),
            };
        }
    }
}
