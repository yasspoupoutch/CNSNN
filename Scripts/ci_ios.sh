#!/usr/bin/env bash
# Steps of the iOS workflow (.github/workflows/ios-simulator.yml), so that every test target
# runs with exactly the same xcodebuild settings. Needs CI_ROOT (and SIMULATOR_ID for the
# simulator steps).
#   setup                 check Xcode 27 and the project, create CI_ROOT
#   resolve               fetch the Swift packages (Firebase) into CI_ROOT/SourcePackages
#   simulator             pick an iPhone simulator matching the SDK and start booting it
#   build-for-testing     build the app, widget and every test bundle once (Debug, unsigned)
#   test <name> <target>…  run test targets on what build-for-testing built, without rebuilding
#   release               build in Release for iPhone, like the IPA
set -euo pipefail
cd "$(dirname "$0")/.."

unsigned=(ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='')
project=(-project CNSNN.xcodeproj -scheme CNSNN -clonedSourcePackagesDirPath "${CI_ROOT:-}/SourcePackages")

# macOS still ships bash 3.2: plain arrays only (no mapfile).
simulator_debug() {
  sim=(-configuration Debug -sdk iphonesimulator
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 60
    -derivedDataPath "$CI_ROOT/DerivedData" -disableAutomaticPackageResolution)
}

case "${1:-}" in
  setup)
    mkdir -p "$CI_ROOT/logs"
    xcodebuild -version | tee "$CI_ROOT/logs/xcode-version.log"
    if ! grep -Eq '^Xcode 27([.]|$)' "$CI_ROOT/logs/xcode-version.log"; then
      echo '::error::Le runner doit fournir Xcode 27.'
      exit 1
    fi
    python3 Scripts/verify_project.py
    ;;

  resolve)
    xcodebuild -resolvePackageDependencies "${project[@]}" \
      -derivedDataPath "$CI_ROOT/DerivedData" "${unsigned[@]}" \
      2>&1 | tee "$CI_ROOT/logs/packages.log"
    ;;

  simulator)
    python3 <<'PY'
import json
import os
import subprocess

sdk = subprocess.check_output(
    ['xcodebuild', '-version', '-sdk', 'iphonesimulator', 'SDKVersion'],
    text=True,
).strip()
sdk_version = tuple(int(part) for part in sdk.split('.')[:2])
listing = json.loads(subprocess.check_output(
    ['xcrun', 'simctl', 'list', '--json'], text=True,
))
candidates = []
for runtime in listing['runtimes']:
    if not runtime.get('isAvailable') or '.iOS-' not in runtime['identifier']:
        continue
    version = tuple(int(part) for part in runtime['version'].split('.')[:2])
    if version[0] != sdk_version[0] or version > sdk_version:
        continue
    for device in listing['devices'].get(runtime['identifier'], []):
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            candidates.append((version, device['name'], device['udid']))
if not candidates:
    raise SystemExit(f'Aucun simulateur iPhone disponible pour le SDK {sdk}.')
version, name, identifier = sorted(candidates, reverse=True)[0]
with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file:
    file.write(f'SIMULATOR_ID={identifier}\n')
print(f'Simulateur choisi : {name}, iOS {version[0]}.{version[1]}, {identifier}')
with open(os.path.join(os.environ['CI_ROOT'], 'simulator-id'), 'w', encoding='utf-8') as file:
    file.write(identifier)
PY
    # Booting takes a few minutes on a fresh runner: it runs while the app compiles.
    nohup xcrun simctl boot "$(cat "$CI_ROOT/simulator-id")" > "$CI_ROOT/logs/simulator-boot.log" 2>&1 &
    ;;

  build-for-testing)
    simulator_debug
    xcodebuild build-for-testing "${project[@]}" "${sim[@]}" \
      -resultBundlePath "$CI_ROOT/build.xcresult" "${unsigned[@]}" \
      2>&1 | tee "$CI_ROOT/logs/build.log"
    ;;

  test)
    name="$2"
    shift 2
    only=()
    for target in "$@"; do only+=("-only-testing:$target"); done
    simulator_debug
    xcodebuild test-without-building "${project[@]}" "${sim[@]}" \
      -parallel-testing-enabled NO -test-timeouts-enabled YES \
      "${only[@]}" -resultBundlePath "$CI_ROOT/$name.xcresult" "${unsigned[@]}" \
      2>&1 | tee "$CI_ROOT/logs/$name.log"
    ;;

  release)
    # The IPA is built in Release: compile that configuration too, so a Release-only error
    # (code under #if DEBUG, optimizer) is caught before merging and not when building the IPA.
    xcodebuild build "${project[@]}" -configuration Release \
      -sdk iphoneos -destination 'generic/platform=iOS' \
      -derivedDataPath "$CI_ROOT/DerivedDataRelease" -disableAutomaticPackageResolution \
      "${unsigned[@]}" 2>&1 | tee "$CI_ROOT/logs/build-release.log"
    ;;

  *)
    echo "Usage: $0 setup|resolve|simulator|build-for-testing|test <name> <target>…|release" >&2
    exit 2
    ;;
esac
