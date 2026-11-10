"""Helper for /debug: lists Mantiza task reports and records what debugging found.

  python tools/debug-inbox/runs.py new             new (not yet debugged) runs, oldest first
  python tools/debug-inbox/runs.py all             every run with its status
  python tools/debug-inbox/runs.py show <run>      one run: prompt, plan, steps, device log, result
  python tools/debug-inbox/runs.py mark <run> <status> <note>
        status: fixed | worked | needs-info | open
        writes <run>/debug.json and rebuilds ledger.md (the list with the ticks)

Runs live in C:\\Users\\PC\\.mantiza\\runs (outside the repo: screenshots can be private).
"""
import json
import sys
from datetime import datetime
from pathlib import Path

RUNS = Path.home() / ".mantiza" / "runs"
TICKS = {"fixed": "✅ fixed", "worked": "✅ worked", "needs-info": "❓ needs info", "open": "⏳ open"}

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def runs():
    return sorted(d for d in RUNS.iterdir() if (d / "run.json").exists()) if RUNS.exists() else []


def load(d):
    return json.loads((d / "run.json").read_text(encoding="utf-8"))


def status(d):
    f = d / "debug.json"
    return json.loads(f.read_text(encoding="utf-8")) if f.exists() else None


def short(d):
    r = load(d)
    took = ""
    if r.get("ended") and r.get("started"):
        try:
            took = f"{(datetime.fromisoformat(r['ended'].replace('Z', '+00:00')) - datetime.fromisoformat(r['started'].replace('Z', '+00:00'))).total_seconds():.0f}s"
        except ValueError:
            pass
    return f"{d.name} | \"{r.get('prompt', '')}\" | {r.get('result', '')} | {len(r.get('steps', []))} steps {took}"


def find(name):
    hits = [d for d in runs() if d.name.startswith(name) or name in d.name]
    if len(hits) != 1:
        sys.exit(f"{len(hits)} runs match {name!r}")
    return hits[0]


def ledger():
    lines = ["# Mantiza debug ledger", "", "| Run | Prompt | Result | Status | Note |", "|---|---|---|---|---|"]
    for d in runs():
        r, s = load(d), status(d)
        tick = TICKS.get(s["status"], s["status"]) if s else "🆕 new"
        note = (s or {}).get("note", "").replace("|", "/").replace("\n", " ")
        lines.append(f"| {d.name} | {r.get('prompt', '').replace('|', '/')} | {str(r.get('result', '')).replace('|', '/')} | {tick} | {note} |")
    (RUNS / "ledger.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "new"
    if cmd == "new":
        new = [d for d in runs() if status(d) is None]
        print(f"{len(new)} new run(s) in {RUNS}")
        for d in new:
            print(" ", short(d))
    elif cmd == "all":
        for d in runs():
            s = status(d)
            print(f"  {TICKS.get(s['status'], s['status']) if s else '🆕 new':14} {short(d)}")
    elif cmd == "show":
        d = find(sys.argv[2])
        r = load(d)
        print(f"Run {d.name}\nFolder: {d}\nBuild: {r.get('build')} · {r.get('device')}\nPrompt: {r.get('prompt')}\nResult: {r.get('result')}\n")
        print("Plan:", r.get("plan"), "\n")
        print("Steps:")
        for s in r.get("steps", []):
            print(f"  {s['t']:6.1f}s  {s['text']}" + (f"   [{s['image']}]" if s.get("image") else ""))
        print("\nDevice log:")
        for line in r.get("deviceLog", []):
            print("  " + line)
        s = status(d)
        if s:
            print(f"\nDebug status: {s}")
    elif cmd == "mark":
        d = find(sys.argv[2])
        st = sys.argv[3]
        if st not in TICKS:
            sys.exit(f"status must be one of {', '.join(TICKS)}")
        note = " ".join(sys.argv[4:])
        (d / "debug.json").write_text(json.dumps({"status": st, "note": note, "when": datetime.now().isoformat(timespec="minutes")},
                                                 indent=2, ensure_ascii=False), encoding="utf-8")
        ledger()
        print(f"{TICKS[st]}  {d.name}")
    elif cmd == "ledger":
        ledger()
        print((RUNS / "ledger.md").read_text(encoding="utf-8"))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
