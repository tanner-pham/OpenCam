#!/bin/zsh
# scripts/test.sh [SuiteName]
set -euo pipefail
cd "$(dirname "$0")/.."
UDID="$(scripts/sim-udid.sh)"
xcodebuild test -quiet -project OpenCam.xcodeproj -scheme OpenCam -destination "id=$UDID" \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO ${1:+-only-testing:OpenCamTests/$1}
