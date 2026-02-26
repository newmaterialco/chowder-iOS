import Foundation
import CryptoKit
import CommonCrypto

/// Manages Ed25519 device identity for OpenClaw gateway authentication.
/// The keypair is generated once and stored in Keychain. The device ID
/// is the SHA-256 hash of the raw public key bytes (hex-encoded).
enum DeviceIdentity {

    private static let privateKeyTag = "deviceEd25519PrivateKey"

    // MARK: - Public API

    /// Returns the device ID (SHA-256 of raw public key, hex-encoded).
    static var deviceId: String {
        let key = loadOrCreatePrivateKey()
        let rawPublicKey = key.publicKey.rawRepresentation
        return SHA256.hash(data: rawPublicKey)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Returns the raw public key as base64url (no padding).
    static var publicKeyBase64Url: String {
        let key = loadOrCreatePrivateKey()
        return base64UrlEncode(key.publicKey.rawRepresentation)
    }

    /// Signs the device auth payload for the gateway connect handshake.
    /// Payload format (v2): version|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce
    static func sign(
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        token: String,
        nonce: String
    ) -> (signature: String, signedAt: Int64) {
        let key = loadOrCreatePrivateKey()
        let signedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        let scopesStr = scopes.joined(separator: ",")

        let payload = [
            "v2",
            deviceId,
            clientId,
            clientMode,
            role,
            scopesStr,
            String(signedAtMs),
            token,
            nonce
        ].joined(separator: "|")

        let payloadData = Data(payload.utf8)
        let signatureRaw = try! key.signature(for: payloadData)
        let signatureData = signatureRaw.withUnsafeBytes { Data($0) }
        let signatureBase64Url = base64UrlEncode(signatureData)

        return (signatureBase64Url, signedAtMs)
    }

    // MARK: - Private

    private static func loadOrCreatePrivateKey() -> Curve25519.Signing.PrivateKey {
        if let stored = loadPrivateKey() {
            return stored
        }
        let newKey = Curve25519.Signing.PrivateKey()
        savePrivateKey(newKey)
        return newKey
    }

    private static func loadPrivateKey() -> Curve25519.Signing.PrivateKey? {
        guard let b64 = KeychainService.load(key: privateKeyTag),
              let data = Data(base64Encoded: b64) else {
            return nil
        }
        return try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    private static func savePrivateKey(_ key: Curve25519.Signing.PrivateKey) {
        let b64 = key.rawRepresentation.base64EncodedString()
        KeychainService.save(key: privateKeyTag, value: b64)
    }

    private static func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
