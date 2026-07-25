#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# YT-MP3 Backend — local startup script (no Docker required)
# Usage:  chmod +x start.sh && ./start.sh
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

VENV_DIR=".venv"

echo "▶  Checking Python version..."
python3 --version

echo "▶  Checking FFmpeg..."
if ! command -v ffmpeg &>/dev/null; then
  echo "❌  FFmpeg not found. Install it:"
  echo "    macOS  → brew install ffmpeg"
  echo "    Ubuntu → sudo apt install ffmpeg"
  echo "    Windows→ https://ffmpeg.org/download.html (add to PATH)"
  exit 1
fi
ffmpeg -version | head -1

echo "▶  Setting up virtual environment..."
if [ ! -d "$VENV_DIR" ]; then
  python3 -m venv "$VENV_DIR"
fi
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

echo "▶  Installing Python dependencies..."
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt

echo ""
echo "══════════════════════════════════════════════════════════"
echo "  YT-MP3 Backend starting on http://0.0.0.0:8000"
echo "  Docs → http://localhost:8000/docs"
echo "  Health → http://localhost:8000/health"
echo "══════════════════════════════════════════════════════════"
echo ""

uvicorn main:app --host 0.0.0.0 --port 8000 --reload
