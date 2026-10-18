import Foundation
import ArcusPersistence

/// Version of the running app, from the main bundle's Info.plist.
///
/// When not running inside an Arcus bundle (unit tests, command-line tools) the values fall back to
/// `0.0.0` / `dev` so documents written by tests are clearly marked as development builds.
public struct AppVersionInfo: Sendable, Hashable, CustomStringConvertible {
    public var marketingVersion: String
    public var build: String
    public var documentSchema: Int

    public static let fallbackMarketingVersion = "0.0.0"
    public static let fallbackBuild = "dev"

    public init(marketingVersion: String, build: String, documentSchema: Int = ArcusPackage.currentSchemaVersion) {
        self.marketingVersion = marketingVersion; self.build = build; self.documentSchema = documentSchema
    }

    public static var current: AppVersionInfo { from(bundle: .main) }

    /// Reads `CFBundleShortVersionString` / `CFBundleVersion` from an Arcus bundle (identifier `com.local.arcus*`).
    public static func from(bundle: Bundle) -> AppVersionInfo {
        from(infoDictionary: bundle.infoDictionary ?? [:], bundleIdentifier: bundle.bundleIdentifier)
    }

    public static func from(infoDictionary info: [String: Any], bundleIdentifier: String?) -> AppVersionInfo {
        guard let id = bundleIdentifier, id.lowercased().hasPrefix("com.local.arcus") else {
            return AppVersionInfo(marketingVersion: fallbackMarketingVersion, build: fallbackBuild)
        }
        let mv = (info["CFBundleShortVersionString"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackMarketingVersion
        let b = (info["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackBuild
        return AppVersionInfo(marketingVersion: mv, build: b)
    }

    public var description: String { "Arcus \(marketingVersion) (\(build)), document schema \(documentSchema)" }

    /// Convenience: package write info stamped with this version.
    public func writeInfo(documentID: UUID, created: Date? = nil, thumbnailPNG: Data? = nil) -> ArcusPackage.WriteInfo {
        ArcusPackage.WriteInfo(documentID: documentID, appVersion: marketingVersion, build: build, created: created, thumbnailPNG: thumbnailPNG)
    }

    /// Compares dotted marketing versions numerically ("1.10.0" > "1.9.2"); non-numeric parts compare as 0.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

/// Where updates come from. Arcus ships local-only: no network update checks.
public protocol UpdateProvider: Sendable {
    var isEnabled: Bool { get }
    var statusMessage: String { get }
    func checkForUpdates() async -> UpdateCheckResult
}

public enum UpdateCheckResult: Sendable, Hashable {
    case disabled(String)
    case upToDate
    case available(String)
}

/// The only update provider: never enabled and never touches the network.
public struct LocalOnlyUpdateProvider: UpdateProvider {
    public init() {}
    public var isEnabled: Bool { false }
    public var statusMessage: String {
        "Automatic updates are off. Arcus never checks the internet for updates; to update, quit Arcus and replace Arcus.app with a newer local build."
    }
    public func checkForUpdates() async -> UpdateCheckResult { .disabled(statusMessage) }
}
