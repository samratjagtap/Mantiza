# Way 3 Deep Dive: Bluetooth "Fake Mouse" Gadget

_Written: 2026-10-28 · Part of: [App control feasibility review](app-control-feasibility.md) (section 5, Way 3)_

## The idea in one paragraph

The iPhone's AssistiveTouch feature accepts a Bluetooth or wired mouse, and its pointer can click anything on screen. A small board (for example an ESP32) pretends to be a mouse and keyboard. Mantiza sees the screen with screen capture, an AI decides where to tap, and the board moves the pointer and clicks. This is the only way we found that can tap inside other apps **without a Mac**.

## How to read this document

| Marker | Meaning |
|---|---|
| ✅ | Confirmed from Apple's documentation, an Apple staff reply on the Apple Developer Forums, or the README of a project that has built it |
| 📰 | Reported by a single developer, project or vendor; not independently confirmed |
| ❓ | Unconfirmed; must be tested on a device |
| _(estimate)_ | Our own guess, not measured |

Sources are numbered like [F1] and listed in section 5.

---

## 1. Who has already built this

| Project | How it sees the screen | How it taps | Where the AI runs |
|---|---|---|---|
| esp32-iphone-agent [F1] | AirPlay mirroring to the host (default), or a ReplayKit broadcast extension sending frames over a VPN | ESP32-S3 as a **USB** mouse and keyboard in the iPhone's port (default); **Bluetooth is experimental** | Mac or Linux server |
| Iphone-control-for-social-media [F2] | USB screen capture on a Mac, plus Apple Vision text recognition (OCR) | ESP32 as a Bluetooth mouse | Mac |
| VK DeviceHub [F3] | WebDriverAgent | ESP32 as a Bluetooth mouse | Server |
| EasyClick (commercial) [F4] | Its own screenshot method | ESP32-C3 as a Bluetooth mouse and keyboard | Its own tool |

**Key takeaway:** the hardware side is proven. But in every project we found, the "brain" runs on a **computer or server**. A setup that runs **only on the phone** (the Mantiza app sees the screen, the cloud decides, the board taps) has **not** been shown working by anyone we found.

---

## 2. Limitations and issues

### A. Tapping (the mouse)

1. ✅ **AssistiveTouch must be turned on.** It is set in Settings → Accessibility → Touch → AssistiveTouch. Pointer devices, including Bluetooth ones, can then "click icons on your screen that you might otherwise tap" [F5]. A pointer is visible on screen.
2. ✅ **The mouse sends movements, not positions.** It can say "move 10 right", not "go to point (300, 820)". iOS also changes pointer speed depending on how fast it moves, so **the board never knows exactly where the pointer is**. Workarounds used by existing projects:
   - Push the pointer into a corner as a reset, then move at a constant pace so iOS acceleration stays predictable [F1].
   - Set the iPhone's tracking sensitivity to maximum and keep track of a guessed pointer position [F3].
   - **Find the pointer in the screen image and correct it before every tap** [F1][F2].

   So **every tap needs a check against the screen**, which adds time and retries.
3. ❓ **Precise "go to this point" (absolute) positioning over Bluetooth is unproven.**
   - A developer on Apple's forum reported only relative movement working over Bluetooth [F6].
   - esp32-iphone-agent offers an experimental absolute pointer that needs iOS 18+ and Portrait Orientation Lock, and says whether iOS maps it to the whole screen "is still being measured" [F1].
   - EasyClick claims absolute coordinates are precise on iOS 17+ 📰 (vendor claim) [F4].
4. ✅ **Calibration is fragile** [F1][F2]:
   - It must be redone after changing AssistiveTouch tracking speed.
   - It works best on a light, still screen such as Settings.
   - The pointer can be lost over playing video.
5. 📰 **Landscape apps are not supported.** Taps land in the wrong place [F1].
6. 📰 **Going Home by swiping up with the pointer may fail on iOS 27.** The project uses a keyboard shortcut or the AssistiveTouch menu instead [F1].
7. **One pointer means one finger.** Pinch, rotate and other multi-finger gestures are not directly possible _(follows from how a mouse works; AssistiveTouch menu workarounds not tested by us)_.

### B. Typing (the keyboard)

8. 📰 **Capital letters and symbols can fail over Bluetooth.** On a combined Bluetooth mouse and keyboard, iOS ignored the Shift key ("A" became "a", "!" became "1"). The only tested fix was over USB (declaring the keyboard before the mouse). The issue is still open [F7].
9. 📰 **Non-English typing is hard.** The board sends key codes, not letters, so the phone's keyboard language must match what is sent. One project supports only English and Korean, with a key combination to switch languages [F1]. Hindi, other scripts or emoji would need extra work.

### C. Seeing the screen

10. ✅ **The user must start screen capture by tapping a system prompt.** Mantiza cannot start watching the screen by itself [F8]:
    - Old method (ReplayKit broadcast): the dialog "will be presented each time screen sharing is requested".
    - New method on iOS 27 (ScreenCaptureKit): the user picks "your app, another app, or the whole screen" in a system picker, which times out after 60 seconds.
11. ✅ **ReplayKit screen sharing is deprecated as of the iOS 27 SDK** in favour of ScreenCaptureKit [F8]. We would build on ScreenCaptureKit and keep ReplayKit only for iOS 26 and earlier.
12. ✅ **With ScreenCaptureKit, capture stops when Mantiza goes to the background** unless the app declares the `screen-capture` background mode (error `missingBackgroundMode`) [F8][F9]. Mantiza is always in the background while it operates another app, so this mode is required. App Store Connect at first rejected this value. An Apple engineer said it should now be resolved, and the developer confirmed a successful upload on 2026-08-21 [F9].
13. ✅ **The old ReplayKit extension has a memory limit of about 50 MB** and is killed if it goes over [F10][F11]. That is tight for full-resolution frames.
14. 📰 **Some screens cannot be seen:** passcode entry, Apple Pay and DRM video. This is reported for AirPlay mirroring [F1]. It is likely similar for screen capture ❓ (not tested).
15. ❓ **Apps can detect that the screen is being captured** and may hide content. Which apps actually do this must be tested.
16. **The phone must stay unlocked and on screen while Mantiza works:**
    - ✅ For AirPlay mirroring, "mirroring stops when the phone locks", so auto-lock must be off during tasks [F1].
    - ❓ Whether ScreenCaptureKit capture survives locking was not confirmed.
    - Either way, the user cannot use the phone while a task runs.

### D. Connection and hardware

17. ✅ **An iPhone app cannot act as a mouse itself.** iOS does not let apps publish the Bluetooth HID (keyboard and mouse) service; developers get error `CBErrorDomain Code=8` [F12][F13]. **A separate physical board is mandatory.**
18. ✅ **Not every ESP32 works.** The board needs native Bluetooth support; the ESP32-S2 has no Bluetooth [F2][F3]. ESP32-C6, ESP32-C3 and ESP32-WROOM-32 are reported to work well [F3].
19. 📰 **The Bluetooth link can drop** after the phone has been locked for hours; the server then has to reboot the board [F2]. Bluetooth input devices reconnecting badly on iOS is also reported [F14].
20. 📰 **One board per phone.** More than about 10 boards in one space may cause Bluetooth interference [F4].
21. ✅ **The board needs power.** The USB version is plugged into the iPhone's only port, which blocks charging; the Bluetooth version needs its own power [F1].
22. 📰 **The ESP32-C3 connects to Wi-Fi on 2.4 GHz only** (no 5 GHz) [F4].

### E. Security and safety

23. 📰 **Weak links by default:** pairing uses "Just Works" (no PIN), and the link between the board and the server is unencrypted unless a VPN tunnel is added [F1]. A board that can tap anything is a serious risk if someone else takes control of it.
24. 📰 **Prompt injection:** the AI acts on whatever text is on screen, so a malicious message or web page could trick it [F1].
25. ✅ **Face ID cannot be used** by a pointer (it needs the camera). A passcode could be typed by the keyboard, but the passcode screen may not be visible (item 14), and automating it would be a security problem.

### F. Product and business

26. **Not "download and done".** Users must buy, power and pair a board, turn on AssistiveTouch, tune pointer settings, and approve screen capture each session.
27. ❓ **App Store review is uncertain.** We found no Apple rule that clearly allows or bans an app that drives other apps through an external mouse board. It is a real risk, because Apple's sandbox exists to prevent cross-app control. We should ask Apple, or treat it as unknown.
28. 📰 **Apps may detect automation.** One project reports its automated TikTok and Instagram posts got views near zero (likely shadow-banned) [F2].
29. **Speed.** Every action is: capture the screen → AI decides → move the pointer → find it → correct → click → check the screen changed. Likely a few seconds per step _(estimate)_, slower than WebDriverAgent.

---

## 3. Bottom line

Way 3 is **technically possible and proven** by hobby and commercial projects, but:
- it **always needs a physical board**, so it is not "download and done";
- tapping is **approximate** and needs constant screen-based correction;
- the user must **approve screen capture** and **keep the phone unlocked**;
- a **phone-only version** (no computer) has not been shown working by anyone we found, and App Store approval is unknown.

It is a reasonable **research prototype**, and a poor foundation for a mass consumer product.

---

## 4. If we prototype it anyway

Things to test first on a real iPhone (our suggestion):
1. Does an absolute pointer over Bluetooth work on iOS 27 across the whole screen (item 3)?
2. Does ScreenCaptureKit with the `screen-capture` background mode keep running while another app is in front, and for how long (items 12 and 16)?
3. Which screens and apps go black or hide content when captured (items 14 and 15)?
4. Does Shift and non-English typing work over Bluetooth (items 8 and 9)?
5. How many seconds per step does the full loop take (item 29)?

---

## 5. Sources

| # | Source | Used for |
|---|---|---|
| F1 | [jinwon-int/esp32-iphone-agent (GitHub)](https://github.com/jinwon-int/esp32-iphone-agent) | Architecture, calibration, absolute pointer, limits, security notes |
| F2 | [dovydaskel/Iphone-control-for-social-media (GitHub)](https://github.com/dovydaskel/Iphone-control-for-social-media) | Mac + ESP32 setup, pointer tracking, BLE drops, shadow-ban report |
| F3 | [VKCOM/devicehub: ESP32 docs (GitHub)](https://github.com/VKCOM/devicehub/blob/master/doc/ios-docs/esp32.md) | Max sensitivity, guessed position, supported boards |
| F4 | [EasyClick: iOS Bluetooth HID automation](https://blog.ieasyclick.com/en/blog/ios-ble-hid-no-signature/) | Vendor claims on absolute coordinates, interference, 2.4 GHz |
| F5 | [Apple Support: Use a pointer device with AssistiveTouch](https://support.apple.com/en-us/111775) | Pointer devices supported on iPhone |
| F6 | [Apple Developer Forums: absolute mouse positioning over Bluetooth](https://developer.apple.com/forums/thread/652700) | Only relative movement reported |
| F7 | [Adafruit nRF52 issue #870 (GitHub)](https://github.com/adafruit/Adafruit_nRF52_Arduino/issues/870) | Shift modifier ignored on composite BLE device |
| F8 | [LiveKit Swift SDK: iOS screen sharing docs (GitHub)](https://github.com/livekit/client-sdk-swift/blob/main/Docs/ios-screen-sharing.md) | ReplayKit vs ScreenCaptureKit, pickers, deprecation, background mode |
| F9 | [Apple Developer Forums: iOS 27 ScreenCaptureKit `screen-capture` background mode](https://developer.apple.com/forums/thread/840821) | Background mode requirement and App Store Connect fix |
| F10 | [Apple Developer Forums: ReplayKit extension memory limit](https://developer.apple.com/forums/thread/108854) | Small, fixed memory limit |
| F11 | [Tencent Cloud: Publishing from screen](https://www.tencentcloud.com/document/product/1071/41878) | 50 MB extension memory limit |
| F12 | [Apple Developer Forums: iOS as a HID device via Bluetooth](https://developer.apple.com/forums/thread/725238) | Apps cannot act as HID devices |
| F13 | [Apple Developer Forums: HID over BLE](https://developer.apple.com/forums/thread/5865) | `CBErrorDomain Code=8` when publishing HID service |
| F14 | [Apple Community: BLE HID device reconnection issue](https://discussions.apple.com/thread/253423563) | Reconnection problems |
