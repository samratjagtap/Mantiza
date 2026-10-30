# Mantiza: Tech Stack

_Last updated: 2026-10-26 · Baseline: [Artemis tech stack](../Google%20Artemis%20Analysis/tech-stack.md)_

**Legend:** 🟢 same as Artemis · 🔵 replaces something Artemis uses · _(no marker)_ new / other. GitHub does not render coloured text, so coloured emoji markers are used instead.

**How choices were made:** each area was weighed on speed, privacy, cost, App Store safety and maturity. Only the winner goes in the **Choice** column. Anything good but not best goes in **Options** (fallbacks or later upgrades).

## 1. Stack at a glance

| Area | Choice | Mark | Artemis uses | Options (not chosen, still viable) |
|---|---|---|---|---|
| Language | Swift 6 | 🔵 | Python 3.12 | Kotlin Multiplatform (if Android later), React Native (weak for widgets/intents) |
| UI | SwiftUI | 🔵 | Web dashboard (FastAPI + browser) | UIKit for edge cases |
| Dynamic agentic UI | Model returns typed UI specs (`@Generable` structs) that SwiftUI renders from a fixed component library | | (none) | Server-driven JSON UI; A2UI-style protocols |
| Agent orchestration | Foundation Models `LanguageModelSession.DynamicProfile` with Planner, Operator, Checker profiles ("baton-pass" pattern) | 🔵 | LangGraph + LangChain | Hand-rolled Swift state machine; LangGraph on a server |
| Agent roles | Planner, Operator, Checker, Step Summarizer, safety check | 🟢 | Same roles | Fewer roles for v1 (Router + Operator only) |
| Structured output | `@Generable` / `@Guide` (guided generation) | 🔵 | Pydantic | Codable + JSON schema with cloud models |
| On-device model (fast router, simple tasks) | Apple Foundation Model via `SystemLanguageModel` | 🔵 | Local Llama 3.2 Vision via Ollama (optional) | Own small model via Core AI (iOS 27) or MLX Swift; Gemma 3n |
| Cloud model (hard, multi-step planning) | Gemini Flash (current `gemini-3.x-flash`), plugged in through the Foundation Models `LanguageModel` protocol | 🟢 | Gemini Flash default | Apple Private Cloud Compute model (free for small apps under 2M downloads); Claude Sonnet 5.5 / Haiku 5.5; GPT |
| Fast "which app?" model | Rule matcher + on-device model | 🔵 | Hopper on `gemini-3.5-flash-lite` | Gemini Flash-Lite as cloud fallback |
| Long-task memory | Foundation Models `historyTransform`, `.rollingWindow`, step summaries | 🟢 | Step summarizer replaces old screenshots | Store summaries in SwiftData for cross-session recall |
| Speech to text | Apple **SpeechAnalyzer + SpeechTranscriber** (on-device, streaming) | | (no voice; on Artemis's roadmap) | WhisperKit (on-device, multilingual incl. Hindi); Deepgram / Google STT for Hindi and noisy audio |
| Spoken replies | `AVSpeechSynthesizer` with premium voices | | (none) | Gemini TTS, ElevenLabs |
| Conversational voice mode (later) | Gemini Live API via Firebase AI Logic | 🟢 | Gemini (provider) | OpenAI `gpt-realtime-2.1` (more mature tool calls, ~10× cost) |
| Acting in other apps | App Intents, Shortcuts, URL schemes / universal links | 🔵 | ADB input taps | Mac companion mode (below) |
| Reading other apps' screens | Not possible on iOS for App Store apps; Mantiza reads only its own UI (View Annotations) | 🔵 | Accessibility Helper + UIAutomator2 | Mac companion: iPhone Mirroring screenshots; ReplayKit broadcast extension (view only, no taps) |
| Exposing Mantiza to Siri | App Intents + App Shortcuts + App Schemas | | (none) | SiriKit (deprecated at WWDC26, do not use) |
| Tool connections to web services | MCP client (remote MCP servers) + direct REST APIs | 🟢 | MCP server | Only REST APIs |
| Widget | WidgetKit, all sizes incl. extra-large (iOS 27), interactive buttons via App Intents | | (none) | Live Activities, Control Center controls, Lock Screen widgets (add in Phase 3) |
| Pattern learning | On-device time-bucket scoring over a local event log | | (none) | Core ML / Create ML tabular model; Foundation Models for pattern summaries |
| Local storage | SwiftData in an App Group (shared with widget) | | (files on host) | GRDB / SQLite |
| Secrets | Keychain; no model keys in the app | | `.env` file | |
| Backend | Firebase (AI Logic proxy for Gemini, App Check, Auth, Remote Config) | | (runs locally) | Cloudflare Workers proxy; Supabase |
| Image understanding | Apple Vision framework (OCR, barcodes; also callable as Foundation Models tools) | 🔵 | OpenCV, Pillow, Google Cloud Vision | Gemini vision |
| Screen recording / replays | ReplayKit (own app only) | 🔵 | scrcpy + FFmpeg | |
| Analytics | PostHog iOS SDK (self-host option, privacy settings) | 🟢 | PostHog | TelemetryDeck (privacy-first, simpler) |
| Crash reporting | Firebase Crashlytics | | (none) | Sentry |
| Testing | Swift Testing + XCTest, `AppIntentsTesting` (iOS 27), Foundation Models Evaluations framework | 🔵 | pytest | |
| Lint / types | SwiftLint, SwiftFormat, Swift strict concurrency | 🔵 | Ruff, Pyright | |
| CI / delivery | Xcode Cloud → TestFlight → App Store | | `uv` + scripts | GitHub Actions + fastlane |
| Optional full-control mode | **Mac companion app**: drives the iPhone through iPhone Mirroring with a vision model, Artemis-style | 🟢 | Same idea (computer drives phone) | XCUITest / WebDriverAgent developer build (dev-only, not for users) |
| Spatial "where to tap" model (companion only) | `gemini-robotics-er` | 🟢 | Same model | Claude computer use; Gemini Flash vision |

## 2. Why each choice, and what is better about it

| Choice | Mark | Why we use it | What is better than the Artemis way / alternatives |
|---|---|---|---|
| Swift 6 + SwiftUI | 🔵 | Only first-class way to build widgets, App Intents, Live Activities | Native speed, small app, no bridge lag; Python cannot run as an iOS app |
| Foundation Models dynamic profiles | 🔵 | Apple's built-in agent toolkit: switch model, tools and instructions mid-session, tool-calling loops, Instruments profiling | Runs on the phone, no server needed for orchestration; same Planner/Operator/Checker idea as Artemis's LangGraph but without a Python runtime |
| Apple on-device model as router | 🔵 | Decides "what did the user mean, which app" in milliseconds, offline, free | No network round trip (the single biggest speed win), private, zero token cost. Weakness: small model, so hard plans go to the cloud |
| Gemini Flash for planning | 🟢 | Proven by Artemis for agentic planning; fast and cheap | Plugs in through the `LanguageModel` protocol, so it can be swapped for PCC or Claude without rewriting the agent |
| SpeechAnalyzer streaming STT | | On-device, streams partial words, long-form and distant-mic friendly; benchmarks faster than Whisper | Lets us act on "open Blinkit" before the sentence ends. Free and private. Weakness: no Hindi in Apple Intelligence yet, so WhisperKit/cloud is the option there |
| App Intents + Shortcuts + deep links | 🔵 | The only App Store-approved ways to make other apps do things | Reliable (no mis-taps), fast (no screenshot → think → tap loop, which costs Artemis 3 to 5 s per step), and they keep working when an app redesigns its screens |
| Gemini Live (later) | 🟢 | Real spoken conversation with tool calls while it talks | ~10× cheaper per minute than OpenAI realtime, async tool calls; Firebase SDK means no keys in the app |
| WidgetKit (all four sizes, interactive) | | Users resize between small, medium, large and extra-large; buttons run workflows directly | Extra-large (4×6, iOS 27) gives room for a daily timeline view |
| On-device time-bucket scoring | | Simple counts by hour-of-day, day-of-week and day-of-month, weighted by recency | Explainable ("you order groceries most Sundays around 10"), works from day 3, no training, private. Core ML only if this plateaus |
| SwiftData in App Group | | App and widget read the same data | Native, small, works with widget timelines |
| Firebase AI Logic | | Calls Gemini from the app without shipping API keys, with App Check abuse protection | Same Google stack as Artemis's models; less backend to write |
| Apple Vision | 🔵 | OCR and barcode reading on the phone | Free, on-device, can be handed to the model as a tool |
| PostHog | 🟢 | Same as Artemis, product analytics with an iOS SDK | Can self-host; we keep events coarse and never log what the user says |
| Mac companion with iPhone Mirroring | 🟢 | The only realistic route to tap-anywhere control of an iPhone | Same "computer drives phone" model as Artemis, reuses its vision-tap approach; needs a Mac nearby and is not available in the EU |

## 3. Things we considered and did not choose

| Option | Why not (for now) |
|---|---|
| LangGraph / LangChain on the phone | Python/JS runtime on iOS is heavy and slow; Foundation Models covers the same pattern natively |
| Custom background accessibility helper (like Artemis) | Not allowed on iOS; would be rejected or impossible |
| WebDriverAgent shipped to users | Needs developer signing and a test runner; not App Store compatible. Kept for internal testing only |
| Screen Time / DeviceActivity data for patterns | The data stays inside a sandboxed report extension; the app cannot read or learn from it |
| SiriKit | Deprecated at WWDC26; Siri AI routes through App Intents |
| Arbitrary pixel-size widgets | iOS only allows fixed families; we design for each size instead |
| OpenAI realtime as default voice | Excellent but about 10× the per-minute cost of Gemini Live |
| Apple "system MCP" | Early MCP support was spotted in iOS 26.1 betas and some reports say iOS 27 adopts it, but this is not confirmed in Apple's docs. Watch, do not depend on it |

## 4. Speed design for voice ("open Blinkit" in ~1 s)

1. **Warm start:** audio session and SpeechAnalyzer are prepared when Mantiza opens, or when launched from the Action Button, widget, Control Center or Lock Screen.
2. **Act on partial words:** each partial transcript is checked by a tiny rule matcher against the user's app catalogue ("open / launch / start + app name").
3. **Smart wait:** if the next word is "and" or a pause is under ~350 ms, keep listening; otherwise open immediately.
4. **One-shot deep link:** for "open Blinkit and order milk", the on-device model turns the full sentence into the deepest link or App Intent available, then opens it once (iOS will not let us act after we are in the background).
5. **Stay with the user:** the mic keeps running in the background with the orange dot, and a Live Activity shows what Mantiza heard and did, with a tap-to-talk button.

Budget: speech partial ~100 to 300 ms, match <10 ms, app launch ~300 to 600 ms. Cloud models are not on this path.

## 5. Sensitive-app guard

- A built-in block list by category: banking, UPI and payment apps, brokerages and crypto, password managers and authenticators, Wallet, Health, government ID apps.
- The guard runs before every action in every mode, including the Mac companion.
- Purchases, messages to others and anything irreversible use App Intents `requestConfirmation` (the user taps to confirm).
- Mantiza never stores payment details or one-time passwords.

## 6. Decisions log

| Date | Decision | Reason |
|---|---|---|
| 2026-10-26 | iPhone app, not a computer-driven tool | Target is everyday users, not testers |
| 2026-10-26 | Act through App Intents / Shortcuts / deep links | Only App Store-safe way to control other apps on iOS |
| 2026-10-26 | On-device speech and router; cloud only for planning | Meets the ~1 s voice target |
| 2026-10-26 | Emoji colour markers in docs | GitHub markdown does not render text colour |
