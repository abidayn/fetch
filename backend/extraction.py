"""
Metadata extraction for URLs saved by the user.

Main contract: `extract(url)` NEVER raises. Every path can fail (site down,
blocked, format changed), and that failure must end in thinner data -- not
in an item that fails to process. TikTok/Instagram deliberately limit access
without login; thin data from them is normal, not a bug.

Order per platform:
- youtube   -> yt-dlp (full description) -> YouTube oEmbed (title + channel)
               -> Open Graph fallback
- tiktok    -> public oEmbed (caption, videos only) -> embed page (caption,
               including photo/slideshow posts) -> Open Graph fallback
- instagram -> Open Graph as a link-preview crawler (IG oEmbed needs a
               Facebook app token)
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
# Some sites reject, or serve a different page to, an empty User-Agent.
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/130.0 Safari/537.36"
    ),
    "Accept-Language": "en-US,en;q=0.9,id;q=0.8",
}
# Instagram serves an empty page (just a JavaScript shell, no meta tags) to
# logged-out browsers -- but full meta tags, including the caption, to
# link-preview crawlers, so links shared in chats still get a preview. We
# are building a preview from a link, so this is the right identity.
CRAWLER_HEADERS = {
    "User-Agent": "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
    "Accept-Language": HEADERS["Accept-Language"],
}
# Generic titles platforms send to logged-out visitors -- that's the site
# name, not the content. Dropped so Gemini doesn't mistake it for the title.
# "- youtube" = YouTube's page title for requests it suspects are bots (e.g.
# from Railway's datacenter IPs): the video title is empty, only the suffix is left.
JUNK_TITLES = {"tiktok - make your day", "tiktok", "instagram", "youtube", "- youtube", "login • instagram"}
# Generic descriptions on those same pages. If one slips through, Gemini
# "summarises" the platform's own description -- the item gets saved with a
# summary about YouTube, not about the video (happened in production, 2026-09-24).
JUNK_DESCRIPTION_PREFIXES = ("enjoy the videos and music you love", "tiktok | make your day")
# Cap on the text sent to Gemini and stored in raw_content. YouTube
# descriptions can run to thousands of characters of sponsor links; 4000 is
# enough to capture the substance without wasting tokens.
MAX_TEXT = 4000


@dataclass
class Extracted:
    platform: str
    title: str | None = None
    description: str | None = None
    author: str | None = None
    sources: list[str] = field(default_factory=list)  # which paths succeeded

    def to_text(self) -> str:
        """Combined text for raw_content and the Gemini input. Empty = no data."""
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
    """Fill only fields that are still empty -- richer sources are called first."""
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
        log.info("page fetch failed for %s: %s", url, e)
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
        # Many articles (e.g. Wikipedia) have no meta description at all.
        # The first reasonably long paragraphs usually carry the substance.
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
        log.info("tiktok oembed failed for %s: %s", url, e)
        return
    # On TikTok, the oEmbed "title" is actually the video caption -- that's the content.
    _fill(target, description=data.get("title"), author=data.get("author_name"), source="tiktok_oembed")


TIKTOK_POST_ID = re.compile(r"/(?:video|photo)/(\d+)")


def _tiktok_embed(url: str, target: Extracted) -> None:
    """Caption from TikTok's embed page (the one the blog embed widget uses).

    Fallback for photo/slideshow posts: oEmbed only serves videos, and for
    photos it answers "429 ratelimit triggered" -- misleading, because video
    links requested right before/after still return 200. The regular TikTok
    page doesn't help either: it's a JavaScript shell with no caption.
    """
    match = TIKTOK_POST_ID.search(url)
    if match is None:
        # Short links (vt.tiktok.com/...) only reveal their ID after the redirect.
        resp = _get_page(url)
        match = TIKTOK_POST_ID.search(str(resp.url)) if resp is not None else None
    if match is None:
        log.info("tiktok embed: post ID not found for %s", url)
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
        # TikTok's internal structure, not an official API -- it can change any time.
        log.info("tiktok embed: unrecognised format for %s: %r", url, e)
        return
    _fill(target, description=caption, author=author, source="tiktok_embed")


# Instagram og:description: '1,086 likes, 29 comments - grish.tech on
# September 21, 2026: "caption..."'. Like count and date are just noise for
# Gemini; what we need is the username and caption. The closing quote can be
# missing when Instagram truncates a long caption.
IG_DESCRIPTION = re.compile(r'(?:^|- )(?P<author>[\w.]+) on [^:"\n]+: "(?P<caption>.*?)"?\s*$', re.S)


def _instagram(url: str, target: Extracted) -> None:
    resp = _get_page(url, headers=CRAWLER_HEADERS)
    if resp is None:
        return
    description = _meta(BeautifulSoup(resp.text, "html.parser"), "og:description", "description")
    if not description:
        # Private/deleted post, or Instagram rejected the crawler from this IP.
        log.info("instagram: no og:description for %s", url)
        return
    match = IG_DESCRIPTION.search(description)
    if match:
        _fill(target, description=match["caption"], author=match["author"], source="instagram_og")
    else:
        _fill(target, description=description, source="instagram_og")
    # Title deliberately left empty: Instagram's og:title is "Name on Instagram:
    # <caption>" -- the caption again, not a title. Gemini writes a title from the caption.


def _youtube_ytdlp(url: str, target: Extracted) -> None:
    # Imported inside the function: yt-dlp is heavy to load and only this path needs it.
    import yt_dlp

    opts = {"quiet": True, "no_warnings": True, "skip_download": True, "socket_timeout": HTTP_TIMEOUT}
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
    except Exception as e:  # yt-dlp raises many different error types
        # warning, not info: from datacenter IPs (Railway) YouTube may block
        # yt-dlp as a bot -- this is the message to search for in the logs.
        log.warning("yt-dlp failed for %s: %s", url, e)
        return
    _fill(
        target,
        title=info.get("title"),
        description=info.get("description"),
        author=info.get("uploader") or info.get("channel"),
        source="yt_dlp",
    )


def _youtube_oembed(url: str, target: Extracted) -> None:
    """Title + channel from YouTube's official oEmbed, no description.

    Fallback for when yt-dlp is blocked: oEmbed is a public API for embeds, so
    it isn't subject to the same bot check. The real title is far better than
    the generic "- YouTube" page Open Graph gets when blocked.
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
        log.info("youtube oembed failed for %s: %s", url, e)
        return
    _fill(target, title=data.get("title"), author=data.get("author_name"), source="youtube_oembed")


def extract(url: str) -> Extracted:
    platform = detect_platform(url)
    result = Extracted(platform=platform)
    try:
        if platform == "instagram":
            # Plain Open Graph against Instagram is always empty (see
            # CRAWLER_HEADERS), so there's no point trying it afterwards.
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
        # Open Graph always runs last, to fill whatever is still empty.
        _open_graph(url, result)
    except Exception:
        # Last safety net: an unexpected parser bug must still not fail the
        # item. Whatever data was already collected is returned.
        log.exception("unexpected extraction error for %s", url)
    return result
