#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Ce contrôle nécessite un Mac avec Xcode 26 ou ultérieur."
  exit 1
fi
xcodebuild -version
swift test
simulator_id=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for runtime,devices in d["devices"].items() if "iOS" in runtime for x in devices if "iPhone" in x["name"]))')
xcodebuild -project CNSNN.xcodeproj -scheme CNSNN -destination "platform=iOS Simulator,id=$simulator_id" -derivedDataPath work/DerivedData CODE_SIGNING_ALLOWED=NO test
