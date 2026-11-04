#!/bin/bash
# One-shot Android leaderboard diagnostic build (temporary — uses the live
# tree's LJDBG instrumentation, never commit scripts/scores_api.gd in this state).
set -e
G="/Applications/Godot.app/Contents/MacOS/Godot"
SRC=/Users/saber/lumber-jack
CLEAN=/tmp/lj_relclean
OUT=/tmp/lj_apk
mkdir -p "$OUT"

echo "== 1/5 clean copy (restores menu.tscn from HEAD) =="
rm -rf "$CLEAN"
rsync -a --exclude addons --exclude .godot --exclude builds --exclude screenshots --exclude .git "$SRC/" "$CLEAN/"
git -C "$SRC" show HEAD:scenes/menu.tscn > "$CLEAN/scenes/menu.tscn"

echo "== 2/5 import =="
"$G" --headless --path "$CLEAN" --import > "$OUT/import.log" 2>&1

echo "== 3/5 export debug APK (ignore errors only if the apk exists) =="
"$G" --headless --path "$CLEAN" --export-debug "Android" "$OUT/lumberjack-debug.apk" > "$OUT/export.log" 2>&1 || true
ls -la "$OUT/lumberjack-debug.apk"

echo "== 4/5 verify INTERNET permission in the built APK =="
adb shell dumpsys package com.saber.lumberjack | grep -iE "INTERNET|VIBRATE" || echo "NO INTERNET/VIBRATE MATCH"

echo "== 5/5 install =="
adb install -r "$OUT/lumberjack-debug.apk"

echo ""
echo "== DONE =="
echo "Now: launch the game on the emulator, wait ~20s on the menu (open the"
echo "rename dialog and tap SAVE too), then run:"
echo "  adb logcat -d | grep -iE 'LJDBG|godot' | grep -vE 'OpenGL|shader' | tail -60"
