#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--fresh-install] [--seed k=v]... [--seed-clipboard en|ja|it] [--pbseed-bytes N] TEST" >&2
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

FRESH_INSTALL=0
CLIPBOARD_LANG=""
PBSEED_BYTES=""
TEST=""
SEEDS=(
  keyboard_type=flick
  keyboard_type_en=roman
  enable_qwerty_number_row_hints=true
  enable_qwerty_number_row=false
  enable_space_slide_cursor=false
  enable_italian_keyboard_language=true
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fresh-install)
      FRESH_INSTALL=1
      shift
      ;;
    --seed)
      [[ $# -ge 2 ]] || die "--seed requires key=value"
      [[ "$2" == *=* && -n "${2%%=*}" ]] || die "invalid --seed '$2' (expected key=value)"
      SEEDS+=("$2")
      shift 2
      ;;
    --seed-clipboard)
      [[ $# -ge 2 ]] || die "--seed-clipboard requires en, ja or it"
      CLIPBOARD_LANG="$2"
      shift 2
      ;;
    --pbseed-bytes)
      [[ $# -ge 2 ]] || die "--pbseed-bytes requires a non-negative integer"
      PBSEED_BYTES="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      die "unknown option '$1'"
      ;;
    *)
      [[ -z "$TEST" ]] || die "pass exactly one test method"
      TEST="$1"
      shift
      ;;
  esac
done

[[ -n "$TEST" ]] || { usage; exit 2; }
[[ "$TEST" != */* ]] || die "pass the bare CopakyCampaignTests method name"
[[ -z "$CLIPBOARD_LANG" || "$CLIPBOARD_LANG" == "en" || "$CLIPBOARD_LANG" == "ja" || "$CLIPBOARD_LANG" == "it" ]] \
  || die "--seed-clipboard must be en, ja or it"
[[ -z "$PBSEED_BYTES" || "$PBSEED_BYTES" =~ ^[0-9]+$ ]] \
  || die "--pbseed-bytes must be a non-negative integer"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UDID="${COPAKY_UDID:-E0552C62-FFDB-4DF6-9040-2734DB5B2458}"
PROJECT="$REPO_DIR/azooKey.xcodeproj"
TEST_ID="azooKeyUITests/CopakyCampaignTests/$TEST"
CONFIGURATION="${COPAKY_CONFIGURATION:-Debug}"
DERIVED_DATA="${COPAKY_DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData/CopakySingleUITest}"
APP_BUNDLE="com.pettipol.copaky"
KB_BUNDLE="com.pettipol.copaky.keyboard"
RUNNER_BUNDLE="com.pettipol.copaky.uitests.xctrunner"
FIELDS_URL="http://127.0.0.1:8377/kbtest.html"
XCB_ARGS=(
  -project "$PROJECT"
  -scheme CopakyUITests
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA"
  -destination "id=$UDID"
  -only-testing:"$TEST_ID"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
)

# The requested UDID must be booted in a visible Simulator session.
open -a Simulator
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

# Field tests need the local fixture; iOS 26 ignores Safari's -u launch argument.
bash "$REPO_DIR/scripts/serve_test_page.sh" --daemon

# Build the UI runner once; --fresh-install separately rebuilds/signs only the host app below.
xcodebuild build-for-testing "${XCB_ARGS[@]}"

if [[ "$FRESH_INSTALL" == 1 ]]; then
  # App Group creation requires a signed host app; the UI runner itself remains unsigned below.
  TEAM="${COPAKY_TEAM:-$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' "$REPO_DIR/Copaky.local.xcconfig" 2>/dev/null | sed -n '1p' || true)}"
  [[ -n "$TEAM" ]] || die "--fresh-install requires COPAKY_TEAM or Copaky.local.xcconfig"
  xcodebuild build \
    -project "$PROJECT" -scheme MainApp -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" -destination "id=$UDID" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic

  # Xcode can retain an unchanged installed app, so install and launch this exact build explicitly.
  FRESH_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphonesimulator/azooKey.app"
  FRESH_KEYBOARD="$FRESH_APP/PlugIns/Keyboard.appex"
  [[ -d "$FRESH_APP" ]] || die "fresh azooKey.app not found at $FRESH_APP"
  [[ -d "$FRESH_KEYBOARD" ]] || die "fresh Keyboard.appex not found at $FRESH_KEYBOARD"
  xcrun simctl terminate "$UDID" "$APP_BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$FRESH_APP"
  xcrun simctl launch "$UDID" "$APP_BUNDLE" >/dev/null
  sleep 2
  xcrun simctl terminate "$UDID" "$APP_BUNDLE" >/dev/null 2>&1 || true
  # Simulator products sign ad-hoc ("Sign to Run Locally"): the App Group lives in the
  # linker-embedded Simulated.xcent, NOT in the codesign signature — a codesign entitlements
  # query is EMPTY here even while the group works (measured 2026-08-27). The honest
  # fail-closed gate is behavioural: after install+launch the container must exist.
  CONTAINER_CHECK="$(xcrun simctl get_app_container "$UDID" "$APP_BUNDLE" group.com.pettipol.copaky 2>/dev/null || true)"
  [[ -n "$CONTAINER_CHECK" && -d "$CONTAINER_CHECK" ]] \
    || die "App Group container missing after fresh install+launch (group.com.pettipol.copaky)"
fi

if [[ -n "$CLIPBOARD_LANG" ]]; then
  # Clipboard tab/history seeding requires the App Group container created by a prior app launch.
  bash "$REPO_DIR/scripts/seed_sim_clipboard.sh" --lang "$CLIPBOARD_LANG" --udid "$UDID"
fi

# Apply campaign defaults and user --seed overrides last, after clipboard seeding's roman-layout write.
# A fresh signed install must expose its App Group container; fail closed if that mirror is absent.
COPAKY_SEED_REQUIRE_CONTAINER="$FRESH_INSTALL" \
  bash "$REPO_DIR/scripts/seed_sim_settings.sh" --udid "$UDID" --keep-keyboard "${SEEDS[@]}"

# 20th session, measured: on a container created moments earlier the direct plist writes can lose
# against a cfprefsd cache flush on the app's next launch — mirror read-back said OK, yet at test
# time keyboard_type_en was gone and English fell back to flick (the E-14 trap on fresh containers).
# The race never reproduced on a warm domain, so: warm the domain with one app launch, then verify
# every seeded key is still there; one re-seed heals a lost write, a second loss is a hard failure.
if [[ "$FRESH_INSTALL" == 1 ]]; then
  SHARED_PLIST="$(xcrun simctl get_app_container "$UDID" "$APP_BUNDLE" group.com.pettipol.copaky 2>/dev/null || true)/Library/Preferences/group.com.pettipol.copaky.plist"
  for attempt in 1 2; do
    xcrun simctl launch "$UDID" "$APP_BUNDLE" >/dev/null 2>&1
    sleep 2
    xcrun simctl terminate "$UDID" "$APP_BUNDLE" >/dev/null 2>&1 || true
    SEEDS_LOST=0
    for pair in "${SEEDS[@]}"; do
      key="${pair%%=*}"
      /usr/libexec/PlistBuddy -c "Print :$key" "$SHARED_PLIST" >/dev/null 2>&1 || { SEEDS_LOST=1; echo "seed lost after app launch: $key" >&2; }
    done
    [[ "$SEEDS_LOST" == 0 ]] && break
    [[ "$attempt" == 2 ]] && die "seeded keys vanished from the shared App Group container twice — aborting instead of testing an unseeded state"
    echo "re-seeding the shared container once (cfprefsd race on fresh container)" >&2
    COPAKY_SEED_REQUIRE_CONTAINER=1 \
      bash "$REPO_DIR/scripts/seed_sim_settings.sh" --udid "$UDID" --keep-keyboard "${SEEDS[@]}"
  done
fi

unset TEST_RUNNER_COPAKY_PASTEBOARD_PRESEEDED || true
if [[ -n "$PBSEED_BYTES" ]]; then
  # Seed simulator-wide pasteboard; TEST_RUNNER_ forwards provenance into XCUITest.
  /usr/bin/python3 -c 'import sys; sys.stdout.write("COPAKY_OVERSIZED_SEED_" + "X" * int(sys.argv[1]))' "$PBSEED_BYTES" \
    | xcrun simctl pbcopy "$UDID"
  export TEST_RUNNER_COPAKY_PASTEBOARD_PRESEEDED=1
fi

# The extension snapshots settings and tab state at process launch, so kill it after all seeding.
pkill -f "$UDID.*azooKey.app/PlugIns/Keyboard.appex/Keyboard" 2>/dev/null \
  || xcrun simctl terminate "$UDID" "$KB_BUNDLE" >/dev/null 2>&1 \
  || true

# Safari must already display the fixture before tests call activate() on iOS 26.
xcrun simctl openurl "$UDID" "$FIELDS_URL"

# The installed xctrunner has repeatedly lagged one source build behind.
xcrun simctl uninstall "$UDID" "$RUNNER_BUNDLE" >/dev/null 2>&1 || true

xcodebuild test-without-building "${XCB_ARGS[@]}"
