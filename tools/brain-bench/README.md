# Brain bench (T8 / T11)

Scripts that ask AI models about real iPhone screens and time each answer, to choose Mantiza's fast brain and big brain ([research](../../Docs/Mantiza%20Roadmap/ai-brain-research.md)).

- **Round 1 (now):** many models through OpenRouter, one key.
- **Round 2 (later):** the winners again through their own direct APIs, for true speed.

## Setup
- Python 3 with `requests` and `Pillow`.
- `OPENROUTER_API_KEY=...` in `C:\Users\PC\.mantiza\keys.env`, which is outside the repo. The scripts read it and never print it.

## Files
- `common.py`: reads the key, shrinks screenshots to JPEG (long side ≤ 1568 px, Jev's limit), and sends calls over one kept-alive connection.
- `smoke.py`: a quick check on one known screen (`screens/picker.jpg`, the screen-sharing picker) with fast-brain choice questions, a Jev box question and big-brain "where to tap" calls. Run it with `python smoke.py`; it costs about $0.02.
- `tasks.py`: the exam. It has 20 screens with every tappable element boxed by hand, 82 tasks ("Send the typed message") with known answers, and 12 yes/no checks ("Is Wi-Fi on?").
- `bench.py`: runs every candidate on the exam.
  - `python bench.py` runs everything: every model at once, for accuracy.
  - `python bench.py marks` runs the numbered-box exam.
  - `python bench.py timing` runs one model at a time, for clean speed.
- `speed.py`: the speed round (2026-11-15). It calls the app's two brains with the app's own image size and prompts, and compares settings. Results and what they changed: [speed research](../../Docs/Mantiza%20Roadmap/speed-research.md).
- `rescore.py`: re-marks a saved run after an answer key fix, without calling any models.
- `screens/`: test screenshots. **Only `picker.jpg` is committed**; other screenshots stay local because they may show private data.

## How calls are made (OpenRouter)
- **Fast brain:** `POST https://openrouter.ai/api/alpha/decisions` with `model`, `state` (text plus an `image_url` data URL) and `questions` (`choice`, `noul`, `score`, and `box` on Jev only). It answers with typed answers and probabilities, not text. The endpoint is alpha, so its shape may change.
- **Big brain:** `POST https://openrouter.ai/api/v1/responses` with `input` (`input_text` + `input_image`) and `reasoning.effort`.
  - Gemini points on a 0–1000 grid, so it is asked that way.
  - Claude and GPT are asked in pixels.
- **Thinking through OpenRouter:**
  - `none` (fully off) works for Claude Haiku 5.5, GPT-6.1 Terra and GPT-6 Luna.
  - Claude Sonnet 5.5 and Gemini 3.8 Flash only go down to `low`.

## Smoke test, 2026-11-07 (from India, one kept-alive connection)

| Model | Job | Time per call | Right answer? | Cost per call |
|---|---|---|---|---|
| OpenAI GPT-6 Luna Decisions | which item | 0.45 s | ✅ conf 1.0 | $0.00015 |
| TypeSafe Jev 1.14 | which item | 0.45–0.51 s | ✅ conf 1.0 | $0.00014 |
| Cloudflare Clef | which item | 0.7–1.5 s | ✅ conf 0.94 | $0.00031 |
| Cloudflare Clef-flash | which item | 0.45–0.9 s | ✅ conf 0.69 | $0.00005 |
| Jev 1.14 box | where is it | 0.46–0.54 s | ✅ (inside the button) | $0.00026 |
| Claude Haiku 5.5, thinking none | where to tap | 1.46 s | ✅ | $0.00017 |
| Claude Sonnet 5.5, thinking low | where to tap | 1.75–3.05 s | ✅ | $0.0034 |
| GPT-6.1 Terra, thinking none | where to tap | 2.0–2.1 s | ✅ | $0.0019 (cached $0.0002) |
| Gemini 3.8 Flash, thinking low | where to tap | 2.5 s | ✅ (0–1000 grid) | $0.0015 |

This is one easy screen, so it only shows that everything works. The real comparison needs about 20 screens.

## Round 1 results, 2026-11-07 (OpenRouter, from India)

The exam has 19 real screens from the iPhone 14 Plus, plus the picker: Snapchat, Instagram, Control Centre, App Library, Home Screen, Google Maps ×2, Camera, YouTube ×2, Clock ×2, Settings ×3, Phone ×2 and WhatsApp. There are 82 tasks and 12 checks. The screenshots came through WhatsApp, so they are compressed to 740×1600. The whole round cost $1.92.

### Fast brain: "which numbered box should be tapped?"
Pink numbered boxes are drawn on the screenshot, and the model answers only with a number. This is the realistic test. An easier version with a written description of every button ("green send arrow") gave 98–100% for nearly every model, so it couldn't tell them apart.

In the real app, the fast brain acts alone only when it is **sure**. Otherwise the step goes to the big brain. What matters is how often it is sure, and whether it is ever **sure but wrong**, which would tap the wrong thing.

| Model | Correct overall | Sure at ≥ 0.5 confidence (of 82) | Sure but wrong | Median time |
|---|---|---|---|---|
| **OpenAI GPT-6 Luna Decisions** | 79/82 (96%) | 71 | **0** | **0.43 s** |
| TypeSafe Jev 1.14 | 80/82 (98%) | 81 (78 at ≥ 0.7) | 1 | 0.55 s |
| Liquid d1.1 | 81/82 (99%) | 81 (76 at ≥ 0.7) | 1 (0 at ≥ 0.7) | 0.76 s |
| Respan span-02 | 79/82 (96%) | 79 (78 at ≥ 0.7) | 1 (0 at ≥ 0.7) | 0.72 s |
| Perplexity Decider v1.2 | 81/82 (99%) | 82 (76 at ≥ 0.7) | 1 (0 at ≥ 0.7) | 0.83 s |
| Liquid d1-ultra | 81/82 (99%) | 81 | 0 | 0.93 s |
| Inception Mercury Decide | 78/82 (95%) | 81 | 3 | 0.80 s |
| Cloudflare Clef-flash | 77/82 (94%) | 69 | 3 | 0.47 s |
| Cloudflare Clef | 77/82 (94%) | 75 | 1 | 1.22 s |
| Baseten Joey 1 | 67/82 (82%) | 60 | 7 | 0.90 s |

The other decision models (Mammoth, Elephant, Reflex, Drex-max, Perplexity Decider flash) scored 95–98%, with 1–3 sure-but-wrong answers and times of 0.7–1.0 s. Cloudflare Clairic had no endpoint on OpenRouter yet.

"Did it work?" checks: most models answered 12/12. Luna Decisions answered 12/12 at 0.81 s.

**Jev's box question** (pointing by itself): 60/82 (73%), so it can't replace the big brain.

### Big brain: "where should I tap?" (x, y on the screenshot, least thinking allowed)
| Model | Correct, all 82 | Clean time (one model at a time) | Cost per call |
|---|---|---|---|
| Google Gemini 3.5 Flash-Lite (minimal) | 80/82 (98%) | **1.19 s** | $0.0004 |
| **Anthropic Claude Haiku 5.5 (thinking off)** | 80/82 (98%) | 1.84 s | **$0.0002** |
| Anthropic Claude Sonnet 5.5 (low) | 80/82 (98%) | 2.17 s | $0.0034 |
| OpenAI GPT-6.1 Terra (none) | 81/82 (99%) | 2.29 s | $0.0019 (cached $0.0002) |
| Anthropic Claude Opus 5.5 (low) | 81/82 (99%) | 2.84 s | $0.0068 |
| Google Gemini 3.8 Flash (low) | 81/82 (99%) | 3.53 s (some up to 9 s) | $0.0015 |
| OpenAI GPT-6 Luna, chat version (none) | 77/82 (94%) | 2.1 s* | $0.0002 |
| OpenAI GPT-6.1 Sol (low) | 80/82 (98%) | 2.5 s* | $0.0038 |

\* Measured while all the models were running at once.

### What this means
- **Fast brain: OpenAI Luna Decisions is the best fit.** It is the fastest (0.43 s). When it is at least 50% sure, which was 71 of 82 steps, it was **never wrong**. On the other 11 it says it is unsure and hands over. Jev is a close second: a bit slower, sure more often, with one confident mistake.
- **Big brain: Claude Haiku 5.5 with thinking off.** It was 98% right at 1.8 s and the cheapest. Gemini 3.5 Flash-Lite is faster (1.2 s) and also a good backup. Bigger models (Sonnet, Opus, Terra, Gemini 3.8 Flash) were barely more accurate on this exam and 1.2–2× slower.
- **Expected time per step:** about 0.43 s, plus 13% of steps × 1.8 s at the big brain, which averages about 0.7 s of AI time. Add about 1 s of pointer movement, which is now the slowest part.
- **Cost per step:** about $0.0003.

### Limits of this round
- **Single steps only.** The exam doesn't test whole tasks, planning or recovering from mistakes.
- **One iPhone model, compressed screenshots.**
- In the numbered-box exam, **the boxes were drawn by hand**. The real app must find them by itself. Apple's text recognition only finds text, so icon-only buttons need another way, or the big brain.
- **Times go through OpenRouter**, which adds a hop. Round 2 measures the winners through the direct APIs.
- New OpenRouter accounts are limited to **20 calls per minute per big model**.
