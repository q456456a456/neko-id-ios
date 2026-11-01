#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
layout_workspace=$(mktemp -d /tmp/neko-confirm-sheet.XXXXXX)
layout_run=$(uuidgen)
simulator_id=${1:?Pass a booted simulator UDID}
cp -R neko-id neko-id.xcodeproj Info.plist "$layout_workspace/"
cp Tests/ConfirmSheetLayoutTestApp.swift "$layout_workspace/neko-id/neko_idApp.swift"
xcodebuild -quiet -project "$layout_workspace/neko-id.xcodeproj" -scheme neko-id \
  -destination "platform=iOS Simulator,id=$simulator_id" -derivedDataPath "$layout_workspace/Build" \
  PRODUCT_BUNDLE_IDENTIFIER=uk.nekoid.confirmsheetcheck CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$simulator_id" "$layout_workspace/Build/Build/Products/Debug-iphonesimulator/neko-id.app"
SIMCTL_CHILD_NEKO_LAYOUT_RUN="$layout_run" SIMCTL_CHILD_NEKO_SHEET_BASELINE="${NEKO_SHEET_BASELINE:-0}" \
  xcrun simctl launch --terminate-running-process "$simulator_id" uk.nekoid.confirmsheetcheck
layout_container=$(xcrun simctl get_app_container "$simulator_id" uk.nekoid.confirmsheetcheck data)
layout_report="$layout_container/Documents/sheet-checks-$layout_run.txt"
for ((attempt = 0; attempt < 30; attempt++)); do
  if [[ -f "$layout_report" ]]; then
    sed -n '1,100p' "$layout_report"
    echo "Snapshots: $layout_container/Documents"
    exit 0
  fi
  sleep 1
done
echo 'FAIL: sheet layout checks did not finish; inspect simulator logs.' >&2
exit 1
