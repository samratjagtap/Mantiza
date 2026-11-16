# App Intents index, off a Mac

iOS only lists an app's actions (Siri phrases, Shortcuts actions, Control Centre buttons, buttons on a
Live Activity) from an index inside the app, `Metadata.appintents`. Xcode writes it with Apple's
`appintentsmetadataprocessor`, which only runs on a Mac. Mantiza is built on Windows with xtool, so the
index has to come from somewhere else.

`appintentsmetadataprocessor.py` is an open-source stand-in that writes the same content from the Swift
compiler's constant values (`.swiftconstvalues`), which the build already leaves in `.build`.

- **Source:** [apple-cross-toolchain/rules_applecross](https://github.com/apple-cross-toolchain/rules_applecross),
  `toolchain/stubs/appintentsmetadataprocessor.py`, commit `548f00b` (2026-11-16), unchanged.
  Its notes: [docs/clean-room/appintentsmetadataprocessor.md](https://github.com/apple-cross-toolchain/rules_applecross/blob/main/docs/clean-room/appintentsmetadataprocessor.md).
- **Licence:** Apache 2.0 ([LICENSE](LICENSE)).
- **What it does:** reads JSON, writes `extract.actionsdata` and `version.json`. No network, nothing else.
- **What it covers:** plain actions, parameters of basic types, enums, App Shortcuts phrases. What it
  hasn't been compared on against Xcode it refuses, so keep Mantiza's actions simple
  ([Intents.swift](../../apps/mantiza/Sources/Mantiza/Intents.swift)).
- **How it is run:** `python3 scripts/make_intents.py` from `apps/mantiza`, after `xtool dev build`.
- **Also looked at:** [xtool PR #397](https://github.com/xtool-org/xtool/pull/397) would do this inside
  xtool, but it is an unreviewed draft and doesn't cover actions with parameters.
