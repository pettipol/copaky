#!/usr/bin/env bash
# run_device_test.sh — variante di run_ui_test.sh per iPhone reale (BACKLOG H-12).
# Copre la parte che il Simulatore non può, per costruzione, riprodurre (docs/UI_TESTING_PLAYBOOK.md
# §7/§8): dialogo pasteboard reale, permessi App Group reali, memoria di picco reale. NON seeda le
# impostazioni via plist diretto (l'App Group reale non è scrivibile da fuori l'app): i seed vanno
# passati via launchEnvironment/UI del test, come per ogni test già scritto per il device.
# 実機用のrun_ui_test.sh相当（H-12）。プリスト直書きでの設定シードは不可（実App Groupは外部から
# 書けない）：シードはlaunchEnvironment/UI操作で渡すこと。
#
# Usage:
#   scripts/run_device_test.sh [--udid <UDID>] [--configuration Release|Debug] [--out <dir>] \
#     [--dry-run] [--preflight] [--skip-build] TEST [TEST...]
set -uo pipefail

usage() {
  echo "Usage: $0 [--udid <UDID>] [--configuration Release|Debug] [--out <dir>] [--dry-run] [--preflight] [--skip-build] TEST [TEST...]" >&2
}

die() {
  echo "✘ $*" >&2
  exit 2
}

DRY_RUN=0
PREFLIGHT=0
SKIP_BUILD=0
UDID="${COPAKY_DEVICE_ID:-}"
CONFIGURATION="Debug"
OUT_DIR=""
TESTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid) [[ $# -ge 2 ]] || die "--udid requires a value"; UDID="$2"; shift 2 ;;
    --configuration) [[ $# -ge 2 ]] || die "--configuration requires Release or Debug"; CONFIGURATION="$2"; shift 2 ;;
    --out) [[ $# -ge 2 ]] || die "--out requires a directory"; OUT_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --preflight) PREFLIGHT=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) die "unknown option '$1'" ;;
    *) TESTS+=("$1"); shift ;;
  esac
done

[[ "$CONFIGURATION" == "Debug" || "$CONFIGURATION" == "Release" ]] || die "--configuration must be Release or Debug"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_DIR/azooKey.xcodeproj"
SCHEME="CopakyUITests"
UITEST_BUNDLE="azooKeyUITests"
DERIVED_DATA="${COPAKY_DEVICE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/CopakyDeviceUITest}"
OUT_DIR="${OUT_DIR:-$HOME/copaky_device_logs}"
RUNNER_BUNDLE="com.pettipol.copaky.uitests.xctrunner"

log() { echo "[$(date +%H:%M:%S)] $*"; }
run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

# ---- team (stesso meccanismo di run_ui_test.sh: Copaky.local.xcconfig o COPAKY_TEAM) --------------
TEAM="${COPAKY_TEAM:-$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' "$REPO_DIR/Copaky.local.xcconfig" 2>/dev/null | sed -n '1p' || true)}"

# ---- toolchain check (sempre, anche in --dry-run) --------------------------------------------------
check_tool() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    echo "✓ $name presente"
    return 0
  else
    echo "✘ $name assente"
    return 1
  fi
}

# ---- perimetro di supporto Xcode → iOS device, dedotto da `xcodebuild -version` --------------------
xcode_ios_range() {
  local xcode_ver major
  xcode_ver="$(xcodebuild -version 2>/dev/null | sed -n '1p' | awk '{print $2}')"
  major="${xcode_ver%%.*}"
  case "$major" in
    27) echo "17-27" ;;
    26) echo "15-26.5" ;;
    *) echo "" ;;   # perimetro non tabulato per questa versione: niente verdetto automatico
  esac
}

ios_in_range() {
  local ios="$1" range="$2" lo hi
  [[ -n "$range" ]] || return 2
  lo="${range%-*}"; hi="${range#*-}"
  python3 -c '
import sys
def v(s):
    parts = [int(x) for x in s.split(".")]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts)
ios, lo, hi = sys.argv[1], sys.argv[2], sys.argv[3]
sys.exit(0 if v(lo) <= v(ios) <= v(hi) else 1)
' "$ios" "$lo" "$hi"
}

# ---- preflight: device fisici noti a devicectl, versione iOS, confronto col perimetro Xcode -------
do_preflight() {
  echo "-- preflight device --"
  check_tool xcrun || true
  if xcrun --find xcresulttool >/dev/null 2>&1; then echo "✓ xcrun xcresulttool disponibile"; else echo "✘ xcrun xcresulttool assente"; fi
  if command -v pymobiledevice3 >/dev/null 2>&1; then echo "✓ pymobiledevice3 presente"; else echo "✘ pymobiledevice3 assente (nessuna cattura syslog)"; fi
  echo

  local xcode_ver range
  xcode_ver="$(xcodebuild -version 2>/dev/null | sed -n '1p')"
  range="$(xcode_ios_range)"
  echo "toolchain: $xcode_ver — perimetro device dichiarato: ${range:-non tabulato}"
  echo

  local list_json
  list_json="$(xcrun devicectl list devices --json-output - 2>/dev/null)"
  if [[ -z "$list_json" ]]; then
    echo "✘ 'xcrun devicectl list devices' non ha risposto"
    [[ "$DRY_RUN" == 1 ]] && return 0
    return 2
  fi

  # Solo device fisici iOS (esclude Simulatore e Apple Watch), con la loro versione se disponibile.
  local phys_tsv
  phys_tsv="$(echo "$list_json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for dev in d.get("result", {}).get("devices", []):
    hp = dev.get("hardwareProperties", {})
    if hp.get("platform") != "iOS" or hp.get("deviceType") != "iPhone":
        continue
    if dev.get("visibilityClass") == "simulators":
        continue
    dp = dev.get("deviceProperties", {})
    cp = dev.get("connectionProperties", {})
    name = dp.get("name", "?")
    udid = hp.get("udid", dev.get("identifier", "?"))
    state = cp.get("tunnelState", "?") + "/" + cp.get("pairingState", "?")
    ios = dp.get("osVersionNumber", "")
    print("\t".join([name, udid, state, ios]))
')"

  if [[ -z "$phys_tsv" ]]; then
    echo "✘ nessun device fisico noto a devicectl"
    [[ "$DRY_RUN" == 1 ]] && return 0
    return 2
  fi

  local any_connected=0
  while IFS=$'\t' read -r name udid state ios; do
    [[ -z "$name" ]] && continue
    echo "device: $name — $udid — stato $state — iOS ${ios:-sconosciuta}"
    [[ "$state" == connected/* ]] && any_connected=1
    if [[ -n "$ios" ]]; then
      if ios_in_range "$ios" "$range"; then
        echo "  ✓ versione iOS entro il perimetro dichiarato per $xcode_ver ($range)"
      else
        echo "  ✘ versione iOS FUORI dal perimetro dichiarato per $xcode_ver ($range)"
      fi
    else
      # xcrun devicectl device info details espone osVersionNumber/productVersion più affidabilmente
      # per i device solo appaiati (non connessi ora): tentativo aggiuntivo, mai fatale.
      local details ios2
      details="$(xcrun devicectl device info details --device "$udid" --json-output - 2>/dev/null || true)"
      ios2="$(echo "$details" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
props = d.get("result", {})
v = props.get("deviceProperties", {}).get("osVersionNumber") or props.get("osVersionNumber")
if v:
    print(v)
' 2>/dev/null || true)"
      if [[ -n "$ios2" ]]; then
        echo "  iOS (da device info details): $ios2"
        if ios_in_range "$ios2" "$range"; then
          echo "  ✓ versione iOS entro il perimetro dichiarato per $xcode_ver ($range)"
        else
          echo "  ✘ versione iOS FUORI dal perimetro dichiarato per $xcode_ver ($range)"
        fi
      else
        echo "  versione iOS non leggibile (device non raggiungibile ora)"
      fi
    fi
  done <<< "$phys_tsv"

  if [[ "$any_connected" == 0 ]]; then
    echo
    echo "✘ nessun device fisico raggiungibile ora (tunnel CoreDevice non attivo)"
    [[ "$DRY_RUN" == 1 ]] && return 0
    return 2
  fi
  return 0
}

if [[ "$PREFLIGHT" == 1 ]]; then
  if [[ "$DRY_RUN" == 1 ]]; then
    do_preflight
    [[ ${#TESTS[@]} -eq 0 ]] && exit 0
  else
    do_preflight
    rc=$?
    if [[ $rc -ne 0 ]]; then
      echo "✘ nessun device fisico" >&2
      exit 2
    fi
    [[ ${#TESTS[@]} -eq 0 ]] && exit 0
  fi
fi

[[ ${#TESTS[@]} -gt 0 ]] || { usage; exit 2; }

if [[ "$DRY_RUN" == 1 ]]; then
  echo "-- dry-run: toolchain --"
  check_tool xcrun || true
  if xcrun --find xcresulttool >/dev/null 2>&1; then echo "✓ xcrun xcresulttool disponibile"; else echo "✘ xcrun xcresulttool assente"; fi
  if command -v pymobiledevice3 >/dev/null 2>&1; then echo "✓ pymobiledevice3 presente"; else echo "✘ pymobiledevice3 assente (nessuna cattura syslog)"; fi
  echo
fi

[[ -n "$UDID" ]] || [[ "$DRY_RUN" == 1 ]] || die "--udid mancante (o COPAKY_DEVICE_ID) — usa --preflight per elencare i device noti"
UDID="${UDID:-<UDID>}"

if [[ -n "$TEAM" ]]; then
  echo "team: $TEAM"
else
  [[ "$DRY_RUN" == 1 ]] || die "nessun DEVELOPMENT_TEAM (COPAKY_TEAM o Copaky.local.xcconfig) — la firma è OBBLIGATORIA su device"
  echo "warning: nessun DEVELOPMENT_TEAM — in esecuzione reale questo sarebbe un errore fatale (firma obbligatoria su device)"
fi

mkdir -p "$OUT_DIR" 2>/dev/null || true

BUILD_ARGS=(
  build-for-testing
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "id=$UDID"
  -derivedDataPath "$DERIVED_DATA"
  DEVELOPMENT_TEAM="${TEAM:-<TEAM>}"
  -allowProvisioningUpdates
)

if [[ "$SKIP_BUILD" == 1 ]]; then
  log "--skip-build: salto build-for-testing"
else
  log "build-for-testing (configuration=$CONFIGURATION)"
  # Copaky [F07]: senza controllo esplicito dell'exit code lo script proseguiva anche a build fallita,
  # bastava un azooKey.app residuo di una build precedente perché il controllo su APP_PATH passasse.
  # Copaky [F07]: 明示的なexit code確認が無いとビルド失敗後もスクリプトが続行し、以前のビルドの
  # azooKey.appが残っているだけでAPP_PATHの確認を通過してしまっていた。
  run xcodebuild "${BUILD_ARGS[@]}" || die "build-for-testing fallita (xcodebuild exit $?)"
fi

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos/azooKey.app"
if [[ "$DRY_RUN" == 0 && "$SKIP_BUILD" == 0 ]]; then
  [[ -d "$APP_PATH" ]] || die "azooKey.app non trovato in $APP_PATH dopo build-for-testing"
fi

for TEST in "${TESTS[@]}"; do
  TEST_ID="$UITEST_BUNDLE/CopakyCampaignTests/$TEST"
  log "runner stantio: disinstallo $RUNNER_BUNDLE da $UDID"
  run xcrun devicectl device uninstall app --device "$UDID" "$RUNNER_BUNDLE"

  log "installo azooKey.app da DerivedData su $UDID"
  run xcrun devicectl device install app --device "$UDID" "$APP_PATH" || die "$TEST: installazione fallita (devicectl exit $?)"

  log "termino il processo dell'estensione tastiera se presente (no-op se assente)"
  # `devicectl device process` NON ha un sottocomando `list` (solo awaitTermination/launch/openURL/
  # resume/sendMemoryWarning/signal/suspend/terminate — verificato con --help): il PID va cercato con
  # pymobiledevice3, se disponibile.
  if command -v pymobiledevice3 >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == 1 ]]; then
      echo "[dry-run] pymobiledevice3 processes pgrep Keyboard --udid $UDID → xcrun devicectl device process terminate --device $UDID --pid <pid>"
    else
      for kpid in $(pymobiledevice3 processes pgrep Keyboard --udid "$UDID" 2>/dev/null | awk '$1 ~ /^[0-9]+$/ {print $1}'); do
        log "termino il processo Keyboard stantio pid $kpid"
        xcrun devicectl device process terminate --device "$UDID" --pid "$kpid" >/dev/null 2>&1 || true
      done
    fi
  else
    echo "warning: terminazione dell'estensione non disponibile senza pymobiledevice3: la reinstallazione dell'app la termina comunque" >&2
  fi

  echo "warning: il seed delle impostazioni via plist diretto NON è possibile su device (App Group reale non scrivibile da fuori l'app)." >&2
  echo "         passa i seed via launchEnvironment/UI del test (nessun meccanismo COPAKY_SEED_* trovato in run_ui_test.sh per il device: verificare caso per caso)." >&2

  SYSLOG_PID=""
  SYSLOG_FILE="$OUT_DIR/syslog_${TEST}.log"
  if command -v pymobiledevice3 >/dev/null 2>&1; then
    log "avvio pymobiledevice3 syslog live -m Keyboard su $SYSLOG_FILE"
    if [[ "$DRY_RUN" == 1 ]]; then
      echo "[dry-run] pymobiledevice3 syslog live -m Keyboard -o $SYSLOG_FILE >/dev/null 2>&1 &"
    else
      pymobiledevice3 syslog live -m Keyboard -o "$SYSLOG_FILE" >/dev/null 2>&1 &
      SYSLOG_PID=$!
    fi
  else
    echo "warning: pymobiledevice3 assente — nessuna cattura syslog per $TEST" >&2
  fi

  RESULT_BUNDLE="$OUT_DIR/${TEST}.xcresult"
  TEST_ARGS=(
    test-without-building
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -destination "id=$UDID"
    -derivedDataPath "$DERIVED_DATA"
    -only-testing:"$TEST_ID"
    -resultBundlePath "$RESULT_BUNDLE"
  )
  log "eseguo $TEST_ID su $UDID"
  TEST_STATUS=0
  run xcodebuild "${TEST_ARGS[@]}" || TEST_STATUS=$?

  if [[ -n "$SYSLOG_PID" ]]; then
    kill "$SYSLOG_PID" >/dev/null 2>&1 || true
    wait "$SYSLOG_PID" 2>/dev/null || true
  fi

  if [[ "$DRY_RUN" == 1 ]]; then
    echo "[dry-run] xcrun xcresulttool get test-results summary --path $RESULT_BUNDLE --compact"
    continue
  fi

  [[ -d "$RESULT_BUNDLE" ]] || die "$TEST: nessun result bundle in $RESULT_BUNDLE"
  SUMMARY_JSON="$(xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" --compact 2>/dev/null)"
  # Copaky [F07]: il riepilogo distingue PASS/FAIL/SKIP dal result bundle invece di un solo verdetto
  # (un TEST_STATUS binario nascondeva gli skip e non separava un fallimento da uno skip).
  # Copaky [F07]: 単一の判定ではなくresult bundleからPASS/FAIL/SKIPを区別する（バイナリの
  # TEST_STATUSではskipが隠れ、失敗とskipが区別できなかった）。
  read -r EXECUTED PASSED FAILED SKIPPED <<<"$(echo "$SUMMARY_JSON" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get("totalTestCount", 0), d.get("passedTests", 0), d.get("failedTests", 0), d.get("skippedTests", 0))
' 2>/dev/null || echo "0 0 0 0")"
  echo "Executed $EXECUTED tests — PASS $PASSED / FAIL $FAILED / SKIP $SKIPPED"
  if [[ "$EXECUTED" -eq 0 ]]; then
    echo "✘ $TEST: 0 test eseguiti (runner stantio? -only-testing non ha trovato la classe)" >&2
    exit 1
  fi
  if [[ "$TEST_STATUS" != 0 || "$FAILED" -gt 0 ]]; then
    echo "✘ $TEST fallito (xcodebuild exit $TEST_STATUS, FAIL $FAILED)" >&2
    exit 1
  fi
  if [[ "$SKIPPED" -gt 0 ]]; then
    echo "⚠ $TEST: $EXECUTED test eseguiti, PASS $PASSED / SKIP $SKIPPED, nessun FAIL"
  else
    echo "✓ $TEST: $EXECUTED test eseguiti, PASS $PASSED, xcodebuild ok"
  fi
done

echo "✓ tutti i test richiesti eseguiti"
exit 0
