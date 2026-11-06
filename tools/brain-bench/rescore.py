"""Re-score a saved run with the current answers in tasks.py (no new API calls).

Run:  python rescore.py results/run-<time>.jsonl
"""
import json
import sys
from pathlib import Path

from bench import hit, summarize
from tasks import TASKS

path = Path(sys.argv[1])
rows = [json.loads(line) for line in path.open(encoding="utf-8")]
for r in rows:
    if "error" in r or r["job"] == "check":
        continue
    screen, goal, accepted = TASKS[r["item"]]
    a = r.get("answer")
    if r["job"] == "pick":
        r["ok"] = a in accepted
    elif isinstance(a, list) and len(a) >= 2:
        r["ok"] = hit(screen, accepted, a[0], a[1])
sys.stdout.reconfigure(encoding="utf-8")
out = path.with_name(path.name.replace("run-", "summary-").replace(".jsonl", "-rescored.md"))
text = f"# Re-scored {path.name}\n" + summarize([r for r in rows if r["model"] != "cloudflare/clairic"])
out.write_text(text, encoding="utf-8")
print(text)
