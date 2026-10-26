# Artemis for iOS: Plan

_Last updated: 2026-10-26 · Source: https://github.com/google/artemis (README, pyproject.toml, config/artemis.jsonc)_

## 1. What Artemis is

Artemis is an open-source tool from Google (Apache 2.0 license) that lets an AI use a real Android phone the way a person would. You type an instruction in plain English, such as "Open Settings, find Battery and tell me the current level", and Artemis looks at the phone screen, decides what to tap or type, and keeps going until the job is done.

It is mainly aimed at **app testing**: developers can ask it to install their app, walk through screens, look for bugs or crashes, and get back screenshots and a report. It can also do everyday multi-app tasks (the demo plans routes in Google Maps and then plays a song on YouTube).

**Important detail:** Artemis is not an app that lives on the phone. It runs on a computer (Mac, Linux or Windows) and controls a phone that is plugged in by USB or running as an emulator. The only thing it puts on the phone is a small helper that reads what is on the screen.

## 2. How it works (in simple terms)

1. **You give it a task** in plain language, from its web dashboard, the command line, an AI coding tool (like Claude Code, Cursor or Antigravity), or from Python code.
2. **It looks at the screen.** It takes a screenshot and also reads the list of buttons and text on screen (through the on-phone helper). When an app draws its own custom screens that don't expose that list, it falls back to reading text in the image (OCR) and to a vision model that can point at exact spots.
3. **An AI model decides the next step**: tap here, type this, scroll, go back, open an app.
4. **It does the action** on the phone over the USB connection (Android's ADB).
5. **It checks the result and repeats** until the task is complete. Old screenshots are replaced with short written summaries so it can run long tasks without running out of memory.
6. **It reports back**: success or failure, screenshots, a screen recording, device logs, and (in Pro mode) a written report.

It has two modes:
- **Flash (fast):** one AI model looks, thinks and acts in a quick loop, about 3 to 5 seconds per step. Good for simple, routine tasks.
- **Pro (careful):** a team of AI "roles" works together, about 15 to 40 seconds per step. A **Planner** writes a step-by-step plan, an **Operator** carries it out, a **safety check** confirms each tap is aimed at the right thing before it happens, and a **Checker** verifies the end result matches what you asked. Good for long or tricky tasks (100+ steps).

## 3. What "Artemis for iOS" means

The same idea, but driving an **iPhone or the iOS Simulator** instead of an Android phone. Most of Artemis (the AI brain, the planner, the dashboard, reports) is not Android specific. The parts that would need to be rebuilt for iOS are the ones that talk to the phone: reading the screen, tapping and typing, installing apps, recording video, and collecting logs. See [tech-stack.md](tech-stack.md) for the mapping.

Note: Google's own roadmap for Artemis already lists "iOS Platform Expansion" as a planned item, so we should decide whether to build a separate project or contribute to theirs.

## 4. Goals
- _TBD_

## 5. Non-goals
- _TBD_

## 6. Target users
- _TBD (e.g. iOS developers and QA testers, AI coding tool users)_

## 7. Success metrics
- _TBD (Artemis uses the AndroidWorld benchmark, where it reports 99%+ task completion; an iOS equivalent benchmark would need to be chosen)_

## 8. Scope
- **In scope for v1:** _TBD_
- **Later:** _TBD_

## 9. Constraints
- **Timeline:** _TBD_
- **Team:** _TBD_
- **Budget:** _TBD (AI model API costs per task)_
- **Hardware:** iOS automation generally requires a Mac with Xcode. _Confirm._

## 10. Risks and open questions
- Separate project, or contribute iOS support to Google's Artemis?
- Simulator only first, or real iPhones from day one?
- iOS is more locked down than Android (no equivalent of installing a background accessibility helper), so screen reading has to go through Apple's testing tools.
