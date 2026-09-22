"""
Embedding: teks -> vektor 768 angka yang mewakili "makna" teks itu.

Dipakai di dua sisi RAG, dan keduanya WAJIB pakai model + dimensi yang sama:
- sisi simpan  : enrichment.py meng-embed title+summary item (embedding_text)
- sisi cari    : POST /search meng-embed kalimat pencarian user
Vektor dari model berbeda tidak bisa dibandingkan -- tidak error, cuma
hasilnya ngawur (lihat docs/data-model.md, "Dimensi kolom embedding").

Kontrak sama seperti classifier.py: gagal -> None, tidak pernah melempar.
Pemanggil yang menentukan artinya (background: biarkan NULL, nanti di-backfill;
request pencarian: balas 503).
"""

import logging

from google.genai import types

from gemini import get_client

log = logging.getLogger(__name__)

MODEL = "gemini-embedding-2"
DIMENSIONS = 768  # harus sama dengan Vector(768) di models.py


def embedding_text(title: str | None, summary: str | None) -> str:
    """Teks yang mewakili satu item di ruang vektor.

    title + summary, bukan raw_content: raw_content (mis. deskripsi YouTube)
    penuh link sponsor & ajakan subscribe yang mengencerkan makna vektor.
    Title tetap ikut karena menyimpan nama diri dalam bahasa asli
    ("Despacito", "Carbonara") yang tidak selalu terbawa ke summary.
    Perbandingan empirisnya dicatat di docs/rag-guide.md.
    """
    return "\n".join(part for part in (title, summary) if part and part.strip())


def embed(texts: list[str]) -> list[list[float]] | None:
    """Embed beberapa teks dalam SATU panggilan API, urutan hasil = urutan input."""
    if not texts or any(not t.strip() for t in texts):
        return None

    try:
        response = get_client().models.embed_content(
            model=MODEL,
            # Tiap teks dibungkus Content sendiri. Kalau dikirim sebagai
            # list[str] polos, gemini-embedding-2 menganggapnya SATU konten
            # multi-bagian dan mengembalikan satu vektor gabungan -- bukan
            # satu vektor per teks. Ditemukan saat uji coba, tanpa error.
            contents=[types.Content(parts=[types.Part(text=t)]) for t in texts],
            config=types.EmbedContentConfig(output_dimensionality=DIMENSIONS),
        )
    except Exception as e:  # jaringan, timeout, quota, API error
        log.warning("embedding gagal untuk %d teks: %s", len(texts), e)
        return None

    vectors = [e.values for e in (response.embeddings or [])]
    if len(vectors) != len(texts) or any(len(v or []) != DIMENSIONS for v in vectors):
        log.warning("respons embedding tidak sesuai: %d vektor untuk %d teks", len(vectors), len(texts))
        return None
    return vectors


def embed_one(text: str) -> list[float] | None:
    vectors = embed([text])
    return vectors[0] if vectors else None
