# Mantiza device firmware (M5StickS3)

This is the firmware for the real Mantiza app ([apps/mantiza](../../apps/mantiza/README.md)). It started as a copy of the [Phase 0 test firmware](../t1-hid-test/README.md), which stays as the record of tests T1, T1b, T2, T4d and T9. The test menu and test counters are removed here; type `help` on the serial port for the commands.

## What changed: an absolute pointer
- **The mouse now sends exact screen positions.** x and y go from 0 to 32767 across the whole screen, so `tap x y` jumps the pointer there in **one report** and clicks.
  - The old firmware first pushed the pointer into the corner and then moved in small steps. That took about 1.2 s per tap and needed calibration.
  - Now a tap takes about 0.1 s, with no calibration.
- **Where the idea comes from:** the same layout (16-bit X/Y, 0..32767) was tested over Bluetooth on an iPhone by [jinwon-int/esp32-iphone-agent #104](https://github.com/jinwon-int/esp32-iphone-agent/issues/104) (2026-10-27).
- **Fallback:** setting `-DABSOLUTE_POINTER=0` in `platformio.ini` builds the old relative mouse.
- **The device is now called "Mantiza"**, and `hello` answers `hi Mantiza battery N% abs 1`, so the app knows which pointer it has.
- **No test menu.** The screen shows only what matters: iPhone connected, app ready, battery, and **what Mantiza is doing right now** (the app sends `status <text>` at every step). The screen turns off after a minute without news.
- **Mantiza's look on the screen** (same colours and pixel art as the app, from `images/`):
  - the pixel mantis head and the MANTIZA wordmark
  - an IPHONE light (LINKED / WAITING) and an APP light (READY / NOT OPEN)
  - battery, and what Mantiza is doing
  - the head blinks now and then, a scan line runs through it during a task, and it is dim until the iPhone connects
  - while a task runs, a magenta bar says FRONT BUTTON = STOP
- **Front button = Stop** while a task runs (the app sends `task on` / `task off`; the device sends `stop`).
- **Special keys** (`key <name> [times]`): the keys Apple lists for keyboards in its Accessory Design Guidelines (R32 Update 1, Tables 14-3 and 14-4): `home`, `lock`, `screenshot`, `brighter`, `dimmer`, `louder`, `softer`, `mute`, `playpause`, `next`, `previous`, `siri`, `spotlight`, `globe`, `keyboard`, and `focus` (Do Not Disturb). `key 0x00e9` sends any consumer usage. jinwon-int/esp32-iphone-agent sends some of the same keys over BLE.

## After flashing: pair again
Each time the report map changes (version 4: absolute pointer; version 6: special keys), the device clears its old pairings when it starts.
1. On the iPhone: **Settings → Bluetooth → Mantiza → Forget This Device**.
2. Pair **Mantiza** from the same list.
3. Keep **AssistiveTouch** on.

## Build and upload
```
cd firmware/mantiza-device
~/.platformio/penv/Scripts/pio.exe run -t upload --upload-port COM4
```
