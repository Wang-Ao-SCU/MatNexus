#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
CHAPTER_DIR="${MATNEXUS_CHAPTER_DIR:-/media/wang/58AFBE741F4D5555/第四章}"
PUBLISH_REPO="${MATNEXUS_PUBLISH_REPO:-$BASE_DIR}"
CLOUDFLARED="${CLOUDFLARED:-$CHAPTER_DIR/.local_tools/cloudflared}"
LOG_DIR="$BASE_DIR/logs"
SITE_DIR="$BASE_DIR/site"
mkdir -p "$LOG_DIR" "$SITE_DIR"

is_alive() {
  local pid_file="$1"
  [ -f "$pid_file" ] || return 1
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

start_streamlit() {
  echo "INTERNAL_STATUS=STARTING"
  (
    cd "$CHAPTER_DIR"
    nohup env PYTHONPATH=.:conditional_formula_diffusion:unsupervised_autocg_formula:auto_pu_mlp \
      streamlit run conditional_formula_diffusion/ui_hotpot_app.py \
      --server.address 0.0.0.0 \
      --server.port 8501 \
      --server.headless true \
      --browser.gatherUsageStats false \
      >"$LOG_DIR/streamlit.log" 2>&1 &
    echo $! > "$LOG_DIR/streamlit.pid"
  )
}

start_cloudflared() {
  [ -x "$CLOUDFLARED" ] || { echo "EXTERNAL_STATUS=FAILED_CLOUDFLARED_MISSING"; exit 1; }
  : > "$LOG_DIR/cloudflared.log"
  nohup "$CLOUDFLARED" tunnel --url http://127.0.0.1:8501 --protocol http2 --no-autoupdate \
    >"$LOG_DIR/cloudflared.log" 2>&1 &
  echo $! > "$LOG_DIR/cloudflared.pid"
}

if curl -fsS -I http://127.0.0.1:8501 >/dev/null 2>&1; then
  echo "INTERNAL_STATUS=ALREADY_RUNNING"
else
  start_streamlit
fi

for _ in $(seq 1 45); do
  curl -fsS -I http://127.0.0.1:8501 >/dev/null 2>&1 && break
  sleep 1
done

if ! curl -fsS -I http://127.0.0.1:8501 >/dev/null 2>&1; then
  echo "INTERNAL_STATUS=FAILED"
  echo "See $LOG_DIR/streamlit.log"
  exit 1
fi

echo "INTERNAL_URL=http://127.0.0.1:8501"

# A quick Cloudflare tunnel can become stale after the terminal dies. Always
# create a fresh tunnel for each publish run.
if is_alive "$LOG_DIR/cloudflared.pid"; then
  kill "$(cat "$LOG_DIR/cloudflared.pid")" >/dev/null 2>&1 || true
  sleep 1
fi
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

# Wait until the public URL can actually reach the local Streamlit backend.
EXTERNAL_OK=0
for _ in $(seq 1 45); do
  if curl -fsS -I "$EXTERNAL_URL" >/dev/null 2>&1; then
    EXTERNAL_OK=1
    break
  fi
  sleep 2
done

if [ "$EXTERNAL_OK" -ne 1 ]; then
  echo "EXTERNAL_STATUS=FAILED_HEALTH_CHECK"
  echo "EXTERNAL_URL=$EXTERNAL_URL"
  echo "See $LOG_DIR/cloudflared.log"
  exit 1
fi

echo "EXTERNAL_STATUS=SUCCESS"
echo "EXTERNAL_URL=$EXTERNAL_URL"

if python "$BASE_DIR/scripts/update_distribution_page.py" --url "$EXTERNAL_URL" --site-dir "$SITE_DIR" --publish-repo "$PUBLISH_REPO" --publish-subdir . --push; then
  echo "DISTRIBUTION_PUBLISH=SUCCESS"
  echo "DISTRIBUTION_PAGE=https://wang-ao-scu.github.io/MatNexus/"
else
  echo "DISTRIBUTION_PUBLISH=FAILED"
  exit 1
fi

echo "STREAMLIT_PID=$(cat "$LOG_DIR/streamlit.pid" 2>/dev/null || echo existing)"
echo "CLOUDFLARED_PID=$(cat "$LOG_DIR/cloudflared.pid")"
echo "MatNexus is running in the background. Stop it with: bash stop_matnexus_public.sh"
