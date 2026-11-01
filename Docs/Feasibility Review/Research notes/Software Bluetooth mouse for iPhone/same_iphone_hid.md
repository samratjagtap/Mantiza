# Can an iPhone app emulate a Bluetooth HID mouse/keyboard (for itself or another iPhone)?

Research date: 2026-10-28. Confidence labels: **[Apple-confirmed]** = Apple docs or Apple engineer reply; **[Multi-source]** = several independent non-Apple reports; **[Single-source]** = one report; **[Unconfirmed]** = inference or general knowledge with no source found.

Headline: our earlier note ("iOS apps cannot publish HID, Code=8") is **only partly right**. The 16-bit UUID `1812` is blocked. But developers report that the same service registers when written as the full 128-bit UUID, and at least three App Store apps (Bluetouch, TabletHID, Mobile Mouse Bluetooth Remote) sell "iPhone as a Bluetooth mouse/keyboard with no host software". One of them says an iPhone can control an **iPad** this way. So a *second* iPhone could plausibly replace the ESP32. Making the *same* iPhone its own mouse (loopback) still looks impossible.

## 1. Can CBPeripheralManager publish HID-over-GATT (0x1812), Device Information (0x180A) or Battery (0x180F)?

### Takeaway
Adding the HID service as the 16-bit UUID `1812` fails with `CBErrorDomain Code=8 "The specified UUID is not allowed for this operation."` An Apple engineer confirmed in May 2026 that iOS blocks some UUIDs on purpose, without listing which ones. Developers report that the 128-bit form `00001812-0000-1000-8000-00805F9B34FB` gets past the check, and shipping App Store apps appear to depend on it. Apple has published no list of reserved UUIDs.

### Cited Findings
- **[Multi-source]** Adding service `1812` to a `CBPeripheralManager` returns: `Error Domain=CBErrorDomain Code=8 "The specified UUID is not allowed for this operation."` (Feb 2023). A second developer hit the same error in Jan 2024. — [Apple Dev Forums 725238](https://developer.apple.com/forums/thread/725238)
- **[Single-source]** The same `1812` error appears in a Dec 2021 thread that followed Apple's archived "Best Practices for Setting Up Your iOS Device as a Peripheral" guide. That thread quotes older forum replies (threads 5865 and 69814) saying "HID profiles are directly consumed by the system in iOS and not passed on to the apps." — [Apple Dev Forums 695844](https://developer.apple.com/forums/thread/695844)
- **[Single-source]** In 2013 (Stack Overflow), adding 0x1812 failed while other custom and standard services registered. A commenter suggested filing a radar to get the docs updated, which suggests the block was undocumented. — [SO mirror: create ios ble hid service](https://kiwix.lema.org/stackoverflow.com_en_all_2023-11/questions/20827028/create-ios-ble-hid-service)
- **[Apple-confirmed]** Battery Service `180F` also returns Code=8. An Apple engineer replied (May 2026, marked Recommended): "Yes, advertising certain services/characteristics is restricted by the system. Typically these will be Apple specific UUIDs, and entries in the GATT profiles that are otherwise being used by the system." The reply names no specific UUIDs. — [Apple Dev Forums 826714 "Battery Service Peripheral - Not Allowed?"](https://developer.apple.com/forums/thread/826714)
- **[Single-source]** The gist author says "As of iOS 14, the services are blocked by the system." The gist is a full Swift CoreBluetooth HOGP keyboard (HID service, report map, Device Info service). — [conath gist](https://gist.github.com/conath/c606d95d58bbcb50e9715864eeeecf07)
- **[Single-source, important]** **Workaround:** commenter Taati89 on that gist: "I tried changing the UUID from 1812 to 00001812-0000-1000-8000-00805F9B34FB and it successfully added the service." With extra fixes (a descriptor 0x2908 Report Reference on the report characteristic, and a corrected report map), typing reportedly worked on Windows and Android, and later on macOS. Reconnecting after killing the app was unreliable and needed "Forget Device" on both sides. A later commenter (Sep 2024) could not get a Mac to find the iPhone. — [conath gist comments](https://gist.github.com/conath/c606d95d58bbcb50e9715864eeeecf07)
- **[Single-source]** A May 2026 commenter (kvaDrug) on the same gist says the Device Information Service (0x180A) is not available on CoreBluetooth. Not verified. — [conath gist comments](https://gist.github.com/conath/c606d95d58bbcb50e9715864eeeecf07)
- **[Single-source]** A BLE analyzer showed an iPad running Bluetouch advertising 0x1812. During a 180 s discoverable window it was visible from Windows and Android but not from a MacBook Air. Bluetouch's other mode, where the iPad acts as *central* and connects to the Mac, did deliver keyboard and mouse input (Jan 2024). — [Apple Dev Forums 725238](https://developer.apple.com/forums/thread/725238)
- **[Apple doc exists, text not retrieved]** `CBError.Code.uuidNotAllowed` is a documented case. Its raw value of 8 matches the logged errors, but I could not retrieve the page body. — [CBError.Code.uuidNotAllowed](https://developer.apple.com/documentation/corebluetooth/cberror-swift.struct/code/uuidnotallowed)
- **[Single-source]** Apple's CBPeripheralManager docs describe publishing services to the local GATT database. They say nothing about reserved or restricted UUIDs. — summarized via [CBPeripheralManager docs](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager)

### Inferences
- The check appears to compare the UUID against a blocklist in its 16-bit form, and the 128-bit spelling of the same UUID gets through. That is a loophole, not a supported feature. Apple could close it in any iOS release, and App Review could treat it as misusing the API.
- By iOS version: blocked since at least iOS 7 era (2013 SO), stated "as of iOS 14", still blocked in 2023, 2024 and 2026 (Apple reply). I found nothing saying iOS 17, 18, 26 or 27 removed the block. Whether the 128-bit workaround still works on iOS 26/27 is untested by any source I found. Indirect evidence that it still works: TabletHID (requires iOS 17, version 1.8.0 dated 13 May, presumably 2026) and Mobile Mouse Bluetooth (2026 copyright, updated Oct 2026) are on sale.

### Gaps
- No Apple-published list of restricted UUIDs. The Apple engineer did not name 1812 or 180A.
- No primary source dated iOS 26 or iOS 27 that tests `1812` versus the 128-bit form.
- Bluetouch, TabletHID and Mobile Mouse do not disclose how they work. That they use the 128-bit trick is inferred, not confirmed.

## 2. Can an iPhone be its own HID mouse (central and peripheral loopback on one phone)?

### Takeaway
No source shows an iPhone pairing with its own advertisement, and the BLE link layer is built around two separate devices. Even if a HOGP peripheral could be published, iOS's HID host would need to find and bond to its own radio, and nothing suggests that is possible. Treat same-iPhone emulation as not feasible. A second Apple device acting as the mouse is a different question (see Section 5).

### Cited Findings
- **[Single-source]** The Bluetooth Core Spec allows one device to scan and advertise at the same time. This covers simultaneous roles, not connecting to itself. — [Apple bluetooth-dev list, 2013](https://lists.apple.com/archives/bluetooth-dev/2013/Jan/msg00072.html)
- **[Single-source]** iOS (since iOS 6) can run CoreBluetooth central and peripheral roles. — [jde/CoreBluetoothPeripheral](https://github.com/jde/CoreBluetoothPeripheral)
- **[Unconfirmed]** No search turned up a CoreBluetooth app discovering or connecting to its own `CBPeripheralManager` advertisement, or iOS Settings / AssistiveTouch "Bluetooth Devices" listing the phone itself. — searches summarized in [Apple Dev Forums search results](https://developer.apple.com/forums/thread/679529)

### Inferences
- A BLE connection forms between an advertiser and an initiator with different device addresses. A single controller connecting to itself is not a normal link-layer scenario, and stacks usually reject a connection to the local address. This is general knowledge, not sourced.
- AssistiveTouch pairs pointer devices through Settings > Accessibility > Touch > AssistiveTouch > Devices > Bluetooth Devices ([Apple Support 111775](https://support.apple.com/es-lamr/111775)), which uses the system's HID host. Even if a loopback link existed, iOS would also have to treat its own app-published GATT database as a remote HID device. Nothing suggests it does.

### Gaps
- No Apple or Bluetooth SIG statement on self-connection. Settling this would need a one-afternoon experiment: advertise 128-bit 1812 from an app and look in AssistiveTouch > Bluetooth Devices on the same phone.

## 3. Classic Bluetooth (BR/EDR) HID from an iOS app; External Accessory / MFi / iAP2

### Takeaway
Third-party iOS apps have no public API for being a BR/EDR (Classic) device or for publishing an SDP HID record. External Accessory and MFi let an app *talk to* MFi hardware. They do not make the iPhone act like an accessory. AccessorySetupKit (iOS 18+) is also only for setting up external accessories.

### Cited Findings
- **[Multi-source, community]** "An iOS app cannot act as a Bluetooth Classic device." (endecotp, about 85% confident). The asker ruled out ExternalAccessory because the host is not MFi, and ruled out GameController because it only makes the iPhone a *host* for controllers. — [Apple Dev Forums 725238](https://developer.apple.com/forums/thread/725238)
- **[Single-source]** Adding UUID `1124` (the Classic HID service class) to a CBPeripheralManager succeeds, but iOS publishes it as an ordinary custom GATT service, and the host never treats it as HID. — [Apple Dev Forums 725238](https://developer.apple.com/forums/thread/725238)
- **[Single-source]** The App Store Bluetooth input apps the asker found were Wi-Fi based or tied to specific companies' hardware (2023). — [Apple Dev Forums 725238](https://developer.apple.com/forums/thread/725238)
- **[Apple doc]** AccessorySetupKit (iOS/iPadOS 18.0+) discovers and configures external Bluetooth or Wi-Fi accessories. Under TN3115, from iOS 26 only apps that set up Bluetooth accessories with AccessorySetupKit are relaunched in the background (forum report). — [AccessorySetupKit docs](https://developer.apple.com/documentation/accessorysetupkit), [Punch Through ASK guide](https://punchthrough.com/ios18-accessorysetupkit-everything-ble-developers-need-to-know/)
- **[Unconfirmed]** A third-party skill file lists a `.bluetoothHID` option in AccessorySetupKit. The Apple doc URL I guessed returned 404. If it exists, it would be for pairing an external HID accessory, not for emulating one. — [swift-ios-skills accessorysetupkit](https://skills.sh/dpearson2699/swift-ios-skills/accessorysetupkit)
- **[Single-source]** The MFi route exists for *hardware*: AMAneo BTi is an MFi adapter that lets a physical mouse drive iPhone/iPad. — [AMAneo BTi](https://specialneedscomputers.ca/products/amaneo-bti-assistive-mouse-adapter-for-ios)

### Inferences
- MFi and iAP2 are licensed for accessory hardware with Apple's authentication coprocessor. They give the iPhone side no way to impersonate an accessory, so this route does not remove the ESP32.

### Gaps
- No Apple DTS statement on BR/EDR peripheral roles was found. The claim is community consensus.

## 4. Frameworks or APIs that could synthesize touches/pointer events into other apps (public vs private)

### Takeaway
No public iOS API lets one app inject touches or pointer events into another app. Apple's own synthetic touch code (IOHIDEvent / IOHIDEventSystemClient) is private. App Review rejects apps that use it, and guideline 2.5.1 (public APIs only) also applies to Notarization, so EU alternative-marketplace distribution does not escape it. Private APIs only work in builds that never pass Apple review (Xcode dev installs, possibly ad hoc or enterprise), and even then the sandbox may block them.

### Cited Findings
- **[Apple-confirmed]** Guideline 2.5.1: "Apps may only use public APIs and must run on the currently shipping OS… Apps should use APIs and frameworks for their intended purposes." It carries the "ASR & NR" tag, meaning it applies to Notarization for iOS/iPadOS apps as well as App Store Review. — [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- **[Single-source]** An app was rejected for "Non-public API usage" over symbols including `_IOHIDEventCreateDigitizerEvent`, which came from the bundled KIF testing framework. — [Titanium JIRA MOD-2315](https://jira-archive.titaniumsdk.com/MOD-2315)
- **[Apple open source]** WebKit's internal `_WKTouchEventGenerator` creates synthetic digitizer events through `IOHIDEventSystemClientRef`. This is Apple-internal test tooling built on private IOKit HID headers (`IOHIDEventPrivate.h`). — [_WKTouchEventGenerator.mm](https://opensource.apple.com/source/WebKit2/WebKit2-7610.3.7.0.3/UIProcess/_WKTouchEventGenerator.mm.auto.html), [IOHIDEventPrivate.h](https://opensource.apple.com/source/IOKitUser/IOKitUser-1726.41.1/hid.subproj/IOHIDEventPrivate.h.auto.html)
- **[Single-source]** On Stack Overflow, the author of a touch-injection technique said Apple would not approve it for the App Store. — [SO mirror: injecting touch events on iOS](https://kaweah.freedombox.rocks/kiwix/stackoverflow.com_en_all_2023-11/questions/22693045/injecting-touch-events-on-ios)
- **[Multi-source]** Under the EU model, Apple can revoke an app's notarization, which blocks installing and running it even outside the App Store. iTorrent (AltStore PAL) lost its distribution ability in 2025. — [heise](https://www.heise.de/en/news/iTorrent-Apple-apparently-withdraws-sideloading-license-from-developers-10625008.html?view=print), [iDrop News](https://www.idropnews.com/news/think-eu-app-stores-break-apples-control-think-again/252245/)
- **[Single-source]** Apple's CoreHID docs mention emulating a virtual device such as a game controller "without physical hardware". The search result did not show whether this is available on iOS. — [CoreHID docs](https://developer.apple.com/documentation/corehid)
- **[Multi-source]** GameController makes the iPhone a host for input devices, not an input device itself. — [Apple Dev Forums 725238](https://developer.apple.com/forums/thread/725238)

### Inferences
- CoreHID's virtual-device feature is, as far as I know, macOS-only (macOS 15+). If an iOS version existed it would likely require an entitlement. Not verified; check the docs' availability badges.
- From general knowledge, not sourced here: AssistiveTouch custom gestures and Shortcuts can record and replay gestures, but only when the user triggers them, and apps cannot call them. Universal Control works Mac to iPad, not to iPhone. UIAccessibility and XCTest/XCUITest synthesize events only inside test runners attached from Xcode, not in shipped apps.
- The only private-API path in practice is a developer-signed or jailbroken build. Neither works for a consumer product. TestFlight goes through App Review, and 2.5.1 applies to it.

### Gaps
- No current (2025–2026) primary source on rejections for IOHIDEvent symbols, and none on whether iOS 26/27 sandboxing blocks `IOHIDEventSystemClient` dispatch from a dev-signed app.
- Did not verify CoreHID's platform availability.

## 5. Existing apps and projects that turn an iPhone into a Bluetooth keyboard/mouse

### Takeaway
There are two kinds. (a) Wi-Fi apps with a companion server on the computer, the classic approach. (b) A newer group of App Store apps that claim **native Bluetooth HID with nothing installed on the host**: Bluetouch, TabletHID, and Mobile Mouse Bluetooth Remote. Mobile Mouse explicitly says "An iPhone can control a compatible iPad as a Bluetooth mouse and keyboard." That is the strongest evidence that an iPhone app can be a HOGP pointer for an Apple mobile device. If it also works with an iPhone target, a second iPhone could stand in for the ESP32 in Mantiza.

### Cited Findings
- **[Single-source, App Store listing]** Mobile Mouse Bluetooth Remote (R.P.A. Tech / RPA Tech, Inc.) controls "Mac, Windows, Linux, or iPad". It needs "No Companion Software — Nothing to install on the computer you control". "Multiple Devices" lists "computers, iPads, iPhones, and Apple TV". It requires iOS 17.6+, has a subscription ($4.99/mo, $29.99/yr, $39.99 lifetime), and was at version 2.1.0 on Oct 20 (2026 copyright). — [App Store id6749246683](https://apps.apple.com/us/app/id6749246683)
- **[Single-source, developer site]** "An iPhone can control a compatible iPad as a Bluetooth mouse and keyboard." Compatible devices see it as "a standard Bluetooth keyboard and mouse". Windows and Linux work over Bluetooth without the dongle. The optional USB dongle "acts as a standard USB mouse and keyboard". Bluetooth mode is mouse and keyboard only. The site does not mention AssistiveTouch or iPhone targets. — [bluetooth.mobilemouse.com](https://bluetooth.mobilemouse.com)
- **[Single-source, App Store listing]** TabletHID (developer Max Murphy) offers mouse, gamepad and keyboard macros "for your PC or Mac" over HID-over-GATT, with no server software, and pairs "through your computer's standard Bluetooth settings". The listing warns: "TabletHID utilizes experimental Bluetooth HID-over-GATT implementations… Performance may vary depending on your host device's Bluetooth chipset and operating system." Requires iOS 17+. v1.8.0 dated 13 May. — [App Store TabletHID](https://apps.apple.com/lb/app/tablethid/id6766346670)
- **[Multi-source]** Bluetouch (App Store id1622635358) is a BLE keyboard, trackpad and mouse with no host software. Users report it is buggy, and reconnecting often means force-closing apps. On an analyzer it advertised 0x1812. — [Bluetouch App Store](https://apps.apple.com/app/id1622635358), [SourceForge listing](https://sourceforge.net/app/bluetouch/iphone/), [Apple Dev Forums 725238](https://developer.apple.com/forums/thread/725238)
- **[Single-source]** Hardware approach: KoStard's ESPRemoteControl is an ESP32-S3 that acts as a USB HID device and receives BLE from an iPhone app. This is the same design as Mantiza's current ESP32 plan. — [Hackaday, 2026-02-01](https://hackaday.com/2026/02/01/iphone-becomes-a-bluetooth-keyboard-and-mouse), [GitHub KoStard/ESPRemoteControl](https://github.com/KoStard/ESPRemoteControl)
- **[Single-source]** Wi-Fi approach: in 2023, the App Store keyboard/mouse apps the forum asker found used Wi-Fi with host software. Mobile Mouse's own Wi-Fi edition needs desktop server software for its advanced features. — [Apple Dev Forums 725238](https://developer.apple.com/forums/thread/725238), [bluetooth.mobilemouse.com](https://bluetooth.mobilemouse.com)

### Inferences
- **Implication for Mantiza:** removing the ESP32 by emulating on the *same* phone is not realistic. **Replacing the ESP32 with a second iOS device** (an old iPhone running a "Mantiza Pointer" app that publishes HOGP through the 128-bit UUID) looks plausible. An iPhone-to-iPad mouse ships on the App Store today, and iPhone AssistiveTouch accepts standard Bluetooth mice. Risks:
  - Apple may close the 128-bit loophole.
  - App Review may reject the app under 2.5.1's "intended purposes" clause. Note that three apps doing this are currently approved.
  - Reconnection is reported to be flaky.
  - CoreBluetooth peripheral mode in the background is limited, so the pointer app may need to stay in the foreground. Background advertising is a known limitation, not sourced here.
- The Mantiza agent on phone A cannot tell phone B what to do without a link between them. That link (BLE custom service, Wi-Fi, or cloud) is easy to build with public APIs.

### Gaps
- Whether an iPhone (rather than iPad) target accepts these apps as an AssistiveTouch pointer is unconfirmed. Mobile Mouse's FAQ text on iPhone targets was not retrieved. Testing Mobile Mouse or TabletHID from iPhone B to iPhone A's AssistiveTouch would answer it quickly.
- Not confirmed whether these apps can send absolute positioning (a digitizer report) or only relative mouse deltas. AssistiveTouch is built for relative pointers, which matters for agent precision.
- The apps' internal mechanisms are undisclosed.
