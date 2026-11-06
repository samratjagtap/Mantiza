"""Shared helpers for the brain bench (T8/T11).

Keys are read from C:\\Users\\PC\\.mantiza\\keys.env (outside the repo) and never printed.
"""
import base64
import io
import json
import time
from pathlib import Path

import requests
from PIL import Image

KEYS_FILE = Path.home() / ".mantiza" / "keys.env"
OPENROUTER = "https://openrouter.ai"
HEADERS_EXTRA = {"X-OpenRouter-Title": "Mantiza brain bench"}
# One kept-alive connection, like the real app would have (a new connection per call adds a TLS handshake).
SESSION = requests.Session()


def load_key(name: str) -> str:
    if not KEYS_FILE.exists():
        raise SystemExit(f"No keys file at {KEYS_FILE}")
    for line in KEYS_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith(name + "="):
            value = line.split("=", 1)[1].strip().strip('"').strip("'")
            if value:
                return value
    raise SystemExit(f"{name} is empty in {KEYS_FILE}")


def headers() -> dict:
    return {"Authorization": "Bearer " + load_key("OPENROUTER_API_KEY"),
            "Content-Type": "application/json", **HEADERS_EXTRA}


def image_jpeg(path: Path, max_side: int = 1568, quality: int = 85) -> tuple[bytes, int, int]:
    """Load a screenshot, shrink so the long side is at most max_side, return JPEG bytes and size.
    1568 is Jev's limit; Clef wants < ~300 KB, which this usually gives."""
    img = Image.open(path).convert("RGB")
    scale = min(1.0, max_side / max(img.size))
    if scale < 1:
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=quality)
    return buf.getvalue(), img.width, img.height


def data_url(jpeg: bytes) -> str:
    return "data:image/jpeg;base64," + base64.b64encode(jpeg).decode()


def post(path: str, body: dict, timeout: float = 120) -> tuple[dict, float]:
    """POST to OpenRouter; returns (json, seconds). Raises with the server's message on error."""
    t0 = time.perf_counter()
    r = SESSION.post(OPENROUTER + path, headers=headers(), json=body, timeout=timeout)
    dt = time.perf_counter() - t0
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}: {r.text[:500]}")
    return r.json(), dt


def get(path: str) -> dict:
    r = SESSION.get(OPENROUTER + path, headers=headers(), timeout=30)
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}: {r.text[:300]}")
    return r.json()


def response_text(resp: dict) -> str:
    """Text from a Responses API result."""
    if resp.get("output_text"):
        return resp["output_text"]
    parts = []
    for item in resp.get("output", []):
        if item.get("type") == "message":
            for c in item.get("content", []):
                if c.get("type") in ("output_text", "text"):
                    parts.append(c.get("text", ""))
    return "".join(parts)


def parse_json(text: str):
    """First {...} object in the text, or None."""
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end < start:
        return None
    try:
        return json.loads(text[start:end + 1])
    except json.JSONDecodeError:
        return None
