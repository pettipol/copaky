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
USER_SEEDS=()
DELETE_KEYS=()
AUTO_CLIPBOARD_SEED=0
CLIPBOARD_PRESEEDED=0
SEEDS=(
  keyboard_type=flick
  keyboard_type_en=roman
  enable_qwerty_number_row_hints=true
  enable_qwerty_number_row=false
  enable_space_slide_cursor=false
  space_slide_cursor_sensitivity=medium
  # Copaky [F-04b]: auto-capitalization arms Shift at sentence start, turning key labels
  # uppercase — every lowercase key lookup in the campaign would break. Pin it OFF for the
  # harness; the feature is covered by its unit contracts and by the manual device round.
  # Copaky [F-04b]: 自動大文字化は文頭でShiftを立てラベルが大文字になるため、ハーネスではOFFに固定。
  enable_latin_auto_capitalization=false
  enable_italian_keyboard_language=true
  # Copaky [G-01]: campaign tests use the new Apple-like Shift default unless an historical
  # geometry test pins the previous no-Shift baseline below.
  use_shift_key=true
  # Copaky [F-05] (05/09): mirror the product default explicitly, so a value pinned by one test never
  # leaks into the next run (the device-wide plist survives reinstalls).
  hide_empty_candidate_bar_on_latin=true
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
      USER_SEEDS+=("$2")
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

# Copaky [F-09]: test47's drag distances are calibrated on the SLOW (1.0x key width) threshold.
# The product default is now medium (0.7x), so the test pins slow here — an explicit --seed
# space_slide_cursor_sensitivity=... still wins because user seeds are appended last.
# Copaky [F-09]: test47のドラッグ距離はslow(1.0倍)前提。既定がmediumになったためここでslowを
# 固定する。--seed の明示指定は後勝ちで常に優先される。
if [[ "$TEST" == "test47_spaceSlideCursorOnLatinQwerty" ]]; then
  SEEDS+=(space_slide_cursor_sensitivity=slow)
fi
# Copaky [F-05]: tests 39/46/47 predate the empty-Latin-bar default and either exercise the
# open tab bar or compare geometry calibrated with that row reserved. Pin their historical baseline;
# test48 instead pins the new default before changing it through the real MainApp toggle.
# Copaky [F-05]: test39/46/47は空バーを確保した従来基準で固定し、test48は新しい既定値から開始する。
case "$TEST" in
  test30_accentVariationsOnLongPress|test39_longPressNumbersKeyOpensClipboardHistory|test46_realQwertyNumberRowPreservesLetterHeights|test47_spaceSlideCursorOnLatinQwerty)
    # Copaky (05/09): test30's accent-popup drag is calibrated with the empty bar VISIBLE (row 1 not at the
    # very top of the inputView) — pin its historical baseline like the geometry tests.
    SEEDS+=(hide_empty_candidate_bar_on_latin=false)
    ;;
  test48_hiddenCandidateBarReducesHeight)
    SEEDS+=(hide_empty_candidate_bar_on_latin=true display_tab_bar_button=false)
    ;;
  test49_appleLatinBottomRowGeometryAndImageAccessibility)
    SEEDS+=(hide_empty_candidate_bar_on_latin=true display_tab_bar_button=false use_shift_key=false)
    ;;
  test50_accessibilityAudit_settingsScreens)
    SEEDS+=(use_shift_key=false)
    ;;
esac
case "$TEST" in
  test52_shiftKeyCycleAndCapsLock)
    SEEDS+=(use_shift_key=true keep_deprecated_shift_key_behavior=false hide_empty_candidate_bar_on_latin=true display_tab_bar_button=false enable_latin_auto_capitalization=false)
    ;;
  test54_languageKeyMenuOpensCopakySettings)
    SEEDS+=(keyboard_type_en=roman enable_italian_keyboard_language=true)
    ;;
  test55_flickStar123LongPressOpensClipboardHistory)
    SEEDS+=(keyboard_type=flick enable_clipboard_history_manager_tab=true use_system_paste_control=false display_tab_bar_button=true)
    # Copaky [G-04]: remove the previously persisted Data array so the product's new default is tested.
    DELETE_KEYS+=(clipboard_long_press_slots)
    if [[ -z "$CLIPBOARD_LANG" ]]; then
      # Seed onEnabled's tab-bar side effect when a signed App Group container is available. If the
      # prerequisite container is absent, the UI test retains test39's explicit XCTSkip path.
      CLIPBOARD_LANG=it
      AUTO_CLIPBOARD_SEED=1
    fi
    ;;
  test58_numberRowDigitLongPressVariations)
    SEEDS+=(enable_qwerty_number_row=true enable_qwerty_number_row_hints=false hide_empty_candidate_bar_on_latin=false use_shift_key=true)
    ;;
esac
if [[ "$TEST" == "test39_longPressNumbersKeyOpensClipboardHistory" ]]; then
  # The historical test explicitly exercises the open tab bar; Copaky's product default is OFF.
  SEEDS+=(display_tab_bar_button=true use_shift_key=false)
fi
SEEDS+=(${USER_SEEDS[@]+"${USER_SEEDS[@]}"})
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
# Copaky (05/09): the host app product must ALWAYS carry the App Group entitlement. An unsigned
# build-for-testing (CODE_SIGNING_ALLOWED=NO) re-links azooKey.app without its Simulated.xcent and
# test-without-building then reinstalls it over the signed app: containermanagerd drops the group
# ("Reconciled [com.pettipol.copaky] … new app groups: (null)") and the keyboard logs "client is not
# entitled" — every clipboard test that followed a --fresh-install failed that way (24th session, round
# 10: test14 no tile, test13 seed without container). With a team available the whole scheme is signed
# ad hoc for the simulator (no profile needed), so every reinstall keeps the group.
# 署名なしビルドで再インストールするとApp Groupが消えるため、チームがあれば常に署名付きでビルドする。
TEAM="${COPAKY_TEAM:-$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' "$REPO_DIR/Copaky.local.xcconfig" 2>/dev/null | sed -n '1p' || true)}"
if [[ -n "$TEAM" ]]; then
  SIGNING_ARGS=(-allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic)
else
  echo "warning: no DEVELOPMENT_TEAM (COPAKY_TEAM or Copaky.local.xcconfig): building unsigned — the App Group container will be absent and clipboard tests cannot pass" >&2
  SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi
XCB_ARGS=(
  -project "$PROJECT"
  -scheme CopakyUITests
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA"
  -destination "id=$UDID"
  -only-testing:"$TEST_ID"
  "${SIGNING_ARGS[@]}"
)

# The requested UDID must be booted in a visible Simulator session.
# Xcode 27 ships no Simulator.app: DeviceHub hosts the simulator windows. Override with COPAKY_SIMULATOR_APP.
# Xcode 27 には Simulator.app が無く DeviceHub が代替。COPAKY_SIMULATOR_APP で上書き可。
SIM_APP="${COPAKY_SIMULATOR_APP:-Simulator}"
open -a "$SIM_APP" 2>/dev/null || open -a DeviceHub 2>/dev/null || echo "⚠ no simulator host app found (tried $SIM_APP, DeviceHub)" >&2
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

# Without Simulator.app nobody detaches the simulated hardware keyboard, and iOS parks the software
# keyboard below the screen (only the accessory bar shows, no globe key). Detach it explicitly through
# the SimulatorKit private API wrapped by scripts/sim_hw_keyboard.m (compiled on first use).
# Simulator.app が無いと仮想ハードウェアキーボードが接続されたままになり、ソフトウェアキーボードが画面外に退避する。
# scripts/sim_hw_keyboard.m（初回にコンパイル）で明示的に切断する。
HWKB_BIN="${COPAKY_HWKB_BIN:-$HOME/Library/Developer/Xcode/DerivedData/CopakySingleUITest/sim_hw_keyboard}"
if [[ ! -x "$HWKB_BIN" || "$REPO_DIR/scripts/sim_hw_keyboard.m" -nt "$HWKB_BIN" ]]; then
  mkdir -p "$(dirname "$HWKB_BIN")"
  clang -fobjc-arc -framework Foundation "$REPO_DIR/scripts/sim_hw_keyboard.m" -o "$HWKB_BIN" \
    || echo "⚠ could not build sim_hw_keyboard (hardware keyboard may stay attached)" >&2
fi
[[ -x "$HWKB_BIN" ]] && "$HWKB_BIN" "$UDID" off

# Field tests need the local fixture; iOS 26 ignores Safari's -u launch argument.
bash "$REPO_DIR/scripts/serve_test_page.sh" --daemon

# Build the UI runner (and the signed host app) once; --fresh-install re-installs that host app below.
xcodebuild build-for-testing "${XCB_ARGS[@]}"

if [[ "$FRESH_INSTALL" == 1 ]]; then
  # App Group creation requires a signed host app: same signing settings as the runner build above,
  # so this explicit build is a no-op re-check, never a re-link with different entitlements.
  [[ -n "$TEAM" ]] || die "--fresh-install requires COPAKY_TEAM or Copaky.local.xcconfig"
  xcodebuild build \
    -project "$PROJECT" -scheme MainApp -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" -destination "id=$UDID" \
    "${SIGNING_ARGS[@]}"

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
  if [[ "$AUTO_CLIPBOARD_SEED" == 1 ]]; then
    if CLIPBOARD_SEED_OUTPUT="$(bash "$REPO_DIR/scripts/seed_sim_clipboard.sh" --lang "$CLIPBOARD_LANG" --udid "$UDID" 2>&1)"; then
      printf '%s\n' "$CLIPBOARD_SEED_OUTPUT"
      CLIPBOARD_PRESEEDED=1
    elif [[ "$CLIPBOARD_SEED_OUTPUT" == *"App Group container 'group.com.pettipol.copaky' not found"* ]]; then
      printf '%s\n' "$CLIPBOARD_SEED_OUTPUT" >&2
      echo "warning: test55 App Group prerequisite unavailable; the UI test will apply its explicit skip gate" >&2
    else
      printf '%s\n' "$CLIPBOARD_SEED_OUTPUT" >&2
      die "test55 clipboard seeding failed for a reason other than the allowed missing-App-Group prerequisite"
    fi
  else
    bash "$REPO_DIR/scripts/seed_sim_clipboard.sh" --lang "$CLIPBOARD_LANG" --udid "$UDID"
    CLIPBOARD_PRESEEDED=1
  fi
fi

# Apply campaign defaults and user --seed overrides last, after clipboard seeding's roman-layout write.
# A fresh signed install must expose its App Group container; fail closed if that mirror is absent.
SEED_SCRIPT_ARGS=(--udid "$UDID" --keep-keyboard)
for key in ${DELETE_KEYS[@]+"${DELETE_KEYS[@]}"}; do
  SEED_SCRIPT_ARGS+=(--delete "$key")
done
SEED_SCRIPT_ARGS+=("${SEEDS[@]}")
COPAKY_SEED_REQUIRE_CONTAINER="$FRESH_INSTALL" \
  bash "$REPO_DIR/scripts/seed_sim_settings.sh" "${SEED_SCRIPT_ARGS[@]}"

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
    for key in ${DELETE_KEYS[@]+"${DELETE_KEYS[@]}"}; do
      /usr/libexec/PlistBuddy -c "Print :$key" "$SHARED_PLIST" >/dev/null 2>&1 \
        && { SEEDS_LOST=1; echo "deleted key returned after app launch: $key" >&2; }
    done
    [[ "$SEEDS_LOST" == 0 ]] && break
    [[ "$attempt" == 2 ]] && die "seeded keys vanished from the shared App Group container twice — aborting instead of testing an unseeded state"
    echo "re-seeding the shared container once (cfprefsd race on fresh container)" >&2
    COPAKY_SEED_REQUIRE_CONTAINER=1 \
      bash "$REPO_DIR/scripts/seed_sim_settings.sh" "${SEED_SCRIPT_ARGS[@]}"
  done
fi

unset TEST_RUNNER_COPAKY_PASTEBOARD_PRESEEDED || true
unset TEST_RUNNER_COPAKY_CLIPBOARD_PRESEEDED || true
if [[ "$CLIPBOARD_PRESEEDED" == 1 ]]; then
  # Once the real tab/history seed succeeded, a missing Clipboard tab is a regression, not a skip.
  export TEST_RUNNER_COPAKY_CLIPBOARD_PRESEEDED=1
fi
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
