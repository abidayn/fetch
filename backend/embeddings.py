"""
Embedding: text -> a vector of 768 numbers representing that text's "meaning".

Used on both sides of RAG, and both MUST use the same model + dimensions:
- save side  : enrichment.py embeds an item's title+summary (embedding_text)
- search side: POST /search embeds the user's search query
Vectors from different models can't be compared -- no error, the results are
just nonsense (see docs/data-model.md, "Embedding dimension").

Same contract as classifier.py: failure -> None, never raises. The caller
decides what that means (background: leave NULL, backfill later; search
request: reply 503).
"""

import logging

from google.genai import types

from gemini import get_client

log = logging.getLogger(__name__)

MODEL = "gemini-embedding-2"
DIMENSIONS = 768  # must match Vector(768) in models.py


def embedding_text(title: str | None, summary: str | None) -> str:
    """The text that represents one item in vector space.

    title + summary, not raw_content: raw_content (e.g. a YouTube description)
    is full of sponsor links and calls to subscribe that dilute the vector's
    meaning. The title stays in because it keeps proper names in their
    original language ("Despacito", "Carbonara") that don't always make it
    into the summary. The empirical comparison is in docs/decisions.md.
    """
    return "\n".join(part for part in (title, summary) if part and part.strip())


def embed(texts: list[str]) -> list[list[float]] | None:
    """Embed several texts in ONE API call; output order = input order."""
    if not texts or any(not t.strip() for t in texts):
        return None

    try:
        response = get_client().models.embed_content(
            model=MODEL,
            # Each text is wrapped in its own Content. Sent as a plain
            # list[str], gemini-embedding-2 treats it as ONE multi-part
            # content and returns a single combined vector -- not one vector
            # per text. Found during testing; it raises no error.
            contents=[types.Content(parts=[types.Part(text=t)]) for t in texts],
            config=types.EmbedContentConfig(output_dimensionality=DIMENSIONS),
        )
    except Exception as e:  # network, timeout, quota, API error
        log.warning("embedding failed for %d texts: %s", len(texts), e)
        return None

    vectors = [e.values for e in (response.embeddings or [])]
    if len(vectors) != len(texts) or any(len(v or []) != DIMENSIONS for v in vectors):
        log.warning("unexpected embedding response: %d vectors for %d texts", len(vectors), len(texts))
        return None
    return vectors


def embed_one(text: str) -> list[float] | None:
    vectors = embed([text])
    return vectors[0] if vectors else None
