#!/bin/bash
# TestFlight upload for Copaky — archive → export → upload, driven by the ASC API key.
# TestFlightへのアップロード（アーカイブ→エクスポート→API키でアップロード）。
#
# Requirements (all fail-loud below):
#   - signing team in $COPAKY_TEAM or Copaky.local.xcconfig (never committed);
#   - ASC API key env at ~/.config/copaky/asc.env (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH);
#   - a UNIQUE CURRENT_PROJECT_VERSION per upload (ASC rejects reuse).
# Never touches "Add for Review" — upload only.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${COPAKY_ARCHIVE_DIR:-$HOME/copaky_release}"
STAMP="$(date +%Y%m%d_%H%M)"
ARCHIVE="$OUT_DIR/Copaky_$STAMP.xcarchive"

TEAM="${COPAKY_TEAM:-$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' "$REPO_DIR/Copaky.local.xcconfig" 2>/dev/null | head -n1)}"
if [ -z "$TEAM" ]; then
  echo "FATAL: no signing team — set COPAKY_TEAM or create $REPO_DIR/Copaky.local.xcconfig with: DEVELOPMENT_TEAM = <your team id>" >&2
  exit 1
fi

ASC_ENV="${COPAKY_ASC_ENV:-$HOME/.config/copaky/asc.env}"
if [ ! -f "$ASC_ENV" ]; then
  echo "FATAL: ASC env not found at $ASC_ENV (needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH)" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ASC_ENV"
for v in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
  if [ -z "${!v:-}" ]; then echo "FATAL: $v missing in $ASC_ENV" >&2; exit 1; fi
done
if [ ! -f "$ASC_KEY_PATH" ]; then echo "FATAL: ASC key file not found at $ASC_KEY_PATH" >&2; exit 1; fi

mkdir -p "$OUT_DIR"

echo "== 1/3 archive (Release, generic iOS) → $ARCHIVE"
xcodebuild archive \
  -project "$REPO_DIR/azooKey.xcodeproj" -scheme MainApp \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" -quiet

# Export options live OUTSIDE the repo: they carry the team id, which stays untracked.
EXPORT_PLIST="$OUT_DIR/ExportOptions_$STAMP.plist"
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>$TEAM</string>
    <key>uploadSymbols</key><true/>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "== 2/3 export+upload (destination=upload → straight to App Store Connect)"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "== 3/3 done — build uploaded; ASC will email when processing finishes."
echo "Archive kept at: $ARCHIVE"
