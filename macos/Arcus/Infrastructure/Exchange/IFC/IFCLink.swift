import Foundation
import ArcusGeometry
import ArcusDomain

/// F67: Link IFC. Reads an IFC file into an empty scratch model, keeping every product as exact reference geometry
/// (nothing is converted to native elements), and returns its display geometry for a linked model. The host project is
/// never touched; the caller adds or reloads the link in its own transaction.
public enum IFCLink {
    public static func content(_ data: Data, fileName: String, progress: @Sendable (Double) -> Void = { _ in },
                               isCancelled: @Sendable () -> Bool = { false }) throws -> (parts: [LinkedModelPart], elementCount: Int, report: IFCImportReport) {
        let tx = TransactionContext(model: BIMModel(), name: "Link IFC")
        var options = IFCImportOptions()
        options.mapToNative = false
        let report = try IFCImporter.importFile(data, fileName: fileName, into: tx, options: options, progress: { progress($0 * 0.8) }, isCancelled: isCancelled)
        let model = try tx.commit().model
        let (parts, count) = LinkedGeometry.content(of: model, isCancelled: isCancelled)
        progress(1)
        return (parts, count, report)
    }
}
