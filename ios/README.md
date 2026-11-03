# Mantiza iOS app

SwiftUI app (iOS 27) that drives the Mantiza Hands stick. The project is generated with XcodeGen.

## Build

```sh
brew install xcodegen
cd ios
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set DEVELOPMENT_TEAM (a free Apple ID works)
xcodegen generate
open Mantiza.xcodeproj
```

If `xcode-select -p` still shows CommandLineTools, either run
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, or prefix command-line builds with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Tests run on the Simulator, where the app uses a pretend stick (`MockBoard`):

```sh
xcodebuild -project Mantiza.xcodeproj -scheme Mantiza -destination 'platform=iOS Simulator,name=iPhone 17' test
```

On a phone, launch with the argument `-mockBoard YES` to use the pretend stick there too.

## Options (Config/Local.xcconfig)

- `MANTIZA_BUNDLE_ID`: must be unique to your Apple ID.
- `MANTIZA_ASK = 1`: pair with AccessorySetupKit instead of the Bluetooth scan list (per build: with it on,
  the app only sees accessories set up through the system sheet).
- `MANTIZA_ENTITLEMENTS`, `MANTIZA_WIDGET_ENTITLEMENTS`: entitlements files with the App Group
  `group.$(MANTIZA_BUNDLE_ID)` that the app and widget share (it signs on a free Personal Team too).

## On a phone

```sh
tools/e2e/phone.sh            # from the repo root: build, install and launch on the plugged-in iPhone
tools/e2e/phone.sh --launch   # launch only
```

Free Apple ID installs expire after 7 days; run `phone.sh` again. Launch arguments:
`-mockBoard YES` (pretend stick), `-authSelfTest YES` (after connecting, check that the stick refuses an untagged
command and accepts a tagged one; logs `auth.selftest`).

The Mac test harness in `tools/e2e/` (`e2e.py`) drives the stick over USB, takes screenshots with pymobiledevice3,
reads them with Vision OCR and follows the app's `E2E` log events. Scenarios are in `tools/e2e/scenarios/`.

## Talking to the stick

On the Run tab, tap **Start session** once (iOS asks to share the screen). Then hold **A** on the stick from
anywhere, say what to do and let go: the stick streams the recording (encrypted) to the app, which transcribes it
on the phone, shows "Heard: …" on the stick for 2 s (B cancels) and runs it. Questions the agent has ("Which
size?") appear on the stick; hold A to answer. The session ends when the iPhone locks; the stick then says so.

## Agent widget and Laya training

The **Mantiza agent** widget (full Home Screen page on iOS 27, also large and Lock Screen sizes) shows what the
agent heard, each step, the screen it last saw and a result card Claude writes when a task is done.

Every decision Claude makes is saved as a Laya training row (`Documents/training/`, gold rows from successful
runs). On the Mac: `tools/laya/train.sh` pulls them, fine-tunes Laya, tests it on held-out runs and only
promotes it (served as model `mantiza` by `tools/laya/serve.sh`) when its gated accuracy is at least 95%.
`tools/laya/install-agent.sh` keeps the server running at login.

## Tabs

Run (text or voice request, live steps, save as a workflow), Workflows (saved runs, replay, pin), Device (stick,
pairing code, pointer, calibration, tests), Look (share the screen, OCR, tap a read element), Settings (AI keys,
model choice, Safety and Privacy). The widget extension `MantizaWidgets` holds the Live Activity (step n/m, Stop,
Approve) and the workflow widget (Now / Pinned / Recent tabs).

## Layout

- `Mantiza/Board`: Bluetooth link to the stick, command protocol, session auth (`SessionAuth`, secret in the
  Keychain per stick), gestures (`Hands`), `MockBoard`.
- `Mantiza/Calibration`: tap probe, 3x3 fit and 5-point check.
- `Mantiza/Eyes`: screen capture (ScreenCaptureKit), settle detection, Vision OCR into screen elements.
- `Mantiza/AI`: big brains (`ClaudeBrain`, `GeminiBrain`), the quick picker (`SystemOnePicker`: Laya on your own
  server via `tools/laya/serve.sh`, or TypeSafe's Jev), keys in the Keychain.
- `Mantiza/Agent`: the agent loop (`AgentRunner`), safety rules, approvals from stick or phone, fast paths (Messages,
  Maps, Shortcuts links).
- `Mantiza/Workflows`: run log with step timings (`RunStore`), learned workflows and suggestions (`WorkflowStore`).
- `Mantiza/UI`: the screens.
- `Shared`: Live Activity attributes and intents, widget data (used by both targets).
- `Mantiza/App/Log.swift`: `E2E {json}` event lines in the device log for the Mac test harness.
