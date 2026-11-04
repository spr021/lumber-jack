#!/bin/bash
# v1.3.3 release pipeline — "Android Leaderboard Fix (threaded HTTP hang)".
# Run with:  bash /Users/saber/lumber-jack/tools/lj_release_v133.sh
set -e
G="/Applications/Godot.app/Contents/MacOS/Godot"
SRC=/Users/saber/lumber-jack
CLEAN=/tmp/lj_relclean
OUT=/tmp/lj_release_v133
WEBZIP=/tmp/lj_webzip

echo "== 0/9 sanity: no debug prints left in scores_api.gd =="
if grep -q "LJDBG" "$SRC/scripts/scores_api.gd"; then echo "FATAL: LJDBG prints still in scores_api.gd"; exit 1; fi

echo "== 1/9 restore any editor-clobbered menu.tscn =="
cd "$SRC"
git checkout -- scenes/menu.tscn 2>/dev/null || true

echo "== 2/9 rules test (gate) =="
"$G" --headless --path "$SRC" --script res://tests/rules_test.gd | tail -3

echo "== 3/9 commit + tag + push =="
if git rev-parse -q --verify v1.3.3 >/dev/null 2>&1; then
  echo "tag v1.3.3 already exists — skipping commit/tag"
else
  git add scripts/scores_api.gd export_presets.cfg tools/lj_release_v133.sh tools/lj_android_debug.sh
  git commit -m "fix: Android leaderboard — disable threaded HTTPRequest

Threaded HTTP hangs silently on Android: request() returns OK, no error
is ever logged, the 5s timeout never fires, and the request never leaves
the device (reproduced on the emulator AND a real phone; logcat showed
only periodic !is_inside_tree can_process noise). With
HTTPRequest.use_threads = false every RPC completes normally
(result_code=0, real bodies) and the leaderboard fills.

Also pins permissions/internet=true in the Android preset (debug exports
force-add it anyway, but release exports would need the checkbox)."
  git tag v1.3.3
  git push origin main v1.3.3
fi

echo "== 4/9 clean copy + import =="
rm -rf "$CLEAN"
mkdir -p "$OUT/web" "$OUT/ios"
rsync -a --exclude addons --exclude .godot --exclude builds --exclude screenshots --exclude .git "$SRC/" "$CLEAN/"
git -C "$SRC" show HEAD:scenes/menu.tscn > "$CLEAN/scenes/menu.tscn"
"$G" --headless --path "$CLEAN" --import > "$OUT/import.log" 2>&1

echo "== 5/9 exports =="
"$G" --headless --path "$CLEAN" --export-release "Web" "$OUT/web/lumberjack-web.html" > "$OUT/web-export.log" 2>&1
echo "web ok"
"$G" --headless --path "$CLEAN" --export-debug "Android" "$OUT/lumberjack-android.apk" > "$OUT/android-export.log" 2>&1
echo "android ok"
"$G" --headless --path "$CLEAN" --export-release "Windows Desktop" "$OUT/lumberjack-windows.exe" > "$OUT/win-export.log" 2>&1
echo "windows ok"
"$G" --headless --path "$CLEAN" --export-release "Linux" "$OUT/lumberjack-linux.x86_64" > "$OUT/linux-export.log" 2>&1
mv "$OUT/lumberjack-linux.x86_64" "$OUT/lumberjack-linux"
echo "linux ok"
"$G" --headless --path "$CLEAN" --export-release "macOS" "$OUT/lumberjack-macos.zip" > "$OUT/macos-export.log" 2>&1
echo "macos ok"
"$G" --headless --path "$CLEAN" --export-release "iOS" "$OUT/ios/lumberjack-ios" > "$OUT/ios-export.log" 2>&1 || true
ls "$OUT/ios/lumberjack-ios.xcodeproj" > /dev/null && echo "ios ok (exit 1 expected)"

echo "== 6/9 package zips =="
python3 - <<'PYEOF'
import zipfile, os
O = '/tmp/lj_release_v133'
def z(dst, entries):
    with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
        for arc, p in entries:
            z.write(p, arc)
    print(dst, os.path.getsize(dst))
z(O + '/lumberjack-linux.zip', [('lumberjack-linux', O + '/lumberjack-linux')])
z(O + '/lumberjack-windows.zip', [('lumberjack-windows.exe', O + '/lumberjack-windows.exe')])
web = []
for f in sorted(os.listdir(O + '/web')):
    if f.endswith('.import'):
        continue
    web.append((f, O + '/web/' + f))
z(O + '/lumberjack-web.zip', web)
PYEOF
PB="$OUT/ios/lumberjack-ios.xcodeproj/project.pbxproj"
sed -i '' -e 's/IPHONEOS_DEPLOYMENT_TARGET = 14.0;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g' -e 's/iPhone Developer/Apple Development/g' -e 's/iPhone Distribution/Apple Development/g' "$PB"
python3 - <<'PYEOF'
import zipfile, os
src = '/tmp/lj_release_v133/ios'
dst = '/tmp/lj_release_v133/lumberjack-ios-xcode.zip'
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, src))
print(dst, os.path.getsize(dst))
PYEOF
cd "$OUT/ios"
xcodebuild -project lumberjack-ios.xcodeproj -scheme lumberjack-ios -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO build > "$OUT/xcodebuild.log" 2>&1
APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*Build/Products/Release-iphoneos/lumberjack-ios.app" -maxdepth 6 -newer "$OUT/web/lumberjack-web.html" 2>/dev/null | head -1)
echo "app at: $APP"
python3 - "$APP" "$OUT/lumberjack-ios-unsigned.ipa" <<'PYEOF'
import zipfile, os, shutil, sys
app, dst = sys.argv[1], sys.argv[2]
staging = '/tmp/lj_ipa_staging'
shutil.rmtree(staging, ignore_errors=True)
payload = os.path.join(staging, 'Payload')
os.makedirs(payload)
shutil.copytree(app, os.path.join(payload, os.path.basename(app)))
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(staging):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, staging))
print('ipa', os.path.getsize(dst))
PYEOF

echo "== 7/9 GitHub release =="
if gh release view v1.3.3 --repo spr021/lumber-jack >/dev/null 2>&1; then
  echo "release v1.3.3 already exists — skipping"
else
  gh release create v1.3.3 --repo spr021/lumber-jack \
    --title "v1.3.3 — Android Leaderboard Fix" \
    --notes "Android's leaderboard was hanging silently: Godot's threaded HTTPRequest never completed on Android (no error, no timeout — the request never left the device), so the board stayed empty on phones and emulators while desktop and the Web worked. HTTPRequest.use_threads = false makes every RPC a non-blocking poll that completes normally on all platforms; verified end-to-end on Android (submit, daily board, rename all return 200).

Also pins the INTERNET permission explicitly in the Android preset.

**Full changelog:** https://github.com/spr021/lumber-jack/compare/v1.3.2...v1.3.3" \
    "$OUT/lumberjack-android.apk" \
    "$OUT/lumberjack-ios-unsigned.ipa" \
    "$OUT/lumberjack-ios-xcode.zip" \
    "$OUT/lumberjack-linux.zip" \
    "$OUT/lumberjack-macos.zip" \
    "$OUT/lumberjack-web.zip" \
    "$OUT/lumberjack-windows.zip"
fi

echo "== 8/9 gh-pages deploy =="
rm -rf /tmp/lj_ghpages
git clone https://github.com/spr021/lumber-jack.git /tmp/lj_ghpages > /dev/null 2>&1
cd /tmp/lj_ghpages
git checkout gh-pages > /dev/null 2>&1
rm -rf index.html lumberjack-web.*
for f in "$OUT"/web/lumberjack-web.*; do
  case "$f" in *.import) ;; *) cp "$f" . ;; esac
done
mv lumberjack-web.html index.html
touch .nojekyll
git add -A
git commit -m "deploy v1.3.3 — android leaderboard fix (same web fix carried)" > /dev/null
git push origin gh-pages
LOCAL_PCK=$(shasum -a 256 "$OUT/web/lumberjack-web.pck" | cut -c1-64)
echo "local pck sha256: $LOCAL_PCK"

echo "== 9/9 wait for Pages CDN, verify live pck =="
for i in $(seq 1 40); do
  LIVE=$(curl -s https://spr021.github.io/lumber-jack/lumberjack-web.pck | shasum -a 256 | cut -c1-64)
  if [ "$LIVE" = "$LOCAL_PCK" ]; then echo "LIVE PCK MATCHES after $i checks"; break; fi
  sleep 30
done
[ "$LIVE" = "$LOCAL_PCK" ] || echo "WARNING: CDN did not flip within 20 min — check Pages build"
echo "ALL DONE — install $OUT/lumberjack-android.apk on the phone and re-check"
