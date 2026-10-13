#!/usr/bin/env bash
# Runs CNSNNIntegrationTests in the simulator against the Firebase Auth and Firestore
# emulators, which enforce Firebase/firestore.rules. Used by the iOS workflow.
# Signed ad hoc with simulator entitlements so Firebase Auth can use the keychain.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/Firebase"
npm ci --no-audit --no-fund || npm install --no-audit --no-fund
# Passed by xcodebuild to the test process as CNSNN_EMULATOR.
export TEST_RUNNER_CNSNN_EMULATOR=1
npx firebase emulators:exec --only auth,firestore --project demo-cnsnn "cd '$root' && xcodebuild test \
  -project CNSNN.xcodeproj -scheme CNSNN -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=$SIMULATOR_ID' -destination-timeout 60 \
  -clonedSourcePackagesDirPath '$CI_ROOT/SourcePackages' -derivedDataPath '$CI_ROOT/DerivedData' \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -only-testing:CNSNNIntegrationTests -resultBundlePath '$CI_ROOT/integration-tests.xcresult' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM='' \
  CODE_SIGN_ENTITLEMENTS='$root/Tests/Integration/Simulator.entitlements'"
