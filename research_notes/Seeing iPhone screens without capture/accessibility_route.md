# Accessibility route: getting the text and structure of an iPhone screen to the Mantiza stick or app without screen capture

Context: Mantiza is an iOS 27 app plus an ESP32-S3 stick that acts as a Bluetooth HID mouse and keyboard through AssistiveTouch. Notes written 2026-11-03. Most sources predate iOS 27 (dates are given). Nothing here was tested on iOS 27. Confidence is marked per item: High / Med / Low.

## 1. VoiceOver plus a refreshable braille display: can an ESP32 pose as a HID braille display and receive the focused text?

### Takeaway
On paper this is the most promising channel. Apple's own engineers point developers to the USB-IF HID Braille Display usage page (0x41, HUTRR78). VoiceOver sends the braille display the text of the line or item under the VoiceOver cursor. Its braille key commands can move focus (next, previous, first, last item; activate; Home; scroll; item chooser), so a device could in principle walk every element on a screen. It can also toggle speech off and turn on screen curtain. But nobody has publicly shown a working BLE HID braille emulator on iOS. Two Nordic nRF52840 attempts (iOS 12.1.4 and iOS 14) failed to get the iPhone to recognize the device as a braille display. The one ESP32 project is an unfinished sketch. Overall feasibility: Med-Low until someone tests on a device. Payoff if it works: High.

### Cited Findings
- **Protocol Apple points to.** In October 2023, an Apple "Frameworks Engineer" answered a developer building a refreshable display by citing only the USB-IF document "HUTRR78 – Creation of a Braille Display Usage Page" (https://usb.org/sites/default/files/hutrr78_-_creation_of_a_braille_display_usage_page_0.pdf) as "the Braille HID profile" to adopt. The reply mentions no MFi, no Bluetooth-specific guidance and no API. — [Apple Developer Forums thread 740301](https://developer.apple.com/forums/thread/740301)
- **Usage page 0x41 is the Braille Display page.** NVDA detects HID braille displays by checking that the top-level collection's usage page is 0x41. BRLTTY has a generic HID braille driver (`Drivers/Braille/HID/braille.c`) that parses the report descriptor at startup to find the braille I/O report ID, the output cell array and the router key bits. — [BRLTTY HID driver (googlesource mirror)](https://third-party-mirror.googlesource.com/brltty/+/refs/heads/main/Drivers/Braille/HID/braille.c); [NVDA HID braille commit](https://app.semanticdiff.com/gh/nvaccess/nvda/commit/00cd67b737bc5b23a6f5e31cf28110b64ebf2fee)
- **Android uses the same standard.** Android's `BrailleDisplayController` (API 35) hands over the HID report descriptor in `onConnected` and expects `write()` bytes formatted to that descriptor. This shows HID braille is now the cross-platform standard. — [Android BrailleDisplayController](https://developer.android.com/reference/android/accessibilityservice/BrailleDisplayController)
- **Sample descriptor from the ESP32 project** (brailletouch/HID-braille-ESP32, GPL-3.0, 8 commits, no working code):
  - Top level: Usage Page 0x41, Usage 0x01 (Braille Display), Application collection.
  - Keys: dots 1–8 at usages 0x0201–0x0208; Left/Right Space at 0x020A/0x020B; joystick at 0x0210–0x0214; Face/Left/Right Controls at 0x020C/0x020D/0x020E.
  - Router: Router Set 1 at 0xFA, Router Key at 0x100.
  - Cell output: 8-bit cells, Report Count 20, built on Espressif's Bluedroid BLE HID demo.
  - The cell usage is suspect. The sample uses 0x02, but NVDA's enum gives Braille Row = 0x02 and Eight Dot Braille Cell = 0x03. The project never mentions testing with iOS or VoiceOver.
  — [GitHub brailletouch/HID-braille-ESP32](https://github.com/brailletouch/HID-braille-ESP32)
- **Failed BLE attempt, iOS 12.1.4 (about 2018–2019).** An nRF52840 worked as a standard BLE HID device but was "not recognized" when added as a braille display in VoiceOver > Braille. The only reply guessed that BLE braille is not in the Accessory Interface Specification and might need iAP2 (MFi). — [Nordic DevZone 43602](https://devzone.nordicsemi.com/f/nordic-q-a/43602/ble-hid-braille-on-ios)
- **Failed BLE attempt, iOS 14.** Another nRF52840 braille display was "not recognized" by the iPhone. Nordic said it has "no experience or examples" for braille with VoiceOver and suggested sniffing the air traffic. The thread was never answered. — [Nordic DevZone 88287](https://devzone.nordicsemi.com/f/nordic-q-a/88287/braille-display-not-correctly-work-on-ios-14)
- **HID braille on iOS has mostly been USB.**
  - AppleVis describes HID as letting some displays connect "through USB". It says few displays support the "new HID standard established in 2018". Some displays must be switched into USB HID mode, and the connection needs Apple's adapter plus power.
  - Models reported working over HID (2021, iOS 14.7): Mantis Q40, Brailliant BI 20/40X, Chameleon.
  - Bluetooth is the common route, with over 30 supported models (these mostly use vendor protocols).
  — [AppleVis braille intro guide](https://applevis.com/guides/using-braille-display-ios-introduction); [AppleVis iFeelIt podcast 2021](https://www.applevis.com/podcasts/ifeelit-introduction-using-braille-displays-ios-2021-edition)
- **iOS 16 fix for USB HID.** An AppleVis bug says a USB HID display showed no options in the braille menu. It was marked fixed in iOS 16.0, and the workaround until then was "connect through Bluetooth instead of USB". That workaround implies that at least some displays' Bluetooth mode, possibly vendor protocol rather than HID, worked. — [AppleVis bug (summary via search; page returned 403 on fetch)](https://applevis.com/bugs/ios/after-connecting-usb-hid-compatible-braille-display-there-are-no-options-or)
- **What VoiceOver sends to the display** (Apple VoiceOver guide; the Mac version is the explicit one):
  - The display "describes the entire line where the VoiceOver cursor is focused".
  - It pans to follow the cursor and shows the text-entry cursor position with dots 7 and 8.
  - Status cells can carry extra line information.
  - On the Mac, VoiceOver shows multiple items, not just the focused one, by default. This is configurable.
  — [Apple VoiceOver guide vo15607](https://support.apple.com/guide/voiceover/vo15607/mac)
- **Universal iOS braille commands** (Apple's "Common braille commands for VoiceOver"). These give a device full control of VoiceOver focus:

  | Command | Keys |
  |---|---|
  | Next item | Dot 4 + Space |
  | Previous item | Dot 1 + Space |
  | First item | Dots 1-2-3 + Space |
  | Last item | Dots 4-5-6 + Space |
  | Item chooser | Dots 2-4 + Space |
  | Activate (tap) | Dots 3-6 + Space |
  | Home | Dots 1-2-5 + Space |
  | App switcher | Dots 1-2-5 + Space, pressed twice |
  | Read all | Dots 2-4-5-6 + Space |
  | Toggle speech | Dots 1-3-4 + Space |
  | Toggle mute | Dots 1-3-4-7 + Space |
  | Screen curtain | Dots 1-2-3-4-5-6 + Space |
  | Scroll page up / down / left / right | Dots 3-4-5-6 / 1-4-5-6 / 2-4-6 / 1-3-5 + Space |
  | Pan left / right | Dot 2 / Dot 5 + Space |

  — [Apple Support 118665](https://support.apple.com/en-asia/118665)
- **Router keys double-tap the item.** Display-specific Apple pages map "Router" to "Double-tap selected item" (for example Brailliant B 80). — [Apple Support 103743](https://support.apple.com/en-au/103743)

### Inferences
- **What one cell row carries.** If an ESP32 is accepted as a HID braille display, each output report carries one row of braille cells: the focused item's label, value and trait abbreviations, possibly the whole visual line. There is no element frame (position) and no tree. Positions would have to be inferred by also driving the AssistiveTouch pointer, or by matching against a screenshot. Confidence: Med.
- **The text arrives as braille, not ASCII.** The stick would need the braille output table set to Unicode or "computer braille" (8-dot uncontracted) in VoiceOver > Braille > Output, then a reverse table on the stick. Contracted (Grade 2) output would need back-translation, for example with liblouis. Confidence: Med-High, but on-device testing is needed.
- **Walking the screen is slow.** Next item (Dot 4 + Space), read the cells, repeat. Each step costs one BLE HID input report, VoiceOver's focus update and one output report. A guess is about 50–200 ms per element, so 2–10 s for a screen of 50 elements. This is unmeasured. Making the display report a very large cell count (if iOS honors usage 0x05, Number of Braille Cells, and HID supports it) might put more of a line in one report. Confidence: Low.
- **VoiceOver changes the input model.** With VoiceOver on, single taps focus and double taps activate. Whether an AssistiveTouch pointer click acts as a direct activation or as a VoiceOver focus under VoiceOver is not documented (see section 4). Toggling VoiceOver per perception step, for example with the Accessibility Shortcut (triple-click side button, which the stick can't press) or a Shortcuts action, adds seconds of latency each time. Confidence: Med.
- **Speech and display can be silenced.** Speech-off (Dots 1-3-4) or mute (Dots 1-3-4-7) and screen curtain are all braille commands, so the stick could silence VoiceOver and blank the display. Screen curtain would also blind any camera-based route.
- **The iAP2 hypothesis is likely outdated.** The 2018 Nordic reply guessed iAP2, before Apple endorsed HID braille. A plausible reason both Nordic attempts failed is that iOS's BLE HID braille path, if it exists, is keyed to specific descriptor contents or vendor/product IDs. Another is that iOS only accepted HID braille over USB at the time. Confidence: Low.
- **Wired USB would be a different path.** The ESP32-S3 has native USB OTG and could present a USB HID braille device over Lightning with Apple's camera adapter. That is a wired path, which conflicts with the Lightning port's other uses, but it is the path reported to work with real displays. Confidence: Med.

### Gaps
- **Bluetooth support for 0x41 is unconfirmed.** No source confirms that iOS (any version, including 27) accepts a Bluetooth LE HID device with usage page 0x41 as a braille display. This is the go/no-go question and needs an on-device test with an ESP32 descriptor.
- **I could not retrieve HUTRR78** for exact usages (cell counts, usage 0x05, report layout).
- **Output tables and contents are unknown.** It is undocumented exactly what iOS VoiceOver writes for an element: label, value, trait abbreviations ("btn", "hdg") and container info. Which output tables are available on iOS 27 is also unknown.
- **No latency figures exist** for braille-driven navigation.
- **No public project has done this.** I found no BRLTTY-based or open-source firmware that emulates a braille display towards iOS. BRLTTY drives displays and does not emulate them.
- **The display-row format is unconfirmed on iOS.** Whether iOS sends the whole visual line or only the item is documented clearly only for the Mac guide.

## 2. Voice Control overlays, Switch Control scanning, Full Keyboard Access, AssistiveTouch Dwell: does any of them export element info?

### Takeaway
I found no evidence that any of these send element names, frames or focus to an app or an external device. They are visual or on-device-only features. The braille path above is the only documented accessibility *output* channel to external hardware. Confidence: Med-High (based on no evidence found, plus the platform's design).

### Cited Findings
- The braille display (and Braille Screen Input) is the documented external channel that carries VoiceOver content. Braille Screen Input uses "the same commands you use with a refreshable braille display". — [Apple iPhone guide, Braille Screen Input](https://support.apple.com/en-ge/guide/iphone/iph10366cc30/ios)
- AssistiveTouch pointer docs describe clicking items and navigating the AssistiveTouch menu only. They mention no feedback channel. — [Apple Support 111775](https://support.apple.com/en-ug/111775)

### Inferences
- **Voice Control** numbers and names are on-screen overlays. With them shown, the screen still has to be captured to read them, which defeats the purpose. Third-party apps can't read them (iOS sandbox).
- **Switch Control** scanning highlights a sequence of items visually, and could speak them with "Speech" on. It sends nothing to a Bluetooth switch device, because switches are input-only.
- **Full Keyboard Access** draws a focus ring. A HID keyboard (the stick) can move focus with Tab and arrow keys and activate with Space, but HID keyboards get no output report with focus text, only LED reports. This makes it a good *actuation* method that is blind for perception.
- **Indirect channel through speech.** VoiceOver or Spoken Content could speak the focused item over Bluetooth audio to a device that runs speech-to-text. The ESP32-S3 can't easily act as a Bluetooth audio sink for this: classic A2DP needs Bluetooth Classic, which the S3 lacks, and LE Audio is uncertain. Result: lossy, slow, Low feasibility.

### Gaps
- I found no source on iOS 27 accessibility changes that might add an export API. If time allows, check the WWDC 2026 accessibility sessions.

## 3. XCUITest / WebDriverAgent: reading any app's element tree on a developer-mode device, with or without a Mac

### Takeaway
XCUITest can query other apps' full accessibility trees (labels, frames, types) by bundle ID. This is how Appium/WDA and agent tools like callstack's agent-device work on physical devices. It needs a developer-signed runner and a host to *launch* the test session through testmanagerd. go-ios, tidevice and pymobiledevice3 can do this from Linux or Windows, with no Mac after the first install. As of iOS 17 (2024 reports), the test session stops when the phone loses its link to the host. For Mantiza this means the Mac, or possibly another host, must stay reachable. The "Laya" Mac link already in Mantiza's architecture may make this acceptable. Feasibility: High with a host, Low with no host. Confidence: Med-High.

### Cited Findings
- **The XCUITest pattern for other apps.** A resident runner builds `XCUIApplication(bundleIdentifier:)` and returns its tree (`debugDescription`) from a small server, which makes the tree of any app by bundle ID readable. — [DEV Community post](https://dev.to/joduchan/coordinate-based-ui-tests-break-so-we-read-the-accessibility-tree-instead-from-inside-the-3gl7)
- **Snapshot cost is fixed; queries are cheap.** Snapshotting a single element costs about the same as snapshotting the whole screen, while queries on an existing snapshot are "almost negligible". The efficient pattern is one snapshot, then many queries. The source gives no absolute times. — [Appelium snapshot-query article](https://developer.appelium.com/engineering/snapshot-query/)
- **Failure modes on hard screens.** callstack agent-device reports that a snapshot on a problematic screen "grinds ~30s". Its project then penalizes the XCTest channel for a 120 s window. XCTest serialization sometimes fails with `kAXErrorIllegalArgument`, and compact snapshots can degrade to only the app root. Physical devices keep using XCTest; the private-AX fallback added 2026-06-12 is simulator-only. — [agent-device issue #701](https://github.com/callstack/agent-device/issues/701); [PR #1158](https://github.com/callstack/agent-device/pull/1158)
- **go-ios commands and platforms.**
  - Commands: `ios runwda`, `ios runtest` and `ios runxctest`.
  - Platforms: Linux, Windows and macOS. Windows needs wintun.dll.
  - iOS 17+ requires a host-side tunnel daemon (`sudo ios tunnel start`).
  — [go-ios GitHub](https://github.com/danielpaulus/go-ios)
- **Xcode is needed once.** A typical flow uses `xcodebuild build-for-testing` once to install the WDA runner, then go-ios to "wake up a previously installed WDA Runner". Support for iOS 17 was described as experimental. — [@navaiguide/ios on npm](https://www.npmjs.com/package/@navaiguide/ios)
- **Appium supports preinstalled WDA.** Appium's XCUITest driver can start a preinstalled WDA. pymobiledevice3, go-ios, tidevice and ios-deploy are named as install/launch tools. — Appium "Run Preinstalled WebDriverAgentRunner" guide (the 9.9 docs URL now returns 404; cited via search snippet: https://appium.github.io/appium-xcuitest-driver/9.9/guides/run-preinstalled-wda)
- **iOS 17: WDA stops on disconnect.** WDA started through automation "immediately stops when iPhone is disconnected (USB/network) from the MacBook". The same post says that below iOS 17 it could be run manually on the device. — [Appium Discuss, 2024-04-30](https://discuss.appium.io/t/running-wda-on-ios-17/42392)
- **Launching WDA from its icon.** On iOS 17.1.2, launching WDA by tapping its icon crashed. A commenter got an IPA-repackaged WDA to start from the icon on 17.2; the maintainer said launching as an xctest process is the supported way. — [appium/WebDriverAgent issue #822](https://github.com/appium/WebDriverAgent/issues/822)
- **Visible indicator.** iOS 15+ shows an "Automation Running" overlay while XCTest automation is active, dismissible by pressing both volume buttons. — [Appium XCUITest troubleshooting (mirror)](https://scriptagc.wasmer.app/https_appium_github_io/appium-xcuitest-driver/latest/guides/troubleshooting)
- **iOS 18 reports.** WDA was auto-uninstalled after script errors on iOS 18.6 (iPhone 13 mini). WDA worked over Wi-Fi on iOS 18.0.2. — [TesterHome 42764](https://testerhome.com/topics/42764)
- **tidevice.** It is described as launching WDA without xcodebuild, so once WDA is installed "you can leave the Mac behind". This was pre-iOS 17; tidevice does not support the iOS 17 tunnel. — [Tencent Cloud article](https://developer.cloud.tencent.cn/article/1858108); [TesterHome 29230](https://testerhome.com/topics/29230)

### Inferences
- **For Mantiza this is the highest-fidelity non-capture route.**
  - What it gives: a full element tree with frames, labels, values and types for the foreground app, Springboard included (bundle `com.apple.springboard`). It can also tap directly, which would make the HID stick optional.
  - What it costs: a host (the Mac, which Mantiza already reaches as "Laya", or a Raspberry Pi running go-ios with the tunnel) must start the XCTest session and stay connected over USB or network. An iOS 17+ network tunnel may survive on the same Wi-Fi, but this is unverified on iOS 27.
  - Confidence: Med.
- **The Mantiza app can't run XCUITest itself.** XCUITest needs the testmanagerd session that a host opens. Mantiza can instead talk over localhost HTTP to a WDA (or custom XCTest runner) on the same phone. That keeps perception on the phone, but it is still tied to the host's session. Confidence: Med.
- **Latency.** No published figures. From general Appium experience (not sourced here), expect hundreds of ms to a few seconds per full `/source` snapshot on simple screens, and tens of seconds on pathological ones (agent-device's ~30 s). Benchmark on the iPhone 13 running iOS 27.2.
- **Free Personal Team signing works but expires.** A free Personal Team can sign the WDA runner, but its profiles expire after 7 days, which means weekly re-installs. Developer Mode must be on. Confidence: Med (general knowledge, not sourced here).
- **UX cost.** The "Automation Running" overlay shows on screen, and the session is fragile: it dies on disconnect and WDA can be auto-uninstalled. Apps that detect automation could also refuse to run.

### Gaps
- **Host-free running on iOS 27 is unconfirmed.** No source confirms whether iOS 18–27 lets an XCTest runner keep going after the host link drops, or whether a Wi-Fi tunnel host counts as "connected".
- **No measured per-snapshot latency** on a physical device.
- **pymobiledevice3's exact XCTest launch support** for iOS 17+ was not verified in this session.

## 4. Cross-cutting: VoiceOver with the AssistiveTouch pointer, speech muted, screen curtain; verdict per route

### Takeaway
How the AssistiveTouch pointer behaves with VoiceOver on is undocumented and needs a device test. Speech mute and screen curtain can both be toggled from braille commands. Summary of routes:

| Route | Feasibility on a personal developer build | Indicators / UX cost | Latency | Confidence |
|---|---|---|---|---|
| (a) BLE HID braille emulation on the ESP32 | Unproven; the decisive test is cheap | VoiceOver on changes gestures | About 50–200 ms per element (guess) | Low-Med |
| (b) USB HID braille emulation from the S3 over the Lightning adapter | Plausible, since real HID displays work over USB | Occupies the port | Same as (a) | Med |
| (c) XCUITest/WDA with a host | Works | "Automation Running" overlay, host required | About 0.3–3 s per snapshot (unmeasured) | Med-High |
| (d) Voice Control, Switch Control, Full Keyboard Access | No data channel | — | — | High that it doesn't work |

### Cited Findings
- **No documentation on pointer plus VoiceOver.** There is no official documentation on pointer clicks while VoiceOver is on. The only community thread (2014) covers the AssistiveTouch menu under VoiceOver, not pointer clicks. — [AppleVis forum](https://www.applevis.com/forum/voice-over-and-assistive-touch)
- **Silence and blanking commands exist.** Speech toggle, mute toggle and screen curtain are braille commands. — [Apple Support 118665](https://support.apple.com/en-asia/118665)

### Inferences
- **Hybrid scheme.** Use braille Activate (Dots 3-6 + Space) or router keys for actions while VoiceOver is on, and use the AssistiveTouch pointer only with VoiceOver off. This avoids depending on undocumented pointer behavior.
- **On-device test plan:**
  1. Flash the ESP32-S3 with a BLE HID descriptor on usage page 0x41 and see whether it appears in VoiceOver > Braille. Also try it as a USB device through the camera adapter.
  2. Log the output reports while swiping through Settings.
  3. Time Dot 4 + Space round trips.
  4. Check pointer clicks with VoiceOver on.

### Gaps
- Pointer behavior under VoiceOver on iOS 27.
- Whether VoiceOver can stay on but silent without disturbing other audio (for example push-to-talk).
- Any iOS 27 changes to braille or HID support.
