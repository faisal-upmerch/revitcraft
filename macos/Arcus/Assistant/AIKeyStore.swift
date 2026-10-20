import Foundation
import Security

// AICORE: the user's Anthropic API key lives only in the macOS Keychain (a generic password for this app), never in
// files, defaults, document packages or logs.

/// Where the API key is kept.
public protocol AIKeyStore: AnyObject, Sendable {
    func read() -> String?
    /// Saves (or, with an empty string, removes) the key. Returns false when the Keychain refused.
    @discardableResult func write(_ key: String) -> Bool
}

extension AIKeyStore {
    public var hasKey: Bool { !(read() ?? "").isEmpty }
    /// The key with all but its first 7 and last 4 characters hidden, for the Settings field.
    public var maskedKey: String? {
        guard let k = read(), k.count > 12 else { return read().map { _ in "••••" } }
        return String(k.prefix(7)) + "••••" + String(k.suffix(4))
    }
}

/// The Keychain store (login keychain, accessible after first unlock on this Mac only, not synchronised).
public final class KeychainKeyStore: AIKeyStore, @unchecked Sendable {
    public static let shared = KeychainKeyStore()
    let service: String
    let account: String

    public init(service: String = "com.local.arcus.assistant", account: String = "anthropic-api-key") {
        self.service = service; self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func read() -> String? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func write(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery as CFDictionary)
        guard !trimmed.isEmpty else { return true }
        var q = baseQuery
        q[kSecValueData as String] = Data(trimmed.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        q[kSecAttrLabel as String] = "Arcus AI Assistant (Anthropic API key)"
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}

/// An in-memory store (tests and previews).
public final class MemoryKeyStore: AIKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    public init(_ key: String? = nil) { self.key = key }
    public func read() -> String? { lock.lock(); defer { lock.unlock() }; return key }
    @discardableResult public func write(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let t = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.key = t.isEmpty ? nil : t
        return true
    }
}
