#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
video_workspace=$(mktemp -d /tmp/neko-onboarding-video-checks.XXXXXX)
video_run=$(uuidgen)
cp -R neko-id neko-id.xcodeproj Info.plist "$video_workspace/"
xcrun swift - "$video_workspace" <<'SWIFT'
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("neko-id")
let target = root.appendingPathComponent("OnboardingFlowView.swift")
let source = try String(contentsOf: target, encoding: .utf8)
let checks = try String(contentsOfFile: "Tests/OnboardingVideoLayoutTestApp.swift", encoding: .utf8)
try (source + "\n" + checks).write(to: target, atomically: true, encoding: .utf8)
try "".write(to: root.appendingPathComponent("neko_idApp.swift"), atomically: true, encoding: .utf8)
SWIFT
xcodebuild -quiet -project "$video_workspace/neko-id.xcodeproj" -scheme neko-id \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$video_workspace/Build" \
  PRODUCT_BUNDLE_IDENTIFIER=uk.nekoid.videolayoutchecks CODE_SIGNING_ALLOWED=NO build \
  > "$video_workspace/build.log" 2>&1 || { tail -n 80 "$video_workspace/build.log"; exit 1; }
xcrun simctl install booted "$video_workspace/Build/Build/Products/Debug-iphonesimulator/neko-id.app"
SIMCTL_CHILD_NEKO_LAYOUT_RUN="$video_run" SIMCTL_CHILD_NEKO_VIDEO_BASELINE="${NEKO_VIDEO_BASELINE:-0}" \
  xcrun simctl launch --terminate-running-process booted uk.nekoid.videolayoutchecks
video_container=$(xcrun simctl get_app_container booted uk.nekoid.videolayoutchecks data)
video_report="$video_container/Documents/video-checks-$video_run.txt"
for ((attempt = 0; attempt < 55; attempt++)); do
  if [[ -f "$video_report" ]]; then
    cat "$video_report"
    echo "Review PNGs in: $video_container/Documents"
    echo "Build workspace: $video_workspace"
    exit 0
  fi
  sleep 1
done
echo "FAIL: video layout checks did not finish; inspect simulator crash logs." >&2
echo "Build workspace: $video_workspace"
exit 1
