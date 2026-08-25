#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AgentTracker"
BUNDLE_ID="com.revolt.koogo"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

case "$MODE" in
  run|debug|logs|telemetry|verify) ;;
  *) echo "usage: $0 [run|debug|logs|telemetry|verify]" >&2; exit 2 ;;
esac

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
"$ROOT_DIR/script/build.sh"

case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  debug) lldb -- "$APP_BINARY" ;;
  logs)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
esac
