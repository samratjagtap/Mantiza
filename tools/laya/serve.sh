#!/bin/bash
# Run Laya (convaiinnovations/laya, Apache-2.0) on this Mac as Mantiza's quick-step picker.
# It answers POST /v1/systemone like TypeSafe's Jev. The phone reaches it over the same Wi-Fi.
#   tools/laya/serve.sh           install on first run (PyTorch + ~0.8 GB checkpoint), then serve on port 8765
# Put the printed address and key into Mantiza > Settings > Quick steps and Keys > Laya server.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
VENV="$DIR/.venv"
PORT="${LAYA_PORT:-8765}"

if [ ! -x "$VENV/bin/laya-serve" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet "laya[serve]"
fi

# The server listens on the whole network, so it always needs a key (kept out of git in .key).
[ -s "$DIR/.key" ] || (umask 077; openssl rand -hex 24 > "$DIR/.key")

IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "<this Mac's IP>")"
echo "Laya server:  http://$IP:$PORT"
echo "Laya key:     $(cat "$DIR/.key")"

export LAYA_API_KEY="$(cat "$DIR/.key")"
export LAYA_HOST="${LAYA_HOST:-0.0.0.0}" LAYA_PORT="$PORT"
# The app asks for model "mantiza": the fine-tune tools/laya/train.sh promoted, else the stock typed-decisions checkpoint.
if [ -e "$DIR/models/current" ]; then
  MANTIZA_SOURCE="\"$(cd "$DIR/models/current" && pwd -P)\""
else
  MANTIZA_SOURCE='["convaiinnovations/laya", "typed-decisions"]'
fi
export LAYA_EXTRA_MODELS="{\"mantiza\": $MANTIZA_SOURCE}"
echo "Laya model: mantiza = $MANTIZA_SOURCE"
export LAYA_MODELS="${LAYA_MODELS:-mantiza}" LAYA_DEFAULT_MODEL="${LAYA_DEFAULT_MODEL:-mantiza}"
export LAYA_DEVICE="${LAYA_DEVICE:-mps}" LAYA_PRELOAD=1
exec "$VENV/bin/laya-serve"
