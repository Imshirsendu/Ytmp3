# YT-MP3 — Self-Hosted Audio Downloader
## Complete Setup Guide

---

## Architecture Overview

```
┌─────────────────────────────┐       Home Wi-Fi (LAN)       ┌──────────────────────────────┐
│     Your PC / Raspberry Pi  │ ◄─────────────────────────── │      Flutter Mobile App       │
│                             │   GET /download?url=…         │                              │
│  Python + FastAPI + yt-dlp  │ ──────────────────────────► │  Download queue + player +   │
│  FFmpeg + SponsorBlock      │   streams back the .mp3       │  offline library             │
│  Port :8000                 │                               │                              │
└─────────────────────────────┘                               └──────────────────────────────┘
```

**Data flow:**
1. User pastes YouTube URL in the app → app sends `GET /download?url=<url>` to server
2. Server runs `yt-dlp` → downloads best audio stream → converts to 320 kbps MP3 via FFmpeg
3. Server strips SponsorBlock segments, embeds ID3 tags and cover art → streams file back
4. App saves the MP3 locally → shows it in the library → playback is fully offline

---

## Part 1 — Python Backend

### Prerequisites

| Tool     | Version     | Notes                                         |
|----------|-------------|-----------------------------------------------|
| Python   | 3.10 – 3.12 | 3.11 recommended                              |
| FFmpeg   | Any recent  | Must be on system PATH                        |
| pip      | Any         | Included with Python                          |

### Install FFmpeg

**macOS (Homebrew)**
```bash
brew install ffmpeg
```

**Ubuntu / Debian / Raspberry Pi OS**
```bash
sudo apt update && sudo apt install -y ffmpeg atomicparsley
```

**Windows**
1. Download a build from <https://ffmpeg.org/download.html> (select "Windows builds")
2. Extract to `C:\ffmpeg`
3. Add `C:\ffmpeg\bin` to your system PATH
4. Verify: `ffmpeg -version` in a new terminal

### Option A — Docker (recommended for Raspberry Pi / always-on server)

```bash
cd backend/

# Build the image
docker build -t ytmp3-backend .

# Run it (accessible on all network interfaces at port 8000)
docker run -d \
  --name ytmp3 \
  --restart unless-stopped \
  -p 8000:8000 \
  ytmp3-backend

# Or with docker-compose (handles restarts, volumes, health checks automatically)
docker compose up -d
```

### Option B — Local Python (dev / quick test)

```bash
cd backend/
chmod +x start.sh
./start.sh
```

The script will:
- Create a `.venv` virtualenv
- Install all Python dependencies
- Start FastAPI on `http://0.0.0.0:8000`

### Verify the server is running

```bash
# From the same machine
curl http://localhost:8000/health
# → {"status":"ok","service":"ytmp3"}

# Test a download (will stream the MP3 to disk)
curl -o test.mp3 "http://localhost:8000/download?url=https://youtube.com/watch?v=dQw4w9WgXcQ"
```

### Find your local IP address

The phone needs to reach the server over Wi-Fi. Find the server's LAN IP:

```bash
# macOS / Linux
ip route get 1 | awk '{print $7; exit}'
# or
hostname -I | awk '{print $1}'

# Windows
ipconfig | findstr /i "IPv4"
```

Your IP will look like `192.168.1.X` or `10.0.0.X`. Note it — you'll enter this in the app.

### Optional: Reserve a static LAN IP

If your router supports DHCP reservations (most do), lock the server's IP so it never changes:
1. Find your server's MAC address: `ip link show` → look for `link/ether`
2. In your router admin panel (usually `192.168.1.1`): find DHCP reservations
3. Bind the MAC address to a fixed IP like `192.168.1.50`

---

## Part 2 — Flutter Mobile App

### Prerequisites

| Tool          | Install from                                      |
|---------------|---------------------------------------------------|
| Flutter SDK   | <https://flutter.dev/docs/get-started/install>    |
| Android Studio| (for Android emulator and build tools)            |
| Xcode         | (macOS only, for iOS builds)                      |

Verify your Flutter installation:
```bash
flutter doctor
```
All ticks should be green (or at least the platform you're targeting).

### Add missing package

The `server_provider.dart` uses `shared_preferences` — add it to `pubspec.yaml`:

```yaml
dependencies:
  shared_preferences: ^2.2.3   # ← add this line
  uuid: ^4.4.0                  # ← and this
```

### Install dependencies

```bash
cd frontend/
flutter pub get
```

### Configure the server IP

The server URL is entered directly in the app's Download screen — no code change needed.
Default: `http://192.168.1.100:8000`

Change it to your actual LAN IP once the app is running.

### Run on a connected device or emulator

```bash
# List available devices
flutter devices

# Run (replace with your device ID)
flutter run -d <device_id>
```

### Build a release APK (Android)

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

Transfer `app-release.apk` to your phone and install it (enable "Install unknown apps" in Settings).

### Build for iOS

```bash
flutter build ios --release
# Then open ios/Runner.xcworkspace in Xcode and archive/distribute
```

---

## Connecting App ↔ Server

1. Make sure **phone and server are on the same Wi-Fi network** (same router, no guest network isolation).
2. Open the app → **Download** tab.
3. In the **SERVER** field, type `http://<your-server-ip>:8000`
4. Tap the refresh button — the badge should turn green and say **Online**.
5. Paste any YouTube URL → tap **Get** → track downloads and appears in Library.

### Troubleshooting connectivity

| Symptom                      | Fix                                                                              |
|------------------------------|----------------------------------------------------------------------------------|
| Badge stays red "Offline"    | Confirm the server is running with `curl http://<ip>:8000/health` from a laptop |
| Can ping but app can't reach | Router has AP isolation enabled — disable it in router settings                  |
| Download starts but fails    | Video may be geo-restricted or private; try another video first                  |
| Very slow download           | Normal for long videos; the server is converting on-the-fly (CPU-bound)          |
| iOS: cleartext HTTP blocked  | Add an NSAppTransportSecurity exception in `ios/Runner/Info.plist` (see below)   |

**iOS HTTP exception** (needed if your server is HTTP, not HTTPS):
```xml
<!-- ios/Runner/Info.plist -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

### Expose server over the internet (optional, advanced)

For access outside your home:
- Use **Tailscale** (free, zero-config VPN): install on server and phone → use the Tailscale IP in the app
- Or set up a reverse proxy with HTTPS (Caddy + DuckDNS for a free domain)

---

## Project File Structure

```
ytmp3/
├── backend/
│   ├── main.py              ← FastAPI app (all server logic)
│   ├── requirements.txt     ← Python dependencies
│   ├── Dockerfile           ← Container build
│   ├── docker-compose.yml   ← Compose file with health checks
│   └── start.sh             ← Local (no Docker) startup script
│
├── frontend/
│   ├── pubspec.yaml         ← Flutter dependencies
│   └── lib/
│       ├── main.dart                      ← App entry + theme
│       ├── models/
│       │   └── track.dart                 ← Track + DownloadJob models
│       ├── providers/
│       │   ├── server_provider.dart       ← Server URL + health ping
│       │   ├── download_provider.dart     ← Download queue management
│       │   ├── library_provider.dart      ← Local MP3 scan + search/sort
│       │   └── player_provider.dart       ← Playback state
│       ├── services/
│       │   └── audio_handler.dart         ← just_audio ↔ audio_service bridge
│       ├── screens/
│       │   ├── main_shell.dart            ← Bottom nav + mini player
│       │   ├── download_screen.dart       ← URL input + queue view
│       │   ├── library_screen.dart        ← Track list + search
│       │   └── player_screen.dart         ← Full-screen player
│       └── widgets/
│           ├── mini_player.dart           ← Persistent mini player bar
│           ├── cover_art.dart             ← Embedded art with fallback
│           └── server_status_badge.dart   ← Online/offline indicator
│
└── docs/
    └── SETUP_GUIDE.md       ← This file
```

---

## API Reference

| Endpoint         | Method | Params          | Description                                  |
|------------------|--------|-----------------|----------------------------------------------|
| `/health`        | GET    | —               | Liveness check — returns `{"status":"ok"}`   |
| `/info`          | GET    | `url` (query)   | Fetch video metadata without downloading      |
| `/download`      | GET    | `url` (query)   | Full pipeline: download → convert → tag → stream |

Interactive API docs (Swagger): `http://localhost:8000/docs`

---

## Dependencies Used

### Backend
| Package     | Purpose                                          |
|-------------|--------------------------------------------------|
| `fastapi`   | Web framework                                    |
| `uvicorn`   | ASGI server                                      |
| `yt-dlp`    | YouTube audio extraction + SponsorBlock support  |
| `mutagen`   | ID3 tag writing (title, artist, cover art)       |
| `httpx`     | Async HTTP client for fetching thumbnails        |
| `ffmpeg`    | System binary: audio conversion + segment removal|

### Frontend
| Package               | Purpose                                       |
|-----------------------|-----------------------------------------------|
| `just_audio`          | Low-level audio playback engine               |
| `audio_service`       | Background playback + OS media notifications  |
| `audio_session`       | Audio focus / interruption handling           |
| `dio`                 | HTTP client with download progress callbacks  |
| `path_provider`       | App document directory on device              |
| `id3tag`              | Read MP3 ID3 metadata (title, art, duration)  |
| `provider`            | State management                              |
| `permission_handler`  | Runtime storage/media permissions             |
| `shared_preferences`  | Persist server URL across app restarts        |
