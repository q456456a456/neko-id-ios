#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
insight_workspace=$(mktemp -d /tmp/neko-voice-insight-checks.XXXXXX)
insight_run=$(uuidgen)
cp -R neko-id neko-id.xcodeproj Info.plist "$insight_workspace/"
python3 - "$insight_workspace" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]) / 'neko-id'
source = (root / 'ContentView.swift').read_text()
start = source.index('private struct VoiceInsightBlock: View')
end = source.index('private struct VoiceInsightSkeleton: View', start)
reference = source[start:end].replace('VoiceInsightBlock', 'ReferenceVoiceInsightBlock')
reference = reference.replace('                    .lineLimit(5)\n                    .truncationMode(.tail)\n', '')
(root / 'ContentView.swift').write_text(source + '\n' + reference + '\n' + Path('Tests/VoiceInsightLayoutTests.swift').read_text())
(root / 'neko_idApp.swift').unlink()
PY
xcodebuild -quiet -project "$insight_workspace/neko-id.xcodeproj" -scheme neko-id \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$insight_workspace/Build" \
  PRODUCT_BUNDLE_IDENTIFIER=uk.nekoid.insightchecks CODE_SIGNING_ALLOWED=NO build \
  > "$insight_workspace/build.log" 2>&1 || { cat "$insight_workspace/build.log"; exit 1; }
xcrun simctl install booted "$insight_workspace/Build/Build/Products/Debug-iphonesimulator/neko-id.app"
SIMCTL_CHILD_NEKO_LAYOUT_RUN="$insight_run" xcrun simctl launch --terminate-running-process booted uk.nekoid.insightchecks
insight_container=$(xcrun simctl get_app_container booted uk.nekoid.insightchecks data)
insight_report="$insight_container/Documents/insight-checks-$insight_run.txt"
for ((attempt = 0; attempt < 55; attempt++)); do
  if [[ -f "$insight_report" ]]; then
    cat "$insight_report"
    echo "Review PNGs in: $insight_container/Documents"
    exit 0
  fi
  sleep 1
done
echo "FAIL: interpretation checks did not finish; inspect simulator crash logs." >&2
exit 1
