#!/usr/bin/env python3
"""End-to-end tests on the real iPhone, driven from the Mac.

    python3 tools/e2e/e2e.py events                      # follow the app's E2E events (device log)
    python3 tools/e2e/e2e.py shot out.png                # phone screenshot + the text on it
    python3 tools/e2e/e2e.py run tools/e2e/scenarios/look.json

The stick is driven over USB (tools/hands_cli.py); the app's structured events come from the device log
("E2E {json}" lines from Log.swift) via pymobiledevice3; screenshots too (needs Developer Mode and, on iOS 17+,
`sudo pymobiledevice3 remote tunneld` running in another terminal). Text on screenshots is read with macOS Vision.

Scenario file: {"name": ..., "steps": [step, ...]}, each step one of
    {"hands": "home"}                         stick command over USB (same as hands_cli send)
    {"launch": true}                          (re)launch Mantiza (tools/e2e/phone.sh --launch)
    {"event": "board.up", "timeout": 20, "where": {"key": "value"}}   wait for an app event
    {"screen_has": ["General", "About"], "timeout": 10}               screenshot until all texts are visible
    {"tap_text": "General"}                   screenshot, find the text, tap its centre with the stick
    {"sleep": 1.5}
Results go to tools/e2e/out/<scenario>-<time>/ (screenshots, events.jsonl, report.json).
"""
import argparse
import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from hands_cli import ABS_MAX, Hands  # noqa: E402

PMD = shutil.which("pymobiledevice3") or "pymobiledevice3"


class Events:
    """Background reader of the app's E2E log lines."""

    def __init__(self, sink=None):
        self.queue = queue.Queue()
        self.sink = sink
        self.proc = subprocess.Popen([PMD, "syslog", "live", "-pn", "Mantiza", "-m", "E2E "],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            i = line.find("E2E {")
            if i < 0:
                continue
            try:
                event = json.loads(line[i + 4:].strip())
            except json.JSONDecodeError:
                continue
            if self.sink:
                self.sink.write(json.dumps(event) + "\n")
                self.sink.flush()
            self.queue.put(event)

    def wait(self, name, timeout, where=None):
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                e = self.queue.get(timeout=max(0.1, deadline - time.time()))
            except queue.Empty:
                break
            if e.get("evt") == name and all(e.get(k) == v for k, v in (where or {}).items()):
                return e
        return None

    def close(self):
        self.proc.terminate()


def screenshot(path):
    r = subprocess.run([PMD, "developer", "dvt", "screenshot", path], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("screenshot failed (Developer Mode on? `sudo pymobiledevice3 remote tunneld` running?): "
                           + r.stderr.strip()[-300:])
    return read_text(path)


def read_text(path):
    r = subprocess.run(["swift", os.path.join(HERE, "ocr.swift"), path], capture_output=True, text=True, check=True)
    return [json.loads(line) for line in r.stdout.splitlines() if line.strip()]


def find(texts, wanted):
    w = wanted.lower()
    exact = [t for t in texts if t["text"].lower() == w]
    return (exact or [t for t in texts if w in t["text"].lower()] or [None])[0]


def run(path):
    scenario = json.load(open(path))
    name = scenario.get("name", os.path.splitext(os.path.basename(path))[0])
    out = os.path.join(HERE, "out", f"{name}-{time.strftime('%Y%m%d-%H%M%S')}")
    os.makedirs(out)
    hands = Hands()
    events = Events(open(os.path.join(out, "events.jsonl"), "w"))
    report = {"scenario": name, "steps": [], "passed": True}
    shots = 0
    try:
        for i, step in enumerate(scenario["steps"], 1):
            started = time.time()
            ok, detail = True, ""
            if "hands" in step:
                detail = hands.call(step["hands"])
                ok = detail.startswith("ok")
            elif "launch" in step:
                ok = subprocess.run([os.path.join(HERE, "phone.sh"), "--launch"]).returncode == 0
            elif "event" in step:
                e = events.wait(step["event"], step.get("timeout", 15), step.get("where"))
                ok, detail = e is not None, json.dumps(e) if e else "not seen"
            elif "screen_has" in step:
                deadline = time.time() + step.get("timeout", 10)
                while True:
                    shots += 1
                    texts = screenshot(os.path.join(out, f"{shots:03d}.png"))
                    missing = [w for w in step["screen_has"] if not find(texts, w)]
                    if not missing or time.time() > deadline:
                        break
                    time.sleep(1)
                ok, detail = not missing, f"missing {missing}" if missing else "all visible"
            elif "tap_text" in step:
                shots += 1
                hit = find(screenshot(os.path.join(out, f"{shots:03d}.png")), step["tap_text"])
                ok = hit is not None
                if ok:
                    detail = hands.call(f"tap {int(hit['x'] * ABS_MAX)} {int(hit['y'] * ABS_MAX)}")
                    hands.call("park")
                    ok = detail.startswith("ok")
                else:
                    detail = "text not on screen"
            elif "sleep" in step:
                time.sleep(step["sleep"])
            ms = int((time.time() - started) * 1000)
            print(f"{'PASS' if ok else 'FAIL'} {i:2d} {json.dumps(step)} {detail} ({ms} ms)")
            report["steps"].append({"step": step, "ok": ok, "detail": detail, "ms": ms})
            if not ok:
                report["passed"] = False
                break
    finally:
        events.close()
        json.dump(report, open(os.path.join(out, "report.json"), "w"), indent=2)
    print(f"{'PASSED' if report['passed'] else 'FAILED'}: {name} -> {out}")
    return 0 if report["passed"] else 1


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("events")
    s = sub.add_parser("shot")
    s.add_argument("out")
    r = sub.add_parser("run")
    r.add_argument("scenario")
    a = p.parse_args()
    if a.cmd == "events":
        e = Events(sys.stdout)
        try:
            e.proc.wait()
        except KeyboardInterrupt:
            e.close()
    elif a.cmd == "shot":
        for t in screenshot(a.out):
            print(f"{t['x']:.3f},{t['y']:.3f}  {t['text']}")
    else:
        sys.exit(run(a.scenario))


if __name__ == "__main__":
    main()
