#!/bin/bash
set -e

echo "[start] Launching bgutil PO token server..."
node /opt/bgutil/server/build/main.js &
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

echo "[start] Installing/updating yt-dlp and bgutil plugin (once, before workers fork)..."
pip install --upgrade yt-dlp bgutil-ytdlp-pot-provider --quiet
echo "[start] pip installs done"

echo "[start] Starting uvicorn..."
exec uvicorn main:app --host 0.0.0.0 --port 8000 --workers 1
