# ── Base image ────────────────────────────────────────────────────────────────
FROM python:3.11-slim

# Install system deps + Node.js 20
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg \
        atomicparsley \
        curl \
        ca-certificates \
        gnupg \
        git \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Clone + build bgutil PO token server (version must match pip plugin: 1.3.1)
RUN git clone --single-branch --branch 1.3.1 \
        https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git \
        /opt/bgutil && \
    cd /opt/bgutil/server && \
    npm ci && \
    npx tsc

WORKDIR /app

# Install Python deps first (layer-cached unless requirements change)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source
COPY main.py .

# Temp download dir
RUN mkdir -p /tmp/ytmp3

EXPOSE 8000

# Start bgutil HTTP server, then uvicorn
CMD node /opt/bgutil/server/build/index.js & sleep 3 && \
    uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
