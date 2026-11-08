#!/bin/bash
set -euo pipefail

# Only the temporary copy changes visibility; production stays private.
cd "$(dirname "$0")/.."
navigation_workspace=$(mktemp -d /tmp/neko-voice-navigation.XXXXXX)
navigation_run=$(uuidgen)
cp -R neko-id neko-id.xcodeproj Info.plist "$navigation_workspace/"
cp Tests/VoicePreviewNavigationTestApp.swift "$navigation_workspace/neko-id/neko_idApp.swift"
perl -pi -e 's/^private struct PublishPreviewScreen: View/struct PublishPreviewScreen: View/' \
  "$navigation_workspace/neko-id/ContentView.swift"
xcodebuild -quiet -project "$navigation_workspace/neko-id.xcodeproj" -scheme neko-id \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$navigation_workspace/Build" \
  PRODUCT_BUNDLE_IDENTIFIER=uk.nekoid.voicenavigationchecks CODE_SIGNING_ALLOWED=NO build \
  > "$navigation_workspace/build.log" 2>&1 || { tail -n 80 "$navigation_workspace/build.log"; exit 1; }
xcrun simctl install booted "$navigation_workspace/Build/Build/Products/Debug-iphonesimulator/neko-id.app"
SIMCTL_CHILD_NEKO_LAYOUT_RUN="$navigation_run" SIMCTL_CHILD_NEKO_NAV_BASELINE="${NEKO_NAV_BASELINE:-0}" \
  xcrun simctl launch --terminate-running-process booted uk.nekoid.voicenavigationchecks
navigation_container=$(xcrun simctl get_app_container booted uk.nekoid.voicenavigationchecks data)
navigation_report="$navigation_container/Documents/voice-navigation-checks-$navigation_run.txt"
for ((attempt = 0; attempt < 55; attempt++)); do
  if [[ -f "$navigation_report" ]]; then
    cat "$navigation_report"
    echo "Review PNGs in: $navigation_container/Documents"
    echo "Build workspace: $navigation_workspace"
    exit 0
  fi
  sleep 1
done
echo "FAIL: preview navigation checks did not finish; inspect simulator crash logs." >&2
echo "Build workspace: $navigation_workspace"
exit 1
