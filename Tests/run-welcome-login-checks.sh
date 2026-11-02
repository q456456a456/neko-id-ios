#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
simulator_id=${1:?Pass a booted simulator UDID}
login_run=$(uuidgen)
login_workspace=$(mktemp -d /tmp/neko-welcome-login.XXXXXX)
cp -R neko-id neko-id.xcodeproj Info.plist "$login_workspace/"

# Mechanical test-only composition, leaving production source/session data intact.
xcrun swift - "$login_workspace" <<'SWIFT'
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("neko-id")
let flow = root.appendingPathComponent("OnboardingFlowView.swift")
let source = try String(contentsOf: flow, encoding: .utf8)
let fixture = try String(contentsOfFile: "Tests/WelcomeLoginTestApp.swift", encoding: .utf8)
try (source + "\n" + fixture).write(to: flow, atomically: true, encoding: .utf8)
try "".write(to: root.appendingPathComponent("neko_idApp.swift"), atomically: true, encoding: .utf8)
let keychain = root.appendingPathComponent("KeychainStore.swift")
let isolated = try String(contentsOf: keychain, encoding: .utf8)
    .replacingOccurrences(of: "uk.neko-id.app", with: "uk.nekoid.welcomeloginchecks")
try isolated.write(to: keychain, atomically: true, encoding: .utf8)
let api = root.appendingPathComponent("NekoServerAPIClient.swift")
let apiSource = try String(contentsOf: api, encoding: .utf8)
let sessionMarker = "let configuration = URLSessionConfiguration.default"
precondition(apiSource.contains(sessionMarker))
let mockAPI = apiSource
    .replacingOccurrences(of: sessionMarker, with: sessionMarker + "\n        configuration.protocolClasses = [WelcomeLoginMockProtocol.self]")
    .replacingOccurrences(of: "baseURL: URL = AppConfig.productionWebURL", with: "baseURL: URL = URL(string: \"https://welcome-login.invalid\")!")
precondition(!mockAPI.contains("baseURL: URL = AppConfig.productionWebURL"))
try mockAPI.write(to: api, atomically: true, encoding: .utf8)
SWIFT

xcodebuild -quiet -project "$login_workspace/neko-id.xcodeproj" -scheme neko-id \
  -destination "platform=iOS Simulator,id=$simulator_id" -derivedDataPath "$login_workspace/Build" \
  PRODUCT_BUNDLE_IDENTIFIER=uk.nekoid.welcomeloginchecks CODE_SIGNING_ALLOWED=NO build \
  > "$login_workspace/build.log" 2>&1 || { tail -n 80 "$login_workspace/build.log"; exit 1; }
xcrun simctl install "$simulator_id" "$login_workspace/Build/Build/Products/Debug-iphonesimulator/neko-id.app"
SIMCTL_CHILD_NEKO_LOGIN_RUN="$login_run" xcrun simctl launch --terminate-running-process "$simulator_id" uk.nekoid.welcomeloginchecks
login_container=$(xcrun simctl get_app_container "$simulator_id" uk.nekoid.welcomeloginchecks data)
login_results="$login_container/Documents/login-checks-$login_run"
for ((attempt = 0; attempt < 45; attempt++)); do
  if [[ -f "$login_results/welcome-login-checks.txt" ]]; then
    sed -n '1,40p' "$login_results/welcome-login-checks.txt"
    echo "Snapshots: $login_results"
    echo "Build workspace: $login_workspace"
    exit 0
  fi
  sleep 1
done
echo "FAIL: login checks did not finish. Inspect $login_workspace/build.log and simulator crash logs." >&2
exit 1
