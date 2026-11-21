# Software-only (no extra hardware) routes for an iPhone app/agent to tap and type in other apps

Scope: every non-hardware route other than emulating a Bluetooth mouse from another device. Current as of 2026-10-28 (iOS 27 shipped Sept 2026). Each fact is labelled **[confirmed]** (official Apple/project docs), **[reported]** (one secondary or community source), or **[unconfirmed]** (my background knowledge, not verified in this session; treat it as a lead).

Bottom line up front: no route was found that lets a normally installed or sideloaded app, alone on a stock iPhone, inject taps into other apps. The only working "software" injectors are XCUITest/WebDriverAgent, which needs a Mac to start each session on iOS 17+, and Apple's own accessibility features (Switch Control, Voice Control). The accessibility features are driven by a human or by another Apple device. Third-party code cannot drive them except through crude tricks such as playing audio at Voice Control.

## 1. Switch Control "Use Other Devices", platform switching, and Control Nearby Devices

### Takeaway
"Use Other Devices" lets one Apple device's Switch Control drive another Apple device on the same Wi-Fi network and Apple Account, so Mantiza would need a second Apple device plus a switch input. "Control Nearby Devices" is limited to system buttons and media, with no taps. No API lets a third-party app act as a software switch. Switch sources are the screen, the camera (head movements), or external Bluetooth/MFi switches, which is hardware.

### Cited Findings
- **[confirmed]** Use Other Devices: "control your other Apple devices remotely on the same Wi-Fi network without adjusting any switch connections". It requires the same Wi-Fi, the same Apple Account in iCloud, and Switch Control turned on on the controlling device. A Mac target must enable "Allow platform switching to control your computer". To stop, hold the switch for 10 s or choose Device > Stop Using Device. Apple's examples of targets are Mac and Apple TV. The page does not say whether an iPhone being controlled gets full point-and-tap control. — [Apple Support 118667](https://support.apple.com/118667)
- **[confirmed]** Switch sources are External (a Bluetooth or Made-for-iPhone switch, connected first), Screen (tap or long-press), or Camera (head movements on a TrueDepth device). Actions include tap, gestures and saved custom gestures, scroll, and hardware-button presses (Home, Control Center, volume, screenshot, and so on). Selection modes are item, point, and manual scanning. — [Apple Support 119835](https://support.apple.com/en-us/119835)
- **[reported]** Control Nearby Devices (iOS 16 / iPadOS 16 / watchOS 9) is limited to Home, App Switcher, Notification Center and Control Center, media (play/pause, next/previous, volume), and similar actions. It "cannot open apps or tap the controlled device's screen". It needs the same Apple ID and the same Wi-Fi. — third-party guides: [Gadget Hacks](https://ios.gadgethacks.com/how-to/use-your-iphone-apple-watch-as-remote-control-for-your-ipad-using-hidden-built-feature-0385233), [AnyViewer](https://www.anyviewer.com/how-to/remote-control-an-ipad-from-iphone-2578.html), [HelpWire](https://www.helpwire.app/blog/remote-control-iphone/)
- **[reported]** Third-party guides describe Switch Control platform switching as letting one Apple device "fully command another", with each switch activation triggering an action on the other device. They also call it clunky to set up. — [AnyViewer](https://www.anyviewer.com/how-to/remote-control-an-ipad-from-iphone-2578.html)

### Inferences
- Platform switching cannot work on a single iPhone, because it needs a second Apple device running Switch Control. Even then, the controlling side still needs a switch input. A Mac or iPad with Switch Control could drive the iPhone, but a person, not software, operates the scanning. Whether Mac-side scripting could fake switch presses on the Mac was not checked.
- Control Nearby Devices cannot tap inside apps, so it is useless for Mantiza beyond Home and App Switcher.
- An app cannot register itself as a Switch Control switch. The only external switch types are Bluetooth/MFi hardware, which makes this the same class of route as the ESP32 mouse.

### Gaps
- Apple's current iPhone User Guide pages for "Control Nearby Devices" and "Use Other Devices" (iOS 27) would not render via fetch, so Apple has not confirmed the exact action list.
- No source documents whether "Use Other Devices" exposes point scanning and taps when the target is an iPhone (versus Mac/Apple TV).

## 2. Voice Control (custom commands, grid/tap, self-speaking)

### Takeaway
Voice Control works system-wide and can tap by label, by number or grid, or by natural-language description (new in iOS 27). Custom commands can replay recorded gestures or run Shortcuts. No reliable source documents an app on the same phone driving Voice Control by playing synthesized speech through its own speaker. The idea is plausible but unproven, and it is likely fragile.

### Cited Findings
- **[confirmed]** Voice Control custom commands, set up under Settings > Accessibility > Voice Control > Customize Commands > Create New Command, can insert text, run a recorded gesture, run a Shortcut, or play back recorded actions. — [Apple Support HT210418](https://support.apple.com/HT210418)
- **[reported]** In iOS 27, Apple Intelligence-powered Voice Control lets users describe the target in natural language ("tap the purple folder" in Files, "tap the guide about best restaurants" in Maps) with no numbered overlay. Apple says it helps with unlabeled elements. Apple announced it in May 2026, and MacRumors covered it on 2026-05-20. — [Gadget Hacks](https://apple.gadgethacks.com/news/ios-27-ai-voice-control-what-it-tells-us-about-the-siri-revamp/)
- **[reported]** Voice Control can pick up ambient voices or song lyrics, though non-lyrical music is fine. This suggests audio played through a speaker can trigger it, but no source tests audio coming from the phone itself. — summarised in search of [inairspace guide](https://inairspace.com/de/blogs/learn-with-inair/how-to-control-your-iphone-without-touching-it-complete-hands-free-guide) (low-quality source)
- **[confirmed]** The 2019 Voice Control tech brief describes on-device recognition with "show numbers" and "show grid" overlays. — [Apple Voice Control Tech Brief](https://apple.com/accessibility/pdf/Voice_Control_Tech_Brief_Sept_2019.pdf)
- **[unconfirmed]** iOS generally ducks or pauses other audio while the mic is active for recognition, and echo cancellation on the built-in mic may suppress the device's own speaker output. Either could block self-speaking.

### Inferences
- Self-speaking is the only software way to "drive" an Apple accessibility input from the same phone. It would need: Voice Control left on (the user enables it); Mantiza keeping audio playing in the background (needs the audio background mode, and App Store review may object); and Voice Control accepting speaker audio through echo cancellation. Even if it works, it would be slow (about 1–2 s per command), noisy, socially awkward, and unreliable. It also cannot type arbitrary text quickly, though "type <text>" dictation may help.
- A safer variant is to have the *user* speak while Mantiza only shows hints. That is not autonomous.

### Gaps
- No Reddit, AppleVis or developer report was found of self-triggering Voice Control from the same iPhone's speaker. Someone needs to test it on a device.
- I could not verify whether Voice Control keeps listening while another app plays audio in the foreground or background.

## 3. Shortcuts, App Intents, Siri onscreen awareness, accessibility APIs (iOS 26/27)

### Takeaway
App Intents and iOS 27's Siri expose *each app's own declared actions* to Siri, Spotlight and Shortcuts. They do not let a third-party app tap into another app's UI. Apple's own Siri gains onscreen awareness and in-app actions, but only through intents that apps adopt. No public API gives a third-party agent generic UI control of other apps.

### Cited Findings
- **[reported]** iOS 27 "Siri AI" has full onscreen awareness. It can interpret what is on screen and act on it (for example, mapping an address from a text or adding it to a calendar). It rolled out with iOS 27 in Sept 2026, in English first. — [iPhone in Canada, 2026-09-14](https://www.iphoneincanada.ca/2026/09/14/siri-ai-is-now-available-across-ios-27-ipados-27-and-macos-27/), [Digital Trends](https://www.digitaltrends.com/phones/siri-ai-ios-27-launch/)
- **[reported]** App Intents is how apps describe their actions and entities to the system, and apps without intents are "effectively invisible" to Siri AI. iOS 27 lets users act on third-party apps through Siri or Spotlight without opening them. — [lavx news (WWDC 2026)](https://news.lavx.hu/article/wwdc-2026-ios-27-the-new-siri-ai-and-what-it-means-for-app-developers), [Braze](https://www.braze.com/resources/articles/2026-wwdc-ios-27-updates)
- **[reported]** Supported Siri AI devices are iPhone 15 Pro or newer and M-series iPads and Macs (beta 6). Sources disagreed on whether onscreen awareness was staged. — [BornCity](https://borncity.com/news/ios-27-beta-6-apple-erweitert-siri-ai-um-on-screen-awareness/)
- **[unconfirmed]** Shortcuts has no "tap at x,y" action for other apps. The only coordinate-based automation in Shortcuts is indirect, through a Voice Control custom gesture, and that still needs a voice trigger. UIAccessibility APIs only describe or act on the calling app's own views. There is no public API to read or press elements in other apps (unlike macOS AXUIElement).

### Inferences
- Mantiza can *call* other apps' App Intents through Shortcuts (for example, by running user-installed shortcuts via URL schemes) where those intents exist. This covers structured tasks (messages, notes, timers) but not arbitrary UI.
- Apple's agentic onscreen actions are Siri-only. A third-party app cannot become the agent.

### Gaps
- The Apple doc page on onscreen content for Siri returned 404, so I could not confirm the exact API names (for example, view annotations or App Schemas) or confirm that they are read-only and limited to the app's own content.
- I did not confirm whether iOS 27 lets third-party apps invoke *other* apps' App Intents directly, outside Shortcuts.

## 4. Developer routes: WebDriverAgent / XCUITest, on-device tunnels, signing lifetime, EU distribution

### Takeaway
XCUITest/WebDriverAgent (WDA) really does synthesize taps and typing in any app, because the test runner gets privileged event synthesis through testmanagerd. On iOS 17+, though, WDA stops when the host Mac or PC disconnects, and starting a session needs a host-side RemoteXPC/CoreDevice tunnel. Community "loopback VPN" tools (StikDebug + LocalDevVPN) prove an iPhone can open developer-service connections to itself using a pairing file, but they are used for JIT. No project was found that runs WDA from the phone alone. Free signing lasts 7 days and paid signing lasts 1 year.

### Cited Findings
- **[confirmed]** WDA is a WebDriver server running on the device that exposes the XCUITest API. — [Appium XCUITest driver docs](https://appium.readthedocs.io/en/latest/en/drivers/ios-xcuitest/)
- **[confirmed]** Preinstalled WDA can be launched on iOS/tvOS 17+ (WDA v13+). It starts "over a RemoteXPC tunnel via CoreDevice's process control service", falling back to `xcrun devicectl device process launch`. — [Appium: Run Preinstalled WDA](https://appium.github.io/appium-xcuitest-driver/latest/guides/run-preinstalled-wda/)
- **[reported]** iOS 17 moved device communication from TCP to QUIC + RemoteXPC, which broke older cross-platform tools. Launching via devicectl requires removing XCTest frameworks from the bundle. — [Thuyen's Corner, WDA deep dive](https://trinhngocthuyen.com/posts/tech/mobile-e2e-wda/)
- **[reported]** On iOS 17, WDA "immediately stops when iPhone is disconnected (USB/network) from the MacBook". Before iOS 17 it could be started manually and kept running. Forum post dated 2024-04-30. — [Appium Discuss](https://discuss.appium.io/t/running-wda-on-ios-17/42392)
- **[reported]** The setup in a June 2026 guide is: build WDA once in Xcode with a signing team, trust the developer cert on the phone, and the runner serves on port 8100. Free Apple ID profiles expire in 7 days and are limited to 3 devices. A paid account ($99/yr) gives a 1-year profile. WDA cannot pass Apple ID password or system security prompts. — [Jean Galea, 2026-06-25](https://jeangalea.com/control-automate-iphone-webdriveragent/)
- **[reported]** Commercial "AI agent controls iPhone" products (Mobilerun via mobilerun-ios, Minitap mobile-use) use this WDA model with a host or cloud bridge. — [Jean Galea](https://jeangalea.com/control-automate-iphone-webdriveragent/), [Minitap docs](https://www.minitap.ai/docs/mobile-use-sdk/physical-ios-quickstart), [DEV Community](https://dev.to/priya_negi_9ffd29931ea408/i-automated-my-iphone-using-this-ai-agent-56pp)
- **[confirmed]** Developer Mode is required on iOS 16+ to run developer-signed test runners. — [Appium Discuss iOS 17 thread](https://discuss.appium.io/t/unable-to-launch-ios-webdriver-agent-manually-on-ios-17-x-devices/41492), [Thuyen's Corner](https://trinhngocthuyen.com/posts/tech/mobile-e2e-wda/)
- **[reported]** StikDebug uses a loopback VPN (LocalDevVPN) and a pairing file (.plist/.mobiledevicepairing, generated once from a computer with `idevice pair`) to let the iPhone talk to its own lockdownd and developer services. Its main use is enabling JIT for sideloaded apps. It supports iOS 26.0–26.3. Release 3.1.0 added iOS 26.4, but DDI mounting was broken there. A 26.4 beta "lockdownd dropping connections" issue broke the loopback for a while. The pairing file must be regenerated after an update or reset. — [StikDebug GitHub](https://github.com/StephenDev0/StikDebug), [release 3.1.0](https://newreleases.io/project/github/StephenDev0/StikDebug/release/3.1.0), [NeoSign wiki](https://neosignios.github.io/wiki/guide/guides/enabling-jit)
- **[confirmed]** EU alternative distribution (iOS 17.4+) still requires Notarization for all apps (automated plus human review). Apps installed this way pass install-time checks, and Apple can block launches of known malware. — [Apple: alternative app marketplace](https://developer.apple.com/support/alternative-app-marketplace-in-the-eu), [Apple Support 118110](https://support.apple.com/en-mide/118110), [Apple: apps in the EU](https://developer.apple.com/support/apps-in-the-eu/)

### Inferences
- A possible "software-only" architecture is a one-time pairing file from a computer, plus an on-device loopback VPN, plus a client that speaks RemoteXPC/CoreDevice to the phone itself to launch the preinstalled, developer-signed WDA and keep its testmanagerd session alive. Tools exist for every piece (go-ios, pymobiledevice3 and the `idevice` Rust library speak these protocols, and StikDebug shows loopback works). No public project was found doing the whole chain, so it is unproven. It would also be fragile across iOS point releases, as the 26.4 breakage shows, and needs Developer Mode and re-signing every 7 days (free) or 365 days (paid).
- This cannot ship on the App Store, and Notarization in the EU would very likely reject an app that drives other apps through developer services. It is a power-user or prototype path only.
- A cloud or host Mac bridge (as Mobilerun and Minitap do) works today but needs a computer, which defeats "phone-only" and still counts as extra hardware unless the user already owns a Mac.

### Gaps
- No source confirmed whether an on-device client can start an XCTest session (testmanagerd) over the loopback, as opposed to just process launch or debugserver for JIT. This is the key unknown.
- No source was found on how long a WDA session survives on iOS 26/27 once started (screen lock, backgrounding, memory pressure).
- I did not look at the go-ios / pymobiledevice3 docs for an "on-device tunnel" (userspace tunnel) mode.

## 5. Universal Control / iPhone Mirroring in reverse

### Takeaway
Both features control an iPhone or iPad *from a Mac*. Neither lets software on the iPhone control the iPhone, and both need a Mac (hardware).

### Cited Findings
- **[reported]** iPhone Mirroring is not available in the EU, and Apple said at WWDC 2025 it would stay unavailable there with iOS 26/macOS 26. — [Jean Galea](https://jeangalea.com/control-automate-iphone-webdriveragent/)
- **[unconfirmed]** iPhone Mirroring (macOS 15+) lets a Mac operate the iPhone with the Mac's trackpad and keyboard, and the iPhone must be locked. Universal Control covers Mac and iPad only, not iPhone. No API is exposed to iOS apps.

### Inferences
- If the user owns a Mac, iPhone Mirroring plus Mac-side automation (for example, macOS computer-use) is a "no new hardware" route. It is not on-device and is not available in the EU.

### Gaps
- I did not fetch Apple's iPhone Mirroring or Universal Control support pages in this session.

## 6. Private APIs (IOHIDEvent / BackBoardServices / GSEvent) in sideloaded apps

### Takeaway
Synthesizing system-wide touches from an ordinary or sideloaded app has been blocked by entitlement checks since about iOS 6–7. Nothing found suggests this changed on iOS 26/27 without a jailbreak. Current HID-injection projects run in VMs or privileged daemons, not sandboxed apps.

### Cited Findings
- **[reported]** From iOS 6.1, IOHIDEventSystemCreate checks the caller (compared against "com.apple.springboard"), and a non-privileged call "silently fails". — [Stack Overflow archive (iOS 7/8 era)](https://kaweah.freedombox.rocks/kiwix/stackoverflow.com_en_all_2023-11/questions/26916379/ios7-8-send-touch-events-on-non-jailbroken-iphone-pad)
- **[reported]** GSEvent can no longer simulate touches on iOS 7+. — [Stack Overflow archive](https://kaweah.freedombox.rocks/kiwix/content/stackoverflow.com_en_all_2023-11/questions/13415669/simulating-system-wide-touch-events-in-ios-without-jailbreaking-the-device)
- **[reported]** vphone-cli (2025–26) injects touch and keyboard into *iOS virtual machines* on Apple Silicon Macs through a guest daemon that binds private IOKit HID APIs. It is not a sandboxed app on a real phone. — [instagit write-up](https://instagit.com/Lakr233/vphone-cli/vphone-cli-hid-injection-guest-daemon/)
- **[confirmed]** The sanctioned event-synthesis path is XCTest (W3C Actions via WDA) running in a test-runner context. — [Appium: About iOS Input Events](https://appium.github.io/appium-xcuitest-driver/6.0/guides/input-events)
- **[unconfirmed]** Event dispatch from non-system processes needs private entitlements such as `com.apple.private.hid.client.event-dispatch`. Developer signing (free or paid) cannot grant private `com.apple.private.*` entitlements because AMFI rejects them. TrollStore-style arbitrary entitlements depended on CoreTrust bugs that were patched by about iOS 17.0.1, so they do not apply to iOS 26/27.

### Inferences
- A non-jailbroken route through private HID APIs on iOS 26/27 is effectively dead. The XCTest test runner, which gets privileged synthesis through testmanagerd, is the only exception.

### Gaps
- No primary 2025–2026 source explicitly re-tested IOHIDEvent injection from a sideloaded app on iOS 26/27. The "no" is inferred from long-standing entitlement enforcement.
