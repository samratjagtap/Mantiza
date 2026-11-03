import CryptoKit
import Foundation
import Security

/// The app's half of the stick's session auth (firmware/mantiza-hands/session_auth.h): a 32-byte secret per stick
/// in the Keychain, the HMAC answer to the stick's challenge, and the tag on every command line.
enum SessionAuth {
    static func newSecret() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    /// The 4 digits the stick shows when the secret is set: first two bytes of SHA-256(secret), mod 10000.
    static func code(_ secret: Data) -> String {
        let h = Array(SHA256.hash(data: secret))
        return String(format: "%04d", (Int(h[0]) << 8 | Int(h[1])) % 10000)
    }

    static func answer(secret: Data, nonce: Data) -> String {
        hex(Data(HMAC<SHA256>.authenticationCode(for: nonce, using: SymmetricKey(data: secret))))
    }

    /// "<id> <command>" -> "<id> <command> ~<tag>", tag = first 8 bytes of HMAC(secret, nonce || line).
    static func sign(_ line: String, secret: Data, nonce: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: nonce + Data(line.utf8), using: SymmetricKey(data: secret))
        return line + " ~" + hex(Data(mac).prefix(8))
    }

    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    static func unhex(_ s: String) -> Data? {
        guard s.count % 2 == 0 else { return nil }
        var out = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        return out
    }

    // MARK: Keychain, one secret per stick (CoreBluetooth identifier)

    private static let service = "com.azadjagtap.mantiza.stick"

    static func secret(for stick: UUID) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: stick.uuidString, kSecReturnData as String: true]
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    static func store(_ secret: Data?, for stick: UUID) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: stick.uuidString]
        SecItemDelete(base as CFDictionary)
        guard let secret else { return }
        var add = base
        add[kSecValueData as String] = secret
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

extension Result where Failure == Error {
    /// Result of an async throwing call.
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
