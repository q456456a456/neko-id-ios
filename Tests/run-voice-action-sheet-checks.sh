#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sheet_workspace=$(mktemp -d /tmp/neko-voice-action-sheet.XXXXXX)
sheet_run=$(uuidgen)
sheet_simulator=${NEKO_SHEET_SIMULATOR:-booted}
cp -R neko-id neko-id.xcodeproj Info.plist "$sheet_workspace/"
mv "$sheet_workspace/neko-id/neko_idApp.swift" "$sheet_workspace/original-main.swift"
ruby - "$sheet_workspace" <<'RUBY'
root = ARGV.fetch(0)
path = File.join(root, 'neko-id', 'ContentView.swift')
reference = IO.popen(['git', 'show', '72463e8:neko-id/ContentView.swift'], &:read)
raise 'Cannot load reference sheet' unless $?.success?
start = reference.index('private struct VoiceActionSheet: View') or raise 'Missing reference sheet'
finish = reference.index('private struct SavePosterIcon: View', start) or raise 'Missing sheet boundary'
sheet = reference[start...finish].sub('VoiceActionSheet', 'ReferenceVoiceActionSheet')
File.write(path, File.read(path) + "\n" + sheet + "\n" + File.read('Tests/VoiceActionSheetLayoutTests.swift'))
RUBY
xcodebuild -quiet -project "$sheet_workspace/neko-id.xcodeproj" -scheme neko-id \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$sheet_workspace/Build" \
  PRODUCT_BUNDLE_IDENTIFIER=uk.nekoid.voiceactionchecks CODE_SIGNING_ALLOWED=NO build \
  > "$sheet_workspace/build.log" 2>&1 || { cat "$sheet_workspace/build.log"; exit 1; }
xcrun simctl install "$sheet_simulator" "$sheet_workspace/Build/Build/Products/Debug-iphonesimulator/neko-id.app"
SIMCTL_CHILD_NEKO_LAYOUT_RUN="$sheet_run" xcrun simctl launch --terminate-running-process "$sheet_simulator" uk.nekoid.voiceactionchecks
sheet_container=$(xcrun simctl get_app_container "$sheet_simulator" uk.nekoid.voiceactionchecks data)
sheet_report="$sheet_container/Documents/voice-action-checks-$sheet_run.txt"
for ((attempt = 0; attempt < 45; attempt++)); do
  if [[ -f "$sheet_report" ]]; then
    cat "$sheet_report"
    echo
    echo "Review PNGs in: $sheet_container/Documents"
    echo "Build workspace: $sheet_workspace"
    exit 0
  fi
  sleep 1
done
echo "FAIL: sheet checks did not finish; inspect simulator logs." >&2
echo "Build workspace: $sheet_workspace" >&2
exit 1
