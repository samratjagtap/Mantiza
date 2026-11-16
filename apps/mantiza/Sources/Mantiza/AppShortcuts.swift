import AppIntents

/// The phrases Siri understands without any setup ("Hey Siri, ask Mantiza"). App only.
struct MantizaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskMantizaIntent(),
                    phrases: ["Ask \(.applicationName)", "Ask \(.applicationName) to do something",
                              "Hey \(.applicationName)", "\(.applicationName) do something"],
                    shortTitle: "Ask Mantiza", systemImageName: "sparkles")
        AppShortcut(intent: ListenIntent(),
                    phrases: ["Talk to \(.applicationName)", "\(.applicationName) listen"],
                    shortTitle: "Talk to Mantiza", systemImageName: "mic.fill")
        AppShortcut(intent: StopTaskIntent(),
                    phrases: ["Stop \(.applicationName)", "\(.applicationName) stop"],
                    shortTitle: "Stop Mantiza", systemImageName: "stop.fill")
    }
}
