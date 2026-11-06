# Mantiza v2: Product and Build Plan

_Written: 2026-10-29 · Updated: 2026-10-30 (English first, two-brain AI with Jev, speed) · Status: plan, nothing built yet · Supersedes the "how Mantiza acts" parts of [plan.md](plan.md) · Background: [Feasibility review](../Feasibility%20Review/app-control-feasibility.md), [Fake Mouse deep dive](../Feasibility%20Review/Fake%20Mouse.md)_

## How to read this document

| Marker | Meaning |
|---|---|
| ✅ | Confirmed from official documentation (Apple, Espressif, M5Stack) or Apple staff on the Apple Developer Forums |
| 📰 | Reported by one project, developer or third-party site; not independently confirmed |
| ❓ | Unknown; must be tested on a real device before we rely on it |
| _(idea)_ | Our own design idea, not yet tested |
| _(estimate)_ | Our own guess, not measured |

Sources are numbered like [P1] and listed in section 15.

**Scope decision (2026-10-29):** we build first and do **not** target the App Store for now. We write **our own code**, using existing open-source projects only as reference.

**Scope decision (2026-10-30): English only for the first version.** Hindi and other languages come later (Phase 3 onwards). The Hindi parts of this plan (sections 6.2–6.5, tests T5–T7, T10 and T13) are kept as the plan **for later**, not for now.

**AI decision (2026-10-30): two brains.** A fast decision model (**TypeSafe's Jev**) picks most taps; a frontier model (**Claude or Gemini**) understands, plans, writes text and handles hard steps (section 4.3). This must pass test T11 first.

---

## 1. What Mantiza v2 is

Mantiza is an AI assistant that **uses your iPhone apps for you**. You tell it what to do (by voice or text; **English first**, Hindi and "Hinglish" later), and it operates the apps on your phone the way a person would, through a small pocket device.

It has four parts:

| # | Part | One-line description |
|---|---|---|
| 1 | **iOS app** | The brain: understands the request, watches the screen, decides each step, asks before sensitive actions |
| 2 | **Home screen widget** | Your usual workflows, personalised and grouped in tabs; one tap to run |
| 3 | **Languages** | **v1: English** chat, voice and typing. **Later:** Hindi and other languages, including typing Hindi into other apps |
| 4 | **Mantiza device** | A pocket ESP32 device with a battery and a small screen. It acts as the "hands" (Bluetooth mouse and keyboard) and shows live status |

**One-line pitch:** _"Say it in your language, Mantiza does it on your phone, safely."_

### What already exists, and how we differ

Open-source projects already let an AI operate an iPhone with an ESP32 board [P1][P2][P3]. From their READMEs, all of them:
- use a **cloud vision model with your own API key**;
- type **English only** ("ASCII only");
- use **development boards with no battery** (powered by a cable from the phone, a charger or a power bank);
- have **no personalised widget** of learned workflows;
- have a stop button and consent, but **no sensitive-app blocking or approval step**.

Mantiza's differences:

| Mantiza v2 | Why it matters |
|---|---|
| **Hindi and other languages** (later; v1 is English), including typing them into any app | All existing projects are English-only |
| **Two-brain AI for speed:** a fast picker (Jev) chooses most taps, a frontier model plans and handles hard steps | Existing iPhone projects call one big vision model for every step, "most of it the model" 📰 [P1] |
| **Personalised workflow widget** with tabs | Turns the agent into a one-tap daily tool |
| **Dedicated battery device with a status screen and buttons** | Works in a pocket; shows what it is doing; physical approve/stop |
| **Safety built in**: blocked sensitive apps, approval before paying or sending | None of the existing projects have this |
| **Frontier cloud AI with computer-use tools (Claude or Gemini) + Apple's on-device OCR** | Models built to operate screens, with strong Hindi for later; OCR gives exact text positions for accurate taps |
| **Shortcuts first, taps last** | Faster and more reliable than tapping every step _(idea)_ |

---

## 2. Is it doable? (verdict per component)

| Component | Verdict | Evidence |
|---|---|---|
| App sees the whole screen while other apps are in front | ✅ Doable on iOS 27 | ScreenCaptureKit is on iOS 27 and "replaces ReplayKit for screen streaming and mirroring" [P4]; the `screen-capture` background mode lets capture continue in the background [P5]; App Store Connect accepts that mode after an August 2026 fix (Apple staff) [P6] |
| Board taps and types on the iPhone over Bluetooth, no cable | ✅ Doable (proven by others) | iPhone accepts Bluetooth pointer devices via AssistiveTouch [P7]; Bluetooth mouse + keyboard with an ESP32-S3 shown working, including exact positioning and the app talking to the board at the same time 📰 [P8][P2] |
| App sends commands to the board while in the background | ✅ Doable | `bluetooth-central` background mode: "The app communicates with a Bluetooth accessory while in the background" [P5] |
| Widget with tabs and one-tap workflows | ✅ Doable, with one limit | Widgets support `Button` and `Toggle` with App Intents, "without launching the app", and every tap reloads the widget [P9]. **Limit:** a workflow needs screen capture, so the tap must **open the Mantiza app** (via `Link`/`widgetURL`) [P9] ❓ (see 5.5) |
| English voice, chat and typing (v1) | ✅ Doable | Apple speech recognition and Apple Intelligence support English [P13]; the device types English with keyboard key codes, as all existing projects do [P1][P2][P3] |
| Fast tap decisions with Jev (v1) | ⚠️ Promising, must test (T11) | Jev answers "which option?" questions; repos report ~0.2–0.5 s per decision 📰 [P34][P36][P37]. Text-only input, so we feed it a numbered list built from OCR [P30] |
| Hindi voice input (later) | ✅ Doable | Apple lists **Dictation** for Hindi (India) [P10]; `SFSpeechRecognizer` lists `hi-IN` in sample output 📰 [P11]. Apple's newer `SpeechTranscriber` appears **not** to support Hindi 📰 [P12] |
| Hindi understanding (later) | ✅ Doable with a cloud model | **Apple Intelligence does not support Hindi** in iOS 27 (16 languages listed, no Hindi) [P13]; Claude's Hindi score is 96.7% of English [P26]. The cloud model is our main brain (section 4.3) |
| Typing Hindi into other apps (later) | ⚠️ Doable in principle, must test | Paste approach: iOS treats **⌘V** as user intent, so no paste alert [P14]; key combos work over Bluetooth 📰 [P8]. Writing the clipboard from the background is ❓ |
| Battery device with a screen | ✅ Doable with ready-made hardware | M5StickS3: ESP32-S3, 250 mAh battery, 1.14" screen, 2 buttons, IMU, mic, speaker [P15] |
| Phone in pocket while Mantiza works | ❌ Not fully | Mantiza needs the phone **unlocked and on screen** during a task; protected content and some screens are not captured [P2][P16] |

**Overall:** buildable. For the English-first version, the riskiest parts to test first are **capture behaviour in the background and on lock**, **AI accuracy and speed (Jev vs Claude/Gemini)**, and **pointer accuracy** (section 11, Phase 0).

---

## 3. System overview

```
                      ┌──────────────────────────────── iPhone ────────────────────────────────┐
 You (voice/text) ──► │ Mantiza app                                                          │
                      │  ├─ Language layer: speech → text (English in v1)                    │
                      │  ├─ Planner (big brain): "reply to Azad: I'm coming" → subtask       │
                      │  ├─ Shortcut layer: app links / Shortcuts / Contacts (fast path)     │
                      │  ├─ Eyes: ScreenCaptureKit frames + on-device OCR → numbered list    │
                      │  ├─ Actor (fast brain): Jev picks an item from the list;             │
                      │  │   big brain + screenshot for icons / unsure steps                 │
                      │  ├─ Guards: freshness check, wait-for-settle, no blind retries       │
                      │  ├─ Safety: block list, approvals, stop                              │
                      │  └─ Memory: workflows, patterns ──► Widget (App Group storage)       │
                      │                                                                       │
                      │   ▲ AI calls: Jev (fast picker) + Claude or Gemini (big brain)       │
                      │     + Apple on-device OCR                                            │
                      └────────┼─────────────────────────────┬───────────────────────────────┘
                               │                              │ Bluetooth (our command channel)
                               │                              ▼
                      Mantiza device (ESP32-S3, battery, screen, buttons)
                         ├─ Bluetooth mouse + keyboard ──► iPhone (AssistiveTouch pointer)
                         └─ Screen: live status · Buttons: approve / stop · IMU: shake to stop
```

---

## 4. Part 1: the iOS app

### 4.1 Main screens
| Screen | What it shows |
|---|---|
| **Home / chat** | Text and voice input, recent tasks, suggestions |
| **Live task** | Current step, screenshot with the planned tap drawn on it, Stop button |
| **Workflows** | Saved and learned workflows, edit, pin to widget |
| **Device** | Pairing, battery, calibration, firmware update |
| **Safety** | Blocked apps list, what needs approval, history |
| **Privacy** | What is stored, delete everything, choose AI provider |

### 4.2 The agent loop (per task)
1. **Understand (big brain):** turn the request into a **subtask**: goal, literal inputs, how to check success, allowed risky actions, maximum steps (format idea from arc-cua [P36]). Example: _"Reply to Azad that I'm coming"_ → `{app: Messages, contact: Azad, text: "I'm coming", check: "message 'I'm coming' visible in Azad chat", allowed_risks: [send], max_steps: 8}`.
2. **Fast path first** _(idea)_: if an app link, Shortcut or Apple framework can do part of the job, use it (section 4.5).
3. **Start the eyes:** screen capture via the system picker (consent per session; whether it repeats every time is ❓).
4. **Loop** _(idea, pattern from [P34][P35][P36])_:
   1. Capture the latest frame → OCR → build a **numbered list** of on-screen items with their boxes (e.g. `[1] "Azad"`, `[2] "Search"`, `[3] "iMessage"`).
   2. **Jev** picks the operation and the item number. Risky items (Send, Delete, Buy) are **left out of the list** unless the subtask allows them.
   3. If Jev's **confidence is low**, or the target is an **icon with no text**, ask the **big brain** with the screenshot instead.
   4. **Freshness check:** just before tapping, confirm the item is still where we saw it; if the screen changed, look again instead of tapping.
   5. Device moves the pointer to the **centre of the item's box** and clicks.
   6. **Wait until the screen settles** (frames stop changing), not a fixed delay.
   7. Repeat until the subtask's check passes.
5. **Safety gate before sensitive actions** (section 9). **Never auto-retry** an action after an uncertain failure (e.g. Send) [P35].
6. **Finish:** check success **independently** with OCR (a model saying "done" is not proof [P35][P36]); report, save the run, update patterns, stop capture.

### 4.3 AI layer

**Decision (2026-10-29): a cloud model (Claude or Gemini) is the main brain. Apple's AI is a helper.**
**Update (2026-10-30): two brains.** The cloud model is the **big brain**; **Jev** is the **fast brain** that picks most taps (section 4.3.1).

Why a cloud model rather than Apple's:
- **Hindi (for later):** Apple Intelligence supports 16 languages and **Hindi is not one of them** [P13]. Claude scores **96.7%** of its English performance in Hindi (Claude Sonnet 4.5; 92.4% for Haiku 4.5) [P26].
- **Operating screens:** Claude has a **computer use tool** (screenshots, clicks at coordinates, typing, key combinations, drag, scroll, zoom into small text) [P27]. Gemini has **computer use** with a **mobile mode** (tap, long press, drag at coordinates); it is a **Preview** feature and the mobile mode is **Android-optimised** [P28]. Apple's models have no equivalent tool.
- **Model strength:** Apple's on-device context is **8,192 tokens** and PCC's is **32,000** [P17]; a review calls Apple's models "vastly behind the latest state of the AI frontier" 📰 [P29].

| Model | Role | Facts |
|---|---|---|
| **Cloud model: Claude (Sonnet 5.5 or Haiku 5.5) or Gemini (3.8 Flash)** | **Big brain:** understand the request, plan the subtask, write message text, handle icon-only and low-confidence steps, final check |
| **TypeSafe Jev (fast brain)** | Pick the next operation and item from the numbered OCR list | See 4.3.1 [P30][P31] | Claude computer use supported on Claude 5.5 models [P27]; Gemini computer use models include `gemini-3.8-flash` (recommended) [P28]. Billed per token. We pick one after test T8 |
| **Apple OCR tool (on-device)** | Read all on-screen text **with positions** and send it to the cloud model alongside the screenshot, so taps land on exact targets | "the OCRTool allows the model to extract structured text from images" [P17]; free and private |
| **Apple on-device model** _(optional)_ | Small English-only jobs (e.g. classify a simple command), offline/privacy mode | Accepts image input; 8,192-token context [P17] |
| **Apple Private Cloud Compute** _(optional)_ | Possible cheaper English fallback | 32,000-token context; "no cloud API costs to developers who have less than 2 million first time downloads"; "No prompts are ever stored"; daily per-user limits [P17] |

All of these plug in through Apple's `LanguageModel` protocol ("Anthropic and Google are publishing Swift packages") [P17], so we can switch models later without rewriting the app.

**Trade-offs of cloud-first:** pay per token (reduce by sending downsized screenshots plus OCR text), screenshots leave the phone (clear consent, block list for sensitive apps), and it needs internet plus a small key server.

**Keys and security:** never ship API keys in the app; Apple says to "Always fetch access tokens with a secure mechanism like OAuth, and store them securely using KeyChain" [P17]. We run a small backend that holds cloud keys (Jev's key included).

#### 4.3.1 The fast brain: TypeSafe Jev

**What it is:** a "System One" decision model. You send a **state** (text or JSON) and typed **questions** (pick one option, give a score, yes/no), and it returns the answer with a **confidence** [P30]. It is **not** a chat model: "System One models do not write replies, produce code, or generate explanations" [P30].

| Fact | Detail | Source |
|---|---|---|
| Speed | Not published by TypeSafe. Repos report a median of **178 ms** per request (browser) 📰 [P34], ~**270–320 ms** per decision (arc-cua) 📰 [P36], "~0.5 s per decision" for computer use 📰 [P37]. From India ❓ | 📰 |
| Price | $0.042 per million input tokens; output free | [P31] |
| Models | `jev-1.14.0` (from 2026-10-14), `jev-1.13.0`; `jev-latest` → 1.14. Context 64k tokens per request | [P31] |
| Input | Text/JSON. Images only as an unfinished preview behind a special header ("Dreamer-ready") | [P30][P41] |
| Language | "English is the primary training language and where accuracy is currently best"; other languages "handled but not equally well" | [P31] |
| Known weaknesses | "leans toward the option that comes first"; "Accuracy falls as the state grows with content unrelated to the decision"; does not treat state as hostile by default | [P32] |
| Privacy | Screen text goes to one more company. Zero data retention only for enterprise customers; "commitment not to train models on user data" | [P33] |

**How we use it on iPhone:** existing Jev agents read a list of buttons from the accessibility tree (Android, macOS) or the web page [P34][P35][P36]. iOS does not let us read other apps' buttons, so we **build the list from OCR text and boxes**. Mitigations for its weaknesses: send only what is on screen (small state), shuffle or order the list by screen position, keep risky items out of the list, and use the confidence to fall back to the big brain.

**Gap:** icon-only buttons (Send ➤, back ←, ⋮) have no text, so they are not in the OCR list. First runs use the big brain for these; learned workflows remember them (section 8). Icon detection is a later improvement _(idea)_.

**If T11 fails:** we drop Jev and use the big brain for every step (slower; see section 4.4).

### 4.4 Speed: how long a task takes _(estimates, not measured)_

**Per step (one tap):**

| Part | Big brain only | With Jev |
|---|---|---|
| Grab frame + OCR + build list (phone) | ~0.2–0.5 s | ~0.2–0.5 s |
| Upload + AI decision | ~2–8 s | ~0.3–0.8 s |
| Device moves pointer, checks, clicks | ~0.3–1.5 s | ~0.3–1.5 s |
| Wait for screen to settle | ~0.5–1 s | ~0.5–1 s |
| **Total per step** | **~4–10 s** | **~1.5–3.5 s** |

**Whole task: "Reply to Azad: I'm coming":**

| Stage | Big brain only | With Jev |
|---|---|---|
| User: speak, screen-capture picker, approve | ~6–12 s | ~6–12 s |
| Understand + prepare (big brain, text only) | ~1–3 s | ~1–3 s |
| Open Messages | ~1–2 s | ~1–2 s |
| Tap Azad's chat | ~4–10 s | ~1–3 s |
| Tap text box + type | ~4–9 s | ~1–3 s |
| Tap Send (icon: big brain on first run) | ~1–2 s | ~2–6 s first run, ~1 s learned |
| **Total, first run** | **~20–40 s** | **~13–28 s** |
| **Total, learned workflow** | ~12–25 s | **~10–18 s** |

**What the evidence says:**
- Published phone agents on real apps take **7–30 s per step** (AndroidDaily: Gemini 3 Flash 14.7 s/step) [P39]; mobile-jev reports "about 21 seconds for 9 actions" on Android 📰 [P35].
- Turning repeated steps into shortcuts cut task time **from 209 s to 91 s** in research (AppAgentX) [P40], which supports section 8.

**Speed techniques we adopt** _(ideas; patterns seen in [P34]–[P36], our own code)_:
1. Two brains (fast picker for most taps).
2. Fast paths and learned workflows: skip steps entirely.
3. Wait-for-settle instead of fixed waits (arc-cua cut waiting from ~1.3 s to 0.75 s on a task 📰 [P36]).
4. Small state: only on-screen items, downsized frames.
5. Independent checks with on-device OCR instead of another AI call.
6. Absolute pointer positioning if T1 shows it works (skips pointer correction).
7. **Keyboard first, pointer last** _(added 2026-11-02; T1b 2026-11-03: Search, Return and Tab ✅, Fn ❌)_: ⌘+Space opens Search, so we open any app by typing its name + Enter (no icon hunt, no AI step); ⌘H for Home (✅ works, T1); Return to send messages where the app allows it (skips the icon-only Send button); Full Keyboard Access commands for App Switcher, Control Center and Notification Center (Apple's defaults use Fn/🌐, which our device can't send yet, so we remap them under **Commands**) [P42].
8. **Extra mouse buttons as shortcuts** _(✅ works, T1b 2026-11-03)_: give the device buttons 4, 5, 6… and assign each to a system action (App Switcher, Notification Center, Control Center, Siri) under AssistiveTouch → Devices → **Customize Additional Buttons**. One button report, no pointer move.
9. **iPhone settings tuned for speed:** Tracking Sensitivity max (fewer reports per move), Haptic Touch **Fast** (shorter long presses), **Prefer Single-Touch Actions** (taps instead of slides, iOS 26.1+). Full checklist for users: [README → Set up your iPhone](../../README.md#-set-up-your-iphone-for-mantiza).

The user's own time (~6–12 s) becomes the biggest share; reusing the screen-capture session (T4) is the next win.

### 4.5 Fast path: "Shortcuts first, taps last" _(idea)_
Before tapping, use direct routes where they exist:
- **Contacts** (with permission) to find "Azad" and his number.
- **App links** to open an app at the right screen.
- **Shortcuts** for system actions (alarms, Focus, settings).
- **Taps** only for what is left.

This cuts the number of AI-driven steps, which makes tasks faster, cheaper and less error-prone _(estimate)_.

### 4.6 Background and permissions
| Need | How | Fact |
|---|---|---|
| Keep capturing while other apps are in front | `screen-capture` background mode | ✅ [P5][P6] |
| Keep talking to the device in the background | `bluetooth-central` background mode | ✅ [P5] |
| Screen recording permission | `NSScreenCaptureUsageDescription` + system picker | ✅ [P4] |
| Live progress outside the app | Live Activity / Dynamic Island | ✅ (used by existing projects 📰 [P1]) |
| Microphone, speech, contacts | Standard iOS permissions | ✅ |

### 4.7 Known app limits
- The phone must stay **unlocked**; locking or revoking sharing pauses the task 📰 [P2].
- **Protected video** is blacked out in captures [P16]; apps can detect capture (`sceneCaptureState`) and may hide content [P16].
- **Landscape apps** are not supported by existing projects 📰 [P1][P2]; we start with portrait only.

---

## 5. Part 2: the personalised workflow widget

### 5.1 What it does
A home screen widget that lists **your usual workflows**, grouped in **tabs**, showing each one in short form, with **one tap to run**.

Example (large widget):
```
┌────────────────────────────────────────┐
│ Mantiza          [Now] [Morning] [Week]│
│ ────────────────────────────────────── │
│ 🛒 Order usual groceries      ▶ Run    │
│ 💬 Tell Mum "on my way"       ▶ Run    │
│ 🚕 Book ride to office        ▶ Run    │
│ 🎵 Play focus playlist        ▶ Run    │
│ "You usually do this around 9:00"      │
└────────────────────────────────────────┘
```

### 5.2 How it works (confirmed by Apple's documentation [P9])
- **Tabs:** each tab is a `Button(intent:)` that saves the selected tab and returns. "Interactions with a toggle or button always guarantee a timeline reload", so the widget redraws with the new tab, **without launching the app**.
- **Run:** a workflow needs screen capture, which runs in the app, so the Run control is a **`Link`** that opens Mantiza at that workflow (`widgetURL`/`Link`). Apple notes buttons are meant to do more than open the app; to open the app, use `Link` or `widgetURL` [P9].
- **Sizes:** buttons and toggles work in `systemSmall`, `systemMedium`, `systemLarge`, `systemExtraLarge`, `systemExtraLargePortrait`, and the Lock Screen's `accessoryCircular` and `accessoryRectangular` [P9].
- **Locked phone:** "buttons and toggles are inactive until the person authenticates" [P9].
- **Data:** the app and widget share storage through an App Group _(standard iOS pattern)_.

### 5.3 Layout per size _(idea)_
| Size | Content |
|---|---|
| Small | The single best workflow for right now, one tap |
| Medium | 2–3 workflows for "Now" |
| Large | Tabs (Now / Morning / Week / Favourites) with 4–5 workflows each |
| Extra large (portrait) | A daily timeline: what you usually do at each time of day |
| Lock Screen | One-tap "best next workflow" |

### 5.4 Personalisation _(idea)_
- Every completed task is logged locally: workflow, time of day, day of week, day of month, success.
- Score each workflow with simple counts per time bucket, weighted towards recent use (no training, explainable: "You usually do this on Sundays around 10").
- Tabs: **Now** (highest score for this time), **Morning / Evening**, **This week**, **Favourites** (pinned).
- All learning stays **on the phone**.

### 5.5 Widget limits
- Running a workflow **opens the app** (screen capture needs it) ❓ whether an already running capture session can be reused to avoid the picker each time.
- Widgets refresh on the system's schedule; taps always reload [P9].

---

## 6. Part 3: languages (English now, Hindi later)

### 6.1 Version 1: English only
| Area | How | Status |
|---|---|---|
| Chat | Typed English; the big brain understands it | ✅ |
| Voice | Apple speech recognition (`SpeechTranscriber`) in English; check `supportedLocales` on device | ✅ English supported [P12] |
| Fast picker | Jev is strongest in English [P31] | ⚠️ test T11 |
| Typing into apps | The device types the text with keyboard key codes, as existing projects do [P1][P2][P3]. **Known issue:** capital letters and symbols may fail over Bluetooth on a combined mouse + keyboard 📰 (Fake Mouse doc, item 8). **Fallback:** clipboard + ⌘V paste (section 6.4, Method A) | ✅ Worked in T1 (2026-11-02) |
| Device screen | English labels only; no special font needed | ✅ |

**Walkthrough: "Mantiza, reply to Azad that I'm coming"** (times in section 4.4)
1. **Start:** press A on the device, the widget, or the app; speak the request.
2. **Understand (big brain):** subtask `{app: Messages, contact: Azad, text: "I'm coming", allowed_risks: [send]}`.
3. **Fast path:** look up Azad in Contacts; exactly one match, otherwise ask.
4. **Screen capture** starts (system picker).
5. **Open Messages** (app link).
6. OCR list shows `[n] "Azad"` → **Jev** picks it → freshness check → device taps.
7. OCR list shows the message box → Jev picks it → device taps → device **types "I'm coming"** (or pastes, if typing fails).
8. **Safety gate:** device screen shows "Send to Azad: I'm coming? A = Send · B = Cancel"; phone shows the same.
9. On approve → Send is an icon, so the **big brain** finds it on the first run (learned after that) → device taps Send.
10. **Check:** OCR confirms "I'm coming" appears in the chat → device shows "✓ Sent"; run saved as a learned workflow.

### 6.2 Later: Hindi chat (text)
- Users can type in Hindi (Devanagari), English or Hinglish (Hindi in Latin letters).
- Apple Intelligence does **not** support Hindi [P13]; the **cloud model** (our main brain) handles Hindi and Hinglish, and also converts Hinglish to proper Hindi script when needed ("mai aa rha hu" → "मैं आ रहा हूँ").

### 6.3 Hindi voice (later)
| Option | Hindi? | Notes |
|---|---|---|
| Apple `SpeechTranscriber` (newer API) | ❌ appears not supported 📰 [P12] | Check `supportedLocales` on device |
| Apple `SFSpeechRecognizer` (older API) | ✅ `hi-IN` appears in sample output 📰 [P11] | Check `supportedLocales()` on device |
| Apple Dictation | ✅ Hindi (India) listed [P10] | System dictation in text fields |
| Cloud speech-to-text | ✅ (many providers support Hindi) | Fallback for noisy audio or mixed Hindi-English |

**Plan:** use `SFSpeechRecognizer` for Hindi if `hi-IN` is available on the device, otherwise cloud speech-to-text.

**Wake word "Mantiza":** iOS does not let an app listen for a custom wake word while closed (Siri only). Users start Mantiza from the app, the widget, the device button, or Siri/Shortcuts. Note: Siri AI is English-first in iOS 27 [P13].

### 6.4 Typing Hindi into other apps (the hard part)
The device types by sending **keyboard key codes**, not letters. All existing projects are English-only for this reason [P1][P2][P3]. Two ways around it:

**Method A: copy and paste (recommended) _(idea)_**
1. Mantiza puts the Hindi text on the clipboard.
2. The AI taps the message box.
3. The device sends **⌘V** (Command-V).

Why it should work:
- ✅ Apple: the system "determines user intent based on user interactions, such as tapping a system-provided control or pressing Command-V", so pasting with ⌘V does **not** trigger the paste alert [P14].
- 📰 Key combinations work over Bluetooth from an ESP32-S3 [P8].
- Works for **any language and emoji**, because it pastes finished text; no Hindi keyboard needed.

Open questions:
- ❓ Can Mantiza write to the clipboard **while in the background**? Apple's page does not say [P14]. **Workaround:** write the text while Mantiza is still in front, before switching to the target app (we know the message text before we start).
- ❓ Does ⌘V paste in every app's text box (Messages, WhatsApp, etc.)?
- Privacy: set the clipboard item to **expire** quickly and keep it **local only** (no Handoff to other devices); Apple supports both (`expirationDate`, `localOnly`) [P14].

**Method B: Hindi hardware keyboard layout (fallback)**
- iPhone lets you choose a layout for an external keyboard per language (Settings → General → Keyboard) [P18].
- Community reports describe Hindi **INSCRIPT** and **Devanagari QWERTY** layouts on iOS 📰 [P19]. The device would send INSCRIPT key codes and switch language with a key combo.
- Downsides: user setup, layout names vary by iOS version 📰 [P19], harder for complex Hindi spelling.

### 6.5 Walkthrough (later): "Mantiza, Azad ko reply karo ki mai aa rha hu in Hindi"
1. **Voice → text:** Hindi/Hinglish speech recognised (section 6.3).
2. **Understand (cloud model):** reply to contact "Azad", in Messages, text "मैं आ रहा हूँ".
3. **Fast path:** look up Azad in Contacts (permission); check there is exactly one match, otherwise ask.
4. **Prepare:** write "मैं आ रहा हूँ" to the clipboard (expires in 2 minutes, local only), while Mantiza is still in front.
5. **Screen capture** starts (system picker).
6. **Open Messages** (app link) → AI finds Azad's conversation (OCR finds "Azad") → device taps it.
7. AI taps the message box → device sends **⌘V** → Hindi text appears.
8. **Safety gate:** sending a message to someone needs approval: the phone shows a notification and the **device screen** shows "Send to Azad: मैं आ रहा हूँ? A = Send, B = Cancel".
9. On approve → device taps Send → next frame confirms the message appears.
10. Done: device screen shows "✓ Sent", run saved, "Reply to Azad" pattern updated.

---

## 7. Part 4: the Mantiza device

### 7.1 Prototype hardware: M5Stack M5StickS3 (ready-made, battery and screen built in)
Facts from M5Stack's documentation [P15]:

| Feature | M5StickS3 |
|---|---|
| Chip | ESP32-S3-PICO-1-N8R8, dual-core 240 MHz; 8 MB flash, 8 MB PSRAM |
| Bluetooth | ESP32-S3 has Bluetooth 5 (LE) [P20] |
| Battery | 250 mAh lithium, power chip M5PM1 |
| Screen | 1.14" LCD, 135 × 240, ST7789P3 |
| Buttons | 2 programmable buttons (KEY1, KEY2); single click power on, double click power off |
| Motion sensor | BMI270 6-axis IMU |
| Audio | MEMS microphone; 1 W speaker with amplifier and ES8311 codec |
| Other | IR transmitter + receiver; Hat2 and Grove expansion ports |
| Size / weight | 48 × 24 × 15 mm, 20 g |
| Software | Official Arduino support with the M5Unified (≥ 0.2.12) and M5GFX libraries [P21] |

**Not yet known:** battery life while running Bluetooth mouse + screen ❓ (one buyer reports only about 4 hours on standby 📰 [P22]). It has not been tested with an iPhone as a Bluetooth mouse by anyone we found ❓, although it uses the same chip family as projects that have [P8].

**Later (own product):** a custom enclosure around an ESP32-S3 module with a bigger battery and the same features, once the prototype proves the design.

### 7.2 What the device does
| Function | How | Status |
|---|---|---|
| **Hands:** mouse + keyboard | Bluetooth HID (mouse with absolute positioning if it works, keyboard for keys and ⌘V) | 📰 proven on ESP32-S3 [P8] |
| **Command channel** | Our own Bluetooth service that the app writes commands to (`move`, `click`, `paste`, `home`, `status`) | 📰 app and system HID share the board [P8] |
| **Live status screen** | Shows what Mantiza is doing | _(idea)_ |
| **Physical approve / cancel** | Button A = approve, Button B = cancel, during an approval step | _(idea)_ |
| **Emergency stop** | Shake the device (IMU) or long-press B | _(idea)_ |
| **Sound feedback** | Short beeps: started, needs approval, done, error | _(idea)_ |
| **Firmware updates without a cable** | Espressif's `ble_ota` component (update over Bluetooth) [P23] | ✅ component exists; not tested by us |

### 7.3 Screen designs (135 × 240) _(idea)_
| State | What the screen shows |
|---|---|
| Idle | Mantiza logo, battery %, connected ✓, "Next: Order groceries? (A)" |
| Running | App icon/name, "Step 3/7: Opening chat with Azad", progress bar |
| Typing | "Typing: I'm coming" |
| Needs approval | "Send to Azad? A = Send · B = Cancel" (also on the phone) |
| Done / Error | "✓ Sent" or "✗ Couldn't find Azad. Check phone" |
| Pairing | Device name and a short pairing code |
| Low battery | Battery warning and "Charge me" |

**Note on Hindi on the device screen (later):** showing Devanagari needs a Hindi font in the firmware ❓ (font size and rendering on a 135 × 240 screen must be tested). Fallback: show English labels on the device and Hindi on the phone.

### 7.4 More ideas for the device _(ideas, to evaluate)_
1. **Physical "run my next workflow" button:** on idle, press A to run the top suggestion from the widget's "Now" tab.
2. **Push-to-talk from the device:** hold A and speak into the device's microphone; audio is sent to the phone over Bluetooth for recognition. ❓ Bluetooth bandwidth, audio quality and background handling must be tested. (The original project already streams video over Bluetooth at about 100–350 kbps, suggesting audio is within reach 📰 [P1 issue #12].)
3. **On-device wake word:** Espressif's ESP-SR WakeNet runs on ESP32-S3 [P24], but a custom word like "Mantiza" requires Espressif's customisation process, and Espressif says to own the rights before commercial use [P24]. Later option only.
4. **Haptic-style feedback with the speaker:** different tones for approve/cancel.
5. **"Find my phone/device":** play a sound on either one.

### 7.5 Battery and power plan
- Turn the screen off after a few seconds of no change; wake on button or new status.
- Deep sleep between tasks; wake on button. Measure real current draw and runtime first ❓.
- Show battery % on the device and in the app.

---

## 8. Learned workflows: record once, run fast _(idea)_

1. **First run:** the AI does the task step by step; Mantiza records each step as **intent + target text** (e.g. "tap chat named Azad", "tap text box", "paste", "tap Send"), not just pixel positions.
2. **Saved workflow:** shown in the widget, with parameters ("message text", "contact").
3. **Next runs:** Mantiza replays the steps, using OCR to find the same targets on the current screen, and calls the AI only when the screen does not match.
4. **Benefit:** fewer AI calls → faster, cheaper, more reliable _(estimate)_.

---

## 9. Safety and privacy

| Rule | How |
|---|---|
| **Never touch sensitive apps** | Block list: banking, UPI and payment apps, password managers and authenticators, Wallet, Health, government ID. If the screen shows one of these (detected by app opened + OCR), stop |
| **Ask before anything that cannot be undone** | Sending messages, posting, buying, deleting: approval on phone **and** device screen |
| **Payments stay with the user** | Mantiza never types card numbers, PINs or OTPs; the user completes payment |
| **Always stoppable** | Stop in app, Dynamic Island, device button, or shake |
| **Screen data** | Screenshots go to the cloud model only with clear consent (disclosed by name: Anthropic or Google); send downsized frames; never capture blocked apps; never store full video, only selected step images (deletable) |
| **Clipboard** | Expiring, local-only items [P14] |
| **Prompt injection** | Treat text read from the screen as data, never as instructions; sensitive actions always need approval. Jev does not treat state as hostile by default [P32], so it only ever picks from our list |
| **Risky items hidden from the picker** | Send, Delete, Buy, Pay, Post are left out of Jev's list unless the subtask allows them, and the app refuses such taps without approval _(idea, pattern from arc-cua [P36])_ |
| **No blind retries** | Never repeat an action after an uncertain failure (e.g. Send), so nothing is sent or ordered twice _(pattern from mobile-jev [P35])_ |
| **Literal text only** | The picker never invents text; message text comes only from the user's request via the big brain. Missing input → ask the user |
| **AI providers disclosed** | Consent screen names every company that receives data: Anthropic or Google (screenshots), TypeSafe (on-screen text list) [P33] |
| **Device security** | Bond only with the owner's phone; signed commands on our channel; reject commands when not bonded |

---

## 10. Tech stack

| Area | Choice | Notes |
|---|---|---|
| iOS app | Swift 6, SwiftUI, iOS 27+ | ScreenCaptureKit on iPhone needs iOS 27 [P4] |
| Screen capture | ScreenCaptureKit (`SCContentSharingPicker`, `SCStream`) | ✅ [P4] |
| Bluetooth | Core Bluetooth (`bluetooth-central` background mode) | ✅ [P5] |
| AI (big brain) | Claude (Sonnet 5.5 / Haiku 5.5) or Gemini (3.8 Flash), via Foundation Models' `LanguageModel` protocol | ✅ [P17][P27][P28] |
| AI (fast brain) | TypeSafe Jev (`jev-latest` → `jev-1.14.0`) via its HTTPS API, called through our backend | [P31]; pending T11 |
| AI (helpers) | Apple OCR tool; optional Apple on-device model / PCC for small English jobs | ✅ [P17] |
| OCR | Foundation Models `OCRTool` / Vision framework | ✅ [P17] |
| Speech | v1: `SpeechTranscriber` (English). Later: `SFSpeechRecognizer` (Hindi) + cloud fallback | 📰 [P11][P12] |
| Widget | WidgetKit + App Intents (`Button(intent:)`, `Link`) | ✅ [P9] |
| Live progress | ActivityKit (Live Activity, Dynamic Island) | ✅ |
| Storage | SwiftData in an App Group (shared with the widget) | standard |
| Backend | Small token service for cloud AI keys | per Apple's guidance on keys [P17] |
| Device firmware | Arduino (ESP32 core) or ESP-IDF; NimBLE-Arduino (supports ESP32-S3) [P25]; M5Unified/M5GFX for screen and buttons [P21]; `ble_ota` for updates [P23] | |
| Device hardware | M5StickS3 (prototype) [P15] → custom ESP32-S3 device (later) | |

---

## 11. Roadmap

Dates assume the team starts on 2026-11-02 _(estimate)_.

### Phase 0: Prove the risky parts (2 weeks)
| # | Test | Pass condition |
|---|---|---|
| T1 | M5StickS3 as Bluetooth mouse + keyboard with iPhone (iOS 27) | Pointer reaches any point accurately; English typing works **including capitals and symbols**; ⌘V works <br>**Result (2026-11-02): ✅ PASS.** All 8 tests worked on iPhone 14 Plus (iOS 27.2), including capitals, symbols, ⌘V and ⌘H. Pointer moves are repeatable, and it reconnects after a device restart and after iPhone lock/unlock ([results](../../firmware/t1-hid-test/README.md#results)) |
| T1b | **Keyboard shortcuts and extra buttons** (section 4.4, items 7–8) | ⌘+Space opens Search and an app opens by name; Return sends in Messages; which Full Keyboard Access commands work and can be remapped; whether extra mouse buttons can be assigned to system actions<br>**Result (2026-11-03): mostly ✅.** ⌘+Space Search, Return to send, Tab and extra buttons 4–5 work. Fn/🌐 from our device is ignored, so Fn+H/C/N/↑ fail; remapping still to test ([results](../../firmware/t1-hid-test/README.md#t1b-results)) |
| T2 | App ↔ device command channel while iOS uses the device as a mouse | Commands arrive while the app is in the background<br>**Result (2026-11-05): ✅ PASS (main question).** The app gets the device from iOS's already-connected list while AssistiveTouch uses it. Ping avg 52 ms (max 94). Device-to-app asks answered 96/96, 53 with the app in the background, ~81 ms each. Typing and pointer moves from the app work. Locked phone ✅, and the app's own 5 s timer kept sending from the background ✅ ([results](../../firmware/t1-hid-test/README.md#t2-results)) |
| T3 | ScreenCaptureKit with `screen-capture` background mode | Capture keeps running while another app is in front for 5+ minutes; record what happens on lock<br>**Result (2026-11-05): ✅ PASS.** Capture kept running for 5+ minutes with other apps in front, and the frames showed those apps. Bluetooth (T2 heartbeat) kept running alongside. **Locking the phone stops the capture** (iOS ends it). A red recording indicator shows while capturing ([results](../../apps/phase0-test/README.md#t3--t4-results)) |
| T4 | Picker behaviour | Does it ask every task, or can a session be reused?<br>**Result (2026-11-05): the picker is needed for every new capture.** A stopped capture can't be restarted with the saved choice (start failed), and Start shows the picker again. **Design consequence:** start capture once and **keep it running** between tasks instead of starting per task; the picker is then needed only after a lock or a stop (about once per phone unlock).<br>**T4d (2026-11-06): ✅ the device presses the picker itself.** From the Home Screen with no touch: the device opens the app through Search, the app shows the picker, the device clicks "Share Entire Screen" ("shared ok 4.1s"). Pointer calibration: 1 count = 4.37 pt at the highest tracking speed, 0 pt error, when moving across then down in equal steps. **So the user never taps the picker** while the phone is unlocked ([results](../../apps/phase0-test/README.md#t3--t4-results)) |
| T8 | **Big brain:** Gemini 3.8 Flash vs Claude Sonnet 5.5 vs GPT-6.1 Terra (thinking off per step) with Apple OCR text added, on 20 English tasks, called from India | Success rate, seconds per step, cost per task; pick the big brain. Candidates and reasons: [AI brain research (2026-11-06)](ai-brain-research.md) |
| T9 | Device battery life with Bluetooth + screen | Hours of use and standby |
| T11 | **Fast brain: decision models** (Jev vs OpenAI Decisions API vs Cloudflare Clef, see [research](ai-brain-research.md)) vs big brain on ~20 real English app screens: Jev with the OCR-built list vs Claude/Gemini with the screenshot | Seconds per decision (measured from India), correct pick rate, how often icon-only buttons force a fallback. **Pass:** Jev about as accurate and clearly faster → keep two brains; otherwise big brain only |
| T12 | **End-to-end timing** of the Azad task (section 4.4) | Real seconds for each stage, first run and learned run, logged per request |

**Build route for the test apps (2026-11-05):** ✅ the T2/T3/T4 test app can be built on **Windows with [xtool](https://github.com/xtool-org/xtool)**, no Mac needed. A "Hello" app built, installed and ran on the iPhone ([setup](../Setup/windows-xtool-setup.md)). A Mac or cloud Mac is still needed for the widget (open xtool bugs) and for TestFlight/App Store.

**Exit:** every test has a recorded result; design updated where something failed.

**Later (Hindi phase, not Phase 0):**

| # | Test | Pass condition |
|---|---|---|
| T5 | **Hindi paste** | Clipboard written before switching apps; ⌘V pastes "मैं आ रहा हूँ" into Messages and WhatsApp |
| T6 | Clipboard write from the background | Works or not (decides the design in 6.4) |
| T7 | `SFSpeechRecognizer` `hi-IN` on device | Hindi and Hinglish recognised acceptably |
| T10 | Hindi font on the device screen | Readable Devanagari on 135 × 240 |
| T13 | Jev and big brain on Hindi / Hinglish screens | Accuracy close to English, or Hindi steps go to the big brain only |

### Phase 1: Core agent, English (6 weeks)
- App: English chat + voice, agent loop with two brains, OCR list, freshness check, wait-for-settle, fast path (Contacts, app links), safety gate, Live Activity.
- Device firmware: Bluetooth mouse + keyboard, command channel, status screen, approve/cancel buttons, shake to stop.
- **Exit:** 30 English tasks (including "reply to Azad that I'm coming") succeed at least 80% of the time on our phones; median time per step recorded.

### Phase 2: Widget and learned workflows (4 weeks)
- Save workflows, record-once replay, personalisation scores, widget in all sizes with tabs, device "run next workflow" button.
- **Exit:** widget's "Now" tab shows a workflow the tester actually wanted at least half the time after 1 week of use _(target)_.

### Phase 3: Polish and private beta (4 weeks)
- **Hindi** (sections 6.2–6.5, tests T5–T7, T10, T13), then more languages, push-to-talk on device (if T-tests allow), firmware updates over Bluetooth, battery tuning, privacy screen.
- **Exit:** 10–20 trusted testers using it daily for 2 weeks.

### Phase 4: Own hardware and distribution decision (later)
- Custom device design; decide on distribution (TestFlight, enterprise, App Store attempt) based on what we learn.

---

## 12. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Jev is not accurate enough on OCR-built lists, or slow from India | Speed gain lost | T11 decides; fall back to big brain only (section 4.3.1) |
| Icon-only buttons (Send, back) are missing from the OCR list | More big-brain calls, slower first runs | Learned workflows remember them; icon detection later |
| Jev is a young vendor (models from Sept–Oct 2026); speed figures are self-reported 📰 | Service changes or shuts down | Keep the picker behind our own interface so it can be swapped (e.g. a small fast cloud model) |
| Capital letters / symbols fail when typing over Bluetooth 📰 | Wrong text typed | Test in T1; paste fallback |
| (Later) Hindi paste does not work in some apps | Hindi typing fails there | Method B (Hindi hardware layout); show "paste failed" and ask the user |
| Screen capture stops in the background or on lock | Tasks break | Keep phone awake during tasks; resume from the same step (as existing projects do 📰 [P1]) |
| Chosen cloud model underperforms or changes | Lower success | Swap between Claude and Gemini through the same interface [P17] |
| Cloud AI cost and privacy | Cost per task; screenshots leave the phone | Downsized frames + OCR text; record-once replay (section 8) to cut AI calls; clear consent; block list |
| Gemini's mobile computer use is Preview and Android-optimised | May behave worse on iPhone screens | Compare in T8; Claude as alternative [P27][P28] |
| Taps land in the wrong place | Wrong actions | Absolute positioning, OCR targets, verify every step, approval before irreversible actions |
| User has **Confirm with AssistiveTouch** on | The device could approve Apple Pay or purchases | Setup checklist says Off ([README](../../README.md#-set-up-your-iphone-for-mantiza)); the device never sends the confirm action |
| **Dwell Control** or **Snap to Item** on | Accidental taps while the AI thinks; pointer lands off target | Setup checklist says Off; the app checks taps land where expected |
| Battery life too short | Device dies mid-task | Screen sleep, deep sleep, larger battery in the custom device |
| Other apps' terms of use | Accounts flagged for automation | Personal use first; avoid social media automation (one project reports shadow-bans 📰 [Fake Mouse doc]) |
| Fast-moving competition | Others add similar features | Focus on our differences: speed (two brains), widget, safety, dedicated device, then languages |

---

## 13. Open questions for the team
1. Who owns firmware (device) vs iOS app development?
2. Which cloud model is the big brain: Claude or Gemini? (Test both in T8.)
3. Do we keep Jev as the fast brain? (Decided by T11.)
4. When do we start Hindi, and which language comes after it?
5. Do we buy 2–3 M5StickS3 units for Phase 0?

---

## 14. Legal note
We write **our own code**. Existing projects ([P1][P2][P3]) are used only as **reference**. One of them ([P3]) has **no license**, so we must not copy its code at all; the others are MIT, with a GPL-3.0 AirPlay part in the original that we do not need. The Jev-based projects ([P34]–[P38]) are all MIT and used only as reference for design patterns; using Jev itself means accepting TypeSafe's terms [P33]. _(Not legal advice.)_

---

## 15. Sources

| # | Source |
|---|---|
| P1 | [onehumanbeing/esp32-iphone-agent (original project, README and issues)](https://github.com/onehumanbeing/esp32-iphone-agent) |
| P2 | [await-ovo/esp32-iphone-agent (Bluetooth + ScreenCaptureKit fork)](https://github.com/await-ovo/esp32-iphone-agent) |
| P3 | [boboabw/phone-agent](https://github.com/boboabw/phone-agent) |
| P4 | [Apple: ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) |
| P5 | [Apple: Configuring background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes) |
| P6 | [Apple Developer Forums: iOS 27 `screen-capture` background mode (Apple staff reply)](https://developer.apple.com/forums/thread/840821) |
| P7 | [Apple Support: Use a pointer device with AssistiveTouch](https://support.apple.com/en-us/111775) |
| P8 | [Issue #104 in jinwon-int/esp32-iphone-agent (a fork of P1): Bluetooth mouse + keyboard device test, Oct 27, 2026](https://github.com/jinwon-int/esp32-iphone-agent/issues/104) |
| P9 | [Apple: Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) |
| P10 | [Apple: iOS and iPadOS 27 Feature Availability](https://www.apple.com/ios/feature-availability/) |
| P11 | [SFSpeechRecognizer supported locales sample output (MBS plugins)](https://mbsplugins.eu/SpeechRecognitionSupportedLocales.shtml) and [Apple: supportedLocales()](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportedlocales()) |
| P12 | [SpeechAnalyzer guide listing SpeechTranscriber languages](https://swiftcrafted.dev/article/speechanalyzer-speechtranscriber-ios-26-swift) |
| P13 | [Apple Newsroom: Major updates for Apple's software platforms (Sept 2026)](https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/) |
| P14 | [Apple: UIPasteboard](https://developer.apple.com/documentation/uikit/uipasteboard) |
| P15 | [M5Stack: StickS3 documentation](https://docs.m5stack.switch-science.com/en/core/StickS3) |
| P16 | [Apple: UIScreen.isCaptured (FairPlay content blacked out; use sceneCaptureState)](https://developer.apple.com/documentation/uikit/uiscreen/iscaptured) |
| P17 | [Apple WWDC26: What's new in the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/) |
| P18 | [Apple Support: Add or change keyboards on iPhone](https://support.apple.com/guide/iphone/add-or-change-keyboards-iph73b71eb/ios) |
| P19 | [Apple Community: iOS Hindi Devanagari keyboard](https://discussions.apple.com/thread/250713767) and [Typing Hindi on iPhone (INSCRIPT)](http://theweirdindian.blogspot.com/2012/04/typing-hindi-marathi-sanskrit-on-iphone.html) |
| P20 | [Espressif: ESP32-S3](https://www.espressif.com/en/products/socs/esp32-s3) |
| P21 | [M5Stack: StickS3 Arduino docs (M5Unified, M5GFX)](https://docs.m5stack.com/en/arduino/m5sticks3/speaker) |
| P22 | [Botland: M5StickS3 listing and review](https://botland.store/stick-series/27815-m5sticks3-iot-development-module-esp32-s3-pico-1-m5stack-k150-6972934171955.html) |
| P23 | [Espressif: ble_ota component](https://components.espressif.com/components/espressif/ble_ota) |
| P24 | [Espressif: ESP-SR component](https://components.espressif.com/components/espressif/esp-sr) |
| P25 | [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) |
| P26 | [Claude docs: Multilingual support](https://platform.claude.com/docs/en/build-with-claude/multilingual-support) |
| P27 | [Claude docs: Computer use tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool) |
| P28 | [Gemini API docs: Computer use](https://ai.google.dev/gemini-api/docs/computer-use) |
| P29 | [MacStories: iOS and iPadOS 27 review](https://www.macstories.net/stories/ios-and-ipados-27-review/4/) |
| P30 | [TypeSafe docs: System One (what Jev is and is not)](https://docs.typesafe.ai/concepts/system-one.md) |
| P31 | [TypeSafe docs: Models (versions, price, context, languages)](https://docs.typesafe.ai/models.md) |
| P32 | [TypeSafe docs: Jev 1.13 jaggedness (known weaknesses)](https://docs.typesafe.ai/model-jaggedness/jev-1.13.md) |
| P33 | [TypeSafe docs: Legal (data retention, training)](https://docs.typesafe.ai/legal.md) |
| P34 | [browser-use/jev-ultrafast](https://github.com/browser-use/jev-ultrafast) and its [performance notes](https://github.com/browser-use/jev-ultrafast/blob/main/docs/performance.md) |
| P35 | [droidrun/mobile-jev (Android agent with Jev)](https://github.com/droidrun/mobile-jev) |
| P36 | [shhivv/arc-cua](https://github.com/shhivv/arc-cua) and its [benchmarks](https://github.com/shhivv/arc-cua/blob/master/BENCHMARKS.md) |
| P37 | [kerpopule/hermes-jev-skills](https://github.com/kerpopule/hermes-jev-skills) |
| P38 | [wy-coliney/jev-browser-use](https://github.com/wy-coliney/jev-browser-use) |
| P39 | [AndroidDaily: benchmark for mobile GUI agents on real apps (arXiv 2605.27761)](https://arxiv.org/html/2605.27761v1) |
| P40 | [AppAgentX: evolving GUI agents (arXiv 2503.02268)](https://arxiv.org/html/2503.02268v3) |
| P41 | [TypeSafe docs: Images (preview)](https://docs.typesafe.ai/images.md) |
| P42 | [Apple Support: Control iPhone with an external keyboard (Full Keyboard Access)](https://support.apple.com/en-bn/guide/iphone/ipha4375873f/ios) |
