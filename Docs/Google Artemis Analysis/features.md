# Artemis for iOS: Feature List

_Last updated: 2026-10-26 · Source: https://github.com/google/artemis README_

Priority: **P0** must have for launch, **P1** should have, **P2** nice to have. Priorities and phases for iOS are still _TBD_.

## What Artemis does today (Android), in simple words

| # | Feature | What it means |
|---|---|---|
| 1 | Plain-English tasks | Tell it what to do in normal language and it works out the taps and typing itself. |
| 2 | Works across apps | It can hop between several apps in one task, like a person would. |
| 3 | Sees the screen two ways | It reads the list of buttons and text on screen, and if that's not available it looks at the picture itself to find things. Works with apps that draw custom screens (games, Flutter apps). |
| 4 | Fast mode (Flash) | Quick look, think, act loop, about 3 to 5 seconds per step, for simple tasks. |
| 5 | Careful mode (Pro) | Makes a plan, double-checks each tap before doing it, recovers from mistakes, and verifies the result at the end. Handles long tasks of 100+ steps. |
| 6 | Web dashboard | A browser page showing the phone screen live, a box to type tasks, a live feed of what the AI is thinking and doing, a task queue, and video replays of past runs. |
| 7 | Works inside AI coding tools | Connects to Claude Code, Cursor, Antigravity, Windsurf, Codex, VS Code and others, so you can say "build my app, install it, log in and check for popups" from your editor. |
| 8 | Command line | Run tasks directly from the terminal, for scripted tests. |
| 9 | Python library | Plug it into existing automated test suites and build pipelines, with clear pass/fail results. |
| 10 | Bug diagnosis | Collects phone logs, screenshots and screen recordings, and has AI helpers that analyze errors and suggest likely causes. |
| 11 | Screen recording analysis | Records the session and can review the video to check things that happened quickly (like a popup that disappeared). |
| 12 | Long-task memory | Summarizes older steps so it can keep working for a long time and look back at earlier steps when needed. |
| 13 | Choice of AI models | Works with Google Gemini by default, and also OpenAI, Anthropic Claude, OpenRouter, xAI, or local models. |
| 14 | One-click setup | A start script installs the needed tools and connects it to your AI coding tools. |
| 15 | Tiny on-phone helper | Installs a small helper on the phone to read the screen faster. It only talks to the phone itself and can be removed anytime. |
| 16 | Proven accuracy | Reports 99%+ success on Google's AndroidWorld test (100+ tasks across 20+ apps). |

## Artemis's own planned features (from its roadmap)
- Android Studio plugin
- **iOS support** (devices and simulators)
- Running small AI vision models directly on the phone
- Voice control with real-time conversation

## Artemis for iOS: feature plan

| Feature | Description | Priority | Phase | Status |
|---|---|---|---|---|
| Plain-English tasks on iPhone/Simulator | Same as #1, driving iOS | _TBD_ | _TBD_ | Not started |
| _TBD_ | _TBD_ | _TBD_ | _TBD_ | Not started |

## iOS-specific features to consider
- _e.g. iOS Simulator support, real device support, Xcode integration, TestFlight builds: TBD_

## Ideas backlog
- _TBD_
