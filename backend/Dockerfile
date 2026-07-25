# ── Stage 1: base image ────────────────────────────────────────────────────
FROM python:3.11-slim

# Install FFmpeg (required by yt-dlp for audio conversion + thumbnail embedding)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg \
        atomicparsley \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps first (layer-cached unless requirements change)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source
COPY main.py .

# Temp download dir (can be overridden via -v mount)
RUN mkdir -p /tmp/ytmp3

EXPOSE 8000

# Run with auto-reload disabled in production
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
