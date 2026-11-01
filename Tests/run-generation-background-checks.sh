#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Start generation-background-server.mjs separately with Node first. Pass an
# already booted simulator ID; this installs a separate fixture app, not neko-id.
simulator_id=${1:?Pass a booted simulator UDID}
endpoint=${2:-http://127.0.0.1:18765}
fixture_workspace=$(mktemp -d /tmp/neko-generation-background.XXXXXX)
cp -R neko-id neko-id.xcodeproj Info.plist "$fixture_workspace/"
cp Tests/GenerationBackgroundTestApp.swift "$fixture_workspace/neko-id/neko_idApp.swift"
xcodebuild -quiet -project "$fixture_workspace/neko-id.xcodeproj" -scheme neko-id \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "$fixture_workspace/Build" \
  PRODUCT_BUNDLE_IDENTIFIER=uk.nekoid.generationcheck \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
xcrun simctl install "$simulator_id" "$fixture_workspace/Build/Build/Products/Debug-iphonesimulator/neko-id.app"
xcrun simctl launch --terminate-running-process "$simulator_id" uk.nekoid.generationcheck "--endpoint=$endpoint/generate"

# Wait until the server has accepted the actual file-backed POST.
accepted=false
for _ in $(seq 1 20); do
  if curl -fsS "$endpoint/status" | rg -q '"requests":1'; then accepted=true; break; fi
  sleep 1
done
if [[ "$accepted" != true ]]; then echo "FAIL: POST never reached fixture server"; exit 1; fi
xcrun simctl launch "$simulator_id" com.apple.mobilesafari
sleep 40
xcrun simctl launch "$simulator_id" uk.nekoid.generationcheck "--endpoint=$endpoint/generate"
fixture_container=$(xcrun simctl get_app_container "$simulator_id" uk.nekoid.generationcheck data)
for _ in $(seq 1 20); do
  if [[ -f "$fixture_container/Documents/result.txt" ]]; then break; fi
  sleep 1
done
rg '^PASS:' "$fixture_container/Documents/result.txt"
curl -fsS "$endpoint/status" | rg '"requests":1'
echo 'PASS: delayed file-backed POST survived 40 seconds in background without a second generation'
