// Arcus Bridge — Revit add-in (public Revit API only). UNVERIFIED against a running Revit; see README.md.
#nullable enable
using System;
using System.Reflection;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;

namespace Arcus.Bridge
{
    /// <summary>Adds the "Arcus" ribbon panel (Add-Ins tab) with the two export commands.</summary>
    public sealed class ArcusBridgeApp : IExternalApplication
    {
        public Result OnStartup(UIControlledApplication application)
        {
            try
            {
                RibbonPanel panel = application.CreateRibbonPanel("Arcus");
                string assembly = Assembly.GetExecutingAssembly().Location;

                var project = new PushButtonData("ArcusExportProject", "Export to\nArcus", assembly, typeof(ExportProjectCommand).FullName)
                {
                    ToolTip = "Export this project to an Arcus Exchange file (.arcusx) that Arcus opens as editable elements.",
                    LongDescription = "Writes levels, grids, materials, wall/floor/roof/ceiling types, walls, floors, ceilings, roofs, doors, "
                        + "windows, rooms, columns, beams, stairs, railings, loadable families and reference meshes for anything else.",
                    AvailabilityClassName = typeof(ProjectDocumentAvailability).FullName,
                };
                var family = new PushButtonData("ArcusExportFamily", "Export Family\nto Arcus", assembly, typeof(ExportFamilyCommand).FullName)
                {
                    ToolTip = "Export this family (parameters, formulas, types, reference planes and geometry) to an Arcus Exchange file.",
                    AvailabilityClassName = typeof(FamilyDocumentAvailability).FullName,
                };
                panel.AddItem(project);
                panel.AddItem(family);
                return Result.Succeeded;
            }
            catch (Exception ex)
            {
                TaskDialog.Show("Arcus Bridge", "The Arcus panel could not be created: " + ex.Message);
                return Result.Failed;
            }
        }

        public Result OnShutdown(UIControlledApplication application) => Result.Succeeded;
    }

    /// <summary>"Export to Arcus" is available in project documents.</summary>
    public sealed class ProjectDocumentAvailability : IExternalCommandAvailability
    {
        public bool IsCommandAvailable(UIApplication applicationData, CategorySet selectedCategories)
        {
            Document? doc = applicationData.ActiveUIDocument?.Document;
            return doc != null && !doc.IsFamilyDocument;
        }
    }

    /// <summary>"Export Family to Arcus" is available in the Family Editor.</summary>
    public sealed class FamilyDocumentAvailability : IExternalCommandAvailability
    {
        public bool IsCommandAvailable(UIApplication applicationData, CategorySet selectedCategories)
        {
            Document? doc = applicationData.ActiveUIDocument?.Document;
            return doc != null && doc.IsFamilyDocument;
        }
    }
}
