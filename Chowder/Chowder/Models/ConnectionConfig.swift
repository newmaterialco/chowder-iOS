import Foundation

struct ConnectionConfig {

    private static let gatewayURLKey = "gatewayURL"
    private static let sessionKeyKey = "sessionKey"
    private static let tokenKeychainKey = "gatewayToken"

    var gatewayURL: String {
        get { UserDefaults.standard.string(forKey: Self.gatewayURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.gatewayURLKey) }
    }

    /// The gateway URL normalized to use `wss://` for secure connections.
    /// Falls through as-is for `ws://` (local development) or already-correct `wss://` URLs.
    var effectiveGatewayURL: String {
        let url = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasPrefix("wss://") || url.hasPrefix("ws://") {
            return url
        }
        if !url.isEmpty {
            return "wss://" + url
        }
        return url
    }

    var sessionKey: String {
        get { UserDefaults.standard.string(forKey: Self.sessionKeyKey) ?? "agent:main:main" }
        set { UserDefaults.standard.set(newValue, forKey: Self.sessionKeyKey) }
    }

    var token: String {
        get { KeychainService.load(key: Self.tokenKeychainKey) ?? "" }
        set { KeychainService.save(key: Self.tokenKeychainKey, value: newValue) }
    }

    var isConfigured: Bool {
        let url = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return !url.isEmpty && !token.isEmpty &&
            (url.hasPrefix("wss://") || url.hasPrefix("ws://"))
    }
}
