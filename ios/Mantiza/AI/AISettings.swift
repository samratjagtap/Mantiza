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

    /// Use Jev for quick picks when its key is set.
    static var useJev: Bool {
        get { UserDefaults.standard.object(forKey: "ai.useJev") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "ai.useJev") }
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
        guard useJev, let key = KeyStore.get(.typesafe) else { return nil }
        return JevPicker(key: key)
    }
}
