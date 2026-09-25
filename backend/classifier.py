"""
Content classification via Gemini: extracted text -> title, summary, category.

Contract: `classify(...)` returns a Classification or None. It never raises --
Gemini down / timeout / odd response means the item is still saved, with the
extracted data only (see enrichment.py).
"""

import logging
from typing import Literal

from google.genai import types
from pydantic import BaseModel, Field, ValidationError

from gemini import get_client

log = logging.getLogger(__name__)

MODEL = "gemini-3.6-flash"

# A fixed list, not free text: categories the model makes up freely
# ("Cooking" vs "Food & Recipes") would split one topic into many labels and
# break browsing/filtering by category.
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
    title: str = Field(description="Short title, at most ~80 characters.")
    summary: str = Field(description="1-2 sentence summary in English.")
    category: Category


PROMPT = """You organise links someone has saved so they are easy to find again later.

From the content below, produce:
- title: a short title (max ~80 characters). If the content already has a
  clear title, use it (tidy it up if needed, keep its original language). If
  there is no title, write one from the content.
- summary: 1-2 sentences in English about what this content is.
- category: the single best-fitting category.

Important rules:
- Base everything ONLY on the information below. Do not invent details.
- If the information is thin (e.g. just hashtags), the summary may be short
  and general. Choose "Other" if the topic is genuinely unclear.
- Ignore promotional text, sponsor links, and calls to subscribe.

Platform: {platform}
URL: {url}

Content:
{content}
"""

def classify(url: str, platform: str, content: str) -> Classification | None:
    if not content.strip():
        # With no content, the model can only guess from the URL -> hallucination.
        return None

    try:
        response = get_client().models.generate_content(
            model=MODEL,
            contents=PROMPT.format(platform=platform, url=url, content=content),
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=Classification,
                temperature=0.2,  # consistent categorisation > creativity
                automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
            ),
        )
    except Exception as e:  # network, timeout, quota, API error
        log.warning("gemini failed for %s: %s", url, e)
        return None

    # The SDK fills .parsed when the JSON matches the schema. The raw text is
    # still validated again as a second safety net in case .parsed is empty.
    if isinstance(response.parsed, Classification):
        return response.parsed
    try:
        return Classification.model_validate_json(response.text or "")
    except ValidationError as e:
        log.warning("invalid gemini response for %s: %s | text=%r", url, e, response.text)
        return None
