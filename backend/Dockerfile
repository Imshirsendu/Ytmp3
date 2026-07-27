FROM python:3.11-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg \
        atomicparsley \
        curl \
        ca-certificates \
        gnupg \
        git \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --single-branch --branch 1.3.1 \
        https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git \
        /opt/bgutil && \
    cd /opt/bgutil/server && \
    npm ci && \
    npx tsc

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .
COPY start_docker.sh .
RUN chmod +x start_docker.sh

RUN mkdir -p /tmp/ytmp3

EXPOSE 8000

CMD ["./start_docker.sh"]
