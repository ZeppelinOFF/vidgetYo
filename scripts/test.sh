#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: Functional tests must run on macOS."
  exit 1
fi

xcodebuild test \
  -project "$ROOT/VidgetYo.xcodeproj" \
  -scheme VidgetYo \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$ROOT/build/TestDerived" \
  CODE_SIGNING_ALLOWED=NO
