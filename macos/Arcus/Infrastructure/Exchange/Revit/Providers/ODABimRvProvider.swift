#if ARCUS_HAS_ODA_BIMRV
import Foundation
import ArcusDomain
import ArcusBimRvBridge

// UNVERIFIED: this provider and the C++ bridge it calls (Tools/RevitBridge/BimRvBridge) have not been compiled against,
// or run with, the licensed ODA BimRv SDK: the SDK was not available on the development machine. The Swift half has been
// type-checked against a stub of the bridge's C API only. Follow "Verifying a BimRv-enabled build" in
// Docs/RevitInterop.md before shipping a build that opens .rvt/.rfa files directly.
//
// Design: the bridge reads the Revit file with the licensed SDK and writes an Arcus Exchange (.arcusx) translation to a
// private temporary file. The same `ArcusExchangeImporter` used for Arcus Bridge exports then creates native elements,
// so both routes share one mapping, one set of limits and one report format.

/// Direct .rvt/.rfa import through the licensed Open Design Alliance BimRv SDK.
public struct ODABimRvProvider: RevitImportProvider {
    public init() {}

    /// nil when the SDK initialized; otherwise the SDK's error message.
    private static let initialization: String? = {
        var err = ArcusBimRvError()
        if arcus_bimrv_initialize(&err) == 0 { return nil }
        let msg = message(err)
        return msg.isEmpty ? "unknown error" : msg
    }()

    private static func message(_ e: ArcusBimRvError) -> String {
        withUnsafeBytes(of: e.message) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    }

    public var name: String { "ODA BimRv SDK" + (sdkVersion.map { " \($0)" } ?? "") }
    public var isAvailable: Bool { Self.initialization == nil }
    public var unavailableReason: String? {
        Self.initialization.map { "The ODA BimRv SDK could not be initialized: \($0). See Docs/RevitInterop.md.\n\n" + UnavailableRevitProvider.routes }
    }
    public var sdkVersion: String? { arcus_bimrv_sdk_version().map { String(cString: $0) } }

    public func `import`(_ url: URL, into tx: TransactionContext, options: ExchangeImportOptions) throws(RevitImportError) -> ExchangeImportReport {
        if let r = unavailableReason { throw .unavailable(r) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("arcus-bimrv-\(UUID().uuidString).arcusx")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var err = ArcusBimRvError()
        let rc = url.path.withCString { src in
            tmp.path.withCString { dst in arcus_bimrv_export_arcusx(src, dst, options.importMeshes ? 1 : 0, &err) }
        }
        guard rc == 0 else {
            throw .failed("“\(url.lastPathComponent)” could not be read with the ODA BimRv SDK: \(Self.message(err))")
        }
        var o = options
        if o.fileName == nil { o.fileName = url.lastPathComponent }
        let data: Data
        do { data = try Data(contentsOf: tmp) } catch { throw .failed("The BimRv translation could not be read: \(error.localizedDescription)") }
        do {
            var report = try ArcusExchangeImporter.import(data: data, into: tx, options: o)
            report.warnings.insert(ExchangeImportWarning(code: "bimrv.unverified",
                message: "Read directly with the ODA BimRv SDK. This import path is new; check the result against the Revit model."), at: 0)
            return report
        } catch {
            throw .exchange(error)
        }
    }
}
#endif
