"""Fine-tune Laya on Mantiza's own runs and decide whether the result may serve.

    tools/laya/train.sh          pull training rows from the phone, then run this
    python train.py DATA_DIR     DATA_DIR holds gold/*.jsonl (and failed/*.jsonl, ignored)

Rows are Laya `{state, questions, expected}` lines the app wrote from Claude's decisions (TrainingLog.swift). Runs
are split 80/20 by run id, so screens of one run never sit on both sides. The held-out 20% measure the base and the
fine-tuned checkpoint the way the app uses them: an answer only counts when it clears the app's gate (confidence
and margin), so the numbers that matter are coverage (how often Laya answers) and accuracy when it does.
The new checkpoint becomes models/current (served as `mantiza`) only if that accuracy is at least PROMOTE_ACCURACY.
"""
import datetime
import hashlib
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = HERE / "models"
REPO, SUBFOLDER = "convaiinnovations/laya", "typed-decisions"
# Same gate as SystemOnePicker.Service.laya in the app.
MIN_CONFIDENCE, MIN_MARGIN = 0.85, 0.3
PROMOTE_ACCURACY = 0.95
MIN_TRAIN_ROWS = 150


def read_rows(folder):
    rows = []
    for path in sorted(Path(folder).glob("*.jsonl")):
        for line in path.read_text().splitlines():
            if line.strip():
                rows.append(json.loads(line))
    return rows


def split(rows):
    """80/20 by run, stable across calls."""
    train, test = [], []
    for row in rows:
        bucket = int(hashlib.sha256(row.get("run", "").encode()).hexdigest(), 16) % 5
        (test if bucket == 0 else train).append(row)
    return train, test


def gated(answer):
    """The choice the app would act on, or None."""
    if not isinstance(answer, dict) or "choice" not in answer:
        return None
    probs = sorted((answer.get("probabilities") or {}).values(), reverse=True)
    margin = probs[0] - probs[1] if len(probs) > 1 else (probs[0] if probs else 0)
    return answer["choice"] if answer.get("confidence", 0) >= MIN_CONFIDENCE and margin >= MIN_MARGIN else None


def evaluate(agent, rows):
    """Per-row operation (+ tap target) accuracy, raw and behind the app's gate."""
    total = right = answered = answered_right = 0
    for row in rows:
        result = agent.predict_batch([row["state"]], row["questions"])
        result = result[0] if isinstance(result, list) else result
        answers = result.get("answers", result)
        want = row["expected"]
        op = answers.get("operation", {})
        ok = op.get("choice") == want.get("operation")
        if ok and want.get("operation") == "TAP":
            ok = answers.get("tap_target", {}).get("choice") == want.get("tap_target")
        total += 1
        right += ok
        pick = gated(op)
        if pick is not None and (pick != "TAP" or gated(answers.get("tap_target")) is not None):
            answered += 1
            answered_right += ok
    return {"rows": total, "accuracy": right / total if total else 0,
            "coverage": answered / total if total else 0,
            "gated_accuracy": answered_right / answered if answered else None}


def main():
    data = Path(sys.argv[1] if len(sys.argv) > 1 else HERE / "data")
    rows = read_rows(data / "gold")
    train, test = split(rows)
    print(f"{len(rows)} gold rows from {len({r.get('run') for r in rows})} runs: {len(train)} train, {len(test)} test")
    if len(train) < MIN_TRAIN_ROWS or not test:
        sys.exit(f"Not enough data yet: need {MIN_TRAIN_ROWS} training rows and some test rows. Keep using Mantiza and run this again.")

    import laya
    from huggingface_hub import snapshot_download
    from laya.train import finetune

    base_dir = Path(snapshot_download(REPO, allow_patterns=[f"{SUBFOLDER}/*"])) / SUBFOLDER
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M")
    out = MODELS / stamp
    out.mkdir(parents=True, exist_ok=True)
    for name, part in (("train", train), ("test", test)):
        (out / f"{name}.jsonl").write_text("".join(json.dumps(r) + "\n" for r in part))

    print("training (this can take a while on the Mac's GPU)...")
    summary = finetune(str(out / "train.jsonl"), str(base_dir), str(out / "checkpoint"))

    print("evaluating on the held-out runs...")
    before = evaluate(laya.load(str(base_dir)), test)
    after = evaluate(laya.load(str(out / "checkpoint")), test)
    promote = (after["gated_accuracy"] or 0) >= PROMOTE_ACCURACY and after["coverage"] > 0
    report = {"rows": len(rows), "train": len(train), "test": len(test), "base": before, "fine_tuned": after,
              "gate": {"confidence": MIN_CONFIDENCE, "margin": MIN_MARGIN}, "promoted": promote,
              "train_summary": summary}
    (out / "report.json").write_text(json.dumps(report, indent=2, default=str))
    print(json.dumps({k: report[k] for k in ("base", "fine_tuned", "promoted")}, indent=2))
    if promote:
        current = MODELS / "current"
        if current.is_symlink() or current.exists():
            current.unlink()
        os.symlink(out / "checkpoint", current)
        print(f"promoted: {current} -> {out / 'checkpoint'}; restart tools/laya/serve.sh to use it")
    else:
        print(f"not promoted (needs gated accuracy >= {PROMOTE_ACCURACY}); the app keeps the current model")


if __name__ == "__main__":
    main()
