"""
Throwaway script — not part of the app. Confirms GEMINI_API_KEY works at all
before we build anything that depends on it (Phase 3/4).

Usage:
    venv/Scripts/python.exe check_gemini.py
"""

import os

from dotenv import load_dotenv
from google import genai

load_dotenv()

api_key = os.environ.get("GEMINI_API_KEY")
if not api_key:
    raise SystemExit("GEMINI_API_KEY is not set. Copy .env.example to .env and fill it in.")

client = genai.Client(api_key=api_key)

response = client.models.generate_content(
    model="gemini-3.6-flash",
    contents="Reply with exactly one word: pong",
)

print(response.text)
