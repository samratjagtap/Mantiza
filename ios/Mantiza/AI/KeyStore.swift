import Foundation
import Security

/// API keys in the iOS Keychain (this device only, never synced or backed up in plain text).
/// v1 calls the AI services directly with these keys ("direct mode"); a proxy backend replaces this later.
enum KeyStore {
    enum Provider: String, CaseIterable, Identifiable {
        case anthropic, google, typesafe
        var id: String { rawValue }
        var title: String {
            switch self {
            case .anthropic: return "Anthropic (Claude)"
            case .google: return "Google (Gemini)"
            case .typesafe: return "TypeSafe (Jev)"
            }
        }
    }

    private static let service = "com.azadjagtap.mantiza.keys"

    static func get(_ p: Provider) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: p.rawValue, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        let key = String(decoding: data, as: UTF8.self)
        return key.isEmpty ? nil : key
    }

    static func set(_ p: Provider, _ value: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: p.rawValue]
        SecItemDelete(base as CFDictionary)
        let key = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !key.isEmpty {
            var add = base
            add[kSecValueData as String] = Data(key.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
        refreshRedaction()
    }

    /// Keep keys out of every log line.
    static func refreshRedaction() { Log.redact(Provider.allCases.compactMap(get)) }
}
