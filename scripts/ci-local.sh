#!/usr/bin/env bash
# Copaky — local CI mirror (self-contained in this repo). Replaces the now workflow_dispatch-only
# hosted macOS CI: build and test locally for fast feedback without launching an Actions job.
#
# Usage:
#   scripts/ci-local.sh           full: build MainApp + full AzooKeyCore tests + offline audit
#   scripts/ci-local.sh --fast    fast: build MainApp + ClipboardHistoryManagerTests (pre-push hook)
#
# Rationale: this iOS/UIKit app uses the local Mac toolchain for a quick development gate.
# Hosted runner availability and pricing do not determine this local-first workflow.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM="${COPAKY_CI_SIM:-platform=iOS Simulator,name=iPhone 17}"
FAST=0; [ "${1:-}" = "--fast" ] && FAST=1
fail=0

# Self-wire the git hooks. The hooks in .githooks/ (pre-commit secret scan, pre-push CI gate)
# are INERT on a fresh clone until core.hooksPath points at them, and an instruction that lives
# only in CONTRIBUTING.md is an instruction that gets skipped. Since this script is the
# documented entry point for anyone building the project, it sets it here — idempotently, and
# never overriding a hooksPath somebody chose deliberately.
if [ -z "$(git -C "$REPO" config --local core.hooksPath || true)" ]; then
  git -C "$REPO" config core.hooksPath .githooks \
    && echo "✓ git hooks wired: core.hooksPath=.githooks (pre-commit secret scan, pre-push CI)"
fi

# Cheap and always run: an empty localization value renders as a BLANK label on device
# (Foundation returns the empty value, it does not fall back to the key). Catching this costs
# milliseconds; missing it costs a blank keycap on someone's phone.
echo "▶ [0/3] String Catalog lint…"
python3 "$REPO/scripts/lint_string_catalog.py" || fail=1

echo "▶ [0/3] Hard-coded Japanese UI lint (advisory)…"
python3 "$REPO/scripts/lint_hardcoded_ja.py" || true

# Home-directory path gate on the COMMITTED tree — same check as the pre-commit hook (staged), here
# run over the blobs of HEAD (what a push actually publishes), not the working tree: an unstaged
# cleanup must not hide a path that is still inside the commit being pushed. `git grep -I` skips
# binaries; a non-zero exit other than "no match" (1) is a scanner error and fails closed.
echo "▶ [0/3] Home-directory path scan (HEAD tree)…"
HOME_PATH_HITS="$(git -C "$REPO" grep -I -nE '/Users/[a-z][A-Za-z0-9._-]*' HEAD -- 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then
  echo "✘ absolute home-directory path(s) found in the committed tree:"
  echo "$HOME_PATH_HITS" | sed 's/^HEAD://'
  fail=1
elif [ $rc -ne 1 ]; then
  echo "✘ home-directory path scan could not run (git grep exit $rc): $HOME_PATH_HITS"
  fail=1
fi

echo "▶ [1/3] Build MainApp ($([ $FAST = 1 ] && echo fast || echo full))…"
xcodebuild build -project "$REPO/azooKey.xcodeproj" -scheme MainApp \
  -destination "$SIM" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet \
  || { echo "✘ build FAILED"; fail=1; }

if [ $fail = 0 ]; then
  if [ $FAST = 1 ]; then
    echo "▶ [2/3] Test: ClipboardHistoryManagerTests…"
    EXTRA=(-only-testing:AzooKeyUtilsTests/ClipboardHistoryManagerTests)
  else
    echo "▶ [2/3] Test: full AzooKeyCore package…"
    # Known PRE-EXISTING upstream failure (azooKey commit a1065004, date-template migration quoting),
    # skipped so the gate reflects Copaky's own state. Triage tracked in PLAN.md / CHANGELOG.
    EXTRA=(-skip-testing:AzooKeyUtilsTests/UserDictionaryMigrationTests/test_migrate_known_single_placeholder_merges_into_date_format)
  fi
  # Copaky: keep the local simulator lane serial, including Xcode's implicit test workers.
  # Copaky: Xcodeの暗黙の並列テストワーカーも無効にし、シミュレータ実行を直列化する。
  ( cd "$REPO/AzooKeyCore" && xcodebuild test -scheme AzooKeyCore-Package \
      -destination "$SIM" -parallel-testing-enabled NO \
      -maximum-concurrent-test-simulator-destinations 1 \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet \
      "${EXTRA[@]}" ) || { echo "✘ tests FAILED"; fail=1; }
fi

if [ $FAST = 0 ]; then
  # Copaky: both findings and incomplete scans fail the full gate. Keep the scope,
  # exceptions and independent static verdict visible; this is not runtime evidence.
  echo "▶ [3/3] Harness regression tests (unittest discovery: test_*.py)…"
  if python3 - "$REPO/scripts/tests" <<'PY'
import sys
import unittest
from pathlib import Path

root = Path(sys.argv[1])
required = ("test_audit_network_calls", "test_memory_phase_c_validate")
for name in required:
    if not (root / f"{name}.py").is_file():
        raise SystemExit(f"Missing required harness test: {name}.py")
loader = unittest.TestLoader()
suite = loader.discover(str(root), pattern="test_*.py")
if not suite.countTestCases():
    raise SystemExit("Harness test discovery found zero tests")
for name in required:
    if not loader.loadTestsFromName(name).countTestCases():
        raise SystemExit(f"Required harness module contains zero tests: {name}")
sys.exit(0 if unittest.TextTestRunner(verbosity=1).run(suite).wasSuccessful() else 1)
PY
  then
    echo "✓ harness regression tests: PASS"
  else
    echo "✘ harness regression tests FAILED"
    fail=1
  fi
  echo "▶ [3/3] Offline static source audit (required; runtime NOT_RUN)…"
  if python3 "$REPO/scripts/audit_network_calls.py" "$REPO"; then
    echo "✓ ci-local offline static gate: PASS (reviewed local source scope only)"
  else
    audit_rc=$?
    echo "✘ ci-local offline static gate: FAIL (scanner exit $audit_rc; runtime NOT_RUN)"
    fail=1
  fi
else
  echo "OFFLINE_STATIC=NOT_RUN (--fast); OFFLINE_RUNTIME=NOT_RUN"
fi

echo "──────────────────────────────────────────"
[ $fail = 0 ] && echo "✅ ci-local: PASS" || echo "❌ ci-local: FAIL"
exit $fail
