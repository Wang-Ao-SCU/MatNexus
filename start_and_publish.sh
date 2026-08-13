#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
CHAPTER_DIR="${MATNEXUS_CHAPTER_DIR:-/media/wang/58AFBE741F4D5555/第四章}"
PUBLISH_REPO="${MATNEXUS_PUBLISH_REPO:-$BASE_DIR}"
CLOUDFLARED="${CLOUDFLARED:-$CHAPTER_DIR/.local_tools/cloudflared}"
LOG_DIR="$BASE_DIR/logs"
SITE_DIR="$BASE_DIR/site"
mkdir -p "$LOG_DIR" "$SITE_DIR"

if curl -fsS -I http://127.0.0.1:8501 >/dev/null 2>&1; then
  echo "INTERNAL_STATUS=ALREADY_RUNNING"
else
  echo "INTERNAL_STATUS=STARTING"
  (
    cd "$CHAPTER_DIR"
    PYTHONPATH=.:conditional_formula_diffusion:unsupervised_autocg_formula:auto_pu_mlp \
      streamlit run conditional_formula_diffusion/ui_hotpot_app.py \
      --server.address 0.0.0.0 \
      --server.port 8501 \
      --server.headless true \
      --browser.gatherUsageStats false
  ) >"$LOG_DIR/streamlit.log" 2>&1 &
  echo "$!" > "$LOG_DIR/streamlit.pid"
  for _ in $(seq 1 30); do
    curl -fsS -I http://127.0.0.1:8501 >/dev/null 2>&1 && break
    sleep 1
  done
fi

curl -fsS -I http://127.0.0.1:8501 >/dev/null 2>&1 || { echo "INTERNAL_STATUS=FAILED"; exit 1; }
echo "INTERNAL_URL=http://127.0.0.1:8501"

[ -x "$CLOUDFLARED" ] || { echo "EXTERNAL_STATUS=FAILED_CLOUDFLARED_MISSING"; exit 1; }
: > "$LOG_DIR/cloudflared.log"
"$CLOUDFLARED" tunnel --url http://127.0.0.1:8501 --no-autoupdate >"$LOG_DIR/cloudflared.log" 2>&1 &
TUNNEL_PID=$!
echo "$TUNNEL_PID" > "$LOG_DIR/cloudflared.pid"

EXTERNAL_URL=""
for _ in $(seq 1 60); do
  EXTERNAL_URL="$(grep -Eo 'https://[-a-zA-Z0-9.]+\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" | tail -n 1 || true)"
  [ -n "$EXTERNAL_URL" ] && break
  sleep 1
done

[ -n "$EXTERNAL_URL" ] || { echo "EXTERNAL_STATUS=FAILED_NO_URL"; exit 1; }
echo "EXTERNAL_STATUS=SUCCESS"
echo "EXTERNAL_URL=$EXTERNAL_URL"

if python "$BASE_DIR/scripts/update_distribution_page.py" --url "$EXTERNAL_URL" --site-dir "$SITE_DIR" --publish-repo "$PUBLISH_REPO" --publish-subdir . --push; then
  echo "DISTRIBUTION_PUBLISH=SUCCESS"
  echo "DISTRIBUTION_PAGE=https://wang-ao-scu.github.io/MatNexus/"
else
  echo "DISTRIBUTION_PUBLISH=FAILED"
  exit 1
fi

echo "CLOUDFLARED_PID=$TUNNEL_PID"
echo "Keep this process running while external users need access."
wait "$TUNNEL_PID"
