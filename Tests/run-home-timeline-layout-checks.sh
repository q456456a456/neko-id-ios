#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
timeline_workspace=$(mktemp -d /tmp/neko-home-timeline-checks.XXXXXX)
timeline_run=$(uuidgen)
timeline_simulator=${NEKO_TIMELINE_SIMULATOR:-booted}
cp -R neko-id neko-id.xcodeproj Info.plist "$timeline_workspace/"
mv "$timeline_workspace/neko-id/neko_idApp.swift" "$timeline_workspace/original-main.swift"

# Mechanically append tests and the last shipped row to the disposable source
# copy. Production visibility and the real app entry point remain untouched.
ruby - "$timeline_workspace" <<'RUBY'
root = ARGV.fetch(0)
path = File.join(root, 'neko-id', 'ContentView.swift')
reference = IO.popen(['git', 'show', '72463e8:neko-id/ContentView.swift'], &:read)
raise 'Cannot load reference row' unless $?.success?
start = reference.index('private struct TimelineVoiceRow: View') or raise 'Missing reference row'
finish = reference.index('private struct PendingVoicePublishCard: View', start) or raise 'Missing row boundary'
row = reference[start...finish].sub('TimelineVoiceRow', 'ReferenceTimelineVoiceRow')
row = row.gsub('VoiceFeedCard(', 'ReferenceTimelineFeedCard(')
start = reference.index('private struct VoiceFeedCard: View') or raise 'Missing reference card'
finish = reference.index('private enum VoiceMediaMetrics', start) or raise 'Missing card boundary'
card = reference[start...finish].sub('VoiceFeedCard', 'ReferenceTimelineFeedCard')
File.write(path, File.read(path) + "\n" + card + "\n" + row + "\n" + File.read('Tests/HomeVoiceTimelineLayoutTests.swift'))
RUBY

xcodebuild -quiet -project "$timeline_workspace/neko-id.xcodeproj" -scheme neko-id \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$timeline_workspace/Build" \
  PRODUCT_BUNDLE_IDENTIFIER=uk.nekoid.timelinechecks CODE_SIGNING_ALLOWED=NO build \
  > "$timeline_workspace/build.log" 2>&1 || { cat "$timeline_workspace/build.log"; exit 1; }
xcrun simctl install "$timeline_simulator" "$timeline_workspace/Build/Build/Products/Debug-iphonesimulator/neko-id.app"
SIMCTL_CHILD_NEKO_LAYOUT_RUN="$timeline_run" xcrun simctl launch --terminate-running-process "$timeline_simulator" uk.nekoid.timelinechecks
timeline_container=$(xcrun simctl get_app_container "$timeline_simulator" uk.nekoid.timelinechecks data)
timeline_report="$timeline_container/Documents/timeline-checks-$timeline_run.txt"
for ((attempt = 0; attempt < 55; attempt++)); do
  if [[ -f "$timeline_report" ]]; then
    cat "$timeline_report"
    echo
    echo "Review PNGs in: $timeline_container/Documents"
    echo "Build workspace: $timeline_workspace"
    exit 0
  fi
  sleep 1
done
echo "FAIL: timeline checks did not finish; inspect the simulator crash report." >&2
echo "Build workspace: $timeline_workspace" >&2
exit 1
