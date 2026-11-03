import Foundation
import Security

/// API keys in the iOS Keychain (this device only, never synced or backed up in plain text).
/// v1 calls the AI services directly with these keys ("direct mode"); a proxy backend replaces this later.
enum KeyStore {
    enum Provider: String, CaseIterable, Identifiable {
        case anthropic, google, typesafe, laya
        var id: String { rawValue }
        var title: String {
            switch self {
            case .anthropic: return "Anthropic (Claude)"
            case .google: return "Google (Gemini)"
            case .typesafe: return "TypeSafe (Jev)"
            case .laya: return "Laya server (LAYA_API_KEY)"
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

    /// Debug builds only: the Mac can drop `Documents/import-<provider>.key` into the app container with
    /// `xcrun devicectl device copy to` (see tools/e2e/phone.sh --key); it moves into the Keychain and the file is
    /// deleted, so keys never travel in launch arguments or logs.
    static func importDropped() {
        #if DEBUG
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        for p in Provider.allCases {
            let file = docs.appending(path: "import-\(p.rawValue).key")
            guard let data = try? Data(contentsOf: file) else { continue }
            try? FileManager.default.removeItem(at: file)
            set(p, String(decoding: data, as: UTF8.self))
            Log.event("keys.imported", ["provider": p.rawValue])
        }
        #endif
    }

    /// Keep keys out of every log line.
    static func refreshRedaction() { Log.redact(Provider.allCases.compactMap(get)) }
}
