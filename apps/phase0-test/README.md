# Mantiza Phase 0 test app

A small iPhone app for the Phase 0 tests in the [plan](../../Docs/Mantiza%20Roadmap/mantiza-v2-plan.md). It is **not** the Mantiza app.

| Test | Status |
|---|---|
| **T2** command channel to the device while it is the iPhone's mouse | In this app ([how to test](../../firmware/t1-hid-test/README.md#t2-commands-from-the-iphone-app)) |
| T3 / T4 screen capture | Next |

## Build and install (Windows)
Needs the [Windows xtool setup](../../Docs/Setup/windows-xtool-setup.md) and the iPhone bridge running. Then, in Ubuntu:
```
cd /mnt/c/Users/PC/Desktop/mantiza/Mantiza/apps/phase0-test
xtool dev
```

## Files
- `Sources/MantizaTest/DeviceLink.swift`: Bluetooth. It finds the device among the devices iOS is **already connected to** (the device is busy being the mouse, so it doesn't advertise), then uses the command channel.
- `Sources/MantizaTest/ContentView.swift`: the test screen.
- `Info.plist`: Bluetooth permission text and the `bluetooth-central` background mode.
- The channel IDs must match [firmware/t1-hid-test/src/main.cpp](../../firmware/t1-hid-test/src/main.cpp).
