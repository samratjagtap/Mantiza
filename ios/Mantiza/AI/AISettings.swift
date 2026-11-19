import Foundation

/// Which models to use (UserDefaults); keys live in KeyStore.
enum AISettings {
    enum Big: String, CaseIterable, Identifiable { case claude, gemini; var id: String { rawValue } }

    static var big: Big {
        get { Big(rawValue: UserDefaults.standard.string(forKey: "ai.big") ?? "") ?? .claude }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "ai.big") }
    }

    static var claudeModel: String {
        get { UserDefaults.standard.string(forKey: "ai.claudeModel") ?? ClaudeBrain.defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: "ai.claudeModel") }
    }

    static var geminiModel: String {
        get { UserDefaults.standard.string(forKey: "ai.geminiModel") ?? GeminiBrain.defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: "ai.geminiModel") }
    }

    /// Who picks quick steps from the screen text: Laya on the user's own server, TypeSafe's Jev, or nobody.
    enum Fast: String, CaseIterable, Identifiable { case laya, jev, off; var id: String { rawValue } }

    static var fast: Fast {
        get { Fast(rawValue: UserDefaults.standard.string(forKey: "ai.fast") ?? "") ?? .laya }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "ai.fast") }
    }

    /// Where tools/laya/serve.sh runs, e.g. http://10.0.0.243:8765 (the Mac's address on the same Wi-Fi).
    static var layaURL: String {
        get { UserDefaults.standard.string(forKey: "ai.layaURL") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "ai.layaURL") }
    }

    static func bigBrain() throws -> BigBrain {
        switch big {
        case .claude:
            guard let key = KeyStore.get(.anthropic) else { throw AIError("Add your Anthropic key in Settings.") }
            return ClaudeBrain(key: key, model: claudeModel)
        case .gemini:
            guard let key = KeyStore.get(.google) else { throw AIError("Add your Google key in Settings.") }
            return GeminiBrain(key: key, model: geminiModel)
        }
    }

    static func fastBrain() -> FastBrain? {
        switch fast {
        case .laya:
            guard let url = URL(string: layaURL), url.scheme?.hasPrefix("http") == true, url.host() != nil else { return nil }
            return SystemOnePicker(service: .laya(url), key: KeyStore.get(.laya))
        case .jev:
            guard let key = KeyStore.get(.typesafe) else { return nil }
            return SystemOnePicker(service: .jev, key: key)
        case .off:
            return nil
        }
    }
}
