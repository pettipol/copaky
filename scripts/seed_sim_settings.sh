#!/usr/bin/env bash
#
# seed_sim_settings.sh — put Copaky's keyboard settings into a KNOWN state on the Simulator.
#
# Why this script exists: on the Simulator the App Group is NOT provisioned, so the container app
# and the keyboard extension end up with SEPARATE "group.com.pettipol.copaky" domains — flipping a
# switch inside the app does NOT reach the keyboard. The domain the extension actually reads is the
# device-wide one:
#   ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/Preferences/group.com.pettipol.copaky.plist
# and `cfprefsd` is shared host<->simulator, so it must be flushed around the write (never use
# `simctl spawn <bundle> defaults write`: wrong domain, silently overwritten).
# On a real device none of this is needed — the App Group works and the app's own settings apply.
#
# It also TERMINATES the keyboard extension, on purpose: `KeyboardViewController.variableStates` is a
# process-level `static let`, so the extension keeps its TabManager (and therefore the tab the last
# test left it on, see TabManager.initialize/closeKeyboard) across host-app relaunches. Killing the
# process is what makes both the new settings and a clean tab take effect.
# 拡張は static な variableStates を持つためプロセスを終了させないと設定もタブも切り替わらない。
#
# Usage:
#   scripts/seed_sim_settings.sh keyboard_type=flick enable_italian_keyboard_language=true
#   scripts/seed_sim_settings.sh --udid <UDID> --delete keyboard_type_en
#   scripts/seed_sim_settings.sh --print            # just show the current device-wide domain
#
# Value typing: true/false -> bool, digits -> integer, anything else -> string.
# `keyboard_type` / `keyboard_type_en` (LanguageLayout) accept the legacy STRING values
# "flick" and "roman" — see LanguageLayoutKeyboardSetting.swift (StoredInUserDefault.get).
set -uo pipefail

UDID="${COPAKY_UDID:-E0552C62-FFDB-4DF6-9040-2734DB5B2458}"
GROUP_ID="group.com.pettipol.copaky"
KB_BUNDLE="com.pettipol.copaky.keyboard"
PB=/usr/libexec/PlistBuddy
PRINT_ONLY=0
KILL_KEYBOARD=1
declare -a PAIRS=()
declare -a DELETES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid) UDID="$2"; shift 2 ;;
    --delete) DELETES+=("$2"); shift 2 ;;
    --print) PRINT_ONLY=1; shift ;;
    --keep-keyboard) KILL_KEYBOARD=0; shift ;;   # leave the running extension alone (rarely wanted)
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *=*) PAIRS+=("$1"); shift ;;
    *) echo "ERROR: unknown argument '$1' (expected key=value, --delete key, --udid, --print)" >&2; exit 2 ;;
  esac
done

PLIST="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/Preferences/$GROUP_ID.plist"
if [[ ! -d "$HOME/Library/Developer/CoreSimulator/Devices/$UDID" ]]; then
  echo "ERROR: no simulator device directory for UDID $UDID" >&2
  exit 1
fi

if [[ "$PRINT_ONLY" == 1 ]]; then
  echo "Domain: $PLIST"
  [[ -f "$PLIST" ]] && plutil -p "$PLIST" || echo "(does not exist yet)"
  exit 0
fi

if [[ ${#PAIRS[@]} -eq 0 && ${#DELETES[@]} -eq 0 ]]; then
  echo "ERROR: nothing to do — pass key=value pairs, --delete key, or --print" >&2
  exit 2
fi

# cfprefsd caches this file for BOTH host and simulator: flush before touching it, or the daemon
# rewrites our edit from its cache. / 書き込み前後に必ずフラッシュする。
killall cfprefsd 2>/dev/null || true
sleep 0.3

mkdir -p "$(dirname "$PLIST")"
[[ -f "$PLIST" ]] || $PB -c "Save" "$PLIST" >/dev/null 2>&1 || plutil -create xml1 "$PLIST"

plist_type() {
  case "$1" in
    true|false) echo bool ;;
    ''|*[!0-9]*) echo string ;;
    *) echo integer ;;
  esac
}

# macOS ships bash 3.2, where "${arr[@]}" on an EMPTY array trips `set -u` — hence the length guards.
for key in ${DELETES[@]+"${DELETES[@]}"}; do
  $PB -c "Delete :$key" "$PLIST" >/dev/null 2>&1 || true
  echo "deleted  $key"
done

for pair in ${PAIRS[@]+"${PAIRS[@]}"}; do
  key="${pair%%=*}"
  value="${pair#*=}"
  type="$(plist_type "$value")"
  # Delete first: an existing entry of a DIFFERENT type (LanguageLayout is also stored as Data by the
  # app itself) would make `Set` fail. / 型が違うとSetが失敗するので必ず削除してから追加する。
  $PB -c "Delete :$key" "$PLIST" >/dev/null 2>&1 || true
  if ! $PB -c "Add :$key $type $value" "$PLIST" >/dev/null 2>&1; then
    echo "ERROR: could not write $key ($type $value) into $PLIST" >&2
    exit 1
  fi
  echo "set      $key = $value ($type)"
done

# A build installed via `simctl install` (unsigned, no App Group) resolves the suite to the
# extension's OWN PluginKitPlugin container, not the device-wide domain — mirror every write
# there too, or manual (non-runner) sessions read stale values. Found empirically 2026-08-13.
# simctlインストール版は拡張自身のコンテナ側を読むため、そちらにも同じ値を書き込む。
PLUGIN_BASE="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Data/PluginKitPlugin"
if [[ -d "$PLUGIN_BASE" ]]; then
  for d in "$PLUGIN_BASE"/*/; do
    M="$d.com.apple.mobile_container_manager.metadata.plist"
    [[ -f "$M" ]] || continue
    if $PB -c "Print :MCMMetadataIdentifier" "$M" 2>/dev/null | grep -q "copaky"; then
      CP="$d/Library/Preferences/$GROUP_ID.plist"
      mkdir -p "$(dirname "$CP")"
      [[ -f "$CP" ]] || plutil -create xml1 "$CP" 2>/dev/null || true
      for key in ${DELETES[@]+"${DELETES[@]}"}; do
        $PB -c "Delete :$key" "$CP" >/dev/null 2>&1 || true
      done
      for pair in ${PAIRS[@]+"${PAIRS[@]}"}; do
        key="${pair%%=*}"; value="${pair#*=}"; type="$(plist_type "$value")"
        $PB -c "Delete :$key" "$CP" >/dev/null 2>&1 || true
        $PB -c "Add :$key $type $value" "$CP" >/dev/null 2>&1 || true
      done
      echo "mirrored into extension container: $CP"
    fi
  done
fi

killall cfprefsd 2>/dev/null || true
sleep 0.3

if [[ "$KILL_KEYBOARD" == 1 ]]; then
  # The extension re-reads its settings (and rebuilds the static VariableStates, so the tab goes back
  # to the Japanese default) only on a fresh process. `simctl terminate` does NOT kill keyboard
  # extensions (it silently reports "not running") — the process is named `Keyboard` with the appex
  # path, so kill it by path. / simctl terminateは拡張には効かない：バイナリパスでkillする。
  if pkill -f "$UDID.*azooKey.app/PlugIns/Keyboard.appex/Keyboard" 2>/dev/null; then
    echo "killed the running keyboard extension process (settings + tab state re-read on next load)"
  else
    xcrun simctl terminate "$UDID" "$KB_BUNDLE" >/dev/null 2>&1 || true
    echo "note: keyboard extension was not running (nothing to kill)"
  fi
fi

echo "── device-wide domain now ──"
plutil -p "$PLIST"
