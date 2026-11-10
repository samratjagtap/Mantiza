# Debug inbox and `/debug`

Development builds of Mantiza send a **report of every task** to this PC over Wi-Fi. `/debug` in
Claude Code reads the new reports, finds where each task went wrong, fixes the code, and marks each
report with a tick.

## How the reports get here
1. **On the phone** (`apps/mantiza/Sources/Mantiza/RunLog.swift`): every task saves its report:
   - the prompt and the plan
   - each step with its time and screenshot
   - the device log
   - the result

   Reports are sent to `Secrets.debugInbox`. If the PC isn't reachable, they wait on the phone and
   go out after the next task or the next time Mantiza is opened.
   - Only builds made by `scripts/make_secrets.py` with a debug inbox send anything. User builds get
     `DEBUG_INBOX=off` in keys.env, so no reports.
2. **On the PC** (`inbox.py`, port 8765): reports are saved in `C:\Users\PC\.mantiza\runs\<date>_<time>_<id>\`:
   `run.json` plus `step-NN.jpg`. They are **outside the repo**, because screenshots can show
   private chats. Each request must carry the shared secret in `C:\Users\PC\.mantiza\debug-token`.
3. **`runs.py`** lists the reports and keeps the ledger (`C:\Users\PC\.mantiza\runs\ledger.md`):
   - `python tools/debug-inbox/runs.py new`
   - `python tools/debug-inbox/runs.py show <run>`
   - `python tools/debug-inbox/runs.py mark <run> fixed|worked|needs-info|open "<note>"`
   - `python tools/debug-inbox/runs.py all`

**Address:** `make_secrets.py` puts this PC's Wi-Fi/LAN address into the app (for example
`http://192.168.0.103:8765`). If the router gives the PC a new address, rebuild and install the app.

**Start the inbox** (it isn't started at logon; `/debug` starts it when needed):
`pythonw tools/debug-inbox/inbox.py`

**First time:** if Windows asks whether Python may use the network, allow it on **private**
networks, otherwise the phone can't reach the inbox.

---

## The `/debug` procedure (what Claude does)

1. **Inbox up?**
   - `curl http://127.0.0.1:8765/ping` must answer `mantiza-inbox`.
   - If it doesn't, start it hidden:
     `Start-Process pythonw.exe '"<repo>\tools\debug-inbox\inbox.py"' -WindowStyle Hidden`.
2. **New reports:** `python tools/debug-inbox/runs.py new`.
   - If there are none, say so, and remind the user:
     - the phone must be on the same Wi-Fi as the PC
     - opening Mantiza sends waiting reports
     - Windows may need to allow Python on private networks
   - Then stop.
3. **For each new report, oldest first:**
   1. `runs.py show <run>`. Then **look at the screenshots** (Read the `step-NN.jpg` files) of the
      steps before and at the point where it stopped or went wrong. The last screenshot always.
   2. **Judge it against the prompt:** did Mantiza do exactly what was asked? Check the result, the
      screenshots and the device log, not just the ✅. Note slow steps (the times are in the report).
   3. **Find the cause in the code** (`apps/mantiza/Sources/Mantiza/`, `firmware/mantiza-device/`).
      The report's `build` gives the commit it ran on; check `git log` since then, because it may
      already be fixed.
   4. **When the screenshots don't settle what happened** (what a pop-up said, whether a message
      really went out, what the user saw), ask the user **one short, task-specific question**:
      name the prompt and the time, and say what you saw. Use AskUserQuestion. Don't guess.
   5. **Fix the cause** with the smallest correct change, and group fixes that share a cause. Keep
      to the standing rules in memory:
      - public iOS APIs only; users get only the app, its widget and the StickS3, with Developer
        Mode off
      - never ask approval for something the user explicitly requested
      - direct iOS actions first, AI screen steps only for the rest
4. **Build** (`xtool dev build`), then **commit and push to `v1`** (no Co-Authored-By line).
   - If the iPhone is connected (`listdev.py` count 1), install with `xtool dev`.
   - Otherwise say the install is waiting.
5. **Mark every report you went through** with `runs.py mark`:
   - `fixed`: the cause, the fix and the commit
   - `worked`: it did what was asked (add speed notes if any)
   - `needs-info`: the question you asked
   - `open`: can't be fixed yet, and why
6. **Reply with:**
   - the ledger of this round (✅ / ❓ / ⏳ per report)
   - what was fixed and in which commit
   - which prompts the user should run again to confirm the fixes

   If a fix makes a learned routine wrong, tell the user to forget it (Device tab → Learned
   routines), or make the code drop it.
