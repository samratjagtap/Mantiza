# Android Phone as Software Bluetooth Mouse+Keyboard ("Hands") for Mantiza on iPhone

Research date: 2026-10-28. Labels: **[confirmed]** = official docs; **[reported]** = single non-official source (README, listing, forum); **[unconfirmed]** = inference or background knowledge I could not verify with a fetched source this session.

Method note: the developer.android.com BluetoothHidDevice reference page could not be parsed by the fetch tool (the page body is mostly navigation, over 335k characters), and the AOSP raw-source mirror returned 404. So the API-detail facts below rest on project READMEs, listings and well-known background, and are labelled to match.

## 1. BluetoothHidDevice API: capabilities, permissions, transport, OEM gaps, bugs

### Takeaway
Android 9+ exposes `BluetoothHidDevice`, which lets an app register an arbitrary HID report descriptor and act as a **Bluetooth Classic (BR/EDR) HID device**. That covers mouse, keyboard and composite devices. Support is not universal: some OEM builds don't expose the HID Device profile, so any phone you plan to use has to be checked first.

### Cited Findings
- The API exists in `android.bluetooth` with the companion classes `BluetoothHidDevice.Callback`, `BluetoothHidDeviceAppQosSettings` and `BluetoothHidDeviceAppSdpSettings` **[confirmed: the class index lists them]**. Google's own Wear OS sample "wearmouse" calls it "the Bluetooth HID Device API introduced in Android P" and implements an air mouse plus cursor keys **[reported]**. Sources: [Android reference](https://developer.android.com/reference/android/bluetooth/BluetoothHidDevice), [ginkage/wearmouse](https://github.com/ginkage/wearmouse)
- Open-source apps built on it run as a **Classic** HID keyboard, mouse and trackpad and require Android 9.0+. For example, Bluetooth Remote ("Bluetooth (Classic) HID keyboard, mouse, and trackpad", "registers with Android's BluetoothHidDevice profile and sends HID reports") **[reported]**. Source: [F-Droid btremote](https://f-droid.org/packages/io.github.jqssun.btremote/), [GitHub jqssun/android-bt-remote](https://github.com/jqssun/android-bt-remote)
- BLE/HOGP is a separate path. `rdady/BLE-HID-Peripheral-for-Android` builds a BLE HID peripheral (mouse, keyboard, joystick) itself on top of GATT advertising and serving, rather than using BluetoothHidDevice. Its README says it was tested against Android and macOS centrals and that "connection with iOS central is not tested yet" **[reported]**. Source: [rdady/BLE-HID-Peripheral-for-Android](https://www.github.com/rdady/BLE-HID-Peripheral-for-Android)
- OEM disablement: the Kontroller README says "many device manufacturers disable the Bluetooth HID Device profile". It links a Play Store "Bluetooth HID Device Profile Compatibility Checker" and asks for OnePlus 8/8T/Nord testers **[reported]**. The btctrl README also warns that the profile "is not implemented in every phone" **[reported]**. Sources: [Kontroller](https://github.com/mkyybx/Kontroller), [btctrl](https://zff.dev/vastivety/btctrl)
- A concrete case: on a Fairphone 6 the HID Device profile was not exposed, `dumpsys` showed no HID Device service and registration failed. The same app worked on a Samsung Galaxy S21 **[reported]**. Source: [Fairphone forum](https://forum.fairphone.com/t/bluetoothhiddevice-profile-not-exposed-on-fairphone-6/132462)
- Background: stock Bluedroid originally implemented only the HID **host** role, and the device role had to be added. This explains why vendor stacks vary **[reported, older engineering blog]**. Source: [HSC blog](https://www.hsc.com/resources/blog/android-labs-bluetooth-hid-device-implementation-your-phone-as-a-mouse-voice-control/)
- A general OEM HID-handling bug: a Samsung One UI 7 user reports a BT keyboard stops registering keys after standby until re-paired. That report concerns the host side, but it shows vendor-stack fragility **[reported]**. Source: [Samsung Community](https://r1.community.samsung.com/t5/tablets/bluetooth-keyboard-disconnects-after-standby-oneui-7-bug/m-p/34932916)

### Inferences
- **[unconfirmed]** API shape: obtain the proxy via `BluetoothAdapter.getProfileProxy(..., BluetoothProfile.HID_DEVICE)`, then call `registerApp(sdp, inQos, outQos, executor, callback)` with your own report descriptor, then `connect(device)` and `sendReport(device, reportId, bytes)`. SUBCLASS constants cover keyboard, mouse and combo. Only one HID Device app is typically registered at a time, system-wide. On Android 12+ these calls require the `BLUETOOTH_CONNECT` runtime permission, and discoverability/pairing needs `BLUETOOTH_SCAN`/`BLUETOOTH_ADVERTISE` or a discoverable intent. Check this against the reference page before building.
- Because the descriptor is free-form, a composite mouse+keyboard (+consumer control) descriptor is possible. The existing apps ship exactly that combination, so composite works in practice.
- For Mantiza, using a Classic HID device matches how iOS AssistiveTouch "Bluetooth Devices" pairing works with ordinary BT mice.

### Gaps
- Could not extract the exact `@RequiresPermission` annotations or the official javadoc text (page parse failure).
- No authoritative list of which OEMs or models disable the profile. Only anecdotes (Fairphone 6 no; Samsung S21 yes; OnePlus unknown).
- Found no Android 16/17-specific changes to BluetoothHidDevice.

## 2. Existing apps/libraries and iPhone/iPad (AssistiveTouch) compatibility

### Takeaway
Several apps already turn an Android phone into a BT mouse and keyboard that works with iOS/iPadOS 13+: Appground "Bluetooth Keyboard & Mouse", Bluetooth Remote (open source), Kontroller and btctrl. **Pointer control on iPhone requires AssistiveTouch.** I found no review that specifically confirms the iPhone AssistiveTouch pointer with these apps. The listings say "iOS supported" without detail.

### Cited Findings
- Appground "Bluetooth Keyboard & Mouse" (`io.appground.blek`, also listed as "Serverless Bluetooth Keyboard & Mouse for PC/Phone") lists as "successfully tested": Android/Android TV, **Apple iOS and iPadOS**, Windows 8.1+, ChromeOS, Steam Deck. A Pro version (`io.appground.blekpremium`) exists, support runs through Discord and GitHub discussions, and some features (air mouse, speech input) are premium **[reported, listing mirrors]**. Sources: [BlueStacks listing](https://www.bluestacks.com/campaign/io.appground.blek/en), [AppFollow](https://appfollow.io/android/serverless-bluetooth-keyboard-mouse-for-pc-phone/io.appground.blek?country=fi), [APKMirror 6.10.4](https://www.apkmirror.com/apk/appground-io/bluetooth-keyboard-mouse-2/bluetooth-keyboard-mouse-6-10-4-release)
- Bluetooth Remote (jqssun, GPL-3.0, v0.0.7 added 2026-06-21, Android 9+) claims **full support on iOS/iPadOS 13+** and keyboard-only on iOS 4+. Its permissions include foreground service, run at startup, prevent sleep and location **[reported]**. Source: [F-Droid](https://f-droid.org/packages/io.github.jqssun.btremote/)
- Kontroller (Kotlin, Android 9+, "in development") targets PC, Mac, TV and **iPad**. Setup: remove old pairings, open the app, start pairing from the host, accept on the phone **[reported]**. Source: [Kontroller](https://github.com/mkyybx/Kontroller)
- Other listed apps: Bluke (`dev.arnv.bluke`: keyboard, trackpad, gamepad), btctrl **[reported]**. Sources: [IzzyOnDroid Bluke](https://apt.izzysoft.de/fdroid/index/apk/dev.arnv.bluke?repo=main), [btctrl](https://zff.dev/vastivety/btctrl)
- iOS side: Settings > Accessibility > Touch > AssistiveTouch > Devices > Bluetooth Devices to pair. The pointer is a grey circle. Tracking speed is under Settings > General > Trackpad & Mouse, per-button actions are under AssistiveTouch > Devices, and Dwell and Drag Lock are available **[confirmed]**. Source: [Apple Support 111775](https://support.apple.com/en-us/111775)
- A user report says a BT mouse paired to iPhone did nothing until AssistiveTouch was enabled **[reported]**. Source: [MPU forum](https://talk.macpowerusers.com/t/looking-for-external-bluetooth-control-device-for-iphone/46807)
- Known iPad quirk: AssistiveTouch "Mouse Keys" enabled caused keyboard problems with a BT keyboard and mouse. The fix was turning Mouse Keys off **[reported, iPadOS 13 era]**. Source: [Apple Community](https://discussions-cn-prz.apple.com/thread/250874620)
- Relative pointer calibration is unpredictable on iOS. A developer sending relative HID reports could not map deltas to screen coordinates predictably. The Apple Developer Forums thread (Aug 2022) went unanswered **[reported]**. Source: [Apple Dev Forums 712996](https://developer.apple.com/forums/thread/712996)

### Inferences
- **[unconfirmed]** The same iOS limitations that apply to an ESP32 apply equally to an Android HID: relative-only pointer, pointer acceleration and tracking-speed scaling, and the need to "home" the cursor (e.g. slam it to a corner with large negative deltas) and then move with calibrated deltas. Android adds no advantage or disadvantage here. The HID reports reaching iOS are the same.
- Reconnection: the HID host (iPhone) typically reconnects to a bonded Classic HID device, or the Android app calls `connect()`. I found no iOS-specific reconnection reports for these apps.

### Gaps
- No user review or Reddit thread found confirming Appground or Bluetooth Remote with the **iPhone** AssistiveTouch pointer specifically, as opposed to "iOS supported" claims. Play reviews were not fetched.
- No reports found on Shift/modifier issues specific to Android HID → iOS.

## 3. Absolute positioning / digitizer

### Takeaway
No evidence that iOS accepts an absolute mouse over Bluetooth. A developer report says switching to absolute reports made the pointer stop moving on iPad. One report shows a digitizer/pen descriptor being interpreted as pen input on iPhone, which hints at a possible but unverified route.

### Cited Findings
- A Bluefruit BT mouse emulator worked with AssistiveTouch (iOS 13) only in relative mode. "After changing the HID report frame to absolute, the mouse no longer moved on the iPad" **[reported]**. Source: [Apple Dev Forums 652700](https://developer.apple.com/forums/thread/652700)
- Nordic engineer: "virtually all platforms support relative mode, but not all platforms support absolute mode" **[reported]**. Source: [Nordic DevZone](https://devzone.nordicsemi.com/f/nordic-q-a/56997/hid-finger-swipe-functionality-iphone/233959)
- A remote whose descriptor used the **Digitizer usage page (pen/stylus)** produced a "Pen" warning and drew a straight line in iPhone Notes. So iOS parses some digitizer input from a BT HID **[reported]**. Source: [Nordic DevZone thread](https://devzone.nordicsemi.com/f/nordic-q-a/56997/hid-finger-swipe-functionality-iphone/235594)
- iOS HID quirk: an nRF52840 mouse connected to iOS but did not move. Nordic attributed this to iOS requiring pairing/bonding **[reported]**. Source: [Nordic DevZone 115855](https://devzone.nordicsemi.com/f/nordic-q-a/115855/inquiry-on-hid-mouse-functionality-with-ios-on-nordic-nrf52840-dongle/508693)

### Inferences
- **[unconfirmed]** Because BluetoothHidDevice accepts arbitrary descriptors, an Android phone can **present** a digitizer/absolute descriptor just as an ESP32 can. Whether iOS honors it is an iOS question, and it's the same experiment on either platform. Android's advantage is iteration speed (rebuild an APK rather than reflash), not capability.

### Gaps
- No report found of an Android-hosted absolute or digitizer descriptor tested against iOS 26/27.

## 4. Background operation, screen off, battery

### Takeaway
A `connectedDevice` foreground service (with BLUETOOTH_CONNECT granted) is the sanctioned way to keep an HID session alive in the background. Existing apps request foreground-service, wake-lock and run-at-startup permissions, which suggests they keep running with the screen off. I found no battery measurements.

### Cited Findings
- Foreground service type `connectedDevice` requires manifest permission `FOREGROUND_SERVICE_CONNECTED_DEVICE` plus a runtime prerequisite such as granted `BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE` or `BLUETOOTH_SCAN` (or a network/USB permission). Android 14+ requires declaring the type. The docs suggest CompanionDeviceManager presence for continuous connections **[confirmed]**. Source: [Android FGS types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- Bluetooth Remote declares foreground services, notifications, run at startup and prevent the phone from sleeping (wake lock) **[reported]**. Source: [F-Droid](https://f-droid.org/packages/io.github.jqssun.btremote/)

### Inferences
- **[unconfirmed]** A dedicated spare phone, kept plugged in, with battery optimization disabled for the app and a `connectedDevice` FGS plus partial wake lock, should hold the HID link and a command channel with the screen off. OEM battery killers (Xiaomi, Huawei, some Samsung) may still kill it unless the app is allow-listed.
- **[unconfirmed]** Battery: an idle BT Classic link plus Wi-Fi or BLE is low drain, but a wake lock prevents deep doze. A plugged-in "dock phone" makes this moot.

### Gaps
- No measured battery or screen-off reliability data for any HID-device app.

## 5. Command channel iPhone → Android, simultaneous HID + BLE GATT, latency

### Takeaway
The feasible options are (a) local Wi-Fi (WebSocket/UDP/TCP with mDNS discovery), (b) BLE GATT with Android as peripheral, or (c) a cloud relay. Multipeer Connectivity is Apple-only. I found no source that confirms or denies running BluetoothHidDevice and a BluetoothGattServer concurrently in one app. It is plausible, since they are separate transports (BR/EDR vs LE) on a dual-mode controller, but it needs on-device testing.

### Cited Findings
- `BluetoothGattServer` provides the GATT server role, obtained via `BluetoothManager.openGattServer` **[confirmed]**. Source: [Android BluetoothGattServer](https://developer.android.com/reference/android/bluetooth/BluetoothGattServer)
- No search result addressed HID Device + GATT server coexistence. Community commentary notes controllers can limit concurrent roles **[reported/unspecific]**. Source: [Nordic DevZone 79481](https://devzone.nordicsemi.com/f/nordic-q-a/79481/can-not-connect-multiple-three-four-two-nrf52810-with-android-10/329099)

### Inferences
- **[unconfirmed]** Android phones are dual-mode, and acting as an LE peripheral (advertising plus GATT server) while holding a Classic HID link is common in practice (e.g. a watch on LE alongside BT audio on Classic). Expect it to work on most modern phones, with possible 2.4 GHz scheduling contention. The iPhone app as a CoreBluetooth central can connect to the Android GATT server in the foreground. iOS background central operation is restricted but possible with the `bluetooth-central` background mode.
- **[unconfirmed]** Latency estimates: local Wi-Fi WebSocket ~5–30 ms one-way on the same LAN; BLE GATT write-without-response ~7.5–50 ms depending on connection interval (iOS typically negotiates 15–30 ms); cloud relay ~50–300 ms round trip. All of these are small next to the iOS screenshot → LLM decision loop, so the channel choice is about reliability and setup friction, not speed.
- **[unconfirmed]** Wi-Fi requires both devices on the same network and iOS's Local Network permission prompt. BLE needs no network but adds a second Bluetooth relationship.

### Gaps
- No empirical source on simultaneous HID Device + GATT server on Android. No measured latency figures for this pipeline.

## 6. Google Play policy and sideloading

### Takeaway
HID-device apps are distributed on Google Play today (Appground's app with free and Pro versions, and the Compatibility Checker), so the category is evidently allowed. Open-source alternatives are on F-Droid and IzzyOnDroid, and sideloading an APK is viable for a spare phone.

### Cited Findings
- Appground Bluetooth Keyboard & Mouse and its Pro version are on Google Play **[reported, mirrors]**. Source: [AppGoblin](https://appgoblin.info/apps/io.appground.blek), [AppGoblin Pro](https://appgoblin.info/apps/io.appground.blekpremium)
- Bluetooth Remote is distributed on F-Droid and IzzyOnDroid as a developer-signed reproducible APK **[reported]**. Source: [F-Droid](https://f-droid.org/packages/io.github.jqssun.btremote/), [IzzyOnDroid](https://apt.izzysoft.de/fdroid/index/apk/io.github.jqssun.btremote?repo=main)
- The Kontroller README links a Play-hosted HID Device Profile Compatibility Checker **[reported]**. Source: [Kontroller](https://github.com/mkyybx/Kontroller)

### Inferences
- **[unconfirmed]** Play-policy risk areas: the FGS type declaration (connectedDevice fits), and if the app also uses AccessibilityService or broad device control, Play's accessibility-API policy would apply. A pure HID app doesn't need it. Google's 2026+ developer-verification requirement for sideloaded apps on certified Android devices may affect anonymous sideloading. I did not verify its current status.

### Gaps
- Did not fetch the Google Play Developer Policy text. No found case of an HID app removed from Play.

## 7. USB-C alternative: Android as USB HID gadget; iPhone USB mouse support

### Takeaway
iPhone officially accepts **wired** mice via the USB-C/Lightning port for AssistiveTouch. Making an Android phone act as a USB HID gadget, however, requires **root plus a ConfigFS kernel**, which rules it out for typical users.

### Cited Findings
- AssistiveTouch supports a "wired mouse, trackpad … or Bluetooth device", plugged into the Lightning or USB-C port (USB-A needs an adapter) **[confirmed]**. Source: [Apple Support 111775](https://support.apple.com/en-us/111775)
- USB Gadget Tool (tejado) exposes keyboard and mouse gadgets as /dev/hidg0 and /dev/hidg1. It **requires root and a kernel with ConfigFS** and needs other apps to drive the endpoints **[reported]**. Sources: [GitHub tejado/android-usb-gadget](https://github.com/tejado/android-usb-gadget), [F-Droid USB Gadget Tool](https://f-droid.org/packages/net.tjado.usbgadget/)
- Android HID Client (Arian04) offers phone-as-keyboard+mouse over USB "WITHOUT any software on the other end (Requires root)" **[reported]**. Source: [ecosyste.ms Arian04/android-hid-client](https://awesome.ecosyste.ms/projects/github.com%2FArian04%2Fandroid-hid-client)
- HID Gadget Module (kelexine) is a Magisk module (Magisk 20.4+, OTG, configfs, root) **[reported]**. Source: [ecosyste.ms kelexine/hid-gadget-module](https://awesome.ecosyste.ms/projects/github.com%2Fkelexine%2Fhid-gadget-module)

### Inferences
- **[unconfirmed]** A USB-C to USB-C link between two phones also raises power-role questions (which side supplies power), and iPhone may try to charge from the Android phone or the reverse. USB HID could allow absolute digitizer descriptors that iOS treats differently from BT, but that is untested.
- Overall: for Mantiza, USB gadget mode is a niche power-user path. Unrooted Bluetooth Classic HID is the practical one.

### Gaps
- No report found of an Android USB HID gadget tested against an iPhone 15+ (USB-C).
