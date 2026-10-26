# Artemis for iOS: Tech Stack

_Last updated: 2026-10-26 · Source: https://github.com/google/artemis (pyproject.toml, config/artemis.jsonc, .env.example)_

## 1. What Artemis (Android) uses today

| Area | What it uses |
|---|---|
| Language | Python 3.12+, managed with `uv` |
| AI orchestration | LangGraph and LangChain (the multi-agent "team" in Pro mode) |
| AI tool connection | MCP (Model Context Protocol) server, so AI coding tools can control the phone |
| Talking to the phone | ADB (Android Debug Bridge) via `adbutils` |
| Reading the screen | Its own Accessibility Helper app on the phone, with UIAutomator2 as fallback |
| Screen mirroring and recording | scrcpy and FFmpeg |
| Image processing | OpenCV, Pillow, NumPy, SciPy; optional Google Cloud Vision for OCR |
| Web dashboard / API | FastAPI and Uvicorn web server, with WebSockets for live updates |
| Command line | Typer and Rich |
| Data validation | Pydantic |
| Python SDK | `artemis-client`, a small separate package |
| Analytics | PostHog |
| Testing / quality | pytest, Ruff, Pyright |
| License | Apache 2.0 |

## 2. AI models used

Default provider is **Google Gemini**. Each AI "role" can use a different model:

| Role | Job | Default model |
|---|---|---|
| Default (all roles unless changed) | General thinking and acting | `gemini-3.8-flash` (fallback `gemini-3.7-flash`) |
| Planner | Breaks the goal into a step-by-step plan | Default model, high thinking |
| Operator | Looks at the screen and does the actions | Default model |
| Object Detector / Explorer | Finds exact tap positions on screen | `gemini-robotics-er-2-preview` (a special spatial model; regular models can't point accurately) |
| Hopper | Quickly finds which app to open | `gemini-3.5-flash-lite` |
| Step Summarizer / safety check | Summarizes old steps; checks taps before they happen | `gemini-3.5-flash-lite` |
| Checker | Verifies the final result | Default model |
| Video Analyzer | Reviews screen recordings | Default model |
| Log Analyzer / Diagnoser | Explains errors, with Google Search grounding | Default model |
| Summarizer / Outputter | Writes the final result and report | Default model |

Ready-made presets: Gemini flagship, Gemini 2.5 Flash, OpenAI GPT-4o, a cost-saving Gemini Flash-Lite setup, and local Llama 3.2 Vision via Ollama. API keys are supported for Gemini, OpenAI, Anthropic, OpenRouter and xAI.

## 3. Artemis for iOS: proposed stack

The AI parts can likely be reused as is. The phone-control layer is what changes. The iOS options below are suggestions to decide on, not decisions.

| Area | Android (today) | iOS option (to decide) |
|---|---|---|
| Host machine | Mac, Linux or Windows | Mac with Xcode (likely required) |
| Talking to the device | ADB | _TBD: e.g. XCUITest via WebDriverAgent, Facebook `idb`, `xcrun simctl` for Simulator_ |
| Reading the screen | Accessibility Helper / UIAutomator2 | _TBD: e.g. XCUITest accessibility tree_ |
| Tapping and typing | ADB input | _TBD: e.g. WebDriverAgent / XCUITest_ |
| Installing apps | ADB install (APK) | _TBD: e.g. `simctl install`, `devicectl` for real devices_ |
| Screen recording | scrcpy, FFmpeg | _TBD: e.g. `simctl io recordVideo`_ |
| Logs | Logcat | _TBD: e.g. `log stream`, device syslog_ |
| AI models and orchestration | Gemini + LangGraph | _Reuse?_ |
| Dashboard, CLI, MCP, SDK | FastAPI, Typer, MCP, artemis-client | _Reuse?_ |

## 4. Decisions log
| Date | Decision | Reason |
|---|---|---|
| | | |
