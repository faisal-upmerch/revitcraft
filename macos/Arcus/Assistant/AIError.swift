import Foundation

// AICORE: the assistant's failures, each with a plain sentence for the chat and whether a retry can help.

public struct AIError: Error, Sendable, Hashable, CustomStringConvertible {
    public enum Kind: String, Sendable, Hashable {
        /// The AI switch is off in Settings ▸ AI.
        case disabled
        /// No API key in the Keychain.
        case noKey
        case invalidKey
        case permission
        case offline
        case timeout
        case rateLimited
        case overloaded
        case badRequest
        case tooLarge
        case server
        case badResponse
        case cancelled
        case budget
    }

    public var kind: Kind
    public var message: String
    public var retryable: Bool
    /// Seconds the service asked to wait (`retry-after`).
    public var retryAfter: Double?

    public init(_ kind: Kind, _ message: String, retryable: Bool = false, retryAfter: Double? = nil) {
        self.kind = kind; self.message = message; self.retryable = retryable; self.retryAfter = retryAfter
    }

    public var description: String { message }

    /// The short title the chat's error card shows.
    public var title: String {
        switch kind {
        case .disabled: "The AI assistant is off"
        case .noKey: "No API key"
        case .invalidKey: "The API key was not accepted"
        case .permission: "Not allowed"
        case .offline: "You're offline"
        case .timeout: "No answer in time"
        case .rateLimited: "Rate limit reached"
        case .overloaded: "Service busy"
        case .badRequest: "Request refused"
        case .tooLarge: "Too large"
        case .server: "Service error"
        case .badResponse: "Unexpected response"
        case .cancelled: "Stopped"
        case .budget: "Monthly budget reached"
        }
    }

    /// Maps an HTTP status and error body (`{"type":"error","error":{"type":…,"message":…}}`) to an error.
    public static func http(_ status: Int, body: Data, retryAfter: Double?) -> AIError {
        let apiMessage = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])
            .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
        switch status {
        case 401: return AIError(.invalidKey, "Check the key in Settings ▸ AI (it should start with “sk-ant-”).")
        case 402: return AIError(.permission, apiMessage ?? "Your Anthropic account needs billing set up or more credit.")
        case 403: return AIError(.permission, apiMessage ?? "This API key isn't allowed to use this model.")
        case 404: return AIError(.badRequest, apiMessage ?? "The model wasn't found for this key.")
        case 413: return AIError(.tooLarge, "The request was too large. Remove an attached image or start a new chat.")
        case 429: return AIError(.rateLimited, "Too many requests for your API key right now. Arcus retried; try again in a minute.", retryable: true, retryAfter: retryAfter)
        case 529: return AIError(.overloaded, "Anthropic's service is busy. Arcus retried; try again shortly.", retryable: true, retryAfter: retryAfter)
        case 400..<500: return AIError(.badRequest, apiMessage ?? "The request was refused (\(status)).")
        default: return AIError(.server, "Anthropic's service had a problem (\(status)). Arcus retried; try again shortly.", retryable: true, retryAfter: retryAfter)
        }
    }

    /// Maps a URLSession error.
    public static func transport(_ error: any Error) -> AIError {
        if error is CancellationError { return AIError(.cancelled, "Stopped.") }
        if let e = error as? AIError { return e }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCancelled: return AIError(.cancelled, "Stopped.")
            case NSURLErrorTimedOut: return AIError(.timeout, "Anthropic didn't answer in time. Check your connection and try again.", retryable: true)
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff:
                return AIError(.offline, "Connect to the internet to use the AI assistant. Everything else in Arcus works offline.", retryable: true)
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                return AIError(.offline, "Arcus couldn't reach api.anthropic.com. Check your connection or firewall.", retryable: true)
            default: break
            }
        }
        return AIError(.server, "The connection failed: \(ns.localizedDescription)", retryable: true)
    }
}
