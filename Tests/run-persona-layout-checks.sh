#!/bin/bash
set -euo pipefail

# Requires an already booted iOS simulator. Uses a separate bundle ID and a
# disposable project copy; never launches the real app or calls its backend.
cd "$(dirname "$0")/.."
layout_workspace=$(mktemp -d /tmp/neko-persona-layout.XXXXXX)
layout_run=$(uuidgen)
cp -R neko-id neko-id.xcodeproj Info.plist "$layout_workspace/"
cp Tests/PersonaResultLayoutTestApp.swift "$layout_workspace/neko-id/neko_idApp.swift"
xcodebuild -quiet -project "$layout_workspace/neko-id.xcodeproj" -scheme neko-id \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$layout_workspace/Build" \
  PRODUCT_BUNDLE_IDENTIFIER=uk.nekoid.layoutchecks CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted "$layout_workspace/Build/Build/Products/Debug-iphonesimulator/neko-id.app"
SIMCTL_CHILD_NEKO_LAYOUT_RUN="$layout_run" xcrun simctl launch --terminate-running-process booted uk.nekoid.layoutchecks
layout_container=$(xcrun simctl get_app_container booted uk.nekoid.layoutchecks data)
layout_report="$layout_container/Documents/layout-checks-$layout_run.txt"
for ((attempt = 0; attempt < 45; attempt++)); do
  if [[ -f "$layout_report" ]]; then
    sed -n '1,100p' "$layout_report"
    echo "Review the rendered persona PNGs in: $layout_container/Documents"
    exit 0
  fi
  sleep 1
done
echo 'FAIL: layout checks did not finish; inspect the simulator crash log.' >&2
exit 1
