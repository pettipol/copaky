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
#   scripts/memory_phase_c.sh --mode device [--configuration Release]
#
# Prerequisite (not started by this script — see docs/UI_TESTING_PLAYBOOK.md §4.1): the field-fixture
# server must already be serving http://127.0.0.1:8377/kbtest.html for `sim` mode:
#   bash scripts/serve_test_page.sh --daemon
#
set -uo pipefail

MODE=""
CONFIGURATION="${COPAKY_CONFIGURATION:-}"   # empty = the scheme's default (Debug); "Release" = the shipped kind
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --configuration) CONFIGURATION="$2"; shift 2 ;;
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
DEVICE_ID="${COPAKY_DEVICE_ID:-2902B1DD-4621-5324-9818-37C757CF15E9}"      # CoreDevice id — for xcodebuild
# pymobiledevice3 addresses the phone by its lockdown UDID, NOT by the CoreDevice identifier above:
# passing the CoreDevice id gives "Device not found" and the sampler dies before the first sample
# (paid on 2026-08-15, first device run). Two ids for the same phone, on purpose.
# pymobiledevice3 は CoreDevice ID ではなく lockdown UDID を要求する（同じ端末に2つのIDがある）。
DEVICE_UDID="${COPAKY_DEVICE_UDID:-REDACTED-DEVICE-UDID}"   # lockdown UDID — for pymobiledevice3
LOG_DIR="$HOME/copaky_device_logs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
CSV="$LOG_DIR/memc_${TS}.csv"
XCLOG="$LOG_DIR/memc_${TS}_xcodebuild.log"
RESULT_BUNDLE="$LOG_DIR/memc_${TS}.xcresult"
RAW_DIR="$LOG_DIR/memc_${TS}_raw"; mkdir -p "$RAW_DIR"

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
  # `monitor process` picks ONE process from the snapshot taken at start-up and errors out when
  # nothing matches ("Failed to find a process matching the given filters in the current
  # snapshot") — and the extension process does not exist until the test brings the keyboard up,
  # and can be relaunched by iOS mid-run (new pid). So: keep re-attaching until we are stopped;
  # every attach that fails or ends is retried after 2 s. Verified on the phone 2026-08-15 (the
  # first device run had the sampler die at t=0 for exactly this reason).
  # 拡張プロセスはキーボード表示まで存在せず、途中で再起動もする → 停止されるまで再接続を繰り返す。
  #
  # Output goes to a JSONL FILE per attach (`--output`), never through a pipe: pymobiledevice3
  # block-buffers stdout when piped, so a 280 s run produced ZERO lines through `| python3`
  # (5th device run) while `--output` wrote every second. The files are merged into the CSV by
  # finalize_device_samples() after the test.
  # パイプだと出力がバッファされ何も届かない（実測）→ 必ず --output でファイルに書き、後で CSV に変換する。
  local n=0
  while true; do
    n=$((n + 1))
    PATH="$HOME/.local/bin:$PATH" pymobiledevice3 developer dvt sysmon process monitor process \
        --filter name=Keyboard --key pid --key name --key physFootprint \
        --interval 1000 --choose last --udid "$DEVICE_UDID" \
        --output "$RAW_DIR/attach_$(printf '%03d' "$n").jsonl" >/dev/null 2>&1
    sleep 2
  done
}

# Merge the per-attach JSONL files into the CSV the summarizer reads. `--key execName` is rejected
# by the monitor, so the only handle is the process name: on this phone the sole third-party
# keyboard is Copaky (checked with `sysmon process single`: name=Keyboard, execName …/azooKey.app/
# PlugIns/Keyboard.appex/Keyboard).
finalize_device_samples() {
  /usr/bin/python3 - "$RAW_DIR" "$CSV" <<'PY'
import sys, json, glob, os
raw_dir, csv_path = sys.argv[1], sys.argv[2]
rows = []
for path in sorted(glob.glob(os.path.join(raw_dir, "attach_*.jsonl"))):
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            name = str(rec.get("name", ""))
            if name != "Keyboard" and "copaky" not in name.lower():
                continue
            ts = rec.get("timestamp")
            pid = rec.get("pid", "")
            foot = rec.get("physFootprint", "")
            if ts is None or foot == "":
                continue
            rows.append((ts, pid, foot))
rows.sort()
with open(csv_path, "a") as out:
    for ts, pid, foot in rows:
        out.write(f"{ts},{pid},{foot}\n")
print(f"[device] merged {len(rows)} samples from {len(glob.glob(os.path.join(raw_dir, 'attach_*.jsonl')))} attach file(s)")
PY
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

start_sampler
sleep 1   # let the first sample land before the run's own MEMC markers start

# ---- run test42 on the right destination ----------------------------------------------------
log "running $TEST_ID (mode=$MODE)"
if [[ "$MODE" == "sim" ]]; then
  xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \
    ${CONFIGURATION:+-configuration "$CONFIGURATION"} \
    -destination "platform=iOS Simulator,name=$SIM_NAME" \
    -only-testing:"$TEST_ID" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    -resultBundlePath "$RESULT_BUNDLE" \
    2>&1 | tee "$XCLOG"
else
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
  for kpid in $(xcrun devicectl device info processes --device "$DEVICE_ID" 2>/dev/null | awk '/azooKey.app\/PlugIns\/Keyboard.appex\/Keyboard/ {print $1}'); do
    log "terminating stale Keyboard extension process pid $kpid"
    xcrun devicectl device process terminate --device "$DEVICE_ID" --pid "$kpid" >/dev/null 2>&1 || true
  done
  log "pre-navigating Safari on the phone to https://copaky.app/kbtest"
  xcrun devicectl device process launch --device "$DEVICE_ID" --payload-url "https://copaky.app/kbtest" com.apple.mobilesafari >/dev/null 2>&1 || \
    log "WARN: devicectl could not open Safari — the test will fail on 'textarea-field not found' if the page is not open"
  sleep 3
  # `-configuration Release` measures the SHIPPED kind of binary (Debug builds carry unoptimised
  # code and allocator debugging and read several MB higher — first device run: 47-51 MB Debug).
  xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \
    ${CONFIGURATION:+-configuration "$CONFIGURATION"} \
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
if [[ "$MODE" == "device" ]]; then finalize_device_samples; fi

# ---- markers + summary -----------------------------------------------------------------------
log "=== MEMC markers ($XCLOG) ==="
grep '^MEMC|' "$XCLOG" || echo "(none found — the test may not have run; check the log above)"

log "=== physFootprint summary ($CSV) ==="
SUMMARY_STATUS=0
/usr/bin/python3 - "$XCLOG" "$CSV" <<'PY' || SUMMARY_STATUS=$?
import sys, csv
from datetime import datetime

xclog_path, csv_path = sys.argv[1], sys.argv[2]

def parse_iso(ts):
    ts = ts.strip()
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    return datetime.fromisoformat(ts)

# markers[phase][edge] = timestamp, edge in {"start", "end"} — see MainAppUITests.memcMarker.
markers = {}
malformed = 0
with open(xclog_path, errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line.startswith("MEMC|"):
            continue
        parts = line.split("|", 3)
        if len(parts) != 4 or parts[2] not in ("start", "end"):
            malformed += 1
            continue
        _, phase, edge, ts = parts
        try:
            markers.setdefault(phase, {})[edge] = parse_iso(ts)
        except ValueError:
            malformed += 1

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

total_marker_lines = sum(len(edges) for edges in markers.values())
print(f"markers: {total_marker_lines} ({len(markers)} phases)")
if malformed:
    print(f"malformed MEMC lines skipped: {malformed}")
print(f"samples: {len(samples)}")

ok = True
if not samples:
    print("FAIL: zero samples recorded — the sampler produced no data")
    ok = False

# ---- required marker set (memory phase C review, finding B): every jp-N with BOTH edges, one of
# clipboard/clipboard-skipped, one of it/it-skipped, and a final "end". Missing any of these means
# the run is not trustworthy enough to summarize as a pass. ------------------------------------
required_jp = [f"jp-{i}" for i in range(12)]
missing_edges = [p for p in required_jp if not {"start", "end"} <= markers.get(p, {}).keys()]
if missing_edges:
    print(f"FAIL: missing start+end markers for: {', '.join(missing_edges)}")
    ok = False

clipboard_phase = next((p for p in ("clipboard", "clipboard-skipped") if p in markers), None)
if clipboard_phase is None:
    print("FAIL: no 'clipboard' or 'clipboard-skipped' marker found")
    ok = False

italian_phase = next((p for p in ("it", "it-skipped") if p in markers), None)
if italian_phase is None:
    print("FAIL: no 'it' or 'it-skipped' marker found")
    ok = False

if "end" not in markers:
    print("FAIL: no final 'end' marker found — the test may not have completed")
    ok = False

# ---- per-phase attribution: window = [start, end] for a paired phase, a single instant for "end" -
print("--- per-phase samples ---")
ordered_phases = sorted(markers, key=lambda p: min(markers[p].values()))
phases_with_samples = 0
for phase in ordered_phases:
    edges = markers[phase]
    start = edges.get("start", edges.get("end"))
    end = edges.get("end", edges.get("start"))
    window = [b for t, b in samples if start <= t <= end]
    if window:
        phases_with_samples += 1
        print(f"{phase}: n={len(window)} max={max(window) / (1024 * 1024):.2f} MB")
    else:
        print(f"{phase}: no samples in window")
print(f"phases with samples: {phases_with_samples}/{len(ordered_phases)}")

# ---- required phases must ALSO carry at least one sample in their own window ------------------
# Skipped when there are zero samples overall — every phase would show up "starved" and just repeat
# the "zero samples recorded" FAIL above with no new information.
if samples:
    required_phases = required_jp + [p for p in (clipboard_phase, italian_phase) if p]
    starved = []
    for phase in required_phases:
        edges = markers.get(phase, {})
        start, end = edges.get("start"), edges.get("end")
        if not (start and end):
            continue   # already reported under missing_edges above
        if not [b for t, b in samples if start <= t <= end]:
            starved.append(phase)
    if starved:
        print(f"FAIL: zero samples inside the window of required phase(s): {', '.join(starved)}")
        ok = False

if samples:
    mb = [b / (1024 * 1024) for _, b in samples]
    print(f"min: {min(mb):.2f} MB")
    print(f"max: {max(mb):.2f} MB")
    print(f"avg: {sum(mb) / len(mb):.2f} MB")

sys.exit(0 if ok else 1)
PY

FINAL_STATUS="$XCODEBUILD_STATUS"
if [[ "$SAMPLER_DIED" == 1 && "$FINAL_STATUS" == 0 ]]; then
  FINAL_STATUS=1
fi
if [[ "$SUMMARY_STATUS" != 0 ]]; then
  log "summary validation FAILED (exit $SUMMARY_STATUS) — see FAIL lines above"
  if [[ "$FINAL_STATUS" == 0 ]]; then
    FINAL_STATUS=1
  fi
fi

log "done. CSV=$CSV xcodebuild-log=$XCLOG result-bundle=$RESULT_BUNDLE"
exit "$FINAL_STATUS"
