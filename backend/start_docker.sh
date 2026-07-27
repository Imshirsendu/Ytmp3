#!/bin/bash
set -e

echo "[start] Launching bgutil PO token server..."
node /opt/bgutil/server/build/index.js &
BGUTIL_PID=$!
echo "[start] bgutil PID: $BGUTIL_PID"

echo "[start] Waiting for bgutil to be ready..."
for i in $(seq 1 10); do
    if curl -sf http://127.0.0.1:4416/ping > /dev/null 2>&1; then
        echo "[start] bgutil ready after ${i}s"
        break
    fi
    sleep 1
done

echo "[start] Starting uvicorn..."
exec uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
