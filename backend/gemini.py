"""
Satu client Gemini untuk seluruh backend (klasifikasi + embedding).

Dibuat lazy (baru dibuat saat pertama dipakai) supaya modul-modul yang
meng-import ini tetap bisa di-import tanpa GEMINI_API_KEY, mis. oleh Alembic.
"""

import os

from dotenv import load_dotenv
from google import genai
from google.genai import types

load_dotenv()

TIMEOUT_MS = 20_000

_client: genai.Client | None = None


def get_client() -> genai.Client:
    global _client
    if _client is None:
        _client = genai.Client(
            api_key=os.environ["GEMINI_API_KEY"],
            http_options=types.HttpOptions(
                timeout=TIMEOUT_MS,
                # 429 (rate limit) & 503 ("high demand") itu gangguan sementara
                # -- kejadian nyata waktu uji Fase 3. Dicoba ulang dengan jeda
                # makin panjang (2s, 4s) sebelum dianggap gagal.
                retry_options=types.HttpRetryOptions(
                    attempts=3,
                    initial_delay=2.0,
                    max_delay=10.0,
                    http_status_codes=[429, 500, 502, 503, 504],
                ),
            ),
        )
    return _client
