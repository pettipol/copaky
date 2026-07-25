#!/usr/bin/env bash
#
# seed_sim_clipboard.sh — seed the Copaky App Group container on the Simulator
# with a tab bar that includes the clipboard tab + a realistic clipboard history,
# so the store-screenshot suite can show the REAL clipboard tab.
#
# The container is only reachable by the SIGNED keyboard extension (the container
# app loses the App Groups entitlement on the Simulator). This script writes the
# files the extension reads:
#   <group>/custard/tabbar_0.tabbar   — tab bar WITH the pinned clipboard tab
#   <group>/clipboard_history.json    — demo history (EN or JA)
#
# JSON layout verified against the real CustardKit/AzooKeyCore Codable types
# (round-trip decode) — see the task report. A malformed tab bar would make the
# keyboard SILENTLY fall back to the default (no clipboard tab), so the format
# here must match exactly.
#
# Usage: seed_sim_clipboard.sh --lang en|ja [--udid <UDID>]
# Exits non-zero (with a clear message) if the container does not exist — that
# means the keyboard extension has never run, so run the warmup first.

set -euo pipefail

LANG_ARG="en"
UDID="${COPAKY_UDID:-E0552C62-FFDB-4DF6-9040-2734DB5B2458}"
GROUP_ID="group.com.pettipol.copaky"
KB_BUNDLE="com.pettipol.copaky.keyboard"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang) LANG_ARG="$2"; shift 2 ;;
    --udid) UDID="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ "$LANG_ARG" != "en" && "$LANG_ARG" != "ja" ]]; then
  echo "ERROR: --lang must be 'en' or 'ja' (got '$LANG_ARG')" >&2
  exit 2
fi

# --- locate the shared App Group container --------------------------------------
find_container() {
  # 1) authoritative: ask simctl
  local c
  if c="$(xcrun simctl get_app_container "$UDID" "$KB_BUNDLE" "$GROUP_ID" 2>/dev/null)"; then
    if [[ -n "$c" && -d "$c" ]]; then
      printf '%s' "$c"
      return 0
    fi
  fi
  # 2) fallback: scan the AppGroup metadata plists for MCMMetadataIdentifier
  local base="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Shared/AppGroup"
  [[ -d "$base" ]] || return 1
  local meta id dir
  for meta in "$base"/*/.com.apple.mobile_container_manager.metadata.plist; do
    [[ -f "$meta" ]] || continue
    id="$(/usr/libexec/PlistBuddy -c 'Print :MCMMetadataIdentifier' "$meta" 2>/dev/null || true)"
    if [[ "$id" == "$GROUP_ID" ]]; then
      dir="$(dirname "$meta")"
      printf '%s' "$dir"
      return 0
    fi
  done
  return 1
}

CONTAINER="$(find_container || true)"
if [[ -z "${CONTAINER:-}" || ! -d "$CONTAINER" ]]; then
  cat >&2 <<EOF
ERROR: App Group container '$GROUP_ID' not found for keyboard '$KB_BUNDLE' on
simulator $UDID.
This means the SIGNED keyboard extension has never run (the container is created
on first keyboard launch with Full Access). Run the warmup step first:
  - enable the keyboard + Full Access, then launch the keyboard once
    (store_screenshots.sh does this automatically before seeding).
EOF
  exit 1
fi

echo "Container: $CONTAINER"
mkdir -p "$CONTAINER/custard"

TABBAR_FILE="$CONTAINER/custard/tabbar_0.tabbar"
HISTORY_FILE="$CONTAINER/clipboard_history.json"

# --- write the two files with correct, round-trip-verified JSON -----------------
COPAKY_LANG="$LANG_ARG" \
COPAKY_TABBAR="$TABBAR_FILE" \
COPAKY_HISTORY="$HISTORY_FILE" \
/usr/bin/python3 - <<'PY'
import json, os, time

lang = os.environ["COPAKY_LANG"]
tabbar_path = os.environ["COPAKY_TABBAR"]
history_path = os.environ["COPAKY_HISTORY"]

# Date() is encoded by JSONEncoder as seconds since the 2001-01-01 reference date.
ref = time.time() - 978307200.0

def sysmove(identifier):
    return {"type": "move_tab", "tab_type": "system", "identifier": identifier}

# tab bar: default items + the pinned clipboard tab (doc.badge.clock).
# Structure verified to decode to TabBarData with hasClipboardTab == true.
tabbar = {
    "identifier": 0,
    "lastUpdateDate": ref,
    "items": [
        {"pinned": True,  "label": {"image": "keyboard.chevron.compact.down"}, "actions": [{"type": "dismiss_keyboard"}]},
        {"pinned": True,  "label": {"image": "aspectratio"},                   "actions": [{"type": "enable_resizing_mode"}, {"type": "toggle_tab_bar"}]},
        {"pinned": True,  "label": {"image": "face.smiling"},                  "actions": [sysmove("emoji_tab")]},
        {"pinned": True,  "label": {"image": "doc.badge.clock"},               "actions": [sysmove("clipboard_history_tab")]},
        {"pinned": False, "label": {"text": "あいう"},            "actions": [sysmove("user_japanese")]},
        {"pinned": False, "label": {"text": "ABC"},                            "actions": [sysmove("user_english")]},
    ],
}

# clipboard history: realistic, sober, no real personal data. One pinned item.
# Every language includes the demo OTP 482913 (canary for the seeding).
if lang == "ja":
    entries = [
        # (text, created-age-seconds, pinned-age-seconds or None)
        ("送り先: 東京都千代田区丸の内１-９-１", 400, 40),
        ("確認コードは 482913 です", 90, None),
        ("https://copaky.app/demo", 180, None),
        ("今週どこかでお茶しませんか。", 260, None),
    ]
else:
    entries = [
        ("Ship to: 350 Fifth Ave, New York, NY 10118", 400, 40),
        ("Your verification code is 482913", 90, None),
        ("https://copaky.app/demo", 180, None),
        ("Let's catch up over coffee this week.", 260, None),
    ]

items = []
for text, created_age, pinned_age in entries:
    it = {"content": {"text": {"_0": text}}, "createdData": ref - created_age}
    if pinned_age is not None:
        it["pinnedDate"] = ref - pinned_age
    items.append(it)

with open(tabbar_path, "w", encoding="utf-8") as f:
    json.dump(tabbar, f, ensure_ascii=False)
with open(history_path, "w", encoding="utf-8") as f:
    json.dump(items, f, ensure_ascii=False)

print("wrote", tabbar_path)
print("wrote", history_path, "(%d items, lang=%s)" % (len(items), lang))
PY

echo "Seed complete for lang=$LANG_ARG"
