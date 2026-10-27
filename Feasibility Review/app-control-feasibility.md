# Mantiza: Can We Control Apps? Feasibility Review

_Written: 2026-10-28 · For: the whole team, especially anyone who has not followed these discussions · Related: [Mantiza plan](../Mantiza%20Roadmap/plan.md), [App control options](../Mantiza%20Roadmap/app-control.md), [Artemis analysis](../Google%20Artemis%20Analysis/plan.md)_

## How to read this document

This document sums up a long discussion (2026-10-27 to 2026-10-28) about whether Mantiza can do what we first imagined, where we will get stuck, and what we can do instead.

Every fact is marked with how sure we are:

| Marker | Meaning |
|---|---|
| ✅ | Confirmed from the company's own official page or documentation |
| 📰 | Reported by press or a review site, not confirmed from an official page |
| ❓ | Unclear or unconfirmed; must be checked before we rely on it |
| _(estimate)_ | Our own guess, not measured |

Sources are listed at the end (section 10), numbered like [S1].

---

## 1. The short version

- **Our original idea:** an iPhone app that you just download, that controls any app on the phone by voice ("order milk on Blinkit", "open Google Maps and set directions home"), and that asks you before anything sensitive like payments.
- **The main problem:** no downloaded iPhone app can see or tap inside other apps. Apple blocks this on purpose. Google Play also bans third-party apps from doing this with AI on Android.
- **What still works:** apps and services that provide an "official door" (App Intents, Shortcuts, app links, or an agent server/API). But most of these doors are either already used by Siri, ChatGPT, Gemini and Claude, or closed to small third-party apps.
- **Our suggestion:** do not build a general "does everything" consumer assistant right now. The most realistic project is **Artemis for iPhone** (a developer/testing tool), with an optional small consumer experiment on the side. Details in section 9.

---

## 2. What we originally wanted

From [plan.md](../Mantiza%20Roadmap/plan.md) and the discussion:

1. **Voice and text commands** that act fast (e.g. "open Blinkit" in about 1 second).
2. **Control the apps on the iPhone itself:** open them, tap, type, finish tasks inside them, like a person would.
3. **Not a browser bot:** we do not want to automate websites in a hidden or remote browser. Using a browser app on the phone is fine only when the user asks for it ("open Chrome and search xyz").
4. **Sensitive things are never automatic:** for payments, banking and similar, Mantiza sends a notification and waits for the user to approve.
5. **No hassle:** users download the app and it works. No computer, no cable, no developer setup.
6. **Global**, not only India.
7. A **home screen widget** that learns daily, weekly and monthly habits.

The hard part is combining **2** and **5**.

---

## 3. The main problem: the iPhone sandbox

On iPhone, every app runs in its own sealed box (the "sandbox"):

- An app **cannot see** what another app shows on screen.
- An app **cannot tap or type** inside another app.
- An app **cannot directly run another app's actions** (App Intents). Only Siri and Shortcuts can. Apple confirmed this at WWDC26: when asked whether an app can be "its own orchestrator", Apple answered that the new system orchestrator is part of the system ✅ [S1].
- An app **cannot replace Siri** as the phone's assistant. Apple allows a third-party assistant on the Side Button **only in Japan**, because of a Japanese law 📰 (MacRumors, citing Apple's documentation) [S2].

This is a deliberate privacy and security decision by Apple, not a missing feature we can work around with clever code.

---

## 4. How Google Artemis does it, and why we cannot copy it into an app

[Google Artemis](https://github.com/google/artemis) is an open-source tool (Apache 2.0) ✅ [S3]:

- It runs on a **computer** and controls an **Android phone** connected by USB debugging (or an emulator), using **ADB** ✅ [S3].
- A small **accessibility helper** on the phone reads the list of buttons and text on screen, with UIAutomator2 as a fallback ✅ [S3].
- The AI looks at the screen, decides the next step, sends the tap through ADB, and repeats.
- **Flash mode:** about 3 to 5 s per step. **Pro mode:** about 15 to 40 s per step, with Planner, Operator and Checker roles ✅ [S3].
- Reports 99%+ task completion on Google's AndroidWorld benchmark ✅ [S3].
- **iOS support is on its roadmap**, not built yet ✅ [S3].
- It is built for **developers and testers**, not everyday users.

**Why it does not carry over:** Artemis works because Android's developer mode (ADB) lets a computer act like a finger. iPhone has no equivalent for normal apps. The closest thing is Apple's testing system (XCUITest / WebDriverAgent), which needs developer setup (section 5, Way 2).

---

## 5. All the ways we found to control iPhone apps

### Way 1: Mac + iPhone Mirroring

macOS shows the iPhone screen in a window on the Mac. A Mantiza program on the Mac would take screenshots of that window, let the AI decide where to tap, and click there.

**Requirements** ✅ [S4]
- Mac with Apple silicon or the T2 chip, on macOS Sequoia 15 or later.
- iPhone on iOS 18 or later, with a passcode.
- Both signed in to the same Apple Account with two-factor authentication, Wi-Fi and Bluetooth on.
- Only one Mac and one iPhone paired for mirroring at a time.

**Limitations**
- ✅ The iPhone **must be locked** and near the Mac. **Unlocking the iPhone stops mirroring** [S4]. The user cannot use their phone while Mantiza works.
- ✅ **Not available in the European Union** [S4].
- ✅ **No camera or microphone, including Face ID** and phone calls [S4]. Some streaming video may be blocked [S4].
- ✅ Mirroring **pauses after periods of inactivity** [S4].
- The Mac only gets a **picture**, not a list of buttons, so the AI has to find everything visually (OCR plus a vision model). This means more mistakes and retries than Way 2 _(estimate: a few seconds per step; must be measured)_.
- Clicking on the Mirroring window is not an official automation API. A macOS update could break it.
- **Users need a Mac.** Not "download and done".

### Way 2: WebDriverAgent (Apple's testing system, XCUITest)

A small test helper app is installed on the iPhone. A computer talks to it and it can read every button and text in any app, and tap, type and swipe. This is what Appium uses for iPhone testing. It is the closest thing to ADB on iPhone.

**Requirements**
- Built with **Xcode on a Mac** at least once.
- **Code signing:** with a free Apple account, the install **expires after 7 days** and must be rebuilt and reinstalled; free accounts are limited to 3 devices and 3 installed apps per device ✅ [S5]. A paid developer account ($99/year) lasts a year ✅ [S5].
- **Developer Mode** turned on on the iPhone (iOS 16 and later) ❓ (well known, but Apple's page could not be read during this review) [S6].

**Limitations**
- Developer setup: fine for developers, impossible to expect from normal users.
- The helper can be stopped by iOS and needs restarting.
- Reading the button list can be slow on complex screens _(estimate)_.
- Password fields, Face ID and passcode prompts cannot be automated _(well known testing limit; not re-checked)_.

### Way 3: Bluetooth "fake mouse" gadget

The iPhone's AssistiveTouch feature accepts a Bluetooth or wired mouse, and a pointer can click anything on screen ✅ [S7]. A small board (for example an ESP32) could pretend to be a mouse, and Mantiza could tell it where to click. To see the screen, Mantiza would use screen broadcasting (ReplayKit), which shows a recording indicator.

**Limitations:** extra hardware, fiddly setup, a visible pointer, experimental. Not "download and done". _(Not tested by us.)_

### Way 4: Apple's official routes (App Intents, Shortcuts, app links)

- **App Intents:** actions that apps publish so Siri and Shortcuts can run them (e.g. "Spotify: play playlist").
- **Shortcuts:** Apple's automation app. Very good for system actions (alarms, Focus, settings, messages, music, Home), logic, web requests, and automations that start by time, location, and other triggers.
- **App links:** open an app at a specific screen (e.g. a search page) when the app supports it.

**Limitations**
- Only does what each app chooses to publish. Many apps publish little or nothing.
- Mantiza cannot call other apps' intents directly. Only Siri and Shortcuts can ✅ [S1].
- There is no "tap here" action in Shortcuts.
- Users must add Shortcuts and automations themselves (we can share ready-made ones).
- **Siri uses exactly these same doors**, and does it natively.

### Other ideas we checked

| Idea | Verdict |
|---|---|
| Voice Control / Switch Control (built-in iOS accessibility) | Can tap anything, but **only the user** can start them. Mantiza cannot drive them. Voice Control also needs the user to say every step ("tap Add") |
| Partnerships with apps | Real, but slow and depends on them saying yes |
| Robot finger / stylus rig | Exists in testing labs; not a consumer product |
| Jailbreak | Old iOS versions only, breaks security and banking apps; not for users |
| Company device management (MDM) | Can install apps and set restrictions, **cannot tap** inside apps |
| EU alternative app stores | Same sandbox rules |
| Remote or hidden browser automation | Excluded by our own requirement |

### Comparison of the four ways

| | Way 1: Mirroring | Way 2: WebDriverAgent | Way 3: Gadget | Way 4: Official routes |
|---|---|---|---|---|
| Controls any app | Yes (picture only) | Yes (button list + picture) | Yes (picture only) | No, only what apps publish |
| "Download and done" | No, needs a Mac | No, developer setup | No, extra hardware | Yes |
| User can use phone while it works | No | Yes | Partly | Yes |
| Accuracy | Lower | Highest | Lower | Exact (when available) |
| Works in EU | No | Yes | Yes | Yes |
| Different from Siri | Yes | Yes | Yes | No, Siri uses the same doors |
| Good for | Mac owners | Developers, testers | Experiments | Everyone |

---

## 6. "Official doors" for services (agent servers / MCP / APIs)

Some companies now offer an official way for AI agents to act on a user's account (often called an **MCP server**). This is not a browser and not tapping; orders show up in the user's normal account. We checked whether a small third-party app like Mantiza is **allowed** to use them:

| Service | Agent door exists | Can a third-party consumer app use it? |
|---|---|---|
| **Zomato** | ✅ Yes: restaurants, menus, cart, ordering, QR payment [S8] | ❌ No. Official repo ✅: "We are not allowing any third party apps to be built on top of Zomato MCP right now"; personal use and testing only [S8] |
| **Swiggy** (Food, Instamart, Dineout) | ✅ Yes, "Swiggy Builders Club" [S9] | ⚠️ Only if approved. Official docs ✅: "invite-based in v1"; every application is reviewed; staging first, production after staging is stable for 48+ hours [S9]. Startups and enterprises can apply [S10] |
| **Zepto** | ✅ Yes: search, cart, real orders [S11] | ❓ Described as a consumer integration for Zepto customers in India; no terms for third-party apps are stated [S11]. Must ask Zepto |
| **Instacart** (US/Canada) | ✅ Yes: store availability, recipe ingredients, building and changing orders [S12] | ❓ Partner terms are not stated on the page [S12] |
| **DoorDash** | 📰 Yes, private beta | ❌ 📰 Reported (quoting DoorDash's docs) as built for corporate ordering and "not currently available to be integrated into consumer-facing products" [S13]. DoorDash's page blocked automated reading, so this could not be re-checked directly |
| **Blinkit, Uber, Ola, Rapido** | ❓ No official consumer agent door found | ❌ for now |

**What this means:** the doors exist, but they mostly let users connect **their own** AI assistant (ChatGPT, Claude, Gemini), or require a partnership. A new app has no guaranteed access.

---

## 7. Who we would compete with

| Competitor | What it already does |
|---|---|
| **Siri (iOS 27)** | Acts inside apps that adopt App Intents and App Schemas ✅ [S1]. MacStories' review says it "can do things in and with apps that no other third-party agent can", while Apple's models are "vastly behind the latest state of the AI frontier" 📰 [S14]. MacSparky: "the first wave of app support is uneven" 📰 [S15] |
| **ChatGPT** | Instacart with checkout inside the chat; DoorDash (groceries, finish in the DoorDash app) 📰 [S16] |
| **Claude** | Consumer connectors including Instacart, Uber Eats and Spotify (April 2026), with confirmation before purchases 📰 [S17] |
| **Swiggy via assistants** | Users can order Food, Instamart and Dineout through assistants such as ChatGPT, Claude and Gemini; at launch, AI orders were cash on delivery only 📰 [S18] |
| **Gemini on Android** | ✅ Google's own blog: Gemini can do multi-step tasks in installed apps "without developer work", as a beta on the Galaxy S26 series and select Pixel 10 devices, starting with food delivery, grocery and rideshare apps in the US and Korea, with alerts before purchases [S19]. Google does this as the platform owner |

### Android: not the escape hatch we hoped

We considered Android because, there, an app can use the **Accessibility Service** to see and tap other apps. But Google Play's policy says ✅ [S20]:

- "Any use of the Accessibility API that enables an app to autonomously initiate, plan, and execute actions" is prohibited.
- Fixed, rule-based scripts written by a human are still allowed.
- The only exception is verified accessibility tools whose **core purpose** is helping people with disabilities, and "a general assistant that is voice-activated... would not qualify".

So an AI assistant that taps through apps is **not allowed on Google Play**, while Google's own Gemini can.

---

## 8. Where we will get stuck (summary)

1. **Tapping inside apps from a downloaded app:** impossible on iPhone (sandbox), banned on Google Play (accessibility policy).
2. **Full control needs something outside the phone:** a Mac (Ways 1 and 2) or a gadget (Way 3). That breaks "download and done".
3. **Official doors are shared with giants:** App Intents are Siri's home turf; agent servers are already connected to ChatGPT, Claude and Gemini.
4. **Access is gated:** Zomato does not allow third-party apps; Swiggy is invite-only; DoorDash excludes consumer products (reported); others are unclear.
5. **No clear edge:** a general consumer Mantiza would have less access than ChatGPT and Gemini, less app integration than Siri, and no capability they lack.

### Corrections made during the discussion
To be transparent, two things said earlier in the discussion were wrong and are fixed here:
- We first said "Mantiza could order biryani on Zomato through its agent server". **Zomato currently does not allow third-party apps** [S8].
- We first suggested "Android first, a Play Store app with Accessibility Service". **Google Play bans this for AI agents** [S20].

---

## 9. Suggestions

### Options compared

| Option | What it is | Edge | Main risk |
|---|---|---|---|
| **A. Artemis for iPhone** | Fork Google's Artemis and add an iPhone driver (WebDriverAgent first, Mirroring as backup). For developers and testers | Real gap: iOS is on Artemis's roadmap but not built. Developer setup is normal for this audience. Uses only allowed tools. We have a Mac | Appium and other tools exist; Google may ship iOS support themselves |
| **B. Small consumer experiment: routine widget** | iPhone app with the pattern-learning widget, using only what Apple allows everywhere (Shortcuts, app links, Calendar, Music, Home) | No gatekeepers, works globally, cheap to test (2 to 3 weeks _(estimate)_) | Demand is unproven; Apple could copy it; overlaps with Siri suggestions |
| **C. Full consumer Mantiza (original idea)** | General voice assistant that does tasks across apps | None clear today | Blocked by section 8 |
| **D. Wait and watch** | Apply for access and watch for platform changes | Keeps options open | Builds nothing |

### Our recommendation

1. **Build Option A (Artemis for iPhone) as the main project.**
   - Start by forking Artemis and checking how cleanly its Android device code is separated from its AI brain (about a day of reading).
   - Driver: **WebDriverAgent** first (most accurate), **iPhone Mirroring** as an optional backup.
   - First milestone: on the collaborator's Mac, build WebDriverAgent, install it on an iPhone, and run one tap from a script (1 to 2 days _(estimate)_).
2. **Optionally run Option B** as a small side experiment, to test whether people want routine suggestions.
3. **Keep the door open on services:** apply to Swiggy Builders Club, ask Zepto about third-party use, and watch Zomato's policy.
4. **Re-check after WWDC27 (June 2027):** Apple could open new agent APIs (for example official MCP support, which is rumoured but not confirmed ❓).

### Decisions we need from the team
- Do we agree to pause the general consumer assistant (Option C)?
- Do we go with Option A as the main project?
- Who builds and maintains WebDriverAgent on the Mac?
- Do we want to run Option B in parallel?

---

## 10. Sources

| # | Source | Used for |
|---|---|---|
| S1 | [Apple WWDC26: Apple Intelligence Group Lab](https://developer.apple.com/videos/play/wwdc2026/8011/) | Apps cannot invoke other apps' intents; Siri/Shortcuts orchestrate; App Schemas; view annotations |
| S2 | [MacRumors: iOS 26.2 lets users in Japan replace Siri on the Side Button](https://www.macrumors.com/2025/11/17/ios-26-2-iphone-users-japan-siri/) | Third-party assistant on Side Button, Japan only |
| S3 | [google/artemis on GitHub](https://github.com/google/artemis) | How Artemis works, modes, roadmap, license, benchmark |
| S4 | [Apple Support: Use iPhone Mirroring on Mac](https://support.apple.com/en-us/120421) | Mirroring requirements and limits |
| S5 | [Apple Developer: Compare memberships](https://developer.apple.com/support/compare-memberships/) and [Apple Developer Forums](https://developer.apple.com/forums/thread/69248) | Free provisioning expires after 7 days; free account limits |
| S6 | [Apple Developer: Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) | Developer Mode (page could not be read during review) |
| S7 | [Apple Support: Use AssistiveTouch on iPhone](https://support.apple.com/en-us/111775) | Pointer devices, including Bluetooth, can click on screen |
| S8 | [Zomato MCP server manifest on GitHub](https://github.com/Zomato/mcp-server-manifest) | Zomato capabilities and third-party restriction |
| S9 | [Swiggy Builders Club: Access and onboarding](https://mcp.swiggy.com/builders/docs/operate/access/) | Invite-based, reviewed, staging and production steps |
| S10 | [Swiggy Builders Club: Apply for production access](https://mcp.swiggy.com/builders/access/) | Who can apply; prohibited conduct |
| S11 | [Zepto MCP on GitHub](https://github.com/zeptonow/mcp) | Zepto capabilities and scope |
| S12 | [Instacart MCP servers docs](https://docs.instacart.com/mcp_servers) | Instacart capabilities |
| S13 | [Search result quoting DoorDash MCP docs](https://developer.doordash.com/en-US/docs/mcp/overview/about_mcp/) | DoorDash consumer restriction (page blocked direct reading) |
| S14 | [MacStories: iOS and iPadOS 27 review](https://www.macstories.net/stories/ios-and-ipados-27-review/4/) | Siri AI strengths and weaknesses |
| S15 | [MacSparky: Apps adding Siri AI support for iOS 27](https://www.macsparky.com/blog/2026/10/apps-adding-siri-ai-support-for-ios-27/) | Uneven third-party app support |
| S16 | [Digital Commerce 360: DoorDash app in ChatGPT](https://www.digitalcommerce360.com/2025/12/19/doordash-app-openai-chatgpt/) | ChatGPT with DoorDash and Instacart |
| S17 | [Chain Store Age: Instacart, Uber Eats integrate with Claude](https://chainstoreage.com/instacart-uber-eats-integrate-anthropic-claude-ai-platform) and [9to5Google: Claude connectors](https://9to5google.com/2026/04/24/claude-connectors-spotify-uber-turbotax-more/) | Claude integrations |
| S18 | [Angel One: Swiggy integrates ChatGPT, Gemini and other AI tools](https://www.angelone.in/news/stocks/swiggy-integrates-chatgpt-gemini-and-other-ai-tools-for-food-and-grocery-delivery) | Swiggy ordering through AI assistants |
| S19 | [Android Developers Blog: The Intelligent OS (Feb 2026)](https://android-developers.googleblog.com/2026/02/the-intelligent-os-making-ai-agents.html) | Gemini operating apps on Android; AppFunctions |
| S20 | [Google Play Console Help: Use of the AccessibilityService API](https://support.google.com/googleplay/android-developer/answer/10964491?hl=en) | Ban on autonomous AI agents via Accessibility |
