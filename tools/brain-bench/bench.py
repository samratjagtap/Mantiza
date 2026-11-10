"""Round 1 of T8/T11: every candidate model on every task in tasks.py, through OpenRouter.

Jobs measured:
  pick   fast brain: "which element should be tapped for this goal?" (decision choice question)
  check  fast brain: "did it work?" yes/no about the screen (decision noul question)
  box    Jev only: "where is the element for this goal?" (decision box question)
  point  big brain: "where should I tap?" as x, y (Responses API, least thinking allowed)

One thread per model (each with its own kept-alive connection), calls inside a model run one after another,
so each timing is a single call. Results: results/run-<time>.jsonl and results/summary-<time>.md.

Run:  python bench.py            (everything, about $3)
      python bench.py fast       (decision models only, about $0.40)
      python bench.py big        (big-brain models only)
"""
import base64
import io
import json
import statistics
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

from common import data_url, image_jpeg, parse_json, post, response_text
from tasks import CHECKS, SCREENS, TASKS

HERE = Path(__file__).parent
SRC_W, SRC_H = 740, 1600  # size of the labelled screenshots

FAST = [  # every image-capable decision model on OpenRouter (2026-11-07), no "latest" aliases
    "openai/gpt-6-luna-decisions", "typesafe/jev-1.14", "cloudflare/clef", "cloudflare/clef-flash",
    "cloudflare/clairic", "perplexity/pplx-decider-v1.2", "perplexity/pplx-decider-flash-v1.2",
    "liquid/d1-ultra", "liquid/d1.1", "inception/mercury-decide", "baseten/mammoth-1",
    "baseten/elephant-1", "baseten/joey-1", "morph/reflex", "nace-ai/drex-max", "respan/span-02",
]  # scaledown/classify-1 left out: it rejects image_url parts
BIG = [  # (model, least thinking OpenRouter accepts for it)
    ("anthropic/claude-sonnet-5.5", "low"), ("anthropic/claude-haiku-5.5", "none"),
    ("anthropic/claude-opus-5.5", "low"), ("google/gemini-3.8-flash", "low"),
    ("google/gemini-3.5-flash-lite", "minimal"), ("openai/gpt-6.1-terra", "none"),
    ("openai/gpt-6.1-sol", "low"), ("openai/gpt-6-luna", "none"),
]

TIMING_FAST = ["openai/gpt-6-luna-decisions", "typesafe/jev-1.14", "cloudflare/clef-flash", "cloudflare/clef",
               "inception/mercury-decide", "perplexity/pplx-decider-flash-v1.2", "liquid/d1.1",
               "baseten/elephant-1", "morph/reflex", "nace-ai/drex-max"]
TIMING_BIG = [("anthropic/claude-haiku-5.5", "none"), ("google/gemini-3.5-flash-lite", "minimal"),
              ("anthropic/claude-sonnet-5.5", "low"), ("anthropic/claude-opus-5.5", "low"),
              ("google/gemini-3.8-flash", "low"), ("openai/gpt-6.1-terra", "none")]


def paced(fn, gap=3.2):
    """New OpenRouter accounts get 20 requests/minute per big model: keep calls >= 3 s apart."""
    def wrapper(*args):
        t = time.time()
        r = fn(*args)
        time.sleep(max(0, gap - (time.time() - t)))
        return r
    wrapper.__name__ = fn.__name__
    return wrapper


_images = {}
_lock = threading.Lock()


def screen_image(key):
    with _lock:
        if key not in _images:
            jpeg, w, h = image_jpeg(HERE / "screens" / SCREENS[key]["file"])
            _images[key] = (jpeg, w, h)
        return _images[key]


def hit(screen, accepted, fx, fy):
    """Is the point (fractions of the image) inside one of the accepted elements?"""
    for eid in accepted:
        l, t, r, b = SCREENS[screen]["elements"][eid][1]
        if l / SRC_W <= fx <= r / SRC_W and t / SRC_H <= fy <= b / SRC_H:
            return True
    return False


def call(path, body, tries=2):
    for attempt in range(tries):
        try:
            return post(path, body)
        except RuntimeError as e:
            retry = any(f"HTTP {c}" in str(e) for c in (429, 500, 502, 503, 524, 529))
            if not retry or attempt == tries - 1:
                raise
            time.sleep(3)


# ---- jobs -------------------------------------------------------------------------------------

def pick(model, screen, goal, accepted):
    jpeg, _, _ = screen_image(screen)
    els = SCREENS[screen]["elements"]
    body = {"model": model,
            "state": [f"iPhone screenshot ({SCREENS[screen]['about']}). Goal: {goal}",
                      {"type": "image_url", "image_url": {"url": data_url(jpeg)}}],
            "questions": {"tap": {"type": "choice",
                                  "instructions": "Which element on this screen should be tapped next to reach the goal?",
                                  "criteria": {eid: desc for eid, (desc, _) in els.items()}}}}
    resp, dt = call("/api/alpha/decisions", body)
    a = resp["answers"]["tap"]
    if a.get("type") == "refusal":
        return dict(ok=False, s=dt, answer="refusal", conf=None, cost=resp.get("usage", {}).get("cost"))
    return dict(ok=a.get("choice") in accepted, s=dt, answer=a.get("choice"), conf=a.get("confidence"),
                cost=resp.get("usage", {}).get("cost"))


_marked = {}


def marked_image(screen):
    """Screenshot with every known element drawn as a numbered box (numbers shuffled per screen, so
    position gives no hint). Returns (jpeg, {element id: number})."""
    import io as _io
    import random
    from PIL import Image, ImageDraw, ImageFont
    with _lock:
        if screen in _marked:
            return _marked[screen]
        ids = list(SCREENS[screen]["elements"])
        random.Random(screen).shuffle(ids)
        nums = {eid: str(i + 1) for i, eid in enumerate(ids)}
        img = Image.open(HERE / "screens" / SCREENS[screen]["file"]).convert("RGB")
        d = ImageDraw.Draw(img)
        try:
            font = ImageFont.truetype("arialbd.ttf", 22)
        except OSError:
            font = ImageFont.load_default()
        for eid, (_, b) in SCREENS[screen]["elements"].items():
            d.rectangle(b, outline=(255, 0, 200), width=3)
            label = nums[eid]
            tw = 14 * len(label) + 8
            y = b[1] - 26 if b[1] >= 26 else b[3]  # tag sits just above the box, never over the icon
            d.rectangle((b[0], y, b[0] + tw, y + 26), fill=(255, 0, 200))
            d.text((b[0] + 4, y), label, fill=(255, 255, 255), font=font)
        scale = min(1.0, 1568 / max(img.size))  # Jev's size limit
        if scale < 1:
            img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
        buf = _io.BytesIO()
        img.save(buf, "JPEG", quality=85)
        _marked[screen] = (buf.getvalue(), nums)
        return _marked[screen]


def marks(model, screen, goal, accepted):
    """Like pick, but the only hint is a numbered box drawn on the screenshot: closer to real life."""
    jpeg, nums = marked_image(screen)
    body = {"model": model,
            "state": [f"iPhone screenshot with numbered pink boxes around the things that can be tapped. Goal: {goal}",
                      {"type": "image_url", "image_url": {"url": data_url(jpeg)}}],
            "questions": {"tap": {"type": "choice",
                                  "instructions": "Which numbered box should be tapped next to reach the goal?",
                                  "criteria": {n: f"box {n}" for n in sorted(nums.values(), key=int)}}}}
    resp, dt = call("/api/alpha/decisions", body)
    a = resp["answers"]["tap"]
    ok_nums = {nums[e] for e in accepted}
    return dict(ok=a.get("choice") in ok_nums, s=dt, answer=a.get("choice"), conf=a.get("confidence"),
                cost=resp.get("usage", {}).get("cost"))


def check(model, screen, question, truth):
    jpeg, _, _ = screen_image(screen)
    body = {"model": model,
            "state": [f"iPhone screenshot ({SCREENS[screen]['about']}).",
                      {"type": "image_url", "image_url": {"url": data_url(jpeg)}}],
            "questions": {"q": {"type": "noul", "instructions": question}}}
    resp, dt = call("/api/alpha/decisions", body)
    a = resp["answers"]["q"]
    p = a.get("noul")
    if p is None:
        return dict(ok=False, s=dt, answer="refusal", conf=None, cost=resp.get("usage", {}).get("cost"))
    return dict(ok=(p >= 0.5) == truth, s=dt, answer=round(p, 3), conf=abs(p - 0.5) * 2,
                cost=resp.get("usage", {}).get("cost"))


def box(model, screen, goal, accepted):
    jpeg, _, _ = screen_image(screen)
    body = {"model": model,
            "assets": {"screen": {"type": "image", "format": "jpg", "data_base64": base64.b64encode(jpeg).decode()}},
            "state": ["screen"],
            "questions": {"t": {"type": "box",
                                "instructions": f"In screen (an iPhone screenshot), locate the element to tap next to: {goal}"}}}
    resp, dt = call("/api/alpha/decisions", body)
    a = resp["answers"]["t"]
    b = a.get("box")
    if not b:
        return dict(ok=False, s=dt, answer="no box", conf=a.get("confidence"), cost=resp.get("usage", {}).get("cost"))
    fx, fy = (b["left"] + b["right"]) / 2, (b["top"] + b["bottom"]) / 2
    return dict(ok=hit(screen, accepted, fx, fy), s=dt, answer=[round(fx, 3), round(fy, 3)],
                conf=a.get("confidence"), cost=resp.get("usage", {}).get("cost"))


def point(model, effort, screen, goal, accepted):
    jpeg, w, h = screen_image(screen)
    gemini = model.startswith("google/")
    unit = "on a 0-1000 grid (0,0 top-left, 1000,1000 bottom-right)" if gemini else "in pixels"
    sx, sy = (1000, 1000) if gemini else (w, h)
    prompt = (f"This is an iPhone screenshot, {w}x{h} pixels. Goal: {goal}\n"
              f"Where should the user tap next? Give the point {unit}. Reply with only JSON: "
              '{"x": <x>, "y": <y>, "what": "<short label>"}')
    body = {"model": model,
            "input": [{"type": "message", "role": "user", "content": [
                {"type": "input_text", "text": prompt},
                {"type": "input_image", "image_url": data_url(jpeg), "detail": "high"}]}],
            "reasoning": {"effort": effort}, "max_output_tokens": 4000}
    resp, dt = call("/api/v1/responses", body)
    u = resp.get("usage", {})
    j = parse_json(response_text(resp)) or {}
    try:
        fx, fy = float(j["x"]) / sx, float(j["y"]) / sy
    except (KeyError, TypeError, ValueError):
        return dict(ok=False, s=dt, answer="no json", conf=None, cost=u.get("cost"), out_tokens=u.get("output_tokens"))
    return dict(ok=hit(screen, accepted, fx, fy), s=dt, answer=[round(fx, 3), round(fy, 3), j.get("what")],
                conf=None, cost=u.get("cost"), out_tokens=u.get("output_tokens"))


# ---- runner -----------------------------------------------------------------------------------

def run_model(model, jobs, out, effort=None):
    rows = []
    for job, fn, items in jobs:
        for i, item in enumerate(items):
            rec = dict(model=model, job=job, item=i, screen=item[0], goal=item[1])
            try:
                rec.update(fn(model, effort, *item) if effort is not None else fn(model, *item))
            except Exception as e:
                rec.update(ok=False, error=str(e)[:300])
            rows.append(rec)
            with _lock:
                out.write(json.dumps(rec) + "\n")
                out.flush()
    with _lock:
        n = sum(r.get("ok", False) for r in rows)
        print(f"  done {model}: {n}/{len(rows)} correct, {sum('error' in r for r in rows)} errors", flush=True)
    return rows


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(q * len(xs)))] if xs else float("nan")


def summarize(rows):
    lines = []
    for job in ("pick", "marks", "check", "box", "point"):
        sub = [r for r in rows if r["job"] == job]
        if not sub:
            continue
        lines.append(f"\n### {job}\n")
        lines.append("| Model | Correct | Errors | Median s | Slowest 10% s | Avg cost/call | Sure (conf ≥ 0.9) | Correct when sure |")
        lines.append("|---|---|---|---|---|---|---|---|")
        stats = []
        for model in sorted({r["model"] for r in sub}):
            rs = [r for r in sub if r["model"] == model]
            ok = sum(r.get("ok", False) for r in rs)
            errs = sum("error" in r for r in rs)
            times = [r["s"] for r in rs if "s" in r]
            costs = [r["cost"] for r in rs if isinstance(r.get("cost"), (int, float))]
            sure = [r for r in rs if isinstance(r.get("conf"), (int, float)) and r["conf"] >= 0.9]
            sure_ok = sum(r.get("ok", False) for r in sure)
            stats.append((ok / len(rs), model, rs, ok, errs, times, costs, sure, sure_ok))
        for acc, model, rs, ok, errs, times, costs, sure, sure_ok in sorted(stats, key=lambda x: -x[0]):
            med = statistics.median(times) if times else float("nan")
            lines.append(f"| {model} | {ok}/{len(rs)} ({acc:.0%}) | {errs} | {med:.2f} | {pct(times, 0.9):.2f} | "
                         f"{('$%.5f' % (sum(costs) / len(costs))) if costs else '-'} | "
                         f"{(f'{len(sure)}/{len(rs)}') if sure else '-'} | "
                         f"{(f'{sure_ok}/{len(sure)}') if sure else '-'} |")
    return "\n".join(lines)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    (HERE / "results").mkdir(exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M")
    path = HERE / "results" / f"run-{stamp}.jsonl"
    print(f"{len(TASKS)} tasks, {len(CHECKS)} checks, {len(SCREENS)} screens -> {path.name}", flush=True)
    work = []
    if what in ("all", "fast"):
        for m in FAST:
            jobs = [("pick", pick, TASKS), ("check", check, CHECKS)]
            if m.startswith("typesafe/"):
                jobs.append(("box", box, TASKS))
            work.append((m, jobs, None))
    if what in ("all", "big"):
        for m, effort in BIG:
            work.append((m, [("point", point, TASKS)], effort))
    if what == "marks":
        only = sys.argv[2:]  # optional: just these models
        work = [(m, [("marks", marks, TASKS)], None) for m in (only or FAST)]
    workers = len(work)
    if what == "timing":
        # one model at a time, nothing else running: clean single-call times
        sample = TASKS[::6]
        work = [(m, [("pick", pick, sample)], None) for m in TIMING_FAST]
        work += [(m, [("point", paced(point), sample)], e) for m, e in TIMING_BIG]
        workers = 1
    t0 = time.time()
    with open(path, "w", encoding="utf-8") as out, ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(run_model, m, jobs, out, effort) for m, jobs, effort in work]
        rows = [r for f in futures for r in f.result()]
    summary = f"# Brain bench run {stamp}\n\n{len(TASKS)} tasks, {len(CHECKS)} checks. Took {time.time() - t0:.0f} s.\n" + summarize(rows)
    (HERE / "results" / f"summary-{stamp}.md").write_text(summary, encoding="utf-8")
    print(summary)
