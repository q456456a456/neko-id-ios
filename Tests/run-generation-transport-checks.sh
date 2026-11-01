#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_workspace=$(mktemp -d /tmp/neko-generation-checks.XXXXXX)
xcrun swiftc neko-id/AppConfig.swift neko-id/NekoPerformanceTrace.swift \
  neko-id/NekoGenerationTransport.swift Tests/GenerationTransportTests.swift \
  -o "$test_workspace/generation-tests"
"$test_workspace/generation-tests"
