# Mantiza

Mantiza is an **iPhone app** with an AI agent inside it. You tell it what you want by **voice or text**, and it gets it done across your phone: opening apps, jumping straight to the right screen, running multi-step workflows, and answering back. Its home screen widget learns your daily, weekly and monthly patterns and puts the workflows you are most likely to want right now one tap away.

This repo currently holds the planning docs. Mantiza uses Google's [Artemis](https://github.com/google/artemis) as its baseline, so there is a doc set for each.

## Docs

| Topic | Mantiza | Artemis baseline |
|---|---|---|
| Plan: what it is and how it works | [plan.md](Docs/Mantiza%20Roadmap/plan.md) | [plan.md](Docs/Google%20Artemis%20Analysis/plan.md) |
| Features and priorities | [features.md](Docs/Mantiza%20Roadmap/features.md) | [features.md](Docs/Google%20Artemis%20Analysis/features.md) |
| Tech stack | [tech-stack.md](Docs/Mantiza%20Roadmap/tech-stack.md) | [tech-stack.md](Docs/Google%20Artemis%20Analysis/tech-stack.md) |
| Roadmap and phases | [roadmap.md](Docs/Mantiza%20Roadmap/roadmap.md) | [roadmap.md](Docs/Google%20Artemis%20Analysis/roadmap.md) |

Setting up a Mac to build the iPhone app? Follow [MacBook setup](Docs/Setup/macbook-setup.md).

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
