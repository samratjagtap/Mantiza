# What Mantiza can do on iOS without AI (research, 2026-11-07)

Question: how much can Mantiza do directly through iOS (keys, links, Apple frameworks, Shortcuts, Siri)
without looking at the screen, and for which tasks?

Every finding is marked by how sure it is:

- **[Apple]** Apple's own documentation (developer docs, Accessory Design Guidelines, Support guides)
- **[Maker]** documented by the app's maker (WhatsApp, Google, Telegram)
- **[Reports]** community reports only, not documented
- **[Check]** not settled by any source: needs a one-minute check on the iPhone 14 Plus (iOS 27)

## The short answer

1. **iOS does not let an app change system settings directly.** Wi-Fi, Bluetooth, Airplane Mode, Focus,
   Dark Mode and so on can only be changed in four ways: keys from the device, an Apple Shortcut, Siri, or
   taps in Control Centre or Settings. There is no fifth way.
2. **The device can do a lot more with keys than we use today.** Apple officially lists special keys for
   Home, Lock, Screenshot, brightness, volume, mute, play/pause/next/previous, **Siri**, Spotlight,
   on-screen keyboard and **Focus (Do Not Disturb)** **[Apple]**. Our firmware sends none of them yet (only
   normal keyboard keys), and that's cheap to fix.
3. **Mantiza can jump straight into the right place in many apps with links.** Examples: a WhatsApp chat
   with the message already typed, a phone call, Maps directions, an email draft. A tap on Send or Call is
   usually still needed, and the device can do it.
4. **Some things Mantiza can do itself, with no other app:** alarms and timers (AlarmKit, iOS 26+),
   calendar events and reminders, screen brightness, Apple Music playback, and pasting any text,
   including Hindi and emoji.
5. **Your iPhone 14 Plus gets no Siri AI.** Siri AI needs iPhone 15 Pro or newer and is still beta,
   English only **[Apple]**. The old Siri still works.
6. **Links only work while Mantiza is on screen.** Opening a link brings the other app to the front
   **[Apple]**, and opening one from the background is unreliable **[Reports]**. So the direct step
   happens at the start of a task, when Mantiza is on screen, before it hands over to the other app.

---

## A. Device keys (the StickS3 as a keyboard)

### A1. Special keys Apple supports
These come from Apple's *Accessory Design Guidelines*, Release R32 Update 1 (2026-10-30), Tables
14-3 and 14-4 **[Apple]**. They are "consumer" keys, a separate HID report from normal keys:

| Key | HID usage | What it gives Mantiza |
|---|---|---|
| Home Button | Consumer 0x0040 (Menu) | Home Screen in one key press. Better than ⌘H (see A2) |
| Lock | Consumer 0x0030 (Power) | Locks the phone. This also ends screen sharing, so only use it as a last step |
| Screenshot | Consumer 0x0065 (Snapshot) | Takes a screenshot |
| Brighter / Dimmer | Consumer 0x006F / 0x0070 | Screen brightness up and down |
| Louder / Softer / Mute | Consumer 0x00E9 / 0x00EA / 0x00E2 | Volume up, down, mute |
| Play/Pause, Next, Previous | Consumer 0x00CD / 0x00B5 / 0x00B6 | Media control in any app that plays audio |
| **Siri** | Consumer 0x00CF (Voice Command) | Starts Siri (see section E) |
| Spotlight | Consumer 0x0221 (AC Search) | Opens Search, like ⌘Space |
| Toggle on-screen keyboard | Consumer 0x01AE | Shows or hides the on-screen keyboard |
| Globe | Consumer 0x029D | The Globe key |
| **Focus (Do Not Disturb)** | Generic Desktop 0x009B | Toggles Focus on or off |

**What we need to build:** a consumer-control report in the firmware's report map. Changing the map
means re-pairing once. Watch the report IDs: with report IDs declared, iOS ignores any report sent
without one **[Reports]**. The closest existing project, jinwon-int/esp32-iphone-agent
([README](https://github.com/jinwon-int/esp32-iphone-agent)), already sends Home 0x0040, Spotlight
0x0221, Globe 0x029D and keyboard 0x01AE over BLE.

**Policy note:** the same guidelines forbid *certified* keyboards from sending key combinations or
timed sequences on their own **[Apple]**. That only matters if Mantiza ever applies for Apple's MFi
certification. It doesn't block what we do now.

### A2. Key combinations
| Combo | Status |
|---|---|
| ⌘Space then type the app name, then Enter | Works today. This is how Mantiza opens apps |
| ⌘H (Home) | jinwon-int reports that **on iOS 27, ⌘H does not reach the Home Screen** **[Reports]**. We send it at the start of every task. **[Check]**: replace it with the Home key 0x0040 |
| Fn/Globe + C (Control Centre), + N (Notification Centre), + H (Home), + ↑ (App Switcher) | Apple lists these for Full Keyboard Access (Settings → Accessibility → Keyboards & Typing → Full Keyboard Access) **[Apple]**, and they work on iPad without it. **[Check]** whether they work on iPhone without Full Keyboard Access. If they do, Control Centre opens without the swipe |
| Holding ⌘ in an app | Shows that app's own shortcut list **[Apple]**. Useful for apps that have shortcuts |

---

## B. Links Mantiza opens (start of a task, while Mantiza is on screen)

| Task | Link | Sure? | What is still left |
|---|---|---|---|
| Phone call | `tel:+91…` | [Apple] | iOS asks "Call …?" before dialling (since iOS 10.3) **[Reports]**. The device taps Call |
| FaceTime | `facetime:` / `facetime-audio:` | [Apple] | Same confirmation, then the device taps |
| SMS / iMessage | `sms:+91…` | [Apple] | Apple's docs allow only the number, no text. `&body=` for the text is widely used but undocumented **[Reports]**. Or show Apple's message sheet inside Mantiza (MFMessageComposeViewController) with the text filled in **[Apple]**. The device taps Send |
| **WhatsApp message** | `https://wa.me/<number>?text=<text>` (full international number, digits only) | [Maker] | Opens the chat with the text in the message box. The device taps Send. With a hardware keyboard, Return may send **[Reports]**; **[Check]** |
| Telegram | `tg://resolve?domain=<user>&text=<draft>` or `?phone=<number>&text=` | [Maker] | The device taps Send |
| Email | `mailto:a@b.com?subject=…&body=…` | [Apple] | The device taps Send |
| Apple Maps directions | `https://maps.apple.com/directions?destination=<place>&mode=driving` (also `walking`, `transit`, `cycling`; `waypoint=` for stops). Needs iOS 18.4+ | [Apple] | Nothing, or a tap on Go |
| Google Maps directions | `comgooglemaps://?daddr=<place>&directionsmode=driving`, or `https://www.google.com/maps/dir/?api=1&destination=…` | [Maker] | Nothing, or a tap on Start |
| Run an Apple Shortcut | `shortcuts://run-shortcut?name=<name>&input=text&text=<value>`, plus `x-success=` to come back | [Apple] | See section D |
| Mantiza's own Settings page | `UIApplication.openSettingsURLString` | [Apple] | That's the only documented Settings link |
| Any other Settings page | `App-Prefs:…` / `prefs:…` | Undocumented, "private API" per Apple staff, App Review risk | Don't rely on it. Use Control Centre, Shortcuts or AI |
| Clock alarms/timers | `clock-alarm://` etc. | [Reports]: opens Clock but doesn't work | Use AlarmKit (C1) |
| YouTube / Spotify search | web links like `youtube.com/results?search_query=…`, `open.spotify.com/search/…` open the app if installed | [Reports] | Picking the right result needs the screen |

**Turning "Azad" into a number:** Mantiza reads Contacts (Contacts framework, one permission)
**[Apple]**. Since iOS 18 the person can give access to only some contacts, so Mantiza must handle
"not found".

---

## C. Things Mantiza can do itself (Apple frameworks, no other app)

| Task | API | Sure? | Notes |
|---|---|---|---|
| **Alarm / timer** | AlarmKit (iOS 26+) | [Apple] | One permission. One-time, weekly and countdown alarms. They ring through Focus and silent mode. They are Mantiza's own alarms, not entries in the Clock app |
| Calendar event | EventKit (write-only access is enough) | [Apple] | One permission |
| Reminder | EventKit (full access to Reminders) | [Apple] | One permission |
| **Screen brightness** | `UIScreen.main.brightness = 0…1` | [Apple] | Stays until the phone locks, even after Mantiza closes |
| Music | `MPMusicPlayerController.systemMusicPlayer` (controls the Music app), MusicKit catalog search | [Apple] | Playing from the catalog needs an Apple Music subscription |
| Join a specific Wi-Fi network | NEHotspotConfigurationManager | [Apple] | iOS asks the person. Needs the Hotspot Configuration capability. It can't turn Wi-Fi on or off |
| **Type any text, including Hindi and emoji** | Put the text on the clipboard (UIPasteboard), then the device presses ⌘V | [Apple] for the clipboard; ⌘V is a normal key | Fixes our "US keyboard letters only" limit. Restore the old clipboard afterwards |
| Flashlight | `AVCaptureDevice` torch | [Apple] for the API | Reports say iOS turns the torch off when the app goes to the background **[Reports]**. **[Check]** whether it stays on |
| Read the phone's state | flashlight, Low Power Mode, Dark Mode | [Apple] | Already built (PhoneState). iOS doesn't report Wi-Fi, Bluetooth or Airplane Mode on/off |

---

## D. Apple Shortcuts (for system switches)

The Shortcuts app has ready-made actions for almost every switch: Set Flashlight, Set Wi-Fi, Set
Bluetooth, Set Airplane Mode, Set Cellular Data, Set Personal Hotspot, Set Low Power Mode, Set Appearance
(Dark Mode), Set Orientation Lock, Set Brightness, Set Volume, Set Focus, Set Silent Mode, Set True Tone,
Set Night Shift, Set AirDrop Receiving, Set VPN, Lock Screen, Show Control Center, Go to Home Screen,
Open App, Take Screenshot, plus Clock (Create Alarm, Start Timer) and Send Message
([MacNative list](https://macnative.com/list-of-default-control-actions-for-ios-shortcuts/))
**[Reports]**. Apple's own action reference wasn't fetched.

How Mantiza would use them:
- **One "Mantiza" shortcut** that takes a word like `flashlight on` and runs the matching action. Mantiza
  runs it with `shortcuts://run-shortcut?name=Mantiza&input=text&text=flashlight%20on` **[Apple]**.
- **Installing it:** iOS 15 replaced the full action list with a simple preview when someone opens an
  iCloud link to a shortcut. Adding it is one "Add Shortcut" tap
  ([MacStories](https://www.macstories.net/stories/ios-and-ipados-15-the-macstories-review/12/)), and the
  device can do that tap, so the user does nothing. The shortcut has to be built and shared once from an
  Apple device (by us, not by each user). **[Check]** the flow on iOS 27.
- **Costs:** the Shortcuts app comes to the front for a moment. The first time some actions run, iOS asks
  "Allow once / Always allow", and the device can tap it. Shortcuts' WhatsApp "Send Message" is flaky and
  sometimes waits for a confirmation **[Reports]**, so use the wa.me link for WhatsApp.
- **Never run "Bluetooth off"**: it disconnects the device in the middle of the task.

---

## E. Siri

- **Starting Siri:** the device's Siri key (Consumer 0x00CF) **[Apple]**. AssistiveTouch's menu also has
  Siri.
- **Typing to Siri** needs Settings → Accessibility → Siri → **Type to Siri** on. That's one setup step.
  With it on, Siri opens a text box, the device types the request, then presses Enter. **[Check]** that
  the Siri key opens that text box.
- **Old Siri (your phone)** can switch Wi-Fi, Bluetooth, Do Not Disturb, Low Power Mode and Airplane Mode,
  and can set alarms and timers, make calls and send messages **[Reports]**. Turning Wi-Fi or Airplane
  Mode back on through Siri can fail without internet **[Reports]**.
- **Siri AI (iOS 27, iPhone 15 Pro and newer, beta, English):** works with on-screen content and does
  actions in apps through App Intents **[Apple]**. More apps get it in iOS 27.3, expected around early
  December **[Reports]**. On those phones, a typed Siri request may replace many AI steps. Not on your
  14 Plus.
- Apps can't call Siri, or other apps' App Intents, from code. The only routes are the key, AssistiveTouch
  or Shortcuts.

---

## F. What still needs the AI (the screen)

- Anything inside an app past where a link lands: choosing a restaurant, a product, a search result, a
  photo, a post.
- Settings pages other than Mantiza's own, unless a Shortcut action covers them.
- Checking the result where iOS doesn't report it: Wi-Fi, Bluetooth, Airplane Mode, and whether a message
  was really sent.
- Apps with no links and no Shortcuts actions.

Even then, the direct step shortens the AI's job. For example, WhatsApp opens on the right chat with the
text already in the box, so the AI only has to tap Send.

---

## G. Recommended route per task

| Task | Fastest route without AI | Fallback |
|---|---|---|
| Open any app | Spotlight key or ⌘Space, the name, Enter (today) | — |
| Go Home | Home key 0x0040 | AssistiveTouch → Home |
| Volume, mute, play/pause, next track | Consumer keys | — |
| Brightness | `UIScreen.brightness` (exact value) or brightness keys | — |
| Do Not Disturb / Focus | Generic Desktop 0x009B, or Shortcut "Set Focus" | Control Centre with AI |
| Screenshot | Consumer 0x0065 | — |
| Lock the phone (only as the last step) | Consumer 0x0030 | — |
| Alarm, timer | AlarmKit | Clock app with AI |
| Calendar event, reminder | EventKit | — |
| Call someone | Contacts → `tel:` → the device taps Call | AI |
| WhatsApp message | Contacts → `wa.me/<number>?text=` → the device taps Send | AI (today's route) |
| SMS / iMessage | Contacts → message sheet or `sms:` → the device taps Send | AI |
| Email | `mailto:` → the device taps Send | AI |
| Directions | Apple Maps or Google Maps link | AI |
| Play music | Music app player / MusicKit, or a Spotify link | AI |
| Flashlight | Torch API **[Check]**, or Shortcut "Set Flashlight" | Control Centre with AI (today) |
| Wi-Fi, Airplane Mode, Low Power, Dark Mode, Orientation Lock, Hotspot | Mantiza shortcut | Control Centre with AI (today) |
| Bluetooth off | **Refuse:** it cuts Mantiza's own device link | — |
| Hindi or emoji text | Clipboard + ⌘V | — |
| Everything else | AI, starting from the closest link | — |

## H. Ten-minute check list on the iPhone (to settle every [Check])

1. ⌘H vs the Home key 0x0040: which one reaches the Home Screen on iOS 27.
2. Fn+C / Fn+N / Fn+↑ without Full Keyboard Access.
3. Siri key 0x00CF with Type to Siri on: does a text box open.
4. Focus key 0x009B, brightness keys, volume keys.
5. Torch API: does the light stay on after Mantiza goes to the background.
6. `tel:`: is the "Call" confirmation still there.
7. WhatsApp: does Return from the device send the message.
8. Adding a shortcut from an iCloud link on iOS 27: which taps it takes.
9. Spotlight: does typing "Bluetooth" offer the Settings page.

## Sources

- Apple, [Accessory Design Guidelines for Apple Devices](https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf), R32 Update 1 (2026-10-30), §14 Keyboards, Tables 14-1 to 14-4
- Apple, [What's new in iOS 27](https://developer.apple.com/ios/whats-new/); [Siri AI newsroom](https://www.apple.com/newsroom/2026/09/siri-ai-a-profoundly-more-capable-and-personal-assistant-is-here/); [How to get Siri AI](https://support.apple.com/en-us/127893)
- Apple, [Control iPhone with an external keyboard](https://support.apple.com/guide/iphone/ipha4375873f/ios); [AbilityNet iOS 26 Full Keyboard Access commands](https://mcmw.abilitynet.org.uk/how-to-control-your-device-using-an-external-keyboard-in-ios-26-on-your-iphone-or-ipad)
- Apple, [Run a shortcut from a URL](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios); [x-callback-url](https://support.apple.com/guide/shortcuts/apdcd7f20a6f/ios)
- Apple, [UIApplication.open](https://developer.apple.com/documentation/uikit/uiapplication/open(_:options:completionhandler:)); [openSettingsURLString](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring); [SMS links](https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/SMSLinks/SMSLinks.html); [Unified Maps URLs](https://developer.apple.com/documentation/mapkit/unified-map-urls)
- Apple, [AlarmKit](https://developer.apple.com/documentation/alarmkit), [Scheduling an alarm](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit); [EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store); [UIScreen.brightness](https://developer.apple.com/documentation/uikit/uiscreen/brightness); [systemMusicPlayer](https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller/systemmusicplayer); [NEHotspotConfigurationManager](https://developer.apple.com/documentation/networkextension/nehotspotconfigurationmanager); [MFMessageComposeViewController](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontroller); [torchMode](https://developer.apple.com/documentation/avfoundation/avcapturedevice/torchmode-swift.property)
- Apple Developer Forums: [App-Prefs is not documented](https://developer.apple.com/forums/thread/691712); [tel: confirmation since iOS 10.3](https://developer.apple.com/forums/thread/73406)
- WhatsApp, [How to use click to chat](https://faq.whatsapp.com/5913398998672934); Google, [Maps URLs](https://developers.google.com/maps/documentation/urls) and [iOS URL scheme](https://developers.google.com/maps/documentation/urls/ios-urlscheme); Telegram, [Deep links](https://core.telegram.org/api/links)
- jinwon-int, [esp32-iphone-agent](https://github.com/jinwon-int/esp32-iphone-agent) (consumer keys over BLE; ⌘H on iOS 27)
- Reports: [MacNative Shortcuts control actions](https://macnative.com/list-of-default-control-actions-for-ios-shortcuts/); [MacStories iOS 15 Shortcuts sharing](https://www.macstories.net/stories/ios-and-ipados-15-the-macstories-review/12/); [Stack Overflow: torch off in background](https://kiwix.lema.org/stackoverflow.com_en_all_2023-11/questions/32136442/iphone-flashlight-not-working-while-app-is-in-background); [Clock URL schemes](https://talk.automators.fm/t/ios-alarm-clock-app-with-url-scheme/1745); [Siri settings toggles](https://forums.macrumors.com/threads/siri-turn-wifi-off-turn-wifi-on.1793401); [WhatsApp via Shortcuts](https://discussions.apple.com/thread/254320976)
