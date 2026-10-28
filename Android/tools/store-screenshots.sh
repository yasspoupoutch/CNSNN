#!/usr/bin/env bash
# Google Play screenshots on the running emulator (Firebase emulators, made-up players): dark theme,
# a clean status bar, then StoreScreenshotsTest; the PNG land in $1.
set -euo pipefail
out=${1:?dossier de sortie}
mkdir -p "$out"
adb shell cmd uimode night yes
adb shell settings put global sysui_demo_allowed 1
demo() { adb shell am broadcast -a com.android.systemui.demo -e command "$@" > /dev/null; }
demo enter
demo clock -e hhmm 0941
demo battery -e level 100 -e plugged false
demo network -e wifi show -e level 4
demo network -e mobile show -e datatype none -e level 4
demo notifications -e visible false
# Installed and run by hand: Gradle's connected tests uninstall the app, and its files with it.
./gradlew --no-daemon :app:installDebug :app:installDebugAndroidTest
adb shell am instrument -w -e class com.poupoutch.cnsnn.StoreScreenshotsTest -e storeScreenshots true \
  com.poupoutch.cnsnn.test/androidx.test.runner.AndroidJUnitRunner | tee "$out/instrument.log"
grep -q '^OK (1 test)' "$out/instrument.log" || { echo "::error::Les captures Google Play ont échoué."; exit 1; }
rm "$out/instrument.log"
for name in $(adb shell run-as com.poupoutch.cnsnn ls files/shots); do
  adb exec-out run-as com.poupoutch.cnsnn cat "files/shots/$name" > "$out/$name"
done
ls -l "$out"
