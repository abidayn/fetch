"""
Ekstraksi metadata dari URL yang disimpan user.

Kontrak utama: `extract(url)` TIDAK PERNAH melempar exception. Setiap jalur
bisa gagal (situs down, diblokir, format berubah), dan kegagalan itu harus
berujung ke data yang lebih tipis — bukan ke item yang gagal diproses.
TikTok/Instagram memang sengaja membatasi akses tanpa login; data tipis dari
sana adalah kondisi normal, bukan bug.

Urutan per platform:
- youtube   -> yt-dlp (deskripsi lengkap) -> oEmbed YouTube (judul + channel)
               -> fallback Open Graph
- tiktok    -> oEmbed publik (caption, video saja) -> halaman embed (caption,
               termasuk post foto/slideshow) -> fallback Open Graph
- instagram -> Open Graph sebagai crawler link-preview (oEmbed IG butuh token
               app Facebook)
- generic   -> Open Graph
"""

import json
import logging
import re
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
# Instagram menyajikan halaman kosong (cuma shell JavaScript, tanpa meta tag)
# ke browser yang tidak login -- tapi meta tag lengkap berisi caption ke
# crawler link-preview, supaya link yang di-share di chat tetap punya preview.
# Kita memang sedang membuat preview dari link, jadi ini identitas yang pas.
CRAWLER_HEADERS = {
    "User-Agent": "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
    "Accept-Language": HEADERS["Accept-Language"],
}
# Judul generik yang dikirim platform ke pengunjung tanpa login — itu nama
# situs, bukan isi konten. Dibuang supaya Gemini tidak mengira ini judulnya.
# "- youtube" = judul halaman YouTube untuk request yang dicurigai bot (mis.
# dari IP datacenter Railway): judul videonya kosong, tinggal akhirannya.
JUNK_TITLES = {"tiktok - make your day", "tiktok", "instagram", "youtube", "- youtube", "login • instagram"}
# Deskripsi generik di halaman yang sama. Kalau lolos, Gemini "merangkum"
# deskripsi platformnya -- item tersimpan dengan ringkasan tentang YouTube,
# bukan tentang videonya (kejadian nyata di production, 2026-09-24).
JUNK_DESCRIPTION_PREFIXES = ("enjoy the videos and music you love", "tiktok | make your day")
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
    if description and description.strip().lower().startswith(JUNK_DESCRIPTION_PREFIXES):
        description = None
    if title and not target.title:
        target.title, changed = title.strip(), True
    if description and not target.description:
        target.description, changed = description.strip(), True
    if author and not target.author:
        target.author, changed = author.strip(), True
    if changed and source:
        target.sources.append(source)


def _get_page(url: str, headers: dict = HEADERS) -> httpx.Response | None:
    try:
        resp = httpx.get(url, headers=headers, timeout=HTTP_TIMEOUT, follow_redirects=True)
        resp.raise_for_status()
    except httpx.HTTPError as e:
        log.info("fetch halaman gagal untuk %s: %s", url, e)
        return None
    return resp


def _meta(soup: BeautifulSoup, *names: str) -> str | None:
    for name in names:
        tag = soup.find("meta", attrs={"property": name}) or soup.find("meta", attrs={"name": name})
        if tag and tag.get("content"):
            return tag["content"]
    return None


def _open_graph(url: str, target: Extracted) -> None:
    resp = _get_page(url)
    if resp is None:
        return

    soup = BeautifulSoup(resp.text, "html.parser")
    meta = lambda *names: _meta(soup, *names)  # noqa: E731

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


TIKTOK_POST_ID = re.compile(r"/(?:video|photo)/(\d+)")


def _tiktok_embed(url: str, target: Extracted) -> None:
    """Caption dari halaman embed TikTok (yang dipakai widget embed di blog).

    Jalur cadangan untuk post foto/slideshow: oEmbed cuma melayani video, dan
    untuk foto ia menjawab "429 ratelimit triggered" -- menyesatkan, karena
    link video yang diminta tepat sebelum/sesudahnya tetap 200. Halaman
    TikTok biasa juga tidak membantu: isinya shell JavaScript tanpa caption.
    """
    match = TIKTOK_POST_ID.search(url)
    if match is None:
        # Link pendek (vt.tiktok.com/...) baru ketahuan ID-nya setelah redirect.
        resp = _get_page(url)
        match = TIKTOK_POST_ID.search(str(resp.url)) if resp is not None else None
    if match is None:
        log.info("tiktok embed: ID post tidak ditemukan untuk %s", url)
        return

    post_id = match.group(1)
    resp = _get_page(f"https://www.tiktok.com/embed/v2/{post_id}")
    if resp is None:
        return
    try:
        script = BeautifulSoup(resp.text, "html.parser").find("script", id="__FRONTITY_CONNECT_STATE__")
        state = json.loads(script.string)
        video = state["source"]["data"][f"/embed/v2/{post_id}"]["videoData"]
        caption = video["itemInfos"]["text"]
        author = video["authorInfos"].get("nickName") or video["authorInfos"].get("uniqueId")
    except (AttributeError, TypeError, KeyError, ValueError) as e:
        # Struktur internal TikTok, bukan API resmi -- bisa berubah kapan saja.
        log.info("tiktok embed: format tidak dikenali untuk %s: %r", url, e)
        return
    _fill(target, description=caption, author=author, source="tiktok_embed")


# og:description Instagram: '1,086 likes, 29 comments - grish.tech on
# September 21, 2026: "caption..."'. Jumlah like & tanggal cuma noise untuk
# Gemini; yang dibutuhkan username dan caption. Kutip penutup bisa hilang
# kalau caption panjang dipotong Instagram.
IG_DESCRIPTION = re.compile(r'(?:^|- )(?P<author>[\w.]+) on [^:"\n]+: "(?P<caption>.*?)"?\s*$', re.S)


def _instagram(url: str, target: Extracted) -> None:
    resp = _get_page(url, headers=CRAWLER_HEADERS)
    if resp is None:
        return
    description = _meta(BeautifulSoup(resp.text, "html.parser"), "og:description", "description")
    if not description:
        # Post privat/terhapus, atau Instagram menolak crawler dari IP ini.
        log.info("instagram: tidak ada og:description untuk %s", url)
        return
    match = IG_DESCRIPTION.search(description)
    if match:
        _fill(target, description=match["caption"], author=match["author"], source="instagram_og")
    else:
        _fill(target, description=description, source="instagram_og")
    # Title sengaja tidak diisi: og:title Instagram = "Nama on Instagram:
    # <caption>" -- caption lagi, bukan judul. Gemini membuat judul dari caption.


def _youtube_ytdlp(url: str, target: Extracted) -> None:
    # Import di dalam fungsi: yt-dlp berat dimuat, dan cuma dibutuhkan jalur ini.
    import yt_dlp

    opts = {"quiet": True, "no_warnings": True, "skip_download": True, "socket_timeout": HTTP_TIMEOUT}
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
    except Exception as e:  # yt-dlp melempar banyak jenis error berbeda
        # warning, bukan info: dari IP datacenter (Railway) YouTube bisa
        # memblokir yt-dlp sebagai bot -- pesan ini yang perlu dicari di log.
        log.warning("yt-dlp gagal untuk %s: %s", url, e)
        return
    _fill(
        target,
        title=info.get("title"),
        description=info.get("description"),
        author=info.get("uploader") or info.get("channel"),
        source="yt_dlp",
    )


def _youtube_oembed(url: str, target: Extracted) -> None:
    """Judul + channel dari oEmbed resmi YouTube, tanpa deskripsi.

    Cadangan kalau yt-dlp diblokir: oEmbed adalah API publik untuk embed,
    jadi tidak kena pemeriksaan bot yang sama. Judul asli jauh lebih baik
    daripada halaman "- YouTube" generik yang didapat Open Graph saat diblokir.
    """
    try:
        resp = httpx.get(
            "https://www.youtube.com/oembed",
            params={"url": url, "format": "json"},
            headers=HEADERS,
            timeout=HTTP_TIMEOUT,
        )
        resp.raise_for_status()
        data = resp.json()
    except (httpx.HTTPError, ValueError) as e:
        log.info("youtube oembed gagal untuk %s: %s", url, e)
        return
    _fill(target, title=data.get("title"), author=data.get("author_name"), source="youtube_oembed")


def extract(url: str) -> Extracted:
    platform = detect_platform(url)
    result = Extracted(platform=platform)
    try:
        if platform == "instagram":
            # Open Graph biasa ke Instagram selalu kosong (lihat CRAWLER_HEADERS),
            # jadi tidak ada gunanya dicoba lagi setelah ini.
            _instagram(url, result)
            return result
        if platform == "youtube":
            _youtube_ytdlp(url, result)
            if not result.description:
                _youtube_oembed(url, result)
        elif platform == "tiktok":
            _tiktok_oembed(url, result)
            if not result.description:
                _tiktok_embed(url, result)
        # Open Graph selalu dicoba terakhir untuk mengisi yang masih kosong.
        _open_graph(url, result)
    except Exception:
        # Jaring terakhir: bug tak terduga di parser tetap tidak boleh
        # menggagalkan item. Data yang sudah terkumpul tetap dikembalikan.
        log.exception("ekstraksi error tak terduga untuk %s", url)
    return result
