import Foundation
import ArcusDomain

/// Why a Revit file could not be imported.
public enum RevitImportError: Error, Hashable, Sendable, CustomStringConvertible {
    /// Direct import is not available in this build; the message explains the working alternatives.
    case unavailable(String)
    case inspection(RevitInspectionError)
    case exchange(ExchangeImportError)
    case failed(String)

    public var description: String {
        switch self {
        case .unavailable(let m), .failed(let m): m
        case .inspection(let e): e.description
        case .exchange(let e): e.description
        }
    }
}

/// Opens Revit files (.rvt, .rfa, .rte, .rft) directly.
///
/// Arcus does not reverse-engineer Revit's proprietary format. Every build can `inspect` a file (container metadata,
/// preview, release); `import` needs a provider backed by a licensed SDK. Without one, `RevitProviders.current` is
/// `UnavailableRevitProvider`, whose messages explain the routes that do work: the Arcus Bridge add-in (.arcusx) and IFC.
public protocol RevitImportProvider: Sendable {
    var name: String { get }
    var isAvailable: Bool { get }
    /// Truthful, user-facing explanation when `import` is not available.
    var unavailableReason: String? { get }
    /// Whether this provider handles the file (by extension).
    func canOpen(_ url: URL) -> Bool
    /// Container-level facts, readable in every build.
    func inspect(_ url: URL) throws(RevitImportError) -> RevitFileInfo
    /// Imports the file into the transaction as native Arcus elements.
    func `import`(_ url: URL, into tx: TransactionContext, options: ExchangeImportOptions) throws(RevitImportError) -> ExchangeImportReport
}

extension RevitImportProvider {
    public func canOpen(_ url: URL) -> Bool { RevitProviders.isRevitFile(url) }
    public func inspect(_ url: URL) throws(RevitImportError) -> RevitFileInfo {
        do { return try RevitFileInspector.inspect(url) } catch { throw .inspection(error) }
    }
}

/// The provider used when Arcus is built without a licensed Revit SDK.
public struct UnavailableRevitProvider: RevitImportProvider {
    public init() {}
    public var name: String { "Revit (direct import not installed)" }
    public var isAvailable: Bool { false }

    public static let routes = """
        Two ways work today:
        1. Arcus Bridge (recommended): install the Arcus Bridge add-in in Revit, open your project and choose \
        Add-Ins ▸ Arcus ▸ Export to Arcus (in the Family Editor: Export Family to Arcus). Open the saved .arcusx file \
        in Arcus. Levels, grids, walls, floors, ceilings, roofs, doors, windows, rooms, columns, beams, stairs, railings, \
        materials and families arrive as editable Arcus elements.
        2. IFC: in Revit choose File ▸ Export ▸ IFC, then import the .ifc file in Arcus.
        """

    public var unavailableReason: String? {
        "Arcus can't open Revit files (.rvt, .rfa) directly. Revit's file format is proprietary and Arcus does not "
            + "reverse-engineer it.\n\n" + Self.routes + "\n\nOpening .rvt and .rfa files directly requires the licensed "
            + "ODA BimRv SDK, which is not included in this build of Arcus."
    }

    /// The unavailable message, prefixed with what Arcus could tell about the file.
    public func unavailableMessage(for info: RevitFileInfo?) -> String {
        guard let info else { return unavailableReason ?? "" }
        var first = "“\(info.fileName)” is a \(info.kind.displayName.lowercased())"
        if let r = info.revitRelease { first += " saved by Revit \(r)" }
        return first + ". " + (unavailableReason ?? "")
    }

    public func `import`(_ url: URL, into tx: TransactionContext, options: ExchangeImportOptions) throws(RevitImportError) -> ExchangeImportReport {
        throw .unavailable(unavailableMessage(for: try? RevitFileInspector.inspect(url)))
    }
}

public enum RevitProviders {
    public static let revitExtensions: Set<String> = ["rvt", "rfa", "rte", "rft"]

    /// The direct-import provider of this build: the ODA BimRv-backed provider when compiled with the SDK
    /// (`ARCUS_HAS_ODA_BIMRV`), otherwise `UnavailableRevitProvider`.
    public static var current: any RevitImportProvider {
        #if ARCUS_HAS_ODA_BIMRV
        return ODABimRvProvider()
        #else
        return UnavailableRevitProvider()
        #endif
    }

    public static func isRevitFile(_ url: URL) -> Bool { revitExtensions.contains(url.pathExtension.lowercased()) }
    public static func isExchangeFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == ExchangeFormat.fileExtension
    }

    /// Imports a `.arcusx` file (the route that works in every build).
    public static func importExchangeFile(_ url: URL, into tx: TransactionContext, options: ExchangeImportOptions = .init()) throws(RevitImportError) -> ExchangeImportReport {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= options.maxInputBytes else { throw .exchange(.tooLarge(bytes: size, limit: options.maxInputBytes)) }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw .failed("“\(url.lastPathComponent)” could not be read: \(error.localizedDescription)") }
        var o = options
        if o.fileName == nil { o.fileName = url.lastPathComponent }
        do { return try ArcusExchangeImporter.import(data: data, into: tx, options: o) } catch { throw .exchange(error) }
    }
}
