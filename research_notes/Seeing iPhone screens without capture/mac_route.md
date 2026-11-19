# Mac-side routes to see (and control) the iPhone screen for Mantiza

Context: iPhone 13 (Lightning), iOS 27.2, free Personal Team; MacBook Pro on macOS 26. Date of research: 2026-11-03. Most sources describe macOS 15/26 and iOS 18/26. I found nothing iOS 27 or macOS 27 specific for these routes unless stated, so treat every behavior as "last confirmed on 26.x, verify on 27".

## iPhone Mirroring (macOS 15+/26): requirements, phone-side state, capture, control, automation projects, limits

### Takeaway
iPhone Mirroring is the only Mac route that gives both pixels and pointer/keyboard control with no hardware. Existing open-source MCP servers already drive it with screenshots plus CGEvent input. The catch for Mantiza is structural: the iPhone has to stay **locked**, and picking it up or unlocking it ends the session. The user can't hold and use the phone while the agent works, and Face ID, the camera, Control Center and hardware buttons can't be reached. It does not show a red recording indicator. The phone shows an "in use by <Mac>" lock-screen state instead.

### Cited Findings
- Requirements: macOS Sequoia 15 or later on Apple silicon or a T2 Mac. iOS 18 or later with a passcode. Both devices on the same Apple Account with two-factor authentication. Bluetooth and Wi-Fi on for both. The iPhone must be **locked** and near the Mac, and may be charging or in StandBy. The Mac can't be sharing its internet or using AirPlay or Sidecar. Only one Mac and one iPhone can be paired for mirroring at a time. **Not available in the EU.** (High confidence, Apple primary) — [Apple Support: iPhone Mirroring](https://support.apple.com/en-us/120421)
- On the iPhone during mirroring: "The iPhone stays locked, and it indicates that it's in use and identifies the Mac using it". Afterwards the phone reports that it was used from a Mac, and Settings > General > AirPlay & Continuity > iPhone Mirroring lists which Mac, when and for how long. (High) — [Apple Support](https://support.apple.com/en-us/120421)
- Limits: the camera and microphone aren't available, which rules out **Face ID** and phone calls. Audio plays through the Mac. Streaming providers may block premium video. Notifications go to the Mac whether or not you are mirroring. (High) — [Apple Support](https://support.apple.com/en-us/120421)
- Session end: "Mirroring pauses automatically after periods of inactivity". The session also stops if you quit the app or **unlock the iPhone**. Apple publishes no timeout value. (High that it exists; the duration is unknown) — [Apple Support](https://support.apple.com/en-us/120421)
- **mirroir-mcp** (jfarcand): an MCP server that drives "a real iPhone via macOS iPhone Mirroring" with screenshot, tap, swipe and type, 33 tools, installed with npx for Claude Code. It needs Screen Recording and Accessibility permissions. Input goes through the "macOS CGEvent API" as a regular user process: "no daemons, no kernel extensions, no root". It uses OCR and an optional YOLO CoreML icon detector. Characters the keyboard layout can't type (emoji, CJK) go through Universal Clipboard. Mirroring exposes "a single pointer", so there is no multi-touch. Closing iPhone Mirroring is the "kill switch". One vision-mode frame costs about 24k tokens and takes 3-14 s, mostly LLM time. Its docs/limitations.md lists "Focus stealing, keyboard layout gaps, autocorrect". (High, primary repo) — [GitHub mirroir-mcp](https://github.com/jfarcand/mirroir-mcp); companion skills repo noted in [search listing](https://github.com/jfarcand)
- **iphone-mirror-mcp** (nickatnight96): the same approach, with input through the "CGEvent pipeline". Tap coordinates are pixel positions in the latest screenshot, scaled to the window bounds. Text is pasted through the clipboard. "Pinch and rotate gestures can't be synthesized". There is "no accessibility tree", so OCR and template matching stand in. "Face ID, Control Center, and hardware buttons are unreachable". The session pauses when the phone is unlocked or picked up and resumes only once the phone is locked again. "DRM content captures black". (High, primary repo) — [GitHub iphone-mirror-mcp](https://github.com/nickatnight96/iphone-mirror-mcp)
- Screenshotting the mirroring window works in practice: both projects capture frames with Screen Recording permission. Neither README names the API (ScreenCaptureKit or `screencapture`). (Medium-high) — [mirroir-mcp](https://github.com/jfarcand/mirroir-mcp), [iphone-mirror-mcp](https://github.com/nickatnight96/iphone-mirror-mcp)
- Frame rate and latency: one article claims up to 60 fps. Pre-release demos called it "virtually no lag". I found no measured end-to-end latency. (Low) — [Tom's Guide](https://tomsguide.com/computing/macos/macos-sequoia-7-things-you-need-to-know-about-iphone-mirroring), [Android Authority](https://androidauthority.com/iphone-mirroring-feature-demo-3453019); reviews without numbers: [Engadget](https://www.engadget.com/computing/macos/macos-sequoia-review-iphone-mirroring-is-more-useful-than-you-think-140008463.html?src=rss), [BGR](https://bgr.com/reviews/macos-sequoia-review/), [Six Colors](https://sixcolors.com/post/2024/07/first-look-macos-sequoia-public-beta/)
- Reliability on 26.x is shaky, going by user reports:
  - "Connection Interrupted" after 4-5 s on iOS 26 with Tahoe 26 — [Apple Community](https://discussions.apple.com/thread/256148409)
  - "Timed out connecting" after iOS 26 — [Apple Community](https://discussions-cn-prz.apple.com/thread/256137167)
  - Failures after iOS 26.2 and 26.2.1 — [thread 1](https://discussions.apple.com/thread/256230316), [thread 2](https://discussions.apple.com/thread/256234498)
  - Broken in the primary user account on the macOS 26.6 beta — [Apple Developer Forums](https://developer.apple.com/forums/thread/828526)
  - Sidecar and iPhone Mirroring no longer work at the same time on Tahoe — [Apple Community](https://origin-discussions2-us-dr-prz.apple.com/thread/256159119)
  
  (Medium: anecdotal, but there are many reports)

### Inferences
- **Works on iPhone 13?** Very likely. Mirroring needs iOS 18 or later and the phone is on iOS 27.2. I did not find an Apple page listing models, so verify on the device. (Medium-high)
- **Can it replace the ESP32 entirely?** Only for single-pointer tap, swipe, scroll and typing, and only while the phone is locked and nobody is touching it. Mantiza's ESP32 plus AssistiveTouch route works while the user holds an unlocked phone, and the iOS app stays in the loop. Mirroring inverts that: the on-phone Mantiza app becomes a passive bystander, and any user touch kills the session. It is better framed as a separate "Mac-hosted agent mode" for phone-on-desk tasks than as a drop-in replacement. (Medium)
- No red or orange privacy dot is expected. Apple describes an "in use by Mac" locked state instead. The exact iOS 27 wording and visuals need checking on the device.
- Campus Wi-Fi: Continuity uses Bluetooth for discovery and Wi-Fi for transport. Apple doesn't say whether the devices must share an access point. Client isolation on eduroam-style networks may or may not matter, because Continuity often uses peer-to-peer AWDL. Test on Berkeley Wi-Fi. (Low)
- Latency budget: expect capture to cost a few tens of ms at most. The agent loop will be dominated by the vision LLM (3-14 s per frame in mirroir's numbers), so capture latency hardly matters for model choice. (Medium)

### Gaps
- No measured latency or fps for iPhone Mirroring.
- No inactivity timeout value.
- No confirmation of the iOS 27 / macOS 27 behavior.
- I didn't confirm whether ScreenCaptureKit window capture of the mirroring window is blocked on Tahoe the way AirPlay windows are. The MCP projects imply it isn't, but verify.
- I don't know whether apps can detect that they are being mirrored, for example banking apps that blank their content.

## AirPlay screen mirroring iPhone -> Mac's built-in AirPlay Receiver (macOS 12+)

### Takeaway
It's poorly suited to an agent. On macOS Tahoe 26, the mirrored AirPlay window is reported to go **black as soon as any screen capture starts**, the receiver gives no input path, and the iPhone shows a mirroring indicator in its status bar. It should be deprioritized.

### Cited Findings
- AirPlay Receiver arrived on compatible Macs in macOS Monterey 12. AirPlay works over direct peer-to-peer links or an infrastructure LAN, and peer-to-peer is described as preferred. (Medium, Wikipedia) — [Wikipedia: AirPlay](https://en.wikipedia.org/wiki/AirPlay)
- There are no official latency figures. AirPlay compresses before streaming, so latency "can't be eliminated entirely". A USB link was mentioned for Mac-to-Mac AirPlay. (Low-medium, 2021) — [Cult of Mac](https://www.cultofmac.com/?p=744809), [MacRumors thread](https://spy.macrumors.com/threads/everything-technical-about-airplay-to-mac.2302079/)
- Capture is blocked. One source says wireless mirroring "doesn't work for recording on recent versions of macOS" and shows as "a black rectangle in any screen recording", blocked in every recording app. (Medium-high) — [Tella help](https://www.tella.com/docs/help/tips/i-phone-demos-using-screen-mirroring)
- Further reports of the same block:
  - The mirrored window goes black whenever a recorder runs, on Tahoe but not Sequoia — [Apple Community](https://discussions.apple.com/thread/256155053), [Apple Community 2](https://discussions.apple.com/thread/256219481)
  - OBS users suspect a deliberate restriction, and one says Window Capture instead of Display Capture worked for them — [OBS forum](https://obsproject.com/forum/threads/screen-capture-on-mac-os-when-screen-mirroring-from-ipad.194449)
  - A dev.to post titled "macOS Tahoe blacks out AirPlay mirrored windows under capture" exists, but returned 404 when fetched — [search hit](https://dev.to/apoorvdarshan/macos-tahoe-blacks-out-airplay-mirrored-windows-under-capture-heres-my-workaround-3icb)
- Phone-side indicator: Apple documentation describes a **blue** bar or status-bar highlight while AirPlay mirroring, which is stopped from Control Center > Stop Mirroring. The Apple doc is old (iPod touch iOS 10). Some low-quality blogs claim red, which conflicts. (Medium) — [Apple help (iPod touch)](https://help.apple.com/ipod-touch/10/en.lproj/iphb152a5c6.html), [Macworld](https://www.macworld.com/article/217384/ios_video_capture.html)
- Third-party receivers such as Reflector need the built-in receiver turned off. (Medium) — [AirSquirrels help](https://help.airsquirrels.com/reflector/410-connect-an-iphone-or-ipad-to-reflector-4-on-macos-monterey)
- iPhone Mirroring can't run while the Mac is using AirPlay, so the two routes are mutually exclusive. (High) — [Apple Support](https://support.apple.com/en-us/120421)

### Inferences
- A third-party AirPlay receiver (for example an open-source RPiPlay/UxPlay-style server running on the Mac) would decode frames itself and so avoid the OS capture block. It would still have no control channel, and the blue indicator would remain. I found no source testing this on Tahoe. (Low-medium)
- Mirroring is started from the iPhone's Control Center, so the on-phone app can't start it programmatically. There is no public API to begin screen mirroring.

### Gaps
- Whether mirroring stops when the phone locks.
- The exact iOS 26/27 indicator appearance.
- Measured latency.
- Whether a third-party receiver works with iOS 27.

## USB capture: QuickTime / AVFoundation iOS screen device (CoreMediaIO), and pymobiledevice3 developer services

### Takeaway
A wired connection is the most capture-friendly route.
- **AVFoundation path:** set `kCMIOHardwarePropertyAllowScreenCaptureDevices` = 1. The iPhone then appears as a `.muxed` AVCaptureDevice that streams native-resolution frames over Lightning. There is no input path, and while capturing, the phone's status bar flips to a clean "9:41, full battery". That is a visible change, but it isn't a red dot.
- **pymobiledevice3:** works over USB and also Wi-Fi after USB setup. It exposes DVT screenshots and a newer **DisplayService video stream with VNC/web serving** on iOS 17+. It needs Developer Mode, which is plausible on a Personal-Team phone, but this needs verifying.

### Cited Findings
- To capture over USB, an app opts in by setting the CoreMediaIO property `kCMIOHardwarePropertyAllowScreenCaptureDevices`. The iPhone then appears as an AVCaptureDevice (`AVCaptureDevice.default(for: .muxed)`). Apple's reference page is a stub. (High for the mechanism) — [Apple docs](https://developer.apple.com/documentation/coremediaio/kcmiohardwarepropertyallowscreencapturedevices.md), [Apple dev forum reply](https://origin-devforums.apple.com/forums/profile/GeroTheCoder/replies), [Python ctypes gist](https://gist.github.com/rgov/737a8388747d44f81e5792d89188859f) (notes you "may need QuickTime running to see the devices")
- One developer write-up says native-resolution frames arrive over the cable "without AirPlay or mirroring". The page returned 404 when I fetched it, so only the snippet was seen. (Medium-low) — [dev.to search hit](https://dev.to/apoorvdarshan/your-mac-can-screenshot-a-usb-iphone-apple-just-hides-the-device-5831)
- QuickTime over Lightning: connect the cable, tap Trust, then New Movie Recording and pick the iPhone. Rotating the phone mid-recording can stop QuickTime with an error. The iPhone's own red recording dot does not appear. (Medium) — [MakeUseOf](https://www.makeuseof.com/how-to-record-iphone-screen-with-mac/), [MakeTechEasier](https://maketecheasier.com/record-iphone-screen-with-quicktime)
- Phone-side indicator: during QuickTime capture, iOS swaps in a clean status bar (9:41 AM, full signal and battery, no carrier) **on the device itself**, not only in the Mac window. This has been true since Yosemite in 2014-2015. I found no source confirming it on iOS 26/27. (Medium; old) — [iDownloadBlog](https://www.idownloadblog.com/?p=310951), [Apple Community](https://discussions-jp-prz.apple.com/thread/252580593), [Cult of Mac](https://www.cultofmac.com/news/apple-doesnt-want-posting-messy-ios-screenshots-web-anymore)
- There is an open-source reimplementation of the QuickTime screen-capture USB protocol ("quicktime_video_hack"). (Medium) — [ecosyste.ms listing](https://awesome.ecosyste.ms/projects/github.com%2Fdanielpaulus%2Fquicktime_video_hack)
- A wired iPhone also shows up as a selectable "Display" source in recorder apps such as Tella, which suggests that path isn't affected by the Tahoe AirPlay black-out. (Medium) — [Tella help](https://www.tella.com/docs/help/tips/i-phone-demos-using-screen-mirroring)
- pymobiledevice3 on iOS 17+:
  - Developer and DVT services run over an RSD tunnel that is now built in-process by default, with "no root". (High, primary docs) — [iOS 17+ tunnels guide](https://doronz88.github.io/pymobiledevice3/guides/ios17-tunnels/), [README](https://github.com/doronz88/pymobiledevice3)
  - The userspace tunnel uses USB on iOS 17.4+. For Wi-Fi use, run `lockdown wifi-connections on` once over USB. The userspace stack has lower throughput than kernel tunnels, and `--native` on macOS is faster but less stable. (High) — [tunnels guide](https://doronz88.github.io/pymobiledevice3/guides/ios17-tunnels/)
  - The docs list `display` commands (`serve-web`, `serve-vnc`, `start-video-stream`) over the tunnel. (High) — [tunnels guide](https://doronz88.github.io/pymobiledevice3/guides/ios17-tunnels/)
  - The display stack sits on the **DisplayService** RemoteXPC service, which is a continuous hardware-accelerated video stream, and re-serves frames as VNC (RFB 3.8). (Medium, DeepWiki/AI-generated) — [DeepWiki](https://deepwiki.com/doronz88/pymobiledevice3/4.7-screen-streaming-and-remote-display)
  - In v11.17.0 the command is `pymobiledevice3 developer core-device display serve-vnc`, it binds to 127.0.0.1 by default, and `--bind 0.0.0.0` and `--password` are available. (High) — [release notes](https://newreleases.io/project/github/doronz88/pymobiledevice3/release/v11.17.0)
  - For iOS 17+ screenshots, the reported working command is the DVT variant (`developer dvt screenshot`). The older `developer screenshot` fails on 17+. A mounted Developer Disk Image is needed. I found no per-screenshot speed figures. (Medium) — [skills.cat ios-device-screenshot](https://skills.cat/skills/neversight/skills-feed/ios-device-screenshot)
- Adjacent, outside the Mac scope: Apple's developer docs list a "Capturing screen content on iOS" ScreenCaptureKit sample with iOS 27 availability, streaming via `SCStream`. This could change the on-phone capture picture and should go to the on-phone researcher. (Medium; not read in full) — [Apple docs](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios.md)

### Inferences
- Lightning on the iPhone 13 is USB 2.0. Native-resolution H.264 capture works over it because QuickTime has done this on Lightning devices for years. Expect roughly 30-60 fps with tens of ms of latency, but that number is unmeasured. (Medium)
- DVT single screenshots are typically PNG round-trips, slower than a stream: likely hundreds of ms each. The DisplayService stream or VNC route is the better continuous source. Both are unmeasured. (Low-medium)
- Whether DisplayService/VNC shows any on-phone indicator is unknown. A developer service may show nothing, which would make it the most discreet option, but this must be verified on the device. (Low)
- DisplayService VNC might also accept pointer events, which would give a no-hardware control path while the phone is unlocked. That is unconfirmed and a key thing to test. (Low)
- A free Personal Team doesn't block Developer Mode, which turns on after a dev-signed app is installed from Xcode. DDI mounting is handled by Xcode or pymobiledevice3. Verify on the device. (Medium)

### Gaps
- Measured fps and latency for AVFoundation `.muxed` capture and for DisplayService.
- Whether the iOS 27 status-bar override still happens.
- Whether DisplayService needs a trusted pairing, Developer Mode or a specific iOS build.
- DVT screenshot timing.
- Whether any of these work while the phone is locked.

## Which route shows no red indicator, and which has the best latency

### Takeaway
None of the Mac routes uses iOS's own red screen-recording indicator. Each changes something visible on the phone instead:
- **iPhone Mirroring:** a locked "in use by Mac" state.
- **AirPlay:** a blue status-bar mirroring indicator.
- **QuickTime/AVFoundation USB:** a clean 9:41 status bar.
- **pymobiledevice3 DisplayService/DVT:** possibly nothing, but unverified.

For latency, wired USB (AVFoundation or DisplayService) should be best and most stable. iPhone Mirroring is probably close but flaky on 26.x. AirPlay is the worst and is capture-blocked on Tahoe.

### Cited Findings
- iPhone Mirroring: the iPhone stays locked and "indicates that it's in use and identifies the Mac" — [Apple Support](https://support.apple.com/en-us/120421)
- AirPlay: the blue mirroring indicator — [Apple help](https://help.apple.com/ipod-touch/10/en.lproj/iphb152a5c6.html)
- QuickTime: the red dot is absent and the clean status bar appears on the device — [MakeTechEasier](https://maketecheasier.com/record-iphone-screen-with-quicktime), [Apple Community](https://discussions-jp-prz.apple.com/thread/252580593)
- AirPlay windows black out under capture on Tahoe — [Tella](https://www.tella.com/docs/help/tips/i-phone-demos-using-screen-mirroring)

### Inferences
- Ranking for an agent that needs frames from an unlocked, in-use phone:
  1. USB DisplayService/VNC (pymobiledevice3)
  2. USB AVFoundation `.muxed`
  3. iPhone Mirroring, which only works while the phone is locked, so it is a different mode
  4. AirPlay
  
  (Medium; no latency numbers found for any route, so a stopwatch or glass-to-glass test on the device is needed)

### Gaps
- No published ms-per-frame figures for any route. Measure with a high-speed camera, or by timestamping a frame-counter app.

## How the iPhone app gets results from the Mac, and overall architecture tradeoffs

### Takeaway
The likely architecture is a Mac "eye" daemon that captures frames (USB or Mirroring), runs the vision model, and sends actions back. The actions can go to the ESP32 (which already speaks to the app and the Mac per firmware 0.4.4's Mac discovery), to the iOS app over the local network (Bonjour/Network.framework), or straight into iPhone Mirroring as CGEvents. The main tradeoff is that this route **requires the Mac nearby**, either cabled or Continuity-paired. That cancels the "phone-only" portability, and on campus Wi-Fi local-network peer discovery may be blocked.

### Cited Findings
- pymobiledevice3 can keep developer services working over Wi-Fi after one-time USB setup (`lockdown wifi-connections on`). This allows a cable-free Mac to phone link on the same network. (High) — [tunnels guide](https://doronz88.github.io/pymobiledevice3/guides/ios17-tunnels/)
- The pymobiledevice3 VNC/web servers bind to localhost unless `--bind 0.0.0.0`, which matters if the phone app or another host must reach them. (High) — [release notes](https://newreleases.io/project/github/doronz88/pymobiledevice3/release/v11.17.0)
- iPhone Mirroring sends iPhone notifications to the Mac while connected. That's a privacy side effect, and it could also give the Mac agent notification events. (High) — [Apple Support](https://support.apple.com/en-us/120421)
- Security caution: driving iPhone Mirroring with an agent is "like handing your unlocked phone to the model". (Medium, listing commentary) — [mirroir-mcp search listings](https://glama.ai/mcp/servers/oz8u5abmnx)

### Inferences
- **Option A, Mac-only control:** iPhone Mirroring plus mirroir-mcp-style CGEvents, with no ESP32. This is good for phone-on-desk batch tasks, but it fails when the user holds the phone, can't do Face ID or Control Center, and is fragile on 26.x.
- **Option B, Mac eye with ESP32 hands:** USB or Wi-Fi capture via AVFoundation or DisplayService, ESP32 HID for input, and the phone stays unlocked and usable. The app receives status over Bonjour/TCP or through the ESP32's BLE channel. This keeps the current input stack and replaces only on-phone capture.
- **Option C, hybrid:** on-phone capture when the user is away from the Mac, and the Mac route when it is reachable. The app already has Mac discovery (commit 5661f35), which could advertise a "Mac eye available" flag.
- Results back to the phone: the local-network permission prompt on iOS (NSLocalNetworkUsageDescription) is required for Bonjour. Campus networks with client isolation may break direct Mac to phone TCP. Fallbacks are a Mac hotspot (but iPhone Mirroring then fails, since the Mac can't be sharing internet), a USB tunnel via usbmux, or relaying through the ESP32 over BLE. (Medium)

### Gaps
- No sources on campus or eduroam behavior for Continuity, AirPlay or Bonjour.
- No end-to-end latency data for any loop architecture.
- Unverified whether pymobiledevice3 DisplayService accepts input or shows an on-phone indicator. This is the highest-value on-device test.
