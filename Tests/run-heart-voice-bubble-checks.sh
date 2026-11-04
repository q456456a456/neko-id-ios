#!/bin/bash
set -euo pipefail

# Separate simulator bundle; never touches the installed test account or backend.
cd "$(dirname "$0")/.."
bubble_workspace=$(mktemp -d /tmp/neko-voice-bubble-checks.XXXXXX)
bubble_run=$(uuidgen)
cp -R neko-id neko-id.xcodeproj Info.plist "$bubble_workspace/"
cp Tests/HeartVoiceBubbleLayoutTestApp.swift "$bubble_workspace/neko-id/neko_idApp.swift"
if [[ -n "${NEKO_SHARE_SCREENSHOT:-}" ]]; then
  cp "$NEKO_SHARE_SCREENSHOT" "$bubble_workspace/neko-id/share-user-screenshot.jpg"
fi
if [[ -n "${NEKO_SHARE_ORIGINAL:-}" ]]; then
  cp "$NEKO_SHARE_ORIGINAL" "$bubble_workspace/neko-id/share-user-original.jpg"
fi
if [[ -n "${NEKO_SHARE_CHAIR:-}" ]]; then
  cp "$NEKO_SHARE_CHAIR" "$bubble_workspace/neko-id/share-user-chair.jpg"
fi
xcodebuild -quiet -project "$bubble_workspace/neko-id.xcodeproj" -scheme neko-id \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$bubble_workspace/Build" \
  PRODUCT_BUNDLE_IDENTIFIER=uk.nekoid.bubblechecks CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted "$bubble_workspace/Build/Build/Products/Debug-iphonesimulator/neko-id.app"
SIMCTL_CHILD_NEKO_LAYOUT_RUN="$bubble_run" xcrun simctl launch --terminate-running-process booted uk.nekoid.bubblechecks
bubble_container=$(xcrun simctl get_app_container booted uk.nekoid.bubblechecks data)
bubble_report="$bubble_container/Documents/bubble-checks-$bubble_run.txt"
# The independent share width/prefix sweep is intentionally more exhaustive
# than the production solver; allow time for it and the OCR export assertions.
for ((attempt = 0; attempt < 120; attempt++)); do
  if [[ -f "$bubble_report" ]]; then
    sed -n '1,30p' "$bubble_report"
    echo "Review PNGs in: $bubble_container/Documents"
    exit 0
  fi
  sleep 1
done
echo "FAIL: bubble checks did not finish; inspect the simulator crash log." >&2
exit 1
