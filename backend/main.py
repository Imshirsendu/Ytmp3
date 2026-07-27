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
import subprocess
import sys
from pathlib import Path
from contextlib import asynccontextmanager

import httpx
import yt_dlp
from mutagen.id3 import (
    ID3, TIT2, TPE1, TALB, TDRC, APIC, ID3NoHeaderError
)
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s – %(message)s",
)
log = logging.getLogger("ytmp3")

DOWNLOAD_DIR = Path(os.getenv("DOWNLOAD_DIR", "/tmp/ytmp3"))
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

SPONSORBLOCK_CATS = ["sponsor", "intro", "outro", "selfpromo", "interaction"]

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


def _update_ytdlp() -> None:
    """Update yt-dlp + install bgutil-ytdlp-pot-provider for PO token support on server IPs."""
    packages = [
        ("yt-dlp", "yt-dlp"),
        ("bgutil-ytdlp-pot-provider", "bgutil-ytdlp-pot-provider"),
    ]
    for pip_name, import_name in packages:
        try:
            result = subprocess.run(
                [sys.executable, "-m", "pip", "install", "--upgrade", pip_name, "--quiet"],
                capture_output=True, text=True, timeout=120
            )
            if result.returncode == 0:
                log.info("%s installed/updated OK", pip_name)
            else:
                log.warning("%s update failed: %s", pip_name, result.stderr[:200])
        except Exception as e:
            log.warning("%s update skipped: %s", pip_name, e)


@asynccontextmanager
async def lifespan(app: FastAPI):
    _update_ytdlp()
    _init_cookies()
    log.info("YT-MP3 backend starting – download dir: %s", DOWNLOAD_DIR)
    yield
    log.info("YT-MP3 backend shutting down")


app = FastAPI(
    title="YT-MP3 Downloader",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


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
        "extractor_args": {"youtube": {"player_client": ["android"]}},
        "postprocessors": [
            {"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "320"},
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
            tags["APIC:"] = APIC(encoding=3, mime="image/jpeg", type=3, desc="Cover", data=resp.content)
        except Exception as e:
            log.warning("Could not fetch thumbnail: %s", e)

    tags.save(str(mp3_path), v2_version=3)
    log.info("ID3 tags written → %s", mp3_path.name)


def _download_audio(url: str, work_dir: Path) -> tuple[Path, dict]:
    out_tmpl = str(work_dir / "%(title)s.%(ext)s")
    with yt_dlp.YoutubeDL(_build_ydl_opts(out_tmpl)) as ydl:
        info = ydl.extract_info(url, download=True)
    if "entries" in info:
        info = info["entries"][0]
    mp3_files = list(work_dir.glob("*.mp3"))
    if not mp3_files:
        raise FileNotFoundError("yt-dlp completed but no .mp3 found")
    return mp3_files[0], info


def _get_stream_info(url: str) -> dict:
    """
    Extract audio stream URL + metadata.
    Tries ios -> android -> tv_embedded -> web player clients.
    ios is the most reliable for bypassing YouTube bot detection on servers.
    No format string specified — we pick the best audio URL from returned list.
    """
    client_attempts = [
        ["ios"],
        ["android"],
        ["tv_embedded"],
        ["web"],
    ]

    proxy = os.getenv("YT_PROXY", "").strip() or None
    last_error = None
    for clients in client_attempts:
        opts = {
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "socket_timeout": 30,
            "extractor_args": {
                "youtube": {
                    "player_client": clients,
                }
            },
            **_cookie_opt(),
            **({"proxy": proxy} if proxy else {}),
        }
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(url, download=False)

            if "entries" in info:
                info = info["entries"][0]

            formats = info.get("formats") or []

            # Log all available formats for debugging
            log.info("client=%s total_formats=%d vcodecs=%s abrs=%s",
                clients,
                len(formats),
                list(set(f.get("vcodec","?") for f in formats[:15])),
                [f.get("abr") for f in formats[:15]],
            )

            # Pick best audio-only format with a direct http URL
            audio_only = [
                f for f in formats
                if f.get("vcodec") in (None, "none", "")
                and f.get("url", "").startswith("http")
            ]

            if not audio_only:
                # Fall back to any format with a direct URL
                audio_only = [f for f in formats if f.get("url", "").startswith("http")]

            if not audio_only:
                raise ValueError(f"No usable formats for client={clients}")

            best = max(audio_only, key=lambda f: (f.get("abr") or 0) + (f.get("tbr") or 0))
            stream_url = best["url"]
            ext = best.get("ext") or "m4a"

            log.info("Stream OK client=%s ext=%s abr=%s", clients, ext, best.get("abr"))

            return {
                "stream_url":   stream_url,
                "http_headers": best.get("http_headers", {}),
                "ext":          ext,
                "title":        info.get("title", "Unknown"),
                "artist":       info.get("uploader") or info.get("channel") or "Unknown Artist",
                "album":        info.get("album") or info.get("playlist_title") or "YouTube",
                "duration":     info.get("duration"),
                "thumbnail":    info.get("thumbnail"),
            }

        except yt_dlp.utils.DownloadError as e:
            last_error = e
            log.warning("Stream attempt failed (client=%s): %s", clients, e)
            continue
        except Exception as e:
            last_error = e
            log.warning("Stream attempt error (client=%s): %s", clients, e)
            continue

    raise last_error or ValueError("All stream extraction attempts failed")


# ─── Routes ─────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok", "service": "ytmp3"}


@app.get("/search")
async def search_youtube(
    q: str = Query(...),
    limit: int = Query(10, ge=1, le=25),
):
    if not q.strip():
        raise HTTPException(status_code=400, detail="q parameter is required")

    opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "extract_flat": True,
        **_cookie_opt(),
    }

    try:
        loop = asyncio.get_event_loop()
        def _search():
            with yt_dlp.YoutubeDL(opts) as ydl:
                return ydl.extract_info(f"ytsearch{limit}:{q}", download=False)
        info = await asyncio.wait_for(loop.run_in_executor(None, _search), timeout=15)
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


@app.get("/info")
async def get_info(url: str = Query(...)):
    opts = {"quiet": True, "no_warnings": True, "skip_download": True, **_cookie_opt()}
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


@app.get("/stream/info", summary="Stream metadata only")
async def stream_info_endpoint(url: str = Query(...)):
    """Returns title, artist, thumbnail, duration without proxying audio."""
    if not url.strip():
        raise HTTPException(status_code=400, detail="url required")
    try:
        loop = asyncio.get_event_loop()
        result = await asyncio.wait_for(loop.run_in_executor(None, _get_stream_info, url), timeout=25)
        return JSONResponse({
            "title":      result["title"],
            "artist":     result["artist"],
            "album":      result["album"],
            "duration":   result["duration"],
            "thumbnail":  result["thumbnail"],
            "stream_url": result["stream_url"],   # CDN URL — played directly by just_audio
        })
    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="Timed out")
    except yt_dlp.utils.DownloadError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        log.exception("stream_info error for: %s", url)
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/stream", summary="Proxy audio stream from YouTube")
async def stream(
    url: str = Query(...),
    request: Request = None,
):
    """
    Proxies YouTube audio through the server with correct headers.
    just_audio calls this endpoint — server fetches CDN audio and pipes it
    back as a streaming response. Supports Range header for seeking.
    No audio is stored on the server.
    """
    if not url.strip():
        raise HTTPException(status_code=400, detail="url parameter is required")

    try:
        loop = asyncio.get_event_loop()
        info = await asyncio.wait_for(loop.run_in_executor(None, _get_stream_info, url), timeout=25)
    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="Stream info timed out")
    except yt_dlp.utils.DownloadError as e:
        msg = str(e)
        if "unavailable" in msg.lower() or "private" in msg.lower():
            raise HTTPException(status_code=404, detail="Video unavailable or private")
        raise HTTPException(status_code=422, detail=f"Cannot stream: {msg}")
    except Exception as e:
        log.exception("Unexpected error resolving stream for: %s", url)
        raise HTTPException(status_code=500, detail=str(e))

    cdn_url    = info["stream_url"]
    headers    = dict(info["http_headers"])
    ext        = info["ext"]
    media_type = "audio/webm" if ext == "webm" else f"audio/{ext}"

    # Forward Range header from client — enables seeking in just_audio
    if request and "range" in request.headers:
        headers["Range"] = request.headers["range"]

    log.info("Proxying stream → %s [%s]", info["title"], ext)

    async def _proxy():
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(120.0, connect=10.0),
            follow_redirects=True,
        ) as client:
            async with client.stream("GET", cdn_url, headers=headers) as resp:
                async for chunk in resp.aiter_bytes(chunk_size=65536):
                    yield chunk

    return StreamingResponse(
        _proxy(),
        media_type=media_type,
        headers={
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-cache",
            "X-Title":       info["title"],
            "X-Artist":      info["artist"],
            "X-Duration":    str(info["duration"] or 0),
            "X-Thumbnail":   info["thumbnail"] or "",
        },
    )


@app.get("/download")
async def download(url: str = Query(...)):
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


@app.get("/debug/formats")
async def debug_formats(url: str = Query(...)):
    """Debug: show all formats yt-dlp can extract for a URL."""
    opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "socket_timeout": 30,
        "extractor_args": {"youtube": {"player_client": ["ios"]}},
        **_cookie_opt(),
    }
    try:
        loop = asyncio.get_event_loop()
        def _extract():
            with yt_dlp.YoutubeDL(opts) as ydl:
                return ydl.extract_info(url, download=False)
        info = await asyncio.wait_for(loop.run_in_executor(None, _extract), timeout=30)
        if "entries" in info:
            info = info["entries"][0]
        formats = info.get("formats") or []
        return {
            "title": info.get("title"),
            "total_formats": len(formats),
            "formats": [
                {
                    "format_id": f.get("format_id"),
                    "ext": f.get("ext"),
                    "vcodec": f.get("vcodec"),
                    "acodec": f.get("acodec"),
                    "abr": f.get("abr"),
                    "tbr": f.get("tbr"),
                    "has_url": bool(f.get("url")),
                }
                for f in formats
            ],
        }
    except Exception as e:
        return {"error": str(e)}
