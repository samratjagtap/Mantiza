# Start from anywhere, live progress, voice, habits, weak internet (research and build, 2026-11-16)

Five additions around the core loop: more ways to start a task, seeing it while it runs, hearing the
result, a widget that knows your habits, and working sensibly on a weak connection.

Tags: **[Built]** = in the app, not yet run on the iPhone · **[Needs one step]** = built, waits on the
App Intents index (section 1) · **[Measured]** = our own numbers · **[Docs]** / **[Source]** = where a fact comes from.

## 1. The catch: Siri and buttons need an index that only a Mac writes

Everything where iOS runs one of Mantiza's actions (a Siri phrase, a Shortcuts action, a Control Centre
button, a button on a Live Activity) goes through **App Intents**. iOS only lists an app's actions from
an index inside the app, `Metadata.appintents`. Xcode writes it with Apple's
`appintentsmetadataprocessor`, which only runs on a Mac **[Source: [xtool PR #397](https://github.com/xtool-org/xtool/pull/397)]**.
Mantiza is built on Windows, so actions compile and install but would never show up.

Ways around it:

| Way | State |
|---|---|
| **Our own index writer** | Chosen. It reads the compiler's constant values, which our build already produces, and writes the index in the format iOS reads. **Not written yet.** |
| xtool PR #397 (the same idea inside xtool) | An unreviewed draft; no actions with parameters, so no "Ask Mantiza &lt;request&gt;" |
| Build the index once on a Mac and ship it | Needs a Mac for every change to the actions |

**State:** the actions are written and `scripts/make_intents.py` is ready to call the writer, but the
writer itself isn't written yet (an outside tool was tried, then removed on 2026-11-17: Mantiza uses
only its own code). The index isn't packed into the app. Until
it is, everything below marked **[Needs one step]** falls back to a link that opens Mantiza.

## 2. Start Mantiza from anywhere

| Way in | How | State |
|---|---|---|
| Microphone in the app | Tap, speak, stop talking: it runs | **[Built]** |
| Lock Screen circle widget | Opens Mantiza listening (`mantiza://listen`) | **[Built]** |
| Widget task buttons | A tap opens Mantiza and runs the task at once (they already did) | Already there |
| "Hey Siri, ask Mantiza" | Siri asks what to do, then hands it to Mantiza, which answers out loud | **[Needs one step]** |
| Control Centre / Lock Screen control / Action Button: "Talk to Mantiza" | Opens Mantiza listening | **[Needs one step]** |
| Shortcuts action "Ask Mantiza" | For automations: a time of day, arriving home, an NFC tag, Back Tap | **[Needs one step]** |

Notes:
- **A widget can't run a task without opening Mantiza**, and it shouldn't try: tasks need the app in
  front to start screen sharing and to open other apps by their links. So the tap opens Mantiza and the
  task starts with no second tap.
- **Siri can't take a free sentence inside the phrase** ("Hey Siri, Mantiza order pizza"): Apple only
  allows fixed choices inside a phrase, not open text. So it is two turns: "Ask Mantiza" → "What's the
  request?" → you say it.
- **Siri hears the name better with help:** the app lists "Mantisa" and "Mantis" as other spellings of
  its name, with a pronunciation hint (`INAlternativeAppNames`).
- **The iPhone 14 Plus has no Action Button.** There, the same control goes in Control Centre or on the
  Lock Screen, or Back Tap runs the Shortcuts action.

## 3. Live progress **[Built]**

A Live Activity shows the running task on the Lock Screen and as a banner; on iPhones with a Dynamic
Island, there too (the 14 Plus has a notch, so no island).

Practice followed **[Docs: Apple ActivityKit; WWDC 2026 session 223]**:
- **Started while Mantiza is in front** (iOS requires it), then updated by the app itself as it works in
  the background. No server and no push are needed.
- **At most one update every 0.7 s.** Steps change faster than anyone reads, and iOS may drop updates that
  come too often.
- **Every update has a "stale" time 3 minutes ahead.** If the app is ever killed mid-task, the Lock Screen
  says "no update for a while" instead of showing "working" forever.
- **The result stays a minute** (3 minutes after a failure), then leaves.
- **Small state:** one line of text and a phase (working, waiting for you, done, failed, stopped).
- **Stop button:** stops the task without opening Mantiza **[Needs one step]**; until then it opens Mantiza
  and stops.

## 4. Voice **[Built]**

**Speaking.** Apple's built-in voice (`AVSpeechSynthesizer`): free, on the phone.
- It picks the best voice installed for the phone's language (premium, then enhanced, then standard).
  Better voices are a free download: Settings → Accessibility → Read & Speak → Voices.
- Other audio gets quieter while Mantiza speaks, then comes back.
- It can speak while another app is in front (the app's `audio` background mode).
- **Default: only when you asked by voice** (the mic or Siri), like Siri's own automatic setting. Speech
  is heard even with the ring switch on silent, so "Always" is a choice (Device tab → Voice).
- It says the answer or a short confirmation, never the log details.

**Listening.** Apple's speech recognition (`SFSpeechRecognizer`), on the phone where the iPhone supports
it: private, and it works without internet.
- It stops by itself 1.5 s after your last word and runs what it heard.
- The newer `SpeechAnalyzer` API was not used: whether its transcriber runs on the iPhone 14 isn't
  documented, and Apple's guidance is to fall back to the older path anyway
  **[Source: [WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)]**.

## 5. A widget that knows your habits **[Built]**

- Mantiza keeps a list of the tasks that worked and when (the last 400, on the phone only; Device tab →
  Habits shows the count and can forget them).
- For any moment, a task is a **habit** if it worked on at least 2 different days within 90 minutes of that
  time of day. Its score grows when runs are closer in time of day, on the same weekday (or the same kind
  of day), and more recent (3 weeks old counts half).
- The widget's timeline holds **one entry per half hour for the next 8 hours**, each with that moment's
  tasks. iOS swaps them in without waking the app.
- Entries with a habit carry a higher relevance, so a Smart Stack turns to Mantiza at the right time.
- Habits show a small clock; the rest of the slots are recent tasks, then starters. The Task screen uses
  the same list.

## 6. Weak internet **[Built]**

"Weak" means Low Data Mode is on, or 2 of the last 3 per-step AI calls took over 3.5 s (they normally take
0.5–2 s). It ends by itself when calls are quick again.

| On weak internet | Why |
|---|---|
| One AI call per step (the big brain only) | Two uploads at once compete for the little upload there is |
| Lighter pictures (JPEG quality 0.35) | **[Measured]** 47–56 KB instead of 75 KB, and the big brain was as accurate: 77–78 of 82 at quality 45 and 30, against 76–78 at quality 70 |
| 15 s per call, and no second request | A second request would halve the upload for both |
| Stop after 2 unanswered calls, in plain words | Before: 3 × 40 s, then "Big brain didn't answer" |
| "No internet" said at once, before planning | |

A busy network type (mobile data or Wi-Fi) and the last call times are in the message, so a report shows
what the phone had.

## 7. Ideas alongside (not built)

| Idea | What it adds |
|---|---|
| Approve or decline from the Live Activity | "Send this message?" answered on the Lock Screen, without opening Mantiza |
| The request as a Spotlight action | Type "Ask Mantiza" in Search |
| "Back Tap" setup guide | Double-tap the back of the iPhone to talk to Mantiza (uses the Shortcuts action) |
| Time-based automations | "Every weekday at 8, ask Mantiza to …" through Shortcuts, no code |
| Habit insights in the app | "You usually order on Swiggy around 8 PM": a sentence, plus one tap to make it a widget button |
| Follow-up by voice | When Mantiza asks "Which Azad?", answer by speaking |
| A wake-up on the StickS3's button | Press the StickS3: Mantiza opens listening (the device already has a "share" command that opens the app) |
| Hindi and Hinglish voice | Apple's recogniser lists Hindi (India); the cloud brain already understands it |
