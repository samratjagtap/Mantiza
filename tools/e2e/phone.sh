#!/bin/bash
# Build Mantiza for the plugged-in iPhone, install it and launch it.
#   tools/e2e/phone.sh            build + install + launch
#   tools/e2e/phone.sh --launch   launch only
#   tools/e2e/phone.sh --key anthropic FILE   hand an API key to the app (debug builds), then relaunch it
# Needs: Xcode, ios/Config/Local.xcconfig with DEVELOPMENT_TEAM, Developer Mode on the phone.
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE_ID="${MANTIZA_BUNDLE_ID:-com.azadjagtap.mantiza}"
DEVICE="$(xcrun devicectl list devices --hide-default-columns --columns Identifier --filter "State == 'connected'" 2>/dev/null \
  | awk '/^[0-9A-F]{8}-[0-9A-F]+/ {print $1; exit}')"
[ -n "$DEVICE" ] || { echo "no connected iPhone (plug it in, unlock it, trust this Mac)"; exit 1; }

if [ "${1:-}" = "--key" ]; then
  # The app moves Documents/import-<provider>.key into the Keychain at launch and deletes the file.
  [ -f "${3:-}" ] || { echo "usage: phone.sh --key anthropic|google|typesafe|laya FILE"; exit 1; }
  xcrun devicectl device copy to --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "$3" --destination "Documents/import-$2.key" >/dev/null
elif [ "${1:-}" != "--launch" ]; then
  cd "$ROOT/ios"
  xcodegen generate --quiet
  xcodebuild -project Mantiza.xcodeproj -scheme Mantiza -destination "platform=iOS,id=$DEVICE" -derivedDataPath build/device \
    -allowProvisioningUpdates build -quiet
  APP="$ROOT/ios/build/device/Build/Products/Debug-iphoneos/Mantiza.app"
  xcrun devicectl device install app --device "$DEVICE" "$APP"
fi
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE_ID"
