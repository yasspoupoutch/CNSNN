#!/usr/bin/env bash
# The app on a small phone, like a Galaxy S9 (1080 × 2220 at 480 dpi = 360 × 740 dp, three-button bar,
# on-screen keyboard), then SmallScreenTest: the pictures and the margins land in $1.
set -euo pipefail
out=${1:?dossier de sortie}
mkdir -p "$out"
adb shell wm size 1080x2220
adb shell wm density 480
adb shell cmd overlay enable com.android.internal.systemui.navbar.threebutton || true
adb shell settings put secure show_ime_with_hard_keyboard 1
adb shell cmd uimode night yes
# A slow emulator can show "Pixel Launcher isn't responding" over the app and steal the keyboard: no such dialogs.
adb shell settings put global hide_error_dialogs 1
sleep 20
# Installed and run by hand: Gradle's connected tests uninstall the app, and its files with it.
./gradlew --no-daemon :app:installDebug :app:installDebugAndroidTest
adb shell am instrument -w -e class com.poupoutch.cnsnn.SmallScreenTest -e smallScreen true \
  com.poupoutch.cnsnn.test/androidx.test.runner.AndroidJUnitRunner | tee "$out/instrument.log"
for name in $(adb shell run-as com.poupoutch.cnsnn ls files/shots 2>/dev/null | tr -d "\r" || true); do
  adb exec-out run-as com.poupoutch.cnsnn cat "files/shots/$name" > "$out/$name"
done
ls -l "$out"
cat "$out/mesures.txt" || true
grep -q '^OK (1 test)' "$out/instrument.log" || { echo "::error::Un élément est caché sur petit écran (voir instrument.log et zz-echec.png)."; exit 1; }
