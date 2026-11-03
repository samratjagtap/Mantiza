#!/bin/bash
# Pull Mantiza's training rows from the plugged-in iPhone and fine-tune Laya on them (see train.py).
#   tools/laya/train.sh            pull + train + evaluate (+ promote if good enough)
#   tools/laya/train.sh --no-pull  train on what is already in tools/laya/data
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_ID="${MANTIZA_BUNDLE_ID:-com.azadjagtap.mantiza}"
[ -x "$DIR/.venv/bin/python" ] || { echo "run tools/laya/serve.sh once first (it installs Laya)"; exit 1; }

if [ "${1:-}" != "--no-pull" ]; then
  DEVICE="$(xcrun devicectl list devices --hide-default-columns --columns Identifier --filter "State == 'connected'" 2>/dev/null \
    | awk '/^[0-9A-F]{8}-[0-9A-F]+/ {print $1; exit}')"
  [ -n "$DEVICE" ] || { echo "no connected iPhone"; exit 1; }
  rm -rf "$DIR/data" && mkdir -p "$DIR/data"
  xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source Documents/training --destination "$DIR/data" >/dev/null
fi
exec "$DIR/.venv/bin/python" "$DIR/train.py" "$DIR/data"
