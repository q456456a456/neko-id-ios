#!/bin/bash
set -euo pipefail

# Standalone disposable build; never launches the real app or calls its backend.
cd "$(dirname "$0")/.."
navigation_workspace=$(mktemp -d /tmp/neko-persona-navigation.XXXXXX)
navigation_run=$(uuidgen)
cp -R neko-id neko-id.xcodeproj Info.plist "$navigation_workspace/"
cp Tests/PersonaNavigationTestApp.swift "$navigation_workspace/neko-id/neko_idApp.swift"
xcodebuild -quiet -project "$navigation_workspace/neko-id.xcodeproj" -scheme neko-id \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$navigation_workspace/Build" \
  PRODUCT_BUNDLE_IDENTIFIER=uk.nekoid.navigationchecks CODE_SIGNING_ALLOWED=NO build \
  > "$navigation_workspace/build.log" 2>&1 || { tail -n 80 "$navigation_workspace/build.log"; exit 1; }
xcrun simctl install booted "$navigation_workspace/Build/Build/Products/Debug-iphonesimulator/neko-id.app"
SIMCTL_CHILD_NEKO_LAYOUT_RUN="$navigation_run" SIMCTL_CHILD_NEKO_NAV_BASELINE="${NEKO_NAV_BASELINE:-0}" \
  xcrun simctl launch --terminate-running-process booted uk.nekoid.navigationchecks
navigation_container=$(xcrun simctl get_app_container booted uk.nekoid.navigationchecks data)
navigation_report="$navigation_container/Documents/navigation-checks-$navigation_run.txt"
for ((attempt = 0; attempt < 55; attempt++)); do
  if [[ -f "$navigation_report" ]]; then
    cat "$navigation_report"
    echo "Review PNGs in: $navigation_container/Documents"
    echo "Build workspace: $navigation_workspace"
    exit 0
  fi
  sleep 1
done
echo "FAIL: navigation checks did not finish; inspect simulator crash logs." >&2
echo "Build workspace: $navigation_workspace"
exit 1
