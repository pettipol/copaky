#!/usr/bin/env bash
# Copaky [F-08] — layout gallery shots for the site («funzionalità chiave e come appaiono»).
# Captures ONLY the keyboard (test51 shoots the UIKit inputView element) across the option
# states below, then exports the PNGs. Reuses run_ui_test.sh for every trap (boot, seeding,
# fresh install, cfprefsd warm-up); one state = one invocation, no cross-state reuse.
# Copaky [F-08] — サイト用レイアウトギャラリー撮影。状態ごとにrun_ui_test.shを1回呼ぶ。
#
# Usage: scripts/layout_gallery_shots.sh [OUT_DIR]     (default: /tmp/copaky_layout_gallery)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-/tmp/copaky_layout_gallery}"
DERIVED_DATA="${COPAKY_DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData/CopakySingleUITest}"
mkdir -p "$OUT_DIR"

# name | extra seeds (space-separated k=v) | gallery-type
STATES=(
  "l1_base|enable_qwerty_number_row_hints=false enable_clipboard_history_manager_tab=false display_tab_bar_button=false|"
  "l2_hints|enable_qwerty_number_row_hints=true enable_clipboard_history_manager_tab=false display_tab_bar_button=false|"
  "l3_number_row|enable_qwerty_number_row=true enable_qwerty_number_row_hints=false enable_clipboard_history_manager_tab=false display_tab_bar_button=false|"
  "l4_clipboard_badge|enable_clipboard_history_manager_tab=true enable_qwerty_number_row_hints=false display_tab_bar_button=false|"
  "l5_predictions|enable_qwerty_number_row_hints=false enable_clipboard_history_manager_tab=false display_tab_bar_button=false|ciao"
)

first=1
for state in "${STATES[@]}"; do
  name="${state%%|*}"
  rest="${state#*|}"
  seeds="${rest%%|*}"
  gtype="${rest#*|}"

  args=()
  # The container must exist once; later states reuse the signed install.
  if [[ $first == 1 ]]; then args+=(--fresh-install); first=0; fi
  for kv in $seeds; do args+=(--seed "$kv"); done

  echo "▶ gallery state: $name (seeds: ${seeds:-defaults})"
  TEST_RUNNER_COPAKY_GALLERY_NAME="$name" \
  TEST_RUNNER_COPAKY_GALLERY_TYPE="$gtype" \
    "$REPO_DIR/scripts/run_ui_test.sh" "${args[@]}" test51_layoutGalleryShot \
    | grep -E "Test Case.*(passed|failed)" | tail -1

  # Export the freshest xcresult's gallery attachment.
  XCRESULT="$(ls -td "$DERIVED_DATA"/Logs/Test/*.xcresult | head -1)"
  TMP_EXPORT="$(mktemp -d)"
  xcrun xcresulttool export attachments --path "$XCRESULT" --output-path "$TMP_EXPORT" >/dev/null
  python3 - "$TMP_EXPORT" "$OUT_DIR" "$name" <<'PY'
import json, shutil, sys, os
tmp, out, name = sys.argv[1], sys.argv[2], sys.argv[3]
manifest = json.load(open(os.path.join(tmp, "manifest.json")))
found = []
def walk(node):
    if isinstance(node, dict):
        human = node.get("suggestedHumanReadableName", "")
        if human.startswith(f"gallery-{name}"):
            found.append(node.get("exportedFileName"))
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)
walk(manifest)
if not found:
    sys.exit(f"no gallery attachment for state {name}")
src = os.path.join(tmp, found[0])
dst = os.path.join(out, f"{name}.png")
shutil.copyfile(src, dst)
print(f"  saved {dst}")
PY
  rm -rf "$TMP_EXPORT"
done

echo "✅ layout gallery: $(ls "$OUT_DIR" | wc -l | tr -d ' ') shots in $OUT_DIR"
