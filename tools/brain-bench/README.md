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
