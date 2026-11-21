import Foundation

/// Safety rules (PRD section 9, risky-word filter after arc-cua): risky buttons are hidden from the brains unless
/// the task asked for that kind of action, and even then each one needs the user's approval; some screens stop the
/// agent outright; secrets are never typed.
enum Safety {
    static let riskKinds: Set<String> = ["send", "delete", "purchase", "call", "post"]

    static let riskWords: [String: [String]] = [
        "send": ["send", "send now", "reply all"],
        "delete": ["delete", "remove", "erase", "clear all", "delete all", "discard"],
        "purchase": ["buy", "buy now", "pay", "pay now", "purchase", "place order", "checkout", "check out", "subscribe", "confirm order", "add to cart"],
        "call": ["call", "facetime", "voice call", "video call"],
        "post": ["post", "publish", "share", "tweet", "upload"],
    ]

    /// Screens the agent must never operate: payments, passwords, banking.
    static let stopPhrases = ["enter passcode", "passcode", "password", "apple pay", "wallet", "card number", "cvv",
                              "one-time password", "otp", "upi pin", "enter pin", "net banking", "phonepe", "paytm",
                              "google pay", "face id"]

    /// The risk kind of a tappable element: short labels only, so a message that mentions "send" is not a button.
    static func risk(of element: ScreenElement) -> String? {
        let text = element.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard text.split(separator: " ").count <= 3 else { return nil }
        for (kind, words) in riskWords where words.contains(where: { text == $0 || text.hasPrefix($0 + " ") }) {
            return kind
        }
        return nil
    }

    /// The reading without risky elements the task did not ask for, and the ids that were hidden.
    static func filter(_ reading: ScreenReading, allowed: [String]) -> (visible: ScreenReading, hidden: [Int]) {
        var visible = reading
        var hidden: [Int] = []
        visible.elements = reading.elements.filter { e in
            guard let kind = risk(of: e), !allowed.contains(kind) else { return true }
            hidden.append(e.id)
            return false
        }
        return (visible, hidden)
    }

    /// Why this screen must not be operated, or nil. Matches short labels (titles, field names), not long text.
    static func stopReason(_ reading: ScreenReading) -> String? {
        for e in reading.elements where e.text.split(separator: " ").count <= 4 {
            let t = e.text.lowercased()
            if let p = stopPhrases.first(where: { t == $0 || t.hasPrefix($0 + " ") || t.hasSuffix(" " + $0) }) {
                return "This screen asks for something sensitive (\(p)). Mantiza stops here; please continue yourself."
            }
        }
        return nil
    }

    /// Text that looks like a secret (card number, PIN, one-time code) is never typed.
    static func looksSecret(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        let compact = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if compact.allSatisfy(\.isNumber) && (4...8).contains(digits.count) { return true }  // PIN / OTP
        if (13...19).contains(digits.count) && compact.allSatisfy(\.isNumber) { return true }  // card number
        return false
    }
}
