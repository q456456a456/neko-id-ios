#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
layout_workspace=$(mktemp -d /tmp/neko-heart-voice-layout.XXXXXX)
cp -R neko-id neko-id.xcodeproj Info.plist "$layout_workspace/"
cp Tests/HeartVoiceLayoutTestApp.swift "$layout_workspace/neko-id/neko_idApp.swift"

xcodebuild -quiet -project "$layout_workspace/neko-id.xcodeproj" -scheme neko-id \
  -destination 'platform=iOS Simulator,id=AD252DA1-9D49-40E8-9D14-92D29657ECEA' \
  -derivedDataPath "$layout_workspace/Build" \
  PRODUCT_BUNDLE_IDENTIFIER=uk.nekoid.heartvoicelayout CODE_SIGNING_ALLOWED=NO build

xcrun simctl install AD252DA1-9D49-40E8-9D14-92D29657ECEA \
  "$layout_workspace/Build/Build/Products/Debug-iphonesimulator/neko-id.app"

for scenario in landscape-left landscape-right portrait-left portrait-right face-top large-subject; do
  xcrun simctl launch --terminate-running-process AD252DA1-9D49-40E8-9D14-92D29657ECEA \
    uk.nekoid.heartvoicelayout "--heart-voice=$scenario"
  sleep 1
  xcrun simctl io AD252DA1-9D49-40E8-9D14-92D29657ECEA screenshot \
    "/tmp/heart-voice-$scenario.png"
done

echo "PASS: six heart voice focal crop and bubble placement fixtures"
