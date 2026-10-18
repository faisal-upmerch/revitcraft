// Arcus Bridge commands. UNVERIFIED against a running Revit; see README.md.
#nullable enable
using System;
using System.IO;
using System.Linq;
using System.Text;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using Arcus.Bridge.Export;
using Arcus.Bridge.Schema;

namespace Arcus.Bridge
{
    /// <summary>Exports the active project to a .arcusx file.</summary>
    [Transaction(TransactionMode.Manual)]
    public sealed class ExportProjectCommand : IExternalCommand
    {
        public Result Execute(ExternalCommandData commandData, ref string message, ElementSet elements)
        {
            Document doc = commandData.Application.ActiveUIDocument.Document;
            if (doc.IsFamilyDocument)
            {
                message = "Use “Export Family to Arcus” in the Family Editor.";
                return Result.Failed;
            }
            string? path = SaveDialog.Ask(doc, Path.GetFileNameWithoutExtension(doc.PathName) is { Length: > 0 } n ? n : doc.Title);
            if (path == null) return Result.Cancelled;
            try
            {
                var options = new ExportOptions();
                var exporter = new ProjectExporter(doc, options, commandData.Application.Application);
                ExchangeDocument result = exporter.Export();
                JsonOutput.Write(result, path);
                TaskDialog.Show("Arcus Bridge", Summary(result, exporter.Log, path));
                return Result.Succeeded;
            }
            catch (Exception ex)
            {
                message = "Export to Arcus failed: " + ex.Message;
                return Result.Failed;
            }
        }

        internal static string Summary(ExchangeDocument d, ExportLog log, string path)
        {
            var sb = new StringBuilder();
            sb.AppendLine("Saved " + Path.GetFileName(path) + ".");
            void Count(string label, int? n) { if (n.GetValueOrDefault() > 0) sb.AppendLine($"{n} {label}"); }
            Count("levels", d.Levels?.Count); Count("grids", d.Grids?.Count); Count("walls", d.Walls?.Count);
            Count("floors", d.Floors?.Count); Count("ceilings", d.Ceilings?.Count); Count("roofs", d.Roofs?.Count);
            Count("doors and windows", d.Inserts?.Count); Count("rooms", d.Rooms?.Count); Count("columns", d.Columns?.Count);
            Count("beams", d.Beams?.Count); Count("stairs", d.Stairs?.Count); Count("railings", d.Railings?.Count);
            Count("components", d.Components?.Count); Count("families", d.Families?.Count); Count("reference meshes", d.Meshes?.Count);
            if (log.Warnings.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine($"{log.Warnings.Count} note(s):");
                foreach (string w in log.Warnings.Take(15)) sb.AppendLine("• " + w);
                if (log.Warnings.Count > 15) sb.AppendLine("…");
            }
            sb.AppendLine();
            sb.AppendLine("Import the file in Arcus (Arcus Exchange, .arcusx).");
            return sb.ToString();
        }
    }

    /// <summary>Exports the family open in the Family Editor to a .arcusx file.</summary>
    [Transaction(TransactionMode.Manual)]
    public sealed class ExportFamilyCommand : IExternalCommand
    {
        public Result Execute(ExternalCommandData commandData, ref string message, ElementSet elements)
        {
            Document doc = commandData.Application.ActiveUIDocument.Document;
            if (!doc.IsFamilyDocument)
            {
                message = "Open a family in the Family Editor first, or use “Export to Arcus” for projects.";
                return Result.Failed;
            }
            string? path = SaveDialog.Ask(doc, Path.GetFileNameWithoutExtension(doc.PathName) is { Length: > 0 } n ? n : doc.Title);
            if (path == null) return Result.Cancelled;
            try
            {
                var log = new ExportLog();
                var materials = new MaterialTable(doc);
                var exporter = new FamilyExporter(doc, new ExportOptions(), log, materials.Reference);
                Family owner = doc.OwnerFamily;
                string name = Path.GetFileNameWithoutExtension(doc.PathName) is { Length: > 0 } fn ? fn : doc.Title;
                XFamily family = exporter.Export(Ids.Of(owner.Id), owner.UniqueId, name, includeTypes: true);
                var result = new ExchangeDocument
                {
                    Format = "arcus-exchange",
                    SchemaVersion = ExportOptions.SchemaVersion,
                    DocumentKind = "family",
                    Generator = ExportOptions.Generator(commandData.Application.Application),
                    Source = new XSource { FileName = Path.GetFileName(doc.PathName), Path = doc.PathName, DocumentId = owner.UniqueId, Application = "Autodesk Revit" },
                    Materials = materials.All,
                    Families = new() { family },
                };
                JsonOutput.Write(result, path);
                TaskDialog.Show("Arcus Bridge", ExportProjectCommand.Summary(result, log, path));
                return Result.Succeeded;
            }
            catch (Exception ex)
            {
                message = "Export Family to Arcus failed: " + ex.Message;
                return Result.Failed;
            }
        }
    }

    internal static class SaveDialog
    {
        /// <summary>Asks where to save the .arcusx file (Revit's own save dialog). Returns null when cancelled.</summary>
        public static string? Ask(Document doc, string suggestedName)
        {
            var dialog = new FileSaveDialog("Arcus Exchange (*.arcusx)|*.arcusx")
            {
                Title = "Export to Arcus",
                InitialFileName = suggestedName + ".arcusx",
            };
            if (dialog.Show() != ItemSelectionDialogResult.Confirmed) return null;
            ModelPath? selected = dialog.GetSelectedModelPath();
            if (selected == null) return null;
            string path = ModelPathUtils.ConvertModelPathToUserVisiblePath(selected);
            return path.EndsWith(".arcusx", StringComparison.OrdinalIgnoreCase) ? path : path + ".arcusx";
        }
    }
}
