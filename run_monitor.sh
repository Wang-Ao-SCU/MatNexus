#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export MATNEXUS_MONITOR_INTERVAL="${MATNEXUS_MONITOR_INTERVAL:-800}"

PID_FILE="logs/hourly_monitor.pid"
mkdir -p logs

if [ -f "$PID_FILE" ]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" >/dev/null 2>&1; then
    echo "Stopping old monitor PID $old_pid"
    kill "$old_pid" >/dev/null 2>&1 || true
    for _ in 1 2 3; do
      kill -0 "$old_pid" >/dev/null 2>&1 || break
      sleep 1
    done
    if kill -0 "$old_pid" >/dev/null 2>&1; then
      kill -9 "$old_pid" >/dev/null 2>&1 || true
    fi
  fi
fi

echo "MatNexus public monitor"
echo "Interval: ${MATNEXUS_MONITOR_INTERVAL}s"
echo "Log: logs/hourly_monitor.log"
echo "Stop: Ctrl+C"
echo

MATNEXUS_MONITOR_LIVE=1 ./monitor_matnexus_hourly.sh
