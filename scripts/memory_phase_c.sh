#!/usr/bin/env bash
#
# memory_phase_c.sh — sample the keyboard extension's memory while test42 (phase C of the memory
# protocol: many kana, a clipboard detour, Italian, back to kana) exercises it.
# メモリ協定フェーズCの実行中に、キーボード拡張のメモリをバックグラウンドでサンプリングする。
#
# The Simulator's ABSOLUTE memory numbers are not meaningful for the jetsam budget (playbook §1 point
# 3 / §4.5): `sim` mode exists to see the SHAPE of the curve locally, for free. `device` mode is the
# one whose numbers matter for a real verdict; it is written to the same contract as `sim` but this
# script was authored and exercised on `sim` only — the phone was out of scope for this session.
# シミュレータの絶対値はjetsam予算の判断に使えない（形だけを見る）。実機モードの数値だけが意味を持つ。
#
# Usage:
#   scripts/memory_phase_c.sh --mode sim
#   scripts/memory_phase_c.sh --mode device
#
# Prerequisite (not started by this script — see docs/UI_TESTING_PLAYBOOK.md §4.1): the field-fixture
# server must already be serving http://127.0.0.1:8377/kbtest.html for `sim` mode:
#   bash scripts/serve_test_page.sh --daemon
#
set -uo pipefail

MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown argument '$1' (expected --mode device|sim)" >&2; exit 2 ;;
  esac
done
if [[ "$MODE" != "sim" && "$MODE" != "device" ]]; then
  echo "Usage: $0 --mode device|sim" >&2
  exit 2
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_DIR/azooKey.xcodeproj"
SCHEME="CopakyUITests"
UITEST_BUNDLE="azooKeyUITests"
TEST_ID="$UITEST_BUNDLE/CopakyCampaignTests/test42_memoryPhaseC_japaneseTypingAcrossKana"
SIM_NAME="${COPAKY_SIM_NAME:-iPhone 17}"
DEVICE_ID="${COPAKY_DEVICE_ID:-2902B1DD-4621-5324-9818-37C757CF15E9}"
LOG_DIR="$HOME/copaky_device_logs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
CSV="$LOG_DIR/memc_${TS}.csv"
XCLOG="$LOG_DIR/memc_${TS}_xcodebuild.log"
RESULT_BUNDLE="$LOG_DIR/memc_${TS}.xcresult"

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
# `pymobiledevice3 developer dvt sysmon process monitor process --help` (checked 2026-08-15, see
# docs/UI_TESTING_PLAYBOOK.md §4.5): the subcommand DOES filter the live process snapshot by
# key=value (--filter), so `--filter name=Keyboard` should narrow the stream on its own; the python3
# re-check below is the fallback the brief asked for in case a given pymobiledevice3 build does not
# actually narrow — never verified against the phone in this session (device mode was explicitly out
# of scope: "il telefono NON è disponibile ora — non provare il device").
# --filter name=Keyboard で絞れるはずだが、効かない版に備えてPython側でも再確認する（実機は未検証）。
sample_device() {
  echo "timestamp,pid,physFootprint_bytes" > "$CSV"
  PATH="$HOME/.local/bin:$PATH" pymobiledevice3 developer dvt sysmon process monitor process \
      --filter name=Keyboard --key pid --key name --key physFootprint \
      --interval 1000 --choose first --userspace --udid "$DEVICE_ID" \
    | /usr/bin/python3 -u -c '
import sys, json, datetime
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        rec = json.loads(line)
    except json.JSONDecodeError:
        continue
    name = str(rec.get("name", ""))
    if "keyboard" not in name.lower() and "copaky" not in name.lower():
        continue
    pid = rec.get("pid", "")
    foot = rec.get("physFootprint", "")
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    print(f"{ts},{pid},{foot}")
' >> "$CSV"
}

SAMPLER_PID=""
UDID=""

start_sampler() {
  if [[ "$MODE" == "sim" ]]; then
    UDID="$(resolve_sim_udid)"
    if [[ -z "$UDID" ]]; then
      echo "ERROR: no booted/known Simulator named '$SIM_NAME' (xcrun simctl list devices)" >&2
      exit 1
    fi
    sample_sim "$UDID" &
  else
    sample_device &
  fi
  SAMPLER_PID=$!
  log "sampler started (pid $SAMPLER_PID, mode=$MODE) → $CSV"
}

stop_sampler() {
  if [[ -n "$SAMPLER_PID" ]]; then
    kill "$SAMPLER_PID" 2>/dev/null || true
    wait "$SAMPLER_PID" 2>/dev/null || true
  fi
  if [[ "$MODE" == "device" ]]; then
    # Belt-and-suspenders: $SAMPLER_PID under job control (off by default in non-interactive scripts)
    # is only the LAST element of the `pymobiledevice3 | python3` pipe; kill the upstream by pattern
    # too, scoped narrowly enough not to touch anything else running on the Mac.
    pkill -f "developer dvt sysmon process monitor process" 2>/dev/null || true
  fi
  log "sampler stopped"
}
trap stop_sampler EXIT

# ---- wait out any other xcodebuild run already in flight (repo convention, up to 30 min) ---------
waited=0
while pgrep -fl xcodebuild >/dev/null 2>&1 && [[ $waited -lt 1800 ]]; do
  log "another xcodebuild is running — waiting 30s ($waited/1800s elapsed)"
  sleep 30
  waited=$((waited + 30))
done

# ---- sim only: seed the keyboard layout settings test42 needs (playbook §4.7) --------------------
# The Simulator's App Group is not provisioned, so these never reach the extension via the app itself
# (§5); test42 needs the JAPANESE tab as flick (kana row-heads) and the ENGLISH/Italian tab as QWERTY
# (tapKeys looks up single-letter keys "p"/"e"/"r"/…, which only exist on the roman layout — the flick
# Latin layout groups letters as "ABC"/"DEF"/… instead, same prerequisite test30/31/33 already
# document). This also TERMINATES the running extension, which is the state we want the sampler to
# start counting from anyway.
# シミュレータはApp Group未提供のため、拡張が読む設定をここで直接注入する（test30/31/33と同じ前提）。
if [[ "$MODE" == "sim" ]]; then
  SEED_UDID="$(resolve_sim_udid)"
  if [[ -n "$SEED_UDID" ]]; then
    log "seeding keyboard layout settings on $SEED_UDID (keyboard_type=flick, keyboard_type_en=roman)"
    bash "$REPO_DIR/scripts/seed_sim_settings.sh" \
      --udid "$SEED_UDID" keyboard_type=flick keyboard_type_en=roman || true
  fi
fi

start_sampler
sleep 1   # let the first sample land before the run's own MEMC markers start

# ---- run test42 on the right destination ----------------------------------------------------
log "running $TEST_ID (mode=$MODE)"
if [[ "$MODE" == "sim" ]]; then
  xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=$SIM_NAME" \
    -only-testing:"$TEST_ID" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    -resultBundlePath "$RESULT_BUNDLE" \
    2>&1 | tee "$XCLOG"
else
  xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \
    -destination "platform=iOS,id=$DEVICE_ID" -allowProvisioningUpdates \
    -only-testing:"$TEST_ID" \
    -resultBundlePath "$RESULT_BUNDLE" \
    2>&1 | tee "$XCLOG"
fi
XCODEBUILD_STATUS=$?

stop_sampler
trap - EXIT

# ---- markers + summary -----------------------------------------------------------------------
log "=== MEMC markers ($XCLOG) ==="
grep '^MEMC|' "$XCLOG" || echo "(none found — the test may not have run; check the log above)"

log "=== physFootprint summary ($CSV) ==="
/usr/bin/python3 - "$XCLOG" "$CSV" <<'PY'
import sys, csv
from datetime import datetime

xclog_path, csv_path = sys.argv[1], sys.argv[2]

def parse_iso(ts):
    ts = ts.strip()
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    return datetime.fromisoformat(ts)

markers = []
with open(xclog_path, errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line.startswith("MEMC|"):
            continue
        parts = line.split("|", 2)
        if len(parts) != 3:
            continue
        _, phase, ts = parts
        try:
            markers.append((phase, parse_iso(ts)))
        except ValueError:
            continue

try:
    with open(csv_path) as f:
        rows = list(csv.DictReader(f))
except FileNotFoundError:
    rows = []

samples = []
for r in rows:
    try:
        samples.append((parse_iso(r["timestamp"]), int(r["physFootprint_bytes"])))
    except (KeyError, ValueError):
        continue

print(f"markers: {len(markers)}")
print(f"samples: {len(samples)}")
if not samples:
    print("no samples recorded — nothing more to summarize")
    sys.exit(0)

mb = [b / (1024 * 1024) for _, b in samples]
print(f"min: {min(mb):.2f} MB")
print(f"max: {max(mb):.2f} MB")
print(f"avg: {sum(mb) / len(mb):.2f} MB")

if markers:
    print("--- per-phase max (window = [marker_i, marker_i+1)) ---")
    for i, (phase, ts) in enumerate(markers):
        end = markers[i + 1][1] if i + 1 < len(markers) else None
        window = [b for t, b in samples if t >= ts and (end is None or t < end)]
        if window:
            print(f"{phase}: max={max(window) / (1024 * 1024):.2f} MB (n={len(window)})")
        else:
            print(f"{phase}: no samples in window")
PY

log "done. CSV=$CSV xcodebuild-log=$XCLOG result-bundle=$RESULT_BUNDLE"
exit "$XCODEBUILD_STATUS"
