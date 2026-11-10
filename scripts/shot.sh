#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="$1"; shift
UDID="$(scripts/sim-udid.sh)"
xcodebuild build -quiet -project OpenCam.xcodeproj -scheme OpenCam -destination "id=$UDID" -derivedDataPath .build CODE_SIGNING_ALLOWED=NO
if [[ "${SHOT_FRESH:-0}" == 1 ]]; then xcrun simctl uninstall "$UDID" local.opencam.app || true; fi
xcrun simctl install "$UDID" .build/Build/Products/Debug-iphonesimulator/OpenCam.app
xcrun simctl launch --terminate-running-process "$UDID" local.opencam.app "$@" >/dev/null
sleep 6
DIR="${SHOT_DIR:-docs/screenshots/p1a}"
mkdir -p "$DIR"
xcrun simctl io "$UDID" screenshot --display=1 "$DIR/$NAME.png"
