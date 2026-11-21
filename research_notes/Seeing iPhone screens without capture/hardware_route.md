# Hardware and receiver routes for letting a companion device see the iPhone screen (as of 2026-11-03)

Context: Mantiza is an iOS 27 app plus an M5StickS3 (ESP32-S3) acting as a Bluetooth HID mouse and keyboard through AssistiveTouch. The test phone is an iPhone 13 (Lightning). The question is how a small device (ESP32-S3, Raspberry Pi or similar) could get the screen image without on-phone screen recording, and how that image gets back to the app.

Confidence key: [H] high, [M] medium, [L] low. "TEST" marks something that has to be checked on the bench.

## Q1. Wired video out (Lightning Digital AV Adapter / USB-C) into a capture dongle

### Takeaway
On an iPhone 13, Lightning to HDMI gives a full mirror of the screen, tops out at 1080p and carries compression lag from the adapter's internal decoder. A UVC HDMI dongle (MS2109/MS2130) into a Pi Zero 2 W, Pi 4/5 or Mac can grab that signal, with roughly 100–350 ms of local capture latency on Linux. An ESP32-S3 can't realistically take a UVC HDMI dongle because its USB host is Full Speed only. DRM apps refuse playback or go black, but ordinary UI should mirror. This works and needs no network, but it's bulky: adapter, HDMI cable, dongle and a Pi.

### Cited Findings
- Apple: to connect to a display you need an adapter matching your connector (USB-C, Lightning, 30-pin). The Digital AV (HDMI) adapter carries audio. Movies, TV shows and some streaming apps require HDCP, and on a non-HDCP connection playback shows an alert asking for an HDCP-compliant device. The page says nothing about charging pass-through or resolution. [H] — [Apple Support HT202044](https://support.apple.com/en-us/HT202044)
- Retail listings put the Lightning Digital AV adapter's mirroring at up to 1080p. [M, retail listing, not Apple] — [Lightning Digital AV Adapter listing (ibluetech)](https://ibluetech.ca/en/product/lightning-digital-av-adapter)
- How the Lightning AV adapter works (2013 teardown reporting, OLDER): it contains an ARM SoC. The phone encodes its screen output on the fly and sends it over Lightning, and the adapter decodes it to HDMI. AirPlay is not involved. Engadget reported that the scheme "introduces lag and compression artifacts" and that the SoC's H.264 level limits resolution. [M, old] — [Engadget 2013](https://www.engadget.com/2013/03/04/heres-how-apples-lightning-to-hdmi-digital-av-adapter-probably/); [AppleInsider 2013](https://appleinsider.com/articles/13/03/04/apple-av-adapters-embedded-arm-chip-reportedly-used-for-future-proofing-not-airplay-decoding)
- Reliability on iPhone 13 is mixed in Apple Community threads: some adapters give a black screen, some mirror briefly and then drop, and old adapters sometimes fail with newer phones. [L–M, anecdotal] — [Apple Community 255028142](https://discussions.apple.com/thread/255028142); [Apple Community 254703017](https://discussions.apple.com/thread/254703017?page=2)
- A working chain has been reported: iPhone 13 mini, Lightning-HDMI, Elgato HD60 X capture, OBS. The poster's complaint was audio latency. [M] — [r/rhythmgames](https://lr.sudovanilla.org/r/rhythmgames/comments/1gjbt3p/sound_latency_while_streaming_mobile_rhythm_games)
- HDCP-capable capture can break after iOS updates. One user's HDCP 2.2 capture card stopped being detected through the Apple Lightning adapter after updating from iOS 17 to 18.1.1. [L, single report] — [Apple Community 255865765](https://discussions.apple.com/thread/255865765)
- DRM behavior changed in iOS 26. Disney+ through the Lightning to HDMI adapter now shows an HDCP error where it used to show a black screen. [L–M, single report] — [Apple Community 256138707](https://discussions-kr-prz.apple.com/thread/256138707)
- USB-C iPhones (iPhone 15 and later) support DisplayPort output up to 4K HDR mirroring, and Apple's USB-C Digital AV Multiport Adapter outputs up to 4K60 HDMI. Sources disagree on whether that adapter passes HDR. Base iPhone 15/15 Plus are USB 2 and the Pros are USB 3. Apple says high-resolution displays need a USB 3.1+ cable. [H for 4K out; M for the details] — [MacRumors 2023](https://www.macrumors.com/2023/09/13/all-iphone-15-models-support-displayport/); [9to5Mac 2023](https://9to5mac.com/2023/09/16/iphone-15-usb-c-external-displays/)
- Capture dongles: MS2109 is USB 2.0, up to 1080p30 MJPEG, and enumerates as a standard UVC webcam (534d:2109) with uvcvideo on Linux. MS2130 is USB 3.0, up to 1080p60 YUV. One forum user says the MS2130 does not bypass HDCP and the MS2109 does. [M, forum claims] — [VideoHelp forum](https://forum.videohelp.com/showthread.php?p=2693474); [diyAudio](https://www.diyaudio.com/community/posts/6288806); [CNX Software 2020 roundup of MS2109 dongles (OLDER)](https://www.cnx-software.com/2020/06/05/11-hdmi-to-usb-2-0-video-capture-dongle-supports-up-to-1080p30-grabbing/)
- Measured latency on Linux with an MS2109-class device: uncompressed via ffplay was about 220–350 ms, MJPEG via xawtv about 100–120 ms locally, and network streaming ranged from about 120 ms (ustreamer to Firefox) to about 700 ms end to end. [M, one hobbyist's measurements] — [fluxcoil wiki](https://fluxcoil.net/wiki/hardwarerelated/camlink_hdmi_converter)
- The MS2130S vendor can't measure absolute latency. It reports about 20–50 ms more than an AVerMedia BU113 at 1080p, and notes RGB UVC output is currently flipped. [L, vendor] — [qdm.tw MS2130S](https://livestream.qdm.tw/MS2130S-4K30-capture-card)
- Lower-latency Pi option: a TC358743 HDMI-to-CSI bridge, the PiKVM approach, roughly halves latency compared with USB capture according to the PiKVM author. ustreamer with the kernel driver gives about 100–130 ms over gigabit Ethernet. The boards work with Pi 3B+, 4B and 5. [M] — [Hackaday on PiKVM/TC358743](https://hackaday.com/tag/perboard/); [fluxcoil TC358743 on Pi 4](https://fluxcoil.net/wiki/hardwarerelated/raspberry_pi_4_tc358743); [Geekworm LCKVM HDMI-to-CSI](https://geekworm.com/en-au/products/lckvm-hdmi-to-csi)
- ESP32-S3 as a UVC host: its USB peripheral is Full Speed only (512-byte max packet, about 0.5 MB/s isochronous and about 1.1 MB/s bulk). Espressif's usb_host_uvc lists 320x240@30 and 640x480@15 MJPEG as the common modes, and techpedia lists tested modes of 800x480@15 (bulk) and 480x320@15 (isoc). [H] — [Espressif usb_host_uvc](https://components.espressif.com/components/espressif/usb_host_uvc/versions/1.0.2~1/readme); [Espressif techpedia USB camera](https://docs.espressif.com/projects/esp-techpedia/zh_CN/latest/esp-friends/solution-introduction/camera/usb-camera-solution.html)

### Inferences
- Whole-screen mirror: the Lightning adapter mirrors whatever is on screen, the same as AirPlay mirroring, without any app being involved. That makes it a "capture without on-phone recording" route. Confidence [M]. It's likely, but no source here says explicitly that system UI such as the lock screen, passcode or Apple Pay sheet appears over HDMI. TEST.
- Indicator: I found no source describing an on-phone indicator for wired HDMI mirroring. Based on prior experience (unsourced), there's no status-bar pill as there is for screen recording. TEST on the iPhone 13 with iOS 27.2.
- HDCP: DRM video apps (Netflix, Disney+, Apple TV) will show an error or go black. That doesn't matter for an agent driving UI. If the iPhone only turns on HDCP for protected content, which is how most reports read, ordinary UI shouldn't be blocked by an MS2109/MS2130 dongle. [M] TEST, especially since one report says HDCP 2.2 capture devices failed detection after iOS 18.1.1.
- ESP32-S3 (M5StickS3) taking a UVC HDMI dongle directly: very unlikely. MS2109/MS2130 are High-Speed/SuperSpeed devices with 720p/1080p MJPEG modes. Even if one enumerated at Full Speed, 1080p MJPEG at about 1 MB/s would mean a few fps at best. Whether an MS2109 exposes sub-VGA modes or works on a Full Speed host is unknown. [M] TEST if anyone insists, but plan on a Pi.
- Realistic wired rig: iPhone 13, Apple Lightning Digital AV adapter, short HDMI, an MS2109 dongle, then a Pi Zero 2 W (USB 2 OTG, 512 MB). The Pi grabs MJPEG, downsizes it, and sends JPEGs or crops back to the app over Wi-Fi/TCP, or to the Mac. Expect about 150–400 ms glass-to-app. Plugging the dongle straight into a Mac (UVC appears as a camera) is the easiest desk setup.
- Charging and HID: the adapter takes the iPhone 13's only Lightning port, so charging has to go through the adapter's pass-through Lightning port. Retail listings advertise one, but Apple's support page above doesn't mention it. TEST whether the adapter can power the phone and dongle reliably. Bluetooth HID through AssistiveTouch shouldn't be affected because it's a separate radio path (inference [M]). A wired USB HID approach like the onehumanbeing repo's can't share the port on Lightning. On USB-C iPhones a hub might allow both. TEST.
- Approximate cost (unsourced prices from memory, verify): Apple Lightning Digital AV adapter about $49, MS2109 dongle about $10–20, Pi Zero 2 W about $15 plus SD card and power, so roughly $80–100 in total. Cheap third-party Lightning-HDMI adapters exist, but reports call them hit-or-miss.
- Pocket fit: poor to fair. It's four pieces plus cables, and the phone is tethered. It's best suited to a desk or demo rig, or as a "ground-truth" capture path for training data.

### Gaps
- No Apple primary source found for the Lightning Digital AV adapter's charging port or resolution (the Apple Store product URL returned 404).
- No measured glass-to-glass latency for the Lightning adapter itself. The only evidence is 2013 reporting that it adds lag and artifacts.
- No source confirms which iOS system screens (passcode, Apple Pay, Face ID prompts) are blanked over wired HDMI.
- No source on whether wired mirroring on iOS 26/27 shows any indicator.
- No measurements of MS2109 or MS2130 on a Pi Zero 2 W specifically.

## Q2. AirPlay mirroring receivers on small devices (UxPlay, RPiPlay, ESP32)

### Takeaway
UxPlay (GPL-3.0) is the maintained open-source AirPlay mirror receiver. It runs on Pi Zero 2 W, 3B+, 4B and 5, with hardware H.264 decode on Pi 4B and earlier. iOS 27 mostly works with it: the maintainer reports iPadOS 27 beta working and another tester got frames with `-h265`, but one iOS 27 failure (issue #535) is still open and unconfirmed. Apple has never guaranteed the "legacy" mirroring protocol that UxPlay relies on, so an iOS update could break it. An ESP32-S3 receiver is feasible as a pass-through that never decodes, as onehumanbeing/esp32-iphone-agent shows, but it's low resolution, low fps and takes over the phone's Wi-Fi.

### Cited Findings
- UxPlay: latest release v1.74 (experimental, June 2026), previous series v1.73.x (March 2026). It supports AirPlay mirroring through Apple's "Legacy Protocol". The README names iOS 17 as still supporting it and warns there's "no guarantee that future iOS releases will keep supporting" it. Clients need iOS 9.3.5 or later. License GPL-3.0. [H] — [FDH2/UxPlay README](https://github.com/FDH2/UxPlay)
- UxPlay on Pi: tested on Zero 2 W, 3B+, 4B and 5. Pi 4B and earlier get hardware H.264 decode through bcm2835-codec. Pi 5 has no hardware H.264 decode and relies on its CPU for software decode. Hardware H.265 on Pi 4B/5 isn't working yet. Low-power models may drop frames when timestamp sync is on. `-vsync no` is suggested for live use. [H] — [FDH2/UxPlay README](https://github.com/FDH2/UxPlay)
- Software H.264 decode on a Pi "usually has unacceptable latency". Use GPU decode. [M, README mirror] — [UxPlay mirror README](https://github.com/antimof/Uxplay)
- UxPlay can't show Apple video-DRM content (Apple TV app) in mirror mode. [H] — [FDH2/UxPlay README](https://github.com/FDH2/UxPlay)
- iOS 27 compatibility, issue #535 (opened 2026-07-15, still open): on iPhone16,2 running iOS 27.0, mirroring negotiates but the client never opens the data connection. On 2026-08-01 a tester with iPhone 15 Pro, iOS 27 beta and UxPlay 1.74 on Windows got frames after adding `-h265`, so iOS 27 can send HEVC. On 2026-08-29 the maintainer had iPadOS 27 beta 5 working. On 2026-09-16 the maintainer said it was "(probably?) fixed" by later iOS and wlroots updates. [H for the thread contents; M for the iOS 27 status] — [FDH2/UxPlay #535](https://github.com/FDH2/UxPlay/issues/535)
- iOS 26.6.2 mirroring to the uxplay-windows fork works for video and media audio. System sounds are missing (opened 2026-10-22). [M] — [leapbtw/uxplay-windows #64](https://github.com/leapbtw/uxplay-windows/issues/64)
- Discovery depends on mDNS/DNS-SD (avahi). If the receiver doesn't appear in Screen Mirroring, check avahi. [H] — [FDH2/UxPlay](https://github.com/fdh2/uxplay)
- Phone-side UX (Apple): the phone must be on the same Wi-Fi as the receiver. You open Control Center, tap Screen Mirroring, pick the receiver and may need to enter a passcode. To stop, use Control Center and then Stop Mirroring. Apple's page doesn't describe an indicator. [H] — [Apple Support 102661](https://support.apple.com/en-us/102661)
- No reliable measured UxPlay-on-Pi mirror latency was found. One alibaba.com page claims 192 ms on Pi 5, but it describes shairport-sync (audio-only) and looks unreliable. Not used. [—] — [lifetips.alibaba.com](https://lifetips.alibaba.com/tech-efficiency/add-airplay-mirroring-to-any-tv-with-a-raspberry-pi)
- onehumanbeing/esp32-iphone-agent (described only, no code copied): it runs on a XIAO ESP32-S3 with 8 MB PSRAM (about $7) and needs an iPhone on iOS 18+. The board creates its own Wi-Fi hotspot and advertises itself as "ESP32 Agent" in Screen Mirroring. It passes the H.264 stream through without decoding it and forwards it over BLE to the iPhone app, which does the decoding. Resolution is 480×1040 at ≤5 fps because BLE carries about 300–500 kbps. The receiver code in `hardware/hid_bridge/src/airplay/` is ported from UxPlay and is GPL-3.0, so the firmware binary that links it is GPL-3.0. The rest of the repo is MIT and skills/ is MIT-0. HID is wired USB mouse/keyboard with AssistiveTouch. Stated limits: iOS doesn't mirror passcode entry, Apple Pay or DRM video. Mirroring stops when the phone locks. The phone's Wi-Fi is taken by the board's hotspot, so the model is reached over cellular. The app uses the private `suspend` API, so it isn't App Store safe. [H, the project's own README] — [onehumanbeing/esp32-iphone-agent](https://github.com/onehumanbeing/esp32-iphone-agent)

### Inferences
- RPiPlay and shairplay: not researched separately. RPiPlay was the Pi-focused predecessor and UxPlay is where active development happens, so treat RPiPlay as stale. Confidence [M], unsourced in this pass. shairport-sync is audio-only and doesn't help here.
- Indicator: AirPlay mirroring shows as active in Control Center, and to my knowledge a mirroring icon or status indicator appears while it's running (unsourced, TEST on iOS 27.2). The visible cost is the Control Center step to start it and a possible passcode. The session also ends on lock, per onehumanbeing.
- A useful property: iOS itself blanks secure screens (passcode, Apple Pay) in AirPlay mirroring, per onehumanbeing. That works as a privacy feature, but the agent goes blind on those screens.
- Fit for Mantiza on the M5StickS3: copying the onehumanbeing pass-through design is technically feasible on ESP32-S3 with PSRAM. Using its UxPlay-derived code would put the stick firmware under GPL-3.0, so a clean-room implementation would be needed to avoid that. The stick's BLE link is already used for HID, so pushing about 300–500 kbps of video over the same radio would compete with it (TEST). Joining the stick's hotspot also takes the phone off normal Wi-Fi. A Pi Zero 2 W running UxPlay on the home or Mac network avoids the hotspot problem, but it needs hardware decode, and its 2.4 GHz Wi-Fi limits bandwidth.
- Latency estimate (unsourced, TEST): AirPlay mirroring usually adds a few hundred ms. Hardware decode on Pi 4 or a Mac is probably 100–300 ms. The ESP32 BLE relay at ≤5 fps likely means 200 ms to 1 s+ per frame.
- Reliability risk: high over the long term. The protocol is reverse-engineered and Apple explicitly doesn't guarantee it, and iOS 27 already needed `-h265` and fixes. Pin a UxPlay version and retest after each iOS point release.
- Power: a Pi Zero 2 W running Wi-Fi plus decode is battery-pack class, so it isn't pocket-trivial. The ESP32-S3 is small enough for a pocket device.

### Gaps
- No measured latency for UxPlay on Pi or Mac with iOS 26 or 27.
- Unconfirmed whether issue #535 is resolved for iPhone (as opposed to iPad) on iOS 27.x, or whether iOS 27.1 or 27.2 changed anything. TEST on the iPhone 13 with iOS 27.2 and UxPlay 1.74 using `-h265` (note that an iPhone 13 may send H.264 rather than HEVC).
- Exact iOS 27 on-phone indicator while AirPlay mirroring is not documented by Apple.
- Pi Zero 2 W frame rate and latency at full iPhone 13 resolution are unknown.

## Q3. Miracast / Chromecast

### Takeaway
The iPhone doesn't support Miracast or Chromecast screen mirroring natively. AirPlay is the only built-in wireless mirroring protocol. Third-party "mirror" apps exist, but they rely on in-app ReplayKit capture, which is the on-phone recording this research is trying to avoid.

### Cited Findings
- Apple devices don't implement Miracast, and AirPlay is the iPhone's built-in mirroring technology. [M, consistent across secondary sources, no Apple or Google primary] — [AirDroid](https://airdroid.com/screen-mirror/iphone-miracast); [Apeaksoft](https://www.apeaksoft.com/screen-mirroring/miracast-iphone.html)
- Chromecast doesn't support AirPlay. Google Home has no screen mirroring feature on iPhone, so third-party apps such as DoCast are needed. [M] — [Alphr](https://www.alphr.com/mirror-iphone-with-chromecast)

### Inferences
- Third-party Miracast and Chromecast apps on iOS use a ReplayKit broadcast extension, which is effectively screen recording with the red or status pill. That rules them out for this question. [M, unsourced in this pass]

### Gaps
- No Apple primary statement found. The sources are marketing and tech blogs.

## Q4. Comparison: indicators/UX, latency, reliability, cost, pocket fit

### Takeaway
For the iPhone 13: (1) Wired Lightning HDMI to a UVC dongle to a Pi or Mac is the most deterministic option, needs no network and works offline, but it's bulky and occupies the port. (2) UxPlay on a Pi or Mac is the easiest wireless option, but it needs the Control Center step, ends on lock, and the protocol is fragile. (3) An ESP32 AirPlay pass-through like onehumanbeing's is the most pocketable, but it's low fps, takes the phone's Wi-Fi and brings GPL-3.0 if reused. Miracast and Chromecast aren't options.

### Cited Findings
- See the per-route citations above. The key numbers: about 100–350 ms local MJPEG/uncompressed capture on Linux ([fluxcoil](https://fluxcoil.net/wiki/hardwarerelated/camlink_hdmi_converter)), about 100–130 ms with TC358743 and ustreamer ([fluxcoil TC358743](https://fluxcoil.net/wiki/hardwarerelated/raspberry_pi_4_tc358743)), and 480×1040 at ≤5 fps for the ESP32 BLE relay ([onehumanbeing](https://github.com/onehumanbeing/esp32-iphone-agent)).

### Inferences
| Route | Phone indicator / UX cost | Latency (est.) | Reliability | Cost (est., unverified) | Pocket fit |
|---|---|---|---|---|---|
| Lightning AV adapter, MS2109, Pi Zero 2 W | Probably no indicator (TEST). Port occupied. Charge via pass-through | ~150–400 ms | Medium: adapter flakiness reports, HDCP only on DRM | ~$80–100 | Poor/fair |
| Same into Mac (UVC) | Same | ~100–250 ms | Medium | ~$60–70 | Desk only |
| USB-C iPhone, DP/HDMI, capture | Same. Up to 4K | lower (no Lightning re-encode) | Medium-high | similar | Fair |
| UxPlay on Pi 4/Mac (AirPlay) | Control Center start, possible passcode, stops on lock | ~100–300 ms (TEST) | Medium-low long-term (legacy protocol, iOS 27 hiccups) | Pi 4 ~$35–55 or $0 on Mac | Fair (Pi plus battery) |
| ESP32-S3 AirPlay pass-through over BLE | Same as AirPlay, plus phone Wi-Fi taken by hotspot | 200 ms–1 s+, ≤5 fps | Low-medium. GPL if code reused | ~$7–20 | Good |
| Miracast/Chromecast | n/a, not native | n/a | n/a | n/a | n/a |

- Recommendation to test first: (a) UxPlay 1.74 on the Mac with the iPhone 13 on iOS 27.2 (zero hardware cost), to confirm iOS 27 mirroring and measure latency. (b) An Apple Lightning AV adapter and an MS2109 dongle on the Mac, to check the HDMI indicator, which screens are blanked, charging pass-through and BLE HID coexistence. Only then decide whether a Pi or ESP32 receiver is worth building.

### Gaps
- All prices are unverified estimates from memory and need checking against current listings.
- No head-to-head latency data exists in the sources. Every latency figure above is either a cited hobbyist measurement for capture only or an estimate.
