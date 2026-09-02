#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
STATUS_JSON="$BASE_DIR/status.json"
INTERVAL="${MATNEXUS_WATCH_INTERVAL:-120}"
RECHECK_DELAY="${MATNEXUS_WATCH_RECHECK_DELAY:-20}"
RECHECKS="${MATNEXUS_WATCH_RECHECKS:-3}"
mkdir -p "$LOG_DIR"

echo $$ > "$LOG_DIR/watchdog.pid"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_DIR/healthcheck.log" >/dev/null
}

json_status() {
  local local_status="$1"
  local tunnel_status="$2"
  local distribution_status="$3"
  local current_url="$4"
  local action="$5"
  cat > "$LOG_DIR/current_status.json" <<EOF
{
  "checked_at": "$(date '+%Y-%m-%d %H:%M:%S')",
  "local_status": "$local_status",
  "tunnel_status": "$tunnel_status",
  "distribution_status": "$distribution_status",
  "current_url": "$current_url",
  "action": "$action",
  "watch_interval_seconds": $INTERVAL
}
EOF
}

curl_head() {
  curl --noproxy "*" -fsS -I "$1" >/dev/null 2>&1
}

pid_alive() {
  local pid_file="$1"
  [ -f "$pid_file" ] || return 1
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

current_url() {
  if [ -f "$STATUS_JSON" ]; then
    python - "$STATUS_JSON" <<'PY' 2>/dev/null || true
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    print(json.load(handle).get("current_url", ""))
PY
  fi
}

check_once() {
  local url="$1"
  local local_ok=FAIL
  local tunnel_ok=FAIL
  local dist_ok=SKIP

  curl_head http://127.0.0.1:8501 && local_ok=PASS
  pid_alive "$LOG_DIR/cloudflared.pid" && tunnel_ok=PASS
  if [ -n "$url" ]; then
    curl_head "$url" && dist_ok=PASS || dist_ok=FAIL
  fi

  echo "$local_ok $tunnel_ok $dist_ok"
}

needs_restart() {
  local result="$1"
  [ "$result" = "PASS PASS PASS" ] && return 1
  return 0
}

log "WATCHDOG_STARTED interval=${INTERVAL}s rechecks=${RECHECKS} recheck_delay=${RECHECK_DELAY}s"

while true; do
  url="$(current_url)"
  result="$(check_once "$url")"
  read -r local_status tunnel_status distribution_status <<< "$result"

  if ! needs_restart "$result"; then
    log "HEALTH=PASS url=$url"
    json_status "$local_status" "$tunnel_status" "$distribution_status" "$url" "none"
    sleep "$INTERVAL"
    continue
  fi

  confirmed_fail=0
  for _ in $(seq 1 "$RECHECKS"); do
    sleep "$RECHECK_DELAY"
    url="$(current_url)"
    result="$(check_once "$url")"
    if ! needs_restart "$result"; then
      confirmed_fail=0
      break
    fi
    confirmed_fail=1
  done

  read -r local_status tunnel_status distribution_status <<< "$result"
  if [ "$confirmed_fail" = "1" ]; then
    log "HEALTH=FAIL local=$local_status tunnel=$tunnel_status distribution=$distribution_status url=$url action=restart"
    json_status "$local_status" "$tunnel_status" "$distribution_status" "$url" "restart"
    MATNEXUS_SKIP_WATCHDOG=1 MATNEXUS_WATCH_INTERVAL="$INTERVAL" bash "$BASE_DIR/start_and_publish.sh" >> "$LOG_DIR/watchdog_restart.log" 2>&1 || true
  else
    log "HEALTH=PASS_AFTER_RECHECK url=$url"
    json_status "$local_status" "$tunnel_status" "$distribution_status" "$url" "none"
  fi

  sleep "$INTERVAL"
done
