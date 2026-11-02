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
- `MANTIZA_ENTITLEMENTS`: entitlements file (App Group for the widget), empty by default so a Personal Team can sign.

## Layout

- `Mantiza/Board`: Bluetooth link to the stick, command protocol, gestures (`Hands`), `MockBoard`.
- `Mantiza/Calibration`: tap probe, 3x3 fit and 5-point check.
- `Mantiza/UI`: onboarding, Device, calibration screens.
- `Mantiza/App/Log.swift`: `E2E {json}` event lines in the device log for the Mac test harness.
