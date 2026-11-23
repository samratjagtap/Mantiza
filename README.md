# Mantiza

Mantiza is an **iPhone app** with an AI agent inside it. You tell it what you want by **voice or text**, and it gets it done across your phone: opening apps, jumping straight to the right screen, running multi-step workflows, and answering back. Its home screen widget learns your daily, weekly and monthly patterns and puts the workflows you are most likely to want right now one tap away.

This repo holds the app, the device firmware and the planning docs. Mantiza uses Google's [Artemis](https://github.com/google/artemis) as its baseline, so there is a doc set for each.

## What's built (as of 2026-11-16)

"Built" means the code is in the [app](apps/mantiza/README.md) and installs on the iPhone. Items marked *to check* haven't been confirmed in a real run on the phone yet.

| Area | What Mantiza does | State |
|---|---|---|
| **Siri's jobs go to Siri** | Alarms, timers, phone settings, weather, notes, music: the StickS3 holds the Siri key, types the request and reads Siri's answer ([research](Docs/Mantiza%20Roadmap/siri-ios27-research.md)) | Built; the hand-off was tested by hand, the app doing it alone is *to check* |
| **Chat** | The Task tab is a chat: requests and answers as messages, the steps folded under each answer, chats kept on the phone with History (search, delete). Follow-ups use the chat ("send it again") | Built, *to check* |
| **Direct iOS routes** | Calls, WhatsApp, SMS, email, directions, calendar, reminders, flashlight, brightness, device keys | Built |
| **AI screen route** | Looks at the screen and acts when nothing else can. Both brains are asked at once; a step should take about 1.5–3 s instead of 6–7 s ([speed research](Docs/Mantiza%20Roadmap/speed-research.md)) | Built; speed is an estimate, *to check* |
| **Gestures** | Tap, press and hold, type (with Return for search), scroll up and down, swipe left and right, back, several taps from one answer | Built, *to check* |
| **Learned routines** | A screen task that worked is replayed next time without AI; a repeated request reuses its plan | Built |
| **Voice in** | Microphone on the Task screen; the Lock Screen widget opens Mantiza listening | Built, *to check* |
| **Voice out** | Says the result when you asked by voice (Device → Voice) | Built, *to check* |
| **Live progress** | A Live Activity shows the running task on the Lock Screen and as a banner, with Stop | Built, *to check* |
| **Habit widget** | The widget and the Task screen offer what you usually ask around this time | Built, *to check* |
| **Weak internet** | Lighter pictures, one AI call per step, an early and plain "weak internet" stop | Built, *to check* |
| **"Hey Siri, ask Mantiza", Control Centre button, Shortcuts action** | Written as App Intents | **Not switched on:** iOS needs an index that only a Mac's tool writes; Mantiza's own writer for Windows isn't built yet |
| **Safety** | Asks before paying, buying, deleting or posting; stops instead of tapping when screen sharing is off or iOS paused it | Built |

Details for the newest group (ways in, voice, Live Activity, habits, weak internet): [research note](Docs/Mantiza%20Roadmap/entry-points-voice-live-research.md).

## Docs

| Topic | Mantiza | Artemis baseline |
|---|---|---|
| Plan: what it is and how it works | [plan.md](Docs/Mantiza%20Roadmap/plan.md) | [plan.md](Docs/Google%20Artemis%20Analysis/plan.md) |
| Features and priorities | [features.md](Docs/Mantiza%20Roadmap/features.md) | [features.md](Docs/Google%20Artemis%20Analysis/features.md) |
| Tech stack | [tech-stack.md](Docs/Mantiza%20Roadmap/tech-stack.md) | [tech-stack.md](Docs/Google%20Artemis%20Analysis/tech-stack.md) |
| Roadmap and phases | [roadmap.md](Docs/Mantiza%20Roadmap/roadmap.md) | [roadmap.md](Docs/Google%20Artemis%20Analysis/roadmap.md) |

Building the iPhone app: on **Windows** follow [Windows setup with xtool](Docs/Setup/windows-xtool-setup.md) (works today, no Mac needed); on a **Mac** follow [MacBook setup](Docs/Setup/macbook-setup.md) (needed later for the widget and TestFlight).

New here? Start with the [Mantiza plan](Docs/Mantiza%20Roadmap/plan.md). Unfamiliar terms are explained in the [glossary](Docs/Mantiza%20Roadmap/glossary.md).

## 📱 Set up your iPhone for Mantiza

The Mantiza device controls your iPhone as a Bluetooth **mouse + keyboard**. iPhone only allows that through **AssistiveTouch**, and apps can't change these settings for you, so do this once before first use (about 5 minutes).

**How to read the tables**

| Set it to | Meaning |
|---|---|
| ✅ **On** | Turn the switch on |
| ❌ **Off** | Turn the switch off |
| 🎚️ / ⚡ | Move the slider / pick the option shown |

| Importance | Meaning |
|---|---|
| 🔴 **Required** | Mantiza won't work properly without it |
| 🟠 **Recommended** | Makes Mantiza faster or more reliable |
| 🔒 **Safety** | Protects you from accidental actions |
| ⚪ **Your choice** | Doesn't affect Mantiza; pick what you like |

`🧪` = not tested yet; the advice may change after testing.

### Step 1: Turn on AssistiveTouch and pair the device
1. **Settings → Accessibility → Touch → AssistiveTouch** → turn ✅ **On**.
2. On the same screen: **Devices → Bluetooth Devices** → tap **Mantiza** → **Pair**.
3. A round grey pointer appears on screen. ✔️
4. **Settings → General → Keyboard → Hardware Keyboard** → set **English** to **U.S.** (this menu only appears while the device is connected).

### Step 2: AssistiveTouch settings
📍 **Settings → Accessibility → Touch → AssistiveTouch**

| Setting | Set it to | Importance | Why |
|---|---|---|---|
| AssistiveTouch | ✅ On | 🔴 Required | iPhone only accepts a mouse through AssistiveTouch |
| Perform Touch Gestures | ✅ On | 🔴 Required | Makes the device's drags act like a real finger swipe (scrolling, swiping) |
| Tracking Sensitivity | 🎚️ **Max** (all the way to the 🐇) | 🔴 Required | Mantiza's pointer distances are tuned to this; changing it makes taps miss |
| Dwell Control | ❌ Off | 🔴 Required | With Dwell on, a still pointer taps by itself. Mantiza's pointer waits still while the AI thinks, so it would tap things by accident |
| Snap to Item | ❌ Off | 🔴 Required | It pulls the pointer to nearby buttons, which breaks Mantiza's exact positioning |
| Confirm with AssistiveTouch | ❌ Off | 🔒 Safety | When on, AssistiveTouch can confirm **Apple Pay and purchases**. Keep it off so the device can never approve a payment |
| Always Show Menu | ✅ On (for now) | ⚪ Your choice 🧪 | The floating menu button can cover things on screen; we will test whether Mantiza works better with it off |
| Show Onscreen Keyboard | ✅ On | ⚪ Your choice | On lets you still type with your finger. Off shows more of the screen, but you can only type with the device |
| Sound on Click | Either | ⚪ Your choice | A click sound on every device tap |
| Idle Opacity | Any | ⚪ Your choice | How see-through the floating menu button is |

### Step 3: Touch settings
📍 **Settings → Accessibility → Touch**

| Setting | Set it to | Importance | Why |
|---|---|---|---|
| Touch Accommodations | ❌ Off | 🔴 Required | It adds hold delays and changes how far a swipe must move, which slows down and confuses device taps |
| Haptic Touch → Touch Duration | ⚡ **Fast** | 🟠 Recommended | Long-press menus open sooner, so each long press is quicker |
| Prefer Single-Touch Actions | ✅ On | 🟠 Recommended 🧪 | Turns some "slide to…" controls (alarms, timers) into buttons. A tap is faster and more reliable than a slide |
| Reachability | ❌ Off | 🟠 Recommended | A swipe near the bottom edge can trigger it by accident and shift the whole screen down |
| Back Tap | Either | ⚪ Your choice | Tip: set Double Tap to a Mantiza shortcut to start a task by tapping the back of your phone |
| Tap to Wake, Shake to Undo, Vibration, Prevent Lock to End Call, Call Audio Routing | Any | ⚪ Your choice | Don't affect Mantiza |

### Step 4 (optional): quick on/off switch
If you only want AssistiveTouch while using Mantiza:
**Settings → Accessibility → Accessibility Shortcut** → tick **AssistiveTouch**. Now **triple-click the side button** to turn it on or off.

> [!WARNING]
> **Never turn on "Confirm with AssistiveTouch"** while the Mantiza device is paired. It would let the device confirm payments.

> [!TIP]
> **Didn't work?** Check the 🔴 Required rows first. If normal finger swipes feel wrong after turning on AssistiveTouch, restart the iPhone.

<details>
<summary>Settings you can ignore</summary>

These don't affect Mantiza: Customize Top Level Menu, Custom Actions (Single-Tap, Double-Tap, Long Press), Custom Gestures, Mouse Keys, Use Game Controller, Sound Actions, and Dwell's own options (Fallback Action, Movement Tolerance, Hot Corners, Keyboard, seconds). The Dwell options only work when Dwell Control is on, and it must stay off.
</details>

## Legend
The Mantiza docs mark each item against Artemis:

| Marker | Meaning |
|---|---|
| 🟢 | Same as Artemis |
| 🔵 | Replaces something Artemis uses |
| _(no marker)_ | New to Mantiza |
