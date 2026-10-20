import Foundation

// AICORE: the two models the assistant may use (owner's decision, 2026-10-20): Haiku does the work, Sonnet retries a
// step that failed verification twice. No other model is ever requested.

/// A Claude model the assistant can run.
public enum AIModel: String, Codable, Sendable, CaseIterable, Hashable {
    case haiku = "claude-haiku-5-5"
    case sonnet = "claude-sonnet-5-5"

    /// The model ID sent in `model` (exact, no date suffix).
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .haiku: "Haiku 5.5"
        case .sonnet: "Sonnet 5.5"
        }
    }
    /// `output_config.effort`. Haiku 5.5 defaults to medium; Sonnet 5.5 defaults to high, so the retry pins medium
    /// (the documented starting point for multistep tool use) to keep its cost down.
    public var effort: String { "medium" }
}

/// Token usage of one or more Messages API responses (`usage`).
public struct AIUsage: Codable, Sendable, Hashable {
    /// Uncached input tokens (full price).
    public var input = 0
    /// Input tokens written to the cache (5-minute TTL).
    public var cacheWrite = 0
    /// Input tokens read from the cache.
    public var cacheRead = 0
    public var output = 0

    public init(input: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0, output: Int = 0) {
        self.input = input; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead; self.output = output
    }

    /// Every prompt token of the request (the Haiku long-prompt rate is chosen on this).
    public var promptTokens: Int { input + cacheWrite + cacheRead }
    public var total: Int { promptTokens + output }

    public static func + (a: AIUsage, b: AIUsage) -> AIUsage {
        AIUsage(input: a.input + b.input, cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead, output: a.output + b.output)
    }
    public static func += (a: inout AIUsage, b: AIUsage) { a = a + b }
}

/// Per-million-token prices of one rate card.
public struct AIRateCard: Codable, Sendable, Hashable {
    public var input: Double
    public var cacheWrite: Double
    public var cacheRead: Double
    public var output: Double

    public init(input: Double, cacheWrite: Double, cacheRead: Double, output: Double) {
        self.input = input; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead; self.output = output
    }

    public func cost(_ u: AIUsage) -> Double {
        (Double(u.input) * input + Double(u.cacheWrite) * cacheWrite + Double(u.cacheRead) * cacheRead + Double(u.output) * output) / 1_000_000
    }
}

/// The editable price table (Settings ▸ AI ▸ Prices). Defaults are Anthropic's published first-party prices, read from
/// platform.claude.com/docs/en/about-claude/pricing on `AIPriceTable.checkedOn`; the Settings pane says when they
/// were checked and that the user should compare them with the current pricing page.
public struct AIPriceTable: Codable, Sendable, Hashable {
    /// Haiku 5.5 for prompts up to 100,000 tokens.
    public var haiku: AIRateCard
    /// Haiku 5.5 for prompts over 100,000 tokens (the whole request is billed at this card).
    public var haikuLong: AIRateCard
    public var sonnet: AIRateCard
    /// True once the user has edited a value (the pane then shows "Custom prices").
    public var edited = false

    public static let checkedOn = "October 20, 2026"
    public static let haikuLongThreshold = 100_000

    public static let published = AIPriceTable(
        haiku: AIRateCard(input: 0.10, cacheWrite: 0.125, cacheRead: 0.01, output: 0.50),
        haikuLong: AIRateCard(input: 0.50, cacheWrite: 0.625, cacheRead: 0.05, output: 2.50),
        sonnet: AIRateCard(input: 2.00, cacheWrite: 2.50, cacheRead: 0.10, output: 10.00))

    public init(haiku: AIRateCard, haikuLong: AIRateCard, sonnet: AIRateCard, edited: Bool = false) {
        self.haiku = haiku; self.haikuLong = haikuLong; self.sonnet = sonnet; self.edited = edited
    }

    /// The cost in US dollars of one request's usage on `model`.
    public func cost(_ u: AIUsage, model: AIModel) -> Double {
        switch model {
        case .haiku: (u.promptTokens > Self.haikuLongThreshold ? haikuLong : haiku).cost(u)
        case .sonnet: sonnet.cost(u)
        }
    }
}

/// Formats dollars and token counts for the cost line.
public enum AIFormat {
    public static func dollars(_ d: Double) -> String {
        if d == 0 { return "$0.00" }
        if d < 0.01 { return String(format: "$%.4f", d) }
        if d < 1 { return String(format: "$%.3f", d) }
        return String(format: "$%.2f", d)
    }
    public static func tokens(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        if n < 100_000 { return String(format: "%.1fK", Double(n) / 1000) }
        if n < 1_000_000 { return "\(n / 1000)K" }
        return String(format: "%.2fM", Double(n) / 1_000_000)
    }
}
