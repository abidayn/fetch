"""
Content classification: extracted text -> title, summary, category.

Runs through the fallback chain in llm.py (primary Gemini -> second Gemini ->
Groq). Contract: `classify(...)` returns a Result (the Classification plus
which model produced it) or None. It never raises -- all models failing means
the item is still saved, with the extracted data only (see enrichment.py).
"""

import logging
from typing import Literal

from pydantic import BaseModel, Field

import llm

log = logging.getLogger(__name__)

# Ordered fallback chain, overridable with the CLASSIFY_MODELS env var. Every
# model here must be able to follow the Classification schema. The first entry
# is the PRIMARY: items classified by any other model are re-done by it later
# (enrichment.upgrade_fallback_items), since raw_content is kept.
CHAIN = llm.chain_from_env(
    "CLASSIFY_MODELS",
    "gemini:gemini-3.6-flash,gemini:gemini-3.5-flash-lite,groq:openai/gpt-oss-120b",
)
PRIMARY = CHAIN[0]
# Background work, nobody waits: a generous budget for the whole chain.
BUDGET_S = 60.0

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

def classify(
    url: str, platform: str, content: str, chain: list[llm.ModelRef] | None = None
) -> "llm.Result[Classification] | None":
    """`chain` overrides the default chain, e.g. [PRIMARY] to upgrade an item
    that a fallback model classified."""
    if not content.strip():
        # With no content, the model can only guess from the URL -> hallucination.
        return None

    result = llm.generate_json(
        "classify",
        PROMPT.format(platform=platform, url=url, content=content),
        Classification,  # validated for every model: a category outside the list = failure
        chain or CHAIN,
        budget_s=BUDGET_S,
        temperature=0.2,  # consistent categorisation > creativity
    )
    if result is None:
        log.warning("classification failed for %s (all models)", url)
    return result
