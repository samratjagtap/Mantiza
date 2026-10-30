# Mantiza: Plan

_Last updated: 2026-10-26 · Baseline: [Google Artemis Analysis](../Google%20Artemis%20Analysis/plan.md)_

## How to read the colour markers

GitHub markdown strips text colour (no `<font>` or `style` tags), so these docs use coloured emoji markers, which render the same on GitHub web, mobile and in editors.

| Marker | Meaning |
|---|---|
| 🟢 | **Same as Artemis.** We use the same tech, model or approach Artemis uses. |
| 🔵 | **Replaces Artemis.** Artemis uses something for this job; we swap it for an iOS-native or better fit. |
| _(no marker)_ | **New / other.** Artemis has nothing comparable, so it is listed normally. |

The same legend is used in [features.md](features.md), [tech-stack.md](tech-stack.md) and [roadmap.md](roadmap.md).

## 1. What Mantiza is

Mantiza is an **iPhone app** with an AI agent inside it. You tell it what you want by **voice or text**, and it gets it done across your phone: opening apps, jumping straight to the right screen, running multi-step workflows, and answering back. Its home screen **widget learns your daily, weekly and monthly patterns** and puts the workflows you are most likely to want right now one tap away. The UI is **dynamic**: the agent builds the cards, buttons and confirmations it needs for each task on the fly, instead of fixed screens.

## 2. How it differs from Artemis

| | Artemis (Google) | Mantiza |
|---|---|---|
| Where it runs | On a computer, driving an Android phone over USB (ADB) | 🔵 On the iPhone itself, as a normal App Store app |
| Who it is for | Developers and QA testers | Everyday iPhone users |
| Input | Typed tasks (dashboard, CLI, AI coding tools) | Voice **and** text, voice tuned for speed |
| How it acts | Taps and types on screen like a person | 🔵 Calls apps through Apple's official doors: App Intents, Shortcuts, deep links. Screen tapping only in an optional Mac companion mode (see section 4) |
| AI brain | 🟢 Planner, Operator, Checker roles; Gemini models | 🟢 Same roles and Gemini for hard tasks, plus 🔵 Apple's on-device model for the fast first step |
| Memory of long tasks | 🟢 Summarises old steps | 🟢 Same idea, using Foundation Models history trimming |
| Pattern-learning widget | None | **New:** resizable widget with daily, weekly, monthly patterns |
| Safety | 🟢 Pre-tap safety check | 🟢 Same idea, plus a hard block list for banking, payments and other sensitive apps |

## 3. The three asks, and what iOS really allows

### 3.1 Voice that acts live ("open Blinkit, and...")
**Possible, and can feel instant.** Apple's on-device speech engine (SpeechAnalyzer, iOS 26+) streams partial words as you speak, so Mantiza can recognise "open Blinkit" before you finish the sentence. Opening an installed app by its link takes well under a second. Target: Blinkit in front of you **within about 1 second of saying "Blinkit"**.

The catch: once Blinkit is open, Mantiza is in the background, and iOS does not let a background app bring up another app or tap inside one. So for "open Blinkit **and** order milk", Mantiza must understand the whole sentence first and open Blinkit straight at the right place in one go (a search link, if Blinkit supports it, or a Blinkit Shortcut/App Intent if it has any). Our design: act immediately when you say "open X" and pause; if it hears "and...", it waits a fraction of a second for the rest, then opens the deepest link it can. Mantiza can keep listening in the background (with the orange mic dot) and show progress in a Live Activity / Dynamic Island.

### 3.2 Pattern-learning, resizable widget
**Possible, with one honest limit on size.** iOS widgets come in fixed sizes, not free height and width. On iOS 27 iPhone has four: small (2×2), medium (4×2), large (4×4) and the new extra-large (4×6), and you resize by dragging between them. We design a layout for each size, so it feels resizable. Widgets also support tap buttons that run a workflow without opening the app (interactive widgets, iOS 17+), and we can add Lock Screen and Control Center versions.

The second limit: Apple does not let apps read your overall app usage (Screen Time data stays sandboxed). So Mantiza learns from **workflows run through Mantiza** (plus what you choose to tell it), not from everything you do on the phone. All learning stays on the device.

### 3.3 "Control everything except sensitive apps"
**This is the hardest limit, and we should be upfront about it.** On Android, Artemis taps on any app because ADB and accessibility services allow it. On iPhone, an App Store app **cannot see or tap inside other apps**. There is no public API for it, and a background accessibility helper like Artemis's is not allowed.

What Mantiza *can* control from the phone:

| Level | How | Coverage |
|---|---|---|
| Open any app, often at a specific screen | URL schemes and universal links | Almost every app, depth varies per app |
| Run real actions in other apps | Their App Intents / Shortcuts actions (via Shortcuts, Siri) | Apps that publish them. Since iOS 27, Siri AI only routes through App Intents, so more apps are adding them |
| System actions | Shortcuts actions: timers, alarms, Focus, messages, music, Home, settings toggles, files | Very broad |
| Web services directly | APIs and MCP servers (calendar, email, notes, smart home, etc.) | Anything with an API |
| Mantiza's own UI | Full control, generated on the fly | Full |

What needs the **optional Mac companion** (Artemis-style, see tech-stack): real tap-by-tap control of any app, using iPhone Mirroring on a Mac plus a vision model, or Apple's XCUITest tooling in a developer build. This is not something an App Store iPhone app can ship.

Sensitive apps (banking, UPI and payment apps, password managers, Wallet, Health, authenticator apps) are on a **hard block list** in every mode. iOS already blocks most of this; our list adds a second lock that also covers the Mac companion mode, and any purchase or message send always asks you first.

## 4. Goals
1. Voice command to visible result fast: "open X" in about 1 second, simple multi-step tasks under 5 seconds.
2. Cover the top 50 apps Indian iPhone users use (Blinkit, Zepto, Swiggy, Zomato, Uber, Ola, WhatsApp, YouTube, Spotify, Maps, etc.) at the deepest level each app allows.
3. A widget that correctly predicts at least one of the user's next actions most of the time (see metrics).
4. Private by default: speech, patterns and simple tasks handled on the device.

## 5. Non-goals (v1)
- Tapping inside other apps from the iPhone alone (not allowed by iOS).
- Any action in banking, payment or other sensitive apps.
- An always-on custom wake word while Mantiza is closed (iOS reserves this for Siri). Users start Mantiza from the Action Button, widget, Control Center, Lock Screen or "Hey Siri, Mantiza".
- Developer testing tools (Artemis's core use case).

## 6. Target users
- Busy iPhone users in India and beyond who repeat the same app routines daily (groceries, rides, food, music, messaging).
- Power users who already use Shortcuts and want it to be spoken and smart.

## 7. Success metrics
| Metric | Target |
|---|---|
| Time from saying the app name to that app on screen | ≤ 1.0 s median, ≤ 1.8 s p95 |
| First visible reaction after you start speaking | ≤ 300 ms |
| Simple task success (single app, supported action) | ≥ 95% |
| Multi-step task success (2 to 3 apps) | ≥ 80% at beta, ≥ 90% at launch |
| Widget "top suggestion was used" rate | ≥ 40% of widget taps after 2 weeks of use |
| Sensitive-app actions performed | 0 |
| Cloud cost per active user per month | ≤ $0.30 |

## 8. Scope
- **v1 (App Store):** voice + text, fast app opener, deep links and Shortcuts workflows, dynamic UI cards, pattern widget in all sizes, sensitive-app guard, cloud planner for multi-step tasks.
- **Later:** natural spoken back-and-forth (realtime voice model), Mac companion full-control mode, Apple Watch and CarPlay, Hindi and other Indian languages via cloud speech.

## 9. Constraints
- **Minimum iOS:** iOS 27 recommended (Foundation Models dynamic profiles, third-party model support, extra-large widget). iOS 26 is possible with reduced features.
- **Devices:** on-device Apple model needs Apple Intelligence (iPhone 15 Pro and later). Older iPhones fall back to the cloud model.
- **Language:** Apple Intelligence supports English (India) but not Hindi as of iOS 27. Hindi needs cloud speech.
- **Team / timeline / budget:** _TBD, roadmap assumes 1 to 2 iOS developers._

## 10. Risks and open questions
| Risk | Impact | Mitigation |
|---|---|---|
| Key apps (e.g. Blinkit) expose no App Intents or deep links beyond "open" | Mantiza can only open them, not act inside | Verify top 50 apps in Phase 0; offer Mac companion; web APIs where they exist |
| App Review rejects features seen as automating other apps | Launch delay | Use only public APIs (URL schemes, App Intents, Shortcuts); keep companion mode outside the iOS app |
| Apple's own Siri (Gemini-powered, iOS 27) overlaps | Competition | Lean on what Siri lacks: pattern widget, dynamic UI, transparent workflows, Indian-app focus. Also expose Mantiza workflows to Siri |
| Background mic limits | Follow-up commands lost after leaving app | Live Activity with a tap-to-talk button; parse the whole sentence before switching apps |
| Cloud model latency on Indian mobile networks | Slow multi-step tasks | On-device first step; regional endpoints; stream partial UI |

## 11. Sources
- Apple WWDC26 iOS guide: https://developer.apple.com/wwdc26/guides/ios/
- WWDC26 "Discover new capabilities in the App Intents framework": https://developer.apple.com/videos/play/wwdc2026/345/
- WWDC26 "Build intelligent Siri experiences with App Schemas": https://developer.apple.com/videos/play/wwdc2026/240/
- WWDC26 "Build agentic app experiences with the Foundation Models framework": https://developer.apple.com/videos/play/wwdc2026/242
- iOS 27 extra-large widgets: https://9to5mac.com/2026/06/08/ios-27-adds-extra-large-widgets-for-your-extra-large-needs/
- iOS 27 feature availability by language: https://www.apple.com/ios/feature-availability/
- Realtime voice API comparison (mid-2026): https://zylos.ai/research/2026-07-19-realtime-voice-api-protocol-adaptation
