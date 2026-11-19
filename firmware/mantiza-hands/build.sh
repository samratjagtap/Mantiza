#!/usr/bin/env bash
# Build and flash Mantiza Hands on an M5StickS3 (needs arduino-cli, esp32:esp32 3.3.x, M5Unified, NimBLE-Arduino 2.5.x).
# Usage: firmware/mantiza-hands/build.sh [port] [--debug] [--build-only]
#   --debug       log every command on USB serial
#   --build-only  compile only (prints flash/RAM usage)
# nimble_cfg.h (NimBLE host buffer sizes) is force-included into every C/C++ file. The -include flag cannot take a
# path with spaces, so it is copied to a temporary directory first.
set -euo pipefail
SKETCH="$(cd "$(dirname "$0")" && pwd)"
FQBN="esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=8M,PartitionScheme=default_8MB,PSRAM=opi"
PORT="" DEFS="" BUILD_ONLY=0
for a in "$@"; do
  case $a in
    --debug) DEFS+=" -DDEBUG_SERIAL=1" ;;
    --build-only) BUILD_ONLY=1 ;;
    --*) echo "unknown option: $a" >&2; exit 1 ;;
    *) PORT=$a ;;
  esac
done
CFG_DIR="$(mktemp -d)"
trap 'rm -rf "$CFG_DIR"' EXIT
cp "$SKETCH/nimble_cfg.h" "$CFG_DIR/nimble_cfg.h"
DEFS+=" -include $CFG_DIR/nimble_cfg.h"
FLAGS=(--build-property "compiler.cpp.extra_flags=$DEFS" --build-property "compiler.c.extra_flags=$DEFS")
BUILD="$SKETCH/build"

arduino-cli compile -b "$FQBN" "${FLAGS[@]}" --output-dir "$BUILD" "$SKETCH"
(( BUILD_ONLY )) && exit 0
if [[ -z $PORT ]]; then
  for p in /dev/cu.usbmodem* /dev/ttyACM*; do [[ -e $p ]] && { PORT=$p; break; }; done
fi
[[ -n $PORT ]] || { echo "no board found on USB" >&2; exit 1; }
arduino-cli upload -b "$FQBN" -p "$PORT" --input-dir "$BUILD" "$SKETCH"
