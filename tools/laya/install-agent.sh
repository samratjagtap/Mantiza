#!/bin/bash
# Keep the Laya server running on this Mac: starts at login and restarts if it stops (a LaunchAgent).
#   tools/laya/install-agent.sh            install and start
#   tools/laya/install-agent.sh --remove   stop and remove
# Logs: ~/Library/Logs/mantiza-laya.log
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.mantiza.laya"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ "${1:-}" = "--remove" ]; then
  rm -f "$PLIST"
  echo "removed $LABEL"
  exit 0
fi
[ -x "$DIR/.venv/bin/laya-serve" ] || { echo "run tools/laya/serve.sh once first (it installs Laya)"; exit 1; }

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$DIR/serve.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/mantiza-laya.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/mantiza-laya.log</string>
</dict>
</plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed $LABEL; Laya now starts at login (log: ~/Library/Logs/mantiza-laya.log)"
