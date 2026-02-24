import CryptoKit
import Foundation

struct DeviceIdentity {
    let id: String
    let publicKey: String
    fileprivate let privateKey: Curve25519.Signing.PrivateKey
}

struct DeviceSignature {
    let signature: String
    let signedAt: Int64
}

enum DeviceIdentityError: LocalizedError {
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .signingFailed:
            return "Failed to sign device payload."
        }
    }
}

enum DeviceIdentityService {
    private static let privateKeyKey = "gatewayDeviceEd25519PrivateKey"
    private static let deviceTokenKey = "gatewayDeviceToken"

    static func loadOrCreateIdentity() throws -> DeviceIdentity {
        let privateKey: Curve25519.Signing.PrivateKey
        if let storedData = KeychainService.loadData(key: privateKeyKey) {
            do {
                privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: storedData)
            } catch {
                let regenerated = Curve25519.Signing.PrivateKey()
                KeychainService.save(key: privateKeyKey, data: regenerated.rawRepresentation)
                privateKey = regenerated
            }
        } else {
            privateKey = Curve25519.Signing.PrivateKey()
            KeychainService.save(key: privateKeyKey, data: privateKey.rawRepresentation)
        }

        let publicKeyRaw = privateKey.publicKey.rawRepresentation
        let id = CryptoHelper.sha256Hex(publicKeyRaw)
        let publicKey = Base64URL.encode(publicKeyRaw)
        return DeviceIdentity(id: id, publicKey: publicKey, privateKey: privateKey)
    }

    static func loadDeviceToken() -> String? {
        KeychainService.load(key: deviceTokenKey)
    }

    static func saveDeviceToken(_ token: String) {
        guard !token.isEmpty else { return }
        KeychainService.save(key: deviceTokenKey, value: token)
    }

    static func signConnectPayload(
        identity: DeviceIdentity,
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        signedAtMs: Int64,
        token: String,
        nonce: String
    ) throws -> DeviceSignature {
        let scopesCSV = scopes.joined(separator: ",")
        let payload = "v2|\(identity.id)|\(clientId)|\(clientMode)|\(role)|\(scopesCSV)|\(signedAtMs)|\(token)|\(nonce)"
        let data = Data(payload.utf8)
        do {
            let signatureData = try identity.privateKey.signature(for: data)
            return DeviceSignature(
                signature: Base64URL.encode(signatureData),
                signedAt: signedAtMs
            )
        } catch {
            throw DeviceIdentityError.signingFailed
        }
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

enum CryptoHelper {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
