# Mantiza: Glossary

_Last updated: 2026-10-26_

Plain-language meanings for the terms used in [plan.md](plan.md), [features.md](features.md), [tech-stack.md](tech-stack.md) and [roadmap.md](roadmap.md).

## Mantiza terms

| Term | Meaning |
|---|---|
| Fast mode | Simple tasks handled on the phone by Apple's on-device model. Mantiza's version of Artemis Flash. |
| Careful mode | Longer tasks handled by a Planner, Operator and Checker using a cloud model. Mantiza's version of Artemis Pro. |
| Planner | The AI role that breaks a goal into step-by-step instructions. |
| Operator | The AI role that carries out each step. |
| Checker | The AI role that checks the final result matches what you asked for. |
| Dynamic agentic UI | Screens the agent builds for each task (cards, pickers, confirm buttons) instead of fixed screens. |
| Pattern widget | The home screen widget that learns your daily, weekly and monthly habits and shows likely workflows. |
| Sensitive-app guard | A hard block that stops Mantiza acting in banking, payments, password managers, Wallet and Health. |
| Mac companion mode | Optional mode where a Mac drives the iPhone through iPhone Mirroring and taps the screen like Artemis does. |

## Apple and iOS terms

| Term | Meaning |
|---|---|
| App Intents | Apple's official way for an app to expose actions ("search", "order") that Siri, Shortcuts and other apps can call. |
| Shortcuts | Apple's app for chaining actions from many apps into one workflow. |
| Deep link | A link that opens an app straight at a specific screen, such as a search result. Includes URL schemes and universal links. |
| Foundation Models | Apple's framework for running its on-device language model inside an app. |
| PCC (Private Cloud Compute) | Apple's privacy-focused cloud for running larger Apple models. |
| SpeechAnalyzer | Apple's on-device speech-to-text engine (iOS 26+) that streams words as you speak. |
| Live Activity / Dynamic Island | Live status shown on the Lock Screen and around the iPhone's camera cutout. |
| WidgetKit | Apple's framework for home screen and Lock Screen widgets. |
| SwiftUI / SwiftData | Apple's frameworks for building the app's screens and storing its data on the phone. |
| TestFlight | Apple's service for sharing pre-release builds with testers. |

## Artemis and general AI terms

| Term | Meaning |
|---|---|
| Artemis | Google's open-source tool that lets an AI use an Android phone like a person. Mantiza's baseline. |
| ADB (Android Debug Bridge) | The USB connection Artemis uses to tap and type on an Android phone. |
| Flash / Pro | Artemis's fast and careful modes. |
| MCP (Model Context Protocol) | An open standard for connecting AI agents to outside tools and services. |
| STT / TTS | Speech to text and text to speech. |
| Gemini | Google's family of AI models. Mantiza's choice of cloud model for Careful mode. |
