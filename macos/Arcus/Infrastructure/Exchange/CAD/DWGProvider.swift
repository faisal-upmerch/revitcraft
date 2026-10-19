import Foundation
import ArcusGeometry
import ArcusDomain
#if ARCUS_HAS_ODA
import ArcusDWGBridge
#endif

/// Reads DWG files into a `CADDocument`: Arcus's bundled engines (BundledDWGEngine.swift), a converter the user installed
/// (ExternalDWGConverter.swift) or the licensed ODA SDK build.
public protocol DWGImportProvider: Sendable {
    var isAvailable: Bool { get }
    /// Truthful, user-facing explanation when DWG import is not available.
    var unavailableReason: String? { get }
    var sdkName: String { get }
    var sdkVersion: String? { get }
    /// DWG format versions (e.g. "AC1032") this provider reads.
    var supportedVersions: [String] { get }
    func read(_ url: URL, options: CADReadOptions, progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) throws -> CADDocument
}

/// The provider used when no DWG route is available (no bundled engine, no installed converter, no ODA SDK).
public struct UnavailableDWGProvider: DWGImportProvider {
    public init() {}
    public var isAvailable: Bool { false }
    /// Why the external converter route is not in use (e.g. a chosen converter that is missing); appended to the reason.
    public var converterProblem: String? = nil
    public var unavailableReason: String? {
        var s = "DWG import is not available: the DWG engines that come with Arcus are missing from this copy of Arcus, and no "
            + "DWG converter was found on this Mac. Reinstall Arcus (its build script bundles the engines), or install a free "
            + "converter yourself (ODA File Converter from the Open Design Alliance, or LibreDWG's dwg2dxf), which converts the "
            + "drawing to DXF on this Mac. You can also save the drawing as DXF from your CAD application and link the DXF, or "
            + "build Arcus with the licensed ODA Drawings SDK (not bundled) as described in Docs/DWGSDKSetup.md."
        if let converterProblem { s += " " + converterProblem }
        return s
    }
    public var sdkName: String { "ODA Drawings SDK (not installed)" }
    public var sdkVersion: String? { nil }
    public var supportedVersions: [String] { [] }
    public func read(_ url: URL, options: CADReadOptions, progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) throws -> CADDocument {
        throw CADError(unavailableReason ?? "DWG import is not available.")
    }
}

public enum DWGProviders {
    /// The DWG reader of this copy of Arcus: every available route, tried in order (DWG):
    /// 1. Arcus's bundled acadrust engine, 2. the bundled LibreDWG, 3. a converter the user installed (chosen in Settings
    /// or detected; see ExternalDWGConverter.swift), 4. the ODA Drawings SDK when Arcus was built with it.
    public static var current: any DWGImportProvider {
        if let o = providerOverride { return o }
        return chain(helpers: .standard, converter: DWGConverterPreferences.resolveFromDefaults())
    }

    /// The route chain for the given bundled helpers and converter preference. // DWG
    public static func chain(helpers: BundledDWGHelpers, converter: Result<ExternalDWGConverter, DWGConverterPreferences.ConverterProblem>?) -> DWGEngineChain {
        var routes: [any DWGImportProvider] = []
        if let a = helpers.acadrust { routes.append(BundledAcadrustDWGProvider(helper: a)) }
        if let l = helpers.libreDWG { routes.append(BundledLibreDWGProvider(executable: l)) }
        var unavailable = UnavailableDWGProvider()
        switch converter {
        case .success(let c)?: routes.append(ExternalConverterDWGProvider(converter: c))
        case .failure(let p)?: unavailable.converterProblem = p.message
        case nil: break
        }
        #if ARCUS_HAS_ODA
        routes.append(ODADWGProvider())
        #endif
        return DWGEngineChain(routes: routes, unavailable: unavailable)
    }

    /// Replaces `current` within a task (tests, and a one-off choice in the UI). // W2-DWG
    @TaskLocal public static var providerOverride: (any DWGImportProvider)?

    /// The provider for a resolved converter preference: the external converter, or `UnavailableDWGProvider` explaining why.
    public static func external(_ resolved: Result<ExternalDWGConverter, DWGConverterPreferences.ConverterProblem>?) -> any DWGImportProvider {
        switch resolved {
        case .success(let c)?: return ExternalConverterDWGProvider(converter: c)
        case .failure(let p)?: var u = UnavailableDWGProvider(); u.converterProblem = p.message; return u
        case nil: return UnavailableDWGProvider()
        }
    }

    /// DWG versions Arcus maps to friendly names (the SDK may read more; see `supportedVersions` of the provider).
    public static let knownVersions = ["AC1009", "AC1012", "AC1014", "AC1015", "AC1018", "AC1021", "AC1024", "AC1027", "AC1032"]

    /// Reads the version code from a DWG file header (first 6 bytes, e.g. "AC1032") without an SDK.
    public static func sniffVersion(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 6), d.count == 6, let s = String(data: d, encoding: .ascii), s.hasPrefix("AC") else { return nil }
        return s
    }
}

#if ARCUS_HAS_ODA
// UNVERIFIED: this provider and the C++ bridge it calls (Arcus/Infrastructure/Exchange/DWGBridge) have not been compiled or
// run on the development machine because the licensed ODA Drawings SDK is not available there. Build with ARCUS_ODA_SDK_DIR
// set and run the DWG verification steps in Docs/DWGSDKSetup.md before shipping a DWG-enabled build.

/// DWG import through the licensed ODA Drawings SDK.
///
/// The bridge opens the DWG with the SDK, writes an in-SDK DXF translation to a private temporary file (the SDK's own
/// DWG→DXF writer, so geometry, blocks, layouts, dimension blocks and xref paths come through the same well-tested DXF path),
/// and enumerates proxy / custom objects so their extents and original class names can be attached by handle.
public struct ODADWGProvider: DWGImportProvider {
    public init() {}

    /// nil when the SDK initialized; otherwise the SDK's error message.
    private static let initialization: String? = {
        var err = ArcusDWGError()
        if arcus_dwg_initialize(&err) == 0 { return nil }
        let msg = message(err)
        return msg.isEmpty ? "unknown error" : msg
    }()

    public var isAvailable: Bool { Self.initialization == nil }
    public var unavailableReason: String? {
        Self.initialization.map { "The ODA Drawings SDK could not be initialized: \($0). See Docs/DWGSDKSetup.md." }
    }
    public var sdkName: String { "ODA Drawings SDK" }
    public var sdkVersion: String? { arcus_dwg_sdk_version().map { String(cString: $0) } }
    public var supportedVersions: [String] { DWGProviders.knownVersions }

    private final class ProxyBox {
        var items: [String: (String, Rect2?)] = [:]
        var cancelled: @Sendable () -> Bool = { false }
    }

    private static func message(_ e: ArcusDWGError) -> String {
        withUnsafeBytes(of: e.message) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    }

    public func read(_ url: URL, options: CADReadOptions, progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) throws -> CADDocument {
        if let r = unavailableReason { throw CADError(r) }
        var err = ArcusDWGError()
        guard let db = url.path.withCString({ arcus_dwg_open($0, &err) }) else {
            throw CADError("The DWG file could not be opened: \(Self.message(err))")
        }
        defer { arcus_dwg_close(db) }
        progress(0.2)
        if isCancelled() { throw CancellationError() }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("arcus-dwg-\(UUID().uuidString).dxf")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard tmp.path.withCString({ arcus_dwg_write_dxf(db, $0, &err) }) == 0 else {
            throw CADError("The DWG file could not be translated: \(Self.message(err))")
        }
        progress(0.45)
        // Proxy / unsupported object extents by handle.
        let box = ProxyBox()
        try withoutActuallyEscaping(isCancelled) { cancel in
            box.cancelled = cancel
            let ctx = Unmanaged.passUnretained(box).toOpaque()
            let rc = arcus_dwg_enumerate_objects(db, { info, ctx in
                guard let info, let ctx else { return }
                let b = Unmanaged<ProxyBox>.fromOpaque(ctx).takeUnretainedValue()
                let h = String(cString: info.pointee.handle).uppercased()
                let t = String(cString: info.pointee.typeName)
                let r: Rect2? = info.pointee.hasExtents != 0
                    ? Rect2(min: Vec2(info.pointee.minX, info.pointee.minY), max: Vec2(info.pointee.maxX, info.pointee.maxY)) : nil
                b.items[h] = (t, r)
            }, { ctx in
                guard let ctx else { return 0 }
                return Unmanaged<ProxyBox>.fromOpaque(ctx).takeUnretainedValue().cancelled() ? 1 : 0
            }, ctx, &err)
            if rc == 2 { throw CancellationError() }
            if rc != 0 { throw CADError("Reading DWG objects failed: \(Self.message(err))") }
        }
        let data = try Data(contentsOf: tmp)
        var doc = try DXFReader.read(data, fileName: url.lastPathComponent, options: options,
                                     progress: { progress(0.5 + 0.5 * $0) }, isCancelled: isCancelled)
        doc.format = "DWG"
        if let v = arcus_dwg_file_version(db) { doc.version = String(cString: v); doc.versionName = CADDocument.friendlyVersion(doc.version) }
        // Attach proxy extents and class names by handle.
        func patch(_ e: CADEntity) -> CADEntity {
            let n: String
            var isProxy = false
            switch e {
            case .proxy(let x, _, _): n = x; isProxy = true
            case .unsupported(let x, _): n = x
            default: return e
            }
            let p = e.props
            guard let info = box.items[p.handle] else { return e }
            let name = info.0.isEmpty ? n : info.0
            if let r = info.1, CADGeometry.isFinite(r) { return .proxy(typeName: name, bounds: r, p) }
            return isProxy ? .proxy(typeName: name, bounds: nil, p) : e
        }
        doc.modelSpace = doc.modelSpace.map(patch)
        doc.layouts = doc.layouts.map { var l = $0; l.entities = l.entities.map(patch); return l }
        for (k, v) in doc.blocks { var b = v; b.entities = b.entities.map(patch); doc.blocks[k] = b }
        return doc
    }
}
#endif
