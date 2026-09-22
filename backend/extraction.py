"""
Ekstraksi metadata dari URL yang disimpan user.

Kontrak utama: `extract(url)` TIDAK PERNAH melempar exception. Setiap jalur
bisa gagal (situs down, diblokir, format berubah), dan kegagalan itu harus
berujung ke data yang lebih tipis — bukan ke item yang gagal diproses.
TikTok/Instagram memang sengaja membatasi akses tanpa login; data tipis dari
sana adalah kondisi normal, bukan bug.

Urutan per platform:
- youtube   -> yt-dlp (deskripsi lengkap)   -> fallback Open Graph
- tiktok    -> oEmbed publik (caption)      -> fallback Open Graph
- instagram -> Open Graph saja (oEmbed IG butuh token app Facebook)
- generic   -> Open Graph
"""

import logging
from dataclasses import dataclass, field
from urllib.parse import urlparse

import httpx
from bs4 import BeautifulSoup

log = logging.getLogger(__name__)

HTTP_TIMEOUT = 10.0
# Sebagian situs menolak/menyajikan halaman berbeda ke User-Agent kosong.
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/130.0 Safari/537.36"
    ),
    "Accept-Language": "en-US,en;q=0.9,id;q=0.8",
}
# Judul generik yang dikirim platform ke pengunjung tanpa login — itu nama
# situs, bukan isi konten. Dibuang supaya Gemini tidak mengira ini judulnya.
JUNK_TITLES = {"tiktok - make your day", "tiktok", "instagram", "youtube", "login • instagram"}
# Batas teks yang dikirim ke Gemini & disimpan di raw_content. Deskripsi
# YouTube bisa ribuan karakter berisi link sponsor; 4000 sudah cukup untuk
# menangkap inti isi tanpa membuang token percuma.
MAX_TEXT = 4000


@dataclass
class Extracted:
    platform: str
    title: str | None = None
    description: str | None = None
    author: str | None = None
    sources: list[str] = field(default_factory=list)  # jalur mana yang berhasil

    def to_text(self) -> str:
        """Gabungan teks untuk raw_content & input Gemini. Kosong = tidak ada data."""
        parts = []
        if self.title:
            parts.append(f"Title: {self.title}")
        if self.author:
            parts.append(f"Author: {self.author}")
        if self.description:
            parts.append(f"Description: {self.description}")
        return "\n".join(parts)[:MAX_TEXT]


def detect_platform(url: str) -> str:
    host = (urlparse(url).hostname or "").lower()
    host = host.removeprefix("www.").removeprefix("m.")
    if host in ("youtube.com", "youtu.be", "music.youtube.com"):
        return "youtube"
    if host == "tiktok.com" or host.endswith(".tiktok.com"):
        return "tiktok"
    if host in ("instagram.com", "instagr.am"):
        return "instagram"
    return "generic"


def _fill(target: Extracted, title=None, description=None, author=None, source=None):
    """Isi field yang masih kosong saja — sumber yang lebih kaya dipanggil duluan."""
    changed = False
    if title and title.strip().lower() in JUNK_TITLES:
        title = None
    if title and not target.title:
        target.title, changed = title.strip(), True
    if description and not target.description:
        target.description, changed = description.strip(), True
    if author and not target.author:
        target.author, changed = author.strip(), True
    if changed and source:
        target.sources.append(source)


def _open_graph(url: str, target: Extracted) -> None:
    try:
        resp = httpx.get(url, headers=HEADERS, timeout=HTTP_TIMEOUT, follow_redirects=True)
        resp.raise_for_status()
    except httpx.HTTPError as e:
        log.info("open graph fetch gagal untuk %s: %s", url, e)
        return

    soup = BeautifulSoup(resp.text, "html.parser")

    def meta(*names):
        for name in names:
            tag = soup.find("meta", attrs={"property": name}) or soup.find(
                "meta", attrs={"name": name}
            )
            if tag and tag.get("content"):
                return tag["content"]
        return None

    title = meta("og:title", "twitter:title") or (soup.title.string if soup.title else None)
    description = meta("og:description", "twitter:description", "description")
    if not description:
        # Banyak artikel (mis. Wikipedia) tidak punya meta description.
        # Paragraf-paragraf awal yang cukup panjang biasanya berisi inti isi.
        paragraphs = [p.get_text(" ", strip=True) for p in soup.find_all("p")]
        body = " ".join(p for p in paragraphs if len(p) > 80)
        description = body[:MAX_TEXT] or None
    _fill(
        target,
        title=title,
        description=description,
        author=meta("author", "og:site_name"),
        source="open_graph",
    )


def _tiktok_oembed(url: str, target: Extracted) -> None:
    try:
        resp = httpx.get(
            "https://www.tiktok.com/oembed",
            params={"url": url},
            headers=HEADERS,
            timeout=HTTP_TIMEOUT,
        )
        resp.raise_for_status()
        data = resp.json()
    except (httpx.HTTPError, ValueError) as e:
        log.info("tiktok oembed gagal untuk %s: %s", url, e)
        return
    # Di TikTok, "title" oEmbed sebenarnya caption video — itu isi kontennya.
    _fill(target, description=data.get("title"), author=data.get("author_name"), source="tiktok_oembed")


def _youtube_ytdlp(url: str, target: Extracted) -> None:
    # Import di dalam fungsi: yt-dlp berat dimuat, dan cuma dibutuhkan jalur ini.
    import yt_dlp

    opts = {"quiet": True, "no_warnings": True, "skip_download": True, "socket_timeout": HTTP_TIMEOUT}
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
    except Exception as e:  # yt-dlp melempar banyak jenis error berbeda
        log.info("yt-dlp gagal untuk %s: %s", url, e)
        return
    _fill(
        target,
        title=info.get("title"),
        description=info.get("description"),
        author=info.get("uploader") or info.get("channel"),
        source="yt_dlp",
    )


def extract(url: str) -> Extracted:
    platform = detect_platform(url)
    result = Extracted(platform=platform)
    try:
        if platform == "youtube":
            _youtube_ytdlp(url, result)
        elif platform == "tiktok":
            _tiktok_oembed(url, result)
        # Open Graph selalu dicoba terakhir untuk mengisi yang masih kosong.
        _open_graph(url, result)
    except Exception:
        # Jaring terakhir: bug tak terduga di parser tetap tidak boleh
        # menggagalkan item. Data yang sudah terkumpul tetap dikembalikan.
        log.exception("ekstraksi error tak terduga untuk %s", url)
    return result
