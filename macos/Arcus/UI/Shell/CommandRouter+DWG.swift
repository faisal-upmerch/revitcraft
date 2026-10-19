import AppKit
import ArcusApplication
import ArcusCAD

// DWG: routing for File ▸ Export ▸ CAD Formats ▸ DWG (Dialogs/DWGExportDialog.swift).

extension CommandRouter {
    /// Runs one of the DWG commands; true when handled.
    func dwgPerform(_ id: CommandID) -> Bool {
        switch id {
        case .exportDWG: state.presented = .exportDWG
        default: return false
        }
        return true
    }

    /// Why a DWG command can't run now, or nil.
    func dwgDisabledReason(_ id: CommandID) -> String? {
        guard id == .exportDWG else { return nil }
        if let r = DWGExporter.unavailableReason() { return r }
        return model.sheets.isEmpty && !model.views.contains(where: { $0.view?.kind != .threeD }) ? "Create a view or sheet to export." : nil
    }
}
