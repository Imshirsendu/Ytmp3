"""
YT-MP3 Downloader Backend
FastAPI server that downloads YouTube audio, converts to 320kbps MP3,
strips sponsor segments via SponsorBlock, and embeds ID3 metadata.
"""

import os
import uuid
import shutil
import asyncio
import logging
import tempfile
from pathlib import Path
from contextlib import asynccontextmanager

import httpx
import yt_dlp
from mutagen.id3 import (
    ID3, TIT2, TPE1, TALB, TDRC, APIC, ID3NoHeaderError
)
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.middleware.cors import CORSMiddleware

# ─── Logging ────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s – %(message)s",
)
log = logging.getLogger("ytmp3")

# ─── Config ─────────────────────────────────────────────────────────────────
DOWNLOAD_DIR = Path(os.getenv("DOWNLOAD_DIR", "/tmp/ytmp3"))
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

SPONSORBLOCK_CATS = ["sponsor", "intro", "outro", "selfpromo", "interaction"]

# ─── Cookies ─────────────────────────────────────────────────────────────────
_COOKIES_PATH: str | None = None

def _init_cookies() -> None:
    global _COOKIES_PATH
    content = os.getenv("YT_COOKIES", "").strip()
    if content:
        tmp = Path(tempfile.gettempdir()) / "yt_cookies.txt"
        tmp.write_text(content, encoding="utf-8")
        _COOKIES_PATH = str(tmp)
        log.info("Cookies written from env var → %s", _COOKIES_PATH)
        return
    local = Path(__file__).parent / "cookies.txt"
    if local.exists():
        _COOKIES_PATH = str(local)
        log.info("Cookies loaded from local file: %s", _COOKIES_PATH)
    else:
        log.warning("No YT_COOKIES env var and no cookies.txt — bot detection likely")

def _cookie_opt() -> dict:
    return {"cookiefile": _COOKIES_PATH} if _COOKIES_PATH else {}


# ─── App lifespan ───────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    _init_cookies()
    log.info("YT-MP3 backend starting – download dir: %s", DOWNLOAD_DIR)
    yield
    log.info("YT-MP3 backend shutting down")


app = FastAPI(
    title="YT-MP3 Downloader",
    description="Self-hosted YouTube → 320 kbps MP3 converter with SponsorBlock",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


# ─── Helpers ────────────────────────────────────────────────────────────────

def _sponsorblock_opts(categories: list[str]) -> dict:
    return {
        "key": "SponsorBlock",
        "categories": categories,
        "api": "https://sponsor.ajay.app",
    }


def _build_ydl_opts(out_tmpl: str) -> dict:
    return {
        "format": "bestaudio/best",
        "outtmpl": out_tmpl,
        "quiet": True,
        "no_warnings": True,
        "socket_timeout": 30,
        "extractor_args": {
            "youtube": {"player_client": ["android"]},
        },
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "320",
            },
            {"key": "EmbedThumbnail"},
            {"key": "FFmpegMetadata", "add_metadata": True},
            _sponsorblock_opts(SPONSORBLOCK_CATS),
            {"key": "ModifyChapters", "remove_sponsor_segments": SPONSORBLOCK_CATS},
        ],
        "writethumbnail": True,
        "embedthumbnail": True,
    }


def _embed_metadata(mp3_path: Path, info: dict) -> None:
    try:
        tags = ID3(str(mp3_path))
    except ID3NoHeaderError:
        tags = ID3()

    title  = info.get("title", "Unknown Title")
    artist = info.get("uploader") or info.get("channel") or "Unknown Artist"
    album  = info.get("album") or info.get("playlist_title") or "YouTube"
    year   = str(info.get("upload_date", ""))[:4] or ""

    tags["TIT2"] = TIT2(encoding=3, text=title)
    tags["TPE1"] = TPE1(encoding=3, text=artist)
    tags["TALB"] = TALB(encoding=3, text=album)
    if year:
        tags["TDRC"] = TDRC(encoding=3, text=year)

    thumbnail_url = info.get("thumbnail")
    if thumbnail_url and "APIC:" not in tags:
        try:
            resp = httpx.get(thumbnail_url, timeout=10, follow_redirects=True)
            resp.raise_for_status()
            tags["APIC:"] = APIC(
                encoding=3,
                mime="image/jpeg",
                type=3,
                desc="Cover",
                data=resp.content,
            )
        except Exception as e:
            log.warning("Could not fetch thumbnail: %s", e)

    tags.save(str(mp3_path), v2_version=3)
    log.info("ID3 tags written → %s", mp3_path.name)


def _download_audio(url: str, work_dir: Path) -> tuple[Path, dict]:
    out_tmpl = str(work_dir / "%(title)s.%(ext)s")
    opts = _build_ydl_opts(out_tmpl)

    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=True)

    if "entries" in info:
        info = info["entries"][0]

    mp3_files = list(work_dir.glob("*.mp3"))
    if not mp3_files:
        raise FileNotFoundError("yt-dlp completed but no .mp3 found in work dir")

    mp3_path = mp3_files[0]
    return mp3_path, info


def _get_stream_url(url: str) -> dict:
    """
    Extract the direct audio stream URL from YouTube without downloading.
    Returns the best audio format URL plus metadata.
    """
    # Android client bypasses bot detection natively.
    # MUST set cookiefile=None explicitly — if a cookies env var is present,
    # yt-dlp skips android/ios clients entirely since they don't support cookies.
    opts = {
        "format": "bestaudio/best",
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "socket_timeout": 20,
        "cookiefile": None,   # force no cookies → android client won't be skipped
        "extractor_args": {
            "youtube": {"player_client": ["android"]},
        },
    }
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=False)

    if "entries" in info:
        info = info["entries"][0]

    # Find the best audio-only format URL
    stream_url = None
    formats = info.get("formats", [])

    # Prefer audio-only formats (no video)
    audio_only = [
        f for f in formats
        if f.get("vcodec") == "none" and f.get("url")
    ]
    if audio_only:
        # Pick highest quality audio-only
        best = max(audio_only, key=lambda f: f.get("abr") or f.get("tbr") or 0)
        stream_url = best.get("url")

    # Fallback: use the top-level url yt-dlp resolved
    if not stream_url:
        stream_url = info.get("url")

    if not stream_url:
        raise ValueError("Could not extract stream URL")

    return {
        "stream_url": stream_url,
        "title":      info.get("title", "Unknown"),
        "artist":     info.get("uploader") or info.get("channel") or "Unknown Artist",
        "album":      info.get("album") or info.get("playlist_title") or "YouTube",
        "duration":   info.get("duration"),
        "thumbnail":  info.get("thumbnail"),
    }


# ─── Routes ─────────────────────────────────────────────────────────────────

@app.get("/health", summary="Health check")
async def health():
    return {"status": "ok", "service": "ytmp3"}


@app.get("/search", summary="Search YouTube for tracks")
async def search_youtube(
    q: str = Query(..., description="Search query"),
    limit: int = Query(10, ge=1, le=25, description="Max results"),
):
    if not q.strip():
        raise HTTPException(status_code=400, detail="q parameter is required")

    opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "extract_flat": True,
        "cookiefile": None,
        "extractor_args": {
            "youtube": {"player_client": ["android"]},
        },
    }

    try:
        loop = asyncio.get_event_loop()

        def _search():
            with yt_dlp.YoutubeDL(opts) as ydl:
                return ydl.extract_info(f"ytsearch{limit}:{q}", download=False)

        info = await asyncio.wait_for(
            loop.run_in_executor(None, _search),
            timeout=15,
        )

        results = []
        for entry in (info.get("entries") or []):
            if not entry:
                continue
            video_id = entry.get("id")
            results.append({
                "id":        video_id,
                "title":     entry.get("title"),
                "uploader":  entry.get("uploader") or entry.get("channel"),
                "duration":  entry.get("duration"),
                "thumbnail": entry.get("thumbnail"),
                "url":       f"https://www.youtube.com/watch?v={video_id}",
            })

        return {"query": q, "results": results}

    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="Search timed out")
    except Exception as e:
        log.exception("Search error for query: %s", q)
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/info", summary="Fetch video metadata without downloading")
async def get_info(url: str = Query(..., description="YouTube video URL")):
    opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "extractor_args": {
            "youtube": {"player_client": ["android"]},
        },
    }
    try:
        loop = asyncio.get_event_loop()
        def _extract():
            with yt_dlp.YoutubeDL(opts) as ydl:
                return ydl.extract_info(url, download=False)
        info = await loop.run_in_executor(None, _extract)
        if "entries" in info:
            info = info["entries"][0]
        return {
            "title":       info.get("title"),
            "uploader":    info.get("uploader"),
            "duration":    info.get("duration"),
            "thumbnail":   info.get("thumbnail"),
            "webpage_url": info.get("webpage_url"),
        }
    except yt_dlp.utils.DownloadError as e:
        raise HTTPException(status_code=422, detail=f"Cannot fetch info: {e}")
    except Exception as e:
        log.exception("Unexpected error in /info")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/stream", summary="Get direct audio stream URL for a YouTube video")
async def stream(
    url: str = Query(..., description="YouTube video URL"),
):
    """
    Returns the direct audio stream URL (and metadata) for client-side playback.
    The client plays this URL directly via just_audio — no file is downloaded
    to the server. URL expires after ~6 hours (YouTube CDN signed URLs).
    """
    if not url.strip():
        raise HTTPException(status_code=400, detail="url parameter is required")

    try:
        loop = asyncio.get_event_loop()
        result = await asyncio.wait_for(
            loop.run_in_executor(None, _get_stream_url, url),
            timeout=20,
        )
        return JSONResponse(result)

    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="Stream URL extraction timed out")
    except yt_dlp.utils.DownloadError as e:
        msg = str(e)
        if "Video unavailable" in msg or "not available" in msg:
            raise HTTPException(status_code=404, detail="Video unavailable or private")
        raise HTTPException(status_code=422, detail=f"Cannot stream: {msg}")
    except Exception as e:
        log.exception("Unexpected error in /stream for URL: %s", url)
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/download", summary="Download YouTube audio as 320 kbps MP3")
async def download(
    url: str = Query(..., description="YouTube video or playlist URL"),
):
    """
    Full pipeline:
    1. Extract best audio via yt-dlp
    2. Convert to 320 kbps MP3 via FFmpeg
    3. Strip SponsorBlock segments
    4. Embed ID3 tags + cover art
    5. Stream the MP3 back to the client
    """
    if not url.strip():
        raise HTTPException(status_code=400, detail="url parameter is required")

    work_dir = DOWNLOAD_DIR / uuid.uuid4().hex
    work_dir.mkdir(parents=True, exist_ok=True)

    try:
        log.info("Download request → %s", url)

        loop = asyncio.get_event_loop()

        mp3_path, info = await asyncio.wait_for(
            loop.run_in_executor(None, _download_audio, url, work_dir),
            timeout=300,
        )

        _embed_metadata(mp3_path, info)

        filename = mp3_path.name
        log.info("Serving → %s (%d bytes)", filename, mp3_path.stat().st_size)

        return FileResponse(
            path=str(mp3_path),
            media_type="audio/mpeg",
            filename=filename,
            background=_cleanup_task(work_dir),
        )

    except asyncio.TimeoutError:
        shutil.rmtree(work_dir, ignore_errors=True)
        raise HTTPException(status_code=504, detail="Download timed out (>5 min)")

    except yt_dlp.utils.DownloadError as e:
        shutil.rmtree(work_dir, ignore_errors=True)
        msg = str(e)
        if "Video unavailable" in msg or "not available" in msg:
            raise HTTPException(status_code=404, detail="Video is unavailable or private")
        if "is not a valid URL" in msg or "Unsupported URL" in msg:
            raise HTTPException(status_code=422, detail="Invalid or unsupported URL")
        raise HTTPException(status_code=422, detail=f"Download error: {msg}")

    except FileNotFoundError as e:
        shutil.rmtree(work_dir, ignore_errors=True)
        raise HTTPException(status_code=500, detail=str(e))

    except Exception as e:
        shutil.rmtree(work_dir, ignore_errors=True)
        log.exception("Unexpected error for URL: %s", url)
        raise HTTPException(status_code=500, detail=f"Internal error: {e}")


def _cleanup_task(work_dir: Path):
    from starlette.background import BackgroundTask

    def _rm():
        shutil.rmtree(work_dir, ignore_errors=True)
        log.debug("Cleaned up %s", work_dir)

    return BackgroundTask(_rm)
