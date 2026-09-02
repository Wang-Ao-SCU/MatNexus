#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
STATUS_JSON="$BASE_DIR/status.json"
INTERVAL_SECONDS="${MATNEXUS_MONITOR_INTERVAL:-3600}"
RECHECKS="${MATNEXUS_MONITOR_RECHECKS:-2}"
RECHECK_DELAY="${MATNEXUS_MONITOR_RECHECK_DELAY:-30}"
CONNECT_TIMEOUT="${MATNEXUS_MONITOR_CONNECT_TIMEOUT:-20}"
MAX_TIME="${MATNEXUS_MONITOR_MAX_TIME:-60}"
mkdir -p "$LOG_DIR"

MONITOR_PID_FILE="$LOG_DIR/hourly_monitor.pid"
MONITOR_LOG="$LOG_DIR/hourly_monitor.log"
echo $$ > "$MONITOR_PID_FILE"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$MONITOR_LOG" >/dev/null
}

current_url() {
  if [ -f "$STATUS_JSON" ]; then
    python - "$STATUS_JSON" <<'PY' 2>/dev/null || true
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    print(json.load(handle).get("current_url", ""))
PY
  fi
}

public_ok() {
  local url="$1"
  [ -n "$url" ] || return 1
  curl -L --fail -I \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    "$url" >/dev/null 2>&1
}

restart_matnexus() {
  log "RESTART_BEGIN"
  bash "$BASE_DIR/stop_matnexus_public.sh" >> "$MONITOR_LOG" 2>&1 || true
  bash "$BASE_DIR/start_and_publish.sh" >> "$MONITOR_LOG" 2>&1
  log "RESTART_END current_url=$(current_url)"
}

check_and_recover() {
  local url
  url="$(current_url)"
  if public_ok "$url"; then
    log "HEALTH=PASS url=$url"
    return 0
  fi

  log "HEALTH=FAIL_INITIAL url=${url:-EMPTY}"
  for _ in $(seq 1 "$RECHECKS"); do
    sleep "$RECHECK_DELAY"
    url="$(current_url)"
    if public_ok "$url"; then
      log "HEALTH=PASS_AFTER_RECHECK url=$url"
      return 0
    fi
    log "HEALTH=FAIL_RECHECK url=${url:-EMPTY}"
  done

  restart_matnexus
}

log "HOURLY_MONITOR_STARTED interval=${INTERVAL_SECONDS}s rechecks=${RECHECKS} recheck_delay=${RECHECK_DELAY}s"

if [ "${1:-}" = "--once" ]; then
  check_and_recover
  exit 0
fi

while true; do
  check_and_recover
  sleep "$INTERVAL_SECONDS"
done
