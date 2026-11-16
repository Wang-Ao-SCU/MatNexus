#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
STATUS_JSON="$BASE_DIR/status.json"
INTERVAL_SECONDS="${MATNEXUS_MONITOR_INTERVAL:-600}"
RECHECKS="${MATNEXUS_MONITOR_RECHECKS:-2}"
RECHECK_DELAY="${MATNEXUS_MONITOR_RECHECK_DELAY:-30}"
CONNECT_TIMEOUT="${MATNEXUS_MONITOR_CONNECT_TIMEOUT:-20}"
MAX_TIME="${MATNEXUS_MONITOR_MAX_TIME:-60}"
LIVE="${MATNEXUS_MONITOR_LIVE:-0}"
mkdir -p "$LOG_DIR"

MONITOR_PID_FILE="$LOG_DIR/hourly_monitor.pid"
MONITOR_LOG="$LOG_DIR/hourly_monitor.log"
echo $$ > "$MONITOR_PID_FILE"

cleanup_pid() {
  if [ -f "$MONITOR_PID_FILE" ] && [ "$(cat "$MONITOR_PID_FILE" 2>/dev/null || true)" = "$$" ]; then
    rm -f "$MONITOR_PID_FILE"
  fi
}
trap cleanup_pid EXIT INT TERM

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$MONITOR_LOG"
}

sleep_until_next_check() {
  local remain="$INTERVAL_SECONDS"
  local step=60
  while [ "$remain" -gt 0 ]; do
    if [ "$LIVE" = "1" ]; then
      log "WAIT next_check_in=${remain}s"
    fi
    if [ "$remain" -lt "$step" ]; then
      sleep "$remain"
      remain=0
    else
      sleep "$step"
      remain=$((remain - step))
    fi
  done
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
  bash "$BASE_DIR/stop_matnexus_public.sh" 2>&1 | tee -a "$MONITOR_LOG" || true
  if bash "$BASE_DIR/start_and_publish.sh" 2>&1 | tee -a "$MONITOR_LOG"; then
    log "RESTART_END status=PASS current_url=$(current_url)"
  else
    log "RESTART_END status=FAILED; monitor will continue current_url=$(current_url)"
  fi
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
  sleep_until_next_check
done
