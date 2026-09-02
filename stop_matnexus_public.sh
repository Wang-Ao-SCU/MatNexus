#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
for name in watchdog cloudflared streamlit; do
  pid_file="$BASE_DIR/logs/$name.pid"
  if [ -f "$pid_file" ]; then
    pid="$(cat "$pid_file")"
    if [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1; then
      kill -- "-$pid" >/dev/null 2>&1 || kill "$pid" || true
      echo "Stopped $name PID $pid"
    fi
  fi
done

if command -v lsof >/dev/null 2>&1; then
  for pid in $(lsof -ti :8501 2>/dev/null || true); do
    kill "$pid" >/dev/null 2>&1 || true
    echo "Stopped 8501 listener PID $pid"
  done
fi

pkill -f "cloudflared tunnel --url http://127.0.0.1:8501" >/dev/null 2>&1 || true
pkill -f "watch_matnexus_public.sh" >/dev/null 2>&1 || true
