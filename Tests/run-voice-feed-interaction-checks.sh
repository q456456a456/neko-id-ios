#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
feed_workspace=$(mktemp -d /tmp/neko-feed-interactions.XXXXXX)
feed_simulator=${NEKO_FEED_SIMULATOR:-booted}
cp -R neko-id neko-id.xcodeproj Info.plist "$feed_workspace/"
mv "$feed_workspace/neko-id/neko_idApp.swift" "$feed_workspace/original-main.swift"
ruby - "$feed_workspace" <<'RUBY'
path = File.join(ARGV.fetch(0), 'neko-id', 'ContentView.swift')
current = File.read(path)
reference = IO.popen(['git', 'show', '72463e8:neko-id/ContentView.swift'], &:read)
raise 'Cannot load reference feed' unless $?.success?
start = reference.index('private struct VoiceFeedCard: View') or raise 'Missing card'
finish = reference.index('private enum VoiceMediaMetrics', start) or raise 'Missing card boundary'
card = reference[start...finish].sub('VoiceFeedCard', 'ReferenceFeedCard')
start = current.index('private struct TimelineVoiceRow: View') or raise 'Missing row'
finish = current.index('private struct PendingVoicePublishCard', start) or raise 'Missing row boundary'
row = current[start...finish].sub('TimelineVoiceRow', 'ReferenceFeedTimelineRow').gsub('VoiceFeedCard(', 'ReferenceFeedCard(')
File.write(path, current + "\n" + card + "\n" + row + "\n" + File.read('Tests/VoiceFeedInteractionTestApp.swift'))
RUBY
xcodebuild -quiet -project "$feed_workspace/neko-id.xcodeproj" -scheme neko-id \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$feed_workspace/Build" \
  PRODUCT_BUNDLE_IDENTIFIER=uk.nekoid.feedinteractionchecks CODE_SIGNING_ALLOWED=NO build \
  > "$feed_workspace/build.log" 2>&1 || { cat "$feed_workspace/build.log"; exit 1; }
xcrun simctl install "$feed_simulator" "$feed_workspace/Build/Build/Products/Debug-iphonesimulator/neko-id.app"
SIMCTL_CHILD_NEKO_FEED_BASELINE="${NEKO_FEED_BASELINE:-0}" xcrun simctl launch --terminate-running-process "$feed_simulator" uk.nekoid.feedinteractionchecks
echo "Build workspace: $feed_workspace"
xcrun simctl get_app_container "$feed_simulator" uk.nekoid.feedinteractionchecks data
echo 'Use Device Hub to tap the first/second more buttons, the photo and tags; verify feed-events.txt.'
