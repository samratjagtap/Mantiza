# Mantiza: Roadmap

_Last updated: 2026-10-26 · Baseline: [Artemis roadmap](../Google%20Artemis%20Analysis/roadmap.md)_

**Legend:** 🟢 same as Artemis · 🔵 replaces something Artemis uses · _(no marker)_ new / other. GitHub does not render coloured text, so coloured emoji markers are used.

Dates assume 1 to 2 iOS developers starting 2026-11-02 and are targets, not commitments.

## How this relates to Artemis's roadmap
| Artemis roadmap item | In Mantiza |
|---|---|
| iOS support | 🔵 Done differently: Mantiza is a native iPhone app, not a computer driving an iPhone |
| On-device vision models | 🔵 Apple's on-device model and Vision framework from day one |
| Real-time voice | Voice is core from Phase 1; full conversation mode in Phase 4 |
| Android Studio plugin | Not planned |

## Phase 0: Discovery (2026-11-02 to 2026-11-22, 3 weeks)
- Check the top 50 apps on a real iPhone: URL schemes, search links, App Intents / Shortcuts actions (fills the table in [features.md](features.md#4-app-coverage-to-verify-in-phase-0)).
- Speed spike: SpeechAnalyzer partial results + rule matcher + app open, measure "said Blinkit → Blinkit on screen".
- Model spike: on-device model vs Gemini Flash vs PCC on 100 sample commands (accuracy and latency).
- Design: dynamic UI component library, widget layouts for all four sizes.
- **Exit:** latency ≤ 1 s median in the spike; app coverage table complete; model choice confirmed.

## Phase 1: Core agent MVP (2026-11-23 to 2027-01-17, 8 weeks)
- SwiftUI app, text and voice input (SpeechAnalyzer) 🔵
- Instant app opener and one-shot deep links 🔵
- On-device router via Foundation Models 🔵; Fast mode 🟢
- Dynamic agentic UI renderer
- Sensitive-app guard and confirmations 🟢
- Local event log in SwiftData (feeds the widget later)
- **Exit:** 30 single-app commands work by voice at ≥ 95% success, internal TestFlight.

## Phase 2: Workflows and Careful mode (2027-01-18 to 2027-03-07, 7 weeks)
- Multi-app workflows through Shortcuts actions and App Intents 🔵
- Careful mode: Planner → Operator → Checker with Gemini Flash via `LanguageModel` protocol 🟢
- Long-task memory 🟢
- Live Activity / Dynamic Island progress 🔵
- Siri / App Shortcuts exposure of Mantiza workflows
- Spoken replies
- Firebase backend (AI Logic, App Check, Auth); PostHog analytics 🟢
- **Exit:** 2 to 3 app workflows at ≥ 80% success; external TestFlight beta (100 users).

## Phase 3: Pattern widget (2027-03-08 to 2027-04-18, 6 weeks)
- WidgetKit in small, medium, large and extra-large, interactive buttons
- Daily, weekly, monthly pattern scoring on the device
- Pattern insights in plain language
- Lock Screen, Control Center and Action Button entry points
- Privacy dashboard (see and delete learned data)
- **Exit:** widget top suggestion used in ≥ 40% of widget taps for beta users after 2 weeks.

## Phase 4: App Store launch and growth (2027-04-19 to 2027-06-13, 8 weeks)
- App Store review, launch in India first
- Web service connectors via APIs / MCP 🟢
- Conversation mode via Gemini Live 🟢
- Hindi via WhisperKit or cloud STT
- Model choice (Gemini, PCC, Claude) 🟢
- Run history
- **Exit:** public launch; ≥ 90% multi-step success; cloud cost ≤ $0.30 per user per month.

## Phase 5: Mac companion full-control mode (after launch, from 2027-06)
- macOS app that drives the iPhone via iPhone Mirroring, Artemis-style 🟢
- Vision tap targeting with `gemini-robotics-er` 🟢
- Same sensitive-app guard as the phone
- Re-check WWDC27 (June 2027) for any new Apple APIs for cross-app agents and adjust

## Milestones
| Milestone | Target date | Status |
|---|---|---|
| App coverage table and speed spike done | 2026-11-22 | Not started |
| Voice MVP on internal TestFlight | 2027-01-17 | Not started |
| External TestFlight beta | 2027-03-07 | Not started |
| Pattern widget in beta | 2027-04-18 | Not started |
| App Store launch (India) | 2027-06-13 | Not started |
| Mac companion preview | 2027-Q3 | Not started |
