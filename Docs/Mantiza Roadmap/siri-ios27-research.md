# The new Siri (iOS 27): what it can and can't do

Researched 2026-11-13. Tags: **[Apple]** = Apple's own newsroom, support or developer pages ·
**[Reviews]** = MacRumors, 9to5Mac, TechCrunch, Engadget and other press ·
**[Older]** = documented for an earlier iOS and assumed unchanged · **[Check]** = not confirmed yet.

## In one paragraph
iOS 27 (September 2026) brought **Siri AI**: a rebuilt, conversational Siri with its own app. It can find
things in your messages, mail and photos, understand what's on screen, write, and act in apps.
**It only acts in apps through actions the app has built for it** (App Intents / App Schemas). It
can't tap its way through an app the way Mantiza does. It is still **beta** and needs an
**iPhone 15 Pro or newer**. **Your iPhone 14 Plus doesn't get it.** It keeps **Siri Classic**, the
iOS 26 Siri.

## Who gets which Siri

| | Siri AI (new) | Siri Classic (old) |
|---|---|---|
| iPhone | 15 Pro / Pro Max, 16 and later, Air **[Apple]** | everything else on iOS 27, **including iPhone 14 Plus** **[Reviews]** |
| Status | Beta **[Apple]** | Same as iOS 26 **[Reviews]** |
| Languages | English, plus French, Japanese, Korean, Portuguese and Spanish since iOS 27.2 (26 Oct 2026) **[Apple]** | All Siri languages |
| Regions | **Not in the EU** on iPhone/iPad, not in China **[Apple]** | Everywhere |
| Limits | Server features have **daily usage limits**, with "expanded access … for a fee in the future" **[Apple]** | None stated |
| Other | Age 13+, device and Siri language must match, up to 8–14 GB of storage **[Apple]** | — |

Siri AI devices can switch back to Siri Classic in Settings → Siri **[Reviews]**.

## What Siri AI can do

**Conversation and the Siri app**
- A dedicated Siri app with a conversation history that syncs over iCloud **[Apple]**.
- Follow-up questions on almost any answer **[Apple]**. Several tasks in one request **[Reviews]**.
- Since iOS 27.2 it remembers past conversations ("the restaurants you recommended last week") **[Reviews]**.
- Ways to start it: "Hey Siri", the side button, or a swipe down from the Dynamic Island **[Apple]**. You can type or speak; a swipe down on an answer opens a text bar; a + button attaches images or documents **[Reviews]**.

**Your personal data ("personal context")**
- It searches messages, emails, photos, files and notes, e.g. a confirmation number or a door code someone texted **[Apple]** **[Reviews]**.
- iOS 27.2 added photos attached in Messages, Calendar attendees and voicemails, and improved Safari history and Reading List **[Reviews]**.
- Settings → Siri → Excluded Apps (iOS 27.2) chooses which apps Siri may read **[Reviews]**.

**What's on screen**
- It answers questions about, or acts on, what's on screen, e.g. finding a team's home games on a web page and adding them to Calendar **[Apple]**. It can read text, look at images and translate a menu **[Reviews]**.
- In third-party apps, Siri can point at "this message" only if the app labels its views for Siri **[Apple, WWDC26]**.

**Acting in apps**
- **Apple apps:** draft email, edit and share photos, add to Reminders, create Calendar events **[Apple]**; move meetings, add a stop to directions **[Reviews]**.
- **Third-party apps, available now:** texting in **WhatsApp**, playing a book on **Audible** **[Apple]**.
- **Coming "soon", no date:** Outlook (draft email), Notability, Tripsy **[Apple]**.
- **Rule:** only apps that have built Siri actions. Developers describe content and actions with **App Schemas** grouped into domains (messages, mail, photos "and more"), and Siri runs them **[Apple, WWDC26]**. Nothing in Apple's material says Siri can operate an app's screens by itself.

**Writing, camera, knowledge, voice**
- "Write with Siri" almost anywhere you type: drafts, edits, tone, proofreading. In Mail and Messages it matches how you usually write **[Apple]**.
- Camera: a Siri mode that answers questions about what the camera sees, e.g. a festival poster's set times turned into Calendar events **[Apple]**.
- Answers from the web: sports scores, travel, local recommendations **[Apple]**. It makes images with Image Playground **[Apple]**.
- More natural voices with adjustable expressiveness and pace **[Apple]**. Better dictation **[Apple]**.
- Privacy: on the phone plus Apple's Private Cloud Compute **[Apple]**.

## What Siri AI can't do, or does badly

- **It can't use apps that haven't built Siri actions.** There's no tapping through screens like a person; Apple only describes acting through app actions **[Apple]**. Third-party support is still limited **[Reviews]**. In testing it couldn't get recent Slack or Messenger chats or Gmail **[Reviews]**, and struggled with Things, Flighty and organising files **[Reviews]**.
- **No real agent behaviour yet.** Reviewers say it has only "caught up with what AI assistants could do in 2024" and needs explicit instructions for bigger jobs **[Reviews]**.
- **Slow and sometimes down:** "painfully slow to answer even simple queries"; slow networks make it worse, because much of it runs in the cloud; "Sorry, something went wrong" errors **[Reviews]**. One reader reported sending a text took 30–40 s, against seconds with Siri Classic **[Reviews, one user]**.
- **Lost some old abilities:** sometimes can't find a Reminders list or says you have no alarms when you do; finds HomeKit accessories by name inconsistently; some old phrasings now confuse it **[Reviews]**.
- **Locked iPhone:** many requests need the phone unlocked, even with "Allow Siri When Locked" on **[Reviews]**.
- **Not supported:** Health app data questions (per Apple's documentation, as reported by 9to5Mac); the "Use ChatGPT" prefix no longer works **[Reviews]**.
- **Usage cap:** daily limits on server features **[Apple]**.
- **Not in the EU or China**, and beta only **[Apple]**.

## What Siri Classic does (your iPhone 14 Plus)

The same Siri as iOS 26. It works by fixed commands, not conversation.

- **On the phone, without internet** (A12 chip or later, since iOS 15): set and turn off **timers and alarms**, **open apps**, control **audio**, change **settings** **[Older]**.
- **Settings by voice** **[Older]**:
  - Wi-Fi, Bluetooth, mobile data, Airplane Mode, Dark Mode, Low Power Mode
  - brightness ("set brightness to 20%"), volume, flashlight, VoiceOver, Focus / Do Not Disturb
- **Apple apps:** calls, Messages, alarms and timers (they land in the **Clock app's list**), Reminders, Calendar, Notes, Maps directions, Music, the weather, unit conversion, and so on **[Older]**.
- **Third-party apps:** through SiriKit (messaging, calls, media, workouts, lists, payments…) and the apps' own **App Shortcuts** phrases, e.g. WhatsApp messages **[Older]**.
- **Typing instead of speaking:** Settings → Accessibility → Siri → **Type to Siri** **[Older]**.
- **Can't do:**
  - conversation or follow-up questions
  - anything in your personal data or on screen
  - Write with Siri, the camera mode or the Siri app (all Siri AI)
  - anything in apps without SiriKit or App Shortcuts support

## What this means for Mantiza
1. **On the iPhone 14 Plus, Siri Classic is the Siri to use.** It's fast, offline-capable and sure for alarms, timers, settings toggles, calls, messages and opening apps. Those are the jobs where screen tapping is slow or fragile; the Clock alarm runs are the example.
2. **Siri AI wouldn't replace Mantiza even on a 15 Pro.** It only works inside apps that built Siri actions. Mantiza's StickS3 can tap through any app, which is the gap reviewers point out.
3. **Built (2026-11-14): Mantiza hands Siri's jobs to Siri.** Tested by hand on the iPhone 14 Plus:
   - a short Siri key press does nothing; **holding it 1 s** opens Siri's typing box (Type to Siri on)
   - the request must be typed at once: the box closes after a few seconds, and late typing lands in Search
   - Enter sends it, Siri answers, **Escape closes Siri**
   Mantiza goes to the Home Screen first, checks the request shows in Siri's box (not in Search),
   reads Siri's answer, and only then reports done. Used for alarms and timers (with the old routes as
   fallback), phone settings, live info, notes and music.

## Sources
- Apple: [Siri AI is here (Sept 2026)](https://www.apple.com/newsroom/2026/09/siri-ai-a-profoundly-more-capable-and-personal-assistant-is-here/) · [Apple Intelligence, WWDC26](https://www.apple.com/newsroom/2026/06/apple-intelligence-brings-powerful-ai-capabilities-into-everyday-experiences/) · [More languages (Oct 2026)](https://www.apple.com/newsroom/2026/10/siri-ai-is-available-in-more-languages-starting-today/) · [Apple Intelligence requirements and limits](https://support.apple.com/en-us/121115) · [WWDC26: App Schemas](https://developer.apple.com/videos/play/wwdc2026/240/) · [WWDC26: App Intents for Siri](https://developer.apple.com/videos/play/wwdc2026/343/) · [Siri settings, iPhone User Guide (iOS 15)](https://support.apple.com/en-asia/guide/iphone/iphc28624b81/15.0/ios)
- Reviews: [MacRumors, Siri AI guide](https://www.macrumors.com/guide/ios-27-siri/) · [MacRumors, iOS 27.2](https://www.macrumors.com/2026/10/30/new-things-iphone-can-do-ios-27-2/) · [MacRumors, which iPhones get what](https://www.macrumors.com/2026/09/09/which-iphones-support-every-ios-27-feature/) · [9to5Mac, five frustrations](https://9to5mac.com/2026/09/20/five-ways-that-the-new-siri-ai-is-frustrating-iphone-and-apple-watch-users/) · [9to5Mac, catching up](https://9to5mac.com/2026/10/22/apple-is-finally-catching-up-with-siri-but-the-goalposts-are-moving-again/) · [TUAW, WWDC limits](https://www.tuaw.com/2026/06/15/siri-ai-shines-at-wwdc-2026-despite-key-limitations) · [Geeky Gadgets, Siri on Mac](https://www.geeky-gadgets.com/siri-ai-mac-test/) · [Cult of Mac, Siri Classic](https://www.cultofmac.com/how-to/turn-off-siri-ai-apple-intelligence-ios-27) · [TechCrunch, iOS 27.2](https://techcrunch.com/2026/10/27/apple-rolls-out-ios-27-2-with-new-siri-ai-languages-and-security-fixes/) · [Engadget, iOS 27 features](https://www.engadget.com/2303526/iphones-ios-27-features-you-should-use/)
- Older: [MacRumors, iOS 15 offline Siri](https://www.macrumors.com/guide/ios-15-siri) · [iDrop News, offline Siri settings](https://www.idropnews.com/gallery/8-things-you-can-now-do-on-device-with-siri-in-ios-15-and-5-things-you-cant/168656/4) · [AbilityNet, Type to Siri](https://mcmw.abilitynet.org.uk/how-to-use-siri-by-typing-your-requests-in-ios-26-on-your-iphone-or-ipad)
