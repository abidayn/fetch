"""
One Gemini client for the whole backend (classification + embeddings + answers).

Created lazily (only on first use) so modules importing this can still be
imported without GEMINI_API_KEY, e.g. by Alembic.
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
                # 429 (rate limit) and 503 ("high demand") are transient --
                # both actually happened during testing. Retried with growing
                # delays (2s, 4s) before being treated as a failure.
                retry_options=types.HttpRetryOptions(
                    attempts=3,
                    initial_delay=2.0,
                    max_delay=10.0,
                    http_status_codes=[429, 500, 502, 503, 504],
                ),
            ),
        )
    return _client
