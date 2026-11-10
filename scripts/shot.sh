#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="$1"; shift
UDID="$(scripts/sim-udid.sh)"
xcodebuild build -quiet -project OpenCam.xcodeproj -scheme OpenCam -destination "id=$UDID" -derivedDataPath .build CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$UDID" .build/Build/Products/Debug-iphonesimulator/OpenCam.app
xcrun simctl launch --terminate-running-process "$UDID" local.opencam.app "$@" >/dev/null
sleep 4
mkdir -p docs/screenshots/p1a
xcrun simctl io "$UDID" screenshot --display=1 "docs/screenshots/p1a/$NAME.png"
