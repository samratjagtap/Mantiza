"""Debug inbox: receives Mantiza's task reports over Wi-Fi and saves them for /debug.

Development builds of Mantiza send one report per task (prompt, plan, steps with screenshots,
device log, result) to http://<this PC>:8765/runs. Reports are saved outside the repo, in
C:\\Users\\PC\\.mantiza\\runs\\<date>_<time>_<id>\\, because screenshots can show private chats.

Run:  pythonw tools/debug-inbox/inbox.py        (no window; started at logon, see README)
Check: http://127.0.0.1:8765/ping  ->  mantiza-inbox
"""
import base64
import json
import re
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOME = Path.home() / ".mantiza"
RUNS = HOME / "runs"
PORT = 8765
MAX_BODY = 80 * 1024 * 1024


def token():
    f = HOME / "debug-token"
    return f.read_text(encoding="utf-8").strip() if f.exists() else ""


class Handler(BaseHTTPRequestHandler):
    def _answer(self, code, text):
        body = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/ping":
            self._answer(200, "mantiza-inbox")
        else:
            self._answer(404, "not found")

    def do_POST(self):
        if self.path != "/runs":
            return self._answer(404, "not found")
        if not token() or self.headers.get("X-Mantiza-Token") != token():
            return self._answer(403, "wrong token")
        size = int(self.headers.get("Content-Length") or 0)
        if size <= 0 or size > MAX_BODY:
            return self._answer(413, "too big")
        try:
            data = json.loads(self.rfile.read(size))
            run = data["run"]
            rid = re.sub(r"[^A-Za-z0-9-]", "", str(run.get("id", "")))[:12] or "run"
            started = str(run.get("started", ""))[:19].replace("T", "_").replace(":", "")
            started = re.sub(r"[^0-9_-]", "", started) or datetime.now().strftime("%Y-%m-%d_%H%M%S")
            folder = RUNS / f"{started}_{rid}"
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "run.json").write_text(json.dumps(run, indent=2, ensure_ascii=False), encoding="utf-8")
            for name, b64 in (data.get("images") or {}).items():
                if re.fullmatch(r"step-\d+\.jpg", name) and b64:
                    (folder / name).write_bytes(base64.b64decode(b64))
        except (ValueError, KeyError, TypeError, OSError) as e:
            return self._answer(400, f"bad report: {e}")
        self._answer(200, "saved")

    def log_message(self, fmt, *args):  # quiet (runs without a window)
        pass


if __name__ == "__main__":
    RUNS.mkdir(parents=True, exist_ok=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
