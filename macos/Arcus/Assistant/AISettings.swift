import Foundation
import Observation

// AICORE: Settings ▸ AI: the opt-in switch (off by default), the monthly budget, the price table and this month's
// spending. Kept in UserDefaults; the API key is not here (Keychain, AIKeyStore).

@MainActor
@Observable
public final class AISettings {
    public static let shared = AISettings()

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored public let keys: any AIKeyStore

    enum Key {
        static let enabled = "ai.enabled"
        static let budget = "ai.monthlyBudget"
        static let prices = "ai.prices"
        static let spending = "ai.spending"
        static let explained = "ai.explainedWhatIsSent"
        static let useSelection = "ai.useSelection"
    }

    /// The opt-in switch. Off: the assistant never touches the network.
    public var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled) } }
    /// Monthly spending cap in US dollars (0 = no cap).
    public var monthlyBudget: Double { didSet { defaults.set(monthlyBudget, forKey: Key.budget) } }
    public var prices: AIPriceTable { didSet { save(prices, Key.prices) } }
    /// Dollars spent per calendar month ("2026-10").
    public private(set) var spending: [String: Double] { didSet { save(spending, Key.spending) } }
    /// Whether the user has seen (and accepted) what the assistant sends.
    public var explainedWhatIsSent: Bool { didSet { defaults.set(explainedWhatIsSent, forKey: Key.explained) } }
    /// The composer's "Use selection" toggle (remembered).
    public var useSelection: Bool { didSet { defaults.set(useSelection, forKey: Key.useSelection) } }
    /// Bumped when the key changes (views observe it; the key itself is never stored here).
    public private(set) var keyRevision = 0

    public init(defaults: UserDefaults = .standard, keys: any AIKeyStore = KeychainKeyStore.shared) {
        self.defaults = defaults
        self.keys = keys
        enabled = defaults.bool(forKey: Key.enabled)
        monthlyBudget = defaults.object(forKey: Key.budget) as? Double ?? 10
        prices = Self.load(AIPriceTable.self, defaults, Key.prices) ?? .published
        spending = Self.load([String: Double].self, defaults, Key.spending) ?? [:]
        explainedWhatIsSent = defaults.bool(forKey: Key.explained)
        useSelection = defaults.object(forKey: Key.useSelection) as? Bool ?? true
    }

    public var hasKey: Bool { _ = keyRevision; return keys.hasKey }
    public var maskedKey: String? { _ = keyRevision; return keys.maskedKey }

    /// Saves the key to the Keychain. Returns false when the Keychain refused.
    @discardableResult
    public func setKey(_ key: String) -> Bool {
        let ok = keys.write(key)
        keyRevision += 1
        return ok
    }
    public func removeKey() { keys.write(""); keyRevision += 1 }

    /// Ready to send: switched on and a key saved.
    public var isReady: Bool { enabled && hasKey }

    /// The access check the client runs before every request.
    public static func access(_ settings: AISettings) -> AIAccess {
        let keys = settings.keys
        let flag = EnabledFlag(settings.defaults)
        return AIAccess(enabled: { flag.value }, key: { keys.read() })
    }

    // MARK: Spending

    public static func monthKey(_ date: Date = Date()) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
    public func spent(in month: String = AISettings.monthKey()) -> Double { spending[month] ?? 0 }
    public func record(_ dollars: Double, date: Date = Date()) {
        guard dollars > 0 else { return }
        spending[Self.monthKey(date), default: 0] += dollars
        // Keep a year of months.
        if spending.count > 12, let oldest = spending.keys.sorted().first { spending.removeValue(forKey: oldest) }
    }
    public var budgetReached: Bool { monthlyBudget > 0 && spent() >= monthlyBudget }
    public func resetPrices() { prices = .published }

    // MARK: Storage

    private func save<T: Encodable>(_ v: T, _ key: String) {
        if let d = try? JSONEncoder().encode(v) { defaults.set(d, forKey: key) }
    }
    private static func load<T: Decodable>(_ t: T.Type, _ d: UserDefaults, _ key: String) -> T? {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}

/// Reads the switch from any thread (UserDefaults is thread-safe).
final class EnabledFlag: @unchecked Sendable {
    let defaults: UserDefaults
    init(_ d: UserDefaults) { defaults = d }
    var value: Bool { defaults.bool(forKey: AISettings.Key.enabled) }
}
