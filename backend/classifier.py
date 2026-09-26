"""
Content classification: extracted text -> title, summary, category.

Runs through the fallback chain in llm.py (primary Gemini -> second Gemini ->
Groq). Contract: `classify(...)` returns a Result (the Classification plus
which model produced it) or None. It never raises -- all models failing means
the item is still saved, with the extracted data only (see enrichment.py).
"""

import json
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
    # A plain required string, not Optional and not a Literal of the user's
    # folder names: Groq's strict JSON mode wants every property required, and
    # a folder name that matches nothing must not fail the whole
    # classification (title/summary are the valuable part). folders.py
    # matches it to the user's folders case-insensitively, or creates it.
    folder: str = Field(description="Existing folder name, or a new 1-3 word folder name.")


PROMPT = """You organise links someone has saved so they are easy to find again later.

From the content below, produce:
- title: a short title (max ~80 characters). If the content already has a
  clear title, use it (tidy it up if needed, keep its original language). If
  there is no title, write one from the content.
- summary: 1-2 sentences in English about what this content is.
- category: the single best-fitting category.
- folder: the folder this link belongs in. {folder_rule}

Important rules:
- Base everything ONLY on the information below. Do not invent details.
- If the information is thin (e.g. just hashtags), the summary may be short
  and general. Choose "Other" if the topic is genuinely unclear.
- Ignore promotional text, sponsor links, and calls to subscribe.
{folder_list}
Platform: {platform}
URL: {url}

Content:
{content}
"""

NEW_FOLDER_RULE = (
    "A new folder name: 1-3 words, in English, Title Case, general enough to also hold "
    'similar links later (e.g. "Recipes", not "Lemon Garlic Pasta").'
)
EXISTING_FOLDER_RULE = (
    "If one of the user's folders listed below fits well, return its name exactly as "
    "listed. Only if none of them fits, propose a new folder name instead: 1-3 words, "
    'in English, Title Case, general enough to also hold similar links later (e.g. '
    '"Recipes", not "Lemon Garlic Pasta").'
)


def folder_prompt_parts(folders: list[str]) -> dict[str, str]:
    """The folder part of the prompt. The names are the user's own text, so
    each is JSON-quoted: that delimits it clearly, and a name can't break out
    of the list (e.g. one containing a newline and fake instructions)."""
    if not folders:
        return {"folder_rule": NEW_FOLDER_RULE, "folder_list": ""}
    listed = "\n".join(f"- {json.dumps(name, ensure_ascii=False)}" for name in folders)
    return {"folder_rule": EXISTING_FOLDER_RULE, "folder_list": f"\nThe user's folders:\n{listed}\n"}


def classify(
    url: str,
    platform: str,
    content: str,
    folders: list[str] | None = None,
    chain: list[llm.ModelRef] | None = None,
) -> "llm.Result[Classification] | None":
    """`folders` = the user's folder names, so the model can pick one (or
    propose a new one; see folders.apply_ai_folder). `chain` overrides the
    default chain, e.g. [PRIMARY] to upgrade an item that a fallback model
    classified."""
    if not content.strip():
        # With no content, the model can only guess from the URL -> hallucination.
        return None

    result = llm.generate_json(
        "classify",
        PROMPT.format(
            platform=platform, url=url, content=content, **folder_prompt_parts(folders or [])
        ),
        Classification,  # validated for every model: a category outside the list = failure
        chain or CHAIN,
        budget_s=BUDGET_S,
        temperature=0.2,  # consistent categorisation > creativity
    )
    if result is None:
        log.warning("classification failed for %s (all models)", url)
    return result
