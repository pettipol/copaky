#!/usr/bin/env bash
#
# memory_phase_c.sh — sample the keyboard extension's memory while test42 (phase C of the memory
# protocol: many kana, a clipboard detour, Italian, back to kana) exercises it.
# メモリ協定フェーズCの実行中に、キーボード拡張のメモリをバックグラウンドでサンプリングする。
#
# The Simulator's ABSOLUTE memory numbers are not meaningful for the jetsam budget (playbook §1 point
# 3 / §4.5): `sim` mode exists to see the SHAPE of the curve locally, for free. `device` mode is the
# one whose numbers matter for a qualified verdict. Complete phase coverage is required; historical
# captures with skipped workloads are rejected by memory_phase_c_validate.py.
# シミュレータの絶対値はjetsam予算の判断に使えない（形だけを見る）。実機モードの数値だけが意味を持つ。
#
# Usage:
#   scripts/memory_phase_c.sh --mode sim
#   scripts/memory_phase_c.sh --mode device [--configuration Release]
#
# Prerequisite (not started by this script — see docs/UI_TESTING_PLAYBOOK.md §4.1): the field-fixture
# server must already be serving http://127.0.0.1:8377/kbtest.html for `sim` mode:
#   bash scripts/serve_test_page.sh --daemon
#
set -uo pipefail

MODE=""
CONFIGURATION="${COPAKY_CONFIGURATION:-Release}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) [[ $# -ge 2 ]] || exit 2; MODE="$2"; shift 2 ;;
    --configuration) [[ $# -ge 2 ]] || exit 2; CONFIGURATION="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown argument '$1' (expected --mode device|sim)" >&2; exit 2 ;;
  esac
done
if [[ "$MODE" != "sim" && "$MODE" != "device" ]]; then
  echo "Usage: $0 --mode device|sim" >&2
  exit 2
fi
if [[ "$CONFIGURATION" != "Release" && "$CONFIGURATION" != "Debug" ]]; then
  echo "ERROR: configuration must be Release or Debug" >&2; exit 2
fi
if [[ "$MODE" == "device" && "$CONFIGURATION" != "Release" ]]; then
  echo "ERROR: device memory qualification requires Release" >&2; exit 2
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_DIR/azooKey.xcodeproj"
SCHEME="CopakyUITests"
UITEST_BUNDLE="azooKeyUITests"
TEST_ID="$UITEST_BUNDLE/CopakyCampaignTests/test42_memoryPhaseC_japaneseTypingAcrossKana"
SIM_NAME="${COPAKY_SIM_NAME:-iPhone 17}"
DEVICE_ID="${COPAKY_DEVICE_ID:-}"      # CoreDevice id — for xcodebuild; never a device-specific default
# pymobiledevice3 addresses the phone by its lockdown UDID, NOT by the CoreDevice identifier above:
# passing the CoreDevice id gives "Device not found" and the sampler dies before the first sample
# (paid on 2026-08-15, first device run). Two ids for the same phone, on purpose.
# pymobiledevice3 は CoreDevice ID ではなく lockdown UDID を要求する（同じ端末に2つのIDがある）。
# No default: a lockdown UDID is a persistent identifier of one specific phone and does not belong in a
# public repository (Codex counter-review, 2026-08-16). Set COPAKY_DEVICE_UDID, or let the script pick the
# explicit paired device. / 既定値なし：端末固有の UDID は公開リポジトリに置かない。
DEVICE_UDID="${COPAKY_DEVICE_UDID:-}"   # lockdown UDID — for pymobiledevice3
if [[ "$MODE" == "device" && ( -z "$DEVICE_UDID" || -z "$DEVICE_ID" ) ]]; then
  echo "ERROR: set COPAKY_DEVICE_ID and COPAKY_DEVICE_UDID for the same paired phone" >&2; exit 2
fi
LOG_DIR="$HOME/copaky_device_logs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
CSV="$LOG_DIR/memc_${TS}.csv"
XCLOG="$LOG_DIR/memc_${TS}_xcodebuild.log"
RESULT_BUNDLE="$LOG_DIR/memc_${TS}.xcresult"
RAW_DIR="$LOG_DIR/memc_${TS}_raw"; mkdir -p "$RAW_DIR"
VALIDATOR="$REPO_DIR/scripts/memory_phase_c_validate.py"
SUMMARY_JSON="$LOG_DIR/memc_${TS}_summary.json"
PROVENANCE_JSON="$RAW_DIR/provenance.json"
DERIVED_DATA="${COPAKY_MEMORY_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/CopakyMemoryPhaseC}"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# ---- resolve the Simulator UDID by NAME (do not assume it matches COPAKY_UDID from the other
#      scripts in this folder — those default to "iPhone 17 Pro Max", a DIFFERENT device) -----------
resolve_sim_udid() {
  # `VAR=val cmd1 | cmd2` only exports VAR into cmd1's environment, not cmd2's — export it for real so
  # the python3 side of the pipe can see it too.
  export SIM_NAME
  xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, os, sys
name = os.environ["SIM_NAME"]
data = json.load(sys.stdin)
for devices in data.get("devices", {}).values():
    for d in devices:
        if d.get("name") == name:
            print(d["udid"])
            sys.exit(0)
'
}

# ---- sampler: sim mode -------------------------------------------------------------------------
# Finds the Keyboard extension process by the SAME path pattern seed_sim_settings.sh uses to kill it
# (Keyboard.appex is not a system keyboard, and the UDID-anchored path avoids matching an unrelated
# third-party keyboard extension that happens to also be named "Keyboard" — see docs/UI_TESTING_
# PLAYBOOK.md §5 on the "our markers must be ours" lesson, same idea applied to process names).
# physFootprint comes from /usr/bin/footprint (verified present on this machine, `-f bytes` gives a
# plain "phys_footprint: N B" line); if that binary is ever missing, fall back to `ps -o rss=`
# (resident set size — a looser but still useful signal, per the brief this script was built from).
sample_sim() {
  local udid="$1"
  echo "timestamp,pid,physFootprint_bytes" > "$CSV"
  while true; do
    local pid
    pid="$(pgrep -f "$udid.*azooKey.app/PlugIns/Keyboard.appex/Keyboard" | head -1)"
    if [[ -n "$pid" ]]; then
      local ts bytes
      ts="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
      bytes=""
      if [[ -x /usr/bin/footprint ]]; then
        bytes="$(/usr/bin/footprint -p "$pid" -f bytes 2>/dev/null | awk '/phys_footprint:/ {print $2; exit}')"
      fi
      if [[ -z "$bytes" ]]; then
        local rss_kb
        rss_kb="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')"
        [[ -n "$rss_kb" ]] && bytes=$((rss_kb * 1024))
      fi
      [[ -n "$bytes" ]] && echo "$ts,$pid,$bytes" >> "$CSV"
    fi
    sleep 1
  done
}

# ---- sampler: device mode -----------------------------------------------------------------------
# Copaky: single includes execName (monitor does not). Resolve the exact extension first, then
# monitor that PID; a process named Keyboard alone is never an identity proof. Snapshots and monitor
# stderr remain private evidence. A new PID during the campaign invalidates qualification.
sample_device() {
  local n=0 identity kpid
  while true; do
    n=$((n + 1))
    identity="$RAW_DIR/identity_$(printf '%03d' "$n").json"
    if PATH="$HOME/.local/bin:$PATH" pymobiledevice3 developer dvt sysmon process single \
        --filter name=Keyboard --key pid --key name --key execName --udid "$DEVICE_UDID" \
        --output "$identity" 2>"$RAW_DIR/identity_$(printf '%03d' "$n").stderr"; then
      kpid="$(python3 "$VALIDATOR" --select-pids "$identity")"
      # Reject ambiguous matches rather than choose the newest unrelated keyboard.
      if [[ "$kpid" =~ ^[0-9]+$ ]]; then
        PATH="$HOME/.local/bin:$PATH" pymobiledevice3 developer dvt sysmon process monitor process \
          --filter "pid=$kpid" --key pid --key name --key physFootprint \
          --interval 1000 --choose last --udid "$DEVICE_UDID" \
          --output "$RAW_DIR/attach_$(printf '%03d' "$n").jsonl" \
          >"$RAW_DIR/attach_$(printf '%03d' "$n").log" 2>&1
      fi
    fi
    sleep 2
  done
}

SAMPLER_PID=""
SAMPLER_PGID=""
UDID=""

# `set -m` (job control) makes bash give the NEXT backgrounded job its own process group, with a
# PGID equal to the job's own PID — that PGID is what lets stop_sampler() kill exactly this sampler
# (and, in device mode, the `pymobiledevice3 | python3` pipe underneath it) without a global
# `pkill -f` pattern that could hit another device's or another session's monitor process too
# (memory phase C review, finding C). `set +m` right after so the rest of the script keeps its
# normal non-interactive job-control behaviour (no "[1]+ Done" chatter at exit).
# `set -m` でジョブに専用のプロセスグループを与え、そのPGIDだけをkillする（他セッションを巻き込まない）。
start_sampler() {
  if [[ "$MODE" == "sim" ]]; then
    UDID="$(resolve_sim_udid)"
    if [[ -z "$UDID" ]]; then
      echo "ERROR: no booted/known Simulator named '$SIM_NAME' (xcrun simctl list devices)" >&2
      exit 1
    fi
    set -m
    sample_sim "$UDID" &
  else
    set -m
    sample_device &
  fi
  SAMPLER_PID=$!
  SAMPLER_PGID=$SAMPLER_PID
  set +m
  log "sampler started (pid $SAMPLER_PID, pgid $SAMPLER_PGID, mode=$MODE) → $CSV"
}

stop_sampler() {
  if [[ -n "$SAMPLER_PGID" ]]; then
    kill -- "-$SAMPLER_PGID" 2>/dev/null || true
    sleep 0.2
    kill -9 -- "-$SAMPLER_PGID" 2>/dev/null || true
  fi
  if [[ -n "$SAMPLER_PID" ]]; then
    wait "$SAMPLER_PID" 2>/dev/null || true
  fi
  log "sampler stopped"
}
trap stop_sampler EXIT

# ---- wait out any other xcodebuild run already in flight (repo convention, up to 30 min) ---------
# Match REAL xcodebuild build/test/archive processes only — a bare `pgrep -f xcodebuild` also
# matches shell wrappers and inspection commands that merely mention the word (this script waited
# 11 minutes on itself on 2026-08-15 before that was noticed).
# 本物の xcodebuild プロセスだけを待つ（単語を含むだけのシェルには反応しない）。
waited=0
while pgrep -f "usr/bin/xcodebuild (build|test|archive|build-for-testing|test-without-building)" >/dev/null 2>&1 && [[ $waited -lt 1800 ]]; do
  log "another xcodebuild is running — waiting 30s ($waited/1800s elapsed)"
  sleep 30
  waited=$((waited + 30))
done
if [[ $waited -ge 1800 ]]; then
  log "ERROR: another xcodebuild still owns the execution lane"; exit 2
fi

# ---- sim only: seed the keyboard layout settings test42 needs (playbook §4.7) --------------------
# The Simulator's App Group is not provisioned, so these never reach the extension via the app itself
# (§5); test42 needs the JAPANESE tab as flick (kana row-heads) and the ENGLISH/Italian tab as QWERTY
# (tapKeys looks up single-letter keys "p"/"e"/"r"/…, which only exist on the roman layout — the flick
# Latin layout groups letters as "ABC"/"DEF"/… instead, same prerequisite test30/31/33 already
# document). Also seeds enable_italian_keyboard_language=true (BoolKeyboardSetting.swift:249-253
# defaults it to false): on a device the user's own setting is already ON, but the Simulator's App
# Group isn't provisioned either, so without this the language-switch key never offers "IT" and
# test42's Italian phase records a soft it-skipped instead of exercising anything. This also
# TERMINATES the running extension, which is the state we want the sampler to start counting from
# anyway.
# シミュレータはApp Group未提供のため、拡張が読む設定をここで直接注入する（test30/31/33と同じ前提）。
# イタリア語設定も同じ理由でここに含める（実機ではユーザー設定が既にON）。
if [[ "$MODE" == "sim" ]]; then
  SEED_UDID="$(resolve_sim_udid)"
  if [[ -n "$SEED_UDID" ]]; then
    log "seeding keyboard layout settings on $SEED_UDID (keyboard_type=flick, keyboard_type_en=roman, enable_italian_keyboard_language=true)"
    bash "$REPO_DIR/scripts/seed_sim_settings.sh" \
      --udid "$SEED_UDID" keyboard_type=flick keyboard_type_en=roman enable_italian_keyboard_language=true || true
    # Stale-runner guard. Observed three times on 2026-08-15: `xcodebuild test` compiled the edited
    # test file but the Simulator RAN the previously installed UI-test runner — every run was exactly
    # one build behind (old MEMC markers after a marker-format change, a missing print after adding
    # it). Uninstalling the runner forces a fresh install of the bundle that was just built.
    # 直前のビルドではなく一つ前のテストランナーが実行される事象を3回観測: ランナーを毎回アンインストールする。
    xcrun simctl uninstall "$SEED_UDID" com.pettipol.copaky.uitests.xctrunner 2>/dev/null || true
  fi
fi

# ---- run test42 on the right destination ----------------------------------------------------
log "running $TEST_ID (mode=$MODE)"
if [[ "$MODE" == "sim" ]]; then
  start_sampler
  xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" -derivedDataPath "$DERIVED_DATA" \
    -destination "platform=iOS Simulator,name=$SIM_NAME" \
    -only-testing:"$TEST_ID" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    -resultBundlePath "$RESULT_BUNDLE" \
    2>&1 | tee "$XCLOG"
else
  # Verify that xcodebuild/devicectl and sysmon refer to the same phone; never select the first USB device.
  xcrun devicectl list devices --json-output "$RAW_DIR/devices.json" >"$RAW_DIR/devices.log" 2>&1
  if [[ $? != 0 ]] || ! python3 "$VALIDATOR" --device-map "$RAW_DIR/devices.json" \
      --device-id "$DEVICE_ID" --device-udid "$DEVICE_UDID"; then
    log "ERROR: CoreDevice/lockdown identifiers could not be correlated"; exit 2
  fi
  # Build and install BEFORE restarting the process, so an old Debug extension cannot survive
  # an apparent Release measurement. Execution remains in this single script's lane.
  xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" -derivedDataPath "$DERIVED_DATA" \
    -destination "platform=iOS,id=$DEVICE_ID" -allowProvisioningUpdates \
    2>&1 | tee "$RAW_DIR/build.log"
  if [[ $? != 0 ]]; then log "ERROR: Release build-for-testing failed"; exit 2; fi
  xcrun devicectl device install app --device "$DEVICE_ID" \
    "$DERIVED_DATA/Build/Products/Release-iphoneos/azooKey.app" >"$RAW_DIR/install.log" 2>&1
  if [[ $? != 0 ]]; then log "ERROR: Release app installation failed"; exit 2; fi
  # Pre-navigate Safari on the phone to the public copy of the field fixture (site/kbtest.html →
  # https://copaky.app/kbtest): on device the test ACTIVATES Safari instead of launching it, because
  # `launch()` restores the user's last tab and 127.0.0.1 would be the phone itself.
  # 実機ではフィクスチャの公開コピーを先に開いておく（テスト側は activate のみ）。
  # Same stale-runner guard as sim mode (the phone keeps the previously installed xctrunner too).
  xcrun devicectl device uninstall app --device "$DEVICE_ID" com.pettipol.copaky.uitests.xctrunner >/dev/null 2>&1 || true
  # Fresh extension process. iOS keeps a running keyboard-extension process alive across the app
  # (re)install xcodebuild performs, so without this the run measures the PREVIOUS binary (seen
  # 2026-08-15: the same pid, in the same bundle container, survived three runs — including the
  # first "Release" one, which therefore measured Debug). Terminate it; the test's first keystroke
  # spawns a new process from the binary that was just installed.
  # 拡張プロセスは再インストール後も生き残る → 事前に終了させ、新しいバイナリで起動させる。
  PATH="$HOME/.local/bin:$PATH" pymobiledevice3 developer dvt sysmon process single \
    --key pid --key name --key execName --udid "$DEVICE_UDID" \
    --output "$RAW_DIR/before.json" >"$RAW_DIR/before.log" 2>&1
  if [[ $? != 0 ]]; then log "ERROR: cannot establish pre-run process identity"; exit 2; fi
  STALE_PIDS="$(python3 "$VALIDATOR" --select-pids "$RAW_DIR/before.json")"
  if [[ $? != 0 ]]; then log "ERROR: invalid pre-run identity snapshot"; exit 2; fi
  for kpid in $STALE_PIDS; do
    log "terminating stale Keyboard extension process pid $kpid"
    xcrun devicectl device process terminate --device "$DEVICE_ID" --pid "$kpid" >/dev/null 2>&1 || {
      log "ERROR: could not terminate stale Keyboard process"; exit 2;
    }
  done
  log "pre-navigating Safari on the phone to https://copaky.app/kbtest"
  xcrun devicectl device process launch --device "$DEVICE_ID" --payload-url "https://copaky.app/kbtest" com.apple.mobilesafari >/dev/null 2>&1 || \
    log "WARN: devicectl could not open Safari — the test will fail on 'textarea-field not found' if the page is not open"
  sleep 3
  start_sampler
  # `-configuration Release` measures the SHIPPED kind of binary (Debug builds carry unoptimised
  # code and allocator debugging and read several MB higher — first device run: 47-51 MB Debug).
  xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" -derivedDataPath "$DERIVED_DATA" \
    -destination "platform=iOS,id=$DEVICE_ID" -allowProvisioningUpdates \
    -only-testing:"$TEST_ID" \
    -resultBundlePath "$RESULT_BUNDLE" \
    2>&1 | tee "$XCLOG"
fi
XCODEBUILD_STATUS=$?

# Monitor the sampler itself: if it died mid-run (crash, killed by something else) the CSV silently
# stops growing and a "zero samples" verdict below would look like a product problem instead of a
# harness one. Check BEFORE stop_sampler intentionally kills it (memory phase C review, finding B).
SAMPLER_DIED=0
if [[ -n "$SAMPLER_PID" ]] && ! kill -0 "$SAMPLER_PID" 2>/dev/null; then
  log "ERROR: sampler process (pid $SAMPLER_PID) was not running when the test finished — it died mid-run"
  SAMPLER_DIED=1
fi

stop_sampler
trap - EXIT

# ---- machine-readable, fail-closed summary ----------------------------------------------------
# Copaky: record requested configuration and local build output separately from process identity.
# This is not a remote hash attestation of the installed binary.
python3 - "$PROVENANCE_JSON" "$MODE" "$CONFIGURATION" "$XCODEBUILD_STATUS" "$SAMPLER_DIED" "$REPO_DIR" <<'PYPROV'
import json, subprocess, sys
from pathlib import Path
path, mode, configuration, status, sampler_died, repo = sys.argv[1:]
def git(*args):
    result = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None
Path(path).write_text(json.dumps({"mode": mode, "configuration": configuration,
    "xcodebuild_status": int(status), "sampler_died": int(sampler_died),
    "device_mapping_verified": mode == "device",
    "source_commit": git("rev-parse", "HEAD"), "source_dirty": bool(git("status", "--porcelain")),
    "installed_binary_hash": "NOT_VERIFIED", "test": "test42_memoryPhaseC_japaneseTypingAcrossKana"}, indent=2) + "\n")
PYPROV
PROVENANCE_STATUS=$?
if [[ "$PROVENANCE_STATUS" != 0 ]]; then log "ERROR: could not record provenance"; exit 2; fi

SUMMARY_STATUS=0
if [[ "$MODE" == "device" ]]; then
  python3 "$VALIDATOR" --log "$XCLOG" --csv "$CSV" --raw-dir "$RAW_DIR" \
    --provenance "$PROVENANCE_JSON" --app "$DERIVED_DATA/Build/Products/Release-iphoneos/azooKey.app" \
    --json "$SUMMARY_JSON" || SUMMARY_STATUS=$?
else
  python3 "$VALIDATOR" --log "$XCLOG" --csv "$CSV" --provenance "$PROVENANCE_JSON" \
    --json "$SUMMARY_JSON" || SUMMARY_STATUS=$?
fi
log "done. summary=$SUMMARY_JSON CSV=$CSV xcodebuild-log=$XCLOG result-bundle=$RESULT_BUNDLE"
# 0 = complete/in budget; 1 = complete/over budget; 2 = measurement error or simulator-only.
exit "$SUMMARY_STATUS"
