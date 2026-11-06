"""Smoke test: is the OpenRouter key working, and do both kinds of call work?

Uses one real iPhone screen (the screen-sharing picker) where the right answer is known:
"Share Entire Screen". Prints time and answer per model. Costs well under $0.05.

Run:  python tools/brain-bench/smoke.py
"""
import sys
from pathlib import Path

from common import data_url, get, image_jpeg, parse_json, post, response_text
import base64

HERE = Path(__file__).parent
SCREEN = HERE / "screens" / "picker.jpg"
GOAL = "Share the whole iPhone screen."
# Where "Share Entire Screen" is, as fractions of the image (measured by hand on picker.jpg)
TARGET = dict(left=0.17, right=0.83, top=0.553, bottom=0.607)


def inside(fx: float, fy: float) -> bool:
    return TARGET["left"] <= fx <= TARGET["right"] and TARGET["top"] <= fy <= TARGET["bottom"]


def check_key():
    info = get("/api/v1/key")["data"]
    print(f"Key OK. Used ${info.get('usage', 0):.4f}, limit {info.get('limit')}, free tier {info.get('is_free_tier')}")


def decision(model: str, jpeg: bytes):
    body = {
        "model": model,
        "state": [f"iPhone screenshot. Goal: {GOAL}",
                  {"type": "image_url", "image_url": {"url": data_url(jpeg)}}],
        "questions": {
            "tap": {
                "type": "choice",
                "instructions": "Which item on the screen should be tapped next to reach the goal?",
                "criteria": {
                    "share_entire_screen": "the 'Share Entire Screen' button",
                    "mantiza_test": "the 'Mantiza Test' row",
                    "record_icon": "the round record icon at the top of the panel",
                    "outside": "the empty dark area outside the panel",
                },
            },
            "done": {"type": "noul", "instructions": "Is the goal already reached on this screen?"},
        },
    }
    resp, dt = post("/api/alpha/decisions", body)
    a = resp["answers"]["tap"]
    ok = a.get("choice") == "share_entire_screen"
    print(f"  {model:34s} {dt:5.2f}s  choice={a.get('choice')} conf={a.get('confidence')} "
          f"done={resp['answers']['done'].get('noul')}  {'OK' if ok else 'WRONG'}  "
          f"cost=${resp.get('usage', {}).get('cost')}")


def box(model: str, jpeg: bytes):
    body = {
        "model": model,
        "assets": {"screen": {"type": "image", "format": "jpg",
                              "data_base64": base64.b64encode(jpeg).decode()}},
        "state": ["screen"],
        "questions": {"target": {"type": "box",
                                 "instructions": "In screen, locate the 'Share Entire Screen' button."}},
    }
    resp, dt = post("/api/alpha/decisions", body)
    a = resp["answers"]["target"]
    b = a.get("box") or {}
    fx = (b.get("left", 0) + b.get("right", 0)) / 2
    fy = (b.get("top", 0) + b.get("bottom", 0)) / 2
    print(f"  {model:34s} {dt:5.2f}s  box centre=({fx:.3f},{fy:.3f}) conf={a.get('confidence')}  "
          f"{'OK' if inside(fx, fy) else 'MISS'}  cost=${resp.get('usage', {}).get('cost')}")


def bigbrain(model: str, effort: str, jpeg: bytes, w: int, h: int):
    gemini = model.startswith("google/")
    # Gemini is trained to point on a 0-1000 grid; Claude and GPT in pixels. Ask each in its own way.
    unit = "on a 0-1000 grid (0,0 top-left, 1000,1000 bottom-right)" if gemini else "in pixels"
    prompt = (f"This is an iPhone screenshot, {w}x{h} pixels. Goal: {GOAL}\n"
              f"Where should the user tap next? Give the point {unit}. Reply with only JSON: "
              '{"x": <x>, "y": <y>, "what": "<short label>"}')
    sx, sy = (1000, 1000) if gemini else (w, h)
    body = {
        "model": model,
        "input": [{"type": "message", "role": "user", "content": [
            {"type": "input_text", "text": prompt},
            {"type": "input_image", "image_url": data_url(jpeg), "detail": "high"}]}],
        "reasoning": {"effort": effort},
        "max_output_tokens": 3000,
    }
    resp, dt = post("/api/v1/responses", body)
    text = response_text(resp)
    j = parse_json(text) or {}
    try:
        fx, fy = float(j["x"]) / sx, float(j["y"]) / sy
        verdict = "OK" if inside(fx, fy) else "MISS"
        where = f"({j['x']},{j['y']}) '{j.get('what')}'"
    except (KeyError, TypeError, ValueError):
        verdict, where = "NO JSON", repr(text[:80])
    u = resp.get("usage", {})
    print(f"  {model + ' [' + effort + ']':34s} {dt:5.2f}s  {where}  {verdict}  "
          f"tokens in/out={u.get('input_tokens')}/{u.get('output_tokens')} cost=${u.get('cost')}")


def run(label, fn, *args):
    try:
        fn(*args)
    except Exception as e:  # keep going so one failure doesn't hide the rest
        print(f"  {label:34s} ERROR {e}")


if __name__ == "__main__":
    check_key()
    jpeg, w, h = image_jpeg(SCREEN)
    print(f"Screen {SCREEN.name}: {w}x{h}, {len(jpeg) // 1024} KB\n")

    print("Fast brain (decision, 'which item?')")
    for m in sys.argv[1:] or ["openai/gpt-6-luna-decisions", "typesafe/jev-1.14", "cloudflare/clef",
                              "cloudflare/clef-flash"]:
        for _ in range(3):
            run(m, decision, m, jpeg)

    print("\nJev box question ('where is it?')")
    for _ in range(3):
        run("typesafe/jev-1.14", box, "typesafe/jev-1.14", jpeg)

    print("\nBig brain ('where to tap?', least thinking OpenRouter allows)")
    for m, e in [("anthropic/claude-sonnet-5.5", "low"), ("anthropic/claude-haiku-5.5", "none"),
                 ("google/gemini-3.8-flash", "low"), ("openai/gpt-6.1-terra", "none")]:
        for _ in range(2):
            run(m, bigbrain, m, e, jpeg, w, h)
