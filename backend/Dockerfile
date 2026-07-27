# ── Stage 1: base image ────────────────────────────────────────────────────
FROM python:3.11-slim

# Install FFmpeg, AtomicParsley, Node.js 20
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg \
        atomicparsley \
        curl \
        ca-certificates \
        gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install bgutil HTTP server globally
RUN npm install -g @imputnet/bgutil-ytdlp-pot-provider

WORKDIR /app

# Install Python deps first (layer-cached unless requirements change)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source
COPY main.py .

# Temp download dir (can be overridden via -v mount)
RUN mkdir -p /tmp/ytmp3

EXPOSE 8000

# Start bgutil PO token server, then uvicorn
CMD bgutil-ytdlp-pot-provider serve & sleep 3 && uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
