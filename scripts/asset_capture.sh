#!/usr/bin/env bash
#
# asset_capture.sh — instructional-asset base-screenshot pipeline (F1 residue).
# 同梱チュートリアル画像の元スクリーンショット採取パイプライン。
#
# For ONE language (en|ja) and ONE appearance (light|dark):
#   a. boot the simulator + set SYSTEM language (reboot only if it changes)
#   b. set appearance (simctl ui) + status bar override (9:41, full battery)
#   c. run CopakyAssetCaptureTests (SIGNED) → xcresult → export attachments
#   d. copy asset_appsettings / asset_keyboards / asset_fa_alert PNGs to
#      <WORKSPACE>/reports/asset_recapture/raw/<lang>_<appearance>/
#
# Simulator limitation (verified 2026-07-25): the paste-permission dialog and
# the "Paste from Other Apps" settings row do not exist on the Simulator —
# pasteRequestDialogue + pasteFromOtherAppsSetting bases need a physical device.
#
# Usage: asset_capture.sh en|ja light|dark
#
set -uo pipefail

LANG_ARG="${1:-}"
APPEAR="${2:-}"
if [[ "$LANG_ARG" != "en" && "$LANG_ARG" != "ja" ]] || [[ "$APPEAR" != "light" && "$APPEAR" != "dark" ]]; then
  echo "Usage: $0 en|ja light|dark" >&2
  exit 2
fi

UDID="${COPAKY_UDID:-E0552C62-FFDB-4DF6-9040-2734DB5B2458}"
TEAM="4XDQKU66NJ"
SCHEME="CopakyUITests"
UITEST_BUNDLE="azooKeyUITests"
REPO_DIR="/Users/vittoriovillani/SviluppoTastieraOpen/vendor/azooKey"
PROJECT="$REPO_DIR/azooKey.xcodeproj"
WORKSPACE="/Users/vittoriovillani/SviluppoTastieraOpen"
OUT_DIR="$WORKSPACE/reports/asset_recapture/raw/${LANG_ARG}_${APPEAR}"
ART_DIR="$WORKSPACE/reports/asset_recapture/_artifacts"
DEST="id=$UDID"

if [[ "$LANG_ARG" == "ja" ]]; then
  APPLE_LANGS='ja'; APPLE_LOCALE='ja_JP'
else
  APPLE_LANGS='en'; APPLE_LOCALE='en_US'
fi

mkdir -p "$OUT_DIR" "$ART_DIR"
log() { echo "[$(date +%H:%M:%S)] $*"; }
sign_args=(-allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic)

status_bar() {
  xcrun simctl status_bar "$UDID" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100 2>/dev/null || true
}

# ---- a. boot + language (reboot only when the language actually changes) -----
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
CURRENT_LANG="$(xcrun simctl spawn "$UDID" defaults read .GlobalPreferences.plist AppleLanguages 2>/dev/null | sed -n 's/^ *"*\([a-z][a-z]\)"*,*$/\1/p' | head -1)"
if [[ "$CURRENT_LANG" != "$APPLE_LANGS" ]]; then
  log "Language $CURRENT_LANG → $APPLE_LANGS (reboot)"
  xcrun simctl spawn "$UDID" defaults write .GlobalPreferences.plist AppleLanguages -array "$APPLE_LANGS" || true
  xcrun simctl spawn "$UDID" defaults write .GlobalPreferences.plist AppleLocale -string "$APPLE_LOCALE" || true
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
  sleep 3
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
  sleep 3
else
  log "Language already $APPLE_LANGS"
fi

# ---- b. appearance + status bar ---------------------------------------------
xcrun simctl ui "$UDID" appearance "$APPEAR" 2>/dev/null || true
sleep 1
status_bar
log "Appearance=$APPEAR, status bar overridden"

# ---- c. run the capture suite (SIGNED) --------------------------------------
XCRESULT="$ART_DIR/${LANG_ARG}_${APPEAR}.xcresult"
rm -rf "$XCRESULT"
xcrun simctl terminate "$UDID" com.apple.Preferences 2>/dev/null || true
log "Running CopakyAssetCaptureTests"
xcodebuild test \
  -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" "${sign_args[@]}" \
  -resultBundlePath "$XCRESULT" \
  -only-testing:"$UITEST_BUNDLE/CopakyAssetCaptureTests/test_assetCapture" \
  2>&1 | tail -15 || true

# ---- d. export attachments → PNGs -------------------------------------------
EXPORT_DIR="$ART_DIR/${LANG_ARG}_${APPEAR}_attachments"
rm -rf "$EXPORT_DIR"
if [[ ! -d "$XCRESULT" ]]; then
  log "FATAL: no xcresult produced ($XCRESULT)"
  exit 1
fi
xcrun xcresulttool export attachments --path "$XCRESULT" --output-path "$EXPORT_DIR" >/dev/null 2>&1 || true

COPAKY_EXPORT_DIR="$EXPORT_DIR" COPAKY_OUT_DIR="$OUT_DIR" /usr/bin/python3 - <<'PY'
import json, os, re, shutil
export_dir = os.environ["COPAKY_EXPORT_DIR"]
out_dir = os.environ["COPAKY_OUT_DIR"]
manifest = os.path.join(export_dir, "manifest.json")
wanted = ["asset_appsettings", "asset_keyboards", "asset_fa_alert"]
best = {}
if os.path.exists(manifest):
    data = json.load(open(manifest))
    for test in data:
        for att in test.get("attachments", []):
            name = att.get("suggestedHumanReadableName", "") or ""
            for shot in wanted:
                if re.match(rf"^{shot}([._]|$)", name):
                    ts = att.get("timestamp", 0) or 0
                    if shot not in best or ts >= best[shot][0]:
                        best[shot] = (ts, att.get("exportedFileName"))
                    break
for shot in wanted:
    if shot in best:
        _, fn = best[shot]
        src = os.path.join(export_dir, fn) if fn else ""
        if fn and os.path.exists(src):
            shutil.copyfile(src, os.path.join(out_dir, shot + ".png"))
            print("mapped", shot)
missing = [s for s in wanted if s not in best]
if missing:
    print("MISSING:", ", ".join(missing))
PY

log "=== DONE $LANG_ARG/$APPEAR → $OUT_DIR ==="
