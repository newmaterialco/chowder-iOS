import Foundation

struct ConnectionConfig {

    private static let gatewayURLKey = "gatewayURL"
    private static let sessionKeyKey = "sessionKey"
    private static let tokenKeychainKey = "gatewayToken"
    private static let cfAccessClientIdKeychainKey = "cfAccessClientId"
    private static let cfAccessClientSecretKeychainKey = "cfAccessClientSecret"

    var gatewayURL: String {
        get { UserDefaults.standard.string(forKey: Self.gatewayURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.gatewayURLKey) }
    }

    var sessionKey: String {
        get { UserDefaults.standard.string(forKey: Self.sessionKeyKey) ?? "agent:main:main" }
        set { UserDefaults.standard.set(newValue, forKey: Self.sessionKeyKey) }
    }

    var token: String {
        get { KeychainService.load(key: Self.tokenKeychainKey) ?? "" }
        set { KeychainService.save(key: Self.tokenKeychainKey, value: newValue) }
    }
    
    // Cloudflare Zero Trust service token credentials.
    // When both are set, they are sent as HTTP headers during the WebSocket upgrade.
    var cfAccessClientId: String {
        get { KeychainService.load(key: Self.cfAccessClientIdKeychainKey) ?? "" }
        set { KeychainService.save(key: Self.cfAccessClientIdKeychainKey, value: newValue) }
    }
    
    var cfAccessClientSecret: String {
        get { KeychainService.load(key: Self.cfAccessClientSecretKeychainKey) ?? "" }
        set { KeychainService.save(key: Self.cfAccessClientSecretKeychainKey, value: newValue) }
    }
    
    var hasCloudflareAccessTokens: Bool {
        !cfAccessClientId.isEmpty && !cfAccessClientSecret.isEmpty
    }

    var isConfigured: Bool {
        !gatewayURL.isEmpty && !token.isEmpty
    }
}

