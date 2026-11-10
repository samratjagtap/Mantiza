# Mantiza Phase 0 test app

A small iPhone app for the Phase 0 tests in the [plan](../../Docs/Mantiza%20Roadmap/mantiza-v2-plan.md). It is **not** the Mantiza app.

| Test | Status |
|---|---|
| **T2** command channel to the device while it is the iPhone's mouse | In this app ([how to test](../../firmware/t1-hid-test/README.md#t2-commands-from-the-iphone-app)) |
| **T3** screen capture keeps running while other apps are in front | In this app, tab **T3/T4 Screen** (below) |
| **T4** does the picker ask every time, or can a session be reused? | Same tab |
| **T9** battery: device standby, phone drain with screen capture | Tab **T9 Battery** (below) |

## T3 / T4: screen capture (iOS 27 ScreenCaptureKit)
How it works on iPhone (from the iOS 27.1 SDK headers): the app shows Apple's **picker** (`SCContentSharingPicker`), you choose to share the screen, the app gets a filter and starts an `SCStream`. iOS has no screenshot API and no frame-rate setting: frames simply arrive when the screen changes. The `screen-capture` background mode is in [Info.plist](Info.plist).

| # | Do | Look for |
|---|---|---|
| T3a | Tab **T3/T4 Screen → Start (picker)** → share the screen | State **Capturing ✅**, Frames rising |
| T3b | Use **other apps for 5+ minutes** (scroll, open things) | Back in the app: **…while app in background** frames are high; thumbnails with an **orange** border show **other apps** |
| T3c | **Lock the phone** for 1 minute, unlock | Is it still capturing? Check the **Log** tab for "Capture STOPPED by iOS: …" and the code |
| T4a | **Stop**, then **Restart without picker** | Does capture start again **without asking**? |
| T4b | **Stop**, then **Start (picker)** again | Does iOS show the picker again, or remember? |
| T4c | Close the app from the App Switcher, reopen, **Start (picker)** | Does it ask after a relaunch? |
| – | Watch the top of the screen while capturing | Is there a recording indicator (red pill / dot)? |

### T3 / T4 results
Date: 2026-11-05 · iPhone 14 Plus · iOS 27

| # | Test | Result | Notes |
|---|---|---|---|
| T3a | Capture starts from the picker | ✅ | |
| T3b | Keeps capturing with other apps in front (5 min) | ✅ | Frames showed the other apps. The T2 Bluetooth heartbeat kept running alongside |
| T3c | Phone locked | ❌ stops | iOS ends the capture when the phone locks |
| T4a | Restart without picker | ❌ | "Start failed": a stopped capture can't reuse the earlier choice |
| T4b | Picker again: asks every time? | Asks every time | |
| T4c | After app relaunch | not recorded | Expected to ask, since T4b already asks |
| – | Recording indicator | Shown | Red indicator while capturing |

| T4d | **Device presses the share button** (no touch on the phone) | ✅ | 2026-11-06. From the app ("Try now") ✅, and from the Home Screen with StickS3 "4 Share screen" ✅: the device opens the app through Search, the app shows the picker, the device clicks "Share Entire Screen". StickS3 showed "shared ok 4.1s" (picker → capturing, includes a 2 s wait before the click) |

**What this means for Mantiza:** start capture once and keep it running between tasks. When it isn't running (after a lock, or the first task), **the device starts it by itself**: open the app, show the picker, click "Share Entire Screen". The user never has to touch the phone for screen sharing, as long as it is unlocked.

### T4d: how the device finds the button
The device can't see the screen, so the app calibrates the pointer: the device clicks 3 known spots on a full-screen view and the app measures where they land. Result on iPhone 14 Plus at the highest tracking speed: **1 count = 4.37 pt on both axes, check click 0 pt off**. This only works because the device moves **across first, then down, in equal 5-count steps** (`goTo` in the firmware): diagonal or mixed-size steps get different acceleration from iOS and the distance becomes unpredictable (first try: 2.99 × 4.78 pt, check click 85 pt off). The share button is at about (214, 538) pt on the 14 Plus (from a screenshot; screenshot pixels ÷ 1.73 here).

## T9: battery
The StickS3 menu item **"9 Battery test"** turns its screen off (like the real device most of the time) and sends `batt <percent> <millivolts> <minutes> <charging>` to the app every minute. The app's **T9 Battery** tab saves each report together with the phone's battery level and whether screen capture is running, and shows the drain per hour.

| # | Run | How | Look for |
|---|---|---|---|
| T9a | **Device standby**: connected, idle, screen off | StickS3 unplugged from USB, "9 Battery test" on. Phone off the charger, app in the background, **no** screen capture. Several hours (overnight is best) | Device %/h and hours left |
| T9b | **Phone with screen capture running** | Same, but screen capture on (T3/T4 tab → Start) while you use the phone normally for 1–2 hours | Phone %/h with capture on |
| T9c | **Phone without capture** (baseline) | Same normal use for 1–2 hours, capture off | Compare with T9b |

Notes: the tab warns if anything was charging during a run (that run doesn't count). Start each run with **Clear and start a new run**. A press on a StickS3 button only wakes its screen for 10 s; the next press works as usual.

### T9 results
| # | Run | Hours | Start → end | Drain | Notes |
|---|---|---|---|---|---|
| T9a | Device standby | | | | |
| T9b | Phone, capture on | | | | |
| T9c | Phone, capture off | | | | |

## Build and install (Windows)
Needs the [Windows xtool setup](../../Docs/Setup/windows-xtool-setup.md) and the iPhone bridge running. Then, in Ubuntu:
```
cd /mnt/c/Users/PC/Desktop/mantiza/Mantiza/apps/phase0-test
xtool dev
```

## Files
- `Sources/MantizaTest/DeviceLink.swift`: Bluetooth. It finds the device among the devices iOS is **already connected to** (the device is busy being the mouse, so it doesn't advertise), then uses the command channel.
- `Sources/MantizaTest/ContentView.swift`: the T2 screen.
- `Sources/MantizaTest/ScreenCapture.swift` + `CaptureView.swift`: T3/T4 screen capture, and the Log tab.
- `Info.plist`: permission texts and the `bluetooth-central` + `screen-capture` background modes.
- The channel IDs must match [firmware/t1-hid-test/src/main.cpp](../../firmware/t1-hid-test/src/main.cpp).
