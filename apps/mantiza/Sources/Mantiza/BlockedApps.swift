import Foundation

/// Apps Mantiza never opens or works in: money, passwords and codes. A hard stop, checked before a
/// task starts and again whenever Mantiza opens an app, so no plan or AI decision can get around it.
/// The user can change the list in the Device tab.
@MainActor
final class BlockedApps: ObservableObject {
    static let shared = BlockedApps()

    static let defaults = [
        "Wallet", "Passwords", "Google Pay", "GPay", "PhonePe", "Paytm", "BHIM", "CRED", "Amazon Pay",
        "YONO SBI", "HDFC Bank", "iMobile Pay", "ICICI", "Axis Mobile", "Kotak", "1Password", "Bitwarden",
        "LastPass", "Authenticator", "Google Authenticator",
    ]

    @Published private(set) var names: [String]
    private let storeKey = "blockedApps"

    init() {
        names = UserDefaults.standard.stringArray(forKey: "blockedApps") ?? BlockedApps.defaults
    }

    /// The blocked entry this app name matches, or nil. Whole words, either way round: "Google Pay
    /// for Business" matches "Google Pay", and so does a bare "Pay" (when in doubt, stop).
    func match(_ app: String?) -> String? {
        guard let app else { return nil }
        let a = " " + Words.norm(app) + " "
        guard a.count > 2 else { return nil }
        return names.first { name in
            let b = " " + Words.norm(name) + " "
            return b.count > 2 && (a == b || a.contains(b) || b.contains(a))
        }
    }

    func add(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !names.contains(where: { Words.norm($0) == Words.norm(n) }) else { return }
        names.append(n)
        save()
    }

    func remove(_ name: String) {
        names.removeAll { $0 == name }
        save()
    }

    func reset() {
        names = BlockedApps.defaults
        save()
    }

    private func save() {
        UserDefaults.standard.set(names, forKey: storeKey)
    }
}
