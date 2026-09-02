#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
CHAPTER_DIR="${MATNEXUS_CHAPTER_DIR:-/media/wang/58AFBE741F4D5555/第四章}"
PUBLISH_REPO="${MATNEXUS_PUBLISH_REPO:-$BASE_DIR}"
CLOUDFLARED="${CLOUDFLARED:-$CHAPTER_DIR/.local_tools/cloudflared}"
LOG_DIR="$BASE_DIR/logs"
SITE_DIR="$BASE_DIR/site"
WATCHDOG_INTERVAL="${MATNEXUS_WATCH_INTERVAL:-120}"
mkdir -p "$LOG_DIR" "$SITE_DIR"

is_alive() {
  local pid_file="$1"
  [ -f "$pid_file" ] || return 1
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

stop_pid_file() {
  local pid_file="$1"
  if is_alive "$pid_file"; then
    kill "$(cat "$pid_file")" >/dev/null 2>&1 || true
    sleep 1
  fi
}

curl_head() {
  curl --noproxy "*" -fsS -I "$1" >/dev/null 2>&1
}

detect_8501_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -ti :8501 2>/dev/null | head -n 1 || true
  fi
}

stop_all_cloudflared() {
  pkill -f "cloudflared tunnel --url http://127.0.0.1:8501" >/dev/null 2>&1 || true
  sleep 1
}

start_streamlit() {
  echo "INTERNAL_STATUS=STARTING"
  setsid bash -lc "
    cd '$CHAPTER_DIR'
    PYTHONPATH=.:conditional_formula_diffusion:unsupervised_autocg_formula:auto_pu_mlp \
      exec streamlit run conditional_formula_diffusion/ui_hotpot_app.py \
      --server.address 0.0.0.0 \
      --server.port 8501 \
      --server.headless true \
      --browser.gatherUsageStats false
  " >"$LOG_DIR/streamlit.log" 2>&1 < /dev/null &
  echo $! > "$LOG_DIR/streamlit.pid"
}

start_cloudflared() {
  [ -x "$CLOUDFLARED" ] || { echo "EXTERNAL_STATUS=FAILED_CLOUDFLARED_MISSING"; exit 1; }
  : > "$LOG_DIR/cloudflared.log"
  setsid "$CLOUDFLARED" tunnel --url http://127.0.0.1:8501 --protocol http2 --no-autoupdate \
    >"$LOG_DIR/cloudflared.log" 2>&1 < /dev/null &
  echo $! > "$LOG_DIR/cloudflared.pid"
}

cleanup() {
  echo "START_SCRIPT_INTERRUPTED=TRUE"
  echo "Use ./stop_matnexus_public.sh if you want to stop MatNexus."
}
trap cleanup INT TERM

STREAMLIT_STARTED=0
if curl_head http://127.0.0.1:8501; then
  echo "INTERNAL_STATUS=ALREADY_RUNNING"
  existing_streamlit_pid="$(detect_8501_pid)"
  if [ -n "$existing_streamlit_pid" ]; then
    echo "$existing_streamlit_pid" > "$LOG_DIR/streamlit.pid"
  fi
else
  start_streamlit
  STREAMLIT_STARTED=1
fi

for _ in $(seq 1 60); do
  curl_head http://127.0.0.1:8501 && break
  sleep 1
done

if ! curl_head http://127.0.0.1:8501; then
  echo "INTERNAL_STATUS=FAILED"
  echo "See $LOG_DIR/streamlit.log"
  exit 1
fi

echo "INTERNAL_URL=http://127.0.0.1:8501"

# Always use a fresh quick tunnel URL.
stop_pid_file "$LOG_DIR/cloudflared.pid"
stop_all_cloudflared
start_cloudflared

EXTERNAL_URL=""
for _ in $(seq 1 60); do
  EXTERNAL_URL="$(grep -Eo 'https://[-a-zA-Z0-9.]+\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" | tail -n 1 || true)"
  [ -n "$EXTERNAL_URL" ] && break
  sleep 1
done

if [ -z "$EXTERNAL_URL" ]; then
  echo "EXTERNAL_STATUS=FAILED_NO_URL"
  echo "See $LOG_DIR/cloudflared.log"
  exit 1
fi

if ! is_alive "$LOG_DIR/cloudflared.pid"; then
  echo "EXTERNAL_STATUS=FAILED_TUNNEL_EXITED"
  echo "EXTERNAL_URL=$EXTERNAL_URL"
  echo "See $LOG_DIR/cloudflared.log"
  exit 1
fi

echo "EXTERNAL_STATUS=STARTED"
echo "EXTERNAL_URL=$EXTERNAL_URL"

# DNS propagation of quick tunnels can lag. Do not terminate the tunnel just
# because this local health check is slow; report the check result instead.
if curl_head "$EXTERNAL_URL"; then
  echo "EXTERNAL_HEALTH=PASS"
else
  echo "EXTERNAL_HEALTH=WAIT_OR_CHECK_FROM_BROWSER"
fi

if python "$BASE_DIR/scripts/update_distribution_page.py" --url "$EXTERNAL_URL" --site-dir "$SITE_DIR" --publish-repo "$PUBLISH_REPO" --publish-subdir . --push; then
  echo "DISTRIBUTION_PUBLISH=SUCCESS"
  echo "DISTRIBUTION_PAGE=https://wang-ao-scu.github.io/MatNexus/"
else
  echo "DISTRIBUTION_PUBLISH=FAILED"
  exit 1
fi

echo "STREAMLIT_PID=$(cat "$LOG_DIR/streamlit.pid" 2>/dev/null || echo existing)"
echo "CLOUDFLARED_PID=$(cat "$LOG_DIR/cloudflared.pid")"
if [ "${MATNEXUS_SKIP_WATCHDOG:-0}" != "1" ] && [ -x "$BASE_DIR/watch_matnexus_public.sh" ]; then
  if [ -f "$LOG_DIR/watchdog.pid" ] && kill -0 "$(cat "$LOG_DIR/watchdog.pid" 2>/dev/null)" >/dev/null 2>&1; then
    echo "WATCHDOG_STATUS=ALREADY_RUNNING"
  else
    setsid bash -lc "MATNEXUS_WATCH_INTERVAL='$WATCHDOG_INTERVAL' exec '$BASE_DIR/watch_matnexus_public.sh'" \
      >"$LOG_DIR/watchdog.log" 2>&1 < /dev/null &
    echo $! > "$LOG_DIR/watchdog.pid"
    echo "WATCHDOG_STATUS=STARTED"
    echo "WATCHDOG_INTERVAL_SECONDS=$WATCHDOG_INTERVAL"
  fi
fi
echo "MatNexus is running in the background."
echo "You may close this terminal. Use ./stop_matnexus_public.sh to stop the public tunnel."
