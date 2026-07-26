#!/usr/bin/env bash
#
# store_screenshots.sh — App Store 6.9" screenshot pipeline for ONE language.
#
# Pipeline (per language en|ja):
#   a. boot the simulator + set SYSTEM language (the keyboard extension follows the
#      system language, not a launch arg) + disable the hardware keyboard + reboot
#   b. status bar override (9:41, full battery, strong signal)
#   c. one-time setup (SIGNED): enable keyboard + Full Access, then navigate Safari to
#      the demo page (simctl openurl) and run the keyboard once to CREATE the App Group
#      container — only if the container does not exist yet
#   d. seed the container with the clipboard tab + demo history (seed_sim_clipboard.sh)
#   e. run the CopakyScreenshotTests suite (SIGNED) → xcresult → export attachments → PNGs
#   f. verify: 1320x2868 and no alpha channel (ASC 2026)
#
# Navigation note: `safari.launchArguments=["-u", url]` does NOT navigate on iOS 26 — it
# opens the Start Page. We navigate with `xcrun simctl openurl` (terminating the foreground
# apps first so Safari opens cleanly, without a "◀ App" breadcrumb) and the test only
# `activate()`s Safari.
#
# Output PNGs: <WORKSPACE>/reports/store_screenshots/<lang>/shot01..shot06.png
#
# Usage: store_screenshots.sh en|ja
#
set -uo pipefail

LANG_ARG="${1:-}"
if [[ "$LANG_ARG" != "en" && "$LANG_ARG" != "ja" ]]; then
  echo "Usage: $0 en|ja" >&2
  exit 2
fi

# ---- config --------------------------------------------------------------------
UDID="${COPAKY_UDID:-E0552C62-FFDB-4DF6-9040-2734DB5B2458}"
SCHEME="CopakyUITests"
UITEST_BUNDLE="azooKeyUITests"
REPO_DIR="/Users/vittoriovillani/SviluppoTastieraOpen/vendor/azooKey"
PROJECT="$REPO_DIR/azooKey.xcodeproj"
WORKSPACE="/Users/vittoriovillani/SviluppoTastieraOpen"
OUT_DIR="$WORKSPACE/reports/store_screenshots/$LANG_ARG"
ART_DIR="$WORKSPACE/reports/store_screenshots/_artifacts"
SEED="$REPO_DIR/scripts/seed_sim_clipboard.sh"
DEST="id=$UDID"
GROUP_ID="group.com.pettipol.copaky"
KB_BUNDLE="com.pettipol.copaky.keyboard"
EXPECTED_W=1320   # ASC 2026 6.9" portrait
EXPECTED_H=2868

if [[ "$LANG_ARG" == "ja" ]]; then
  DEMO_URL="https://copaky.app/demo.ja"
  APPLE_LANGS='ja'
  APPLE_LOCALE='ja_JP'
else
  DEMO_URL="https://copaky.app/demo"
  APPLE_LANGS='en'
  APPLE_LOCALE='en_US'
fi
export COPAKY_UDID="$UDID"

mkdir -p "$OUT_DIR" "$ART_DIR"
log() { echo "[$(date +%H:%M:%S)] $*"; }
# Signing team: env override, else machine-local xcconfig (see CONTRIBUTING.md)
TEAM="${COPAKY_TEAM:-$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' "$REPO_DIR/Copaky.local.xcconfig" 2>/dev/null | head -n1)}"
if [[ -z "$TEAM" ]]; then
  echo "FATAL: no signing team — set COPAKY_TEAM or create $REPO_DIR/Copaky.local.xcconfig with: DEVELOPMENT_TEAM = <your team id>" >&2
  exit 1
fi
sign_args=(-allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic)

# ---- helpers -------------------------------------------------------------------
boot_wait() {
  local state
  state="$(xcrun simctl list devices | grep "$UDID" | grep -o 'Booted' || true)"
  if [[ "$state" != "Booted" ]]; then
    log "Booting $UDID"
    xcrun simctl boot "$UDID" 2>/dev/null || true
  fi
  xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
}

disable_hw_keyboard() {
  # Ensure the software keyboard shows (a "connected hardware keyboard" would suppress it).
  local plist="$HOME/Library/Preferences/com.apple.iphonesimulator.plist"
  /usr/libexec/PlistBuddy -c "Add :DevicePreferences dict" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :DevicePreferences:$UDID dict" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :DevicePreferences:$UDID:ConnectHardwareKeyboard bool false" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :DevicePreferences:$UDID:ConnectHardwareKeyboard false" "$plist" 2>/dev/null || true
  defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false 2>/dev/null || true
}

container_path() {
  # get_app_container often can't resolve an App-Group container by the extension bundle id
  # on the Simulator, so fall back to scanning the AppGroup metadata plists (same as the seed).
  local c
  c="$(xcrun simctl get_app_container "$UDID" "$KB_BUNDLE" "$GROUP_ID" 2>/dev/null || true)"
  if [[ -n "$c" && -d "$c" ]]; then printf '%s' "$c"; return 0; fi
  c="$(xcrun simctl get_app_container "$UDID" com.pettipol.copaky "$GROUP_ID" 2>/dev/null || true)"
  if [[ -n "$c" && -d "$c" ]]; then printf '%s' "$c"; return 0; fi
  local base="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Shared/AppGroup"
  [[ -d "$base" ]] || return 0
  local meta id
  for meta in "$base"/*/.com.apple.mobile_container_manager.metadata.plist; do
    [[ -f "$meta" ]] || continue
    id="$(/usr/libexec/PlistBuddy -c 'Print :MCMMetadataIdentifier' "$meta" 2>/dev/null || true)"
    if [[ "$id" == "$GROUP_ID" ]]; then printf '%s' "$(dirname "$meta")"; return 0; fi
  done
  return 0
}

status_bar() {
  xcrun simctl status_bar "$UDID" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100 2>/dev/null || true
}

# Navigate Safari to the demo page cleanly (no inter-app breadcrumb).
openurl_clean() {
  xcrun simctl terminate "$UDID" com.apple.Preferences 2>/dev/null || true
  xcrun simctl terminate "$UDID" com.apple.mobilesafari 2>/dev/null || true
  xcrun simctl terminate "$UDID" com.pettipol.copaky 2>/dev/null || true
  status_bar
  xcrun simctl openurl "$UDID" "$DEMO_URL" 2>/dev/null || true
  sleep 6
  status_bar
}

# ---- a. language + reboot ------------------------------------------------------
log "=== lang=$LANG_ARG  demo=$DEMO_URL ==="
boot_wait
disable_hw_keyboard
log "Setting system language ($APPLE_LANGS / $APPLE_LOCALE)"
xcrun simctl spawn "$UDID" defaults write .GlobalPreferences.plist AppleLanguages -array "$APPLE_LANGS" || true
xcrun simctl spawn "$UDID" defaults write .GlobalPreferences.plist AppleLocale -string "$APPLE_LOCALE" || true
log "Rebooting simulator to apply language"
xcrun simctl shutdown "$UDID" 2>/dev/null || true
sleep 3
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
sleep 3

# ---- b. status bar -------------------------------------------------------------
status_bar
log "Status bar overridden"

# ---- c. one-time setup (only if container missing) -----------------------------
CONTAINER="$(container_path)"
if [[ -z "$CONTAINER" || ! -d "$CONTAINER" ]]; then
  log "Container missing → enabling keyboard + Full Access (SIGNED)"
  TEST_RUNNER_COPAKY_DEMO_URL="$DEMO_URL" \
  xcodebuild test \
    -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" "${sign_args[@]}" \
    -only-testing:"$UITEST_BUNDLE/CopakyCampaignTests/test01_enableKeyboardInSettings" \
    -only-testing:"$UITEST_BUNDLE/CopakyCampaignTests/test10_phaseB_enableFullAccess" \
    2>&1 | tail -25 || true

  for attempt in 1 2 3; do
    log "warmup attempt $attempt (create container)"
    openurl_clean
    TEST_RUNNER_COPAKY_DEMO_URL="$DEMO_URL" \
    xcodebuild test \
      -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" "${sign_args[@]}" \
      -only-testing:"$UITEST_BUNDLE/CopakyScreenshotTests/test_shot00_warmup" \
      2>&1 | tail -25 || true
    CONTAINER="$(container_path)"
    if [[ -n "$CONTAINER" && -d "$CONTAINER" ]]; then
      log "Container created: $CONTAINER"
      break
    fi
  done
else
  log "Container already exists: $CONTAINER (skipping setup)"
fi

if [[ -z "$CONTAINER" || ! -d "$CONTAINER" ]]; then
  log "FATAL: container still missing after setup — cannot seed. Aborting."
  exit 1
fi

# ---- d. seed -------------------------------------------------------------------
log "Seeding clipboard container (lang=$LANG_ARG)"
if ! bash "$SEED" --lang "$LANG_ARG" --udid "$UDID"; then
  log "FATAL: clipboard seed failed — stale history from a previous language pass could leak into shot03"
  exit 1
fi

# ---- e. screenshot run ---------------------------------------------------------
XCRESULT="$ART_DIR/$LANG_ARG.xcresult"
rm -rf "$XCRESULT"
# A failed rerun must never leave stale shots from a previous run looking current.
rm -f "$OUT_DIR"/shot0[1-6].png
for i in 1 2 3 4 5 6; do
  if [[ -e "$OUT_DIR/shot0$i.png" ]]; then
    log "FATAL: could not clear stale $OUT_DIR/shot0$i.png"
    exit 1
  fi
done
openurl_clean
log "Running screenshot suite (SIGNED)"
XCB_STATUS=0
TEST_RUNNER_COPAKY_DEMO_URL="$DEMO_URL" \
TEST_RUNNER_COPAKY_CLIPBOARD_CANARY="482913" \
xcodebuild test \
  -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" "${sign_args[@]}" \
  -resultBundlePath "$XCRESULT" \
  -only-testing:"$UITEST_BUNDLE/CopakyScreenshotTests/test_shot01_hero" \
  -only-testing:"$UITEST_BUNDLE/CopakyScreenshotTests/test_shot02_conversion" \
  -only-testing:"$UITEST_BUNDLE/CopakyScreenshotTests/test_shot03_clipboard" \
  -only-testing:"$UITEST_BUNDLE/CopakyScreenshotTests/test_shot04_privacy" \
  -only-testing:"$UITEST_BUNDLE/CopakyScreenshotTests/test_shot05_themes" \
  -only-testing:"$UITEST_BUNDLE/CopakyScreenshotTests/test_shot06_english" \
  2>&1 | tail -60 || XCB_STATUS=$?
# Keep going even on failure: export whatever the xcresult holds for debugging,
# but the final gate below fails the script.

# ---- export attachments → PNGs -------------------------------------------------
EXPORT_DIR="$ART_DIR/${LANG_ARG}_attachments"
rm -rf "$EXPORT_DIR"
if [[ ! -d "$XCRESULT" ]]; then
  log "FATAL: no xcresult produced ($XCRESULT)"
  exit 1
fi
log "Exporting attachments"
if ! xcrun xcresulttool export attachments --path "$XCRESULT" --output-path "$EXPORT_DIR" >/dev/null 2>&1; then
  log "FATAL: attachment export failed ($XCRESULT)"
  exit 1
fi

COPAKY_EXPORT_DIR="$EXPORT_DIR" COPAKY_OUT_DIR="$OUT_DIR" /usr/bin/python3 - <<'PY'
import json, os, re, shutil
export_dir = os.environ["COPAKY_EXPORT_DIR"]
out_dir = os.environ["COPAKY_OUT_DIR"]
manifest = os.path.join(export_dir, "manifest.json")
wanted = [f"shot0{i}" for i in range(1, 7)]
# suggestedHumanReadableName looks like 'shot01_0_<uuid>.png' → match by prefix.
best = {}   # shotName -> (timestamp, exportedFileName)
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
        dst = os.path.join(out_dir, shot + ".png")
        if fn and os.path.exists(src):
            shutil.copyfile(src, dst)
            print("mapped", shot, "->", dst)
missing = [s for s in wanted if s not in best]
if missing:
    print("MISSING:", ", ".join(missing))
PY
if [[ $? -ne 0 ]]; then
  log "FATAL: attachment mapping failed (python)"
  exit 1
fi

# ---- f. flatten (strip alpha) + verify dims (hard gate) -------------------------
log "Flattening + verifying PNGs"
GATE_FAIL=0
for i in 1 2 3 4 5 6; do
  P="$OUT_DIR/shot0$i.png"
  if [[ ! -f "$P" ]]; then
    log "shot0$i: MISSING"
    GATE_FAIL=1
    continue
  fi
  HAS_ALPHA="$(sips -g hasAlpha "$P" 2>/dev/null | awk '/hasAlpha/{print $2}')"
  if [[ "$HAS_ALPHA" == "yes" ]]; then
    TMPBMP="$OUT_DIR/.shot0$i.bmp"
    sips -s format bmp "$P" --out "$TMPBMP" >/dev/null 2>&1
    sips -s format png "$TMPBMP" --out "$P" >/dev/null 2>&1
    rm -f "$TMPBMP"
  fi
  W="$(sips -g pixelWidth  "$P" 2>/dev/null | awk '/pixelWidth/{print $2}')"
  H="$(sips -g pixelHeight "$P" 2>/dev/null | awk '/pixelHeight/{print $2}')"
  A="$(sips -g hasAlpha    "$P" 2>/dev/null | awk '/hasAlpha/{print $2}')"
  log "shot0$i: ${W}x${H} hasAlpha=${A}"
  if [[ "$W" != "$EXPECTED_W" || "$H" != "$EXPECTED_H" || "$A" != "no" ]]; then
    log "shot0$i: FAIL (expected ${EXPECTED_W}x${EXPECTED_H} hasAlpha=no)"
    GATE_FAIL=1
  fi
done

if [[ "$XCB_STATUS" -ne 0 ]]; then
  log "FATAL: screenshot suite exited with status $XCB_STATUS — do not trust this set"
  exit 1
fi
if [[ "$GATE_FAIL" -ne 0 ]]; then
  log "FATAL: output gate failed — missing/wrong-size/alpha screenshots (see above)"
  exit 1
fi

log "=== DONE lang=$LANG_ARG → $OUT_DIR (6/6 fresh, ${EXPECTED_W}x${EXPECTED_H}, no alpha) ==="
