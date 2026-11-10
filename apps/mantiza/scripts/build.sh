#!/bin/sh
# Build and install Mantiza on the iPhone (run inside WSL Ubuntu; iPhone bridge running, phone unlocked).
set -e
cd "$(dirname "$0")/.."
python3 scripts/make_secrets.py
xtool dev
