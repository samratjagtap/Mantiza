# Making the AI route fast and right (research and build, 2026-11-15)

The AI route is what Mantiza uses when neither Siri nor a direct iOS route can do the job: it looks at the
screen, decides, and taps, step by step. This note records where a step's time went, what the research and
our own measurements say, and what was built.

Tags: **[Measured]** = our own numbers · **[Docs]** = the service's own documentation ·
**[Paper]** = published research · **[To check]** = built, not yet run on the iPhone.

## 1. Where the time went (13 real runs, 83 AI steps, 10–13 Nov) **[Measured]**

| Part of a step | Time | Notes |
|---|---|---|
| Waiting for the screen to settle | **about 2.5 s** | Nearly always ran to its time limit |
| Reading the text (on the phone) | 0.4 s | |
| Fast brain | 1.1 s median | Asked first, every step |
| Big brain | 1.8–2.7 s median | Asked **after** the fast brain, on almost every step (83 calls in 83 steps) |
| Tap | 0.3 s | |
| **Whole step** | **6–7 s at best, 15–20 s on a bad connection** | |

Three things stood out:
- **The wait, not the AI, was the biggest part.** "Settled" meant "no new frame from iOS", but iOS keeps
  sending frames for the clock, the red recording pill and blinking cursors. The wait hit its 2.5 s limit
  on nearly every step.
- **The brains ran one after the other.** The fast brain was rarely sure, so most steps paid for both.
- **Slow calls waited for a 12 s timeout, then retried.** That is how steps reached 15–20 s.

## 2. What the services can do (speed round, 82 tasks on 20 real iPhone screens) **[Measured]**

Run with [speed.py](../../tools/brain-bench/speed.py), calling the services directly, with the image exactly
as the app sends it (642 px wide, JPEG quality 70).

| Test | Right | Median time |
|---|---|---|
| Big brain, old prompt ("where to tap?") | 78/82 | 0.93 s |
| Big brain, new prompt (any action) | 76–78/82 (two "misses" answered "back", which is right) | 0.93 s |
| Big brain, new prompt, medium image | 78/82 | 0.92 s |
| Big brain, new prompt, low image | 75/82 | 0.93 s |
| Fast brain, image detail auto or high | 76/82 | 0.44 s |
| Fast brain, image detail low | 61/82 | 0.30 s |

What this settled:
- **A smaller image doesn't make the big brain faster** (0.92 s vs 0.93 s) and a low one costs accuracy.
  The image stays as it is.
- **A richer prompt costs nothing.** The big brain can be asked for any action, not only a tap, at the same
  speed and accuracy.
- **The fast brain needs a higher bar.** At the app's image size it was wrong 4 times in 82 when 50–70% sure,
  and never when 70% or more sure (66 of 82 tasks). The old bar was 50%.
- **Low image detail for the fast brain is a bad trade:** 0.14 s saved, 15 more wrong answers.
- **Moves that aren't taps work.** 11 of 11 probes were right: scroll, press and hold, type with Return,
  swipe, "done", "can't be done from here", and five weekday buttons from one answer.

## 3. What the research says

- **Split the work: a slow planner, a fast executor.** Jev-Mobile uses a large model for local goals and a
  fast decision model for each action: 33% less total time and 73% less cost than a large model on every
  step, for 5 points less success (79% vs 84%) **[Paper]**. Mantiza already has this shape. The lesson is
  the cost: the fast model alone is less accurate, so ours acts alone only when it is sure.
- **Reuse what worked.** ActionEngine compiles repeated tasks into fixed programs: model calls fall from
  10.2 to 1.8 per task and time is halved **[Paper]**. Mantiza's learned routines do this; the plan itself
  is now remembered too.
- **Several actions from one decision.** UFO² runs a batch of actions and checks the screen before each
  **[Paper]**. Built here for several taps on one screen.
- **Checking costs time too.** One study found reflection steps were 76–96% of task time **[Paper]**. Our
  check is free: the fast brain's "is the goal reached?" rides along in the call it already makes.
- **Thinking must stay off for per-step calls.** Gemini 3.5 Flash-Lite defaults to minimal thinking
  **[Docs]**; nothing to change.
- **Decision API options:** image `detail`, prompt caching and per-choice probabilities **[Docs]**. Caching
  doesn't help us (the image changes every step). `detail: low` was measured above and rejected.

## 4. What was built **[To check]**

| Change | Time saved per step | How |
|---|---|---|
| Settle by picture, not by frames | up to about 2 s | Each frame is reduced to a grid of brightness samples below the status bar. Only a real difference counts as a change. After an action Mantiza waits for the change to start, then for it to stop. |
| Both brains at once | about 1 s on steps the big brain decides | The fast brain acts alone when it is 70% sure or more; otherwise the big brain's answer is already on its way. |
| Big brain asked while the text is read | about 0.4 s | It only needs the picture. |
| Second request after 2.5 s (1.5 s for the fast brain) | the 6–12 s outliers | The first answer wins. Timeout 8 s instead of 12 s. A busy server (HTTP 503) is asked once more. |
| Connections opened during planning | a few hundred ms on the first step | |
| Screen sharing started during planning | about 2.7 s on the first task after unlocking | |
| Plan remembered for a repeated request | about 2 s per task | Only plans that worked, that don't depend on the day or time, from the same build, for 14 days. |
| Several taps from one answer | about 2 s per extra tap | Only on the same screen, checked before each tap, never in tasks that need your OK. |

Accuracy changes:
- **The big brain chooses any action:** tap, press and hold, type (with Return for search boxes), scroll up
  or down, swipe left or right, back, wait, done, or "can't get there from here". Before, it could only tap,
  so a loading screen or a finished task still got a tap.
- **"Done" needs both brains.** If only one says done, Mantiza follows the other or looks once more.
- **A slow app isn't tapped twice.** If the words on screen are the same as before the action, Mantiza waits
  until 1.6 s after it before deciding nothing happened.
- **Gestures are checked.** A scroll, swipe or back that changed nothing is reported to the brains so they
  choose another way.
- **Learned routines record the new gestures** and replay them without AI.

Expected step time on Wi-Fi: **about 1.5–3 s** instead of 6–7 s. This is an estimate from the parts above;
the next debug reports show the real numbers (each step now logs `look`, `decide`, which brain decided,
and `tap`).

## 5. Looked at and not done

| Idea | Why not |
|---|---|
| Smaller or lower-detail images | Measured: no faster for the big brain, less accurate for the fast one |
| A direct OpenAI key for the fast brain | The speed round ran through OpenRouter at 0.44 s, the same as before; no clear gain. Worth one check if a key is added. |
| An on-phone AI model | Apple's on-device model needs an iPhone 15 Pro or newer; the 14 Plus can't run it ([brain research](ai-brain-research.md)) |
| Guessing the next step ahead of time | Research gains were 10–19% on other kinds of agents, and a wrong guess taps the wrong thing |

## Sources
- Papers: [Jev-Mobile](https://arxiv.org/abs/2609.30186) · [Efficient GUI Agents: a systems survey](https://arxiv.org/abs/2609.02309) (ActionEngine, V-Droid, OSWorld-Human) · [UFO²](https://arxiv.org/pdf/2504.14603) · [PastForward](https://arxiv.org/html/2609.32166) · [Speculative Macro Commit](https://arxiv.org/abs/2609.03236)
- Docs: [OpenAI Decisions API reference](https://developers.openai.com/api/reference/resources/decisions/methods/create) · [Gemini 3.6 Flash and 3.5 Flash-Lite](https://ai.google.dev/gemini-api/docs/generate-content/whats-new-gemini-3.6) · [Gemini media resolution](https://ai.google.dev/gemini-api/docs/media-resolution)
- Background: [Jev box tool on ScreenSpot](https://dev.to/arthurkatcher/i-benchmarked-jevs-box-tool-on-screenspot-v2-and-screenspot-pro-here-is-how-well-it-reads-a-screen-32fb) · [Decisions API on images](https://nyosegawa.com/en/posts/openai-decisions-api-image-classification/)
