#!/usr/bin/env bash
# Installs the Release APK (R8 shrunk, like the published app) on the running emulator, opens it and
# checks it is still alive with no crash a few seconds later: the instrumented tests only cover Debug.
set -euo pipefail
apk=app/build/outputs/apk/release/app-release.apk
adb install -r "$apk"
adb logcat -c
adb shell am start -W -n com.poupoutch.cnsnn/.MainActivity
sleep 15
if ! adb shell pidof com.poupoutch.cnsnn >/dev/null; then
  echo "::error::La version Release s'est fermée au lancement."
  adb logcat -d -s AndroidRuntime:E | tail -80
  exit 1
fi
if adb logcat -d -s AndroidRuntime:E | grep -q "FATAL EXCEPTION"; then
  echo "::error::Plantage dans la version Release."
  adb logcat -d -s AndroidRuntime:E | tail -80
  exit 1
fi
echo "Version Release lancée sans plantage."
