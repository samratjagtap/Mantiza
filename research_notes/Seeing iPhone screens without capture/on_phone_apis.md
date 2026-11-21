# On-iPhone software routes for seeing another app's screen (other than ScreenCaptureKit/ReplayKit sharing and Photos screenshots)

Context: Mantiza is a personal, developer-signed iOS 27 app on an iPhone 13 running iOS 27.2. It drives the phone through an ESP32 acting as a Bluetooth HID mouse and keyboard via AssistiveTouch. State is as of 2026-11-03. Confidence tags: [High] means a primary source or several agreeing sources; [Med] means one secondary or community source; [Low/Unverified] means an inference that needs an on-device test.

## 1. Shortcuts "Take Screenshot" action: output, UX artifacts, triggers, hand-off to an App Intent, latency

### Takeaway
"Take Screenshot" returns the image only inside the shortcut. Nothing reaches Photos unless a Save action follows it, so the image can go straight to an app's App Intent. It does have visible side effects: the screen flashes and a Shortcuts notification banner shows for about 1-2 seconds, with no corner thumbnail. Back Tap, the Action button and AssistiveTouch menu items can all run it while another app is in front. Whether the banner shows up inside the captured image, the real latency, and whether a mouse-only AssistiveTouch trigger works all need testing on the device.

### Cited Findings
- [High] The output stays in the shortcut. On iOS 26, an Action-button shortcut with only "Take Screenshot" made the screen flash, but no image appeared in Photos. Adding a "Save to Photo Album" or "Save File" step after it fixed that (Dec 2025, iPhone 17 Pro Max, iOS 26; 7 "me too" votes). — [Apple Community thread 256213252](https://discussions.apple.com/thread/256213252)
- [Med] A 2022 Apple Community report agrees: a shortcut did nothing visible until "Save to Photo Album" came after "Take Screenshot". — [Apple Community 254390485 (via search summary)](https://discussions.apple.com/thread/254390485)
- [High] Screen flash: the same thread says "the screen flashes" when the action runs from the Action button (iOS 26). — [Apple Community 256213252](https://discussions.apple.com/thread/256213252)
- [Med] No thumbnail, but a banner: a Back Tap shortcut built from Take Screenshot and Save to Photo Album shows no thumbnail preview. The Shortcuts app does show "a notification at the top of the screen… for a second or two", and the article says "there's no way to disable these notifications". The action needs iOS 14.5 or later. This is an iOS 14/15-era article; current behaviour is unconfirmed. — [How-To Geek](https://www.howtogeek.com/720221/how-to-take-a-screenshot-on-iphone-without-a-thumbnail-preview/)
- [Med] Other community guides describe Take Screenshot as user-triggered automation, run from the Shortcuts app, a Home Screen icon, Siri, Back Tap or the Action button. They do not describe it as a silent background capture method. — [MacMyths guide](https://macmyths.com/how-to-automate-screenshots-on-ios/)
- [High] Back Tap (Settings > Accessibility > Touch > Back Tap, double or triple tap) can run a shortcut or take a screenshot, on iPhone 8 or later with iOS 14 or later. — [Apple Support 111772](https://support.apple.com/111772)
- [Med] AssistiveTouch: the custom menu and the Single-Tap, Double-Tap and Long Press custom actions can be assigned a shortcut, because "all your shortcuts are listed at the bottom" of the action list. Apple's own support page lists custom actions but does not explicitly mention shortcuts. — [TidBITS 2022](https://tidbits.com/2022/07/22/use-assistivetouch-for-customizable-shortcuts-on-the-iphone-and-ipad/); [hellouniweb](https://hellouniweb.com/en/columns/assistivetouch/); [Apple Support: Use AssistiveTouch](https://support.apple.com/en-om/guide/iphone/iph96b21954/ios)
- [High] Running an App Intent in the background: since iOS 26, `AppIntent.supportedModes` / `IntentModes` lets an intent declare `.background`, so it can run without the app coming to the foreground. `.background` plus `.foreground(.dynamic)` prefers the background but can escalate to the foreground. Before iOS 26 the equivalent was `openAppWhenRun = false`. — [Apple docs: supportedModes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes.md); [Apple docs: IntentModes](https://developer.apple.com/documentation/appintents/intentmodes.md); [dev.to post on iOS 26 modes](https://dev.to/eliguzz/building-an-open-source-one-sec-alternative-breaking-the-shortcuts-infinite-loop-thanks-to-ios-26-ka4)
- [High] App Intents run in the app's own process, and the developer chooses foreground or background through supportedModes. — [Apple Developer Forums 833681](https://developer.apple.com/forums/thread/833681)
- [Low] One third-party guide says background intents are killed after about 30 seconds. — [capgo app-intents skill (search summary)](https://tanstack.com/intent/registry/%2540capgo%252Fcapgo-skills/capacitor-app-intents)

### Inferences
- The most plausible zero-UI-in-app pipeline is: trigger, then a shortcut ("Take Screenshot" followed by "Mantiza: Ingest Screenshot (IntentFile)" with `supportedModes = .background`), then the app writes to its App Group or sends to the Mac. The image never touches Photos, and Mantiza never comes to the front. [Low/Unverified; build and test]
- Triggers that fit Mantiza:
  - (a) AssistiveTouch custom action or menu item mapped to the shortcut. The ESP32 can open the AssistiveTouch menu and click the item with the mouse. A pointer-device button mapping (AssistiveTouch > Devices > button customisation) should offer the same action list, shortcuts included, so an ESP32 "button 4/5" click could fire it directly. That is plausible but unverified.
  - (b) Back Tap works but needs a physical tap, so it is no use to an autonomous agent.
  - (c) Hardware keyboard: I found no source showing that a Bluetooth keyboard chord can run a user shortcut on iPhone. Full Keyboard Access custom commands may allow it; unverified.
  - (d) Action button: the iPhone 13 has no Action button, so it is not an option on the test phone.
- The flash and banner are artifacts that could land in the captured frame. The flash probably happens at capture time, but whether the "Running shortcut" banner or Dynamic Island pill is composited into the screenshot is unknown. The iPhone 13 has a notch, not a Dynamic Island, so Shortcuts feedback appears as a top banner. Each banner would also be visible to the user on every capture.
- Expect roughly 0.5-2 s per capture: Shortcuts startup, the capture itself, and intent dispatch into Mantiza's process. That is an inference only; I found no measured numbers.

### Gaps
- No source gives a measured latency per capture, or any rate limit on repeated Take Screenshot runs.
- I couldn't confirm whether the Shortcuts banner appears in the image the action returns. Test: run it 10 times over a known screen and check the top 100 px.
- Not verified: whether Shortcuts notifications can now be hidden. Community lore says the Screen Time "Notifications" toggle for Shortcuts does it; I found no source.
- Not verified: whether AssistiveTouch pointer-button customisation lists shortcuts on iOS 27, and whether a run triggered from AssistiveTouch passes the image to an IntentFile parameter without a "Allow Shortcut to share with Mantiza?" privacy prompt. Shortcuts has historically shown per-app data-sharing prompts that you can set to "Always Allow". Unconfirmed for iOS 27.
- No source on whether Take Screenshot works while the screen is locked or when the frontmost app marks content as secure (DRM video, password fields). Assume secure content is blacked out, as with normal screenshots. Unverified.
- I found no open-source iPhone agent that uses the Take Screenshot shortcut in a loop. The nearest projects are on-demand "screenshot to LLM" shortcuts: [Snap2Chat on Gumroad](https://harrycoder0731.gumroad.com/l/pehtn), [Private LLM "Chat with Screenshot"](https://privatellm.app/shortcuts/chat-with-screenshot), and the macOS tool [willprout/Agentic-Screenshot](https://github.com/willprout/Agentic-Screenshot), whose iPhone side uses a share sheet and iCloud Drive. None report automation results.

## 2. Apple Intelligence, on-screen awareness, "Get What's On Screen", Use Model, Siri (iOS 18/26/27)

### Takeaway
None of these give a third-party app another app's screen. Onscreen entities run the other way: an app exposes its own content to Siri or Apple Intelligence, and Siri hands it on only through system flows such as "send this to <app>" with file-schema entities. "Get What's On Screen" returns links or files only from apps that host that content, not pixels. In iOS 27 beta, Siri appears to read the screen from its own automatic screenshot, which apps never receive.

### Cited Findings
- [High] `NSUserActivity.appEntityIdentifier` (iOS 18.2+) links one of the app's own AppEntity values to its activity so Siri and Apple Intelligence can use it. It exposes content and does not receive any. — [Apple docs: appEntityIdentifier](https://developer.apple.com/documentation/foundation/nsuseractivity/appentityidentifier.md); [devicebase summary of Nov 2024 docs update](https://devicebase.net/en/apple-intelligence/updates/make-onscreen-content-available-to-siri-and-apple-intelligence-with-app-intents/5dp)
- [Med] iOS 27 beta 3 (July 2026), from one developer's tests:
  - "Describe this image" and "Create a note for this" used an automatic screenshot. Siri's answers described the app's UI chrome, and the app's `entities(for:)` was never called.
  - The legacy `NSUserActivity.appEntityIdentifier` path was "never consumed".
  - ChatGPT resolved the entity but never ran the Transferable export.
  - The only cross-app transfer that worked was "send this to <contact>/<app>", using the `.files.file` schema, a `FileEntityIdentifier` and a `FileRepresentation`. It needs a real file on disk.
  - Apple DTS pointed to Photos and Messages as reference implementations and logged FB23813341.
  — [Apple Developer Forums 838329](https://developer.apple.com/forums/thread/838329)
- [Med] iOS 27 adds a SwiftUI `.appEntityIdentifier(_:)` modifier and `collectionView(_:appEntityIdentifierForItemAt:)`, both for the app's own views. — [Apple Developer Forums 838329](https://developer.apple.com/forums/thread/838329)
- [Med] WWDC 2026 coverage says Siri in iOS 27 can "read and interpret what's happening on a user's screen in real time, across third-party apps". Apps take part by modelling their actions as App Intents. On-screen awareness needs Apple Intelligence turned on, and Siri AI is delayed in the EU. These are marketing and developer blogs, not Apple primary sources. — [Braze](https://www.braze.com/resources/articles/2026-wwdc-ios-27-updates); [ecorpit](https://ecorpit.com/ios-27-app-intents-siri-ai-developer-guide-2026/); [Superwall](https://superwall.com/blog/3-things-for-developers-from-wwdc-2026)
- [High] "Get What's On Screen" (`is.workflow.actions.getonscreencontent`, iOS 15+) has no input and returns Files: links and files from apps that host on-screen content, such as Safari's URL. On Mac, Safari, Preview and CotEditor returned content, while Finder, Notes, Mail and Terminal returned nothing. — [Matthew Cassinelli](https://matthewcassinelli.com/actions/get-whats-on-screen/); [MacScripter](https://www.macscripter.net/t/the-get-whats-on-screen-shortcut-action/77716); [TechRepublic](https://www.techrepublic.com/article/how-to-create-context-aware-shortcuts-on-ios-15/)
- [High] "Receive What's On Screen" lets a shortcut run from Siri or Back Tap take on-screen items as input. — [Apple Shortcuts User Guide](https://support.apple.com/guide/shortcuts/apd350ce757a/ios)
- [High] Use Model (iOS 26) sends a prompt plus variables to the on-device model, Private Cloud Compute or ChatGPT. I found no source saying it reads the screen by itself. Gallery examples use content passed in, such as an open Safari PDF. — [Matthew Cassinelli iOS 26 actions](https://matthewcassinelli.com/ios-26-public-beta-shortcuts-actions-apple-intelligence-messages-notes-checklists/); [Tom's Guide](https://www.tomsguide.com/phones/iphones/i-used-ios-26-shortcuts-to-build-some-ai-powered-workflows-heres-what-you-can-do-now); [AppleInsider](https://appleinsider.com/articles/25/06/16/apple-says-theres-no-chatbot----but-shortcuts-in-ios-26-says-otherwise)

### Inferences
- You can chain "Take Screenshot" into "Use Model" to get a text description of the screen without Mantiza's own model, then pass that text to Mantiza's intent. The Shortcuts banner cost is the same, plus model latency. Unverified.
- "Get What's On Screen" could serve as a cheap context signal, such as the current Safari URL, alongside a pixel capture. It never gives a full screen view.
- Siri's screen awareness is a closed system feature. A third-party app cannot query it for another app's content.

### Gaps
- I didn't find Apple's WWDC 2026 session pages listing exactly what changed in iOS 27 App Intents or on-screen awareness. The Apple guide URL "making-onscreen-content-available-to-siri-and-apple-intelligence" returned 404 to my fetch.
- No source says whether a "Visual Intelligence on screenshot" result can be exported to Shortcuts or a third-party app on iOS 27.

## 3. Other routes: Live Text, Screen Time, MDM/Classroom, Broadcast Upload Extension, indicators, SCContentSharingPicker consent

### Takeaway
None of these give a third-party app silent access to another app's screen.
- Live Text and Vision only work on images the app already has. They are useful for OCR on Shortcut screenshots.
- Screen Time and DeviceActivity give usage data only, inside a sandboxed report extension that cannot send data out.
- Classroom Screen View is iPad-only and needs supervision.
- On iOS 27, ScreenCaptureKit with SCContentSharingPicker replaces the Broadcast Extension. Background full-display capture needs `UIBackgroundModes: screen-capture`, which App Store Connect now accepts. I found no documented way to avoid the capture indicator.

### Cited Findings
- [High] DeviceActivityReport extensions are sandboxed so they cannot make network requests or move sensitive content outside the extension. App Group writes are denied (seen on iOS 26.4.1), Apple DTS (Quinn) says this is intentional, and developers conclude that no data can leave the extension. The data is per-app usage, not screen content. — [Apple Developer Forums 708444](https://developer.apple.com/forums/thread/708444); [834794](https://developer.apple.com/forums/thread/834794); [729818](https://developer.apple.com/forums/thread/729818); [736351](https://developer.apple.com/forums/thread/736351)
- [Med] Apple Classroom Screen View: the App Store listing requires an iPad on iOS 14.4 or later. Student devices must be supervised, and iPhone is not mentioned. — [App Store: Classroom](https://apps.apple.com/au/app/classroom/id1085319084); [Relution guide PDF](https://www.relution.io/assets/downloads/Managing_Classes_with_Apple_Classroom.pdf)
- [High] SCContentSharingPicker is available on iOS 27.0+. — [Apple docs: SCContentSharingPicker](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker.md)
- [High] Apple's iOS 27 sample (marked preliminary):
  - `present()` offers full-display capture; `presentForCurrentApplication()` limits the picker to the app's own windows.
  - The picker returns an SCContentFilter through an observer callback, and the app starts an SCStream with `.screen` output.
  - The sample declares `UIBackgroundModes` `screen-capture` (so the stream survives backgrounding for full-display capture) and `audio`.
  - Camera overlay works only for in-app capture.
  — [Apple sample: Capturing screen content on iOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios.md)
- [High] Apple engineer, June 2026: from iOS 27, ScreenCaptureKit is used for screen sharing, and SCContentSharingPicker can replace the Broadcast Extension. Frames go to the host app through SCStreamOutput or SCRecordingOutput. The thread title says the Broadcast Extension and ReplayKit are deprecated in iOS 28; that version is not confirmed. — [Apple Developer Forums 831465](https://developer.apple.com/forums/thread/831465)
- [High] Without the `screen-capture` background mode, a backgrounded iOS 27 app's SCStream ends with SCStreamError -3824 (`missingBackgroundMode`). Keeping the app alive with a silent audio engine does not prevent it. App Store Connect at first rejected `screen-capture` as an invalid Info.plist value (FB24169650). DTS said this was resolved, and on 2026-08-21 the poster confirmed the upload rejection was gone. — [Apple Developer Forums 840821](https://developer.apple.com/forums/thread/840821)

### Inferences
- For a developer-signed personal app installed from Xcode, the App Store allowlist issue never applies. Declaring `screen-capture` should let a full-display SCStream keep running while Mantiza is in the background, which is the most reliable continuous frame source.
- Live Text (VisionKit `ImageAnalyzer`) and Vision `RecognizeTextRequest` turn Shortcut screenshots into text and boxes on-device. They need the image first and do not capture anything themselves.
- MDM has no "view the screen" command on iPhone. The only Apple screen-viewing feature is Classroom on supervised iPads, or AirPlay mirroring. Unsourced beyond the Classroom listing.

### Gaps
- I found no source on iOS 27 SCContentSharingPicker consent: whether the picker must appear for every stream or every app launch, or whether the user's choice persists. The docs only show `present()` before each session. On macOS the picker is needed per session. Test whether a stopped and restarted SCStream on iOS 27.2 needs the picker again, and whether a filter can be reused after the app relaunches.
- I found no source on the exact iOS 27 capture indicator (red status-bar pill, Dynamic Island, or Control Center entry) for SCStream, or whether full-display capture can avoid it. Assume it cannot be avoided; it has always shown for ReplayKit broadcasts.
- I found no iOS 27-specific source on whether a Broadcast Upload Extension still works and shows the same indicator as screen recording.
