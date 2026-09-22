"""
Klasifikasi konten via Gemini: teks hasil ekstraksi -> title, summary, category.

Kontrak: `classify(...)` mengembalikan Classification atau None. Tidak pernah
melempar — Gemini down / timeout / respons aneh berarti item tetap tersimpan
dengan data hasil ekstraksi saja (lihat enrichment.py).
"""

import logging
from typing import Literal

from google.genai import types
from pydantic import BaseModel, Field, ValidationError

from gemini import get_client

log = logging.getLogger(__name__)

MODEL = "gemini-3.6-flash"

# Daftar tetap, bukan teks bebas: kategori yang dikarang bebas oleh model
# ("Cooking" vs "Food & Recipes") akan memecah satu topik jadi banyak label
# dan merusak browse/filter per kategori nanti.
Category = Literal[
    "Tech & Coding",
    "Food & Cooking",
    "Fitness & Health",
    "Finance & Career",
    "Education & Learning",
    "Entertainment",
    "Music",
    "Travel",
    "Lifestyle & Fashion",
    "News & Opinion",
    "Other",
]


class Classification(BaseModel):
    title: str = Field(description="Judul singkat, maksimal ~80 karakter.")
    summary: str = Field(description="Ringkasan 1-2 kalimat dalam Bahasa Indonesia.")
    category: Category


PROMPT = """Kamu mengorganisir link yang disimpan seseorang supaya mudah dicari lagi nanti.

Dari konten di bawah, hasilkan:
- title: judul singkat (maks ~80 karakter). Kalau konten sudah punya judul
  yang jelas, pakai itu (boleh dirapikan, pertahankan bahasa aslinya). Kalau
  tidak ada judul, buat dari isi kontennya.
- summary: 1-2 kalimat dalam Bahasa Indonesia tentang isi konten ini.
- category: satu kategori yang paling cocok.

Aturan penting:
- Hanya berdasarkan informasi yang ADA di bawah. Jangan mengarang detail.
- Kalau informasinya tipis (misalnya cuma hashtag), ringkasan boleh pendek
  dan umum. Pilih "Other" kalau benar-benar tidak jelas topiknya.
- Abaikan teks promosi, link sponsor, dan ajakan subscribe.

Platform: {platform}
URL: {url}

Konten:
{content}
"""

def classify(url: str, platform: str, content: str) -> Classification | None:
    if not content.strip():
        # Tanpa isi, model cuma bisa menebak dari URL -> halusinasi.
        return None

    try:
        response = get_client().models.generate_content(
            model=MODEL,
            contents=PROMPT.format(platform=platform, url=url, content=content),
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=Classification,
                temperature=0.2,  # konsistensi pengkategorian > kreativitas
                automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
            ),
        )
    except Exception as e:  # jaringan, timeout, quota, API error
        log.warning("gemini gagal untuk %s: %s", url, e)
        return None

    # SDK mengisi .parsed kalau JSON-nya cocok dengan schema. Tetap divalidasi
    # ulang dari teks mentah sebagai jaring kedua kalau .parsed kosong.
    if isinstance(response.parsed, Classification):
        return response.parsed
    try:
        return Classification.model_validate_json(response.text or "")
    except ValidationError as e:
        log.warning("respons gemini tidak valid untuk %s: %s | teks=%r", url, e, response.text)
        return None
