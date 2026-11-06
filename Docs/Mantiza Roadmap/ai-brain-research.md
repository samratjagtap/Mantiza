# Mantiza's brain: which AI services, for which job (research, 2026-11-06)

_Status: research. Nothing here is measured by us yet; tests T8 and T11 decide. Prices and claims are as published in November 2026._

## 1. The jobs
Every Mantiza task is: **understand the request → per step: look → decide → act → check**. These are different jobs, and the fastest setup uses a different tool for each:

| Job | How often | What it needs | Speed target |
|---|---|---|---|
| **A. Read the screen** (words + where they are) | every step | text and boxes from the screenshot | < 0.2 s |
| **B. Pick the next tap** from a list | every step | multiple choice + confidence | < 0.3 s |
| **C. Check** "did it work?" | every step / end | yes/no probability | < 0.3 s |
| **D. Find a button with no text** (Send ➤, back ←) and other hard steps | sometimes | look at the screenshot, return x, y | ~1 s |
| **E. Plan** (understand the request) | once per task | language understanding | ~1–2 s |
| **F. Repeat a learned task** | often, later | no AI at all | 0 s |

## 2. Job A: read the screen
- **Apple Vision text recognition (on the phone):** free, no network, works on every iPhone that runs iOS 27, including our 14 Plus. Gives every word and its box. Speed on the 14 Plus is still to measure.
- **Apple Foundation Models with image input (iOS 27):** an on-device model that can look at images ([MacRumors](https://www.macrumors.com/2026/06/08/apple-unveils-xcode-and-models-improvements/), [details](https://blakecrosley.com/blog/foundation-models-image-input-ios-27)). ❌ **Only on Apple Intelligence iPhones (iPhone 15 Pro and newer).** The iPhone 14 series isn't supported ([Beebom](https://gadgets.beebom.com/guides/ios-27-eligible-devices-list), [Technobezz](https://www.technobezz.com/news/ios-27-requires-apple-intelligence-features-that-demand-an-iphone-15-pro-or-newer)). Its on-device context is 4K tokens. It could be a later bonus on newer phones, but can't be the base.
- **Icon detectors** like Microsoft OmniParser: the icon detector is **AGPL** (inherited from YOLO), which is a problem for a closed app ([GitHub](https://github.com/microsoft/OmniParser)). Not chosen.

## 3. Jobs B and C: decision models (the "fast brain")
A new category since September 2026: models that **write no text** and only answer typed questions (choice, yes/no, score) with probabilities. The four main ones are below. **Correction (2026-11-07):** OpenRouter lists **37** decision models, **25** of which take images (e.g. Perplexity Decider, Liquid d1, Inception Mercury Decide, Baseten Joey/Elephant/Mammoth, Morph Reflex). Jev 1.13/1.14 now take images too, and Jev 1.14 has a **box** question that returns where a target is on the image. First measurements: [brain bench](../../tools/brain-bench/README.md).

| | **Jev** (TypeSafe) | **OpenAI Decisions API** | **Cloudflare Clef / Clef-flash** | **AWS Strands Decider 2B** |
|---|---|---|---|---|
| Sees images | ✅ since Jev 1.13 (was text only); 1.14 can also return a box | ✅ | ✅ Clef and Clef-flash | ❌ text only |
| Speed (all vendor-reported) | median 0.27–0.31 s in an independent medical study; 0.5 s in Cloudflare's run | "~150 ms" (OpenAI claim, unreproduced) | Clef 209 ms, Clef-flash 39 ms (Cloudflare's own run) | ~115 ms on own hardware |
| Price per M input tokens (output free) | $0.042 | $0.10 | $0.24 / $0.09 | self-host |
| Status | GA, on OpenRouter | **GA since 2026-10-22** (beta from 2026-10-06; earlier news saying "limited preview" is out of date), open to any API account | GA on Workers AI; open weights (Apache 2.0) | open weights (Apache 2.0) |
| Where it runs | US (not stated) | US or Europe (OpenAI's regional processing; no India region), so calls from India cross the ocean | Cloudflare GPUs incl. **Mumbai and New Delhi** (location reported; whether Clef runs there is unconfirmed) | anywhere we host it |
| Accuracy notes | Beat OpenAI Decisions **81.7% vs 61.2%** on a community logic test ([repo](https://raw.githubusercontent.com/etsabary/luna-decisions-benchmark/7a5ea1371905c1e680f936d0a2ac1862b9039ca8/README.md)) | see left | Beats Jev on intent sorting (BANKING77 94 vs 80), loses on reasoning (GPQA 48 vs 78), per Cloudflare | none for UI |

Sources: [Jev overview](https://metricnexus.ai/blog/jev-benchmarks-pricing), [Jev on OpenRouter](https://openrouter.ai/typesafe/jev-1.14), [rivals](https://www.implicator.ai/typesafe-ai-raises-870-million-for-jev-as-openai-amazon-and-cloudflare-ship-rivals/), [OpenAI Decisions guide](https://developers.openai.com/api/docs/guides/decisions), [OpenAI changelog (beta 10-06, GA 10-22)](https://developers.openai.com/api/docs/changelog), [GA announcement](https://openai.com/index/decisions-api/), [Decisions latency claim](https://www.orcarouter.ai/blog/openai-decisions-api-gpt-6-luna), [Clef](https://www.developersdigest.tech/blog/cloudflare-clef-decision-models-2026), [Clef pricing](https://datanorth.ai/news/cloudflare-releases-clef-and-clef-flash), [Cloudflare GPUs in India](https://dailyaiworld.com/blogs/cloudflare-brings-workers-ai-300-edge-cities-sub-25ms-cold-starts), [Strands Decider](https://www.marktechpost.com/2026/10/01/aws-strands-labs-releases-strands-decider-2b/).

Anthropic and Google have **no** native decision model; frameworks emulate it with normal prompts ([Vercel](https://vercel.com/i/what-are-decision-models)).

**For Mantiza:** none has been tested on phone screens. The **image-capable ones (OpenAI Decisions, Cloudflare Clef)** fit best because they see icons, and Clef may run in India. Jev is the cheapest and strongest on reasoning tests, but blind to icons. All are in T11.

## 4. Job D: find a button on the screenshot (coordinates)

| | **Gemini 3.8 Flash** | **Claude Sonnet 5.5** | **GPT-6.1 Terra** | Open grounding models (Holo2, GUI-Owl, Qwen-VL) |
|---|---|---|---|---|
| Built-in phone mode | ✅ "mobile" environment (Android-optimized): click, long_press, go_back, open_app; 0–999 coordinates | ❌ desktop; has **zoom** | ❌ browser/desktop | — |
| Built-in "ask before risky actions" | ✅ `require_confirmation` for messages, payments, deletions | via our rules | safety checks | — |
| Desktop computer-use score | 59% OSWorld 2.0 (Google) | ~84% OSWorld 2.1 (reported in Terra coverage) | 67% medium / 74% max (OpenAI) | Holo2-8B 59% ScreenSpot-Pro |
| Turning thinking off (speed!) | "minimal" thinking | `thinking: between_tools` (no up-front thinking) | reasoning "none" | n/a |
| Price in/out per M tokens | $0.75/$3.75 → **$1.50/$7.50 from 2027-01-01** | $2/$10 | $1/$5 | self-host |
| India region | not confirmed (US/global reported) | Bedrock India routing for Sonnet 5; 5.5 unconfirmed | storage in India, compute not stated | anywhere |

Sources: [Gemini computer use](https://aistudio.google.com/docs/computer-use), [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing), [Claude computer use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool), [Claude effort/thinking](https://platform.claude.com/docs/en/build-with-claude/effort), [Claude pricing](https://platform.claude.com/docs/en/about-claude/pricing), [OpenAI computer use](https://developers.openai.com/api/docs/guides/tools-computer-use), [OpenAI models](https://developers.openai.com/api/docs/models), [Terra scores](https://www.marktechpost.com/2026/10/26/openai-gpt-6-1-terra/), [Sonnet vs Terra](https://letsdatascience.com/blog/gpt-6-1-terra-beats-openai-flagship-claude-still-leads), [Gemini 3.8 Flash scores](https://computingforgeeks.com/gemini-3-8-flash-released-features-benchmarks/), [Holo2](https://huggingface.co/Hcompany/Holo2-4B), [Bedrock India](https://aws.amazon.com/blogs/machine-learning/amazon-bedrock-expands-claude-model-availability-to-india-cross-region-inference/), [Gemini India region](https://discuss.google.dev/t/gemini-flash-on-vertex-ai-india-region-availability-and-latency-for-real-time-voice-agents/398735).

**The most important speed finding: thinking.** With thinking on, these models take **6–22 s** before answering (Haiku 5.5 low: ~9 s; Gemini 3.8 Flash high: ~22 s) ([Artificial Analysis](https://artificialanalysis.ai/models/claude-haiku-5-5-low/providers), [AA Gemini](https://artificialanalysis.ai/models/gemini-3-8-flash)). Published speed tables mostly measure *with* thinking, so they are misleading for us. **Every per-step call must run with thinking off**; only the plan (job E) may think a little.

## 5. Options looked at and set aside
| Option | Why not now |
|---|---|
| Gemini Live (streams the screen) | 1 frame per second, built for voice conversations; adds complexity without a clear gain per step ([docs](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/live-api)) |
| Very fast hosts (Groq, Cerebras) | Their vision models (Qwen3.6-27B preview on Groq, Gemma 4 31B on Cerebras) are general models, not trained for screens; Cerebras API is US-only ([Groq](https://raw.githubusercontent.com/anionex/dsh-vision-toolkit/main/docs/groq-qwen3.6-vision.md), [Cerebras](https://www.oflight.co.jp/en/columns/cerebras-gemma-4-31b-multimodal-inference-2026-07)) |
| Apple Ferret-UI Lite (3B, on device) | Research model; not a shipped API ([InfoQ](https://www.infoq.com/news/2026/02/apple-ferret-ui-lite-on-device)) |
| Open phone agents (Artemis, mobile-use, OpenMobile-2) | Android, need their own GPU servers; useful as design references ([Artemis](https://pasqualepillitteri.it/en/news/25427/google-artemis-open-source-ai-agent-android-en), [OpenMobile-2](https://the-decoder.com/openmobile-2-proves-open-source-smartphone-agents-can-rival-proprietary-models/)) |
| Big model for every step | 5–10 × (1–3 s) per task; slowest and priciest |

## 6. Recommended setup (to confirm in T8/T11)
```
Request ──► E. Plan: big brain, little thinking (once, ~1–2 s)
             │
   ┌────────►▼
   │   A. Apple text recognition on the phone (free, no network)
   │         │ numbered list: words + boxes
   │         ▼
   │   B. Decision model: screenshot + list → "which item?" + confidence
   │         │ sure                         │ unsure / icon only
   │         ▼                              ▼
   │   device taps the box        D. big brain, thinking off → x, y
   │         │◄─────────────────────────────┘
   │         ▼
   │   C. Decision model: "did it work?" (yes/no)
   └── next step                    done ✅ → F. save as learned task
```
- **Fast brain (B, C):** OpenAI Decisions vs Cloudflare Clef vs Jev. Favourites are the two that see images.
- **Big brain (D, E):** Gemini 3.8 Flash (phone mode, built-in confirmations, cheapest now) vs Claude Sonnet 5.5 (likely most accurate, zoom) vs GPT-6.1 Terra. All with thinking off for D.

**Chosen (2026-11-07, to confirm in T8/T11):** fast brain = **OpenAI Decisions API** (`gpt-6-luna`), big brain = **Claude** (Sonnet 5.5, thinking off for job D). Keys: `OPENAI_API_KEY` and `ANTHROPIC_API_KEY` in `C:\Users\PC\.mantiza\keys.env` (outside the repo).

**Round 1 measured (2026-11-07, [brain bench](../../tools/brain-bench/README.md#round-1-results-2026-11-07-openrouter-from-india)):**
- **Fast brain:** OpenAI Luna Decisions. 0.43 s median through OpenRouter from India; never wrong when ≥ 50% sure (71 of 82 steps).
- **Big brain:** Claude Haiku 5.5 with thinking off. 98% right, 1.8 s, $0.0002 per call. Gemini 3.5 Flash-Lite is the fast backup at 1.2 s.
- Larger models were barely more accurate and slower.

## 7. Speed: where the time actually goes
Rough per-step budget with this setup: text recognition ~0.1 s + decision ~0.2–0.5 s (incl. network from India) + **device pointer move ~1 s**. Today our `goTo` pushes to the corner (40 reports) and then moves in 5-count steps at 15 ms per report, so a tap mid-screen takes about **1 s just to move**. Once the brain is fast, **the pointer becomes the slowest part**. Fixes to test: move from the current position instead of the corner, and bigger calibrated steps.

## 8. How T8/T11 should run
Same ~20 real iPhone screens and goals for every candidate, called **from India**, thinking off, and measured:
- correct action rate;
- seconds per call (median and slowest 5%);
- cost per step;
- for the fast brain, how often it hands over to the big brain.

**Keys needed:** OpenAI, Google AI Studio, Anthropic, Cloudflare (account + API token), and Jev (TypeSafe, or through OpenRouter). Measure direct APIs for speed: routers like OpenRouter add a hop.

**Plan (2026-11-07):** round 1 compares many models through **OpenRouter** (one key, easy to switch; same plain prompt for all, coordinates asked as JSON so every model is judged the same way). Round 2 re-times the winners with **direct** keys from India, and tests Claude's own computer-use tool (zoom) there, since it may not pass through OpenRouter. Note: through OpenRouter, Claude Sonnet 5.5 and Gemini 3.8 Flash can't turn thinking fully off (lowest is `low`); Claude Haiku 5.5, GPT-6.1 Terra and GPT-6 Luna can (`none`).
