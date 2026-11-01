# Computers and other Apple devices as a software Bluetooth mouse/keyboard (HID "hands") for an iPhone

Context: Mantiza needs a device that shows up to the iPhone as a mouse (driving the AssistiveTouch pointer) plus keyboard, and takes commands from the Mantiza iPhone app. The baseline is a dedicated ESP32 board. This note covers whether devices a user may already own could do that job instead. Researched 2026-10-28.

Confidence labels: **[confirmed]** = official docs or vendor page; **[reported]** = one community or third-party source; **[unconfirmed]** = inference, or no source found.

## Q1. Linux (BlueZ) / Raspberry Pi as BLE HID (HOGP) or Classic HID device, and whether it works with iPhone/iPad + AssistiveTouch

### Takeaway
A Linux box or Pi can technically advertise as a BLE HID mouse or keyboard, and btferret ships ready-made `mouse`/`keyboard`/`keymouse` programs. But the most recent public reports (Oct 2025 to May 2026) say Apple hosts pair and then **ignore the input**, or time out on pairing. Those reports cover macOS, iPadOS and iOS. The same code works on Windows 11 and Android. I found no source showing a Pi or BlueZ software mouse moving the iPhone AssistiveTouch pointer, so this path is unproven and looks fragile for Apple hosts.

### Cited Findings
- btferret (C/Python Bluetooth stack for the Pi) says its "LE server can act as a Human Interface Device (HID) such as a keyboard, mouse or joystick. (Sometimes called HOGP - HID Over GATT Profile). So the Pi can be a Bluetooth keyboard for a phone/tablet/PC." It ships `keyboard.c/py`, `mouse.c/py` and `keymouse.c/py`. [confirmed, project docs] — [btferret README §3-11](https://github.com/petzval/btferret)
- The btferret README names Windows and Android as tested HID clients (passkey and cache quirks) and recommends JUST_WORKS pairing "for all clients". It gives no iOS-specific HID guidance. [confirmed, project docs] — [btferret README](https://github.com/petzval/btferret)
- btferret issue #79 (May 2026, open), on a **Raspberry Pi Zero 2 W**: `mouse.py` "worked" on a Windows 11 PC, but on macOS/iPadOS "device appears as connected, but cursor does not move and even button press is not recognized". The maintainer tried pairing changes and IRK fixes, then wrote: "I have now run out of suggestions… it works OK for Android devices." The reporter suspects "Apple products expect something more out of Bluetooth mouse." [reported] — [btferret #79](https://github.com/petzval/btferret/issues/79)
- btferret issue #68 (Oct 2025, open): the keyboard example with iOS, iPadOS and macOS "connect[s]… but the pairing always times out and the device is not recognized as a HID". [reported] — [btferret #68](https://github.com/petzval/btferret/issues/68)
- btferret issue #73 (Jan 2026, open): a Pi acting as a BLE HID mouse succeeded on the first iPadOS connection, but "every attempt afterward results in iPad showing 'pair time out'". [reported] — [btferret #73](https://github.com/petzval/btferret/issues/73)
- btferret issue #65 (Jun 2025, closed): iOS failed to auto-reconnect after its Bluetooth address rotated, until a bonding bug was fixed. This shows iOS address randomisation and bonding is a known pain point. It is not confirmed to be a HID case. [reported] — [btferret #65](https://github.com/petzval/btferret/issues/65)
- Other Pi Bluetooth HID projects exist: anesbenmerzoug/bluetooth_hid (Pi "emulate a keyboard/mouse Bluetooth HID client", Classic via BlueZ), nutki/bt-keyboard-switcher (tested on Pi 3B+ and Zero W, requires disabling the BlueZ input plugin), and PiKVM Bluetooth HID (tested only on RPi4 / v2; "Bluetooth mouse can work only in relative mode"). None documents iOS testing. [reported] — [bluetooth_hid](https://github.com/anesbenmerzoug/bluetooth_hid); [bt-keyboard-switcher](https://github.com/nutki/bt-keyboard-switcher); [PiKVM bluetooth_hid doc](https://git.blob42.xyz/Archives/pikvm/blame/commit/659b46a95afe02616830e7f93c103e3ab805c7cf/pages/bluetooth_hid.md)
- A MacRumors thread describes a Python Pi program that "emulates a Bluetooth mouse and keyboard on a Raspberry Pi, which is then connected to the iOS device via Bluetooth" to remote-control an iOS device from a browser. The page returned 403, so I could only see the search snippet and could not verify details or latency. [reported, unverified] — [MacRumors thread](https://forums.macrumors.com/threads/remotely-control-and-mirror-an-ios-device-from-your-browser-with-a-raspberry-pi.2332097)
- btferret also turns a Pi 400/500/500+ into a regular Bluetooth keyboard (Pi must boot Linux first, about 20 s). Press coverage mentions only "other computers" as hosts. [reported] — [CNX Software](https://www.cnx-software.com/2025/11/09/using-the-raspberry-pi-500-keyboard-pc-as-a-regular-bluetooth-keyboard/)
- Apple's official iPhone pointer support: pair under Settings > Accessibility > Touch > AssistiveTouch > Devices > Bluetooth Devices. The AssistiveTouch pointer then appears. [confirmed] — [Apple Support 111775](https://support.apple.com/en-bw/111775); [Apple iPhone guide](https://support.apple.com/en-om/guide/iphone/iph96b21954/ios)

### Inferences
- The Apple failures cluster in the BLE (HOGP) security/bonding and report-map area. Commercial BLE mice and ESP32 HID libraries pass that bar. A BlueZ-native HOGP server (bluez's own GATT `input`/`hog` profile in peripheral mode) or a Classic HID (L2CAP PSM 0x11/0x13 + SDP record) implementation might behave differently from btferret's custom stack. I found no source showing either working on iOS. [unconfirmed]
- If Mantiza goes the Pi/Linux route, budget for packet-level debugging (Apple PacketLogger vs a known-good BLE mouse), as issue #79's reporter plans. [unconfirmed]

### Gaps
- No source confirms a BlueZ/Pi software mouse driving the iPhone **AssistiveTouch** pointer specifically.
- I could not search GitHub issues on thanhle/quangthanh010290 `keyboard_mouse_emulate_on_raspberry` (a Classic HID project), because the API search failed. Its iOS compatibility is unknown.
- No latency measurements found for any Pi to iPhone HID path.

## Q2. Windows: can an app publish a GATT HID service (0x1812) via GattServiceProvider? Any working project?

### Takeaway
Microsoft's official restricted list for `GattServiceProvider` does **not** include HID (0x1812). It blocks only DIS, GATT, GAP and Scan Parameters. **But the block on Device Information Service (0x180A) matters:** a HOGP device is expected to expose DIS with a PnP ID, so a standards-complete HID peripheral can't be built from a Windows app. I found no project anywhere that turns a Windows PC into a BLE or Classic HID mouse/keyboard for a phone. Community advice is to run Linux in a VM with a passed-through dongle.

### Cited Findings
- Microsoft Learn (updated 2026-05-27): "The following Services are reserved by the system and cannot be published at this time: 1. Device Information Service (DIS) 2. Generic Attribute Profile Service (GATT) 3. Generic Access Profile Service (GAP) 4. Scan Parameters Service (SCP)". Attempting one returns `BluetoothError.DisabledByPolicy` from `CreateAsync`. HID (0x1812) is **not listed**. [confirmed] — [Microsoft Learn: Bluetooth GATT Server](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/gatt-server)
- The same doc: services published in the foreground must call `StopAdvertising` when the app suspends. The API needs the `bluetooth` capability in the app manifest. [confirmed] — [Microsoft Learn: Bluetooth GATT Server](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/gatt-server)
- `GattServiceProvider` has been available since Windows 10 Creators Update (10.0.15063). [confirmed] — [GattServiceProvider class](https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.genericattributeprofile.gattserviceprovider)
- HOGP requires bonding (security mode 1, level 2/3). Silicon Labs notes the profile also requires Battery Service and **Device Information Service**. [confirmed vendor docs / reported] — [Silicon Labs BLE HID Keyboard](https://docs.silabs.com/bluetooth/2.13/bluetooth-code-examples-applications/ble-hid-keyboard); [Nordic DevZone](https://devzone.nordicsemi.com/f/nordic-q-a/17515/windows-10-driver-error-when-connecting-hid-device/67341)
- Tom's Guide forum, "Can Windows emulate bluetooth keyboard/mouse": the answer offered was to run a Linux HID client in a VM with a passed-through Bluetooth dongle. No native Windows tool was named. [reported] — [Tom's Guide forum](https://forums.tomsguide.com/threads/can-windows-emulate-bluetooth-keyboard-mouse.309911/latest)
- Searches for a GitHub Windows `GattServiceProvider` HID emulator found none. The only HID-over-GATT library hits were mbed firmware (BLE_HID, 2015). [reported, negative result] — [mbed BLE_HID](https://os.mbed.com/users/jbru/code/BLE_HID)

### Inferences
- iOS reads PnP ID from DIS for HID matching. The Apple forum gamepad case below shows iOS logging `vendorID = 0` and refusing to start the HID driver. So a Windows app that can't publish its own DIS is likely to hit the same wall. [unconfirmed]
- Windows also has no public API for the Classic HID device role. [unconfirmed; no Microsoft doc found stating it either way]

### Gaps
- No primary test of `GattServiceProvider.CreateAsync(0x1812)` succeeding or failing on Windows 11 was found.
- No Windows project or latency data for an iPhone target.

## Q3. macOS: is HID publishing blocked in CoreBluetooth? IOBluetooth / private API workarounds? Typeeto, KeyPad, 1Keyboard: do they act as keyboard/mouse for iPhone?

### Takeaway
**The Mac is the strongest "already owned" option.** Commercial Mac apps have long made the Mac look like a Bluetooth keyboard to iPhones. Typeeto (Eltima) is keyboard only, last updated Jan 2022. **KeyPad (Toolbunch, Mac App Store, macOS 11+, v2.30) explicitly advertises "basic mouse functions for iPhones via Assistive Touch."** That is the only source I found of a software mouse driving the iPhone AssistiveTouch pointer. These apps most likely use the Classic Bluetooth HID device role via IOBluetooth (unconfirmed). On macOS, CoreBluetooth BLE HID publishing appears to be *allowed*: a Sep 2026 developer forum thread had an iPhone reading a Mac-published HID service. But iOS's HID driver rejected it (vendorID 0, "IOHIDEventDriver start failed"), and Apple DTS said this is not a supported path.

### Cited Findings
- **KeyPad – Bluetooth Keyboard** (Toolbunch LLC, Mac App Store): "Turn your Mac into a universal Bluetooth keyboard, mouse and media remote control." It targets iPhone, iPad, Android, Apple TV, smart TVs and Raspberry Pi. It offers "full cursor control" for iPads and "basic mouse functions for iPhones via Assistive Touch". It has Control+Option for mouse control, needs macOS 11.0+, and is free with KeyPad Pro lifetime at $4.99. Latest version 2.30 ("Minor UI Updates", Aug 29). No user review mentions iPhone mouse use. [confirmed vendor listing; iPhone mouse quality unconfirmed] — [App Store: KeyPad](https://apps.apple.com/us/app/keypad-keyboard-and-mouse/id1491684442)
- **Typeeto** (Eltima): "Your Mac acts as a Bluetooth keyboard" for any device that supports Bluetooth keyboards (iPhone, iPad, Android, Apple TV). Compatible with OS X 10.9.5+. Latest version 1.6 (516), released 2022-01-09, listed as free. "For iOS devices the connection has to be initiated from them." The page does not mention mouse support. [confirmed vendor page] — [Eltima Typeeto](https://mac.eltima.com/bluetooth-keyboard.html)
- A Typeeto review says the trackpad is not forwarded. The copy-paste feature is limited to 1024 characters, and keystrokes arrive "with little to no delay". [reported] — [Macworld review](https://www.macworld.com/article/226772/typeeto-review-magic-software-keyboard-for-all-of-your-mobile-devices.html); [macautomationtips](https://macautomationtips.com/typeeto-easy-remote-typing-on-your-ios-device/)
- Apple Developer Forums thread 848602 (Sep 2026): a **macOS CoreBluetooth peripheral** (MacBookPro17,1) published a BLE HID gamepad service. The iPhone connected and read the Report Map, HID Information and Input Report, and subscribed to input. But iOS logged "Un-authenticated game controller device attached", "Start failed: 0xe00002bc", "IOHIDEventDriver start failed", with `vendorID = 0, productID = 0`. Two Device Information services were visible: a system one ("Apple Inc.") and the app's one with PnP ID. Apple DTS (Kevin Elliott) said a generic BLE HID gamepad via macOS CoreBluetooth "is not a formally supported path" and suggested filing a bug. [reported, with Apple DTS reply] — [Apple Dev Forums 848602](https://developer.apple.com/forums/thread/848602)
- On **iOS**, `CBPeripheralManager` adding service 0x1812 fails with `CBErrorDomain Code=8 "The specified UUID is not allowed for this operation."`. Service 0x1124 (Classic HID UUID) can be added but is not treated as HID by hosts. A forum member adds: "An iOS app cannot act as a Bluetooth Classic device." This comes from community replies; Apple did not respond in the thread. [reported, multiple devs] — [Apple Dev Forums 725238](https://developer.apple.com/forums/thread/725238)
- In the same thread, a developer claims the iOS app "Bluetouch" appeared to advertise 0x1812 over BLE and mouse/keyboard input worked with a Mac. The mechanism was unexplained. [reported, single unverified source] — [Apple Dev Forums 725238](https://developer.apple.com/forums/thread/725238)

### Inferences
- Typeeto and KeyPad keep working on current macOS and iOS while CoreBluetooth HID is rejected by iOS. That makes it likely they use the **Classic HID (BR/EDR) device role** via IOBluetooth: SDP HID record, L2CAP control/interrupt channels, Mac class-of-device set to keyboard/peripheral. iOS AssistiveTouch accepts Classic HID mice. [unconfirmed: no vendor statement of mechanism found]
- For Mantiza, a Mac helper app (KeyPad-like) could receive commands from the iPhone app over Wi-Fi (WebSocket/Bonjour on the LAN), or via the Mac's own BLE GATT custom service, which CoreBluetooth allows for non-HID UUIDs. It would then emit Classic HID reports to the paired iPhone. The Mac must stay awake, have Bluetooth on, and be within about 10 m (Typeeto cites ~32 ft range). [unconfirmed design inference; range from Eltima/press]
- "Basic mouse functions" suggests relative-move + click only. Mantiza would need closed-loop pointer positioning (screenshot or screen-reader feedback), the same as with an ESP32. [unconfirmed]

### Gaps
- 1Keyboard (Eltima, an older sibling of Typeeto): I could not confirm its current availability. Treat it as likely discontinued (unconfirmed).
- No source states whether IOBluetooth's HID device role still works on macOS 26 (Tahoe) for third-party apps without entitlements. KeyPad's ongoing updates imply yes (unconfirmed).
- No latency figures for Mac-as-mouse to iPhone.

## Q4. iPad / second iPhone / Apple Watch / Apple TV as HID to an iPhone

### Takeaway
**No.** iOS and iPadOS apps can't publish the BLE HID service (0x1812 blocked) and can't act as Classic Bluetooth devices. watchOS and tvOS run on the same CoreBluetooth stack with no HID exemption documented, and I found nothing showing them acting as HID. The one oddity is a forum claim about the iOS app "Bluetouch". Even there, the tested host was a Mac, not an iPhone.

### Cited Findings
- iOS `CBPeripheralManager` rejects 0x1812 with CBErrorDomain Code=8 "The specified UUID is not allowed for this operation". A 0x1124 Classic HID UUID is accepted as a plain custom GATT service but not recognised as HID. Same thread: "An iOS app cannot act as a Bluetooth Classic device." [reported, multiple developers, Feb 2023 to Jan 2024] — [Apple Dev Forums 725238](https://developer.apple.com/forums/thread/725238)
- An Apple forum response says HID profiles "are directly consumed by the system and are not passed on to apps." [reported] — [Apple Dev Forums 695844](https://developer.apple.com/forums/thread/695844)
- iPhone-as-keyboard App Store apps (BT Keys, Bluetouch) target PCs, Macs, smart TVs and Raspberry Pi. None advertise iPhone or iPad as a target host. [reported vendor listings] — [BT Keys listing](https://mwm.ai/apps/bt-keys-keyboard-trackpad/6778806487); [Apple Dev Forums 725238](https://developer.apple.com/forums/thread/725238)

### Inferences
- Apple Watch and Apple TV: CoreBluetooth peripheral-role support on those platforms is limited and has the same UUID restrictions, and Apple TV is a HID *host*. I found no source showing either acting as a HID device. Treat both as not viable. [unconfirmed: I could not load Apple's CBPeripheralManager availability page]
- A spare iPhone or iPad remains useful only as a *command relay*, not as the HID. [unconfirmed]

### Gaps
- Whether the "Bluetouch" app really publishes HID-over-GATT on iOS, and whether an iPhone would accept it as a host, is unverified.

## Q5. Raspberry Pi Zero 2 W / Pico W as cheaper alternatives to ESP32, and USB-C wired HID (gadget mode) for iPhone 15+

### Takeaway
iPhone 15 and later officially accept **wired USB-C mice and trackpads** for AssistiveTouch. That opens a wired path that avoids the Apple BLE-HID pairing problems in Q1: a microcontroller or Pi in USB device (gadget) mode. A Pico W / Pico 2 W ($6–7 list) can be a USB HID mouse and also a BLE/Classic HID device via BTstack. A Pi Zero 2 W ($15 list, ~$28 retail) can be a USB HID gadget through its micro-USB data port. I found **no source confirming either board's USB HID being accepted by an iPhone**. Standard USB HID boot mice generally are, so this is promising but untested.

### Cited Findings
- Apple: you can connect a wired mouse or trackpad through the Lightning or **USB-C** port (USB-A needs an adapter), or Bluetooth. AssistiveTouch then shows the pointer. [confirmed] — [Apple Support 111775](https://support.apple.com/en-bw/111775)
- iPhone 15 and later accept USB-C mice by plugging them directly into the port. AssistiveTouch must be on. Apple Magic Mouse is not supported on iPhone. [reported] — [iDownloadBlog](https://www.idownloadblog.com/2023/10/10/how-to-use-mouse-with-iphone/)
- Linux USB gadget mode lets a Pi present as a USB HID keyboard/mouse via ConfigFS. The configuration is volatile and must be re-created each boot. [reported tutorial] — [Random Nerd Tutorials](https://randomnerdtutorials.com/raspberry-pi-zero-usb-keyboard-hid/)
- The `zero-hid` Python library emulates mouse and keyboard on a Pi Zero. You must "connect the data usb port (left one)", not the power port. [reported] — [zero-hid on PyPI](https://pypi.org/project/zero-hid)
- Raspberry Pi: gadget mode on Pi 4/5/500 uses the on-board USB-C port, and a port in gadget mode can't host other peripherals. [confirmed, Raspberry Pi news] — [raspberrypi.com](https://raspberrypi.com/news/usb-gadget-mode-in-raspberry-pi-os-ssh-over-usb)
- An iOS user reported that a Pi in gadget mode worked with Windows/Linux/macOS, but USB-Ethernet, audio and MIDI gadget functions did not work from iOS/iPadOS. That report was not about HID. [reported] — [Blokas community](https://community.blokas.io/t/gadget-mode-supported/5886)
- A project powered a Pi Zero from an iPad's USB-C port. A Pico acted as the USB HID keyboard toward *other* devices, which says the Pico "can be connected to any device that supports USB keyboards from smartphones to laptops and tablets". [reported] — [Tom's Hardware](https://www.tomshardware.com/news/raspberry-pi-ipad-hid-adapter)
- Pico W (arduino-pico core): BTstack Classic + BLE enabled. `MouseBT`/`KeyboardBT` emulate Classic HID devices and `MouseBLE` emulates a BLE mouse, "using the same API as their USB versions". [confirmed project docs] — [arduino-pico Bluetooth docs](https://arduino-pico.readthedocs.io/en/latest/bluetooth.html)
- Pico SDK 1.5.0 added BTstack Bluetooth, so the Pico W can be "a wireless mouse, wireless keyboard or other peripheral". [reported] — [Tom's Hardware](https://www.tomshardware.com/news/raspberry-pi-pico-w-sdk-adds-bluetooth)
- No iOS confirmation for a Pico HID: an Espruino forum user "didn't find any references to connecting the Pico to iOS devices" as HID. [reported] — [Espruino forum](https://forum.espruino.com/comments/13103622)
- Pricing: Pico 2 W launched at $7. Retail examples are $8.61 and €15.49. [reported] — [Notebookcheck](https://www.notebookcheck.net/Pico-2-W-Raspberry-Pi-releases-new-RP2350-single-board-computer-with-wireless-and-Micro-USB-connectivity.923219.0.html); [Vilros listing](https://reach.dog/shop/vilroscom/products/raspberry-pi-pico-2w). Pi Zero 2 W lists at $15; Walmart retail is $27.99 ($34.99 with header). [reported] — [hackerboards](https://hackerboards.com/compare/raspberry-pi-foundation-raspberry-pi-zero-2-w/raspberry-pi-foundation-raspberry-pi-pico); [Walmart](https://www.walmart.com/c/kp/raspberry-pi-zero-w-projects)

### Inferences
- **Wired option:** Pico W / Pico 2 W plugged into the iPhone's USB-C port as a TinyUSB HID mouse+keyboard, powered by the iPhone. It would receive commands over Wi-Fi (the iPhone app connects to the Pico's soft-AP or the LAN via WebSocket/UDP) or over BLE with a custom GATT service. This avoids Bluetooth HID pairing entirely and is likely the lowest-latency, most reliable "dongle" form. Caveats: it occupies the charging port (needs a passthrough hub to charge) and only works on USB-C iPhones (15+). [unconfirmed: needs a bench test]
- **Pi Zero 2 W** is overkill compared with ESP32/Pico: it boots Linux (seconds), draws more power and costs 2–4× more. Its BLE HID path inherits the Apple problems in Q1. Its micro-USB data port needs a micro-B OTG to USB-C cable for the iPhone. [unconfirmed]
- Cost against ESP32: Pico 2 W at ~$7 is in the same range as common ESP32 dev boards. Its advantage is native USB device support, which plain ESP32/ESP32-C3 lack and ESP32-S3 has. [unconfirmed; ESP32 prices not researched here]

### Gaps
- No test report of an iPhone accepting a Pi or Pico USB HID gadget mouse. No report on iPhone USB-C bus power sufficiency for a Pi Zero 2 W.
- No test of Pico W BTstack HID mouse with iOS AssistiveTouch.

## Q6. Command channel from the iPhone app, latency, and whether the computer must be on and nearby

### Takeaway
Every computer-based option needs the computer **powered on, awake, with Bluetooth on, and within Bluetooth range (~10 m)** of the iPhone. The command channel would be a LAN socket (Wi-Fi/WebSocket/Bonjour) or a custom BLE GATT service, which iOS allows for non-HID UUIDs. That makes it a "desk mode" solution, not a portable one. No measured latency data exists in any source found. Vendors only claim "little to no delay".

### Cited Findings
- Typeeto range is "approximately 32 feet". Typed input reaches the device "with little to no delay". [reported] — [macautomationtips](https://macautomationtips.com/typeeto-easy-remote-typing-on-your-ios-device/); [TechARP](https://www.techarp.com/articles/typeeto-using-mac-bluetooth-keyboard/?amp=1)
- For iOS targets, the Bluetooth connection to Typeeto must be initiated from the iOS device. [confirmed vendor page] — [Eltima Typeeto](https://mac.eltima.com/bluetooth-keyboard.html)
- Windows GATT services published in the foreground must stop advertising when the app suspends. A Windows helper would need to stay in the foreground or use background registration. [confirmed] — [Microsoft Learn: Bluetooth GATT Server](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/gatt-server)
- btferret HID on a Pi: reconnects can fail first time with "MIC failure" and then succeed. The connection procedure "can take some time". [confirmed project docs] — [btferret README](https://github.com/petzval/btferret)
- iOS rotates its Bluetooth address, which broke btferret auto-reconnect until a 2025 fix. [reported] — [btferret #65](https://github.com/petzval/btferret/issues/65)

### Inferences
- Suggested channels: (a) **Mac/PC/Pi on the same Wi-Fi**: the iPhone app opens a WebSocket to the helper, which is discoverable via Bonjour/mDNS. Typical LAN round trip is a few ms, so total command-to-pointer latency is likely dominated by the Bluetooth HID report interval (7.5–15 ms BLE, ~10 ms Classic) plus iOS pointer smoothing. (b) **BLE custom GATT** from the iPhone app to the helper. This works without Wi-Fi, but the helper's radio then runs both a BLE link and a HID link at once. [unconfirmed: no measured data]
- iOS background limits matter on the Mantiza side. The iPhone app must keep its command socket alive while another app is in the foreground. BLE (with `bluetooth-central` background mode) usually survives backgrounding better than a raw WebSocket. [unconfirmed; not researched here]
- Overall ranking for "already owned" hands: (1) **Mac running a KeyPad-style Classic-HID helper**: the only documented iPhone AssistiveTouch mouse path, but tethered to a desk. (2) **Pico W/2 W wired over USB-C** (iPhone 15+): cheap, portable, untested. (3) Linux/Pi BLE HID: documented Apple failures. (4) Windows: no known path. (5) iPad/iPhone/Watch/TV: not possible. [unconfirmed synthesis]

### Gaps
- No published latency measurements for any software-HID to iPhone path.
- No evidence on whether KeyPad's iPhone mouse mode supports precise or absolute positioning. It is probably relative-only.
