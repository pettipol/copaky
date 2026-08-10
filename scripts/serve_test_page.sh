#!/usr/bin/env bash
# Copaky — serve the XCUITest field fixture on 127.0.0.1:8377.
# The UI campaign (MainAppUITests) drives Safari against http://127.0.0.1:8377/kbtest.html;
# without this server every field-based test fails at "Safari webview did not load".
#
# Usage:
#   scripts/serve_test_page.sh            start in the foreground (Ctrl-C to stop)
#   scripts/serve_test_page.sh --daemon   start in the background, print the PID
#   scripts/serve_test_page.sh --stop     stop a background instance
#
# iOS 26 gotcha: Safari ignores the "-u" launch argument, so the ORCHESTRATOR must also
# pre-navigate the simulator before running a test that uses activatePreNavigatedField:
#   xcrun simctl openurl booted http://127.0.0.1:8377/kbtest.html
set -uo pipefail
PORT=8377
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../MainAppUITests/Fixtures" && pwd)"
PIDFILE="${TMPDIR:-/tmp}/copaky-test-page.pid"

case "${1:-}" in
  --stop)
    if [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "server stopped (pid $(cat "$PIDFILE"))"
    else
      echo "no running server found; freeing port $PORT anyway"
      lsof -ti :$PORT | xargs -r kill 2>/dev/null
    fi
    rm -f "$PIDFILE"
    ;;
  --daemon)
    if lsof -ti :$PORT >/dev/null 2>&1; then
      echo "port $PORT already serving — reusing it"
      exit 0
    fi
    python3 -m http.server $PORT --bind 127.0.0.1 --directory "$DIR" >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
    sleep 0.5
    echo "serving $DIR on http://127.0.0.1:$PORT (pid $(cat "$PIDFILE"))"
    ;;
  *)
    echo "serving $DIR on http://127.0.0.1:$PORT — Ctrl-C to stop"
    exec python3 -m http.server $PORT --bind 127.0.0.1 --directory "$DIR"
    ;;
esac
