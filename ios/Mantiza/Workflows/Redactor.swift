import Foundation

// Based on ESP32 iPhone Agent by Henry Yuan (MIT); see THIRD_PARTY_NOTICES.md.

/// Strips what must not leave the phone from shared run data: API keys, the text the agent typed, email
/// addresses and phone or card-like numbers. Training rows (which stay on the phone and the user's Mac, and
/// need the task's inputs to learn from) only lose keys and long digit runs.
struct Redactor {
    var secrets: [String]
    var typed: [String] = []
    static let mask = "[redacted]"
    static let typedMask = "•••"

    private static let email = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
    /// 6+ digits, optionally broken by spaces, dots or dashes: codes, card and phone numbers.
    private static let digits = #"\+?\d(?:[ .\-]?\d){5,}"#

    /// For exports: everything above.
    func text(_ s: String) -> String {
        var out = s
        for x in secrets.filter({ $0.count >= 4 }).sorted(by: { $0.count > $1.count }) {
            out = out.replacingOccurrences(of: x, with: Self.mask)
        }
        for x in typed.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            out = out.replacingOccurrences(of: x, with: Self.typedMask)
        }
        out = out.replacingOccurrences(of: Self.email, with: Self.mask, options: .regularExpression)
        return out.replacingOccurrences(of: Self.digits, with: Self.mask, options: .regularExpression)
    }

    /// For training rows: keys and long digit runs only.
    func light(_ s: String) -> String {
        var out = s
        for x in secrets.filter({ $0.count >= 4 }) { out = out.replacingOccurrences(of: x, with: Self.mask) }
        return out.replacingOccurrences(of: Self.digits, with: Self.mask, options: .regularExpression)
    }

    /// Every string inside a JSON value.
    func json(_ v: Any, _ f: (String) -> String) -> Any {
        switch v {
        case let s as String: return f(s)
        case let a as [Any]: return a.map { json($0, f) }
        case let d as [String: Any]: return d.mapValues { json($0, f) }
        default: return v
        }
    }

    static var forThisPhone: Redactor { Redactor(secrets: KeyStore.Provider.allCases.compactMap(KeyStore.get)) }
}
