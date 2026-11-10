# Can Mantiza read other apps' buttons like Appium? (research, 2026-11-10)

**Short answer: yes, as an optional "Turbo mode" for phones in Developer Mode, using an on-device
XCUITest runner. It can never be an App Store feature, and asking for consent doesn't change that:
Apple only runs this kind of agent under developer conditions.**

## Why an app can't just do it
- iOS keeps every app in a sandbox. There is no public API that lets one app read another app's
  buttons, labels or switches, with or without the user's consent.
- Appium does it on iPhone with **WebDriverAgent (WDA)**. WDA is an **XCUITest runner**: Apple's
  UI-test engine. Apple only lets that engine run when:
  - **Developer Mode** is on (Settings → Privacy & Security). Mantiza already needs it, because xtool
    installs development builds.
  - The runner is **development-signed**, including its nested `.xctest` bundle.
  - The **Developer Disk Image (DDI)** is mounted. It provides the `testmanagerd` service.
    **A reboot unmounts it.**
  - The **passcode** is entered when an automation session starts (again after a reboot).
- The usual setups (Appium, mozarkai/optics-framework, mobile-mcp, Midscene) keep a **Mac or PC
  connected** to start and drive WDA ([Driving a real iPhone from Claude Code, 2026-09-17](https://fuadkamal.org/2026/09/17/driving-a-real-iphone-from-claude-code/);
  [Derrors/iphone-control-toolkit](https://github.com/Derrors/iphone-control-toolkit), Linux with
  no Mac, but the computer stays attached).

## The project that does it on the phone itself: iCTRL
[OpenMinis/iCTRL](https://github.com/OpenMinis/iCTRL): Apache 2.0, 593 stars, v1.98.16
(2026-10-26), iOS 16+. It ships two IPAs: the runner (about 1 MB, required) and an optional companion
app.

**How it runs:**
- A "UITest that never stops" (WDA's trick). You start it by **tapping its icon on the Home Screen**.
- It then runs in the background and serves **JSON-RPC over HTTP on `127.0.0.1:8200`**, so **apps on
  the same phone can call it**. This is exactly what Mantiza needs.
- The display can sleep without stopping it.

**What it offers:**

| Group | Methods |
|---|---|
| Read the screen | `page_source` (element tree: type, label, value, frame), `find_element`, `screen_text` (Vision OCR fallback), `screenshot` |
| Act | `tap`, `tap_element`, `find_and_tap`, `swipe`, `scroll`, `scroll_to_element`, `drag` (paths), `type` |
| Apps and device | `launch_app`, `open_url`, `home`, `lock`/`unlock` |

**Speed (their measurements):**
- taps about **280 ms**
- the visible element tree **p50 416 ms, p90 593 ms, never over 1 s** (8 apps)
- element lookups about 0.3–1 s

**Security:**
- Each client must be approved once from a notification on the phone.
- Every request is then encrypted (X25519 pairing, HMAC-SHA256 per request).
- It's local-only by default.

**Mounting the DDI with no Mac:**
- The companion app (or StikDebug) mounts it **on the device** through LocalDevVPN (App Store) and a
  RemotePairing file. The pairing file is made once on a computer with
  [idevice_pair](https://github.com/jkcoxson/idevice_pair) or iLoader, or on iOS 27 by StikDebug
  itself, according to [this guide](https://techsimplest.com/stikdebug-pair-without-computer/).
- Mounting needs Wi-Fi, and internet the first time.
- The protocol work is done by [jkcoxson/idevice](https://github.com/jkcoxson/idevice) (MIT).

**Limits:**
- It uses private XCTest and LSApplicationWorkspace APIs, so it's **not App Store safe**.
- Free Apple ID: certificates last 7 days, and at most **3** sideloaded apps can be active (for us:
  Mantiza + runner + mounter).
- The DDI must be remounted, and the runner relaunched, after every reboot.
- The passcode may be asked when the session starts.
- `unlock` can't type the passcode.
- Apps with bot detection may still notice it.
- **Signing:** the runner's nested `.xctest` must be signed from the inside out. Signers that skip it
  produce a runner that **crashes on launch**. Whether `xtool install` handles this is untested.

## What Turbo mode would change in Mantiza

| Today (StickS3 + screen capture + OCR + AI) | Turbo (runner on the phone) |
|---|---|
| Finds things by reading text in a screenshot. Icons and switches without text need the big brain (about 1.2 s) | Gets every element with its type, label and frame, **including icons and switches** ("switch 'Wi-Fi' value 1") in about 0.4 s |
| "Is Wi-Fi on?" can't be read | Switch values are in the tree, so done-checks are exact |
| Fast brain sees an image | Fast brain can decide from text rows alone (smaller, faster), with the image only when needed |
| Taps by the StickS3 (about 0.1 s) | Taps by the StickS3 or by the runner (about 0.28 s). The StickS3 still does the special keys |

**It doesn't replace the standard mode.** Phones without Developer Mode, or a phone that rebooted
before the DDI was remounted, keep using the StickS3 + screen-capture path. Mantiza should check
`127.0.0.1:8200` at the start of each task and use whichever is available.

## Steps if we go ahead
1. **Feasibility on the developer's iPhone 14 Plus (iOS 27):**
   - Download `iCTRLUITests-Runner.ipa` and install it with `xtool install`. Watch for the
     nested-`.xctest` signing crash.
   - Mount the DDI from the PC (USB) or with the iCTRL companion app.
   - Launch the runner. Time `page_source` in Settings, WhatsApp and Control Centre.
2. **Mantiza client:** pairing and the encrypted envelope in Swift (CryptoKit has Curve25519 and
   HMAC), then `page_source` → text rows like optics' `e7 switch "Wi-Fi" [tap] value=1`, plus
   `find_and_tap`.
3. **Agent:** use the tree when the runner is up; otherwise use the current path.
4. **Setup screen in Mantiza:** walk the user through Developer Mode, the runner, the mounter, and the
   one-time pairing approval. It's opt-in and explained plainly.
