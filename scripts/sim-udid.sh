#!/bin/zsh
# scripts/sim-udid.sh: prints the UDID of "OpenCam Dev", creating and booting it if needed.
# OPENCAM_SIM_NAME names another simulator, so two worktrees can build and test at the same time without sharing one.
set -euo pipefail
NAME="${OPENCAM_SIM_NAME:-OpenCam Dev}"; TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-Duo; RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4
UDID="$(xcrun simctl list devices | grep -E "^ +$NAME \(" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)"
if [[ -z "$UDID" ]]; then UDID="$(xcrun simctl create "$NAME" "$TYPE" "$RUNTIME")"; fi
xcrun simctl bootstatus "$UDID" -b >/dev/null
print -r -- "$UDID"
